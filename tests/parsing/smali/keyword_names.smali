# A field may be named after a smali keyword. Java and Kotlin names -- and the
# names an obfuscator emits -- are not constrained by smali's vocabulary, so
# every access flag is a legitimate field name. These appear in real APKs:
# `public` in a shipping application, `annotation` in simpleframework's XML
# library.
.class public Lcom/example/KeywordNames;
.super Ljava/lang/Object;

.field private public:Z
.field private final annotation:Ljava/lang/annotation/Annotation;
.field private static final enum:I
.field private interface:Ljava/lang/String;
.field private static synthetic:[B
.field private native:F
.field private ordinary:Z

.method public readKeywordField()Z
    .registers 2
    iget-boolean v0, p0, Lcom/example/KeywordNames;->public:Z
    return v0
.end method

.method public writeKeywordField(I)V
    .registers 3
    iput v1, p0, Lcom/example/KeywordNames;->enum:I
    return-void
.end method

.method public static readStaticKeywordField()Ljava/lang/String;
    .registers 1
    sget-object v0, Lcom/example/KeywordNames;->interface:Ljava/lang/String;
    return-object v0
.end method

# A *method* may be named after an access flag too, for the same reason.
# `synchronized` is what Kotlin emits for the stdlib's synchronized-block
# helper (kotlin/StandardKt__SynchronizedKt, kotlinx/coroutines/internal/
# SynchronizedKt); `bridge` and `native` are what an obfuscator produces.
# Deciding between "another modifier" and "the method name" needs the `(`
# that follows, one token past LR(1), so it rests on a GLR conflict.
.method private static final synchronized(Ljava/lang/Object;Lkotlin/jvm/functions/Function0;)Ljava/lang/Object;
    .registers 3
    return-object p0
.end method

.method public bridge()V
    .registers 1
    return-void
.end method

.method public static native(I)I
    .registers 2
    return p0
.end method
