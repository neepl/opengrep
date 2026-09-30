# `#` begins a comment in smali, but inside a char literal it is data. The
# literal is a seq rather than a single token, so without `immediate` on its
# body and closing quote the comment extra matches between the children: the
# `#` opens a comment that swallows the closing quote and the rest of the
# line, and the parse then fails on the *following* declaration. Both of
# these are real -- ICU's DecimalFormat and Samsung's SESL fork of AndroidX,
# which together reach a large fraction of any Samsung image.
.class public Lcom/example/CharLiterals;
.super Ljava/lang/Object;

.field private static final PATTERN_DIGIT:C = '#'
.field static final PATTERN_EXPONENT:C = 'E'
.field private static final DIGIT_CHAR:C = '#'          # a real trailing comment
.field private static final CURRENCY_SIGN:C = '¤'
.field private static final FAVORITE_CHAR:C = '★'
.field private static final SYMBOL_CHAR:C = '&'
.field private static final PATTERN_DECIMAL_SEPARATOR:C = '.'
.field private static final QUOTE:C = '\''
.field private static final BACKSLASH:C = '\\'
.field private static final NEWLINE:C = '\n'
.field private static final reached_the_end:I = 0x1

.method public hashInString()Ljava/lang/String;
    .registers 2
    # a `#` inside a string is data too, and strings already worked
    const-string v0, "a # inside a string"
    return-object v0
.end method
