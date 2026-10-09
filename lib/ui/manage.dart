import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../backup.dart';
import '../cloud_backup.dart';
import '../models.dart';
import '../store.dart';
import 'widgets.dart';

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('אישור'))],
    )) ?? false;

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    void go(Widget w) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => w));
    }
    return Drawer(child: ListView(children: [
      DrawerHeader(
        decoration: const BoxDecoration(color: Color(0xFF1F4E5A)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
          const Text('קופת מעשר', style: TextStyle(color: Colors.white, fontSize: 22)),
          Text('${s.txs.length} פעולות · יתרה ${fmt(s.totalBalance())}', style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      ListTile(leading: const Icon(Icons.account_balance_wallet), title: const Text('קופות ויתרות פתיחה'), onTap: () => go(const FundsScreen())),
      ListTile(leading: const Icon(Icons.percent), title: const Text('חלוקת הכנסות'),
          subtitle: Text('מעשר ${s.maaserPct.toStringAsFixed(0)}% + חומש ${s.chomeshPct.toStringAsFixed(0)}%'), onTap: () => go(const PercentScreen())),
      ListTile(leading: const Icon(Icons.category), title: const Text('קטגוריות הכנסות'), onTap: () => go(const CategoriesScreen(type: typeIncome))),
      ListTile(leading: const Icon(Icons.category_outlined), title: const Text('קטגוריות תרומות'), onTap: () => go(const CategoriesScreen(type: typeExpense))),
      ListTile(leading: const Icon(Icons.repeat), title: const Text('תשלומים קבועים'),
          subtitle: Text('${s.rules.where((r) => r.enabled).length} פעילים'), onTap: () => go(const RecurringScreen())),
      const Divider(),
      ListTile(leading: const Icon(Icons.backup), title: const Text('גיבוי ושחזור'), onTap: () => go(const BackupScreen())),
    ]));
  }
}

// ---------- קטגוריות ----------
Future<Category?> editCategory(BuildContext context, Category? c, String type) async {
  final s = context.read<Store>();
  final name = TextEditingController(text: c?.title ?? '');
  var color = c?.color ?? palette[s.cats.length % palette.length];
  var icon = c?.icon ?? (type == typeExpense ? 'volunteer' : 'money');
  var full = c?.full ?? false;
  final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
    title: Text(c == null ? 'קטגוריה חדשה' : 'עריכת קטגוריה'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'שם')),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in palette) GestureDetector(onTap: () => set(() => color = p), child: CircleAvatar(radius: 14, backgroundColor: Color(p),
            child: p == color ? const Icon(Icons.check, size: 16, color: Colors.white) : null)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (final k in iconChoices) IconButton.filledTonal(isSelected: k == icon, onPressed: () => set(() => icon = k), icon: Icon(iconMap[k])),
      ]),
      if (type == typeIncome)
        CheckboxListTile(value: full, onChanged: (v) => set(() => full = v ?? false), contentPadding: EdgeInsets.zero,
            title: const Text('כמו קופת צדקה: כל הסכום נכנס במלואו למעשר')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('שמירה'))],
  )));
  if (ok != true || name.text.trim().isEmpty) return null;
  final t = nowIso();
  final cat = c ?? Category(uid: newUid(), title: '', type: type, icon: icon, color: color, created: t, modified: t);
  cat..title = name.text.trim()..icon = icon..color = color..full = type == typeIncome && full;
  return s.saveCategory(cat);
}

class CategoriesScreen extends StatelessWidget {
  final String type;
  const CategoriesScreen({super.key, required this.type});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final list = s.catsOf(type);
    return Scaffold(
      appBar: AppBar(title: Text(type == typeIncome ? 'קטגוריות הכנסות' : 'קטגוריות תרומות')),
      floatingActionButton: FloatingActionButton(onPressed: () => editCategory(context, null, type), child: const Icon(Icons.add)),
      body: ListView(children: [
        for (final c in list)
          ListTile(
            leading: CatIcon(c), title: Text(c.title + (c.full ? ' · 100% למעשר' : '')),
            subtitle: Text('${s.txs.where((t) => t.categoryUid == c.uid).length} פעולות'),
            onTap: () => editCategory(context, c, type),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
              final others = list.where((x) => x.uid != c.uid).toList();
              final used = s.txs.any((t) => t.categoryUid == c.uid);
              String? moveTo;
              if (used) {
                if (others.isEmpty) { toast(context, 'יש פעולות בקטגוריה, ואין קטגוריה אחרת להעביר אליה.'); return; }
                moveTo = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(
                  title: const Text('לאיזו קטגוריה להעביר את הפעולות?'),
                  children: [for (final o in others) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o.uid), child: Text(o.title))],
                ));
                if (moveTo == null) return;
              } else if (!await confirm(context, 'למחוק את הקטגוריה "${c.title}"?')) {
                return;
              }
              await s.deleteCategory(c, moveTo: moveTo);
            }),
          ),
      ]),
    );
  }
}

