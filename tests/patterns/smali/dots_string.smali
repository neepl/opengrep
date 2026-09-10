.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    # ERROR:
    const-string v0, "xxabcyy"
    # ERROR:
    const-string v1, "nope"
    const/4 v2, 0x1
    return-void
.end method
