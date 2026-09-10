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