// ---------- קופות ואחוזים ----------
class FundsScreen extends StatelessWidget {
  const FundsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('קופות')),
      body: ListView(children: [
        for (final f in s.funds)
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(f.color)),
            title: Text(f.title), subtitle: Text('יתרת פתיחה ${fmt(f.openingBalance)}'),
            trailing: Text(fmt(s.balance(f.uid)), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () async {
              final name = TextEditingController(text: f.title);
              final open = TextEditingController(text: (f.openingBalance / 100).toString());
              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                title: const Text('עריכת קופה'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'שם')),
                  TextField(controller: open, textDirection: TextDirection.ltr, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'יתרת פתיחה')),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ביטול')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('שמירה'))],
              ));
              if (ok != true) return;
              final t = open.text.trim();
              final neg = t.startsWith('-');
              final v = parseAmount(neg ? t.substring(1) : t) ?? 0;
              if (name.text.trim().isNotEmpty) f.title = name.text.trim();
              f.openingBalance = neg ? -v : v;
              await s.saveFund(f);
            },
          ),
      ]),
    );
  }
}

class PercentScreen extends StatefulWidget {
  const PercentScreen({super.key});
  @override
  State<PercentScreen> createState() => _PercentScreenState();
}

class _PercentScreenState extends State<PercentScreen> {
  late final m = TextEditingController(text: context.read<Store>().maaserPct.toString());
  late final c = TextEditingController(text: context.read<Store>().chomeshPct.toString());
  @override
  Widget build(BuildContext context) {
    final mv = double.tryParse(m.text) ?? 0, cv = double.tryParse(c.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('חלוקת הכנסות')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('בחלוקה אוטומטית, מכל הכנסה מלאה נכנס האחוז הזה לכל קופה. פעולות קיימות לא משתנות.'),
        TextField(controller: m, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'מעשר %'), onChanged: (_) => setState(() {})),
        TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'חומש (בנוסף למעשר) %'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Text('מהכנסה של ₪1,000: ${fmt((100000 * mv / 100).round())} למעשר ו־${fmt((100000 * cv / 100).round())} לחומש.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: mv < 0 || cv < 0 || mv + cv > 100 ? null : () async {
          await context.read<Store>().setPercents(mv, cv);
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('שמירה')),
      ]),
    );
  }
}

// ---------- תשלומים קבועים ----------
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('תשלומים קבועים')),
      body: s.rules.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Text('אין עדיין תשלומים קבועים. כדי ליצור, מוסיפים פעולה ובוחרים בה "חזרה".'))
          : ListView(children: [
              for (final r in s.rules)
                ListTile(
                  leading: CatIcon(s.cat(r.t.categoryUid)),
                  title: Text('${s.cat(r.t.categoryUid)?.title ?? ''}${r.t.comment.isEmpty ? '' : ' · ${r.t.comment}'}'),
                  subtitle: Text('${Store.freqs[r.freq]} · ${!r.enabled ? 'מושהה' : (r.endDate != null && s.ruleNext(r).compareTo(r.endDate!) > 0) ? 'הסתיים' : 'הבא: ${dmy(s.ruleNext(r))}'}'),
                  trailing: Text('${r.t.type == typeExpense ? '-' : '+'}${fmt(r.t.raw)}', textDirection: TextDirection.ltr),
                  onTap: () => _editRule(context, r),
                ),
            ]),
    );
  }

  Future<void> _editRule(BuildContext context, Rule r) async {
    final s = context.read<Store>();
    final amount = TextEditingController(text: (r.t.raw / 100).toString());
    final comment = TextEditingController(text: r.t.comment);
    var freq = r.freq, enabled = r.enabled;
    String? end = r.endDate;
    final res = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('תשלום קבוע'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amount, textDirection: TextDirection.ltr, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: r.t.type == typeIncome ? 'סכום ההכנסה המלא' : 'סכום')),
        TextField(controller: comment, decoration: const InputDecoration(labelText: 'תיאור')),
        DropdownButton<String>(value: freq, isExpanded: true,
            items: [for (final e in Store.freqs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => freq = v!)),
        ListTile(contentPadding: EdgeInsets.zero, title: Text(end == null ? 'בלי תאריך סיום' : 'עד ${dmy(end!)}'),
            trailing: const Icon(Icons.event), onTap: () async {
              final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: parseYmd(r.startDate), lastDate: DateTime(2100));
              set(() => end = p == null ? null : ymd(p));
            }),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: enabled, onChanged: (v) => set(() => enabled = v), title: const Text('פעיל')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('מחיקה', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('שמירה')),
      ],
    )));
    if (res == 'delete') {
      if (context.mounted && await confirm(context, 'למחוק את התשלום הקבוע? פעולות שכבר נרשמו יישארו.')) await s.deleteRule(r);
    } else if (res == 'save') {
      final wasOff = !r.enabled;
      r.t.raw = parseAmount(amount.text) ?? r.t.raw;
      r.t.comment = comment.text.trim();
      r..freq = freq..endDate = end..enabled = enabled;
      if (wasOff && enabled) {
        // חידוש בלי למלא את התקופה שבה היה מושהה
        final today = ymd(DateTime.now());
        while (s.ruleNext(r).compareTo(today) < 0) { r.lastDate = s.ruleNext(r); }
      }
      await s.saveRule(r);
      await s.runRecurring();
    }
  }
}

