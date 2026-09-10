.class public Lcom/example/XS;
.super Ljava/lang/Object;

.method public static entry(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    invoke-virtual {p0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    invoke-static {p1, v0}, Lcom/example/XS;->helper(Landroid/database/sqlite/SQLiteDatabase;Ljava/lang/String;)V
    return-void
.end method

.method private static helper(Landroid/database/sqlite/SQLiteDatabase;Ljava/lang/String;)V
    .registers 4
    # ruleid: smali-crossstatic
    invoke-virtual {p0, p1}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
