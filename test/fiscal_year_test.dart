import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/services/balance_service.dart';
import 'package:karkard/services/fiscal_year_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late BalanceService balanceService;
  late FiscalYearService fiscalYearService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    balanceService = BalanceService(db);
    fiscalYearService = FiscalYearService(db: db, balanceService: balanceService);
  });

  tearDown(() => db.close());

  test('FiscalYearService closeAndRollover generates accurate opening entries and balances', () async {
    const p1Id = 'proj-1404';
    final p1 = Project(id: p1Id, name: 'سال مالی ۱۴۰۴', status: 'open', createdAt: '', updatedAt: '');
    await db.into(db.projects).insert(p1);

    // Add cash account
    const accId = 'acc-main';
    final acc = CashAccount(id: accId, name: 'صندوق شرکت', kind: 'project', createdAt: '', updatedAt: '');
    await db.into(db.cashAccounts).insert(acc);

    // Add persons
    const clientId = 'person-client-1';
    final client = Person(id: clientId, name: 'کارفرمای نمونه', kind: 'client', createdAt: '', updatedAt: '', isActive: true);
    await db.into(db.persons).insert(client);

    const workerId = 'person-worker-1';
    final worker = Person(id: workerId, name: 'راننده جرثقیل', kind: 'worker', createdAt: '', updatedAt: '', isActive: true);
    await db.into(db.persons).insert(worker);

    await db.into(db.projectPersons).insert(
          ProjectPersonsCompanion.insert(
            projectId: p1Id,
            personId: workerId,
            settlementMode: const Value('payout_only'),
          ),
        );

    const partnerId = 'person-partner-1';
    final partner = Person(id: partnerId, name: 'شریک اصلی', kind: 'partner', createdAt: '', updatedAt: '', isActive: true);
    await db.into(db.persons).insert(partner);

    await db.into(db.projectPersons).insert(
          ProjectPersonsCompanion.insert(
            projectId: p1Id,
            personId: partnerId,
            settlementMode: const Value('profit_share'),
            shareBp: const Value(10000),
          ),
        );

    // Add transactions to 1404:
    // 1. Work done for client: 10,000,000 Toman
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: const Uuid().v4(),
            projectId: p1Id,
            type: 'work_in',
            amount: 10000000,
            date: '2025-05-01',
            clientId: const Value(clientId),
          ),
        );

    // 2. Client paid 6,000,000 to cash account -> remaining receivable = 4,000,000
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: const Uuid().v4(),
            projectId: p1Id,
            type: 'income',
            amount: 6000000,
            date: '2025-05-02',
            clientId: const Value(clientId),
            cashAccountId: const Value(accId),
          ),
        );

    // 3. Worker salary: 3,000,000 (work_out)
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: const Uuid().v4(),
            projectId: p1Id,
            type: 'work_out',
            amount: 3000000,
            date: '2025-05-03',
            personId: const Value(workerId),
          ),
        );

    // 4. Paid worker 1,000,000 from cash account -> remaining worker payable = 2,000,000
    // Remaining cash balance: 6,000,000 - 1,000,000 = 5,000,000
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: const Uuid().v4(),
            projectId: p1Id,
            type: 'payout',
            amount: 1000000,
            date: '2025-05-04',
            personId: const Value(workerId),
            cashAccountId: const Value(accId),
            purpose: const Value('settle_payable'),
          ),
        );

    // Verify 1404 closing state
    final rep1404 = await balanceService.calculateProjectBalance(p1Id);
    expect(rep1404.totalProjectAccountsBalance, 5000000);
    expect(rep1404.totalReceivables, 4000000);
    expect(rep1404.totalPayables, 2000000);

    // Execute Rollover to 1405
    final p2Id = await fiscalYearService.closeAndRollover(
      sourceProjectId: p1Id,
      targetYearName: 'سال مالی ۱۴۰۵',
      startDateJalali: '1405/01/01',
      lockSource: true,
    );

    // 1. Verify 1404 is now locked
    final updatedP1 = await (db.select(db.projects)..where((p) => p.id.equals(p1Id))).getSingle();
    expect(updatedP1.status, 'locked');

    // 2. Verify 1405 project exists and is open
    final p2 = await (db.select(db.projects)..where((p) => p.id.equals(p2Id))).getSingle();
    expect(p2.name, 'سال مالی ۱۴۰۵');
    expect(p2.status, 'open');

    // 3. Verify opening balance transactions in 1405
    final txs1405 = await (db.select(db.transactions)..where((t) => t.projectId.equals(p2Id))).get();
    expect(txs1405.length, 4); // Cash credit + cash deposit, Client receivable opening, Worker payable opening

    // 4. Verify new year balances match previous year's carried-over balances
    final rep1405 = await balanceService.calculateProjectBalance(p2Id);
    expect(rep1405.totalProjectAccountsBalance, 5000000);
    expect(rep1405.totalReceivables, 4000000);
    expect(rep1405.totalPayables, 2000000);
    expect(rep1405.isGoldenEquationBalanced, true);

    // 5. Check summaries list
    final summaries = await fiscalYearService.getFiscalYearSummaries();
    expect(summaries.length, 2);
    expect(summaries.firstWhere((s) => s.project.id == p1Id).isLocked, true);
    expect(summaries.firstWhere((s) => s.project.id == p2Id).isLocked, false);
  });
}
