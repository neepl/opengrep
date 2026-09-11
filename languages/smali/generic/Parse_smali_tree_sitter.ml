(* Translate the smali CST produced by tree-sitter into AST_generic.
 *
 * Smali is register-based three-address code, which is close to the engine's
 * own IL. The job here is to lower it into the AST_generic shapes the
 * existing analyses already understand -- assignments, calls, literals and
 * real control flow -- so that constant propagation, CFG construction and
 * taint work without any engine change.
 *
 * Naming: class and type references are normalised from their descriptor
 * form to a dotted name (`Lcom/foo/Bar;` -> `com.foo.Bar`). Patterns go
 * through this same function, so `L$CLS;` normalises to `$CLS`, which is
 * what makes a metavariable in class position work.
 *)
open Fpath_.Operators
module CST = Tree_sitter_smali.CST
module H = Parse_tree_sitter_helpers
module G = AST_generic

(* Per-method context.
   - [switch_targets] maps a payload label (`:pswitch_data_0`) to the case
     targets declared under it, so a `packed-switch`/`sparse-switch`
     instruction can be lowered to a real Switch even though its payload is
     a separate directive further down the method.
   - [param_map] maps parameter registers onto their local numbering, so
     `p0` and the `v` register it aliases are one variable (task 4.3). *)
