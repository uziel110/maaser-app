import 'package:flutter/material.dart' hide Split;
import 'package:provider/provider.dart';
import '../models.dart';
import '../store.dart';
import 'manage.dart';
import 'widgets.dart';

/// מסך הוספה/עריכה. הכנסה: אוטומטית (אחוזים) / ידנית / קופת צדקה (100% למעשר).
/// תרומה: ממעשר / מחומש / משתיהן (קודם מעשר). אפשר להגדיר חזרה (תשלום קבוע).
class EditTxScreen extends StatefulWidget {
  final Tx? editing;
  final String initialType;
  final String? initialFund;
  const EditTxScreen({super.key, this.editing, this.initialType = typeIncome, this.initialFund});
  @override
  State<EditTxScreen> createState() => _EditTxScreenState();
}

class _EditTxScreenState extends State<EditTxScreen> {
  late String type;
  String? catUid;
  late String mode;
  late String fundSel;
  late String date;
  final amount = TextEditingController();
  final desc = TextEditingController();
  final manual = <String, TextEditingController>{};
  String repeat = 'none';
  String? repeatEnd;
  String? error;

  Store get s => Provider.of<Store>(context, listen: false);

  @override
  void initState() {
    super.initState();
    final st = context.read<Store>();
    final t = widget.editing;
    type = t?.type ?? widget.initialType;
    catUid = t?.categoryUid;
    mode = (t?.mode == modeAuto || t?.mode == modeManual) ? t!.mode! : st.lastIncomeMode;
    date = t?.date ?? ymd(DateTime.now());
    desc.text = t?.comment ?? '';
    for (final f in st.funds) {
      final v = t != null && t.type == typeIncome ? t.splits.where((x) => x.fundUid == f.uid).fold<int>(0, (a, x) => a + x.amount) : 0;
      manual[f.uid] = TextEditingController(text: v > 0 ? (v / 100).toString() : '');
    }
    if (t != null) {
      final shown = t.type == typeIncome ? (t.mode == modeManual ? t.gross : (t.gross ?? t.amount)) : t.amount;
      amount.text = shown == null ? '' : (shown / 100).toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
      fundSel = t.type == typeExpense ? (t.splits.length > 1 ? fundBoth : t.splits.first.fundUid) : st.fundByRole(roleMaaser)!.uid;
    } else {
      fundSel = widget.initialFund ?? st.fundByRole(roleMaaser)!.uid;
    }
    catUid ??= st.catsOf(type).firstOrNull?.uid;
    amount.addListener(() => setState(() {}));
    desc.addListener(() => setState(() {}));
  }

  String get kind {
    if (type == typeExpense) return 'expense';
    return s.cat(catUid ?? '')?.full == true ? modeFull : mode;
  }

  List<Split> preview() {
    final raw = parseAmount(amount.text) ?? 0;
    if (kind == 'expense') {
      if (raw <= 0) return [];
      return s.expenseSplits(fundSel, raw, excluding: widget.editing);
    }
    return s.incomeSplits(kind, raw, {for (final e in manual.entries) e.key: parseAmount(e.value.text) ?? 0});
  }

