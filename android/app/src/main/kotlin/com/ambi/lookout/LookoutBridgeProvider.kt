package com.ambi.lookout

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Binder
import org.json.JSONArray
import org.json.JSONObject

/** Read-only device-local watch data. Only Friday's package UID may query. */
class LookoutBridgeProvider : ContentProvider() {
    override fun onCreate() = true
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val ctx = context ?: return null
        val packages = ctx.packageManager.getPackagesForUid(Binder.getCallingUid()) ?: return null
        if (!packages.contains("com.friday.assistant") || uri.path != "/status") return null
        val file = ctx.getDatabasePath("lookout.db")
        if (!file.exists()) return null
        return try {
            val json = JSONObject().put("readAt", System.currentTimeMillis())
            val rows = JSONArray()
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT id,title,status,lastCheckedAt,currentValue,lastSuccessfulReadAt,lastSuccessfulValue FROM agents ORDER BY createdAt DESC LIMIT 100", null).use { c ->
                    while(c.moveToNext()) {
                        val row = JSONObject()
                        for(i in 0 until c.columnCount) {
                            val value: Any = if(c.isNull(i)) JSONObject.NULL else when(c.getType(i)) {
                                Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
                                Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
                                else -> c.getString(i)
                            }
                            row.put(c.getColumnName(i), value)
                        }
                        rows.put(row)
                    }
                }
                db.rawQuery("SELECT COUNT(*) FROM agents", null).use { c -> c.moveToFirst(); json.put("total", c.getInt(0)) }
            }
            json.put("watches", rows)
            MatrixCursor(arrayOf("json")).apply { addRow(arrayOf(json.toString())) }
        } catch (_: Exception) { null }
    }
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
}
