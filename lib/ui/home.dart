import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../models.dart';
import '../store.dart';
import 'edit_tx.dart';
import 'manage.dart';
import 'widgets.dart';

const tabIncome = 'Income';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String tab = tabIncome;
  Period period = Period.month;
  DateTime ref = DateTime.now();
  bool listMode = false;
  String? catFilter;

  String periodLabel(Store s) {
    final (a, b) = s.range(period, ref);
    switch (period) {
      case Period.day: return DateFormat('EEEE, d בMMMM y', 'he').format(ref);
      case Period.week: return '${dmy(a)} – ${dmy(b)}';
      case Period.month: return DateFormat('MMMM y', 'he').format(ref);
      case Period.year: return '${ref.year}';
      case Period.all: return 'כל הזמן';
    }
  }

  /// value לתרשים: בהכנסות – הסכום המלא; בקופה – כמה יצא ממנה.
  List<(Tx, int)> chartItems(Store s, List<Tx> inRange) {
    if (tab == tabIncome) {
      return inRange.where((t) => t.type == typeIncome).map((t) => (t, t.gross ?? t.amount)).toList();
    }
    return inRange.where((t) => t.type == typeExpense && t.effectOn(tab) < 0).map((t) => (t, -t.effectOn(tab))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    if (s.fund(tab) == null) tab = tabIncome;
    final (a, b) = s.range(period, ref);
    final inRange = s.inRange(a, b);
    final items = chartItems(s, inRange);
    final groups = <String, (int, int)>{};
    for (final (t, v) in items) {
      final g = groups[t.categoryUid] ?? (0, 0);
      groups[t.categoryUid] = (g.$1 + v, g.$2 + 1);
    }
    final sorted = groups.entries.toList()..sort((x, y) => y.value.$1 - x.value.$1);
    final total = sorted.fold<int>(0, (acc, e) => acc + e.value.$1);
    final f = s.fund(tab);
    final tabs = [tabIncome, ...s.funds.map((f) => f.uid)];

    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        centerTitle: true,
        title: Column(children: [
          Text(f?.title ?? 'מעשר וחומש', style: const TextStyle(fontSize: 13, color: Colors.white70)),
          Text(fmt(f == null ? s.totalBalance() : s.balance(f.uid)),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            icon: Icon(listMode ? Icons.donut_large : Icons.list),
            onPressed: () => setState(() { listMode = !listMode; catFilter = null; }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Row(children: [
            for (final t in tabs)
              Expanded(child: InkWell(
                onTap: () => setState(() { tab = t; catFilter = null; }),
                child: Container(
                  height: 46, alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(
                      color: t == tab ? const Color(0xFFF2B108) : Colors.transparent, width: 3))),
                  child: Text(t == tabIncome ? 'הכנסות' : s.fund(t)!.title,
                      style: TextStyle(color: Colors.white.withOpacity(t == tab ? 1 : .7), fontWeight: FontWeight.w500)),
                ),
              )),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF2B108),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTxScreen(
            initialType: tab == tabIncome ? typeIncome : typeExpense, initialFund: tab == tabIncome ? null : tab))),
        child: const Icon(Icons.add, size: 30),
      ),
      body: GestureDetector(
        // גרירה ימינה = תקופה הבאה, שמאלה = קודמת (כיוון קריאה בעברית)
        onHorizontalDragEnd: period == Period.all ? null : (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 250) return;
          setState(() => ref = s.shift(period, ref, v > 0 ? 1 : -1));
        },
        child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          Card(
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final (p, l) in [(Period.day, 'יום'), (Period.week, 'שבוע'), (Period.month, 'חודש'), (Period.year, 'שנה'), (Period.all, 'הכול')])
                  TextButton(
                    onPressed: () => setState(() { period = p; ref = DateTime.now(); }),
                    child: Text(l, style: TextStyle(fontWeight: p == period ? FontWeight.bold : FontWeight.normal,
                        color: p == period ? Colors.black : Colors.black54)),
                  ),
              ]),
              Row(children: [
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: period == Period.all ? null : () => setState(() => ref = s.shift(period, ref, 1))),
                Expanded(child: Text(periodLabel(s), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500))),
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: period == Period.all ? null : () => setState(() => ref = s.shift(period, ref, -1))),
              ]),
              Donut(
                slices: [for (final e in sorted) DonutSlice(e.value.$1.toDouble(), Color(s.cat(e.key)?.color ?? 0xFF999999))],
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tab == tabIncome ? 'סה״כ הכנסות' : 'נתרם', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  Text(fmt(total), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: tab == tabIncome ? const Color(0xFF2E8B57) : const Color(0xFFD8433A))),
                  Text('${items.length} פעולות', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
              ),
              const Divider(),
              _SummaryRow(store: s, tab: tab, inRange: inRange),
            ])),
          ),
          if (!listMode)
            for (final e in sorted)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CatIcon(s.cat(e.key)),
                  title: Row(children: [
                    Flexible(child: Text(s.cat(e.key)?.title ?? 'ללא קטגוריה')),
                    if (s.cat(e.key)?.full == true) const _Badge('100% למעשר'),
                  ]),
                  subtitle: Text('${(e.value.$1 * 100 / (total == 0 ? 1 : total)).round()}% · ${e.value.$2} פעולות'),
                  trailing: Text(fmt(e.value.$1), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => setState(() { listMode = true; catFilter = e.key; }),
                ),
              )
          else
            ..._txList(context, s, inRange),
          if (items.isEmpty && !listMode)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('אין פעולות בתקופה הזו.'))),
        ]),
      ),
    );
  }

  List<Widget> _txList(BuildContext context, Store s, List<Tx> inRange) {
    var rows = tab == tabIncome
        ? inRange.where((t) => t.type == typeIncome).toList()
        : inRange.where((t) => t.effectOn(tab) != 0).toList();
    if (catFilter != null) rows = rows.where((t) => t.categoryUid == catFilter).toList();
    rows.sort((x, y) => y.date != x.date ? y.date.compareTo(x.date) : y.created.compareTo(x.created));
    final out = <Widget>[];
    if (catFilter != null) {
      out.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(label: Text(s.cat(catFilter!)?.title ?? ''), onDeleted: () => setState(() => catFilter = null)),
      )));
    }
    String? day;
    for (final t in rows) {
      if (t.date != day) {
        day = t.date;
        out.add(Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(DateFormat('EEEE, d בMMMM y', 'he').format(parseYmd(t.date)), style: const TextStyle(color: Colors.black54))));
      }
      final c = s.cat(t.categoryUid);
      final v = tab == tabIncome ? (t.gross ?? t.amount) : t.effectOn(tab).abs();
      final neg = tab != tabIncome && t.effectOn(tab) < 0;
      final parts = <String>[
        if (t.recurringUid != null) '🔁',
        if (t.comment.isNotEmpty) t.comment,
        if (t.splits.length > 1 || tab == tabIncome)
          t.splits.map((x) => '${s.fund(x.fundUid)?.title ?? '?'} ${fmt(x.amount)}').join(' · '),
      ];
      out.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: ListTile(
          leading: CatIcon(c),
          title: Text(c?.title ?? 'ללא קטגוריה'),
          subtitle: Text(parts.isEmpty ? '—' : parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text('${neg ? '-' : '+'}${fmt(v)}', textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w600, color: neg ? const Color(0xFFD8433A) : (c?.full == true ? const Color(0xFFA87B00) : const Color(0xFF2E8B57)))),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditTxScreen(editing: t))),
        ),
      ));
    }
    if (rows.isEmpty) out.add(const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('אין פעולות בתקופה הזו.'))));
    return out;
  }
}

