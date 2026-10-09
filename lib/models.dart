// מודל הנתונים. סכומים באגורות (int), תאריכים 'yyyy-MM-dd', מזהים UUID.
import 'dart:convert';

const roleMaaser = 'maaser';
const roleChomesh = 'chomesh';

const typeIncome = 'Income';
const typeExpense = 'Expense';

/// אופן חישוב הכנסה
const modeAuto = 'auto';
const modeMaaserOnly = 'maaser_only';
const modeMaaserChomesh = 'maaser_chomesh';
const modeManual = 'manual'; // סכומים ידניים לכל קופה
const modeFull = 'full'; // קופת צדקה: 100% למעשר

/// מקור תרומה
const fundBoth = 'both'; // קודם מעשר, השאר מחומש

class Fund {
  String uid;
  String title;
  String role; // maaser / chomesh
  int color;
  int openingBalance;
  String created;
  String modified;
  Fund({required this.uid, required this.title, required this.role, required this.color,
      this.openingBalance = 0, required this.created, required this.modified});

  Map<String, Object?> toRow() => {
        'uid': uid, 'title': title, 'role': role, 'color': color,
        'openingBalance': openingBalance, 'created': created, 'modified': modified,
      };
  static Fund fromRow(Map<String, Object?> r) => Fund(
        uid: r['uid'] as String, title: r['title'] as String, role: r['role'] as String,
        color: r['color'] as int, openingBalance: (r['openingBalance'] as int?) ?? 0,
        created: r['created'] as String, modified: r['modified'] as String);
}

class Category {
  String uid;
  String title;
  String type; // Income / Expense
  String icon; // מפתח לאייקון Material (ראו ui/widgets.dart)
  int color;
  bool full; // קופת צדקה: נכנס במלואו למעשר
  int useCount;
  String? lastUse;
  int position;
  bool isRemoved;
  String created;
  String modified;
  Category({required this.uid, required this.title, required this.type, required this.icon,
      required this.color, this.full = false, this.useCount = 0, this.lastUse, this.position = -1,
      this.isRemoved = false, required this.created, required this.modified});

  Map<String, Object?> toRow() => {
        'uid': uid, 'title': title, 'type': type, 'icon': icon, 'color': color,
        'full': full ? 1 : 0, 'useCount': useCount, 'lastUse': lastUse, 'position': position,
        'isRemoved': isRemoved ? 1 : 0, 'created': created, 'modified': modified,
      };
  static Category fromRow(Map<String, Object?> r) => Category(
        uid: r['uid'] as String, title: r['title'] as String, type: r['type'] as String,
        icon: r['icon'] as String, color: r['color'] as int, full: r['full'] == 1,
        useCount: (r['useCount'] as int?) ?? 0, lastUse: r['lastUse'] as String?,
        position: (r['position'] as int?) ?? -1, isRemoved: r['isRemoved'] == 1,
        created: r['created'] as String, modified: r['modified'] as String);
}

class Split {
  final String fundUid;
  final int amount;
  const Split(this.fundUid, this.amount);
  Map<String, Object?> toJson() => {'f': fundUid, 'a': amount};
  static Split fromJson(Map<String, dynamic> j) => Split(j['f'] as String, j['a'] as int);
}

/// פעולה. הכנסה מחולקת לקופות (splits חיוביים), תרומה יוצאת מקופות (splits = כמה יצא מכל קופה).
class Tx {
  String uid;
  String type;
  int amount; // סה"כ שנכנס לקופות / סכום התרומה
  int? gross; // סכום ההכנסה המלא (אם ידוע)
  String? mode; // להכנסה: auto/manual/full
  String date;
  String comment;
  String categoryUid;
  List<Split> splits;
  String? recurringUid;
  bool isRemoved;
  String created;
  String modified;
  Tx({required this.uid, required this.type, required this.amount, this.gross, this.mode,
      required this.date, this.comment = '', required this.categoryUid, required this.splits,
      this.recurringUid, this.isRemoved = false, required this.created, required this.modified});

