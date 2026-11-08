import 'dart:io';
import 'package:excel/excel.dart';

class NormalizedTx {
  final int originalRow;
  final String originalSheet;
  final String date;
  final String description;
  final int? amount;
  final String type; // work_in | expense | payout | transfer
  final String counterparty;
  final String account;
  final String partner; // امیر | عارف | فرشاد | -
  final String hasReceipt; // دارد | ندارد
  final String receiptAmount;
  final String status; // معتبر | نیازمند تصمیم

  NormalizedTx({
    required this.originalRow,
    required this.originalSheet,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.counterparty,
    required this.account,
    required this.partner,
    required this.hasReceipt,
    required this.receiptAmount,
    required this.status,
  });
}

void main() {
  final file = File('جرثقيل آذرمي (مهر.xlsx');
  if (!file.existsSync()) {
    stderr.writeln('Source file not found!');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final srcExcel = Excel.decodeBytes(bytes);

  final allTransactions = <NormalizedTx>[];
  final first6MonthsTx = <NormalizedTx>[];
  final mehrTx = <NormalizedTx>[];
  final farshadTx = <NormalizedTx>[];

  // 1. Process "6 ماهه اول"
  if (srcExcel.tables.containsKey('6 ماهه اول')) {
    final sheet = srcExcel.tables['6 ماهه اول']!;
    final list = processStandardSheet(sheet, '6 ماهه اول');
    first6MonthsTx.addAll(list);
    allTransactions.addAll(list);
  }

  // 2. Process "مهر"
  if (srcExcel.tables.containsKey('مهر')) {
    final sheet = srcExcel.tables['مهر']!;
    final list = processStandardSheet(sheet, 'مهر');
    mehrTx.addAll(list);
    allTransactions.addAll(list);
  }

  // 3. Process "فرشاد"
  if (srcExcel.tables.containsKey('فرشاد')) {
    final sheet = srcExcel.tables['فرشاد']!;
    final list = processFarshadSheet(sheet, 'فرشاد');
    farshadTx.addAll(list);
    allTransactions.addAll(list);
  }

  stdout.writeln('Successfully processed all sheets:');
  stdout.writeln('  • 6 ماهه اول: ${first6MonthsTx.length} تراکنش');
  stdout.writeln('  • مهرماه: ${mehrTx.length} تراکنش');
  stdout.writeln('  • حساب فرشاد: ${farshadTx.length} تراکنش');
  stdout.writeln('  • جمع کل تراکنش‌ها: ${allTransactions.length} تراکنش');

  // Build target Excel
  final targetExcel = Excel.createExcel();

  // Create unified sheet
  final unifiedSheetName = 'همه تراکنش‌ها (آماده ورود)';
  final defaultSheet = targetExcel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != unifiedSheetName) {
    targetExcel.rename(defaultSheet, unifiedSheetName);
  }

  populateSheet(targetExcel[unifiedSheetName], allTransactions);
  populateSheet(targetExcel['6 ماهه اول 1405'], first6MonthsTx);
  populateSheet(targetExcel['مهرماه 1405'], mehrTx);
  populateSheet(targetExcel['حساب فرشاد'], farshadTx);
  populateSummarySheet(targetExcel['خلاصه تراز و آمار'], allTransactions);

  final outFile = File('دفتر_کارکرد_جرثقیل_آذرمی_آماده_ورود.xlsx');
  final outBytes = targetExcel.save();
  if (outBytes != null) {
    outFile.writeAsBytesSync(outBytes);
    stdout.writeln('Created target file: ${outFile.path} (${outBytes.length} bytes)');
  }
}

