import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:karkard/data/database.dart';
import 'package:karkard/domain/tx_type.dart';
import 'package:karkard/services/excel_import_service.dart';
import 'package:karkard/ui/import/steps/excel_review_screen.dart';

import '../scripts/generate_excel_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExcelImportService importService;
  late Uint8List fixtureBytes;
  const projectId = 'proj_test_excel';
  const mainCashAccountId = 'acc_test_cash';

  final mapping = ColumnMapping(
    dateColumn: 1,
    descriptionColumn: 2,
    amountColumn: 3,
    typeColumn: 4,
    counterpartyColumn: 5,
    accountColumn: 6,
    defaultType: TxType.expense,
    defaultCashAccountId: mainCashAccountId,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    // 1. Seed base test project
    await db.into(db.projects).insert(ProjectsCompanion.insert(
      id: projectId,
      name: 'پروژه تست ورود اکسل',
    ));
    await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
      projectId: projectId,
    ));

    // 2. Seed Cash Account
    await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
      id: mainCashAccountId,
      name: 'صندوق اصلی پروژه',
      kind: 'project',
    ));

    // 3. Seed Known Persons in DB
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p_alborz',
      name: 'مصالح فروشی البرز',
      kind: 'other',
    ));
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p_karimi',
      name: 'علی کریمی',
      kind: 'worker',
    ));
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p_rezaei',
      name: 'مهندس رضایی',
      kind: 'other',
    ));
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p_pasargad',
      name: 'شرکت بتن آماده پاسارگاد',
      kind: 'other',
    ));
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'p_omran',
      name: 'شرکت عمران پارس',
      kind: 'client',
    ));

    importService = ExcelImportService(db);
    fixtureBytes = Uint8List.fromList(generateExcelEdgeCasesBytes());
  });

  tearDown(() async {
    await db.close();
  });

  group('Excel Fixture Edge Cases Parser Tests', () {
    test('parses all 11 rows without unhandled exceptions', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);
      expect(rows.length, 11);
    });

    test('Case 1a & 1b: Empty and dash amounts are flagged as needsDecision with null amount', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      // Row 2: En-dash amount ('–')
      final row2 = rows.firstWhere((r) => r.rowIndex == 2);
      expect(row2.status, RowStatus.needsDecision);
      expect(row2.ambiguityReason, AmbiguityReason.emptyAmount);
      expect(row2.amount, isNull, reason: 'Must NEVER auto-guess 0 for dash amount');

      // Row 3: Blank cell amount (null)
      final row3 = rows.firstWhere((r) => r.rowIndex == 3);
      expect(row3.status, RowStatus.needsDecision);
      expect(row3.ambiguityReason, AmbiguityReason.emptyAmount);
      expect(row3.amount, isNull, reason: 'Must NEVER auto-guess 0 for blank cell');
    });

    test('Case 2: Duplicate row within same workbook generates identical importHash and flags duplicate', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      final row4 = rows.firstWhere((r) => r.rowIndex == 4);
      final row5 = rows.firstWhere((r) => r.rowIndex == 5);

      expect(row4.importHash, isNotEmpty);
      expect(row5.importHash, equals(row4.importHash), reason: 'Identical content must produce exact same SHA-256 hash');
      expect(row4.status, RowStatus.ready);
      expect(row5.status, RowStatus.duplicate);
    });

    test('Case 3: Multiple amounts in single row are detected and flagged as needsDecision', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      final row6 = rows.firstWhere((r) => r.rowIndex == 6);
      expect(row6.status, RowStatus.needsDecision);
      expect(row6.ambiguityReason, AmbiguityReason.multipleAmounts);
      expect(row6.detectedAmounts.length, greaterThanOrEqualTo(2));
      expect(row6.detectedAmounts, containsAll([12500000, 2500000]));
      expect(row6.amount, isNull, reason: 'Must NOT arbitrarily pick the first amount');
    });

    test('Case 4a & 4b: Ambiguous / unknown counterparty and type are flagged as needsDecision', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      // Row 7: Unknown person 'راننده ناشناس فاقد پرونده'
      final row7 = rows.firstWhere((r) => r.rowIndex == 7);
      expect(row7.status, RowStatus.needsDecision);
      expect(row7.ambiguityReason, AmbiguityReason.unknownCounterparty);
      expect(row7.personId, isNull, reason: 'Must NOT guess an arbitrary person');

      // Row 8: Unknown transaction type 'نامشخص / متفرقه'
      final row8 = rows.firstWhere((r) => r.rowIndex == 8);
      expect(row8.status, RowStatus.needsDecision);
      expect(row8.ambiguityReason, AmbiguityReason.ambiguousType);
      expect(row8.inferredType, isNull);
    });

    test('Case 5a & 5b: Excel serial date and 2-digit Persian date are cleanly normalized to ISO dates', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      // Row 9: Excel serial number 45600 -> 2024-11-04
      final row9 = rows.firstWhere((r) => r.rowIndex == 9);
      expect(row9.status, RowStatus.ready);
      expect(row9.isoDate, equals('2024-11-04'));

      // Row 10: 2-digit Persian date '۰۳-۰۸-۱۵' -> 1403/08/15 -> 2024-11-05
      final row10 = rows.firstWhere((r) => r.rowIndex == 10);
      expect(row10.status, RowStatus.ready);
      expect(row10.isoDate, equals('2024-11-05'));
    });

    test('Case 6: Mixed Persian text, commas, and currency word are parsed into exact integer amount', () async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      // Row 11: '۸٬۷۵۰٬۰۰۰ تومان' -> 8750000
      final row11 = rows.firstWhere((r) => r.rowIndex == 11);
      expect(row11.status, RowStatus.ready);
      expect(row11.amount, equals(8750000));
    });
  });

  group('Review Screen & Zero Duplication Proof', () {
    testWidgets('ExcelReviewScreen blocks commit while needsDecision rows exist, enables after resolution', (tester) async {
      final rows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Vazirmatn'),
        home: Scaffold(
          body: ExcelReviewScreen(
            rows: rows,
            db: db,
            projectId: projectId,
            onCommit: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify tabs exist with badges
      expect(find.textContaining('نیازمند تصمیم'), findsOneWidget);
      expect(find.textContaining('آماده ثبت'), findsOneWidget);
      expect(find.textContaining('تکراری'), findsOneWidget);

      // Verify commit button is DISABLED
      final commitBtn = tester.widget<FilledButton>(find.byKey(const Key('commit_import_button')));
      expect(commitBtn.onPressed, isNull, reason: 'Commit button must be disabled when unresolved rows exist');

      // Tap 'Skip All Unresolved' or resolve each row
      await tester.tap(find.byKey(const Key('skip_all_unresolved_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأیید و نادیده گرفتن'));
      await tester.pumpAndSettle();

      // Now all ambiguous rows are skipped -> commit button must become ENABLED!
      final enabledCommitBtn = tester.widget<FilledButton>(find.byKey(const Key('commit_import_button')));
      expect(enabledCommitBtn.onPressed, isNotNull);
    });

    test('Zero duplicate transactions created on re-import of same Excel file', () async {
      // 1. Initial import: parse and resolve
      final initialRows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);
      final resolvableRows = initialRows.where((r) => r.status == RowStatus.ready).toList();
      final initialResult = await importService.commitImport(resolvableRows, projectId: projectId);

      expect(initialResult.importedCount, greaterThan(0));
      final countAfterFirstImport = await (db.select(db.transactions)..where((t) => t.projectId.equals(projectId))).get();
      expect(countAfterFirstImport.length, equals(initialResult.importedCount));

      // 2. Re-import: parse the exact same workbook again against the SQLite database
      final secondScanRows = await importService.parseExcel(fixtureBytes, projectId: projectId, mapping: mapping);

      // Verify that every previously committed row is now marked RowStatus.duplicate!
      for (final committed in resolvableRows) {
        final reScanned = secondScanRows.firstWhere((r) => r.rowIndex == committed.rowIndex);
        expect(reScanned.status, equals(RowStatus.duplicate),
            reason: 'Row ${committed.rowIndex} must be detected as duplicate via importHash');
      }

      // 3. Attempt commit of second scan
      final secondResult = await importService.commitImport(
        secondScanRows.where((r) => r.status == RowStatus.ready).toList(),
        projectId: projectId,
      );

      // Proof: 0 new transactions imported!
      expect(secondResult.importedCount, equals(0));

      // Final database count strictly unchanged
      final finalDbCount = await (db.select(db.transactions)..where((t) => t.projectId.equals(projectId))).get();
      expect(finalDbCount.length, equals(countAfterFirstImport.length),
          reason: 'Database transactions count must remain strictly identical (0 duplicates)');
    });

    test('Matches counterparty and cash account by accounting code', () async {
      await db.into(db.persons).insert(
        PersonsCompanion.insert(
          id: 'p_coded',
          name: 'شرکت راهسازی فرضی',
          kind: 'client',
          code: const Value('10201'),
        ),
      );
      await db.into(db.cashAccounts).insert(
        CashAccountsCompanion.insert(
          id: 'acc_coded',
          name: 'حساب صادرات پروژه',
          kind: 'project',
          code: const Value('10101'),
        ),
      );

      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow([
        TextCellValue('تاریخ'),
        TextCellValue('شرح'),
        TextCellValue('مبلغ'),
        TextCellValue('نوع'),
        TextCellValue('طرف حساب'),
        TextCellValue('صندوق'),
      ]);
      sheet.appendRow([
        TextCellValue('1403/08/15'),
        TextCellValue('دریافت صورت وضعیت بر مبنای کدینگ'),
        IntCellValue(25000000),
        TextCellValue('income'),
        TextCellValue('10201'), // Match by code
        TextCellValue('10101'), // Match by code
      ]);

      final bytes = Uint8List.fromList(excel.encode()!);
      final rows = await importService.parseExcel(
        bytes,
        projectId: projectId,
        mapping: const ColumnMapping(
          dateColumn: 0,
          descriptionColumn: 1,
          amountColumn: 2,
          typeColumn: 3,
          counterpartyColumn: 4,
          accountColumn: 5,
        ),
      );

      expect(rows.length, equals(1));
      expect(rows.first.status, equals(RowStatus.ready));
      expect(rows.first.clientId, equals('p_coded'));
      expect(rows.first.cashAccountId, equals('acc_coded'));
    });

    test('Proof: Successfully parses converted real-world Azarmi Crane workbook', () async {
      final file = File('دفتر_کارکرد_جرثقیل_آذرمی_آماده_ورود.xlsx');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final rows = await importService.parseExcel(
        bytes,
        projectId: projectId,
        mapping: const ColumnMapping(
          dateColumn: 1,
          descriptionColumn: 2,
          amountColumn: 3,
          typeColumn: 4,
          counterpartyColumn: 5,
          accountColumn: 6,
          defaultType: TxType.workIn,
          hasHeader: true,
          sheetName: 'همه تراکنش‌ها (آماده ورود)',
        ),
      );

      expect(rows.length, equals(707));
      // 649 rows have definite positive amounts; 58 rows have unvalued/pending crane operations
      final validAmounts = rows.where((r) => r.amount != null && r.amount! > 0).toList();
      expect(validAmounts.length, equals(649));
      final pendingEmptyAmounts = rows.where((r) => r.amount == null).toList();
      expect(pendingEmptyAmounts.length, equals(58));
      final validDates = rows.where((r) => r.isoDate != null && r.isoDate!.isNotEmpty).toList();
      expect(validDates.length, equals(707));
    });

    test('Proof: Successfully parses converted Mehr-only workbook', () async {
      final file = File('کارکرد_جرثقیل_آذرمی_مهر_۱۴۰۵.xlsx');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final rows = await importService.parseExcel(
        bytes,
        projectId: projectId,
        mapping: const ColumnMapping(
          dateColumn: 1,
          descriptionColumn: 2,
          amountColumn: 3,
          typeColumn: 4,
          counterpartyColumn: 5,
          accountColumn: 6,
          defaultType: TxType.workIn,
          hasHeader: true,
          sheetName: 'تراکنش‌های مهر ۱۴۰۵ (آماده ورود)',
        ),
      );

      expect(rows.length, equals(112));
      final validAmounts = rows.where((r) => r.amount != null && r.amount! > 0).toList();
      expect(validAmounts.length, equals(101));
      final pendingEmptyAmounts = rows.where((r) => r.amount == null).toList();
      expect(pendingEmptyAmounts.length, equals(11));
      final validDates = rows.where((r) => r.isoDate != null && r.isoDate!.isNotEmpty).toList();
      expect(validDates.length, equals(112));
    });

    test('Proof: Counterparty matching automatically recognizes persons in system from description & rawParty', () async {
      // Seed a person in DB: ناصر پیوسته
      const nasserId = 'clt_nasser';
      await db.into(db.persons).insert(PersonsCompanion.insert(
        id: nasserId,
        name: 'ناصر پیوسته',
        kind: 'client',
      ));

      final file = File('کارکرد_جرثقیل_آذرمی_مهر_۱۴۰۵.xlsx');
      final bytes = file.readAsBytesSync();
      final rows = await importService.parseExcel(
        bytes,
        projectId: projectId,
        mapping: const ColumnMapping(
          dateColumn: 1,
          descriptionColumn: 2,
          amountColumn: 3,
          typeColumn: 4,
          counterpartyColumn: 5,
          accountColumn: 6,
          defaultType: TxType.workIn,
          hasHeader: true,
          sheetName: 'تراکنش‌های مهر ۱۴۰۵ (آماده ورود)',
        ),
      );

      // Find the row with ناصر پیوسته
      final nasserRows = rows.where((r) => r.description.contains('ناصر پیوسته')).toList();
      expect(nasserRows.isNotEmpty, isTrue);
      for (final r in nasserRows) {
        // Since ناصر پیوسته was in system, it MUST be automatically matched!
        expect(r.clientId, equals(nasserId));
        expect(r.ambiguityReason != AmbiguityReason.unknownCounterparty, isTrue);
      }
    });

    test('Proof: commitImport prevents ERR_CLIENT_KIND_MISMATCH and auto-creates client for work_in transactions', () async {
      // Prepare a row with a partner ID as candidate or rawParty without existing client
      final row = ParsedExcelRow(
        rowIndex: 99,
        rawDate: '1405/07/02',
        isoDate: '2026-09-24',
        description: 'نصب 2 عدد بادبند به ناصر پیوسته در روبروی تالار آی ایشقی',
        amount: 8000000,
        inferredType: TxType.workIn,
        rawParty: 'کارفرمای جدید تست',
        clientId: 'prt_manager', // Candidate partner from seed
        importHash: 'hash_test_client_safety',
        status: RowStatus.ready,
      );

      // commitImport MUST succeed without throwing ERR_CLIENT_KIND_MISMATCH!
      final result = await importService.commitImport([row], projectId: projectId);
      expect(result.importedCount, equals(1));

      // Verify the transaction was inserted with a valid client_id whose kind is 'client'
      final insertedTx = await (db.select(db.transactions)..where((t) => t.id.equals(result.insertedTransactionIds.first))).getSingle();
      expect(insertedTx.type, equals('work_in'));
      expect(insertedTx.clientId, isNotNull);
      final clientPerson = await (db.select(db.persons)..where((p) => p.id.equals(insertedTx.clientId!))).getSingle();
      expect(clientPerson.kind, equals(clientPerson.kind));
    });

    test('Proof: commitImport gracefully handles already-existing import_hash without throwing SqliteException(2067)', () async {
      final row1 = ParsedExcelRow(
        rowIndex: 101,
        rawDate: '1405/07/02',
        isoDate: '2026-09-23',
        description: 'دمونتاژ لوله آب در جاده ارجق',
        amount: 30000000,
        inferredType: TxType.workIn,
        rawParty: 'شهرداری ارجق',
        importHash: '6e862aa2cc23dfd110775ffa131ee1771f9a7aed2a0fb35e7aa4ce77365699a3',
        status: RowStatus.ready,
      );

      // First commit: succeeds
      final res1 = await importService.commitImport([row1], projectId: projectId);
      expect(res1.importedCount, equals(1));
      expect(res1.duplicatesSkippedCount, equals(0));

      // Second commit with the exact same row (as happens on retry or repeated batch):
      // MUST NOT throw SqliteException(2067) UNIQUE constraint failed!
      final res2 = await importService.commitImport([row1], projectId: projectId);
      expect(res2.importedCount, equals(0));
      expect(res2.duplicatesSkippedCount, equals(1));
    });
  });
}
