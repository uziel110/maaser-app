// הלוגיקה של האפליקציה (מקבילה ל-Bloc של ניהול כספים): טעינה לזיכרון, חישוב יתרות,
// חלוקת הכנסות למעשר/חומש, תרומה משתי הקופות, תשלומים קבועים והשלמת תיאורים.
import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';
import 'models.dart';

const _uuid = Uuid();
String newUid() => _uuid.v4();
String nowIso() => DateTime.now().toUtc().toIso8601String();
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseYmd(String s) => DateTime.parse(s);

enum Period { day, week, month, year, all }

class Store extends ChangeNotifier {
  final Db db = Db();
  List<Fund> funds = [];
  List<Category> cats = [];
  List<Tx> txs = [];
  List<Rule> rules = [];
  double maaserPct = 10, chomeshPct = 10;
  String lastIncomeMode = modeAuto;
  bool loaded = false;

  Future<void> init() async {
    await db.open();
    await reload();
    if (funds.isEmpty) await _seed();
    await runRecurring();
    loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    funds = (await db.all('fund')).map(Fund.fromRow).toList();
    cats = (await db.all('category')).map(Category.fromRow).toList();
    txs = (await db.all('tx')).map(Tx.fromRow).where((t) => !t.isRemoved).toList();
    rules = (await db.all('rule')).map(Rule.fromRow).toList();
    final s = await db.settings();
    maaserPct = double.tryParse(s['maaserPct'] ?? '') ?? 10;
    chomeshPct = double.tryParse(s['chomeshPct'] ?? '') ?? 10;
    lastIncomeMode = s['lastIncomeMode'] ?? modeAuto;
    notifyListeners();
  }

  Future<void> _seed() async {
    final t = nowIso();
    funds = [
      Fund(uid: 'maaser', title: 'מעשר', role: roleMaaser, color: 0xFF9BB68E, created: t, modified: t),
      Fund(uid: 'chomesh', title: 'חומש', role: roleChomesh, color: 0xFFF2B108, created: t, modified: t),
    ];
    cats = [
      Category(uid: newUid(), title: 'משכורת', type: typeIncome, icon: 'work', color: 0xFF2E78CF, created: t, modified: t),
      Category(uid: newUid(), title: 'קופת צדקה', type: typeIncome, icon: 'star', color: 0xFF2E78CF, full: true, created: t, modified: t),
      Category(uid: newUid(), title: 'תרומה', type: typeExpense, icon: 'volunteer', color: 0xFFF63535, created: t, modified: t),
    ];
    for (final f in funds) { await db.put('fund', f.toRow()); }
    for (final c in cats) { await db.put('category', c.toRow()); }
  }

  // ---------- שאילתות ----------
  Fund? fund(String uid) => funds.where((f) => f.uid == uid).firstOrNull;
  Fund? fundByRole(String role) => funds.where((f) => f.role == role).firstOrNull;
  Category? cat(String uid) => cats.where((c) => c.uid == uid).firstOrNull;
  List<Category> catsOf(String type) => cats.where((c) => c.type == type && !c.isRemoved).toList()
    ..sort((a, b) => b.useCount != a.useCount ? b.useCount - a.useCount : a.position - b.position);

  int balance(String fundUid, {Tx? excluding}) {
    final f = fund(fundUid);
    var b = f?.openingBalance ?? 0;
    for (final t in txs) {
      if (excluding != null && t.uid == excluding.uid) continue;
      b += t.effectOn(fundUid);
    }
    return b;
  }

  int totalBalance() => funds.fold<int>(0, (a, f) => a + balance(f.uid));

  (String, String) range(Period p, DateTime ref) {
    final r = DateTime(ref.year, ref.month, ref.day);
    switch (p) {
      case Period.day: return (ymd(r), ymd(r));
      case Period.week:
        final s = r.subtract(Duration(days: r.weekday % 7)); // שבוע מתחיל ביום ראשון
        return (ymd(s), ymd(s.add(const Duration(days: 6))));
      case Period.month: return (ymd(DateTime(r.year, r.month, 1)), ymd(DateTime(r.year, r.month + 1, 0)));
      case Period.year: return ('${r.year}-01-01', '${r.year}-12-31');
      case Period.all: return ('0000-00-00', '9999-12-31');
    }
  }

