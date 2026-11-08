import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart' hide TextSpan;
import 'package:shamsi_date/shamsi_date.dart';
import 'package:uuid/uuid.dart';

import '../core/domain_exception.dart';
import '../data/database.dart';
import '../domain/tx_type.dart';
import 'validation_service.dart';

/// ---------------------------------------------------------------------------
/// Sealed Cell Value Reader
/// ---------------------------------------------------------------------------
class ExcelCellReader {
  /// Extracts clean string representation from any sealed CellValue or Data wrapper.
  static String? readString(dynamic cell) {
    final cellValue = cell is Data ? cell.value : (cell is CellValue ? cell : null);
    return switch (cellValue) {
      null => null,
      TextCellValue(:final value) => value.toString().trim(),
      IntCellValue(:final value) => value.toString(),
      DoubleCellValue(:final value) =>
        value == value.roundToDouble() ? value.toInt().toString() : value.toString(),
      DateCellValue(:final year, :final month, :final day) =>
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      DateTimeCellValue(:final year, :final month, :final day) =>
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
      TimeCellValue(:final hour, :final minute, :final second) =>
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}',
      BoolCellValue(:final value) => value.toString(),
      FormulaCellValue(:final formula) => formula.trim(),
    };
  }

  /// Extracts numeric value (int or double) from CellValue or Data wrapper.
  static num? readNum(dynamic cell) {
    final cellValue = cell is Data ? cell.value : (cell is CellValue ? cell : null);
    return switch (cellValue) {
      null => null,
      IntCellValue(:final value) => value,
      DoubleCellValue(:final value) => value,
      TextCellValue(:final value) => num.tryParse(normalizeDigits(value.toString())),
      FormulaCellValue(:final formula) => num.tryParse(normalizeDigits(formula)),
      _ => null,
    };
  }
}

/// Helper: Normalizes Persian and Arabic digits to ASCII digits 0-9.
String normalizeDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var res = s;
  for (var i = 0; i < 10; i++) {
    res = res.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return res;
}

