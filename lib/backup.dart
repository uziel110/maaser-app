// גיבוי ושחזור – לפי המנגנון שפוענח מניהול כספים:
//   ZIP עם קובץ ה-DB + backup_meta = {"version":1,"hash":H}
//   H = hex(SHA256(salt + join(sorted(base64(MD5(file)) לכל קובץ))))
// שחזור: פריסה לתיקייה זמנית, בדיקת meta, עותק rollback של ה-DB הנוכחי, החלפה, ובמקרה כשל – חזרה.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'store.dart';

const backupSalt = 'maaser.app';
const metaName = 'backup_meta';
const backupVersion = 1;
const backupExt = 'maaserbackup';

String backupHash(List<Uint8List> files) {
  final sums = files.map((b) => base64.encode(md5.convert(b).bytes)).toList()..sort();
  return sha256.convert(utf8.encode(backupSalt + sums.join())).toString();
}

String backupFileName() => 'Maaser_${DateFormat("yyyyMMdd'T'HHmmss").format(DateTime.now())}.$backupExt';

/// מחזיר את תוכן קובץ הגיבוי. סוגר את ה-DB לרגע כדי לקרוא קובץ שלם ועקבי.
Future<Uint8List> createBackup(Store s) async {
  await s.db.close();
  try {
    final dbBytes = await File(s.db.path).readAsBytes();
    final meta = jsonEncode({'version': backupVersion, 'hash': backupHash([dbBytes])});
    final a = Archive()
      ..addFile(ArchiveFile(dbFileName, dbBytes.length, dbBytes))
      ..addFile(ArchiveFile(metaName, utf8.encode(meta).length, utf8.encode(meta)));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  } finally {
    await s.db.open();
  }
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

Future<void> restoreBackup(Store s, Uint8List bytes) async {
  // קבצי ניהול כספים מתחילים ב-8 בייטים לפני ה-ZIP; נתמוך גם בזה.
  var start = 0;
  for (var i = 0; i + 3 < bytes.length && i < 64; i++) {
    if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 3 && bytes[i + 3] == 4) { start = i; break; }
  }
  final Archive arc;
  try {
    arc = ZipDecoder().decodeBytes(bytes.sublist(start));
  } catch (_) {
    throw BackupException('הקובץ אינו קובץ גיבוי תקין.');
  }
  final dbF = arc.findFile(dbFileName), metaF = arc.findFile(metaName);
  if (dbF == null || metaF == null) throw BackupException('בקובץ הגיבוי חסרים נתונים.');
  final dbBytes = Uint8List.fromList(dbF.content as List<int>);
  final meta = jsonDecode(utf8.decode(metaF.content as List<int>)) as Map<String, dynamic>;
  if (meta['version'] != backupVersion || meta['hash'] != backupHash([dbBytes])) {
    throw BackupException('קובץ הגיבוי פגום או ששונה.');
  }

  final tmp = await getTemporaryDirectory();
  final restorePath = p.join(tmp.path, 'temp_restore_${DateTime.now().millisecondsSinceEpoch}.db');
  await File(restorePath).writeAsBytes(dbBytes, flush: true);
  // בדיקה שהקובץ נפתח ויש בו את הטבלאות הנדרשות
  final probe = await openDatabase(restorePath, readOnly: true);
  try {
    final t = await probe.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = t.map((r) => r['name']).toSet();
    if (!names.containsAll(['fund', 'category', 'tx', 'rule', 'settings'])) {
      throw BackupException('מבנה הנתונים בגיבוי לא מתאים לאפליקציה.');
    }
  } finally {
    await probe.close();
  }

  final rollback = p.join(tmp.path, 'temp_rollback_${DateTime.now().millisecondsSinceEpoch}.db');
  await s.db.close();
  await File(s.db.path).copy(rollback);
  try {
    await File(restorePath).copy(s.db.path);
    await s.db.open();
    await s.reload();
    await s.runRecurring();
  } catch (e) {
    await s.db.close();
    await File(rollback).copy(s.db.path);
    await s.db.open();
    await s.reload();
    throw BackupException('השחזור נכשל והנתונים הקודמים הוחזרו.');
  } finally {
    for (final f in [restorePath, rollback]) {
      try { await File(f).delete(); } catch (_) {}
    }
  }
}
