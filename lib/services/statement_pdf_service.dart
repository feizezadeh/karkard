import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/jalali.dart';
import '../core/money.dart';
import '../data/database.dart';
import 'balance_service.dart';

/// Single transaction line in the person account statement.
class StatementRow {
  final int rowIndex;
  final String txId;
  final String dateIso;
  final String dateJalali;
  final String type;
  final String typeLabel;
  final String description;
  final String? accountName;
  final int debit; // تومان بدهکار
  final int credit; // تومان بستانکار
  final int runningBalance; // مانده پس از ردیف (تومان)
  final String balanceStatus; // «بس» (بستانکار) | «بد» (بدهکار) | «تسویه»

  const StatementRow({
    required this.rowIndex,
    required this.txId,
    required this.dateIso,
    required this.dateJalali,
    required this.type,
    required this.typeLabel,
    required this.description,
    this.accountName,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    required this.balanceStatus,
  });
}

/// Complete statement document model ready for rendering/export.
class PersonStatementReport {
  final Person person;
  final Project project;
  final String generatedAtIso;
  final String generatedAtJalali;
  final String? periodStartJalali;
  final String? periodEndJalali;
  final List<StatementRow> rows;
  final int totalDebit;
  final int totalCredit;
  final int netBalance; // Absolute net balance
  final String netStatus; // «بستانکار (طلبکار از پروژه)» | «بدهکار (بدهکار به پروژه)» | «تسویه حساب کامل»
  final PersonBalance? engineBalance; // Exact match with BalanceService

  const PersonStatementReport({
    required this.person,
    required this.project,
    required this.generatedAtIso,
    required this.generatedAtJalali,
    this.periodStartJalali,
    this.periodEndJalali,
    required this.rows,
    required this.totalDebit,
    required this.totalCredit,
    required this.netBalance,
    required this.netStatus,
    this.engineBalance,
  });
}

class StatementPdfService {
  final AppDatabase db;

  const StatementPdfService(this.db);

  /// Translates person kind to Persian label.
  static String personKindLabel(String kind) {
    switch (kind) {
      case 'client':
        return 'کارفرما';
      case 'partner':
        return 'شریک';
      case 'driver':
        return 'راننده';
      case 'worker':
        return 'پرسنل / کارگر';
      case 'contractor':
        return 'پیمانکار جز';
      default:
        return 'سایر';
    }
  }

  /// Translates transaction type and purpose to Persian label.
  static String txTypeLabel(String type, String? purpose) {
    switch (type) {
      case 'work_in':
        return 'صورت‌وضعیت کارفرما';
      case 'work_out':
        return 'کارکرد و خدمات';
      case 'income':
        return 'دریافت از کارفرما';
      case 'expense':
        return 'هزینه منتسب';
      case 'payout':
        if (purpose == 'distribution') return 'توزیع سود شریک';
        return 'پرداخت و تسویه';
      case 'transfer':
        return 'انتقال حساب';
      default:
        return type;
    }
  }

  /// Compiles statement report data from DB.
  Future<PersonStatementReport> generateReportData({
    required String projectId,
    required String personId,
    String? startDateIso,
    String? endDateIso,
  }) async {
    final person = await (db.select(db.persons)..where((p) => p.id.equals(personId))).getSingle();
    final project = await (db.select(db.projects)..where((p) => p.id.equals(projectId))).getSingle();

    // Load cash accounts to display account names
    final accounts = await db.select(db.cashAccounts).get();
    final accountMap = {for (final a in accounts) a.id: a.name};

    // Load active transactions for this project
    final allTx = await (db.select(db.transactions)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull()))
        .get();

    // Accounts held by this person (personal card/account custody)
    final personalAccountIds = accounts
        .where((a) => a.kind == 'personal' && a.holderPersonId == personId)
        .map((a) => a.id)
        .toSet();

    // Filter transactions relevant to this person
    final relevantTx = allTx.where((tx) {
      if (startDateIso != null && tx.date.compareTo(startDateIso) < 0) return false;
      if (endDateIso != null && tx.date.compareTo(endDateIso) > 0) return false;

      // Match by person fields
      if (tx.personId == personId) return true;
      if (tx.clientId == personId) return true;
      if (tx.performedBy == personId) return true;
      if (tx.attributedTo == personId) return true;

      // Match by personal account held by this person
      if (tx.cashAccountId != null && personalAccountIds.contains(tx.cashAccountId)) return true;
      if (tx.fromAccountId != null && personalAccountIds.contains(tx.fromAccountId)) return true;
      if (tx.toAccountId != null && personalAccountIds.contains(tx.toAccountId)) return true;

      return false;
    }).toList();

