import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('جرثقيل آذرمي (مهر.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  int multiCount = 0;
  for (final sheetName in ['6 ماهه اول', 'مهر', 'فرشاد']) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) continue;

    for (int r = 2; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.length < 3) continue;
      final desc = row[2]?.value?.toString().trim() ?? '';
      if (desc.isEmpty || desc.contains('جمع کل') || desc.startsWith('صورت ریز')) continue;

      int nonZeroCols = 0;
      final amir = row.length > 3 ? int.tryParse(row[3]?.value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '') : null;
      final aref = row.length > 4 ? int.tryParse(row[4]?.value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '') : null;
      final exp = row.length > 5 ? int.tryParse(row[5]?.value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '') : null;
      final payout = row.length > 8 ? int.tryParse(row[8]?.value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '') : null;

      if (amir != null && amir > 0) nonZeroCols++;
      if (aref != null && aref > 0) nonZeroCols++;
      if (exp != null && exp > 0) nonZeroCols++;
      if (payout != null && payout > 0) nonZeroCols++;

      if (nonZeroCols > 1) {
        multiCount++;
        stdout.writeln('Multi-amount row in $sheetName row $r: desc="$desc" amir=$amir aref=$aref exp=$exp payout=$payout');
      }
    }
  }

  stdout.writeln('Total multi-amount rows across all sheets: $multiCount');
}
