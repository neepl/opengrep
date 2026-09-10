.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    const-string v0, "s"
    # ERROR:
    invoke-static {v0}, Lcom/example/H;->a(Ljava/lang/String;)V
    invoke-static {v0}, Lcom/example/H;->b(Ljava/lang/String;)V
    return-void
.end method