    // Sort chronologically
    relevantTx.sort((a, b) {
      final c1 = a.date.compareTo(b.date);
      if (c1 != 0) return c1;
      final c2 = a.createdAt.compareTo(b.createdAt);
      if (c2 != 0) return c2;
      return a.id.compareTo(b.id);
    });

    final isClient = person.kind == 'client';
    var runningBalance = 0;
    var totalDebit = 0;
    var totalCredit = 0;
    var rowIndex = 1;

    final rows = <StatementRow>[];

    // Compute opening balance if period start date is provided
    if (startDateIso != null) {
      final priorTx = allTx.where((tx) {
        if (tx.date.compareTo(startDateIso) >= 0) return false;
        if (tx.personId == personId || tx.clientId == personId || tx.performedBy == personId || tx.attributedTo == personId) return true;
        if (tx.cashAccountId != null && personalAccountIds.contains(tx.cashAccountId)) return true;
        if (tx.fromAccountId != null && personalAccountIds.contains(tx.fromAccountId)) return true;
        if (tx.toAccountId != null && personalAccountIds.contains(tx.toAccountId)) return true;
        return false;
      });

      for (final tx in priorTx) {
        var debit = 0;
        var credit = 0;
        if (isClient) {
          if (tx.type == 'work_in' && tx.clientId == personId) {
            debit = tx.amount;
          } else if (tx.type == 'income' && tx.clientId == personId) {
            credit = tx.amount;
          }
          runningBalance = runningBalance + debit - credit;
        } else {
          if (tx.type == 'work_out' && tx.personId == personId) {
            credit = tx.amount;
          } else if (tx.type == 'payout' && tx.personId == personId) {
            debit = tx.amount;
          } else if (tx.type == 'expense' && tx.attributedTo == personId) {
            debit = tx.amount;
          } else if (tx.type == 'income' && personalAccountIds.contains(tx.cashAccountId)) {
            debit = tx.amount;
          } else if (tx.type == 'payout' && personalAccountIds.contains(tx.cashAccountId)) {
            credit = tx.amount;
          }
          runningBalance = runningBalance + credit - debit;
        }
      }

      if (runningBalance != 0) {
        final initialDebit = isClient ? (runningBalance > 0 ? runningBalance : 0) : (runningBalance < 0 ? -runningBalance : 0);
        final initialCredit = isClient ? (runningBalance < 0 ? -runningBalance : 0) : (runningBalance > 0 ? runningBalance : 0);
        totalDebit += initialDebit;
        totalCredit += initialCredit;

        String initialStatus;
        if (runningBalance > 0) {
          initialStatus = isClient ? 'بدهکار' : 'بستانکار';
        } else {
          initialStatus = isClient ? 'بستانکار' : 'بدهکار';
        }

        rows.add(
          StatementRow(
            rowIndex: rowIndex++,
            txId: 'opening_balance',
            dateIso: startDateIso,
            dateJalali: isoToJalali(startDateIso),
            type: 'opening',
            typeLabel: 'مانده از قبل',
            description: 'مانده انتقالی ابتدای دوره',
            accountName: null,
            debit: initialDebit,
            credit: initialCredit,
            runningBalance: runningBalance.abs(),
            balanceStatus: initialStatus,
          ),
        );
      }
    }

    for (final tx in relevantTx) {
      var debit = 0;
      var credit = 0;

      if (isClient) {
        // Client accounting:
        // work_in = debit (client owes project)
        // income = credit (client paid project)
        if (tx.type == 'work_in' && tx.clientId == personId) {
          debit = tx.amount;
        } else if (tx.type == 'income' && tx.clientId == personId) {
          credit = tx.amount;
        }
      } else {
        // Payee/Partner accounting:
        // work_out = credit (project owes person for services)
        // payout = debit (project paid person or distribution)
        // expense attributed = debit
        // personal account deposits/withdrawals
        if (tx.type == 'work_out') {
          if (tx.personId == personId) {
            credit = tx.amount;
          }
        } else if (tx.type == 'payout') {
          if (tx.personId == personId) {
            debit = tx.amount;
          }
        } else if (tx.type == 'expense' && tx.attributedTo == personId) {
          debit = tx.amount;
        } else if (tx.type == 'income' && personalAccountIds.contains(tx.cashAccountId)) {
          // Money deposited into personal account held by person -> person owes project
          debit = tx.amount;
        } else if (tx.type == 'payout' && personalAccountIds.contains(tx.cashAccountId)) {
          // Money paid out from personal account held by person -> person paid for project
          credit = tx.amount;
        }
      }

      totalDebit += debit;
      totalCredit += credit;

      if (isClient) {
        runningBalance = runningBalance + debit - credit;
      } else {
        runningBalance = runningBalance + credit - debit;
      }

      String balanceStatus;
      if (runningBalance > 0) {
        balanceStatus = isClient ? 'بدهکار' : 'بستانکار';
      } else if (runningBalance < 0) {
        balanceStatus = isClient ? 'بستانکار' : 'بدهکار';
      } else {
        balanceStatus = 'تسویه';
      }

      String? accountLabel;
      if (tx.cashAccountId != null) {
        accountLabel = accountMap[tx.cashAccountId];
      } else if (tx.fromAccountId != null && tx.toAccountId != null) {
        accountLabel = '${accountMap[tx.fromAccountId]} ← ${accountMap[tx.toAccountId]}';
      }

      rows.add(
        StatementRow(
          rowIndex: rowIndex++,
          txId: tx.id,
          dateIso: tx.date,
          dateJalali: isoToJalali(tx.date),
          type: tx.type,
          typeLabel: txTypeLabel(tx.type, tx.purpose),
          description: tx.description,
          accountName: accountLabel,
          debit: debit,
          credit: credit,
          runningBalance: runningBalance.abs(),
          balanceStatus: balanceStatus,
        ),
      );
    }

