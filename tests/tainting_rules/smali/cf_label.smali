.class public Lcom/example/LB;
.super Ljava/lang/Object;

.method public labelled(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    :cond_1
    # ruleid: smali-cf-label
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
