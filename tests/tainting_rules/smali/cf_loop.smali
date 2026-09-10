.class public Lcom/example/L;
.super Ljava/lang/Object;

.method public loop(Landroid/content/Intent;Landroid/database/sqlite/SQLiteDatabase;)V
    .registers 8
    const/4 v2, 0x0
    invoke-virtual {p1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    :goto_0
    const/16 v3, 0xa
    if-ge v2, v3, :cond_1
    add-int/lit8 v2, v2, 0x1
    goto :goto_0
    :cond_1
    # ruleid: smali-cf-loop
    invoke-virtual {p2, v0}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
    return-void
.end method