// ---------- גיבוי ----------
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final s = context.read<Store>();
    final user = CloudBackupService.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('גיבוי ושחזור')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('גיבוי ענן (Google Drive)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E5A))),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync),
          title: Text(user == null ? 'התחברות לחשבון Google' : 'מחובר: ${user.email}'),
          subtitle: Text(user == null ? 'גיבוי ושחזור מהענן האישי שלך' : 'לחץ לניתוק או גיבוי'),
          trailing: FilledButton(
            onPressed: loading ? null : () async {
              setState(() => loading = true);
              try {
                if (user == null) {
                  final u = await CloudBackupService.signIn();
                  if (u != null && context.mounted) toast(context, 'התחברת בהצלחה');
                } else {
                  await CloudBackupService.signOut();
                  if (context.mounted) toast(context, 'התנתקת מחשבון Google');
                }
              } catch (e) {
                if (context.mounted) toast(context, 'שגיאה: $e');
              } finally {
                setState(() => loading = false);
              }
            },
            child: Text(user == null ? 'התחבר' : 'התנתק'),
          ),
        ),
        if (user != null) ...[
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('גיבוי כעת לענן'),
            subtitle: const Text('שמירת עותק עדכני ב-Google Drive האישי'),
            onTap: loading ? null : () async {
              setState(() => loading = true);
              try {
                final ok = await CloudBackupService.uploadBackup(s);
                if (context.mounted) toast(context, ok ? 'הגיבוי הועלה לענן בהצלחה' : 'הגיבוי נכשל');
              } catch (e) {
                if (context.mounted) toast(context, 'שגיאה: $e');
              } finally {
                setState(() => loading = false);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('שחזור מהענן'),
            subtitle: const Text('שחזור הנתונים מהגיבוי השמור בענן'),
            onTap: loading ? null : () async {
              if (!await confirm(context, 'השחזור מהענן יחליף את כל הנתונים הנוכחיים. להמשיך?')) return;
              setState(() => loading = true);
              try {
                await CloudBackupService.downloadAndRestoreBackup(s);
                if (context.mounted) toast(context, 'הנתונים שוחזרו בהצלחה מהענן');
              } catch (e) {
                if (context.mounted) toast(context, '$e');
              } finally {
                setState(() => loading = false);
              }
            },
          ),
        ],
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('גיבוי מקומי', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E5A))),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt), title: const Text('יצירת גיבוי לקובץ'),
          subtitle: const Text('שומר עותק מלא של הנתונים לקובץ במכשיר.'),
          onTap: () async {
            try {
              final bytes = await createBackup(s);
              final path = await FilePicker.platform.saveFile(fileName: backupFileName(), bytes: bytes);
              if (context.mounted) toast(context, path == null ? 'השמירה בוטלה' : 'הגיבוי נשמר');
            } catch (e) {
              if (context.mounted) toast(context, 'אירעה שגיאה בעת יצירת הגיבוי: $e');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.restore), title: const Text('שחזור מקובץ מקומי'),
          subtitle: const Text('הנתונים הנוכחיים יוחלפו בתוכן הקובץ.'),
          onTap: () async {
            final r = await FilePicker.platform.pickFiles(withData: true);
            final b = r?.files.single.bytes;
            if (b == null || !context.mounted) return;
            if (!await confirm(context, 'השחזור יחליף את כל הנתונים הנוכחיים. להמשיך?')) return;
            try {
              await restoreBackup(s, b);
              if (context.mounted) toast(context, 'הנתונים שוחזרו בהצלחה');
            } catch (e) {
              if (context.mounted) toast(context, '$e');
            }
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.upload_file), title: const Text('ייבוא מאפליקציית ה־HTML'),
          subtitle: const Text('טעינת maaser-data.json או גיבוי JSON מהגרסה הקודמת.'),
          onTap: () async {
            final r = await FilePicker.platform.pickFiles(withData: true);
            final b = r?.files.single.bytes;
            if (b == null || !context.mounted) return;
            if (!await confirm(context, 'הייבוא יחליף את כל הנתונים הנוכחיים. להמשיך?')) return;
            try {
              final n = await s.importHtmlJson(utf8.decode(b));
              if (context.mounted) toast(context, 'נטענו $n פעולות');
            } catch (e) {
              if (context.mounted) toast(context, 'הקובץ לא נטען: $e');
            }
          },
        ),
      ]),
    );
  }
}
