(* Translate the smali CST produced by tree-sitter into AST_generic.
 *
 * STATUS: the tree-sitter parse is real -- syntax errors in a target are
 * reported as such -- but the CST is not yet lowered. Both entry points
 * currently yield an empty program / pattern, so a `.smali` target is
 * selected, read and parsed end to end without any construct being
 * matchable yet.
 *
 * The lowering itself is Gate C of the add-smali-language-support change
 * (tasks 4.1-4.15): registers as method-scoped locals, invoke/move-result
 * fusion into assignments, const-* as literals, and labels/gotos/switches/
 * try-catch onto the constructs CFG_build already understands. Until that
 * lands, smali rules cannot match anything, which is why smali is marked
 * `develop` maturity in the language table.
 *)
open Fpath_.Operators
module G = AST_generic
module H = Parse_tree_sitter_helpers

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let parse file =
  H.wrap_parser
    (fun () -> Tree_sitter_smali.Parse.file !!file)
    (fun _cst _extras -> ([] : G.program))

let parse_pattern str =
  H.wrap_parser
    (fun () -> Tree_sitter_smali.Parse.string str)
    (fun _cst _extras -> G.Pr [])