  DateTime shift(Period p, DateTime ref, int n) {
    switch (p) {
      case Period.day: return ref.add(Duration(days: n));
      case Period.week: return ref.add(Duration(days: 7 * n));
      case Period.month: return DateTime(ref.year, ref.month + n, 1);
      case Period.year: return DateTime(ref.year + n, 1, 1);
      case Period.all: return ref;
    }
  }

  List<Tx> inRange(String a, String b) => txs.where((t) => t.date.compareTo(a) >= 0 && t.date.compareTo(b) <= 0).toList();

  // ---------- חישובי חלוקה ----------
  List<Split> incomeSplits(String kind, int raw, Map<String, int>? manual) {
    final m = fundByRole(roleMaaser), c = fundByRole(roleChomesh);
    if (kind == modeManual) {
      return funds.map((f) => Split(f.uid, manual?[f.uid] ?? 0)).where((s) => s.amount > 0).toList();
    }
    if (raw <= 0 || m == null) return [];
    if (kind == modeFull) return [Split(m.uid, raw)];
    if (kind == modeMaaserOnly) {
      return [Split(m.uid, (raw * 10 / 100).round())];
    }
    final out = <Split>[Split(m.uid, (raw * 10 / 100).round())];
    if (c != null) out.add(Split(c.uid, (raw * 10 / 100).round()));
    return out.where((s) => s.amount > 0).toList();
  }

  /// תרומה משתי הקופות: קודם מהמעשר עד יתרתו, והשאר מהחומש.
  List<Split> bothSplits(int raw, {Tx? excluding}) {
    final m = fundByRole(roleMaaser)!, c = fundByRole(roleChomesh)!;
    final bal = balance(m.uid, excluding: excluding);
    final int avail = bal > 0 ? bal : 0;
    final int fromM = raw < avail ? raw : avail;
    return [if (fromM > 0) Split(m.uid, fromM), if (raw - fromM > 0) Split(c.uid, raw - fromM)];
  }

  List<Split> expenseSplits(String fundSel, int raw, {Tx? excluding}) =>
      fundSel == fundBoth ? bothSplits(raw, excluding: excluding) : [Split(fundSel, raw)];

  // ---------- שמירת פעולות ----------
  Future<void> saveTx(Tx t, {bool isNew = false}) async {
    t.modified = nowIso();
    if (isNew) {
      txs.add(t);
      final c = cat(t.categoryUid);
      if (c != null) { c.useCount++; c.lastUse = t.modified; await db.put('category', c.toRow()); }
    } else {
      final i = txs.indexWhere((x) => x.uid == t.uid);
      if (i >= 0) txs[i] = t;
    }
    await db.put('tx', t.toRow());
    notifyListeners();
  }

  Future<void> deleteTx(Tx t) async {
    t.isRemoved = true;
    t.modified = nowIso();
    txs.removeWhere((x) => x.uid == t.uid);
    await db.put('tx', t.toRow());
    notifyListeners();
  }

  Future<void> setIncomeMode(String m) async {
    lastIncomeMode = m;
    await db.setSetting('lastIncomeMode', m);
  }

  Future<void> setPercents(double m, double c) async {
    maaserPct = m; chomeshPct = c;
    await db.setSetting('maaserPct', '$m');
    await db.setSetting('chomeshPct', '$c');
    notifyListeners();
  }

  Future<void> saveFund(Fund f) async {
    f.modified = nowIso();
    await db.put('fund', f.toRow());
    notifyListeners();
  }

  // ---------- קטגוריות ----------
  Future<Category> saveCategory(Category c) async {
    c.modified = nowIso();
    if (!cats.any((x) => x.uid == c.uid)) cats.add(c);
    await db.put('category', c.toRow());
    notifyListeners();
    return c;
  }

  /// מחיקה עם העברת הפעולות לקטגוריה אחרת (כמו במקור, גרסה 1.9.5).
  Future<void> deleteCategory(Category c, {String? moveTo}) async {
    for (final t in txs.where((t) => t.categoryUid == c.uid).toList()) {
      if (moveTo != null) { t.categoryUid = moveTo; await saveTx(t); }
    }
    c.isRemoved = true;
    await saveCategory(c);
  }

