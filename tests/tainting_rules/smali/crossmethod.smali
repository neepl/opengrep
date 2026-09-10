.class public Lcom/example/X;
.super Ljava/lang/Object;

.method public entry(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    invoke-direct {p0, p2, v0}, Lcom/example/X;->helper(Landroid/database/sqlite/SQLiteDatabase;Ljava/lang/String;)V
    return-void
.end method

.method private helper(Landroid/database/sqlite/SQLiteDatabase;Ljava/lang/String;)V
    .registers 6
    # ruleid: smali-crossmethod
    invoke-virtual {p1, p2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