type ctx = {
  switch_targets : (string, (string * Tok.t) list) Hashtbl.t;
  mutable param_map : (string * string) list;
  (* start label -> (end label, handler label, exception type) for each
     `.catch`/`.catchall`, so a guarded range can be rebuilt as a Try *)
  mutable catch_ranges : (string * (string * (string * Tok.t) * string)) list;
  (* byte position of a `const` opcode -> descriptor of the parameter
     position that definition reaches. Keyed per *definition*, not per
     register: Dalvik reuses registers constantly, and 35% of registers in
     a real APK feed parameter positions with disagreeing descriptors
     purely because they were reassigned in between. A per-register map
     therefore either mis-types or, being conservative, gives up on a third
     of the cases. *)
  zero_types : (int, string) Hashtbl.t;
  (* enclosing class, and the local that `this` occupies in the method being
     lowered (None in a static method). A bytecode invoke always names its
     declaring class, so `Class.m()` is how *every* static call looks and
     `this.m()` is how an instance call to a sibling method looks. Typing the
     receiver lets the call graph resolve the latter -- see
     Callee_resolution.identify_callee, which reads the receiver's id_type. *)
  mutable current_class : (string * Tok.t) option;
  mutable super_class : string option;
  mutable this_local : string option;
  (* line -> [(register, verifier type)] from baksmali --register-info.
     dexlib2 runs the same dataflow the runtime verifier does and prints the
     type of every register at every program point, which is strictly better
     than anything inferred from the instruction stream alone: it is correct
     across branches and merges, and it survives the register reuse that
     makes a register's own name meaningless as a type key. Reading it is
     preferred over re-deriving it. *)
  reg_types : (int, (string * string) list) Hashtbl.t;
}

type env = ctx H.env

let new_ctx () =
  {
    switch_targets = Hashtbl.create 8;
    param_map = [];
    catch_ranges = [];
    zero_types = Hashtbl.create 8;
    current_class = None;
    super_class = None;
    this_local = None;
    reg_types = Hashtbl.create 64;
  }

let token = H.token
let str = H.str
let fb = Tok.unsafe_fake_bracket
let sc tok = tok

(*****************************************************************************)
(* Names *)
(*****************************************************************************)

(* `Lcom/foo/Bar;` is emitted by the grammar as the token `L`, a
 * `/`-separated list of segments, and `;`. Join the segments with '.' so a
 * reference reads as a normal qualified name. A metavariable written as
 * `L$CLS;` is a single segment and comes out as `$CLS`, which the matcher
 * then treats as a metavariable. *)
let class_identifier (env : env) ((_l, first, rest, _semi) : CST.class_identifier)
    : string * Tok.t =
  let s0, t0 = str env first in
  let parts = s0 :: List_.map (fun (_slash, seg) -> fst (str env seg)) rest in
  (String.concat "." parts, t0)

let rec type_ (env : env) (x : CST.type_) : string * Tok.t =
  match x with
  | `Prim_type p -> (
      (* V Z B S C I J F D -- kept as their descriptor letter, since the
       * pattern side is written in the same notation *)
      match p with
      | `Tok_choice_v t -> str env t
      | `Tok_prec_p1_choice_v t -> str env t)
  | `Class_id c -> class_identifier env c
  | `Array_type (lb, t) ->
      let s, _ = type_ env t in
      (s ^ "[]", token env lb)

let name_of (s, t) : G.name = G.Id ((s, t), G.empty_id_info ())
let id_expr (s, t) : G.expr = G.N (name_of (s, t)) |> G.e
let ty_of (s, t) : G.type_ = G.TyN (name_of (s, t)) |> G.t

(* `Lcom/foo/Bar;` -> `com.foo.Bar`, matching how class references are
   normalised everywhere else. *)
let rec descriptor_to_dotted (d : string) : string =
  let n = String.length d in
  if n > 2 && d.[0] = 'L' && d.[n - 1] = ';' then
    String.map (function '/' -> '.' | c -> c) (String.sub d 1 (n - 2))
  else if n > 1 && d.[0] = '[' then
    (* An array must come out the way [type_] renders one, `B[]` rather than
       `[B`, or a register's recorded type never agrees with the type a
       pattern writes for it. *)
    descriptor_to_dotted (String.sub d 1 (n - 1)) ^ "[]"
  else d

(* Parse the register-type comments baksmali emits with --register-info.
   They precede the instruction they describe:

     #v0=(Reference,Landroid/webkit/WebSettings;);v1=(One);
     invoke-virtual {v0, v1}, ...->setJavaScriptEnabled(Z)V

   Comments are tree-sitter `extras` and so never reach the CST; reading the
   file directly is the cheapest way to recover them, keyed by the line of
   the instruction they annotate. *)
let load_register_info (file : Fpath.t) : (int, (string * string) list) Hashtbl.t =
  let tbl = Hashtbl.create 64 in
  (try
     let ic = open_in (Fpath.to_string file) in
     let pending = ref [] in
     let lineno = ref 0 in
     (try
        while true do
          let line = input_line ic in
          incr lineno;
          let t = String.trim line in
          if String.length t > 1 && t.[0] = '#' && String.contains t '=' then (
            (* Scan for `reg=(type)` groups. Splitting on ';' would be wrong:
               a class descriptor ends in ';', so `Reference,Lcom/foo/Bar;`
               contains one. A type never contains ')', so the parenthesis
               is the reliable delimiter. *)
            let n = String.length t in
            let i = ref 1 in
            while !i < n do
              match String.index_from_opt t !i '=' with
              | None -> i := n
              | Some eq ->
                  if eq + 1 < n && t.[eq + 1] = '(' then (
                    match String.index_from_opt t (eq + 1) ')' with
                    | None -> i := n
                    | Some cl ->
                        (* the register name runs back to the previous
                           delimiter *)
                        let start =
                          let j = ref (eq - 1) in
                          while
                            !j >= 1
                            && (match t.[!j] with
                                | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
                                | _ -> false)
                          do
                            decr j
                          done;
                          !j + 1
                        in
                        let reg = String.sub t start (eq - start) in
                        let ty = String.sub t (eq + 2) (cl - eq - 2) in
                        if reg <> "" && ty <> "" then
                          pending := (reg, ty) :: !pending;
                        i := cl + 1)
                  else i := eq + 1
            done)
          else if t <> "" then (
            if !pending <> [] then Hashtbl.replace tbl !lineno (List.rev !pending);
            pending := [])
        done
      with End_of_file -> ());
     close_in ic
   with Sys_error _ -> ());
  tbl

(* The verifier's type for a register at a given line, if it recorded one. *)
let verifier_type (env : ctx H.env) (reg : string) (t : Tok.t) : string option =
  match Hashtbl.find_opt env.H.extra.reg_types (Tok.line_of_tok t) with
  | None -> None
  | Some entries -> List.assoc_opt reg entries

(*****************************************************************************)
(* Operands *)
(*****************************************************************************)

(* Registers are ordinary method-local variables. `v0` and `p0` are distinct
 * names; normalising p-registers onto their v-numbering needs the method's
 * `.registers` count and its argument count, which is task 4.3. *)
(* `this` is just a register, so nothing in the instruction stream says what
   type it holds. Name it explicitly: it is the only register whose type is
   known without any inference, and the call graph needs it to resolve an
   instance call to a sibling method. *)
let reg_expr ?raw (env : env) (s, t) : G.expr =
  (* The verifier's own type, where it recorded one, in preference to
     anything we could infer. It is the only source that is correct across
     branches and unaffected by register reuse. `raw` is the register as
     written (`p0`), which is what the comments name, before the p-to-v
     normalisation. *)
  let from_verifier =
    match verifier_type env (Option.value raw ~default:s) t with
    | Some ty when String.length ty > 10 && String.sub ty 0 10 = "Reference," ->
        Some (descriptor_to_dotted (String.sub ty 10 (String.length ty - 10)))
    | _ -> None
  in
  let declared =
    match (env.H.extra.this_local, env.H.extra.current_class) with
    | Some this_s, Some (cls, _) when String.equal s this_s -> Some cls
    | _ -> None
  in
  match (from_verifier, declared) with
  | None, None -> id_expr (s, t)
  | v, d ->
      let id_info = G.empty_id_info () in
      (* `this` is known exactly; otherwise take what the verifier says. *)
      let chosen = match d with Some c -> c | None -> Option.get v in
      id_info.G.id_type := Some (ty_of (chosen, t));
      G.N (G.Id ((s, t), id_info)) |> G.e

(* Every register from `a` to `b` inclusive. Falls back to the two endpoints
   if either is not a plain numbered register, which is the only shape the
   range syntax actually permits but is worth not crashing on. *)
let expand_register_range (env : env) (a : G.expr) (b : G.expr) : G.expr list =
  let name_tok e =
    match e.G.e with G.N (G.Id ((n, t), _)) -> Some (n, t) | _ -> None
  in
  let split n =
    if String.length n < 2 then None
    else
      match int_of_string_opt (String.sub n 1 (String.length n - 1)) with
      | Some i -> Some (n.[0], i)
      | None -> None
  in
  match (name_tok a, name_tok b) with
  | Some (na, ta), Some (nb, _) -> (
      match (split na, split nb) with
      | Some (pa, ia), Some (pb, ib) when Char.equal pa pb && ia <= ib ->
          List.init (ib - ia + 1) (fun k ->
              let raw = Printf.sprintf "%c%d" pa (ia + k) in
              let mapped =
                try List.assoc raw env.H.extra.param_map with Not_found -> raw
              in
              reg_expr ~raw env (mapped, ta))
      | _ -> [ a; b ])
  | _ -> [ a; b ]

let register (env : env) (x : CST.register) : G.expr =
  match x with
  | `Choice_var (`Var v) -> reg_expr env (str env v)
  | `Choice_var (`Param p) ->
      (* A parameter register aliases a numbered local; use the local name so
         `p0` and `v3` in the same method are one variable. The verifier
         comments still name it `p0`, so pass the original through. *)
      let s0, t = str env p in
      let s = try List.assoc s0 env.H.extra.param_map with Not_found -> s0 in
      reg_expr ~raw:s0 env (s, t)
  | `Semg_meta m -> id_expr (str env m)

let literal (env : env) (x : CST.literal) : G.expr =
  match x with
  | `Num n ->
      let s, t = str env n in
      G.L (G.Int (Parsed_int.parse (s, t))) |> G.e
  | `Float f ->
      let s, t = str env f in
      G.L (G.Float (float_of_string_opt s, t)) |> G.e
  | `Nan n -> G.L (G.Float (None, snd (str env n))) |> G.e
  | `Infi i -> G.L (G.Float (None, snd (str env i))) |> G.e
  | `Str (l, frags, r) ->
      let parts =
        List_.map
          (fun f ->
            match f with
            | `Str_frag x -> fst (str env x)
            | `Esc_seq (`Imm_tok_bslash_pat_36cdeeb x) -> fst (str env x)
            | `Esc_seq (`Esc_seq_ x) -> fst (str env x))
          frags
      in
      let s = String.concat "" parts in
      G.L (G.String (token env l, (s, token env l), token env r)) |> G.e
  | `Bool b -> (
      match b with
      | `True t -> G.L (G.Bool (true, token env t)) |> G.e
      | `False t -> G.L (G.Bool (false, token env t)) |> G.e)
  | `Char (l, _, _r) -> G.L (G.Char (("", token env l))) |> G.e
  | `Null t -> G.L (G.Null (token env t)) |> G.e

(* A method reference `Lcom/Foo;->bar(I)V`. The parameter descriptor is not
 * currently part of the lowered callee, so a pattern naming one overload
 * matches every overload of that name on that class. See the note in the
 * change's task 4.6. *)
let method_signature (env : env) ((nm, _body) : CST.method_signature) :
    string * Tok.t =
  match nm with
  | `Opt_DASH_id (_dash, id) -> str env id
  | `Num n -> str env n

let full_method_signature (env : env) ((cls, arrow, msig) : CST.full_method_signature)
    : G.expr =
  let cls_name =
    match cls with
    | `Class_id c -> class_identifier env c
    | `Array_type (lb, t) ->
        let s, _ = type_ env t in
        (s ^ "[]", token env lb)
  in
  let m = method_signature env msig in
  G.DotAccess (id_expr cls_name, token env arrow, G.FN (name_of m)) |> G.e

(* The text of an access-modifier keyword. Needed before [access_modifier]
   itself because a field may be *named* after one. *)
let access_modifier_str (env : env) (x : CST.access_modifier) : string * Tok.t =
  match x with
  | `Public t | `Priv t | `Prot t | `Static t | `Final t | `Sync t
  | `Vola t | `Bridge t | `Tran t | `Varargs t | `Native t | `Inte t
  | `Abst t | `Stri t | `Synt t | `Anno t | `Enum t | `Decl t | `Whit t
  | `Grey_a7e06de t | `Blac t | `Grey_9c01c67 t | `Grey_cf1de84 t
  | `Grey_1cbf3dc t | `Grey_7d723aa t | `Core t | `Test t ->
      str env t

(* A field name. Ordinarily an identifier or a number, but `public`,
   `annotation` and the other access flags are extracted keywords, so a field
   that happens to carry one of those names arrives on its own branch. *)
let field_name (env : env) (x : CST.field_body) : string * Tok.t =
  match x with
  | `Choice_id_COLON_type (n, _colon, _ty) -> (
      match n with `Id x -> str env x | `Num x -> str env x)
  | `Access_modi_COLON_type (m, _colon, _ty) -> access_modifier_str env m

(* The declared type of a field, whichever spelling its name took. *)
let field_type (env : env) (x : CST.field_body) : string * Tok.t =
  match x with
  | `Choice_id_COLON_type (_, _, ty)
  | `Access_modi_COLON_type (_, _, ty) ->
      type_ env ty

(* A field reference `Lcom/Foo;->NAME:Ljava/lang/String;`. *)
let full_field_body (env : env) ((cls, arrow, fb_) : CST.full_field_body) : G.expr =
  let cls_name =
    match cls with
    | `Class_id c -> class_identifier env c
    | `Array_type (lb, t) ->
        let s, _ = type_ env t in
        (s ^ "[]", token env lb)
  in
  let fid = field_name env fb_ in
  G.DotAccess (id_expr cls_name, token env arrow, G.FN (name_of fid)) |> G.e

let body (env : env) (x : CST.body) : G.expr =
  match x with
  | `Full_meth_sign f -> full_method_signature env f
  | `Full_field_body f -> full_field_body env f
  (* a bare field or method reference, i.e. one without its declaring
     class, as produced by an implicit reference *)
  | `Field_body fb_ -> id_expr (field_name env fb_)
  | `Meth_sign m -> id_expr (method_signature env m)
  | `Meth_sign_body b ->
      let lp = match b with
        | `LPAR_rep_type_RPAR_type (lp, _, _, _) -> lp
        | `LPAR_ellips_RPAR_type (lp, _, _, _) -> lp
      in
      G.Ellipsis (token env lp) |> G.e

let rec value (env : env) (x : CST.value) : G.expr =
  match x with
  | `Ellips t -> G.Ellipsis (token env t) |> G.e
  | `Deep_ellips (l, v, r) ->
      G.DeepEllipsis (token env l, value env v, token env r) |> G.e
  | `Choice_type v -> (
      match v with
      | `Type t -> id_expr (type_ env t)
      | `List (l, vs, r) ->
          let xs =
            match vs with
            | None -> []
            | Some (v0, rest) ->
                value env v0 :: List_.map (fun (_c, v) -> value env v) rest
          in
          G.Container (G.Tuple, (token env l, xs, token env r)) |> G.e
      | `Label lb -> id_expr (str env lb)
      | `Jmp_label lb -> id_expr (str env lb)
      | `Range (l, r_, r) ->
          let xs =
            match r_ with
            | `Regi_DOTDOT_regi (a, _dd, b) ->
                (* `{v5 .. v11}` names seven registers, not two. The /range
                   invoke forms use it whenever a call has more arguments than
                   the short form can encode, so keeping only the endpoints
                   loses every argument in between -- and with it any taint
                   flowing through one. *)
                expand_register_range env (register env a) (register env b)
            | `Num_DOTDOT_num (a, _dd, b) ->
                [ id_expr (str env a); id_expr (str env b) ]
            | `Jmp_label_DOTDOT_jmp_label (a, _dd, b) ->
                [ id_expr (str env a); id_expr (str env b) ]
          in
          G.Container (G.Tuple, (token env l, xs, token env r)) |> G.e
      | `Regi r -> register env r
      | `Body b -> body env b
      | `Lit l -> literal env l
      | `Enum_ref (_e, f) -> (
          match f with
          | `Full_field_body fb_ -> full_field_body env fb_
          | `Field_body fb_ -> id_expr (field_name env fb_))
      | `Suba_dire (t, _, _, _) -> G.Ellipsis (token env t) |> G.e
      | `Meth_handle (_op, _at, b) -> (
          match b with
          | `Full_field_body fb_ -> full_field_body env fb_
          | `Full_meth_sign m -> full_method_signature env m)
      (* invoke-custom call site: keep the bootstrap target as the callee so
         a rule can name it, e.g. StringConcatFactory for compiled string
         concatenation *)
      | `Custom_invoke (_id, _lp, _args, _rp, _at, cls, arrow, msig) ->
          G.DotAccess
            ( id_expr (class_identifier env cls),
              token env arrow,
              G.FN (name_of (method_signature env msig)) )
          |> G.e)

(*****************************************************************************)
(* Instructions *)
(*****************************************************************************)

(* Opcode families. `opcode` is a single token (the semgrep grammar wraps
 * upstream's 263-way choice in token()), so dispatch is on its text. *)
let family (op : string) : string =
  match String.index_opt op '/' with
  | Some i -> String.sub op 0 i
  | None -> op

let is_invoke op = String.length op >= 6 && String.sub op 0 6 = "invoke"
let is_const op = String.length op >= 5 && String.sub op 0 5 = "const"

let is_move_result op =
  String.length op >= 11 && String.sub op 0 11 = "move-result"

(* `const/4 v0, 0x0` is null, false or integer zero depending on how the
   value is used -- the bytecode does not say which. Rules are written in
   source-level terms, so the literal is typed from the descriptor of the
   parameter it is eventually passed to.

   Conservative by design: a register is retyped only when it is passed to
   exactly one invoke operand position within the method, so an ambiguous
   or reused register keeps its integer reading rather than risking a
   false negative. Task 4.15 records whether the disassembler's own
   register-type output should supersede this. *)
let is_reference_descriptor (t : string) : bool =
  (* a single descriptor letter is a primitive; anything else is a class,
     an array, or a normalised dotted class name *)
  String.length t <> 1 || not (String.contains "VZBSCIJFD" t.[0])

(* An instruction lowers to one expression. `invoke-*` becomes a Call whose
 * callee is the referenced method; for the instance forms the first operand
 * is the receiver and is attached to the callee, mirroring how a Java call
 * is shaped, so that receiver-vs-static patterns distinguish correctly.
 *
 * That shape has one slot for what bytecode gives two, so an instance
 * invoke's declaring class is not represented and patterns compare the
 * method name alone. The class is not lost: it is recovered from the
 * pattern text as a prefilter condition (Analyze_rule.smali_class_idents),
 * which restricts a rule to files that actually reference the class.
 *
 * `<init>` is the exception, and has to be. A constructor pattern that
 * compared only the name would match every `invoke-direct` in the APK, four
 * orders of magnitude of noise, so `new-instance` + `invoke-direct <init>`
 * is folded into the `New` node Java produces, which does carry the type.
 * A typed receiver was tried instead and does not work: Naming_AST re-derives
 * a register's type from its definition, and a receiver is routinely a
 * subclass of the class the invoke declares. *)
let expression (env : env) ((op, args, _nl) : CST.expression) : G.expr =
  let opstr, optok = str env op in
  let vals =
    match args with
    | None -> []
    | Some (v0, rest) -> value env v0 :: List_.map (fun (_c, v) -> value env v) rest
  in
  let call_of callee operands =
    G.Call (callee, fb (List_.map (fun e -> G.Arg e) operands)) |> G.e
  in
  (* the register list of an invoke is a Tuple built by `value` *)
  let unpack_list e =
    match e.G.e with
    | G.Container (G.Tuple, (_, xs, _)) ->
        (* A range inside the operand list is itself a tuple; flatten one
           level so the invoke sees individual arguments. *)
        Some
          (List.concat_map
             (fun x ->
               match x.G.e with
               | G.Container (G.Tuple, (_, inner, _)) -> inner
               | _ -> [ x ])
             xs)
    | _ -> None
  in
  match vals with
  | _ when is_invoke opstr -> (
      match vals with
      | [ regs; callee ] -> (
          let operands = Option.value (unpack_list regs) ~default:[ regs ] in
          let is_static = opstr = "invoke-static" || opstr = "invoke-static/range" in
          match (callee.G.e, operands, is_static) with
          (* instance forms: first operand is the receiver *)
          | G.DotAccess (cls, dot, fld), recv :: rest, false -> (
              let cls_name =
                match cls.G.e with G.N (G.Id (id, _)) -> Some id | _ -> None
              in
              let is_ctor =
                match fld with
                | G.FN (G.Id (("<init>", _), _)) -> true
                | _ -> false
              in
              (* Every constructor begins by invoking its own or its
                 superclass's constructor on `this`. That is not an object
                 creation, and rewriting it as one would retype `this` for
                 the rest of the method. The declaring class has to be part
                 of the test: `p0` is only `this` until the method overwrites
                 it, and real code does reuse it as a scratch register. *)
              let on_this =
                let recv_is_this =
                  match (recv.G.e, env.H.extra.this_local) with
                  | G.N (G.Id ((s, _), _)), Some tl -> String.equal s tl
                  | _ -> false
                in
                let declares_enclosing =
                  match cls_name with
                  | None -> false
                  | Some (c, _) ->
                      let same = function
                        | Some x -> String.equal c x
                        | None -> false
                      in
                      same (Option.map fst env.H.extra.current_class)
                      || same env.H.extra.super_class
                in
                recv_is_this && declares_enclosing
              in
              match (is_ctor, on_this, cls_name) with
              | true, false, Some id ->
                  G.Assign
                    ( recv,
                      optok,
                      G.New
                        ( optok,
                          G.TyN (G.Id (id, G.empty_id_info ())) |> G.t,
                          G.empty_id_info (),
                          fb (List_.map (fun e -> G.Arg e) rest) )
                      |> G.e )
                  |> G.e
              | _ ->
                  call_of (G.DotAccess (recv, dot, fld) |> G.e) rest)
          | _ -> call_of callee operands)
      | _ -> G.OtherExpr ((opstr, optok), List_.map (fun e -> G.E e) vals) |> G.e)
  | [ dst; src ] when is_const opstr ->
      (* Retype an ambiguous zero from the descriptor of the parameter the
         register feeds (task 4.13). *)
      let src =
        match (dst.G.e, src.G.e) with
        | G.N (G.Id (_, _)), G.L (G.Int (Some n, ztok)) when n = 0L || n = 1L -> (
            match
              ( Hashtbl.find_opt env.H.extra.zero_types
                  (Tok.bytepos_of_tok optok),
                n )
            with
            | Some ty, 0L when is_reference_descriptor ty -> G.L (G.Null ztok) |> G.e
            (* There is no boolean in Dalvik: `Z` is an int that is 0 or 1, and
               the parameter descriptor is the only thing that says which it
               means. Typing 0 alone was half the job -- `setX(true)` is at
               least as common in Android rules as `setX(false)`. *)
            | Some "Z", 0L -> G.L (G.Bool (false, ztok)) |> G.e
            | Some "Z", 1L -> G.L (G.Bool (true, ztok)) |> G.e
            | _ -> src)
        | _ -> src
      in
      G.Assign (dst, optok, src) |> G.e
  | [ dst; src ] when family opstr = "move" || family opstr = "move-object"
                      || family opstr = "move-wide" ->
      G.Assign (dst, optok, src) |> G.e
  | [ dst; fld ] when family opstr = "sget" || family opstr = "iget" ->
      G.Assign (dst, optok, fld) |> G.e
  | [ src; fld ] when family opstr = "sput" || family opstr = "iput" ->
      G.Assign (fld, optok, src) |> G.e
  | [ dst; recv; fld ] when family opstr = "iget" ->
      G.Assign (dst, optok, G.DotAccess (recv, optok, G.FDynamic fld) |> G.e) |> G.e
  | [ dst; ty ] when opstr = "new-instance" ->
      let tyname =
        match ty.G.e with
        | G.N (G.Id (id, _)) -> G.TyN (G.Id (id, G.empty_id_info ())) |> G.t
        | _ -> G.TyN (name_of ("?", optok)) |> G.t
      in
      G.Assign (dst, optok, G.New (optok, tyname, G.empty_id_info (), fb []) |> G.e)
      |> G.e
  | _ -> G.OtherExpr ((opstr, optok), List_.map (fun e -> G.E e) vals) |> G.e


(*****************************************************************************)
(* Control flow *)
(*****************************************************************************)

(* Labels and jump targets are the same thing to us; the grammar spells a
   definition `:foo` and a reference `foo:` differently, and both carry the
   punctuation in their token text. Strip it so a `goto :foo` resolves to
   the `:foo` that defines it -- CFG_build matches labels by name. *)
let normalize_label (s : string) : string =
  let s = if String.length s > 0 && s.[0] = ':' then String.sub s 1 (String.length s - 1) else s in
  let n = String.length s in
  if n > 0 && s.[n - 1] = ':' then String.sub s 0 (n - 1) else s

let label_of_value (env : env) (v : CST.value) : (string * Tok.t) option =
  match v with
  | `Choice_type (`Label l) ->
      let s, t = str env l in
      Some (normalize_label s, t)
  | `Choice_type (`Jmp_label l) ->
      let s, t = str env l in
      Some (normalize_label s, t)
  | _ -> None

let catch_range (env : env)
    (r : CST.anon_choice_LCURL_label_DOTDOT_label_RCURL_label_ddeb82c) :
    string * string * (string * Tok.t) =
  match r with
  | `LCURL_label_DOTDOT_label_RCURL_label (_, a, _, b, _, h)
  | `LCURL_jmp_label_DOTDOT_jmp_label_RCURL_jmp_label (_, a, _, b, _, h) ->
      let sa, _ = str env a in
      let sb, _ = str env b in
      let sh, th = str env h in
      (normalize_label sa, normalize_label sb, (normalize_label sh, th))

let is_goto op = op = "goto" || op = "goto/16" || op = "goto/32"
let is_if op = String.length op >= 3 && String.sub op 0 3 = "if-"
let is_return op = String.length op >= 6 && String.sub op 0 6 = "return"
let is_throw op = op = "throw"
let is_switch op = op = "packed-switch" || op = "sparse-switch"

(* `if-eqz vA, :L` is "if vA == 0 goto L"; `if-ge vA, vB, :L` is
   "if vA >= vB goto L". The comparison operator is recovered from the
   mnemonic so the condition is a real expression rather than opaque. *)
let cmp_operator (op : string) : G.operator option =
  let base = match String.index_opt op '/' with
    | Some i -> String.sub op 0 i
    | None -> op
  in
  match base with
  | "if-eq" | "if-eqz" -> Some G.Eq
  | "if-ne" | "if-nez" -> Some G.NotEq
  | "if-lt" | "if-ltz" -> Some G.Lt
  | "if-ge" | "if-gez" -> Some G.GtE
  | "if-gt" | "if-gtz" -> Some G.Gt
  | "if-le" | "if-lez" -> Some G.LtE
  | _ -> None

(*****************************************************************************)
(* Statements *)
(*****************************************************************************)

(* Debug-only directives are dropped from the statement sequence so that an
 * exact-instruction-sequence pattern still matches a body that carries them
 * (task 4.8). `.line` is consumed for position information only. *)
let directive (_env : env) (x : CST.directive) : G.stmt option =
  match x with
  (* Debug-only: dropped so an exact-instruction-sequence pattern still
     matches a body carrying them (task 4.8). *)
  | `Line_dire _ | `Locals_dire _ | `Regiss_dire _ | `Local_dire _
  | `End_local_dire _ | `Rest_local_dire _ | `Prol_dire _ | `Epil_dire _
  | `Param_dire_c83bfa2 _ | `Param_dire_19f22ef _ | `Source_dire _ ->
      None
  (* Structural, but not yet reconstructed: guarded ranges become try/catch
     in task 4.12 and switch payloads in task 4.11. *)
  | `Catch_dire _ | `Catc_dire _ | `Packed_switch_dire _
  | `Sparse_switch_dire _ | `Array_data_dire _ ->
      None

let statement (env : env) (x : CST.statement) : G.stmt option =
  match x with
  | `Ellips t -> Some (G.ExprStmt (G.Ellipsis (token env t) |> G.e, sc (token env t)) |> G.s)
  | `Choice_label s -> (
      match s with
      (* Both forms must be normalised the same way as a jump target, or
         the label a `goto` names never matches the label that defines it
         and CFG_build silently produces no edge. *)
      | `Label lb ->
          let s, t = str env lb in
          Some (G.Label ((normalize_label s, t), G.Block (fb []) |> G.s) |> G.s)
      | `Jmp_label lb ->
          let s, t = str env lb in
          Some (G.Label ((normalize_label s, t), G.Block (fb []) |> G.s) |> G.s)
      | `Dire d -> directive env d
      | `Anno_dire (t, _, _, _, _) ->
          Some (G.OtherStmt (G.OS_Todo, [ G.Tk (token env t) ]) |> G.s)
      | `Exp ((op, args, _nl) as e) -> (
          let opstr, optok = str env op in
          let cst_vals =
            match args with
            | None -> []
            | Some (v0, rest) -> v0 :: List_.map (fun (_c, v) -> v) rest
          in
          let labels = List_.filter_map (label_of_value env) cst_vals in
          let regs =
            List_.filter_map
              (fun v ->
                match v with
                | `Choice_type (`Regi r) -> Some (register env r)
                | _ -> None)
              cst_vals
          in
          match opstr with
          (* unconditional jump *)
          | _ when is_goto opstr -> (
              match labels with
              | (l, lt) :: _ -> Some (G.Goto (optok, (l, lt), sc (G.fake ";")) |> G.s)
              | [] -> Some (G.ExprStmt (expression env e, sc (G.fake ";")) |> G.s))
          (* conditional jump: lower to a real If so both edges exist *)
          | _ when is_if opstr -> (
              match (labels, cmp_operator opstr) with
              | (l, lt) :: _, Some opr ->
                  let zero = G.L (G.Int (Parsed_int.of_int 0)) |> G.e in
                  let lhs, rhs =
                    match regs with
                    | [ a; b ] -> (a, b)
                    | [ a ] -> (a, zero)
                    | _ -> (zero, zero)
                  in
                  let cond =
                    G.Call
                      ( G.IdSpecial (G.Op opr, optok) |> G.e,
                        fb [ G.Arg lhs; G.Arg rhs ] )
                    |> G.e
                  in
                  Some
                    (G.If
                       ( optok,
                         G.Cond cond,
                         G.Goto (optok, (l, lt), sc (G.fake ";")) |> G.s,
                         None )
                    |> G.s)
              | _ -> Some (G.ExprStmt (expression env e, sc (G.fake ";")) |> G.s))
          | _ when is_switch opstr -> (
              let scrutinee = match regs with r :: _ -> r | [] -> G.L (G.Null optok) |> G.e in
              match labels with
              | (payload, _) :: _ -> (
                  match Hashtbl.find_opt env.H.extra.switch_targets payload with
                  | Some targets when targets <> [] ->
                      let cases =
                        List_.map
                          (fun (t, tt) ->
                            G.CasesAndBody
                              ( [ G.Case (optok, G.PatWildcard tt) ],
                                G.Goto (tt, (t, tt), sc (G.fake ";")) |> G.s ))
                          targets
                      in
                      Some (G.Switch (optok, Some (G.Cond scrutinee), cases) |> G.s)
                  | _ ->
                      Some (G.ExprStmt (expression env e, sc (G.fake ";")) |> G.s))
              | [] -> Some (G.ExprStmt (expression env e, sc (G.fake ";")) |> G.s))
          | _ when is_return opstr ->
              let e_opt = match regs with r :: _ -> Some r | [] -> None in
              Some (G.Return (optok, e_opt, sc (G.fake ";")) |> G.s)
          | _ when is_throw opstr ->
              let ex = match regs with r :: _ -> r | [] -> G.L (G.Null optok) |> G.e in
              Some (G.Throw (optok, ex, sc (G.fake ";")) |> G.s)
          | _ -> Some (G.ExprStmt (expression env e, sc (G.fake ";")) |> G.s)))

(* Fuse `invoke-* ... / move-result* vX` into a single assignment, so that a
 * pattern can bind the result register. Debug directives between the two
 * have already been dropped by `statement`. *)
let rec fuse_move_results (env : env) (stmts : (string option * G.stmt) list) :
    G.stmt list =
  match stmts with
  | (Some op, ({ G.s = G.ExprStmt (call, _); _ } as s1)) :: (Some op2, s2) :: rest
    when is_invoke op && is_move_result op2 -> (
      match s2.G.s with
      | G.ExprStmt ({ G.e = G.OtherExpr (_, [ G.E dst ]); _ }, _) ->
          (G.ExprStmt (G.Assign (dst, G.fake "=", call) |> G.e, sc (G.fake ";"))
          |> G.s)
          :: fuse_move_results env rest
      | _ -> s1 :: fuse_move_results env ((Some op2, s2) :: rest))
  | (_, s) :: rest -> s :: fuse_move_results env rest
  | [] -> []

let opcode_of_statement (x : CST.statement) : string option =
  match x with
  | `Choice_label (`Exp ((_loc, opstr), _, _)) -> Some opstr
  | _ -> None

let label_name_of_statement (env : env) (st : CST.statement) : string option =
  match st with
  | `Choice_label (`Label l) | `Choice_label (`Jmp_label l) ->
      Some (normalize_label (fst (str env l)))
  | _ -> None