  // ---------- השלמת תיאורים (כמו "SELECT comment, COUNT(*) ... GROUP BY comment") ----------
  List<String> suggestions(String type, String? categoryUid, String query) {
    final q = query.trim().toLowerCase();
    final map = <String, (String, int, int)>{};
    for (final t in txs) {
      final c = t.comment.trim();
      if (c.isEmpty || t.type != type) continue;
      final k = c.toLowerCase();
      final e = map[k] ?? (c, 0, 0);
      map[k] = (e.$1, e.$2 + 1, e.$3 + (t.categoryUid == categoryUid ? 1 : 0));
    }
    final list = map.entries.where((e) => e.key != q && (q.isEmpty || e.key.contains(q))).map((e) => e.value).toList()
      ..sort((a, b) => b.$3 != a.$3 ? b.$3 - a.$3 : b.$2 - a.$2);
    return list.take(6).map((e) => e.$1).toList();
  }

  // ---------- תשלומים קבועים ----------
  static const freqs = {
    'd1': 'כל יום', 'w1': 'כל שבוע', 'w2': 'כל שבועיים', 'm1': 'כל חודש',
    'm2': 'כל חודשיים', 'm3': 'כל רבעון', 'm6': 'כל חצי שנה', 'y1': 'כל שנה',
  };

  /// המועד הבא. בחודשים שומרים את יום החודש של תאריך ההתחלה (ובחודש קצר – היום האחרון).
  static String nextDate(String last, String freq, String anchor) {
    final u = freq[0], n = int.parse(freq.substring(1));
    final d = parseYmd(last);
    if (u == 'd') return ymd(d.add(Duration(days: n)));
    if (u == 'w') return ymd(d.add(Duration(days: 7 * n)));
    final months = u == 'm' ? n : 12 * n;
    final y = d.year, mo = d.month + months;
    final end = DateTime(y, mo + 1, 0).day;
    final day = parseYmd(anchor).day;
    return ymd(DateTime(y, mo, day < end ? day : end));
  }

  String ruleNext(Rule r) => nextDate(r.lastDate, r.freq, r.startDate);

  Tx? _fromRule(Rule r, String date) {
    final c = cat(r.t.categoryUid);
    if (c == null || c.isRemoved) return null;
    final t0 = nowIso();
    if (r.t.type == typeExpense) {
      final sel = r.t.fund == fundBoth ? fundBoth : (fund(r.t.fund ?? '')?.uid ?? fundByRole(roleMaaser)!.uid);
      return Tx(uid: newUid(), type: typeExpense, amount: r.t.raw, date: date, comment: r.t.comment,
          categoryUid: c.uid, splits: expenseSplits(sel, r.t.raw), recurringUid: r.uid, created: t0, modified: t0);
    }
    final kind = c.full ? modeFull : (r.t.mode == modeManual ? modeManual : modeAuto);
    final sp = incomeSplits(kind, r.t.raw, r.t.manual);
    if (sp.isEmpty) return null;
    return Tx(uid: newUid(), type: typeIncome, amount: sp.fold<int>(0, (a, s) => a + s.amount),
        gross: (kind == modeAuto || (kind == modeManual && r.t.raw > 0)) ? r.t.raw : null, mode: kind,
        date: date, comment: r.t.comment, categoryUid: c.uid, splits: sp, recurringUid: r.uid, created: t0, modified: t0);
  }

  /// נקרא בפתיחת האפליקציה ואחרי שינויים: יוצר את כל המופעים שהגיע זמנם.
  Future<int> runRecurring() async {
    final today = ymd(DateTime.now());
    var added = 0;
    for (final r in rules) {
      if (!r.enabled) continue;
      var d = ruleNext(r);
      var guard = 0;
      while (d.compareTo(today) <= 0 && (r.endDate == null || d.compareTo(r.endDate!) <= 0) && guard++ < 1000) {
        final t = _fromRule(r, d);
        if (t == null) { r.enabled = false; break; }
        await saveTx(t, isNew: true);
        r.lastDate = d;
        added++;
        d = ruleNext(r);
      }
      await db.put('rule', r.toRow());
    }
    if (added > 0) notifyListeners();
    return added;
  }