  int effectOn(String fundUid) {
    final s = splits.where((x) => x.fundUid == fundUid).fold<int>(0, (a, x) => a + x.amount);
    return type == typeIncome ? s : -s;
  }

  Map<String, Object?> toRow() => {
        'uid': uid, 'type': type, 'amount': amount, 'gross': gross, 'mode': mode, 'date': date,
        'comment': comment, 'categoryUid': categoryUid,
        'splits': jsonEncode(splits.map((s) => s.toJson()).toList()),
        'recurringUid': recurringUid, 'isRemoved': isRemoved ? 1 : 0,
        'created': created, 'modified': modified,
      };
  static Tx fromRow(Map<String, Object?> r) => Tx(
        uid: r['uid'] as String, type: r['type'] as String, amount: r['amount'] as int,
        gross: r['gross'] as int?, mode: r['mode'] as String?, date: r['date'] as String,
        comment: (r['comment'] as String?) ?? '', categoryUid: r['categoryUid'] as String,
        splits: (jsonDecode(r['splits'] as String) as List)
            .map((e) => Split.fromJson(e as Map<String, dynamic>)).toList(),
        recurringUid: r['recurringUid'] as String?, isRemoved: r['isRemoved'] == 1,
        created: r['created'] as String, modified: r['modified'] as String);
}

/// תשלום קבוע. template מתאר את הפעולה שתיווצר בכל מועד.
class Rule {
  String uid;
  bool enabled;
  String freq; // d1 w1 w2 m1 m2 m3 m6 y1
  String startDate;
  String lastDate; // המועד האחרון שבו נוצרה פעולה (כמו lastTransactionDate במקור)
  String? endDate;
  RuleTemplate t;
  String created;
  String modified;
  Rule({required this.uid, this.enabled = true, required this.freq, required this.startDate,
      required this.lastDate, this.endDate, required this.t, required this.created, required this.modified});

  Map<String, Object?> toRow() => {
        'uid': uid, 'enabled': enabled ? 1 : 0, 'freq': freq, 'startDate': startDate,
        'lastDate': lastDate, 'endDate': endDate, 'template': jsonEncode(t.toJson()),
        'created': created, 'modified': modified,
      };
  static Rule fromRow(Map<String, Object?> r) => Rule(
        uid: r['uid'] as String, enabled: r['enabled'] == 1, freq: r['freq'] as String,
        startDate: r['startDate'] as String, lastDate: r['lastDate'] as String,
        endDate: r['endDate'] as String?,
        t: RuleTemplate.fromJson(jsonDecode(r['template'] as String) as Map<String, dynamic>),
        created: r['created'] as String, modified: r['modified'] as String);
}

class RuleTemplate {
  String type;
  String categoryUid;
  int raw; // הכנסה: סכום מלא; תרומה: הסכום
  String? mode; // הכנסה
  String? fund; // תרומה: uid של קופה או 'both'
  Map<String, int>? manual; // הכנסה ידנית: fundUid -> amount
  String comment;
  RuleTemplate({required this.type, required this.categoryUid, required this.raw, this.mode,
      this.fund, this.manual, this.comment = ''});
  Map<String, Object?> toJson() => {
        'type': type, 'categoryUid': categoryUid, 'raw': raw, 'mode': mode, 'fund': fund,
        'manual': manual, 'comment': comment,
      };
  static RuleTemplate fromJson(Map<String, dynamic> j) => RuleTemplate(
        type: j['type'] as String, categoryUid: j['categoryUid'] as String, raw: j['raw'] as int,
        mode: j['mode'] as String?, fund: j['fund'] as String?,
        manual: (j['manual'] as Map?)?.map((k, v) => MapEntry(k as String, v as int)),
        comment: (j['comment'] as String?) ?? '');
}
