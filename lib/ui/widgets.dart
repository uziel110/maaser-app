import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';

final _nf = NumberFormat('#,##0.00', 'he');
String fmt(int agorot) => '${agorot < 0 ? '-' : ''}₪${_nf.format(agorot.abs() / 100)}';
int? parseAmount(String s) {
  final t = s.replaceAll(RegExp(r'[,₪\s]'), '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null ? null : (v * 100).round();
}
String dmy(String ymd) => ymd.split('-').reversed.join('.');

/// אייקונים (Material) לפי מפתח. מפתחות מניהול כספים ממופים לאייקון דומה.
const iconMap = <String, IconData>{
  'work': Icons.work, 'prepaid': Icons.work, 'money': Icons.payments, 'investing': Icons.trending_up,
  'cards': Icons.credit_card, 'lottery': Icons.confirmation_number, 'present': Icons.card_giftcard,
  'return': Icons.replay, 'other': Icons.more_horiz, 'star': Icons.star, 'star_david': Icons.star,
  'payment': Icons.volunteer_activism, 'volunteer': Icons.volunteer_activism, 'bill': Icons.receipt_long,
  'book': Icons.menu_book, 'heart': Icons.favorite, 'hands': Icons.handshake, 'synagogue': Icons.account_balance,
  'torah': Icons.auto_stories, 'candle': Icons.local_fire_department, 'coin': Icons.savings,
  'home': Icons.home, 'family': Icons.family_restroom, 'baby': Icons.child_friendly, 'bread': Icons.bakery_dining,
  'education': Icons.school, 'health': Icons.medical_services, 'wedding': Icons.diamond, 'food': Icons.restaurant,
  'box': Icons.inventory_2, 'sprout': Icons.eco,
};
const iconChoices = ['work', 'money', 'star', 'volunteer', 'heart', 'hands', 'synagogue', 'torah', 'book', 'candle',
  'coin', 'present', 'home', 'family', 'baby', 'bread', 'education', 'health', 'wedding', 'food', 'box', 'sprout',
  'bill', 'other'];
const palette = [0xFF2E78CF, 0xFF67AF45, 0xFFF2B108, 0xFFEC8207, 0xFFF63535, 0xFFDB4D87, 0xFF9C4DCC, 0xFF26A69A,
  0xFF9BB68E, 0xFF8D6E63, 0xFF616161, 0xFF3F51B5, 0xFF00ACC1, 0xFF5FEADB, 0xFFFF2AAA, 0xFF42F441];

class CatIcon extends StatelessWidget {
  final Category? cat;
  final double size;
  const CatIcon(this.cat, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: Color(cat?.color ?? 0xFF999999),
        child: Icon(iconMap[cat?.icon] ?? Icons.label, color: Colors.white, size: size * .5),
      );
}

class DonutSlice {
  final double value;
  final Color color;
  DonutSlice(this.value, this.color);
}

class Donut extends StatelessWidget {
  final List<DonutSlice> slices;
  final Widget center;
  const Donut({super.key, required this.slices, required this.center});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240, height: 240,
        child: CustomPaint(painter: _DonutPainter(slices), child: Center(child: center)),
      );
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  _DonutPainter(this.slices);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 26.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke;
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, p..color = const Color(0xFFE4E9EB));
      return;
    }
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.value / total * math.pi * 2;
      canvas.drawArc(rect, start, math.max(sweep - (slices.length > 1 ? 0.015 : 0), 0.001), false, p..color = s.color);
      start += sweep;
    }
  }
  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}