List<NormalizedTx> processStandardSheet(Sheet sheet, String sheetName) {
  final result = <NormalizedTx>[];
  String lastValidDate = '1405/01/01';

  for (int r = 2; r < sheet.maxRows; r++) {
    final row = sheet.rows[r];
    if (row.isEmpty) continue;

    var rawDate = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';
    final rawDesc = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';
    final amirCell = row.length > 3 ? row[3]?.value?.toString().trim() ?? '' : '';
    final arefCell = row.length > 4 ? row[4]?.value?.toString().trim() ?? '' : '';
    final expCell = row.length > 5 ? row[5]?.value?.toString().trim() ?? '' : '';
    final receiptCell = row.length > 6 ? row[6]?.value?.toString().trim() ?? '' : '';
    final receiptAmtCell = row.length > 7 ? row[7]?.value?.toString().trim() ?? '' : '';
    final payoutCell = row.length > 8 ? row[8]?.value?.toString().trim() ?? '' : '';

    if (rawDesc.isEmpty || rawDesc.contains('جمع کل') || rawDesc.startsWith('صورت ریز')) {
      continue;
    }

    if (rawDate.isNotEmpty && RegExp(r'140\d[/-]\d{1,2}[/-]\d{1,2}').hasMatch(rawDate)) {
      lastValidDate = cleanDate(rawDate);
    } else if (rawDate.isEmpty) {
      rawDate = lastValidDate;
    } else {
      rawDate = cleanDate(rawDate);
    }

    final hasReceipt = (receiptCell == 'P' || receiptAmtCell.isNotEmpty) ? 'دارد' : 'ندارد';
    final receiptAmount = receiptAmtCell;

    final amirAmt = parseMoney(amirCell);
    final arefAmt = parseMoney(arefCell);
    final expAmt = parseMoney(expCell);
    final payoutAmt = parseMoney(payoutCell);

    final isAmirQuestion = amirCell == '؟' || amirCell == '?';
    final isArefQuestion = arefCell == '؟' || arefCell == '?';
    final isExpQuestion = expCell == '؟' || expCell == '?';

    // 1. Work Amir
    if (amirAmt != null && amirAmt > 0) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: rawDesc,
        amount: amirAmt,
        type: 'work_in',
        counterparty: extractCounterparty(rawDesc),
        account: 'صندوق اصلی کارگاه',
        partner: 'امیر',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'معتبر',
      ));
    } else if (isAmirQuestion) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: '$rawDesc (نیازمند تعیین مبلغ کارکرد امیر)',
        amount: null,
        type: 'work_in',
        counterparty: extractCounterparty(rawDesc),
        account: 'صندوق اصلی کارگاه',
        partner: 'امیر',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'نیازمند تصمیم',
      ));
    }

    // 2. Work Aref
    if (arefAmt != null && arefAmt > 0) {
      final isDirectToAref = rawDesc.contains('بحساب عارف') || rawDesc.contains('کارت خوان عارف');
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: rawDesc,
        amount: arefAmt,
        type: 'work_in',
        counterparty: extractCounterparty(rawDesc),
        account: isDirectToAref ? 'کارت بانکی عارف' : 'صندوق اصلی کارگاه',
        partner: 'عارف',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'معتبر',
      ));
    } else if (isArefQuestion) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: '$rawDesc (نیازمند تعیین مبلغ کارکرد عارف)',
        amount: null,
        type: 'work_in',
        counterparty: extractCounterparty(rawDesc),
        account: 'کارت بانکی عارف',
        partner: 'عارف',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'نیازمند تصمیم',
      ));
    }

    // 3. Expense
    if (expAmt != null && expAmt > 0) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: rawDesc,
        amount: expAmt,
        type: 'expense',
        counterparty: extractCounterparty(rawDesc),
        account: 'صندوق اصلی کارگاه',
        partner: '-',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'معتبر',
      ));
    } else if (isExpQuestion) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: '$rawDesc (نیازمند تعیین مبلغ هزینه)',
        amount: null,
        type: 'expense',
        counterparty: extractCounterparty(rawDesc),
        account: 'صندوق اصلی کارگاه',
        partner: '-',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'نیازمند تصمیم',
      ));
    }

    // 4. Payout / Transfer to Aref (only if not already captured as direct deposit work)
    if (payoutAmt != null && payoutAmt > 0 && arefAmt == null) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: rawDate,
        description: rawDesc,
        amount: payoutAmt,
        type: 'payout',
        counterparty: 'عارف محمدی (شریک)',
        account: 'کارت بانکی عارف',
        partner: 'عارف',
        hasReceipt: hasReceipt,
        receiptAmount: receiptAmount,
        status: 'معتبر',
      ));
    }

    // If completely zero / text note (like "بدون کارکرد" or descriptive note)
    if (amirAmt == null && arefAmt == null && expAmt == null && payoutAmt == null &&
        !isAmirQuestion && !isArefQuestion && !isExpQuestion) {
      if (!rawDesc.contains('بدون کارکرد') && rawDesc.length > 5) {
        result.add(NormalizedTx(
          originalRow: r + 1,
          originalSheet: sheetName,
          date: rawDate,
          description: rawDesc,
          amount: null,
          type: 'work_in',
          counterparty: extractCounterparty(rawDesc),
          account: 'صندوق اصلی کارگاه',
          partner: 'امیر',
          hasReceipt: hasReceipt,
          receiptAmount: receiptAmount,
          status: 'نیازمند تصمیم',
        ));
      }
    }
  }

  return result;
}

