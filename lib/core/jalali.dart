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