  Future<void> saveRule(Rule r) async {
    r.modified = nowIso();
    if (!rules.any((x) => x.uid == r.uid)) rules.add(r);
    await db.put('rule', r.toRow());
    notifyListeners();
  }

  Future<void> deleteRule(Rule r) async {
    rules.removeWhere((x) => x.uid == r.uid);
    await db.remove('rule', r.uid);
    notifyListeners();
  }

  // ---------- ייבוא מאפליקציית ה-HTML (maaser-data.json / גיבוי JSON) ----------
  Future<int> importHtmlJson(String text) async {
    final d = jsonDecode(text) as Map<String, dynamic>;
    if (d['app'] != 'maaser-tracker') throw const FormatException('לא קובץ של קופת מעשר');
    final t0 = nowIso();
    int col(Object? v, int def) {
      if (v is String && v.startsWith('#') && v.length == 7) return 0xFF000000 | int.parse(v.substring(1), radix: 16);
      return def;
    }
    final fs = <Fund>[];
    for (final a in (d['accounts'] as List)) {
      final role = a['role'];
      if (role != roleMaaser && role != roleChomesh) continue; // קופות נפרדות לא רלוונטיות
      fs.add(Fund(uid: a['uid'], title: a['title'], role: role, color: col(a['color'], 0xFF9BB68E),
          openingBalance: (a['openingBalance'] ?? 0) as int, created: a['created'] ?? t0, modified: t0));
    }
    final fundIds = fs.map((f) => f.uid).toSet();
    final cs = <Category>[];
    for (final c in (d['categories'] as List)) {
      if (c['space'] != null) continue;
      cs.add(Category(uid: c['uid'], title: c['title'], type: c['type'] == 'Charity' ? typeIncome : c['type'],
          icon: (c['icon'] ?? 'other') as String, color: col(c['color'], 0xFF2E78CF),
          full: c['full'] == true || c['type'] == 'Charity', useCount: (c['useCount'] ?? 0) as int,
          created: c['created'] ?? t0, modified: t0));
    }
    final xs = <Tx>[];
    for (final t in (d['transactions'] as List)) {
      final List<Split> sp;
      if (t['splits'] != null) {
        sp = (t['splits'] as List).map((s) => Split(s['accountUid'], s['amount'] as int)).toList();
      } else {
        sp = [Split(t['accountUid'], t['amount'] as int)];
      }
      if (!sp.every((s) => fundIds.contains(s.fundUid))) continue;
      xs.add(Tx(uid: t['uid'], type: t['type'] == 'Charity' ? typeIncome : t['type'], amount: t['amount'] as int,
          gross: t['gross'] as int?, mode: t['mode'] as String?, date: t['date'], comment: (t['comment'] ?? '') as String,
          categoryUid: t['categoryUid'], splits: sp, recurringUid: t['recurringUid'] as String?,
          created: t['created'] ?? t0, modified: t0));
    }
    final rs = <Rule>[];
    for (final r in (d['recurring'] as List? ?? [])) {
      final tp = r['template'];
      rs.add(Rule(uid: r['uid'], enabled: r['enabled'] == true, freq: r['freq'], startDate: r['startDate'],
          lastDate: r['lastDate'], endDate: (r['endDate'] as String?)?.isEmpty == true ? null : r['endDate'],
          t: RuleTemplate(type: tp['type'], categoryUid: tp['categoryUid'], raw: tp['raw'] as int,
              mode: tp['mode'], fund: tp['fund'], comment: (tp['comment'] ?? '') as String,
              manual: (tp['manual'] as Map?)?.map((k, v) => MapEntry(k as String, v as int))),
          created: r['created'] ?? t0, modified: t0));
    }
    final st = d['settings'] as Map<String, dynamic>? ?? {};
    await db.replaceAll(funds: fs, cats: cs, txs: xs, rules: rs, settings: {
      'maaserPct': '${st['maaserPct'] ?? 10}', 'chomeshPct': '${st['chomeshPct'] ?? 10}',
      'lastIncomeMode': '${st['lastIncomeMode'] ?? modeAuto}',
    });
    await reload();
    await runRecurring();
    return xs.length;
  }
}
