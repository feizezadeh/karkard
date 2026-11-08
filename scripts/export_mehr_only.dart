import 'dart:io';
import 'package:excel/excel.dart';
import 'convert_user_excel_to_app_ready.dart';

void main() {
  final srcFile = File('جرثقيل آذرمي (مهر.xlsx');
  if (!srcFile.existsSync()) {
    stderr.writeln('Source file not found!');
    exit(1);
  }

  final bytes = srcFile.readAsBytesSync();
  final srcExcel = Excel.decodeBytes(bytes);

  if (!srcExcel.tables.containsKey('مهر')) {
    stderr.writeln('Sheet مهر not found in source file!');
    exit(1);
  }

  final mehrSheet = srcExcel.tables['مهر']!;
  final mehrTx = processStandardSheet(mehrSheet, 'مهر');

  final targetExcel = Excel.createExcel();
  final defaultSheet = targetExcel.getDefaultSheet();
  const mainSheetName = 'تراکنش‌های مهر ۱۴۰۵ (آماده ورود)';

  if (defaultSheet != null && defaultSheet != mainSheetName) {
    targetExcel.rename(defaultSheet, mainSheetName);
  }

  populateSheet(targetExcel[mainSheetName], mehrTx);
  populateSummarySheet(targetExcel['خلاصه تراز مهر'], mehrTx);

  final outFile = File('کارکرد_جرثقیل_آذرمی_مهر_۱۴۰۵.xlsx');
  final outBytes = targetExcel.save();
  if (outBytes != null) {
    outFile.writeAsBytesSync(outBytes);
    stdout.writeln('Created Mehr-only file: ${outFile.path} (${outBytes.length} bytes)');
    stdout.writeln('Total Mehr transactions: ${mehrTx.length}');

    final workAmir = mehrTx.where((t) => t.type == 'work_in' && t.partner == 'امیر').toList();
    final workAref = mehrTx.where((t) => t.type == 'work_in' && t.partner == 'عارف').toList();
    final expenses = mehrTx.where((t) => t.type == 'expense').toList();
    final payouts = mehrTx.where((t) => t.type == 'payout').toList();
    final pending = mehrTx.where((t) => t.amount == null).toList();

    int sum(List<NormalizedTx> list) => list.fold(0, (a, b) => a + (b.amount ?? 0));

    stdout.writeln('Breakdown for Mehr 1405:');
    stdout.writeln('  • کارکرد امیر: ${workAmir.length} تراکنش، مجموع: ${sum(workAmir)} تومان');
    stdout.writeln('  • کارکرد عارف: ${workAref.length} تراکنش، مجموع: ${sum(workAref)} تومان');
    stdout.writeln('  • هزینه‌ها: ${expenses.length} تراکنش، مجموع: ${sum(expenses)} تومان');
    stdout.writeln('  • تسویه/واریزی عارف: ${payouts.length} تراکنش، مجموع: ${sum(payouts)} تومان');
    stdout.writeln('  • ردیف‌های بدون مبلغ قطعی: ${pending.length} تراکنش');
  }
}
