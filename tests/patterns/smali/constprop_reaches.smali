.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    const-string v0, "kept"
    # ERROR:
    invoke-static {v0}, Lcom/example/H;->sink(Ljava/lang/String;)V
    return-void
.end method
