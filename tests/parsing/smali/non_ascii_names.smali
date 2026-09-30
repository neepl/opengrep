# Dalvik's SimpleName permits non-ASCII (U+00a1..U+1fff, U+2010..U+2027,
# U+2030..U+d7ff, U+e000..U+ffef) and baksmali emits such names verbatim.
# Localized resource-constant classes are the common case: an ASCII-only
# identifier rule truncates the name mid-token and fails the file with
# PartialParsing, so the remainder is silently skipped.
.class public Lcom/example/NonAsciiNames;
.super Ljava/lang/Object;

.field public static Costa_Rican_colón:I = 0x7f130015
.field public static Icelandic_króna:I = 0x7f130039
.field public static Vietnamese_đồng:I = 0x7f130040
.field public static 日本語:I = 0x7f130041
.field public static plain_ascii_after:I = 0x7f130042

.method public readAccented()I
    .registers 2
    sget v0, Lcom/example/NonAsciiNames;->Costa_Rican_colón:I
    return v0
.end method
