import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('جرثقيل آذرمي (مهر.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  final extractedParties = <String, int>{};

  for (final sheetName in ['6 ماهه اول', 'مهر', 'فرشاد']) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) continue;

    for (int r = 2; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.length < 3) continue;
      final desc = row[2]?.value?.toString().trim() ?? '';
      if (desc.isEmpty || desc.contains('جمع کل') || desc.startsWith('صورت ریز')) continue;

      final party = extractCounterparty(desc);
      extractedParties[party] = (extractedParties[party] ?? 0) + 1;
    }
  }

  final sorted = extractedParties.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  stdout.writeln('Total unique extracted counterparties: ${sorted.length}');
  stdout.writeln('Top 35 counterparties:');
  for (final e in sorted.take(35)) {
    stdout.writeln('  • ${e.key}: ${e.value} تراکنش');
  }
}

String extractCounterparty(String desc) {
  var s = desc.replaceAll('ي', 'ی').replaceAll('ك', 'ک').trim();

  // 1. Specific recurring expenses
  if (s == 'ناهار' || s.contains('ناهار')) return 'رستوران و ناهار پرسنل';
  if (s == 'صبحانه' || s.contains('صبحانه')) return 'صبحانه پرسنل';
  if (s == 'شام' || s.contains('شام')) return 'شام پرسنل';
  if (s.contains('گازوئیل') || s.contains('بنزین') || s.contains('سوخت')) return 'جایگاه سوخت';
  if (s.contains('روغن') || s.contains('فیلتر')) return 'تعویض روغنی و لوازم مصرفی';
  if (s.contains('بیمه')) return 'بیمه جرثقیل';
  if (s.contains('کرایه وانت') || s.contains('آژانس')) return 'کرایه حمل و وانت';
  if (s.contains('دفتر فاکتور') || s.contains('لوازم التحریر')) return 'لوازم اداری و دفتر فاکتور';

  // 2. Transfers to partners/staff
  final varizMatch = RegExp(r'(?:واریز\s+(?:به\s*حساب|بحساب)|بحساب)\s+([^\(\)\d،,]+)').firstMatch(s);
  if (varizMatch != null) {
    var name = varizMatch.group(1)!.trim();
    name = name.replaceAll(RegExp(r'\s+بابت.*$'), '').trim();
    if (name.isNotEmpty) return cleanName(name);
  }

  // 3. Work client: "به مهندس/آقای..."
  final beMatch = RegExp(r'به\s+(?:مهندس\s+|آقای\s+|دکتر\s+|اوستا\s+)?([^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (beMatch != null) {
    final name = beMatch.group(1)!.trim();
    if (name.length > 2 && !isStopWord(name)) {
      return cleanName(name);
    }
  }

  // 4. Work client: "کار آقای/مهندس..."
  final karMatch = RegExp(r'کار\s+(?:مهندس\s+|آقای\s+|دکتر\s+|اوستا\s+)?([^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (karMatch != null) {
    final name = karMatch.group(1)!.trim();
    if (name.length > 2 && !isStopWord(name)) {
      return cleanName(name);
    }
  }

  // 5. Work client: "شرکت..."
  final sherkatMatch = RegExp(r'(شرکت\s+[^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (sherkatMatch != null) {
    return cleanName(sherkatMatch.group(1)!.trim());
  }

  // 6. Work client: "شهرداری..."
  final shahrdariMatch = RegExp(r'(شهرداری\s+[^\s\(\)\d،,]+)').firstMatch(s);
  if (shahrdariMatch != null) {
    return cleanName(shahrdariMatch.group(1)!.trim());
  }

  // Fallback
  return 'کارفرمای متفرقه جرثقیل';
}

bool isStopWord(String s) {
  const stops = {'مقصد', 'داخل', 'روی', 'سقف', 'پشت', 'جنب', 'روبروی', 'بالاتر', 'پایین‌تر', 'ساختمان', 'کارگاه', 'کوچه', 'خیابان'};
  return stops.contains(s);
}

String cleanName(String s) {
  var name = s.replaceAll(RegExp(r'[\(\)]'), '').trim();
  name = name.replaceAll(RegExp(r'\s+در\s+.*$'), '').trim();
  name = name.replaceAll(RegExp(r'\s+با\s+.*$'), '').trim();
  return name.trim();
}
