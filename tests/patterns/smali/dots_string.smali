.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    # ERROR:
    const-string v0, "xxabcyy"
    const-string v1, "nope"
    return-void
.end method
