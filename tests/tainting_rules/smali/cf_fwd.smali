.class public Lcom/example/FW;
.super Ljava/lang/Object;

.method public fwd(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    goto :cond_1
    :cond_1
    # ruleid: smali-cf-fwd
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