List<NormalizedTx> processFarshadSheet(Sheet sheet, String sheetName) {
  final result = <NormalizedTx>[];
  for (int r = 1; r < sheet.maxRows; r++) {
    final row = sheet.rows[r];
    if (row.isEmpty) continue;
    final date = row.length > 1 ? cleanDate(row[1]?.value?.toString().trim() ?? '') : '';
    final desc = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';
    final amt = row.length > 3 ? parseMoney(row[3]?.value?.toString().trim() ?? '') : null;

    if (desc.isEmpty || desc.contains('جمع کل')) continue;
    if (amt != null && amt > 0) {
      result.add(NormalizedTx(
        originalRow: r + 1,
        originalSheet: sheetName,
        date: date,
        description: desc,
        amount: amt,
        type: 'work_in',
        counterparty: extractCounterparty(desc),
        account: 'کارت بانکی فرشاد',
        partner: 'فرشاد',
        hasReceipt: 'ندارد',
        receiptAmount: '',
        status: 'معتبر',
      ));
    }
  }
  return result;
}

String formatPersianType(String t) {
  return switch (t) {
    'work_in' => 'کارکرد (درآمد)',
    'expense' => 'هزینه کارگاه',
    'payout' => 'تسویه شریک (واریزی)',
    'transfer' => 'انتقال بین حسابی',
    _ => t,
  };
}

void populateSheet(Sheet sheet, List<NormalizedTx> txs) {
  sheet.isRTL = true;

  // Header row
  sheet.appendRow([
    TextCellValue('ردیف'),
    TextCellValue('تاریخ'),
    TextCellValue('شرح'),
    TextCellValue('مبلغ (تومان)'),
    TextCellValue('نوع'),
    TextCellValue('طرف حساب'),
    TextCellValue('حساب/صندوق'),
    TextCellValue('شریک مجری'),
    TextCellValue('وضعیت رسید'),
    TextCellValue('مبلغ رسید'),
    TextCellValue('وضعیت ردیف'),
  ]);

  for (int i = 0; i < txs.length; i++) {
    final tx = txs[i];
    sheet.appendRow([
      IntCellValue(i + 1),
      TextCellValue(tx.date),
      TextCellValue(tx.description),
      tx.amount != null ? IntCellValue(tx.amount!) : TextCellValue('–'),
      TextCellValue(formatPersianType(tx.type)),
      TextCellValue(tx.counterparty),
      TextCellValue(tx.account),
      TextCellValue(tx.partner),
      TextCellValue(tx.hasReceipt),
      TextCellValue(tx.receiptAmount),
      TextCellValue(tx.status),
    ]);
  }
}

