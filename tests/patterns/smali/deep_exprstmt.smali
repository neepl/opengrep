.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    const-string v1, "x"
    # ERROR:
    invoke-static {v1}, Lcom/example/H;->sink(Ljava/lang/String;)V
    return-void
.end method
