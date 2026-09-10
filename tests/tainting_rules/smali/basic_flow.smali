.class public Lcom/example/Flow;
.super Ljava/lang/Object;

.method public tainted(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 6
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    # ruleid: smali-basic-flow
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method

.method public reassigned(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 6
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    const-string v0, "safe"
    # OK: smali-basic-flow
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
