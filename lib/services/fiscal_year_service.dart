import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/jalali.dart';
import '../data/database.dart';
import 'balance_service.dart';

class FiscalYearSummary {
  final Project project;
  final int transactionCount;
  final int totalProjectAccountsBalance;
  final int totalReceivables;
  final int totalDue;
  final int netProfitAccrual;
  final bool isGoldenEquationBalanced;

  const FiscalYearSummary({
    required this.project,
    required this.transactionCount,
    required this.totalProjectAccountsBalance,
    required this.totalReceivables,
    required this.totalDue,
    required this.netProfitAccrual,
    required this.isGoldenEquationBalanced,
  });

  bool get isLocked => project.status == 'locked';
}

class FiscalYearService {
  final AppDatabase db;
  final BalanceService balanceService;

  FiscalYearService({
    required this.db,
    required this.balanceService,
  });

  /// Returns summary for all projects/fiscal years.
  Future<List<FiscalYearSummary>> getFiscalYearSummaries() async {
    final projects = await db.select(db.projects).get();
    final List<FiscalYearSummary> summaries = [];

    for (final p in projects) {
      final txCountQuery = db.selectOnly(db.transactions)
        ..addColumns([db.transactions.id.count()])
        ..where(db.transactions.projectId.equals(p.id));
      final count = await txCountQuery.map((row) => row.read(db.transactions.id.count()) ?? 0).getSingle();

      final report = await balanceService.calculateProjectBalance(p.id);

      summaries.add(FiscalYearSummary(
        project: p,
        transactionCount: count,
        totalProjectAccountsBalance: report.totalProjectAccountsBalance,
        totalReceivables: report.totalReceivables,
        totalDue: report.totalDue,
        netProfitAccrual: report.profitAccrual,
        isGoldenEquationBalanced: report.isGoldenEquationBalanced,
      ));
    }

    return summaries;
  }

