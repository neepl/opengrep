.class public Lcom/example/Basic;
.super Ljava/lang/Object;
.source "Basic.java"

.field private static final TAG:Ljava/lang/String; = "Basic"

.method public constructor <init>()V
    .registers 1
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

.method public static leak(Landroid/content/Intent;)Ljava/lang/String;
    .registers 4
    .param p0, "intent"
    const-string v0, "AES/ECB/PKCS5Padding"
    invoke-static {v0}, Ljavax/crypto/Cipher;->getInstance(Ljava/lang/String;)Ljavax/crypto/Cipher;
    move-result-object v1
    invoke-virtual {p0}, Landroid/content/Intent;->getDataString()Ljava/lang/String;
    move-result-object v2
    sget-object v3, Lcom/example/Basic;->TAG:Ljava/lang/String;
    return-object v2
.end method