  Future<void> save() async {
    final c = s.cat(catUid ?? '');
    if (c == null) { setState(() => error = 'יש לבחור קטגוריה או ליצור חדשה.'); return; }
    final raw = parseAmount(amount.text);
    if (kind != modeManual && (raw == null || raw <= 0)) { setState(() => error = 'יש להזין סכום גדול מאפס.'); return; }
    final sp = preview();
    if (sp.isEmpty) { setState(() => error = kind == modeManual ? 'יש להזין סכום לפחות לקופה אחת.' : 'לא ניתן לחשב חלוקה.'); return; }
    final t0 = nowIso();
    final old = widget.editing;
    final t = Tx(
      uid: old?.uid ?? newUid(), type: type, amount: type == typeExpense ? raw! : sp.fold<int>(0, (a, x) => a + x.amount),
      gross: type == typeIncome && (kind == modeAuto || (kind == modeManual && (raw ?? 0) > 0)) ? raw : null,
      mode: type == typeIncome ? kind : null, date: date, comment: desc.text.trim(), categoryUid: c.uid, splits: sp,
      recurringUid: old?.recurringUid, created: old?.created ?? t0, modified: t0,
    );
    if (type == typeIncome && (kind == modeAuto || kind == modeManual)) await s.setIncomeMode(kind);
    if (old == null && repeat != 'none') {
      final r = Rule(uid: newUid(), freq: repeat, startDate: date, lastDate: date, endDate: repeatEnd,
          t: RuleTemplate(type: type, categoryUid: c.uid, raw: raw ?? 0, mode: type == typeIncome ? kind : null,
              fund: type == typeExpense ? fundSel : null,
              manual: kind == modeManual ? {for (final e in manual.entries) e.key: parseAmount(e.value.text) ?? 0} : null,
              comment: t.comment),
          created: t0, modified: t0);
      t.recurringUid = r.uid;
      await s.saveRule(r);
    }
    await s.saveTx(t, isNew: old == null);
    await s.runRecurring();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<Store>();
    final cats = st.catsOf(type);
    final sp = preview();
    final sugs = st.suggestions(type, catUid, desc.text);
    final editingRule = widget.editing?.recurringUid != null ? st.rules.where((r) => r.uid == widget.editing!.recurringUid).firstOrNull : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'פעולה חדשה' : 'עריכת פעולה'),
        actions: [
          if (widget.editing != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
              final ok = await confirm(context, 'למחוק את הפעולה?');
              if (ok) { await st.deleteTx(widget.editing!); if (context.mounted) Navigator.pop(context); }
            }),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: typeIncome, label: Text('הכנסה')), ButtonSegment(value: typeExpense, label: Text('תרומה'))],
          selected: {type},
          onSelectionChanged: widget.editing != null ? null : (v) => setState(() { type = v.first; catUid = st.catsOf(type).firstOrNull?.uid; }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          decoration: InputDecoration(prefixText: '₪ ', labelText: switch (kind) {
            modeFull => 'הסכום שנאסף',
            modeAuto => 'סכום ההכנסה המלא',
            modeManual => 'סכום ההכנסה המלא (לא חובה)',
            _ => 'סכום התרומה',
          }),
        ),
        if (type == typeIncome && kind != modeFull)
          Wrap(spacing: 8, children: [
            ChoiceChip(label: Text('אוטומטית: ${st.maaserPct.toStringAsFixed(0)}% מעשר + ${st.chomeshPct.toStringAsFixed(0)}% חומש'),
                selected: mode == modeAuto, onSelected: (_) => setState(() => mode = modeAuto)),
            ChoiceChip(label: const Text('הזנה ידנית'), selected: mode == modeManual, onSelected: (_) => setState(() => mode = modeManual)),
          ]),
        const _H('קטגוריה'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in cats)
            InkWell(
              onTap: () => setState(() => catUid = c.uid),
              child: SizedBox(width: 76, child: Column(children: [
                Container(
                  decoration: c.uid == catUid ? BoxDecoration(shape: BoxShape.circle, border: Border.all(width: 3)) : null,
                  padding: const EdgeInsets.all(2), child: CatIcon(c, size: 46)),
                Text(c.title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12)),
                if (c.full) const Text('100% למעשר', style: TextStyle(fontSize: 10, color: Color(0xFFA87B00))),
              ])),
            ),
          InkWell(
            onTap: () async {
              final c = await editCategory(context, null, type);
              if (c != null) setState(() => catUid = c.uid);
            },
            child: const SizedBox(width: 76, child: Column(children: [
              CircleAvatar(radius: 25, child: Icon(Icons.add)), Text('חדשה', style: TextStyle(fontSize: 12)),
            ])),
          ),
        ]),
        if (type == typeIncome) ...[
          _H(kind == modeManual ? 'כמה נכנס לכל קופה' : 'חלוקה לקופות'),
          for (final f in st.funds)
            ListTile(
              dense: true,
              leading: CircleAvatar(backgroundColor: Color(f.color), radius: 14),
              title: Text(f.title),
              trailing: kind == modeManual
                  ? SizedBox(width: 120, child: TextField(controller: manual[f.uid], textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})))
                  : Text(fmt(sp.where((x) => x.fundUid == f.uid).fold<int>(0, (a, x) => a + x.amount)), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (kind == modeFull) const Text('קופת צדקה היא הכנסה שנכנסת במלואה לקופת המעשר.', style: TextStyle(color: Color(0xFFA87B00))),
        ] else ...[
          const _H('מאיזו קופה'),
          for (final o in [...st.funds.map((f) => (f.uid, f.title, st.balance(f.uid))),
            if (st.fundByRole(roleMaaser) != null && st.fundByRole(roleChomesh) != null)
              (fundBoth, 'משתיהן: קודם מעשר, השאר מחומש', st.totalBalance())])
            RadioListTile<String>(
              value: o.$1, groupValue: fundSel, onChanged: (v) => setState(() => fundSel = v!),
              title: Text(o.$2), secondary: Text(fmt(o.$3)),
            ),
          if (fundSel == fundBoth && sp.isNotEmpty)
            Text(sp.map((x) => 'מ${st.fund(x.fundUid)?.title} ${fmt(x.amount)}').join(', '), style: const TextStyle(color: Color(0xFFA87B00))),
        ],
        const _H('תאריך'),
        Wrap(spacing: 8, children: [
          for (final (l, d) in [('היום', 0), ('אתמול', 1), ('שלשום', 2)])
            ChoiceChip(label: Text(l), selected: date == ymd(DateTime.now().subtract(Duration(days: d))),
                onSelected: (_) => setState(() => date = ymd(DateTime.now().subtract(Duration(days: d))))),
          ActionChip(avatar: const Icon(Icons.calendar_today, size: 16), label: Text(dmy(date)), onPressed: () async {
            final p = await showDatePicker(context: context, initialDate: parseYmd(date), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (p != null) setState(() => date = ymd(p));
          }),
        ]),
        const _H('תיאור'),
        TextField(controller: desc, decoration: const InputDecoration(hintText: 'למשל: ישיבה, בית כנסת, ויברך')),
        Wrap(spacing: 6, children: [
          for (final x in sugs) ActionChip(label: Text(x), onPressed: () => setState(() => desc.text = x)),
        ]),
        const _H('חזרה'),
        if (widget.editing == null) ...[
          DropdownButton<String>(
            value: repeat, isExpanded: true,
            items: [const DropdownMenuItem(value: 'none', child: Text('לא חוזר')),
              for (final e in Store.freqs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => repeat = v!),
          ),
          if (repeat != 'none') ...[
            ListTile(
              title: Text(repeatEnd == null ? 'בלי תאריך סיום' : 'עד ${dmy(repeatEnd!)}'),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final p = await showDatePicker(context: context, initialDate: parseYmd(date), firstDate: parseYmd(date), lastDate: DateTime(2100));
                setState(() => repeatEnd = p == null ? null : ymd(p));
              },
            ),
            Text('${date.compareTo(ymd(DateTime.now())) < 0 ? 'פעולות שהיו צריכות להירשם מאז ${dmy(date)} יירשמו מיד. ' : ''}'
                'הפעולה תירשם אוטומטית ${Store.freqs[repeat]}. הפעם הבאה: ${dmy(Store.nextDate(date, repeat, date))}.',
                style: const TextStyle(color: Colors.black54)),
          ],
        ] else
          Text(editingRule != null
              ? 'נוצר מתשלום קבוע (${Store.freqs[editingRule.freq]}). שינוי כאן משפיע רק על הפעולה הזו.'
              : 'פעולה חד־פעמית.', style: const TextStyle(color: Colors.black54)),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        FilledButton(onPressed: save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(widget.editing == null ? 'הוספה' : 'שמירת שינויים')),
      ]),
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
      );
}
