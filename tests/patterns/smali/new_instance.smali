.class public Lcom/example/T;
.super Ljava/lang/Object;

.method public m()V
    .registers 4
    # ERROR:
    new-instance v1, Ljava/util/Random;
    new-instance v2, Ljava/lang/StringBuilder;
    return-void
.end method