(* Rebuild each guarded range as a real Try, so the handler is reachable
   from the range in the CFG rather than only from the point where the
   `.catch` directive happens to sit. The handler body itself lives further
   down the method under its own label, so the catch clause is a Goto to
   it -- that is what wires the edge. *)
let rec lower_statements (env : env) (stmts : CST.statement list) : G.stmt list =
  match stmts with
  | [] -> []
  | st :: rest -> (
      match label_name_of_statement env st with
      | Some l when List.mem_assoc l env.H.extra.catch_ranges ->
          let end_l, (handler, htok), exn =
            List.assoc l env.H.extra.catch_ranges
          in
          let guarded, after =
            let rec split acc = function
              | [] -> (List.rev acc, [])
              | x :: xs -> (
                  match label_name_of_statement env x with
                  | Some e when e = end_l -> (List.rev acc, xs)
                  | _ -> split (x :: acc) xs)
            in
            split [] rest
          in
          let body = G.Block (fb (lower_statements env guarded)) |> G.s in
          let catch_clause =
            ( htok,
              G.CatchPattern (G.PatId ((exn, htok), G.empty_id_info ())),
              G.Goto (htok, (handler, htok), sc (G.fake ";")) |> G.s )
          in
          (G.Try (htok, body, [ catch_clause ], None, None) |> G.s)
          :: lower_statements env after
      | _ ->
          (* Take the whole run of statements up to the next guarded range,
             so invoke/move-result fusion still sees consecutive pairs. *)
          let run, after =
            let rec split acc = function
              | [] -> (List.rev acc, [])
              | x :: xs -> (
                  match label_name_of_statement env x with
                  | Some l when List.mem_assoc l env.H.extra.catch_ranges ->
                      (List.rev acc, x :: xs)
                  | _ -> split (x :: acc) xs)
            in
            split [ st ] rest
          in
          let lowered =
            run
            |> List_.filter_map (fun x ->
                   match statement env x with
                   | None -> None
                   | Some y -> Some (opcode_of_statement x, y))
            |> fuse_move_results env
          in
          lowered @ lower_statements env after)

