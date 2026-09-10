.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    # ERROR:
    invoke-static {v0}, Lcom/example/H;->a()V
    const/4 v1, 0x1
    const/4 v2, 0x2
    invoke-static {v0}, Lcom/example/H;->b()V
    return-void
.end method
