.class public Lcom/example/Z;
.super Ljava/lang/Object;

.method public m()V
    .registers 5
    const/4 v0, 0x0
    invoke-virtual {p0, v0}, Ljavax/net/ssl/SSLContext;->init(Ljava/security/KeyStore;)V
    const/4 v1, 0x0
    invoke-virtual {p0, v1}, Landroid/webkit/WebSettings;->setJavaScriptEnabled(Z)V
    const/4 v2, 0x0
    invoke-virtual {p0, v2}, Lcom/example/H;->count(I)V
    return-void
.end method
