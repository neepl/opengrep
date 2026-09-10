.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    const-string v2, "s"
    # ERROR:
    invoke-static {v2}, Lcom/example/H;->sink(Ljava/lang/String;)V
    return-void
.end method
