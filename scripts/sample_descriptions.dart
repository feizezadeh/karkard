import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('جرثقيل آذرمي (مهر.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  final clientPatterns = <String>[];
  final expensePatterns = <String>[];

  for (final sheetName in ['6 ماهه اول', 'مهر']) {
    final sheet = excel.tables[sheetName]!;
    for (int r = 2; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.length < 3) continue;
      final desc = row[2]?.value?.toString().trim() ?? '';
      if (desc.isEmpty || desc.contains('جمع کل')) continue;

      final amir = row.length > 3 ? row[3]?.value?.toString().trim() : null;
      final aref = row.length > 4 ? row[4]?.value?.toString().trim() : null;
      final exp = row.length > 5 ? row[5]?.value?.toString().trim() : null;

      if ((amir != null && amir.isNotEmpty && amir != '-') ||
          (aref != null && aref.isNotEmpty && aref != '-')) {
        clientPatterns.add(desc);
      } else if (exp != null && exp.isNotEmpty && exp != '-') {
        expensePatterns.add(desc);
      }
    }
  }

  stdout.writeln('=== Sample Work/Client Descriptions (Total: ${clientPatterns.length}) ===');
  for (final d in clientPatterns.take(25)) {
    stdout.writeln('  • $d');
  }

  stdout.writeln('\n=== Sample Expense Descriptions (Total: ${expensePatterns.length}) ===');
  for (final d in expensePatterns.take(25)) {
    stdout.writeln('  • $d');
  }
}
