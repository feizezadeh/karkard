import 'package:shamsi_date/shamsi_date.dart';

import 'errors.dart';
import 'money.dart';

String _iso(Gregorian g) =>
    '${g.year.toString().padLeft(4, '0')}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';

/// Jalali y/m/d -> stored ISO Gregorian. Throws on an invalid date
/// (e.g. 30 Esfand in a non-leap year).
String jalaliToIso(int y, int m, int d) {
  final j = Jalali(y, m, 1);
  if (m < 1 || m > 12 || d < 1 || d > j.monthLength) {
    throw KarkardException('تاریخ شمسی نامعتبر: $y/$m/$d');
  }
  return _iso(Jalali(y, m, d).toGregorian());
}

/// Stored ISO -> "۱۴۰۳/۱۲/۲۹" for display.
String isoToJalali(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) throw KarkardException('تاریخ ISO نامعتبر: $iso');
  final j = Gregorian(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))
      .toJalali();
  return toFaDigits(
      '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
}

/// Stored ISO -> "1403/12/29" with ASCII digits for input fields.
String isoToJalaliLatin(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) throw KarkardException('تاریخ ISO نامعتبر: $iso');
  final j = Gregorian(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))
      .toJalali();
  return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
}

/// Helper for standard Iranian accounting date period presets.
class JalaliDatePresets {
  static const jalaliMonthNames = [
    '',
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  static ({String startIso, String endIso, String label}) currentMonth() {
    final now = Jalali.now();
    final start = Jalali(now.year, now.month, 1);
    final end = Jalali(now.year, now.month, now.monthLength);
    final monthName = jalaliMonthNames[now.month];
    return (
      startIso: jalaliToIso(start.year, start.month, start.day),
      endIso: jalaliToIso(end.year, end.month, end.day),
      label: 'ماه جاری ($monthName)',
    );
  }

  static ({String startIso, String endIso, String label}) last90Days() {
    final nowG = DateTime.now();
    final pastG = nowG.subtract(const Duration(days: 90));
    final startG = Gregorian.fromDateTime(pastG);
    final endG = Gregorian.fromDateTime(nowG);
    return (
      startIso: _iso(startG),
      endIso: _iso(endG),
      label: '۳ ماه اخیر',
    );
  }

  static ({String startIso, String endIso, String label}) currentYear() {
    final now = Jalali.now();
    final start = Jalali(now.year, 1, 1);
    final end = Jalali(now.year, 12, Jalali(now.year, 12, 1).monthLength);
    return (
      startIso: jalaliToIso(start.year, start.month, start.day),
      endIso: jalaliToIso(end.year, end.month, end.day),
      label: 'سال مالی (${toFaDigits(now.year.toString())})',
    );
  }
}

/// Parses a Jalali string ("1403/12/29" or "۱۴۰۳/۱۲/۲۹") to ISO Gregorian.
String parseJalaliStringToIso(String input) {
  var s = input.trim();
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  final parts = s.split(RegExp(r'[/\\-]'));
  if (parts.length != 3) {
    throw KarkardException('فرمت تاریخ نامعتبر است (الگو: YYYY/MM/DD)');
  }
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) {
    throw KarkardException('ارقام تاریخ نامعتبر است');
  }
  return jalaliToIso(y, m, d);
}

