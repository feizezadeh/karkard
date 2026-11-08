import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/main.dart';
import 'package:karkard/ui/reports/reports_screen.dart';
import 'package:path/path.dart' as p;

class StaticProjectNotifier extends ActiveProjectNotifier {
  final String? _id;
  StaticProjectNotifier(this._id);
  @override
  String? build() => _id;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('karkard_rep_test_');
    dbFile = File(p.join(tempDir.path, 'rep_test.db'));
    db = AppDatabase.forFile(dbFile);
    await db.customSelect('SELECT 1').get();

    // Seed test project & settings
    await db.into(db.projects).insert(ProjectsCompanion.insert(
      id: 'proj_rep_1',
      name: 'پروژه تست گزارش‌ها',
    ));
    await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
      projectId: 'proj_rep_1',
      shareMethod: const Value('fixed_percent'),
      shareBasis: const Value('accrual'),
    ));

    // Seed clients
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'client_1',
      name: 'شرکت راهسازی',
      kind: 'client',
    ));
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'client_2',
      name: 'شهرداری تبریز',
      kind: 'client',
    ));

    // Seed payee/driver
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'driver_1',
      name: 'راننده جرثقیل',
      kind: 'driver',
    ));
    await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
      projectId: 'proj_rep_1',
      personId: 'driver_1',
      settlementMode: const Value('payout_only'),
    ));

    // Seed partner
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'partner_1',
      name: 'امیر آذرمی',
      kind: 'partner',
    ));
    await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
      projectId: 'proj_rep_1',
      personId: 'partner_1',
      settlementMode: const Value('profit_share'),
      shareBp: const Value(10000),
      shareOrder: const Value(1),
    ));

    // Seed cash account
    await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
      id: 'acc_mellat',
      name: 'حساب بانکی',
      kind: 'project',
    ));

    // Add a work_in transaction for client 1
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx_1',
      projectId: 'proj_rep_1',
      type: 'work_in',
      amount: 10000000, // 10M
      date: '2024-09-22',
      clientId: const Value('client_1'),
      description: const Value('کارکرد چرثقیل کارفرما ۱'),
    ));

    // Add a work_in transaction for client 2
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx_1_2',
      projectId: 'proj_rep_1',
      type: 'work_in',
      amount: 5000000, // 5M
      date: '2024-09-25',
      clientId: const Value('client_2'),
      description: const Value('کارکرد پروژه شهرداری'),
    ));

    // Add a work_out transaction for driver
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx_2',
      projectId: 'proj_rep_1',
      type: 'work_out',
      amount: 2000000, // 2M
      date: '2024-09-23',
      personId: const Value('driver_1'),
      description: const Value('دستمزد راننده'),
    ));
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget host(Widget w, String activeId) {
    return ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        activeProjectIdProvider.overrideWith(() => StaticProjectNotifier(activeId)),
      ],
      child: MaterialApp(
        locale: const Locale('fa', 'IR'),
        home: Scaffold(body: w),
      ),
    );
  }

  testWidgets('ReportsScreen loads KPIs, tabs, and balances correctly', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(host(const ReportsScreen(), 'proj_rep_1'));
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify Golden Balance check badge is displayed
      expect(find.text('معادله تراز طلایی کاملاً برقرار است'), findsOneWidget);

      // Check tabs
      expect(find.text('کارفرمایان (طلب‌ها)'), findsOneWidget);
      expect(find.text('پرسنل و رانندگان'), findsOneWidget);
      expect(find.text('شرکا و سود'), findsOneWidget);

      // Verify clients are listed in the first tab and have PDF buttons
      expect(find.text('شرکت راهسازی'), findsOneWidget);
      expect(find.text('شهرداری تبریز'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);

      // Switch to creditors/payees tab
      await tester.tap(find.text('پرسنل و رانندگان'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('راننده جرثقیل'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);

      // Switch to partners tab
      await tester.tap(find.text('شرکا و سود'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('امیر آذرمی'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);

      // Clean up widget tree to cancel subscriptions
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('ReportsScreen date preset filters and search filtering work properly', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(host(const ReportsScreen(), 'proj_rep_1'));
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify date filter bar chips exist
      expect(find.text('همه دوره'), findsOneWidget);
      expect(find.text('ماه جاری'), findsOneWidget);
      expect(find.text('۳ ماه اخیر'), findsOneWidget);
      expect(find.text('سال مالی'), findsOneWidget);

      // Tap on 'ماه جاری' preset
      await tester.tap(find.text('ماه جاری'));
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Check active filter indicator banner appears
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);

      // Reset to all time
      await tester.tap(find.text('همه دوره'));
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Test Search Filter: both clients are visible initially
      expect(find.text('شرکت راهسازی'), findsOneWidget);
      expect(find.text('شهرداری تبریز'), findsOneWidget);

      // Enter search query 'شهرداری'
      await tester.enterText(find.byType(TextField).first, 'شهرداری');
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Only 'شهرداری تبریز' should remain visible
      expect(find.text('شهرداری تبریز'), findsOneWidget);
      expect(find.text('شرکت راهسازی'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('شرکت راهسازی'), findsOneWidget);
      expect(find.text('شهرداری تبریز'), findsOneWidget);

      // Clean up widget tree
      await tester.pumpWidget(const SizedBox());
    });
  });
}
