import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('جرثقيل آذرمي (مهر.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  for (final sheetName in excel.tables.keys) {
    final sheet = excel.tables[sheetName]!;
    stdout.writeln('========================================');
    stdout.writeln('SHEET: $sheetName (Total Rows: ${sheet.maxRows}, Cols: ${sheet.maxColumns})');
    stdout.writeln('========================================');

    int nonBlankRows = 0;
    for (int r = 0; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      final vals = row.map((c) => c?.value?.toString().trim() ?? '').toList();
      if (vals.any((v) => v.isNotEmpty)) {
        nonBlankRows++;
        if (r < 10 || r > sheet.maxRows - 10) {
          stdout.writeln('Row $r: ${vals.join(' | ')}');
        }
      }
    }
    stdout.writeln('Non-blank rows in $sheetName: $nonBlankRows\n');
  }
}
