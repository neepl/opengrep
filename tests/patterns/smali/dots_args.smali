.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    const-string v0, "a"
    const-string v1, "b"
    # ERROR:
    invoke-static {v0, v1}, Lcom/example/H;->sink(Ljava/lang/String;Ljava/lang/String;)V
    # ERROR:
    invoke-static {v0}, Lcom/example/H;->sink(Ljava/lang/String;)V
    return-void
.end method
