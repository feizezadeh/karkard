import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/services/balance_service.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';

void main() {
  group('Golden Tests (Section 6: G1 to G5)', () {
    // -------------------------------------------------------------------------
    // G3: Section 5 Numerical Verification (Cases A, B, C)
    // -------------------------------------------------------------------------
    group('G3 — Section 5 Numerical Verification', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('select 1').get();

        // 1. Project
        await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'proj_sec5', name: 'پروژه نمونه بخش ۵'));

        // 2. Persons: Amir (partner), Aref (partner), Driver (driver), Gozel (client), Hadi (client)
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'amir', name: 'امیر', kind: 'partner'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'aref', name: 'عارف', kind: 'partner'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'driver', name: 'راننده', kind: 'driver'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'gozel', name: 'گوزل', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'hadi', name: 'هادی', kind: 'client'));

        // 3. Cash accounts: C1 (project), A1 (personal: Amir), B1 (personal: Aref)
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c1', name: 'صندوق پروژه C1', kind: 'project'));
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
              id: 'a1',
              name: 'جیب امیر A1',
              kind: 'personal',
              holderPersonId: const Value('amir'),
            ));
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
              id: 'b1',
              name: 'حساب عارف B1',
              kind: 'personal',
              holderPersonId: const Value('aref'),
            ));

        // 4. Project Persons: Amir (5000 bp, order 1), Aref (5000 bp, order 2), Driver (payout_only)
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'proj_sec5',
              personId: 'amir',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(5000),
              shareOrder: const Value(1),
            ));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'proj_sec5',
              personId: 'aref',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(5000),
              shareOrder: const Value(2),
            ));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'proj_sec5',
              personId: 'driver',
              settlementMode: const Value('payout_only'),
            ));
      });

      tearDown(() => db.close());

      Future<void> seedSection5Transactions() async {
        // 5. 14 Transactions from Section 5 Table
        // 1. work_in: Gozel, performed_by Amir, 60m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx1',
              projectId: 'proj_sec5',
              type: 'work_in',
              amount: 60000000,
              date: '2025-03-20',
              clientId: const Value('gozel'),
              performedBy: const Value('amir'),
            ));
        // 2. work_in: Gozel, performed_by Aref, 20m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx2',
              projectId: 'proj_sec5',
              type: 'work_in',
              amount: 20000000,
              date: '2025-03-20',
              clientId: const Value('gozel'),
              performedBy: const Value('aref'),
            ));
        // 3. work_in: Hadi, shared, 10m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx3',
              projectId: 'proj_sec5',
              type: 'work_in',
              amount: 10000000,
              date: '2025-03-20',
              clientId: const Value('hadi'),
            ));
        // 4. work_out: Driver, attributed_to Amir, 6m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx4',
              projectId: 'proj_sec5',
              type: 'work_out',
              amount: 6000000,
              date: '2025-03-20',
              personId: const Value('driver'),
              attributedTo: const Value('amir'),
            ));
        // 5. expense: Lunch from C1, shared, 2m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx5',
              projectId: 'proj_sec5',
              type: 'expense',
              amount: 2000000,
              date: '2025-03-20',
              cashAccountId: const Value('c1'),
            ));
        // 6. expense: Fuel from A1, attributed_to Amir, 3m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx6',
              projectId: 'proj_sec5',
              type: 'expense',
              amount: 3000000,
              date: '2025-03-20',
              cashAccountId: const Value('a1'),
              attributedTo: const Value('amir'),
            ));
        // 7. expense: from B1, attributed_to Aref, 1m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx7',
              projectId: 'proj_sec5',
              type: 'expense',
              amount: 1000000,
              date: '2025-03-20',
              cashAccountId: const Value('b1'),
              attributedTo: const Value('aref'),
            ));
        // 8. income: Gozel -> C1, 30m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx8',
              projectId: 'proj_sec5',
              type: 'income',
              amount: 30000000,
              date: '2025-03-20',
              clientId: const Value('gozel'),
              cashAccountId: const Value('c1'),
            ));
        // 9. income: Gozel -> B1, 20m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx9',
              projectId: 'proj_sec5',
              type: 'income',
              amount: 20000000,
              date: '2025-03-20',
              clientId: const Value('gozel'),
              cashAccountId: const Value('b1'),
            ));
        // 10. income: Hadi -> C1, 10m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx10',
              projectId: 'proj_sec5',
              type: 'income',
              amount: 10000000,
              date: '2025-03-20',
              clientId: const Value('hadi'),
              cashAccountId: const Value('c1'),
            ));
        // 11. payout: Driver from C1, settle_payable, 4m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx11',
              projectId: 'proj_sec5',
              type: 'payout',
              amount: 4000000,
              date: '2025-03-20',
              personId: const Value('driver'),
              cashAccountId: const Value('c1'),
              purpose: const Value('settle_payable'),
            ));
        // 12. transfer: A1 -> C1 (Amir reimbursement), 3m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx12',
              projectId: 'proj_sec5',
              type: 'transfer',
              amount: 3000000,
              date: '2025-03-20',
              fromAccountId: const Value('c1'),
              toAccountId: const Value('a1'),
            ));
        // 13. payout: Aref from B1, distribution, 10m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx13',
              projectId: 'proj_sec5',
              type: 'payout',
              amount: 10000000,
              date: '2025-03-20',
              personId: const Value('aref'),
              cashAccountId: const Value('b1'),
              purpose: const Value('distribution'),
            ));
        // 14. payout: Amir from C1, distribution, 5m
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx14',
              projectId: 'proj_sec5',
              type: 'payout',
              amount: 5000000,
              date: '2025-03-20',
              personId: const Value('amir'),
              cashAccountId: const Value('c1'),
              purpose: const Value('distribution'),
            ));
      }

      test('Case A: by_work (accrual) matches 50 / 13 / 2 / 56', () async {
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'proj_sec5',
              reportBasis: const Value('accrual'),
              shareBasis: const Value('accrual'),
              shareMethod: const Value('by_work'),
            ));
        await seedSection5Transactions();

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('proj_sec5');

        // Totals
        expect(report.win, 90000000);
        expect(report.wout, 6000000);
        expect(report.exp, 6000000);
        expect(report.inc, 60000000);
        expect(report.profitAccrual, 78000000);

        // Accounts
        expect(report.projectAccountBalances['c1'], 26000000);
        expect(report.personalAccountBalances['a1'], 0);
        expect(report.personalAccountBalances['b1'], 9000000);
        expect(report.totalProjectAccountsBalance, 26000000);

        // Receivables
        expect(report.receivables['gozel'], 30000000);
        expect(report.receivables['hadi'], 0);
        expect(report.totalReceivables, 30000000);

        // Partner Profit
        final amirAlloc = report.partnerAllocations['amir']!;
        expect(amirAlloc.directProfit, 51000000); // 60m - 6m - 3m
        expect(amirAlloc.poolShare, 4000000);
        expect(amirAlloc.totalProfit, 55000000);
        expect(amirAlloc.claimableShare, 50000000); // 55m - 5m

        final arefAlloc = report.partnerAllocations['aref']!;
        expect(arefAlloc.directProfit, 19000000); // 20m - 1m
        expect(arefAlloc.poolShare, 4000000);
        expect(arefAlloc.totalProfit, 23000000);
        expect(arefAlloc.claimableShare, 13000000); // 23m - 10m

        // Payables
        expect(report.payables['driver'], 2000000); // 6m - 4m

        // Custodies
        expect(report.custodies['amir'], 0);
        expect(report.custodies['aref'], -9000000); // B1 holds 9m of project money

        // Person Balances & Due
        final balDriver = report.personBalances['driver']!;
        expect(balDriver.due, 2000000);

        final balAmir = report.personBalances['amir']!;
        expect(balAmir.share, 50000000);
        expect(balAmir.custody, 0);
        expect(balAmir.due, 50000000);

        final balAref = report.personBalances['aref']!;
        expect(balAref.share, 13000000);
        expect(balAref.custody, -9000000);
        expect(balAref.due, 4000000); // 13m - 9m = 4m

        // Total Due
        expect(report.totalDue, 56000000);

        // Golden Balance: bal(project) + Rec == Due
        // 26m + 30m = 56m == 56m
        expect(report.isGoldenEquationBalanced, isTrue);
        expect(report.totalProjectAccountsBalance + report.totalReceivables, report.totalDue);
      });

      test('Case B: fixed_percent (accrual) matches 34 / 29 / 2 / 56', () async {
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'proj_sec5',
              reportBasis: const Value('accrual'),
              shareBasis: const Value('accrual'),
              shareMethod: const Value('fixed_percent'),
            ));
        await seedSection5Transactions();

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('proj_sec5');

        // Totals
        expect(report.profitAccrual, 78000000);

        // Partner Profit: 78m split 5000/5000 bp -> 39m each
        final amirAlloc = report.partnerAllocations['amir']!;
        expect(amirAlloc.totalProfit, 39000000);
        expect(amirAlloc.claimableShare, 34000000); // 39m - 5m

        final arefAlloc = report.partnerAllocations['aref']!;
        expect(arefAlloc.totalProfit, 39000000);
        expect(arefAlloc.claimableShare, 29000000); // 39m - 10m

        // Due
        expect(report.personBalances['driver']!.due, 2000000);
        expect(report.personBalances['amir']!.due, 34000000);
        expect(report.personBalances['aref']!.due, 20000000); // 29m - 9m = 20m

        // Total Due
        expect(report.totalDue, 56000000);

        // Golden Balance: 26m + 30m == 56m
        expect(report.isGoldenEquationBalanced, isTrue);
        expect(report.totalProjectAccountsBalance + report.totalReceivables, report.totalDue);
      });

      test('Case C: cash basis (fixed_percent, share_basis=cash) matches 50m and 25m', () async {
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'proj_sec5',
              reportBasis: const Value('cash'),
              shareBasis: const Value('cash'),
              shareMethod: const Value('fixed_percent'),
            ));
        await seedSection5Transactions();

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('proj_sec5');

        // Profit_cash = Inc (60m) - Exp (6m) - Ps (4m) = 50m
        expect(report.profitCash, 50000000);

        // Temporary profit share per partner: 25m each
        final amirAlloc = report.partnerAllocations['amir']!;
        expect(amirAlloc.totalProfit, 25000000);

        final arefAlloc = report.partnerAllocations['aref']!;
        expect(arefAlloc.totalProfit, 25000000);
      });
    });

    // -------------------------------------------------------------------------
    // G4: Largest Remainder Distribution Method (Hamilton-Hare with share_order tie-break)
    // -------------------------------------------------------------------------
    group('G4 — Remainder Allocation (Hamilton-Hare)', () {
      test('S = 7 with [3333, 3333, 3334] bp allocates exactly 7 with integer precision', () {
        final partners = [
          const PartnerShareItem(personId: 'p1', shareBp: 3333, shareOrder: 1),
          const PartnerShareItem(personId: 'p2', shareBp: 3333, shareOrder: 2),
          const PartnerShareItem(personId: 'p3', shareBp: 3334, shareOrder: 3),
        ];

        final result = BalanceService.allocateRemainder(7, partners);

        // 3333 * 7 = 23331 -> floor 2, rem 3331
        // 3334 * 7 = 23338 -> floor 2, rem 3338 (highest remainder gets leftover 1)
        expect(result['p1'], 2);
        expect(result['p2'], 2);
        expect(result['p3'], 3);
        expect(result.values.fold(0, (a, b) => a + b), 7);
      });

      test('Tie-breaking by share_order when remainders are identical', () {
        final partners = [
          const PartnerShareItem(personId: 'p1', shareBp: 5000, shareOrder: 1),
          const PartnerShareItem(personId: 'p2', shareBp: 5000, shareOrder: 2),
        ];

        // S = 1: product = 5000, rem = 5000 for both. Leftover = 1.
        // p1 has shareOrder 1 < 2 -> p1 gets +1, p2 gets 0.
        final result = BalanceService.allocateRemainder(1, partners);
        expect(result['p1'], 1);
        expect(result['p2'], 0);
        expect(result.values.fold(0, (a, b) => a + b), 1);
      });

      test('Negative S = -7 allocates exactly -7 with integer precision', () {
        final partners = [
          const PartnerShareItem(personId: 'p1', shareBp: 3333, shareOrder: 1),
          const PartnerShareItem(personId: 'p2', shareBp: 3333, shareOrder: 2),
          const PartnerShareItem(personId: 'p3', shareBp: 3334, shareOrder: 3),
        ];

        final result = BalanceService.allocateRemainder(-7, partners);

        // Sum must be exactly -7
        final total = result.values.fold(0, (a, b) => a + b);
        expect(total, -7);
      });

      test('Zero S = 0 allocates zero to all partners', () {
        final partners = [
          const PartnerShareItem(personId: 'p1', shareBp: 6000, shareOrder: 1),
          const PartnerShareItem(personId: 'p2', shareBp: 4000, shareOrder: 2),
        ];

        final result = BalanceService.allocateRemainder(0, partners);
        expect(result['p1'], 0);
        expect(result['p2'], 0);
        expect(result.values.fold(0, (a, b) => a + b), 0);
      });
    });

    // -------------------------------------------------------------------------
    // G5: Total Cash Balance across all accounts
    // -------------------------------------------------------------------------
    group('G5 — Total Cash Balance', () {
      test('Section 5 total cash: 26 + 0 + 9 = 35 == 60 - 6 - 4 - 15', () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('select 1').get();

        await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p_g5', name: 'P'));
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'p_g5'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'c', name: 'Client', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p', name: 'Partner', kind: 'partner'));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'p_g5',
              personId: 'p',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(10000),
            ));

        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c1', name: 'C1', kind: 'project'));
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'a1', name: 'A1', kind: 'personal', holderPersonId: const Value('p')));

        // Inc = 60, Exp = 6, Ps = 4, Pd = 15
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_inc',
              projectId: 'p_g5',
              type: 'income',
              amount: 60,
              date: '2025-01-01',
              clientId: const Value('c'),
              cashAccountId: const Value('c1'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_exp',
              projectId: 'p_g5',
              type: 'expense',
              amount: 6,
              date: '2025-01-01',
              cashAccountId: const Value('c1'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_ps',
              projectId: 'p_g5',
              type: 'payout',
              amount: 4,
              date: '2025-01-01',
              personId: const Value('p'),
              cashAccountId: const Value('c1'),
              purpose: const Value('settle_payable'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_pd',
              projectId: 'p_g5',
              type: 'payout',
              amount: 15,
              date: '2025-01-01',
              personId: const Value('p'),
              cashAccountId: const Value('c1'),
              purpose: const Value('distribution'),
            ));

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('p_g5');

        final totalAllAccounts = report.projectAccountBalances.values.fold(0, (a, b) => a + b) +
            report.personalAccountBalances.values.fold(0, (a, b) => a + b);

        final expectedTotal = report.inc - report.exp - report.ps - report.pd;
        expect(totalAllAccounts, expectedTotal);
        expect(totalAllAccounts, 35);

        await db.close();
      });
    });

    // -------------------------------------------------------------------------
    // G2: Sum of Partner Profits equals Total Profit (Accrual)
    // -------------------------------------------------------------------------
    group('G2 — Sum of Partner Profits == Total Profit', () {
      test('holds for by_work mode', () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('select 1').get();

        await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p_g2_bw', name: 'P'));
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'p_g2_bw',
              shareMethod: const Value('by_work'),
            ));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'c', name: 'Client', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p1', name: 'P1', kind: 'partner'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p2', name: 'P2', kind: 'partner'));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'p_g2_bw',
              personId: 'p1',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(7000),
              shareOrder: const Value(1),
            ));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'p_g2_bw',
              personId: 'p2',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(3000),
              shareOrder: const Value(2),
            ));
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'ca', name: 'CA', kind: 'project'));

        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_w1',
              projectId: 'p_g2_bw',
              type: 'work_in',
              amount: 5000,
              date: '2025-01-01',
              clientId: const Value('c'),
              performedBy: const Value('p1'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_w2',
              projectId: 'p_g2_bw',
              type: 'work_in',
              amount: 3000,
              date: '2025-01-01',
              clientId: const Value('c'),
              performedBy: const Value('p2'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_ws',
              projectId: 'p_g2_bw',
              type: 'work_in',
              amount: 2000,
              date: '2025-01-01',
              clientId: const Value('c'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_e',
              projectId: 'p_g2_bw',
              type: 'expense',
              amount: 1500,
              date: '2025-01-01',
              cashAccountId: const Value('ca'),
            ));

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('p_g2_bw');

        final sumProfits = report.partnerAllocations.values.fold(0, (a, b) => a + b.totalProfit);
        expect(sumProfits, report.profitAccrual);

        await db.close();
      });

      test('holds for fixed_percent mode', () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('select 1').get();

        await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p_g2_fp', name: 'P'));
        await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'p_g2_fp',
              shareMethod: const Value('fixed_percent'),
            ));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'c', name: 'Client', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p1', name: 'P1', kind: 'partner'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p2', name: 'P2', kind: 'partner'));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'p_g2_fp',
              personId: 'p1',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(6000),
              shareOrder: const Value(1),
            ));
        await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
              projectId: 'p_g2_fp',
              personId: 'p2',
              settlementMode: const Value('profit_share'),
              shareBp: const Value(4000),
              shareOrder: const Value(2),
            ));
        await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'ca', name: 'CA', kind: 'project'));

        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_w',
              projectId: 'p_g2_fp',
              type: 'work_in',
              amount: 10000,
              date: '2025-01-01',
              clientId: const Value('c'),
            ));
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tx_e',
              projectId: 'p_g2_fp',
              type: 'expense',
              amount: 3333,
              date: '2025-01-01',
              cashAccountId: const Value('ca'),
            ));

        final service = BalanceService(db);
        final report = await service.calculateProjectBalance('p_g2_fp');

        final sumProfits = report.partnerAllocations.values.fold(0, (a, b) => a + b.totalProfit);
        expect(sumProfits, report.profitAccrual);

        await db.close();
      });
    });

    // -------------------------------------------------------------------------
    // G1: Golden Equation Property-Based Test (>= 1000 randomized scenarios)
    // -------------------------------------------------------------------------
    group('G1 — Golden Accounting Equation Property Test', () {
      test('holds across 1000 randomized project configurations with seed 42', () async {
        const seed = 42;
        final rng = Random(seed);

        final db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('select 1').get();
        final service = BalanceService(db);

        // Pre-create shared clients, workers, accounts across iterations to keep DB fast
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'g_cli1', name: 'Client 1', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'g_cli2', name: 'Client 2', kind: 'client'));
        await db.into(db.persons).insert(PersonsCompanion.insert(id: 'g_worker', name: 'Worker', kind: 'other'));

        for (var i = 1; i <= 1000; i++) {
          final pid = 'proj_$i';
          final shareMethod = rng.nextBool() ? 'by_work' : 'fixed_percent';

          // Project & settings
          await db.into(db.projects).insert(ProjectsCompanion.insert(id: pid, name: 'Project $i'));
          await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
                projectId: pid,
                shareMethod: Value(shareMethod),
                shareBasis: const Value('accrual'),
                reportBasis: const Value('accrual'),
              ));

          // Partners: 2 or 3 partners with shareBp summing to 10000
          final numPartners = rng.nextBool() ? 2 : 3;
          final pids = <String>[];
          final shareBps = <int>[];

          if (numPartners == 2) {
            final bp1 = 1000 + rng.nextInt(8000);
            shareBps.addAll([bp1, 10000 - bp1]);
          } else {
            final bp1 = 1000 + rng.nextInt(4000);
            final bp2 = 1000 + rng.nextInt(4000);
            shareBps.addAll([bp1, bp2, 10000 - bp1 - bp2]);
          }

          for (var pIdx = 0; pIdx < numPartners; pIdx++) {
            final partnerId = 'p_${i}_$pIdx';
            pids.add(partnerId);
            await db.into(db.persons).insert(PersonsCompanion.insert(
                  id: partnerId,
                  name: 'Partner $pIdx',
                  kind: 'partner',
                ));
            await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
                  projectId: pid,
                  personId: partnerId,
                  settlementMode: const Value('profit_share'),
                  shareBp: Value(shareBps[pIdx]),
                  shareOrder: Value(pIdx + 1),
                ));
          }

          // Worker in project
          await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
                projectId: pid,
                personId: 'g_worker',
                settlementMode: const Value('payout_only'),
              ));

          // Cash accounts for project
          final cProj = 'c_proj_$i';
          final cPers = 'c_pers_$i';
          await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: cProj, name: 'C Proj $i', kind: 'project'));
          await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
                id: cPers,
                name: 'C Pers $i',
                kind: 'personal',
                holderPersonId: Value(pids[0]),
              ));

          // Generate 6 to 12 random transactions
          final numTx = 6 + rng.nextInt(7);
          for (var t = 0; t < numTx; t++) {
            final txId = 'tx_${i}_$t';
            final txTypeChoice = rng.nextInt(6);

            switch (txTypeChoice) {
              case 0: // work_in
                final perf = rng.nextBool() ? pids[rng.nextInt(pids.length)] : null;
                final cli = rng.nextBool() ? 'g_cli1' : 'g_cli2';
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'work_in',
                      amount: 10000 + rng.nextInt(500000),
                      date: '2025-01-01',
                      clientId: Value(cli),
                      performedBy: Value(perf),
                    ));
                break;

              case 1: // work_out
                final attr = rng.nextBool() ? pids[rng.nextInt(pids.length)] : null;
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'work_out',
                      amount: 5000 + rng.nextInt(100000),
                      date: '2025-01-01',
                      personId: const Value('g_worker'),
                      attributedTo: Value(attr),
                    ));
                break;

              case 2: // income
                final acc = rng.nextBool() ? cProj : cPers;
                final cli = rng.nextBool() ? 'g_cli1' : 'g_cli2';
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'income',
                      amount: 5000 + rng.nextInt(200000),
                      date: '2025-01-01',
                      clientId: Value(cli),
                      cashAccountId: Value(acc),
                    ));
                break;

              case 3: // expense
                final acc = rng.nextBool() ? cProj : cPers;
                final attr = rng.nextBool() ? pids[rng.nextInt(pids.length)] : null;
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'expense',
                      amount: 1000 + rng.nextInt(50000),
                      date: '2025-01-01',
                      cashAccountId: Value(acc),
                      attributedTo: Value(attr),
                    ));
                break;

              case 4: // transfer
                final fromAcc = rng.nextBool() ? cProj : cPers;
                final toAcc = (fromAcc == cProj) ? cPers : cProj;
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'transfer',
                      amount: 1000 + rng.nextInt(20000),
                      date: '2025-01-01',
                      fromAccountId: Value(fromAcc),
                      toAccountId: Value(toAcc),
                    ));
                break;

              case 5: // payout
                final isDist = rng.nextBool();
                final acc = rng.nextBool() ? cProj : cPers;
                final person = isDist ? pids[rng.nextInt(pids.length)] : 'g_worker';
                final purpose = isDist ? 'distribution' : 'settle_payable';
                await db.into(db.transactions).insert(TransactionsCompanion.insert(
                      id: txId,
                      projectId: pid,
                      type: 'payout',
                      amount: 1000 + rng.nextInt(50000),
                      date: '2025-01-01',
                      personId: Value(person),
                      cashAccountId: Value(acc),
                      purpose: Value(purpose),
                    ));
                break;
            }
          }

          // Evaluate golden equation
          final report = await service.calculateProjectBalance(pid);

          expect(
            report.isGoldenEquationBalanced,
            isTrue,
            reason: 'Failed golden equation at scenario #$i (method: $shareMethod)',
          );

          expect(
            report.totalProjectAccountsBalance + report.totalReceivables,
            report.totalDue,
            reason: 'Mismatch at scenario #$i: bal(${report.totalProjectAccountsBalance}) + Rec(${report.totalReceivables}) != Due(${report.totalDue})',
          );

          // Also verify G2 in each scenario
          final sumProfits = report.partnerAllocations.values.fold(0, (a, b) => a + b.totalProfit);
          expect(sumProfits, report.profitAccrual, reason: 'G2 failed at scenario #$i');
        }

        await db.close();
      });
    });
  });
}
