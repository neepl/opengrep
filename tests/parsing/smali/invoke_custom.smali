# A call site is `name(string, prototype, literal*)@method`. The bootstrap
# arguments after the prototype may be any literal -- smali's own grammar is
# `string_literal COMMA method_prototype (COMMA literal)*` -- and a numeric one
# is the common case for a desugared invokedynamic.
#
# Not observed in the corpus: `invoke-custom` appears zero times in the
# 75,242-file Samsung Health tree, because D8 desugars lambdas into classes.
# It is reachable on newer toolchains, and the failure shape is the usual
# silent partial parse.
.class public Lcom/example/InvokeCustom;
.super Ljava/lang/Object;

.method public numericArgument()V
    .registers 2
    invoke-custom {}, call_site_1("n", (I)V, 0x1)@Lcom/example/Bsm;->bsm()Ljava/lang/invoke/CallSite;
    return-void
.end method

.method public mixedArguments()V
    .registers 2
    invoke-custom {}, call_site_2("s", ()V, "str", 1.5, 0x2L, true)@Lcom/example/Bsm;->bsm()Ljava/lang/invoke/CallSite;
    return-void
.end method

.method public methodHandleArgument()V
    .registers 2
    invoke-custom {}, call_site_3("h", ()V, invoke-static@Lcom/example/A;->b()V)@Lcom/example/Bsm;->bsm()Ljava/lang/invoke/CallSite;
    return-void
.end method

.method public noBootstrapArguments()V
    .registers 2
    invoke-custom {}, call_site_4("n", ()V)@Lcom/example/Bsm;->bsm()Ljava/lang/invoke/CallSite;
    return-void
.end method