void populateSummarySheet(Sheet sheet, List<NormalizedTx> txs) {
  sheet.isRTL = true;

  sheet.appendRow([
    TextCellValue('عنوان سرفصل آماری'),
    TextCellValue('تعداد تراکنش'),
    TextCellValue('مجموع مبالغ (تومان)'),
  ]);

  final workAmir = txs.where((t) => t.type == 'work_in' && t.partner == 'امیر');
  final workAref = txs.where((t) => t.type == 'work_in' && t.partner == 'عارف');
  final workFarshad = txs.where((t) => t.type == 'work_in' && t.partner == 'فرشاد');
  final expenses = txs.where((t) => t.type == 'expense');
  final payouts = txs.where((t) => t.type == 'payout');
  final needsDecision = txs.where((t) => t.status == 'نیازمند تصمیم');

  int sumOf(Iterable<NormalizedTx> items) => items.fold(0, (acc, t) => acc + (t.amount ?? 0));

  sheet.appendRow([
    TextCellValue('کارکرد اجرایی شریک امیر (Work Amir)'),
    IntCellValue(workAmir.length),
    IntCellValue(sumOf(workAmir)),
  ]);

  sheet.appendRow([
    TextCellValue('کارکرد اجرایی شریک عارف (Work Aref)'),
    IntCellValue(workAref.length),
    IntCellValue(sumOf(workAref)),
  ]);

  sheet.appendRow([
    TextCellValue('کارکرد اجرایی راننده فرشاد (Work Farshad)'),
    IntCellValue(workFarshad.length),
    IntCellValue(sumOf(workFarshad)),
  ]);

  sheet.appendRow([
    TextCellValue('هزینه‌های جاری کارگاه (Workshop Expenses)'),
    IntCellValue(expenses.length),
    IntCellValue(sumOf(expenses)),
  ]);

  sheet.appendRow([
    TextCellValue('برداشت و واریزی به شرکا (Payouts)'),
    IntCellValue(payouts.length),
    IntCellValue(sumOf(payouts)),
  ]);

  sheet.appendRow([
    TextCellValue('ردیف‌های نیازمند تصمیم / بدون مبلغ قطعی'),
    IntCellValue(needsDecision.length),
    IntCellValue(0),
  ]);

  sheet.appendRow([
    TextCellValue('جمع کل تراکنش‌های آماده ورود'),
    IntCellValue(txs.length),
    IntCellValue(sumOf(txs)),
  ]);
}

int? parseMoney(String s) {
  if (s.isEmpty || s == '-' || s == '–' || s == '؟' || s == '?') return null;
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

String cleanDate(String raw) {
  var s = raw.replaceAll('-', '/').trim();
  final parts = s.split('/');
  if (parts.length == 3) {
    var y = parts[0].padLeft(4, '0');
    var m = parts[1].padLeft(2, '0');
    var d = parts[2].padLeft(2, '0');
    return '$y/$m/$d';
  }
  return s;
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
    name = cleanName(name);
    if (name.isNotEmpty && !isStopWord(name)) return name;
  }

  // 3. Work client: "به مهندس/آقای..."
  final beMatch = RegExp(r'به\s+(?:مهندس\s+|آقای\s+|دکتر\s+|اوستا\s+)?([^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (beMatch != null) {
    final name = cleanName(beMatch.group(1)!);
    if (name.length > 2 && !isStopWord(name)) return name;
  }

  // 4. Work client: "کار آقای/مهندس..."
  final karMatch = RegExp(r'کار\s+(?:مهندس\s+|آقای\s+|دکتر\s+|اوستا\s+)?([^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (karMatch != null) {
    final name = cleanName(karMatch.group(1)!);
    if (name.length > 2 && !isStopWord(name)) return name;
  }

  // 5. Work client: "شرکت..."
  final sherkatMatch = RegExp(r'(شرکت\s+[^\s\(\)\d،,]+(?:\s+[^\s\(\)\d،,]+){0,2})').firstMatch(s);
  if (sherkatMatch != null) {
    return cleanName(sherkatMatch.group(1)!);
  }

  // 6. Work client: "شهرداری..."
  final shahrdariMatch = RegExp(r'(شهرداری\s+[^\s\(\)\d،,]+)').firstMatch(s);
  if (shahrdariMatch != null) {
    return cleanName(shahrdariMatch.group(1)!);
  }

  // Fallback
  return 'کارفرمای متفرقه جرثقیل';
}

bool isStopWord(String s) {
  const stops = {'مقصد', 'داخل', 'روی', 'سقف', 'پشت', 'جنب', 'روبروی', 'بالاتر', 'پایین‌تر', 'ساختمان', 'کارگاه', 'کوچه', 'خیابان', 'در'};
  return stops.contains(s);
}

String cleanName(String s) {
  var name = s.replaceAll(RegExp(r'[\(\)]'), '').trim();
  name = name.replaceAll(RegExp(r'\s+در(?:\s+.*)?$'), '').trim();
  name = name.replaceAll(RegExp(r'\s+با(?:\s+.*)?$'), '').trim();
  name = name.replaceAll(RegExp(r'\s+روبروی(?:\s+.*)?$'), '').trim();
  name = name.replaceAll(RegExp(r'\s+جنب(?:\s+.*)?$'), '').trim();
  return name.trim();
}