/// Helper: Normalizes Persian text (Yeh/Kaf/Teh Marbuta, diacritics, spaces).
String normalizePersianText(String input) {
  var s = input.trim();
  s = s.replaceAll('ي', 'ی');
  s = s.replaceAll('ك', 'ک');
  s = s.replaceAll('ة', 'ه');
  s = s.replaceAll(RegExp(r'[\u064B-\u0652]'), ''); // Diacritics
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

/// ---------------------------------------------------------------------------
/// Jalali & Gregorian Date Parser
/// ---------------------------------------------------------------------------
class ExcelDateParser {
  static String _isoGregorian(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  /// Parses date from dynamic input (CellValue, DateTime, num, or String).
  /// Normalizes Jalali, serials, and Gregorian dates into ISO YYYY-MM-DD.
  /// Returns null if empty, dash, or invalid.
  static String? parseToIso(dynamic input) {
    if (input == null) return null;
    if (input is Data) {
      input = input.value;
      if (input == null) return null;
    }

    if (input is DateCellValue) {
      return _isoGregorian(input.year, input.month, input.day);
    }
    if (input is DateTimeCellValue) {
      return _isoGregorian(input.year, input.month, input.day);
    }
    if (input is DateTime) {
      return _isoGregorian(input.year, input.month, input.day);
    }
    if (input is IntCellValue) {
      return _parseNumericDate(input.value);
    }
    if (input is DoubleCellValue) {
      return _parseNumericDate(input.value);
    }
    if (input is num) {
      return _parseNumericDate(input);
    }

    String raw;
    if (input is TextCellValue) {
      raw = input.value.toString();
    } else if (input is FormulaCellValue) {
      raw = input.formula;
    } else {
      raw = input.toString();
    }

    return parseStringToIso(raw);
  }

  static String? _parseNumericDate(num value) {
    // Excel date serial numbers (serials ~25000 to 75000 correspond to 1968 - 2105)
    if (value >= 25000 && value <= 75000) {
      final days = value.floor();
      final dt = DateTime.utc(1899, 12, 30).add(Duration(days: days));
      return _isoGregorian(dt.year, dt.month, dt.day);
    }
    // 8-digit Jalali integer YYYYMMDD (13700101 to 14501229)
    if (value >= 13000000 && value <= 15000000) {
      final y = value ~/ 10000;
      final m = (value % 10000) ~/ 100;
      final d = value.toInt() % 100;
      return _tryJalaliToIso(y, m, d);
    }
    // 8-digit Gregorian integer YYYYMMDD (19900101 to 20501229)
    if (value >= 19900000 && value <= 20501229) {
      final y = value ~/ 10000;
      final m = (value % 10000) ~/ 100;
      final d = value.toInt() % 100;
      return _tryGregorianToIso(y, m, d);
    }
    return null;
  }

  static String? parseStringToIso(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;

    s = normalizeDigits(s);

    if (RegExp(r'^[-–—_]+$').hasMatch(s)) return null;

    // Strip time suffix
    s = s.replaceAll(RegExp(r'[T\s]\d{1,2}:\d{1,2}(?::\d{1,2})?(?:\.\d+)?.*$'), '').trim();

    // Pure numeric string
    final numVal = num.tryParse(s);
    if (numVal != null && !s.contains(RegExp(r'[/\\.\-]'))) {
      if (s.length == 5 && numVal >= 25000 && numVal <= 75000) {
        final dt = DateTime.utc(1899, 12, 30).add(Duration(days: numVal.floor()));
        return _isoGregorian(dt.year, dt.month, dt.day);
      }
      if (s.length == 8) {
        final y = int.parse(s.substring(0, 4));
        final m = int.parse(s.substring(4, 6));
        final d = int.parse(s.substring(6, 8));
        if (y >= 1300 && y <= 1500) {
          return _tryJalaliToIso(y, m, d);
        } else if (y >= 1900 && y <= 2100) {
          return _tryGregorianToIso(y, m, d);
        }
      }
      if (s.length == 6) {
        var y = int.parse(s.substring(0, 2));
        final m = int.parse(s.substring(2, 4));
        final d = int.parse(s.substring(4, 6));
        y = y >= 70 ? 1300 + y : 1400 + y;
        return _tryJalaliToIso(y, m, d);
      }
    }

    final parts = s.split(RegExp(r'[/\\.\-]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length != 3) return null;

    final p0 = int.tryParse(parts[0]);
    final p1 = int.tryParse(parts[1]);
    final p2 = int.tryParse(parts[2]);
    if (p0 == null || p1 == null || p2 == null) return null;

    int year, month, day;
    bool isGregorian = false;

    if (p2 >= 1300 && p2 <= 1500) {
      // DD/MM/YYYY Jalali
      day = p0;
      month = p1;
      year = p2;
    } else if (p2 >= 1900 && p2 <= 2100) {
      // DD/MM/YYYY Gregorian
      day = p0;
      month = p1;
      year = p2;
      isGregorian = true;
    } else if (p0 >= 1900 && p0 <= 2100) {
      // YYYY/MM/DD Gregorian
      year = p0;
      month = p1;
      day = p2;
      isGregorian = true;
    } else if (p0 >= 1300 && p0 <= 1500) {
      // YYYY/MM/DD Jalali
      year = p0;
      month = p1;
      day = p2;
    } else {
      // 2-digit years
      if (p0 > 31) {
        year = p0 >= 70 ? 1300 + p0 : 1400 + p0;
        month = p1;
        day = p2;
      } else if (p2 > 31) {
        day = p0;
        month = p1;
        year = p2 >= 70 ? 1300 + p2 : 1400 + p2;
      } else if (p0 > 12 && p2 <= 12) {
        day = p0;
        month = p1;
        year = p2 >= 70 ? 1300 + p2 : 1400 + p2;
      } else {
        year = p0 >= 70 ? 1300 + p0 : 1400 + p0;
        month = p1;
        day = p2;
      }
    }

    if (isGregorian) {
      return _tryGregorianToIso(year, month, day);
    } else {
      return _tryJalaliToIso(year, month, day);
    }
  }

  static String? _tryJalaliToIso(int y, int m, int d) {
    if (m < 1 || m > 12) return null;
    try {
      final j = Jalali(y, m, 1);
      if (d < 1 || d > j.monthLength) return null;
      final g = Jalali(y, m, d).toGregorian();
      return _isoGregorian(g.year, g.month, g.day);
    } catch (_) {
      return null;
    }
  }

  static String? _tryGregorianToIso(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    try {
      final dt = DateTime.utc(y, m, d);
      if (dt.year != y || dt.month != m || dt.day != d) return null;
      return _isoGregorian(y, m, d);
    } catch (_) {
      return null;
    }
  }
}

/// ---------------------------------------------------------------------------
/// Number & Currency Parser
/// ---------------------------------------------------------------------------
class ExcelNumberParser {
  static bool isDashOrEmpty(dynamic input) {
    if (input == null) return true;
    if (input is Data) {
      input = input.value;
      if (input == null) return true;
    }
    final s = switch (input) {
      TextCellValue(:final value) => value.toString(),
      FormulaCellValue(:final formula) => formula,
      _ => input.toString(),
    }.trim();
    if (s.isEmpty) return true;
    return RegExp(r'^[-–—_]+$').hasMatch(s) ||
        const {'n/a', 'na', 'nil', 'null', 'none', 'ندارد', 'هیچ', 'صفر'}.contains(s.toLowerCase());
  }

  /// Parses financial amount into integer Toman.
  /// Returns null if empty/dash or unparseable.
  static int? parseAmount(dynamic input) {
    if (input == null) return null;
    if (input is Data) {
      input = input.value;
      if (input == null) return null;
    }
    if (input is IntCellValue) return input.value;
    if (input is DoubleCellValue) return input.value.round();
    if (input is int) return input;
    if (input is double) return input.round();

    final sRaw = switch (input) {
      TextCellValue(:final value) => value.toString(),
      FormulaCellValue(:final formula) => formula,
      _ => input.toString(),
    };

    var s = sRaw.trim();
    if (isDashOrEmpty(s)) return null;

    s = normalizeDigits(s);

    bool isNegative = false;
    final parenMatch = RegExp(r'^\s*\((.*?)\)\s*$').firstMatch(s);
    if (parenMatch != null) {
      isNegative = true;
      s = parenMatch.group(1)!.trim();
    }

    if (s.startsWith('-') || s.startsWith('−') || s.startsWith('–')) {
      isNegative = true;
      s = s.substring(1).trim();
    } else if (s.endsWith('-') || s.endsWith('−') || s.endsWith('–')) {
      isNegative = true;
      s = s.substring(0, s.length - 1).trim();
    }

    s = s.replaceAll(RegExp(r'(?:تومان|ریال|تومانی|ریالی|IRR|Tomans?|Rials?)', caseSensitive: false), '').trim();

    if (RegExp(r'\d+\s*[\+\/\\&و]\s*\d+').hasMatch(s)) {
      return null;
    }

    // Persian momayyez decimal
    if (s.contains('٫')) {
      final parts = s.split('٫');
      if (parts.length == 2) {
        final whole = parts[0].replaceAll(RegExp(r'[,٬،\s_]'), '');
        final frac = parts[1].replaceAll(RegExp(r'[,٬،\s_]'), '');
        final numVal = double.tryParse('$whole.$frac');
        if (numVal != null) {
          final res = numVal.round();
          return isNegative ? -res : res;
        }
      }
    }

    // Single dot decimal
    final dotCount = '.'.allMatches(s).length;
    if (dotCount == 1) {
      final parts = s.split('.');
      if (parts[1].length <= 2) {
        final whole = parts[0].replaceAll(RegExp(r'[,٬،\s_]'), '');
        final numVal = double.tryParse('$whole.${parts[1]}');
        if (numVal != null) {
          final res = numVal.round();
          return isNegative ? -res : res;
        }
      }
    } else if (dotCount > 1) {
      s = s.replaceAll('.', '');
    }

    s = s.replaceAll(RegExp(r'[,٬،\s_]'), '');

    final v = int.tryParse(s);
    if (v == null) return null;
    return isNegative ? -v : v;
  }
}

/// ---------------------------------------------------------------------------
/// Multi-Amount Candidate Detector
/// ---------------------------------------------------------------------------
class MultiAmountDetector {
  static List<int> detectCandidateAmounts(String text) {
    if (text.trim().isEmpty) return const [];

    var s = normalizeDigits(text);

    // 1. Mask date expressions
    s = s.replaceAll(RegExp(r'\b\d{2,4}[/\\.\-]\d{1,2}[/\\.\-]\d{1,2}\b'), ' ');
    s = s.replaceAll(RegExp(r'\b(?:13|14|19|20)\d{6}\b'), ' ');

    // 2. Mask phone numbers & 16-digit cards
    s = s.replaceAll(RegExp(r'\b09\d{9}\b'), ' ');
    s = s.replaceAll(RegExp(r'\b\d{16}\b'), ' ');
    s = s.replaceAll(RegExp(r'\b\d{4}[-\s]\d{4}[-\s]\d{4}[-\s]\d{4}\b'), ' ');

    // 3. Match numeric tokens
    final regex = RegExp(r'(?:\b|\()(\d+(?:[,٬،\.\s_]\d{3})*(?:[٫\.]\d+)?|\d+)\)?');
    final matches = regex.allMatches(s);

    final results = <int>[];
    for (final m in matches) {
      final raw = m.group(1);
      if (raw == null) continue;
      final amt = ExcelNumberParser.parseAmount(raw);
      if (amt != null && amt.abs() > 0) {
        if (amt.abs() >= 1000 || raw.contains(RegExp(r'[,٬،]'))) {
          results.add(amt.abs());
        }
      }
    }

    return results;
  }
}

/// Status of an Excel row after parsing and pre-scan deduplication.
enum RowStatus {
  ready,
  duplicate,
  needsDecision,
  skippedByUser,
}

/// Specific ambiguity reason requiring user resolution.
enum AmbiguityReason {
  emptyAmount,
  multipleAmounts,
  unknownCounterparty,
  ambiguousType,
  invalidDate,
  missingRequiredField,
  roleMismatch,
}

/// Column mapping configuration for parsing an Excel file.
class ColumnMapping {
  final int dateColumn;
  final int? amountColumn;
  final int? debitAmountColumn;
  final int? creditAmountColumn;
  final int? descriptionColumn;
  final int? typeColumn;
  final int? counterpartyColumn;
  final int? accountColumn;
  final int? cashAccountColumn;
  final int? categoryColumn;
  final TxType defaultType;
  final String? defaultCashAccountId;
  final String defaultPayoutPurpose;
  final bool hasHeader;
  final String? sheetName;

  const ColumnMapping({
    required this.dateColumn,
    this.amountColumn,
    this.debitAmountColumn,
    this.creditAmountColumn,
    this.descriptionColumn,
    this.typeColumn,
    this.counterpartyColumn,
    this.accountColumn,
    this.cashAccountColumn,
    this.categoryColumn,
    this.defaultType = TxType.expense,
    this.defaultCashAccountId,
    this.defaultPayoutPurpose = 'settle_payable',
    this.hasHeader = true,
    this.sheetName,
  });

  int? get effectiveAccountColumn => accountColumn ?? cashAccountColumn;
}

/// A parsed row from an Excel sheet.
class ParsedExcelRow {
  final int rowIndex; // 1-based index in Excel sheet
  final String rawDate;
  final String? isoDate;
  final String description;
  final int? amount;
  final List<int> detectedAmounts;
  final TxType? inferredType;
  final String? rawParty;
  final String? personId;
  final String? clientId;
  final String? cashAccountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String? payoutPurpose;
  final String? overrideReason;
  final String? categoryId;
  final String importHash;
  RowStatus status;
  AmbiguityReason? ambiguityReason;
  String? resolutionNote;

  bool get userSkipped => status == RowStatus.skippedByUser;
  set userSkipped(bool val) {
    if (val) {
      status = RowStatus.skippedByUser;
    } else if (status == RowStatus.skippedByUser) {
      status = ambiguityReason != null ? RowStatus.needsDecision : RowStatus.ready;
    }
  }

  ParsedExcelRow({
    required this.rowIndex,
    required this.rawDate,
    this.isoDate,
    required this.description,
    this.amount,
    this.detectedAmounts = const [],
    this.inferredType,
    this.rawParty,
    this.personId,
    this.clientId,
    this.cashAccountId,
    this.fromAccountId,
    this.toAccountId,
    this.payoutPurpose,
    this.overrideReason,
    this.categoryId,
    required this.importHash,
    required this.status,
    this.ambiguityReason,
    this.resolutionNote,
  });

  ParsedExcelRow copyWith({
    int? rowIndex,
    String? rawDate,
    String? isoDate,
    String? description,
    int? amount,
    List<int>? detectedAmounts,
    TxType? inferredType,
    String? rawParty,
    String? personId,
    String? clientId,
    String? cashAccountId,
    String? fromAccountId,
    String? toAccountId,
    String? payoutPurpose,
    String? overrideReason,
    String? categoryId,
    String? importHash,
    RowStatus? status,
    AmbiguityReason? ambiguityReason,
    String? resolutionNote,
  }) {
    return ParsedExcelRow(
      rowIndex: rowIndex ?? this.rowIndex,
      rawDate: rawDate ?? this.rawDate,
      isoDate: isoDate ?? this.isoDate,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      detectedAmounts: detectedAmounts ?? this.detectedAmounts,
      inferredType: inferredType ?? this.inferredType,
      rawParty: rawParty ?? this.rawParty,
      personId: personId ?? this.personId,
      clientId: clientId ?? this.clientId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      payoutPurpose: payoutPurpose ?? this.payoutPurpose,
      overrideReason: overrideReason ?? this.overrideReason,
      categoryId: categoryId ?? this.categoryId,
      importHash: importHash ?? this.importHash,
      status: status ?? this.status,
      ambiguityReason: ambiguityReason ?? this.ambiguityReason,
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
  }
}

/// Summary report returned after committing imported rows.
class ExcelImportResult {
  final int totalRowsProcessed;
  final int importedCount;
  final int duplicatesSkippedCount;
  final int userSkippedCount;
  final int totalImportedAmount;
  final List<String> insertedTransactionIds;

  int get insertedCount => importedCount;
  int get duplicateSkippedCount => duplicatesSkippedCount;

  const ExcelImportResult({
    required this.totalRowsProcessed,
    required this.importedCount,
    required this.duplicatesSkippedCount,
    required this.userSkippedCount,
    required this.totalImportedAmount,
    this.insertedTransactionIds = const [],
  });
}

/// Calculates a deterministic SHA-256 hash for an imported transaction row.
String calculateImportHash({
  required String projectId,
  required String date, // ISO YYYY-MM-DD (or rawDate if unparsed)
  required String txType, // dbValue (work_in, work_out, income, expense, payout, transfer)
  required int amount, // Integer Tomans
  required String description,
  String? rawParty,
  String? cashAccountNameOrId,
}) {
  final cleanProjectId = projectId.trim();
  final cleanDate = date.trim();
  final cleanType = txType.trim().toLowerCase();
  final cleanAmount = amount.toString();
  final cleanDesc = normalizePersianText(description);
  final cleanParty = normalizePersianText(rawParty ?? '');
  final cleanAccount = normalizePersianText(cashAccountNameOrId ?? '');

  final canonicalString = [
    cleanProjectId,
    cleanDate,
    cleanType,
    cleanAmount,
    cleanDesc,
    cleanParty,
    cleanAccount,
  ].join('|');

  return sha256.convert(utf8.encode(canonicalString)).toString();
}

/// Helper to parse transaction type from Persian text or English keywords.
TxType? parseTxType(String? input, {TxType? fallback}) {
  if (input == null) return fallback;
  final s = normalizePersianText(input).toLowerCase();
  if (s.isEmpty) return fallback;

  if (s == 'work_in' ||
      s.contains('طلب کارفرما') ||
      s.contains('کارکرد کارفرما') ||
      s.contains('صورت وضعیت') ||
      s.contains('کارکرد طلب') ||
      s.contains('کارکرد (درآمد)') ||
      s.contains('کارکرد جرثقیل') ||
      s.contains('کارکرد امیر') ||
      s.contains('کارکرد عارف') ||
      s == 'کارکرد' ||
      s == 'درآمد') {
    return TxType.workIn;
  }
  if (s == 'work_out' ||
      s.contains('کارکرد پیمانکار') ||
      s.contains('کارکرد راننده') ||
      s.contains('کارکرد کارگر') ||
      s.contains('دستمزد') ||
      s.contains('بدهی کارکرد')) {
    return TxType.workOut;
  }
  if (s == 'income' ||
      s.contains('دریافتی') ||
      s.contains('واریز کارفرما') ||
      s.contains('وصول') ||
      s.contains('دریافت از کارفرما')) {
    return TxType.income;
  }
  if (s == 'expense' ||
      s.contains('هزینه') ||
      s.contains('هزینه کرد') ||
      s.contains('هزینه کارگاه') ||
      s.contains('مخارج') ||
      s.contains('خرید') ||
      s.contains('مصالح') ||
      s.contains('سوخت') ||
      s.contains('اجاره')) {
    return TxType.expense;
  }
  if (s == 'payout' ||
      s.contains('پرداخت') ||
      s.contains('تسویه') ||
      s.contains('مساعده') ||
      s.contains('سهم سود') ||
      s.contains('برداشت') ||
      s.contains('واریزی به حساب') ||
      s.contains('واریز به حساب') ||
      s.contains('واریزی بحساب') ||
      s.contains('واریز بحساب')) {
    return TxType.payout;
  }
  if (s == 'transfer' ||
      s.contains('انتقال') ||
      s.contains('کارت به کارت') ||
      s.contains('بین حسابی')) {
    return TxType.transfer;
  }

  // Not a recognized transaction type
  return null;
}

abstract class IExcelImportService {
  Future<List<ParsedExcelRow>> parseExcel(
    Uint8List bytes, {
    required String projectId,
    required ColumnMapping mapping,
  });

  Future<ExcelImportResult> commitImport(
    List<ParsedExcelRow> rows, {
    required String projectId,
  });
}

class ExcelImportService implements IExcelImportService {
  final AppDatabase db;
  final ValidationService validationService;

  ExcelImportService(this.db, {ValidationService? validationService})
      : validationService = validationService ?? ValidationService(db);

  @override
  Future<List<ParsedExcelRow>> parseExcel(
    Uint8List bytes, {
    required String projectId,
    required ColumnMapping mapping,
  }) async {
    final excel = Excel.decodeBytes(bytes);
    final sheetName = mapping.sheetName ?? excel.getDefaultSheet() ?? excel.tables.keys.firstOrNull;
    if (sheetName == null || !excel.tables.containsKey(sheetName)) {
      throw const DomainException('ERR_EMPTY_EXCEL', 'فایل اکسل فاقد شیت معتبر است.');
    }

    final sheet = excel.tables[sheetName]!;
    final allRows = sheet.rows;
    if (allRows.isEmpty) {
      return [];
    }

    // Query existing import_hashes in DB for this project
    final existingTxs = await (db.select(db.transactions)
          ..where((t) => t.projectId.equals(projectId) & t.importHash.isNotNull()))
        .get();
    final dbHashes = existingTxs.map((t) => t.importHash!).toSet();

    // Query all persons in DB for counterparty matching
    final allPersons = await db.select(db.persons).get();

    // Query all cash accounts in DB
    final allAccounts = await db.select(db.cashAccounts).get();

    final seenInFileHashes = <String>{};
    final parsedRows = <ParsedExcelRow>[];

    final startIndex = mapping.hasHeader ? 1 : 0;
    for (var i = startIndex; i < allRows.length; i++) {
      final row = allRows[i];
      if (row.isEmpty || row.every((c) => c == null || ExcelCellReader.readString(c)?.isEmpty == true)) {
        continue;
      }

      final dataRowIndex = mapping.hasHeader ? i : i + 1;

      // 1. Date
      final dateCell = mapping.dateColumn < row.length ? row[mapping.dateColumn] : null;
      final rawDate = ExcelCellReader.readString(dateCell) ?? '';
      final isoDate = ExcelDateParser.parseToIso(dateCell);

      // 2. Description
      String description = '';
      if (mapping.descriptionColumn != null && mapping.descriptionColumn! < row.length) {
        description = ExcelCellReader.readString(row[mapping.descriptionColumn!]) ?? '';
      }

      // 3. Amount & Multi-Amount detection
      final amountCell = (mapping.amountColumn != null && mapping.amountColumn! < row.length)
          ? row[mapping.amountColumn!]
          : null;
      final isDash = ExcelNumberParser.isDashOrEmpty(amountCell);
      final rawAmountStr = ExcelCellReader.readString(amountCell) ?? '';

      final combinedText = '$rawAmountStr $description';
      final candidateAmounts = MultiAmountDetector.detectCandidateAmounts(combinedText);
      final distinctCandidateAmounts = candidateAmounts.toSet().toList();

      int? parsedAmount;
      if (!isDash) {
        parsedAmount = ExcelNumberParser.parseAmount(amountCell);
      }

      // 4. Type
      TxType? inferredType;
      bool explicitTypeAmbiguous = false;
      if (mapping.typeColumn != null && mapping.typeColumn! < row.length) {
        final rawType = ExcelCellReader.readString(row[mapping.typeColumn!]);
        if (rawType != null && rawType.isNotEmpty) {
          inferredType = parseTxType(rawType);
          if (inferredType == null) {
            explicitTypeAmbiguous = true;
          }
        } else {
          inferredType = mapping.defaultType;
        }
      } else {
        inferredType = mapping.defaultType;
      }

      // 5. Counterparty
      String? rawParty;
      String? personId;
      String? clientId;
      bool counterpartyUnknown = false;
      if (mapping.counterpartyColumn != null && mapping.counterpartyColumn! < row.length) {
        rawParty = ExcelCellReader.readString(row[mapping.counterpartyColumn!]);
      }

      // If rawParty is empty, check if an existing person is mentioned in the description
      if ((rawParty == null || rawParty.trim().isEmpty) && description.isNotEmpty) {
        final cleanDesc = normalizePersianText(description);
        for (final p in allPersons) {
          final pName = normalizePersianText(p.name);
          if (pName.length >= 3 && cleanDesc.contains(pName)) {
            rawParty = p.name;
            break;
          }
        }
      }

      if (rawParty != null && rawParty.trim().isNotEmpty) {
        final cleanParty = normalizePersianText(rawParty);
        final trimmedParty = rawParty.trim();

        // 1. Exact match on name or code
        var matches = allPersons.where((p) =>
          normalizePersianText(p.name) == cleanParty ||
          (p.code != null && p.code!.trim() == trimmedParty)
        ).toList();

        // 2. Substring match (e.g. "مهندس ناصر پیوسته" matches "ناصر پیوسته")
        if (matches.isEmpty && cleanParty.length >= 3) {
          matches = allPersons.where((p) {
            final pName = normalizePersianText(p.name);
            return pName.length >= 3 && (cleanParty.contains(pName) || pName.contains(cleanParty));
          }).toList();
        }

        // 3. Search description for registered persons if not matched yet
        if (matches.isEmpty && description.isNotEmpty) {
          final cleanDesc = normalizePersianText(description);
          matches = allPersons.where((p) {
            final pName = normalizePersianText(p.name);
            return pName.length >= 3 && cleanDesc.contains(pName);
          }).toList();
        }

        if (matches.isEmpty) {
          counterpartyUnknown = true;
        } else {
          final matchedPerson = matches.first;
          rawParty = matchedPerson.name;
          if (inferredType == TxType.workIn || inferredType == TxType.income) {
            clientId = matchedPerson.id;
          } else if (inferredType == TxType.workOut || inferredType == TxType.payout) {
            personId = matchedPerson.id;
          } else {
            personId = matchedPerson.id;
          }
        }
      }

      // 6. Cash Account
      String? cashAccountId;
      final effectiveAccCol = mapping.effectiveAccountColumn;
      if (effectiveAccCol != null && effectiveAccCol < row.length) {
        final rawAcc = ExcelCellReader.readString(row[effectiveAccCol]);
        if (rawAcc != null && rawAcc.trim().isNotEmpty) {
          final cleanAcc = normalizePersianText(rawAcc);
          final trimmedAcc = rawAcc.trim();
          final accMatch = allAccounts.where((a) =>
            normalizePersianText(a.name) == cleanAcc ||
            (a.code != null && a.code!.trim() == trimmedAcc)
          ).firstOrNull;
          if (accMatch != null) {
            cashAccountId = accMatch.id;
          }
        }
      }
      cashAccountId ??= mapping.defaultCashAccountId;

      // 7. Calculate Hash
      final effectiveType = inferredType?.dbValue ?? 'expense';
      final effectiveAmount = parsedAmount ?? 0;
      final importHash = calculateImportHash(
        projectId: projectId,
        date: isoDate ?? rawDate,
        txType: effectiveType,
        amount: effectiveAmount,
        description: description,
        rawParty: rawParty,
        cashAccountNameOrId: cashAccountId,
      );

      // 8. Determine Status & AmbiguityReason
      RowStatus status = RowStatus.ready;
      AmbiguityReason? ambiguityReason;

      if (isDash || parsedAmount == null) {
        if (distinctCandidateAmounts.length > 1) {
          status = RowStatus.needsDecision;
          ambiguityReason = AmbiguityReason.multipleAmounts;
          parsedAmount = null;
        } else {
          status = RowStatus.needsDecision;
          ambiguityReason = AmbiguityReason.emptyAmount;
          parsedAmount = null;
        }
      } else if (distinctCandidateAmounts.length > 1) {
        status = RowStatus.needsDecision;
        ambiguityReason = AmbiguityReason.multipleAmounts;
        parsedAmount = null;
      } else if (counterpartyUnknown) {
        status = RowStatus.needsDecision;
        ambiguityReason = AmbiguityReason.unknownCounterparty;
      } else if (explicitTypeAmbiguous || inferredType == null) {
        status = RowStatus.needsDecision;
        ambiguityReason = AmbiguityReason.ambiguousType;
      } else if (isoDate == null) {
        status = RowStatus.needsDecision;
        ambiguityReason = AmbiguityReason.invalidDate;
      } else if (dbHashes.contains(importHash) || seenInFileHashes.contains(importHash)) {
        status = RowStatus.duplicate;
      }

      if (status == RowStatus.ready) {
        seenInFileHashes.add(importHash);
      }

      parsedRows.add(ParsedExcelRow(
        rowIndex: dataRowIndex,
        rawDate: rawDate,
        isoDate: isoDate,
        description: description,
        amount: parsedAmount,
        detectedAmounts: distinctCandidateAmounts,
        inferredType: inferredType,
        rawParty: rawParty,
        personId: personId,
        clientId: clientId,
        cashAccountId: cashAccountId,
        importHash: importHash,
        status: status,
        ambiguityReason: ambiguityReason,
      ));
    }

    return parsedRows;
  }

  @override
  Future<ExcelImportResult> commitImport(
    List<ParsedExcelRow> rows, {
    required String projectId,
  }) async {
    final project = await (db.select(db.projects)..where((p) => p.id.equals(projectId))).getSingleOrNull();
    if (project == null) {
      throw const DomainException('ERR_PROJECT_NOT_FOUND', 'پروژه مورد نظر یافت نشد.');
    }
    if (project.status == 'locked') {
      throw const DomainException(DomainErrors.projectLockedTx, 'پروژه در وضعیت قفل دوره است.');
    }

    final unresolved = rows.where((r) => r.status == RowStatus.needsDecision && !r.userSkipped).toList();
    if (unresolved.isNotEmpty) {
      throw DomainException(
        'ERR_UNRESOLVED_IMPORT_ROWS',
        'تعداد ${unresolved.length} ردیف نیازمند تصمیم کاربر حل‌نشده باقی مانده است.',
      );
    }

    final toImport = rows.where((r) => r.status == RowStatus.ready && !r.userSkipped).toList();
    final duplicates = rows.where((r) => r.status == RowStatus.duplicate).toList();
    final userSkipped = rows.where((r) => r.userSkipped).toList();

    final insertedIds = <String>[];
    const uuid = Uuid();
    int totalAmount = 0;
    int skippedDuplicatesInCommit = 0;

    // Fetch latest existing import hashes from database to prevent duplicate collision
    final existingTxs = await (db.select(db.transactions)
          ..where((t) => t.projectId.equals(projectId) & t.importHash.isNotNull()))
        .get();
    final committedHashes = existingTxs.map((t) => t.importHash!).toSet();

    for (final row in toImport) {
      // 1. If importHash is already committed in database or already in this batch, safely skip as duplicate
      if (committedHashes.contains(row.importHash)) {
        skippedDuplicatesInCommit++;
        continue;
      }
      committedHashes.add(row.importHash);

      final txId = uuid.v4();
      final type = row.inferredType!;

      // If work_out or payout, ensure person is registered in project_persons
      if (type == TxType.payout || type == TxType.workOut) {
        if (row.personId != null) {
          final inProject = await (db.select(db.projectPersons)
                ..where((pp) => pp.projectId.equals(projectId) & pp.personId.equals(row.personId!)))
              .getSingleOrNull();
          if (inProject == null) {
            await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
                  projectId: projectId,
                  personId: row.personId!,
                  settlementMode: const Value('payout_only'),
                ));
          }
        }
      }

      // If work_in or income, ensure clientId has kind == 'client' and match/create if needed
      String? safeClientId;
      if (type == TxType.workIn || type == TxType.income) {
        final candidateId = row.clientId ?? row.personId;
        if (candidateId != null) {
          final p = await (db.select(db.persons)..where((p) => p.id.equals(candidateId))).getSingleOrNull();
          if (p != null) {
            if (p.kind == 'client') {
              safeClientId = p.id;
            } else if (p.kind == 'other') {
              await (db.update(db.persons)..where((tbl) => tbl.id.equals(p.id))).write(
                const PersonsCompanion(kind: Value('client')),
              );
              safeClientId = p.id;
            }
          }
        }

        // If safeClientId is still null, but rawParty is known:
        if (safeClientId == null && row.rawParty != null && row.rawParty!.trim().isNotEmpty) {
          final cleanParty = normalizePersianText(row.rawParty!);
          final existing = await (db.select(db.persons)..where((p) => p.name.equals(cleanParty))).getSingleOrNull();
          if (existing != null) {
            if (existing.kind == 'client') {
              safeClientId = existing.id;
            } else if (existing.kind == 'other') {
              await (db.update(db.persons)..where((tbl) => tbl.id.equals(existing.id))).write(
                const PersonsCompanion(kind: Value('client')),
              );
              safeClientId = existing.id;
            }
          } else {
            // Auto-create client person so counterparty is safely recorded in the system!
            final newId = uuid.v4();
            await db.into(db.persons).insert(PersonsCompanion.insert(
              id: newId,
              name: row.rawParty!.trim(),
              kind: 'client',
            ));
            safeClientId = newId;
          }
        }
      }

      TransactionsCompanion companion;
      switch (type) {
        case TxType.workIn:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            clientId: Value(safeClientId),
            importHash: Value(row.importHash),
          );
          break;

        case TxType.workOut:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            personId: Value(row.personId),
            importHash: Value(row.importHash),
          );
          break;

        case TxType.income:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            clientId: Value(safeClientId),
            cashAccountId: Value(row.cashAccountId),
            importHash: Value(row.importHash),
          );
          break;

        case TxType.expense:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            cashAccountId: Value(row.cashAccountId),
            categoryId: Value(row.categoryId),
            importHash: Value(row.importHash),
          );
          break;

        case TxType.payout:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            personId: Value(row.personId),
            cashAccountId: Value(row.cashAccountId),
            purpose: Value(row.payoutPurpose ?? 'settle_payable'),
            overrideReason: Value(row.overrideReason ?? 'ورود از اکسل'),
            importHash: Value(row.importHash),
          );
          break;

        case TxType.transfer:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: projectId,
            type: type.dbValue,
            amount: row.amount!,
            date: row.isoDate!,
            description: Value(row.description),
            fromAccountId: Value(row.fromAccountId),
            toAccountId: Value(row.toAccountId),
            importHash: Value(row.importHash),
          );
          break;
      }

      try {
        await validationService.createTransactionAtomic(companion);
        insertedIds.add(txId);
        totalAmount += row.amount!;
      } catch (e) {
        if (e.toString().contains('UNIQUE constraint failed: transactions.import_hash') ||
            e.toString().contains('2067')) {
          skippedDuplicatesInCommit++;
          continue;
        }
        rethrow;
      }
    }

    return ExcelImportResult(
      totalRowsProcessed: rows.length,
      importedCount: insertedIds.length,
      duplicatesSkippedCount: duplicates.length + skippedDuplicatesInCommit,
      userSkippedCount: userSkipped.length,
      totalImportedAmount: totalAmount,
      insertedTransactionIds: insertedIds,
    );
  }
}
