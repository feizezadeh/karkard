import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final file = File('جرثقيل آذرمي (مهر.xlsx');
  if (!file.existsSync()) {
    stdout.writeln('File not found: ${file.path}');
    return;
  }

  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  stdout.writeln('Total sheets: ${excel.tables.keys.length}');
  for (final sheetName in excel.tables.keys) {
    final sheet = excel.tables[sheetName]!;
    stdout.writeln('=== Sheet: $sheetName (Rows: ${sheet.maxRows}, Cols: ${sheet.maxColumns}) ===');

    final rowCount = sheet.maxRows > 40 ? 40 : sheet.maxRows;
    for (int r = 0; r < rowCount; r++) {
      final row = sheet.rows[r];
      final values = row.map((c) => c?.value?.toString() ?? '').toList();
      // Only print if there's at least one non-empty cell
      if (values.any((v) => v.trim().isNotEmpty)) {
        stdout.writeln('Row $r: ${values.join(' | ')}');
      }
    }
  }
}
