.class public Lcom/example/S;
.super Ljava/lang/Object;

.method public clean(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    invoke-static {v0}, Landroid/database/DatabaseUtils;->sqlEscapeString(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v1
    # OK: smali-sanitizer
    invoke-virtual {p2, v1}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method

.method public dirty(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    # ruleid: smali-sanitizer
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
