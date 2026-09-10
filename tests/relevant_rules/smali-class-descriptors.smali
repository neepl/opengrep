.class public Lcom/example/Prefilter;
.super Ljava/lang/Object;

.method public static staticCall()V
    .registers 2
    const-string v0, "AES/ECB/PKCS5Padding"
    invoke-static {v0}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;
    move-result-object v1
    return-void
.end method

.method public static fieldRead()V
    .registers 1
    sget-object v0, Landroid/os/Build$VERSION;->SDK_INT:I
    return-void
.end method
