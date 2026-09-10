.class public Lcom/example/T;
.super Ljava/lang/Object;
.field public static final TAG:Ljava/lang/String; = "t"

.method public m()V
    .registers 4
    # ERROR:
    sget-object v0, Lcom/example/T;->TAG:Ljava/lang/String;
    new-instance v1, Ljava/util/Random;
    return-void
.end method