    // Engine validation against BalanceService
    PersonBalance? engineBalance;
    try {
      final balanceService = BalanceService(db);
      final report = await balanceService.calculateProjectBalance(projectId);
      engineBalance = report.personBalances[personId];
    } catch (_) {}

    final now = DateTime.now();
    final generatedAtIso = now.toIso8601String().split('T').first;
    final generatedAtJalali = isoToJalali(generatedAtIso);

    String netStatus;
    if (runningBalance > 0) {
      netStatus = isClient ? 'بدهکار (بدهکار به پروژه)' : 'بستانکار (طلبکار از پروژه)';
    } else if (runningBalance < 0) {
      netStatus = isClient ? 'بستانکار (طلبکار از پروژه)' : 'بدهکار (بدهکار به پروژه)';
    } else {
      netStatus = 'تسویه حساب کامل';
    }

    return PersonStatementReport(
      person: person,
      project: project,
      generatedAtIso: generatedAtIso,
      generatedAtJalali: generatedAtJalali,
      periodStartJalali: startDateIso != null ? isoToJalali(startDateIso) : null,
      periodEndJalali: endDateIso != null ? isoToJalali(endDateIso) : null,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      netBalance: runningBalance.abs(),
      netStatus: netStatus,
      engineBalance: engineBalance,
    );
  }

  /// Builds a printable PDF document from report data.
  Future<Uint8List> generatePdfBytes(
    PersonStatementReport report, {
    Uint8List? regularFontBytes,
    Uint8List? boldFontBytes,
  }) async {
    final regularBytes = regularFontBytes ?? await _loadFont('assets/fonts/Vazirmatn-Regular.ttf');
    final boldBytes = boldFontBytes ?? await _loadFont('assets/fonts/Vazirmatn-Bold.ttf');

    final ttfRegular = pw.Font.ttf(regularBytes.buffer.asByteData());
    final ttfBold = pw.Font.ttf(boldBytes.buffer.asByteData());

    final doc = pw.Document();

    final pdfTheme = pw.ThemeData.withFont(
      base: ttfRegular,
      bold: ttfBold,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pdfTheme,
        textDirection: pw.TextDirection.rtl,
        header: (context) => _buildHeader(context, report),
        footer: (context) => _buildFooter(context, report),
        build: (context) => [
          _buildSummaryCards(report),
          pw.SizedBox(height: 16),
          _buildTransactionsTable(report),
          pw.SizedBox(height: 24),
          _buildSignaturesBlock(),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(pw.Context context, PersonStatementReport report) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.teal, width: 2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'صورت‌حساب وضعیت مالی شخص',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'پروژه: ${report.project.name}',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey800),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'تاریخ گزارش: ${report.generatedAtJalali}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                  if (report.periodStartJalali != null || report.periodEndJalali != null) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'بازه: ${report.periodStartJalali ?? 'ابتدا'} تا ${report.periodEndJalali ?? 'امروز'}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.Text('نام و نام خانوادگی: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(report.person.name, style: const pw.TextStyle(fontSize: 10)),
                if (report.person.code != null && report.person.code!.isNotEmpty) ...[
                  pw.SizedBox(width: 24),
                  pw.Text('کد تفصیلی: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(report.person.code!, style: const pw.TextStyle(fontSize: 10)),
                ],
                pw.SizedBox(width: 24),
                pw.Text('نقش: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(personKindLabel(report.person.kind), style: const pw.TextStyle(fontSize: 10)),
                if (report.person.note != null && report.person.note!.isNotEmpty) ...[
                  pw.SizedBox(width: 24),
                  pw.Text('یادداشت: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text(report.person.note!, style: const pw.TextStyle(fontSize: 10)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryCards(PersonStatementReport report) {
    return pw.Row(
      children: [
        _buildSummaryCell('جمع بدهکار (تومان)', formatToman(report.totalDebit), PdfColors.blueGrey800),
        pw.SizedBox(width: 8),
        _buildSummaryCell('جمع بستانکار (تومان)', formatToman(report.totalCredit), PdfColors.teal800),
        pw.SizedBox(width: 8),
        _buildSummaryCell('مانده نهایی (تومان)', formatToman(report.netBalance), PdfColors.purple800,
            subtitle: report.netStatus),
      ],
    );
  }

  pw.Widget _buildSummaryCell(String title, String value, PdfColor color, {String? subtitle}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: pw.BorderRadius.circular(6),
          color: PdfColors.white,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
            if (subtitle != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(subtitle, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _buildTransactionsTable(PersonStatementReport report) {
    const headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 8, color: PdfColors.grey900);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(24), // ردیف
        1: pw.FixedColumnWidth(48), // تاریخ
        2: pw.FixedColumnWidth(70), // نوع
        3: pw.FlexColumnWidth(2.2), // شرح
        4: pw.FlexColumnWidth(1.2), // حساب
        5: pw.FixedColumnWidth(54), // بدهکار
        6: pw.FixedColumnWidth(54), // بستانکار
        7: pw.FixedColumnWidth(58), // مانده
        8: pw.FixedColumnWidth(30), // وضعیت
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.teal800),
          children: [
            _tableHeaderCell('ردیف', headerStyle),
            _tableHeaderCell('تاریخ', headerStyle),
            _tableHeaderCell('نوع تراکنش', headerStyle),
            _tableHeaderCell('شرح و بابت', headerStyle),
            _tableHeaderCell('حساب / مدرک', headerStyle),
            _tableHeaderCell('بدهکار', headerStyle),
            _tableHeaderCell('بستانکار', headerStyle),
            _tableHeaderCell('مانده', headerStyle),
            _tableHeaderCell('وضعیت', headerStyle),
          ],
        ),
        // Data Rows
        ...report.rows.map((row) {
          final isEven = row.rowIndex % 2 == 0;
          final rowBg = isEven ? PdfColors.grey50 : PdfColors.white;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              _tableDataCell(toFaDigits(row.rowIndex.toString()), cellStyle, align: pw.TextAlign.center),
              _tableDataCell(row.dateJalali, cellStyle, align: pw.TextAlign.center),
              _tableDataCell(row.typeLabel, cellStyle),
              _tableDataCell(row.description, cellStyle),
              _tableDataCell(row.accountName ?? '-', cellStyle),
              _tableDataCell(row.debit > 0 ? formatToman(row.debit) : '-', cellStyle, align: pw.TextAlign.left),
              _tableDataCell(row.credit > 0 ? formatToman(row.credit) : '-', cellStyle, align: pw.TextAlign.left),
              _tableDataCell(formatToman(row.runningBalance), cellStyle, align: pw.TextAlign.left),
              _tableDataCell(row.balanceStatus, cellStyle, align: pw.TextAlign.center),
            ],
          );
        }),
        // Totals Footer Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableDataCell('جمع', pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), align: pw.TextAlign.center),
            _tableDataCell('', cellStyle),
            _tableDataCell('', cellStyle),
            _tableDataCell('جمع کل مبالغ ستون‌ها', pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            _tableDataCell('', cellStyle),
            _tableDataCell(formatToman(report.totalDebit), pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.left),
            _tableDataCell(formatToman(report.totalCredit), pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.left),
            _tableDataCell(formatToman(report.netBalance), pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.left),
            _tableDataCell(report.netStatus.split(' ').first, pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                align: pw.TextAlign.center),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableHeaderCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Center(
        child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
      ),
    );
  }

  pw.Widget _tableDataCell(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.right,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  pw.Widget _buildSignaturesBlock() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            children: [
              pw.Text('مهر و امضای امور مالی / صادرکننده', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
              pw.SizedBox(height: 48),
              pw.Container(width: 140, height: 1, color: PdfColors.grey400),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('امضا و تأیید طرف حساب', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
              pw.SizedBox(height: 48),
              pw.Container(width: 140, height: 1, color: PdfColors.grey400),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context, PersonStatementReport report) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('سامانه مدیریت مالی «دفتر کارکرد»', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text(
            toFaDigits('صفحه ${context.pageNumber} از ${context.pagesCount}'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _loadFont(String path) async {
    try {
      final byteData = await rootBundle.load(path);
      return byteData.buffer.asUint8List();
    } catch (_) {
      final file = File(path);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
      rethrow;
    }
  }
}
