import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/main.dart';
import 'package:karkard/services/balance_service.dart';
import 'package:karkard/ui/dashboard/charts.dart';
import 'package:karkard/ui/dashboard/dashboard_tab.dart';

void main() {
  testWidgets('DashboardTab displays KPIs, charts, shortcuts, and recent transactions', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const mockReport = ProjectBalanceReport(
      projectId: 'p_dash',
      reportBasis: 'both',
      shareBasis: 'accrual',
      shareMethod: 'fixed_percent',
      win: 15000000,
      wout: 5000000,
      exp: 2000000,
      inc: 10000000,
      ps: 3000000,
      pd: 0,
      profitAccrual: 8000000,
      profitCash: 5000000,
      projectAccountBalances: {'acc1': 5000000},
      personalAccountBalances: {},
      totalProjectAccountsBalance: 5000000,
      receivables: {'c1': 5000000},
      totalReceivables: 5000000,
      payables: {'w1': 2000000},
      totalPayables: 2000000,
      custodies: {},
      totalCustody: 0,
      partnerAllocations: {},
      personBalances: {},
      totalDue: 10000000,
      isGoldenEquationBalanced: true,
    );

    final mockTxs = [
      Transaction(
        id: 'tx1',
        projectId: 'p_dash',
        type: 'work_in',
        amount: 5000000,
        date: '2026-05-10',
        description: 'کارکرد چرثقیل در پروژه نگین',
        receiptNotRequired: false,
        createdAt: '',
        updatedAt: '',
      ),
      Transaction(
        id: 'tx2',
        projectId: 'p_dash',
        type: 'income',
        amount: 3000000,
        date: '2026-05-11',
        description: 'دریافت نقدی از کارفرما',
        receiptNotRequired: false,
        createdAt: '',
        updatedAt: '',
      ),
    ];

    final mockProjects = [
      Project(id: 'p_dash', name: 'دفتر جرثقیل آذرمی', status: 'open', createdAt: '', updatedAt: ''),
    ];

    int navigatedTab = -1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectBalanceProvider.overrideWith((ref) => mockReport),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(mockTxs)),
          projectsStreamProvider.overrideWith((ref) => Stream.value(mockProjects)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DashboardTab(
              activeProjectId: 'p_dash',
              onNewTx: () {},
              onNavigateToTab: (idx) => navigatedTab = idx,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Project Title and Golden Balance Badge
    expect(find.text('دفتر جرثقیل آذرمی'), findsOneWidget);
    expect(find.text('تراز طلایی برقرار است'), findsOneWidget);

    // 2. Verify KPI Cards
    expect(find.text('موجودی نقد و بانک'), findsOneWidget);
    expect(find.text('طلب از کارفرمایان'), findsOneWidget);
    expect(find.text('بدهی‌ها و تعهدات'), findsOneWidget);
    expect(find.text('سود تعهدی دوره'), findsOneWidget);

    // 3. Verify Shortcuts exist and tap switches tab
    expect(find.text('دفتر تراکنش‌ها'), findsOneWidget);
    await tester.tap(find.text('دفتر تراکنش‌ها'));
    expect(navigatedTab, 1);

    expect(find.text('گزارش‌ها و چاپ PDF'), findsOneWidget);
    await tester.tap(find.text('گزارش‌ها و چاپ PDF'));
    expect(navigatedTab, 2);

    // 4. Verify Charts are rendered
    expect(find.byType(SimpleLineChart), findsOneWidget);
    expect(find.byType(SimpleDonutChart), findsOneWidget);

    // 5. Verify Recent Transactions list
    expect(find.text('کارکرد چرثقیل در پروژه نگین'), findsOneWidget);
    expect(find.text('دریافت نقدی از کارفرما'), findsOneWidget);
  });
}
