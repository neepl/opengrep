# A dex MemberName is arbitrary UTF-8, and smali quotes a name that is not a
# plain identifier in backticks. Kotlin feature-flag constants written as prose
# produce exactly this. Seen in the wild in Samsung's lockeditor SDK.
#
# The distinction that matters: a backtick in *name* position breaks an
# ASCII-identifier grammar, while a backtick inside a default string value is
# just string content and always parsed fine. Both appear below, because a
# naive search for backticks on a `.field` line finds far more of the second.
.class public Lcom/example/BacktickNames;
.super Ljava/lang/Object;

.field public static final INSTANCE:Lcom/example/BacktickNames;
.field public static final `support show panel API with allowance nest scroll`:J = 0xaae61L
.field public static final `name with  two spaces`:I = 0x1
.field public static final `punctuation!?()[]{}`:I = 0x2
.field private quoted_value:Ljava/lang/String; = "a `backtick` inside a string"
.field public static final plain_after:I = 0x3

.method public readQuoted()J
    .registers 3
    sget-wide v0, Lcom/example/BacktickNames;->`support show panel API with allowance nest scroll`:J
    return-wide v0
.end method

.method public `a quoted method name`()V
    .registers 1
    return-void
.end method

.method public callsQuoted()V
    .registers 1
    invoke-virtual {p0}, Lcom/example/BacktickNames;->`a quoted method name`()V
    return-void
.end method

# A class-name segment may be quoted too. Not seen in the corpus -- only the
# member-name form was -- but it is the same construct through a different
# rule, and it is handled by the external scanner rather than the grammar.
.method public quotedClassName()V
    .registers 2
    new-instance v0, Lcom/example/`a quoted class`;
    invoke-direct {v0}, Lcom/example/`a quoted class`;-><init>()V
    return-void
.end method
