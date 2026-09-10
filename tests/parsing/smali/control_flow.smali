.class public Lcom/example/Flow;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

.method public run()V
    .registers 5
    const/4 v0, 0x0
    :goto_0
    const/16 v1, 0xa
    if-ge v0, v1, :cond_1
    add-int/lit8 v0, v0, 0x1
    goto :goto_0
    :cond_1
    :try_start_0
    invoke-static {}, Ljava/lang/System;->currentTimeMillis()J
    move-result-wide v2
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0
    goto :goto_1
    :catch_0
    move-exception v4
    throw v4
    :goto_1
    packed-switch v0, :pswitch_data_0
    return-void
    :pswitch_0
    return-void
    :pswitch_data_0
    .packed-switch 0x0
        :pswitch_0
    .end packed-switch
.end method
