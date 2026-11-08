import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = generateExcelEdgeCasesBytes();
  final target = File('test/fixtures/excel_edge_cases.xlsx');
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(bytes);
  stdout.writeln('Successfully generated test fixture: ${target.path} (${bytes.length} bytes)');
}

List<int> generateExcelEdgeCasesBytes() {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  final sheet = excel[defaultSheet];
  sheet.isRTL = true;

  // Header row (Index 0)
  sheet.appendRow([
    TextCellValue('ردیف'),
    TextCellValue('تاریخ'),
    TextCellValue('شرح'),
    TextCellValue('مبلغ'),
    TextCellValue('نوع'),
    TextCellValue('طرف حساب'),
    TextCellValue('حساب/صندوق'),
  ]);

  // Row 1: Baseline Valid Row (Expense)
  sheet.appendRow([
    IntCellValue(1),
    TextCellValue('1403/08/10'),
    TextCellValue('خرید سیمان تیپ ۲ پروژه'),
    IntCellValue(15000000),
    TextCellValue('expense'),
    TextCellValue('مصالح فروشی البرز'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 2: Edge Case 1a - En-dash amount ('–')
  sheet.appendRow([
    IntCellValue(2),
    TextCellValue('1403/08/11'),
    TextCellValue('دستمزد آرماتوربندی طبقه ۳'),
    TextCellValue('–'), // En-dash U+2013
    TextCellValue('work_out'),
    TextCellValue('علی کریمی'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 3: Edge Case 1b - Blank cell amount (null)
  sheet.appendRow([
    IntCellValue(3),
    TextCellValue('1403/08/11'),
    TextCellValue('حق‌الزحمه نظارت مهندس ناظر'),
    null, // Blank cell
    TextCellValue('expense'),
    TextCellValue('مهندس رضایی'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 4: Valid Payout row (Original of duplicate pair)
  sheet.appendRow([
    IntCellValue(4),
    TextCellValue('1403/08/12'),
    TextCellValue('پرداخت نقدی علی‌الحساب کارگران'),
    IntCellValue(5000000),
    TextCellValue('payout'),
    TextCellValue('علی کریمی'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 5: Edge Case 2 - Exact duplicate row (Same content as Row 4)
  sheet.appendRow([
    IntCellValue(5),
    TextCellValue('1403/08/12'),
    TextCellValue('پرداخت نقدی علی‌الحساب کارگران'),
    IntCellValue(5000000),
    TextCellValue('payout'),
    TextCellValue('علی کریمی'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 6: Edge Case 3 - Multiple amounts detected in single row
  sheet.appendRow([
    IntCellValue(6),
    TextCellValue('1403/08/13'),
    TextCellValue('خرید بتن آماده ۳۵۰ و کرایه پمپ دکل (مبلغ بتن ۱۲,۵۰۰,۰۰۰ و کرایه پمپ ۲,۵۰۰,۰۰۰)'),
    TextCellValue('12,500,000 / 2,500,000'),
    TextCellValue('expense'),
    TextCellValue('شرکت بتن آماده پاسارگاد'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 7: Edge Case 4a - Ambiguous / Unknown Counterparty
  sheet.appendRow([
    IntCellValue(7),
    TextCellValue('1403/08/14'),
    TextCellValue('کرایه حمل نخاله ساختمانی با خاور'),
    IntCellValue(850000),
    TextCellValue('expense'),
    TextCellValue('راننده ناشناس فاقد پرونده'), // Not in database persons
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 8: Edge Case 4b - Ambiguous / Unknown Transaction Type
  sheet.appendRow([
    IntCellValue(8),
    TextCellValue('1403/08/14'),
    TextCellValue('دریافت چک بابت کارکرد تیرچه بلوک'),
    IntCellValue(45000000),
    TextCellValue('نامشخص / متفرقه'), // Cannot be mapped to 6 enum TxType
    TextCellValue('شرکت عمران پارس'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 9: Edge Case 5a - Excel Date Serial Number (45600 -> 2024-11-04)
  sheet.appendRow([
    IntCellValue(9),
    IntCellValue(45600), // Excel date serial number
    TextCellValue('سرویس دوره‌ای بالابر ساختمانی'),
    IntCellValue(1200000),
    TextCellValue('expense'),
    TextCellValue('مصالح فروشی البرز'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 10: Edge Case 5b - Non-standard Jalali format (2-digit year, Persian digits, dash)
  sheet.appendRow([
    IntCellValue(10),
    TextCellValue('۰۳-۰۸-۱۵'), // Jalali 1403/08/15
    TextCellValue('تهیه لوله و اتصالات آب مصرفی'),
    IntCellValue(3400000),
    TextCellValue('expense'),
    TextCellValue('مصالح فروشی البرز'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  // Row 11: Edge Case 6 - Mixed Persian/English text & currency formatting
  sheet.appendRow([
    IntCellValue(11),
    TextCellValue('1403/08/16'),
    TextCellValue('خرید میلگرد A3 سایز 16 کارخانه فولاد بناب (Price: 8,750,000 Tomans)'),
    TextCellValue('۸٬۷۵۰٬۰۰۰ تومان'), // Mixed Persian digits, comma separator, and currency string
    TextCellValue('expense'),
    TextCellValue('مصالح فروشی البرز'),
    TextCellValue('صندوق اصلی پروژه'),
  ]);

  return excel.save()!;
}
