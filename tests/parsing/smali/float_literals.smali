# Every spelling of a float field initialiser baksmali emits. The suffixed
# specials are what Kotlin's FloatCompanionObject/DoubleCompanionObject carry
# for POSITIVE_INFINITY and NEGATIVE_INFINITY; upstream's grammar gives `NaN`
# an explicit `NaNf` alternative but never did the same for `Infinity`, so
# those two lines used to leave the file partly unparsed.
.class public final Lcom/example/FloatLiterals;
.super Ljava/lang/Object;

.field public static final MAX_VALUE:F = 3.4028235E38f
.field public static final MIN_VALUE:F = 1.4E-45f
.field public static final NEGATIVE_INFINITY:F = -Infinityf
.field public static final POSITIVE_INFINITY:F = Infinityf
.field public static final NOT_A_NUMBER:F = NaNf
.field public static final PLAIN_NAN:D = NaN
.field public static final PLAIN_INF:D = Infinity
.field public static final PLAIN_NEG_INF:D = -Infinity
.field public static final SIMPLE:F = 1.5f
.field public static final ZERO:F = 0.0f
.field public static final NEGATIVE:F = -2.25f
.field public static final SIZE_BITS:I = 0x20

.method public static readMax()F
    .registers 1
    sget v0, Lcom/example/FloatLiterals;->MAX_VALUE:F
    return v0
.end method
