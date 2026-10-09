// שכבת SQLite. נבנתה לפי הדפוס של ניהול כספים: user_version + מיגרציות ALTER TABLE,
// מחיקה רכה (isRemoved), טבלת key-value להגדרות.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'models.dart';

const dbFileName = 'maaser.db';
const schemaVersion = 1;

class Db {
  Database? _db;
  Database get db => _db!;
  late String path;

  Future<void> open() async {
    path = p.join(await getDatabasesPath(), dbFileName);
    _db = await openDatabase(path, version: schemaVersion, onCreate: _create, onUpgrade: _upgrade);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _create(Database d, int v) async {
    await d.execute('''CREATE TABLE fund (
      uid TEXT PRIMARY KEY, title TEXT, role TEXT, color INTEGER,
      openingBalance INTEGER DEFAULT 0, created TEXT, modified TEXT)''');
    await d.execute('''CREATE TABLE category (
      uid TEXT PRIMARY KEY, title TEXT, type TEXT, icon TEXT, color INTEGER,
      full INTEGER DEFAULT 0, useCount INTEGER DEFAULT 0, lastUse TEXT,
      position INTEGER DEFAULT -1, isRemoved INTEGER DEFAULT 0, created TEXT, modified TEXT)''');
    await d.execute('''CREATE TABLE tx (
      uid TEXT PRIMARY KEY, type TEXT, amount INTEGER, gross INTEGER, mode TEXT,
      date TEXT, comment TEXT, categoryUid TEXT, splits TEXT, recurringUid TEXT,
      isRemoved INTEGER DEFAULT 0, created TEXT, modified TEXT)''');
    await d.execute('CREATE INDEX tx_date ON tx(date)');
    await d.execute('''CREATE TABLE rule (
      uid TEXT PRIMARY KEY, enabled INTEGER, freq TEXT, startDate TEXT, lastDate TEXT,
      endDate TEXT, template TEXT, created TEXT, modified TEXT)''');
    await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  // מיגרציות עתידיות: להוסיף כאן if (from < 2) { ALTER TABLE ... } וכו'.
  Future<void> _upgrade(Database d, int from, int to) async {}

  Future<List<Map<String, Object?>>> all(String table) => db.query(table);

  Future<void> put(String table, Map<String, Object?> row) =>
      db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String table, String uid) => db.delete(table, where: 'uid = ?', whereArgs: [uid]);

  Future<Map<String, String>> settings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> setSetting(String k, String v) => put('settings', {'key': k, 'value': v});

  /// החלפת כל הנתונים (ייבוא). בתוך טרנזקציה, כמו בשחזור של ניהול כספים.
  Future<void> replaceAll({required List<Fund> funds, required List<Category> cats,
      required List<Tx> txs, required List<Rule> rules, required Map<String, String> settings}) async {
    await db.transaction((t) async {
      for (final tb in ['fund', 'category', 'tx', 'rule', 'settings']) {
        await t.delete(tb);
      }
      final b = t.batch();
      for (final f in funds) { b.insert('fund', f.toRow()); }
      for (final c in cats) { b.insert('category', c.toRow()); }
      for (final x in txs) { b.insert('tx', x.toRow()); }
      for (final r in rules) { b.insert('rule', r.toRow()); }
      settings.forEach((k, v) => b.insert('settings', {'key': k, 'value': v}));
      await b.commit(noResult: true);
    });
  }
}
