import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('جرثقيل آذرمي (مهر.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  for (final sheetName in ['6 ماهه اول', 'مهر', 'فرشاد']) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) continue;

    int workAmirCount = 0;
    int workArefCount = 0;
    int expenseCount = 0;
    int payoutArefCount = 0;
    int unknownCount = 0;
    int totalAmir = 0;
    int totalAref = 0;
    int totalExpense = 0;
    int totalPayoutAref = 0;

    for (int r = 2; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.isEmpty) {
        continue;
      }

      final desc = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';
      final amirStr = row.length > 3 ? row[3]?.value?.toString().trim() ?? '' : '';
      final arefStr = row.length > 4 ? row[4]?.value?.toString().trim() ?? '' : '';
      final expStr = row.length > 5 ? row[5]?.value?.toString().trim() ?? '' : '';
      final payoutStr = row.length > 8 ? row[8]?.value?.toString().trim() ?? '' : '';

      if (desc.contains('جمع کل') || desc.startsWith('صورت ریز')) {
        continue;
      }

      final amir = int.tryParse(amirStr.replaceAll(RegExp(r'[^0-9]'), ''));
      final aref = int.tryParse(arefStr.replaceAll(RegExp(r'[^0-9]'), ''));
      final exp = int.tryParse(expStr.replaceAll(RegExp(r'[^0-9]'), ''));
      final payout = int.tryParse(payoutStr.replaceAll(RegExp(r'[^0-9]'), ''));

      if (amir != null && amir > 0) {
        workAmirCount++;
        totalAmir += amir;
      }
      if (aref != null && aref > 0) {
        workArefCount++;
        totalAref += aref;
      }
      if (exp != null && exp > 0) {
        expenseCount++;
        totalExpense += exp;
      }
      if (payout != null && payout > 0) {
        payoutArefCount++;
        totalPayoutAref += payout;
      }

      if (amir == null && aref == null && exp == null && payout == null) {
        if (desc.isNotEmpty && !desc.contains('بدون کارکرد')) {
          unknownCount++;
        }
      }
    }

    stdout.writeln('=== Stats for $sheetName ===');
    stdout.writeln('  Work Amir: $workAmirCount rows, sum: $totalAmir Toman');
    stdout.writeln('  Work Aref: $workArefCount rows, sum: $totalAref Toman');
    stdout.writeln('  Expense: $expenseCount rows, sum: $totalExpense Toman');
    stdout.writeln('  Payout Aref: $payoutArefCount rows, sum: $totalPayoutAref Toman');
    stdout.writeln('  Unknown/Question-mark/Zero rows: $unknownCount');
    stdout.writeln('  Total potential transactions: ${workAmirCount + workArefCount + expenseCount + payoutArefCount}');
  }
}
