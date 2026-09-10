.class public Lcom/example/F;
.super Ljava/lang/Object;

.method public sel(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1
    const-string v0, "users"
    # ruleid: smali-focus
    invoke-virtual {p2, v0, v1}, Landroid/database/sqlite/SQLiteDatabase;->query(Ljava/lang/String;Ljava/lang/String;)V
    return-void
.end method

.method public tbl(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1
    const-string v0, "safe"
    # OK: smali-focus
    invoke-virtual {p2, v1, v0}, Landroid/database/sqlite/SQLiteDatabase;->query(Ljava/lang/String;Ljava/lang/String;)V
    return-void
.end method