class _SummaryRow extends StatelessWidget {
  final Store store;
  final String tab;
  final List<Tx> inRange;
  const _SummaryRow({required this.store, required this.tab, required this.inRange});
  @override
  Widget build(BuildContext context) {
    final List<(String, int)> cells;
    if (tab == tabIncome) {
      int to(String role) {
        final f = store.fundByRole(role);
        return f == null ? 0 : inRange.where((t) => t.type == typeIncome).fold<int>(0, (a, t) => a + t.effectOn(f.uid));
      }
      cells = [('למעשר', to(roleMaaser)), ('לחומש', to(roleChomesh))];
    } else {
      final inn = inRange.where((t) => t.type == typeIncome).fold<int>(0, (a, t) => a + t.effectOn(tab));
      final out = inRange.where((t) => t.type == typeExpense).fold<int>(0, (a, t) => a - t.effectOn(tab));
      cells = [('נכנס', inn), ('נתרם', out), ('יתרה עכשיו', store.balance(tab))];
    }
    return Row(children: [
      for (final (l, v) in cells)
        Expanded(child: Column(children: [
          Text(l, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(fmt(v), style: const TextStyle(fontWeight: FontWeight.w600)),
        ])),
    ]);
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsetsDirectional.only(start: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CC), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFFA87B00))),
      );
}