  /// Closes [sourceProjectId], locks it if [lockSource] is true,
  /// and creates [targetYearName] with carried-over opening balance entries.
  Future<String> closeAndRollover({
    required String sourceProjectId,
    required String targetYearName,
    required String startDateJalali,
    bool lockSource = true,
  }) async {
    final sourceProject = await (db.select(db.projects)..where((p) => p.id.equals(sourceProjectId))).getSingleOrNull();
    if (sourceProject == null) {
      throw StateError('پروژه/سال مالی مبدأ یافت نشد.');
    }

    final report = await balanceService.calculateProjectBalance(sourceProjectId);
    final targetProjectId = const Uuid().v4();
    final startDateIso = parseJalaliStringToIso(startDateJalali);

    await db.transaction(() async {
      // 1. Create target project
      await db.into(db.projects).insert(
            ProjectsCompanion.insert(
              id: targetProjectId,
              name: targetYearName.trim(),
              startDate: Value(startDateIso),
              status: const Value('open'),
            ),
          );

      // 2. Copy project settings
      final sourceSettings = await (db.select(db.projectSettings)
            ..where((s) => s.projectId.equals(sourceProjectId)))
          .getSingleOrNull();

      if (sourceSettings != null) {
        await db.into(db.projectSettings).insert(
              ProjectSettingsCompanion.insert(
                projectId: targetProjectId,
                reportBasis: Value(sourceSettings.reportBasis),
                shareBasis: Value(sourceSettings.shareBasis),
                shareMethod: Value(sourceSettings.shareMethod),
              ),
            );
      } else {
        await db.into(db.projectSettings).insert(
              ProjectSettingsCompanion.insert(
                projectId: targetProjectId,
              ),
            );
      }

      // 3. Copy project partners/persons
      final sourcePersons = await (db.select(db.projectPersons)
            ..where((pp) => pp.projectId.equals(sourceProjectId)))
          .get();

      for (final sp in sourcePersons) {
        await db.into(db.projectPersons).insert(
              ProjectPersonsCompanion.insert(
                projectId: targetProjectId,
                personId: sp.personId,
                settlementMode: Value(sp.settlementMode),
                shareBp: Value(sp.shareBp),
                shareOrder: Value(sp.shareOrder),
              ),
            );
      }

      // 4. Generate Opening Balance Transactions (اسناد افتتاحیه)
      // Ensure an opening balance system client exists
      var openingClient = await (db.select(db.persons)
            ..where((p) => p.name.equals('سند افتتاحیه (انتقال دوره)') & p.kind.equals('client')))
          .getSingleOrNull();

      if (openingClient == null) {
        final opId = const Uuid().v4();
        await db.into(db.persons).insert(
              PersonsCompanion.insert(
                id: opId,
                name: 'سند افتتاحیه (انتقال دوره)',
                kind: 'client',
                note: const Value('طرف‌حساب سیستمی برای انتقال مانده‌های ابتدای دوره مالی'),
              ),
            );
        openingClient = await (db.select(db.persons)..where((p) => p.id.equals(opId))).getSingle();
      }

      // a) Project Cash & Bank Accounts
      final accounts = await db.select(db.cashAccounts).get();
      final accountMap = {for (final a in accounts) a.id: a};

      for (final entry in report.projectAccountBalances.entries) {
        final accId = entry.key;
        final bal = entry.value;
        if (bal == 0) continue;

        final accName = accountMap[accId]?.name ?? 'حساب مالی';
        if (bal > 0) {
          // In double-entry: work_in creates the credit, income deposits it into the cash account.
          // Remaining receivable of openingClient remains 0!
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'work_in',
                  amount: bal,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: موجودی ابتدای دوره $accName (انتقال از ${sourceProject.name})'),
                  clientId: Value(openingClient.id),
                  receiptNotRequired: const Value(true),
                ),
              );
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'income',
                  amount: bal,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: واریز موجودی ابتدای دوره $accName (انتقال از ${sourceProject.name})'),
                  clientId: Value(openingClient.id),
                  cashAccountId: Value(accId),
                  receiptNotRequired: const Value(true),
                ),
              );
        } else {
          // Negative balance (overdraft/expense)
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'expense',
                  amount: -bal,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: تعهد/کسری ابتدای دوره $accName (انتقال از ${sourceProject.name})'),
                  cashAccountId: Value(accId),
                  receiptNotRequired: const Value(true),
                ),
              );
        }
      }

      // b) Client Receivables (مطالبات کارفرمایان)
      for (final entry in report.receivables.entries) {
        final clientId = entry.key;
        final rec = entry.value;
        if (rec == 0) continue;

        if (rec > 0) {
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'work_in',
                  amount: rec,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: مانده طلب از کارفرما (انتقال از ${sourceProject.name})'),
                  clientId: Value(clientId),
                  receiptNotRequired: const Value(true),
                ),
              );
        } else {
          // Prepayment received
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'income',
                  amount: -rec,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: پیش‌دریافت کارفرما (انتقال از ${sourceProject.name})'),
                  clientId: Value(clientId),
                  receiptNotRequired: const Value(true),
                ),
              );
        }
      }

      // c) Person Payables / Wages (بدهی به اشخاص و دستمزدها)
      for (final entry in report.payables.entries) {
        final personId = entry.key;
        final pay = entry.value;
        if (pay == 0) continue;

        if (pay > 0) {
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'work_out',
                  amount: pay,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: مانده بستانکاری/دستمزد (انتقال از ${sourceProject.name})'),
                  personId: Value(personId),
                  receiptNotRequired: const Value(true),
                ),
              );
        } else {
          // Prepayment to person
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'payout',
                  amount: -pay,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: پیش‌پرداخت/مساعده شخص (انتقال از ${sourceProject.name})'),
                  personId: Value(personId),
                  purpose: const Value('settle_payable'),
                  receiptNotRequired: const Value(true),
                ),
              );
        }
      }

      // d) Person Custody (تنخواه)
      for (final entry in report.custodies.entries) {
        final personId = entry.key;
        final cust = entry.value;
        if (cust == 0) continue;

        if (cust > 0) {
          await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  id: const Uuid().v4(),
                  projectId: targetProjectId,
                  type: 'expense',
                  amount: cust,
                  date: startDateIso,
                  description: Value('سند افتتاحیه: تنخواه پرداخت‌نشده شخص (انتقال از ${sourceProject.name})'),
                  personId: Value(personId),
                  receiptNotRequired: const Value(true),
                ),
              );
        }
      }

      // 5. Lock source project if requested
      if (lockSource) {
        await (db.update(db.projects)..where((p) => p.id.equals(sourceProjectId))).write(
          const ProjectsCompanion(status: Value('locked')),
        );
      }
    });

    return targetProjectId;
  }
}