(*****************************************************************************)
(* Class members *)
(*****************************************************************************)

let access_modifier (env : env) (x : CST.access_modifier) : G.attribute =
  (* Includes the AOSP hiddenapi flags (whitelist / greylist / blacklist /
     core-platform-api / test-api) alongside the JVM modifiers. *)
  G.unhandled_keywordattr (access_modifier_str env x)

let method_attrs (env : env) (x : CST.method_access_modifiers option) :
    G.attribute list =
  match x with
  | None -> []
  | Some xs ->
      List_.map
        (fun m ->
          match m with
          | `Access_modi a -> access_modifier env a
          | `Cons t -> G.unhandled_keywordattr (str env t))
        xs

(* Pre-pass over a method body:
   - record each switch payload under the label that precedes it, so the
     switch instruction can find its targets;
   - work out the parameter-register aliasing from `.registers`/`.locals`
     and the descriptor arity. With `.registers N`, the arguments occupy the
     last N_args registers; with `.locals L` they start at vL. *)
let scan_method_body (env : env) (stmts : CST.statement list) (nargs : int) : unit =
  let ctx = env.H.extra in
  Hashtbl.reset ctx.switch_targets;
  ctx.param_map <- [];
  let pending_label = ref None in
  let total = ref None and locals = ref None in
  List.iter
    (fun st ->
      match st with
      | `Choice_label (`Label l) | `Choice_label (`Jmp_label l) ->
          pending_label := Some (normalize_label (fst (str env l)))
      | `Choice_label (`Dire (`Regiss_dire (_, n))) ->
          total := int_of_string_opt (fst (str env n))
      | `Choice_label (`Dire (`Locals_dire (_, n))) ->
          locals := int_of_string_opt (fst (str env n))
      | `Choice_label (`Dire (`Packed_switch_dire (_, _, targets, _))) ->
          (match !pending_label with
          | Some l ->
              Hashtbl.replace ctx.switch_targets l
                (List_.map
                   (fun t ->
                     match t with
                     | `Label x | `Jmp_label x ->
                         let s, tk = str env x in
                         (normalize_label s, tk))
                   targets)
          | None -> ());
          pending_label := None
      | `Choice_label (`Dire (`Sparse_switch_dire (_, entries, _))) ->
          (match !pending_label with
          | Some l ->
              Hashtbl.replace ctx.switch_targets l
                (List_.map
                   (fun (_n, _arrow, x) ->
                     let s, tk = str env x in
                     (normalize_label s, tk))
                   entries)
          | None -> ());
          pending_label := None
      | `Choice_label (`Dire (`Catch_dire (_, exn, rng))) ->
          let ename = class_identifier env exn in
          let st, _en, hd = catch_range env rng in
          ctx.catch_ranges <- (st, (_en, hd, fst ename)) :: ctx.catch_ranges;
          pending_label := None
      | `Choice_label (`Dire (`Catc_dire (_, rng))) ->
          let st, _en, hd = catch_range env rng in
          ctx.catch_ranges <-
            (st, (_en, hd, "java.lang.Throwable")) :: ctx.catch_ranges;
          pending_label := None
      | _ -> pending_label := None)
    stmts;
  (* Type an ambiguous constant from the descriptor of the parameter
     position that *this* definition reaches: walk the method in order,
     remember the pending `const` for each register, and settle it at the
     register's first use as an invoke operand. A later `const` to the same
     register replaces the pending one, so a reassigned register types each
     of its definitions independently. *)
  Hashtbl.reset ctx.zero_types;
  let pending : (string, int) Hashtbl.t = Hashtbl.create 8 in
  List.iter
    (fun st ->
      match st with
      | `Choice_label (`Exp ((op, Some (v0, restv), _))) ->
          let opstr = fst (str env op) in
          if is_const opstr then (
            match v0 with
            | `Choice_type (`Regi (`Choice_var (`Var x)))
            | `Choice_type (`Regi (`Choice_var (`Param x))) ->
                Hashtbl.replace pending (fst (str env x))
                  (Tok.bytepos_of_tok (token env op))
            | _ -> ())
          else if is_invoke opstr then
            let vals = v0 :: List_.map (fun (_c, v) -> v) restv in
            let regs =
              match vals with
              | `Choice_type (`List (_, Some (r0, rrest), _)) :: _ ->
                  r0 :: List_.map (fun (_c, r) -> r) rrest
              | _ -> []
            in
            let ptypes =
              match vals with
              | [ _; `Choice_type (`Body (`Full_meth_sign (_, _, (_, msb)))) ] -> (
                  match msb with
                  | `LPAR_rep_type_RPAR_type (_, ps, _, _) ->
                      List_.map (fun t -> fst (type_ env t)) ps
                  | `LPAR_ellips_RPAR_type _ -> [])
              | _ -> []
            in
            let is_static = opstr = "invoke-static" || opstr = "invoke-static/range" in
            let regnames =
              List_.filter_map
                (fun v ->
                  match v with
                  | `Choice_type (`Regi (`Choice_var (`Var x)))
                  | `Choice_type (`Regi (`Choice_var (`Param x))) ->
                      Some (fst (str env x))
                  | _ -> None)
                regs
            in
            let args = if is_static then regnames else (match regnames with _ :: t -> t | [] -> []) in
            List.iteri
              (fun i r ->
                match (List.nth_opt ptypes i, Hashtbl.find_opt pending r) with
                | Some ty, Some pos ->
                    (* First use settles the definition; drop the pending so a
                       later position cannot retype the same constant. *)
                    Hashtbl.replace ctx.zero_types pos ty;
                    Hashtbl.remove pending r
                | _ -> ())
              args
      | _ -> ())
    stmts;
  let base =
    match (!total, !locals) with
    | Some t, _ -> Some (t - nargs)
    | None, Some l -> Some l
    | None, None -> None
  in
  match base with
  | Some b when b >= 0 ->
      ctx.param_map <-
        List.init nargs (fun i -> (Printf.sprintf "p%d" i, Printf.sprintf "v%d" (b + i)))
  | _ -> ()

let method_definition (env : env) ((_m, mods, msig, stmts, _end) : CST.method_definition)
    : G.field =
  let name = method_signature env msig in
  let _nm, msig_body = msig in
  (* `(...)` elides the descriptor (grammar task 1.7); it becomes a single
     ParamEllipsis so a pattern matches any overload. *)
  let ptypes, ellipsis_tok, rett =
    match msig_body with
    | `LPAR_rep_type_RPAR_type (_lp, params, _rp, rett) ->
        (List_.map (fun t -> type_ env t) params, None, rett)
    | `LPAR_ellips_RPAR_type (_lp, ell, _rp, rett) ->
        ([], Some (token env ell), rett)
  in
  let is_static =
    match mods with
    | None -> false
    | Some xs ->
        List.exists (fun m -> match m with `Access_modi (`Static _) -> true | _ -> false) xs
  in
  (* Parameters are counted in *registers*, not in parameters: a long or a
     double occupies two. Getting this wrong shifts the whole p-to-v mapping
     and so silently renames every parameter in the method. *)
  let width (s, _) = if String.equal s "J" || String.equal s "D" then 2 else 1 in
  let this_regs = if is_static then 0 else 1 in
  let nargs = this_regs + List.fold_left (fun acc t -> acc + width t) 0 ptypes in
  scan_method_body env stmts nargs;
  env.H.extra.this_local <-
    (if is_static then None
     else
       Some
         (try List.assoc "p0" env.H.extra.param_map with Not_found -> "p0"));
  (* Name each parameter after the register that holds it.
     Without this the parameter list is a list of bare types and the
     registers the body actually reads (`p1`, `p2`, ...) are unrelated
     variables, so nothing connects an argument at a call site to the value
     the callee uses and no interprocedural analysis -- taint in particular --
     can cross a call. *)
  let fparams =
    match ellipsis_tok with
    | Some t -> [ G.ParamEllipsis t ]
    | None ->
        let _, rev_ps =
          List.fold_left
            (fun (pidx, acc) t ->
              let preg = Printf.sprintf "p%d" pidx in
              let local =
                try List.assoc preg env.H.extra.param_map with Not_found -> preg
              in
              let pc =
                { (G.param_of_type (ty_of t)) with G.pname = Some (local, snd t) }
              in
              (pidx + width t, G.Param pc :: acc))
            (this_regs, []) ptypes
        in
        List.rev rev_ps
  in
  let body = lower_statements env stmts in
  let ent = { G.name = G.EN (name_of name); attrs = method_attrs env mods; tparams = None } in
  let def =
    {
      G.fkind = (G.Method, snd name);
      fparams = fb fparams;
      frettype = Some (ty_of (type_ env rett));
      fbody = G.FBStmt (G.Block (fb body) |> G.s);
    }
  in
  G.F (G.DefStmt (ent, G.FuncDef def) |> G.s)

let field_definition (env : env) ((_f, mods, fbody, init, _anns) : CST.field_definition)
    : G.field =
  let fid = field_name env fbody in
  let fty = field_type env fbody in
  let attrs =
    match mods with
    | None -> []
    | Some xs -> List_.map (access_modifier env) xs
  in
  let ent = { G.name = G.EN (name_of fid); attrs; tparams = None } in
  let vinit = Option.map (fun (_eq, v) -> value env v) init in
  G.F
    (G.DefStmt
       (ent, G.VarDef { G.vinit; vtype = Some (ty_of fty); vtok = None })
    |> G.s)

let class_decl (env : env) ((cdir, sdir, _src, impls, members) : CST.class_decl) :
    G.stmt =
  let _c, cmods, cid = cdir in
  let cname = class_identifier env cid in
  env.H.extra.current_class <- Some cname;
  let _s, sid = sdir in
  env.H.extra.super_class <- Some (fst (class_identifier env sid));
  let attrs =
    match cmods with
    | None -> []
    | Some xs -> List_.map (access_modifier env) xs
  in
  let fields =
    List_.filter_map
      (fun m ->
        match m with
        | `Meth_defi d -> Some (method_definition env d)
        | `Field_defi d -> Some (field_definition env d)
        | `Anno_dire _ -> None
        | `Ellips t -> Some (G.field_ellipsis (token env t)))
      members
  in
  let ent = { G.name = G.EN (name_of cname); attrs; tparams = None } in
  let def =
    {
      G.ckind = (G.Class, snd cname);
      cextends = [ (ty_of (class_identifier env sid), None) ];
      cimplements =
        List_.map (fun (_i, c) -> ty_of (class_identifier env c)) impls;
      cmixins = [];
      cparams = fb [];
      cbody = fb fields;
    }
  in
  G.DefStmt (ent, G.ClassDef def) |> G.s

(* The alternate pattern entry point admits class members as well as
   statements, so a rule can be written as `.method ... .end method`. *)
let semgrep_item (env : env)
    (x : [ `Stmt of CST.statement | `Meth_defi of CST.method_definition
         | `Field_defi of CST.field_definition ]) : G.stmt list =
  match x with
  | `Stmt st -> lower_statements env [ st ]
  | `Meth_defi d -> ( match method_definition env d with G.F st -> [ st ])
  | `Field_defi d -> ( match field_definition env d with G.F st -> [ st ])

let class_definition (env : env) (x : CST.class_definition) :
    (G.program, G.stmt list) Either.t =
  match x with
  | `Rep1_class_decl decls -> Either.Left (List_.map (class_decl env) decls)
  | `Semg_stmt (_marker, items) ->
      Either.Right (List.concat_map (semgrep_item env) items)

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let parse file =
  H.wrap_parser
    (fun () -> Tree_sitter_smali.Parse.file !!file)
    (fun cst _extras ->
      let extra = new_ctx () in
      Hashtbl.iter
        (fun k v -> Hashtbl.replace extra.reg_types k v)
        (load_register_info file);
      let env = { H.file; conv = H.line_col_to_pos file; extra } in
      match class_definition env cst with
      | Either.Left prog -> prog
      | Either.Right stmts -> stmts)

(* A pattern is usually a bare instruction or a method, not a whole class.
   Try it as written first -- that covers a full `.class` pattern -- then
   retry behind the alternate entry point. *)
let parse_statements_or_class str_ =
  let res = Tree_sitter_smali.Parse.string str_ in
  match res.errors with
  | [] -> res
  | _ -> Tree_sitter_smali.Parse.string ("__SEMGREP_STATEMENT " ^ str_)

let parse_pattern str_ =
  H.wrap_parser
    (fun () -> parse_statements_or_class str_)
    (fun cst _extras ->
      let file = Fpath.v "<pattern>" in
      let env = { H.file; conv = H.line_col_to_pos_pattern str_; extra = new_ctx () } in
      match class_definition env cst with
      | Either.Left prog -> G.Pr prog
      | Either.Right [ st ] -> G.S st
      | Either.Right sts -> G.Ss sts)
