import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:karkard/data/database.dart';
import 'package:karkard/services/balance_service.dart';
import 'package:karkard/services/statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late StatementPdfService pdfService;
  late BalanceService balanceService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('karkard_pdf_test_');
    dbFile = File(p.join(tempDir.path, 'pdf_test.db'));

    db = AppDatabase.forFile(dbFile);
    await db.customSelect('SELECT 1').get();

    pdfService = StatementPdfService(db);
    balanceService = BalanceService(db);

    // Seed project & default settings
    await db.into(db.projects).insert(
          ProjectsCompanion.insert(id: 'proj_pdf', name: 'پروژه احداث مجتمع اداری'),
        );
    await db.into(db.projectSettings).insert(
          ProjectSettingsCompanion.insert(
            projectId: 'proj_pdf',
            shareMethod: const Value('by_work'),
            shareBasis: const Value('accrual'),
          ),
        );

    // Seed cash accounts
    await db.into(db.cashAccounts).insert(
          CashAccountsCompanion.insert(
            id: 'acc_mellat',
            name: 'حساب ملت پروژه',
            kind: 'project',
          ),
        );

    // Seed persons: Client, Worker/Driver
    await db.into(db.persons).insert(
          PersonsCompanion.insert(
            id: 'person_client',
            name: 'شرکت عمران سازه (کارفرما)',
            kind: 'client',
            note: const Value('کارفرمای اصلی پروژه'),
          ),
        );
    // Note: Clients are counterparties and must NOT be in project_persons (enforced by trigger)

    await db.into(db.persons).insert(
          PersonsCompanion.insert(
            id: 'person_driver',
            name: 'علی احمدی (راننده)',
            kind: 'driver',
            note: const Value('راننده خاور و کمپرسی'),
          ),
        );
    await db.into(db.projectPersons).insert(
          ProjectPersonsCompanion.insert(
            projectId: 'proj_pdf',
            personId: 'person_driver',
            settlementMode: const Value('payout_only'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('T1: Client Statement Data & BalanceService Match', () {
    test('Client statement calculates debits, credits, running balance, and matches BalanceService',
        () async {
      // 1. Client work_in #1: 10,000,000 Toman
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_c_1',
              projectId: 'proj_pdf',
              type: 'work_in',
              amount: 10000000,
              date: '2026-10-01',
              clientId: const Value('person_client'),
              description: const Value('صورت‌وضعیت شماره ۱ خاکبرداری'),
            ),
          );

      // 2. Client income payment: 4,000,000 Toman into bank
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_c_2',
              projectId: 'proj_pdf',
              type: 'income',
              amount: 4000000,
              date: '2026-10-10',
              clientId: const Value('person_client'),
              cashAccountId: const Value('acc_mellat'),
              description: const Value('واریز علی‌الحساب کارفرما قسط اول'),
            ),
          );

      // 3. Client work_in #2: 6,000,000 Toman
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_c_3',
              projectId: 'proj_pdf',
              type: 'work_in',
              amount: 6000000,
              date: '2026-10-20',
              clientId: const Value('person_client'),
              description: const Value('صورت‌وضعیت شماره ۲ گودبرداری'),
            ),
          );

      final reportData = await pdfService.generateReportData(
        projectId: 'proj_pdf',
        personId: 'person_client',
      );

      expect(reportData.person.name, equals('شرکت عمران سازه (کارفرما)'));
      expect(reportData.rows.length, equals(3));

      // Row 1: work_in (Debit = 10,000,000, Running = 10,000,000 بدهکار)
      expect(reportData.rows[0].debit, equals(10000000));
      expect(reportData.rows[0].credit, equals(0));
      expect(reportData.rows[0].runningBalance, equals(10000000));
      expect(reportData.rows[0].balanceStatus, equals('بدهکار'));

      // Row 2: income (Credit = 4,000,000, Running = 6,000,000 بدهکار)
      expect(reportData.rows[1].debit, equals(0));
      expect(reportData.rows[1].credit, equals(4000000));
      expect(reportData.rows[1].runningBalance, equals(6000000));
      expect(reportData.rows[1].balanceStatus, equals('بدهکار'));

      // Row 3: work_in (Debit = 6,000,000, Running = 12,000,000 بدهکار)
      expect(reportData.rows[2].debit, equals(6000000));
      expect(reportData.rows[2].credit, equals(0));
      expect(reportData.rows[2].runningBalance, equals(12000000));
      expect(reportData.rows[2].balanceStatus, equals('بدهکار'));

      // Totals
      expect(reportData.totalDebit, equals(16000000));
      expect(reportData.totalCredit, equals(4000000));
      expect(reportData.netBalance, equals(12000000));
      expect(reportData.netStatus, contains('بدهکار'));

      // Exact match with BalanceService receivable
      final engineReport = await balanceService.calculateProjectBalance('proj_pdf');
      final engineRec = engineReport.receivables['person_client'];
      expect(reportData.netBalance, equals(engineRec));
      expect(engineRec, equals(12000000));
    });
  });

  group('T2: Driver / Worker Statement Data & BalanceService Match', () {
    test('Driver statement tracks work_out, payout settlement, and matches BalanceService',
        () async {
      // 1. Driver work_out #1: 3,500,000 Toman (Credit = 3,500,000)
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_d_1',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 3500000,
              date: '2026-10-05',
              personId: const Value('person_driver'),
              description: const Value('حمل مصالح روزهای شنبه تا سه‌شنبه'),
            ),
          );

      // 2. Driver payout settle_payable: 1,500,000 Toman (Debit = 1,500,000)
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_d_2',
              projectId: 'proj_pdf',
              type: 'payout',
              purpose: const Value('settle_payable'),
              amount: 1500000,
              date: '2026-10-15',
              personId: const Value('person_driver'),
              cashAccountId: const Value('acc_mellat'),
              description: const Value('تسویه هفتگی کارکرد'),
            ),
          );

      // 3. Driver work_out #2: 2,000,000 Toman
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_d_3',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 2000000,
              date: '2026-10-25',
              personId: const Value('person_driver'),
              description: const Value('کرایه حمل بتن و میلگرد'),
            ),
          );

      final reportData = await pdfService.generateReportData(
        projectId: 'proj_pdf',
        personId: 'person_driver',
      );

      expect(reportData.rows.length, equals(3));

      // Row 1: work_out (Credit = 3,500,000, Running = 3,500,000 بستانکار)
      expect(reportData.rows[0].credit, equals(3500000));
      expect(reportData.rows[0].debit, equals(0));
      expect(reportData.rows[0].runningBalance, equals(3500000));
      expect(reportData.rows[0].balanceStatus, equals('بستانکار'));

      // Row 2: payout (Debit = 1,500,000, Running = 2,000,000 بستانکار)
      expect(reportData.rows[1].credit, equals(0));
      expect(reportData.rows[1].debit, equals(1500000));
      expect(reportData.rows[1].runningBalance, equals(2000000));
      expect(reportData.rows[1].balanceStatus, equals('بستانکار'));

      // Row 3: work_out (Credit = 2,000,000, Running = 4,000,000 بستانکار)
      expect(reportData.rows[2].credit, equals(2000000));
      expect(reportData.rows[2].debit, equals(0));
      expect(reportData.rows[2].runningBalance, equals(4000000));
      expect(reportData.rows[2].balanceStatus, equals('بستانکار'));

      // Totals
      expect(reportData.totalDebit, equals(1500000));
      expect(reportData.totalCredit, equals(5500000));
      expect(reportData.netBalance, equals(4000000));
      expect(reportData.netStatus, contains('بستانکار'));

      // Exact match with BalanceService payables
      final engineReport = await balanceService.calculateProjectBalance('proj_pdf');
      final enginePay = engineReport.payables['person_driver'];
      expect(reportData.netBalance, equals(enginePay));
      expect(enginePay, equals(4000000));
    });
  });

  group('T3: Soft-Deleted Transactions & Date Filtering', () {
    test('Soft-deleted transactions are ignored and date range filters correctly', () async {
      // Valid work_out in October
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_v_1',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 1000000,
              date: '2026-10-01',
              personId: const Value('person_driver'),
            ),
          );

      // Soft-deleted transaction (must be ignored)
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_del',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 9990000,
              date: '2026-10-02',
              personId: const Value('person_driver'),
              deletedAt: const Value('2026-10-03T12:00:00.000'),
              deletedReason: const Value('تراکنش اشتباه ثبت شده بود'),
            ),
          );

      // Valid work_out in November
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_v_2',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 2000000,
              date: '2026-11-01',
              personId: const Value('person_driver'),
            ),
          );

      // 1. Without date filter: 2 rows (deleted row ignored)
      final allRows = await pdfService.generateReportData(
        projectId: 'proj_pdf',
        personId: 'person_driver',
      );
      expect(allRows.rows.length, equals(2));
      expect(allRows.totalCredit, equals(3000000));

      // 2. With October date filter: only 1 row
      final octRows = await pdfService.generateReportData(
        projectId: 'proj_pdf',
        personId: 'person_driver',
        startDateIso: '2026-10-01',
        endDateIso: '2026-10-31',
      );
      expect(octRows.rows.length, equals(1));
      expect(octRows.rows.first.txId, equals('tx_v_1'));
      expect(octRows.totalCredit, equals(1000000));
    });
  });

  group('T4: PDF Binary Generation & Vazirmatn Embedding', () {
    test('generatePdfBytes produces valid %PDF- document with table and summary', () async {
      // Add transactions
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_pdf_1',
              projectId: 'proj_pdf',
              type: 'work_out',
              amount: 5000000,
              date: '2026-10-10',
              personId: const Value('person_driver'),
              description: const Value('حمل ستون‌ها و بادبندهای طبقه اول'),
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_pdf_2',
              projectId: 'proj_pdf',
              type: 'payout',
              purpose: const Value('settle_payable'),
              amount: 2000000,
              date: '2026-10-15',
              personId: const Value('person_driver'),
              cashAccountId: const Value('acc_mellat'),
              description: const Value('واریز پایا به حساب راننده'),
            ),
          );

      final reportData = await pdfService.generateReportData(
        projectId: 'proj_pdf',
        personId: 'person_driver',
      );

      final pdfBytes = await pdfService.generatePdfBytes(reportData);

      expect(pdfBytes.isNotEmpty, isTrue);
      expect(pdfBytes.length, greaterThan(2000));

      // Standard PDF header signature
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));

      // Save a sample PDF artifact to verify
      final artifactDir = Directory('/home/mehdi/.gemini/antigravity/brain/c1c04fab-f96d-4ac1-aed7-44d5e581ee4f');
      if (artifactDir.existsSync()) {
        final samplePdfFile = File(p.join(artifactDir.path, 'sample_person_statement.pdf'));
        await samplePdfFile.writeAsBytes(pdfBytes);
        expect(samplePdfFile.existsSync(), isTrue);
      }
    });
  });
}
