.class public Lcom/example/C;
.super Ljava/lang/Object;

.method public branch(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;I)V
    .registers 8
    const-string v0, "safe"
    if-eqz p3, :cond_0
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    :cond_0
    # ruleid: smali-cf-branch
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method

