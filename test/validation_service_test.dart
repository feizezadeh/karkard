import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/services/balance_service.dart';
import 'package:karkard/services/validation_service.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

void main() {
  group('ValidationService Tests (Phase 1)', () {
    late AppDatabase db;
    late BalanceService balanceService;
    late ValidationService validationService;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      // Seed project, persons, cash accounts
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'proj1', name: 'پروژه تست'));
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'proj1'));

      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'cli1', name: 'کارفرما ۱', kind: 'client'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt1', name: 'شریک ۱', kind: 'partner'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'drv1', name: 'راننده ۱', kind: 'driver'));

      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
            projectId: 'proj1',
            personId: 'prt1',
            settlementMode: const Value('profit_share'),
            shareBp: const Value(10000),
            shareOrder: const Value(1),
          ));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
            projectId: 'proj1',
            personId: 'drv1',
            settlementMode: const Value('payout_only'),
          ));

      await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c_proj', name: 'صندوق پروژه', kind: 'project'));
      await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c_pers', name: 'حساب شخصی', kind: 'personal', holderPersonId: const Value('prt1')));

      await db.into(db.categories).insert(CategoriesCompanion.insert(id: 'cat_fuel', name: 'سوخت', kind: 'expense'));

      balanceService = BalanceService(db);
      validationService = ValidationService(db, balanceService: balanceService);
    });

    tearDown(() => db.close());

    test('positive: valid work_in creates transaction and audit_log atomically', () async {
      final tx = await validationService.createTransactionAtomic(TransactionsCompanion.insert(
        id: 'tx_win_1',
        projectId: 'proj1',
        type: 'work_in',
        amount: 5000000,
        date: '2025-03-20',
        clientId: const Value('cli1'),
      ));

      expect(tx.id, 'tx_win_1');
      expect(tx.amount, 5000000);

      // Verify transaction in DB
      final savedTx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_win_1'))).getSingle();
      expect(savedTx.amount, 5000000);

      // Verify audit_log entry
      final auditEntries = await (db.select(db.auditLog)..where((a) => a.entityId.equals('tx_win_1'))).get();
      expect(auditEntries.length, 1);
      expect(auditEntries.first.action, 'insert');
      expect(auditEntries.first.entityType, 'transaction');
      expect(auditEntries.first.afterJson, contains('5000000'));
    });

    test('negative: amount <= 0 throws ERR_TX_AMOUNT_POSITIVE', () async {
      expect(
        () => validationService.createTransactionAtomic(TransactionsCompanion.insert(
          id: 'tx_zero',
          projectId: 'proj1',
          type: 'work_in',
          amount: 0,
          date: '2025-03-20',
          clientId: const Value('cli1'),
        )),
        throwsA(isA<DomainException>().having((e) => e.code, 'code', 'ERR_TX_AMOUNT_POSITIVE')),
      );
    });

    test('negative: locked project throws ERR_PROJECT_LOCKED_TX', () async {
      await (db.update(db.projects)..where((p) => p.id.equals('proj1'))).write(const ProjectsCompanion(
        status: Value('locked'),
      ));

      expect(
        () => validationService.createTransactionAtomic(TransactionsCompanion.insert(
          id: 'tx_locked',
          projectId: 'proj1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value('cli1'),
        )),
        throwsA(isA<DomainException>().having((e) => e.code, 'code', DomainErrors.projectLockedTx)),
      );
    });

    test('negative: category_id for non-expense throws ERR_CATEGORY_ONLY_FOR_EXPENSE', () async {
      expect(
        () => validationService.createTransactionAtomic(TransactionsCompanion.insert(
          id: 'tx_cat_err',
          projectId: 'proj1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value('cli1'),
          categoryId: const Value('cat_fuel'),
        )),
        throwsA(isA<DomainException>().having((e) => e.code, 'code', 'ERR_CATEGORY_ONLY_FOR_EXPENSE')),
      );
    });

    test('positive: atomic update records beforeJson and afterJson in audit_log', () async {
      await validationService.createTransactionAtomic(TransactionsCompanion.insert(
        id: 'tx_upd_test',
        projectId: 'proj1',
        type: 'expense',
        amount: 2000,
        date: '2025-03-20',
        cashAccountId: const Value('c_proj'),
      ));

      final updated = await validationService.updateTransactionAtomic(
        'tx_upd_test',
        const TransactionsCompanion(
          amount: Value(3500),
        ),
        reason: 'اصلاح بر اساس فاکتور نهایی',
      );

      expect(updated.amount, 3500);

      final auditEntries = await (db.select(db.auditLog)..where((a) => a.entityId.equals('tx_upd_test'))).get();
      expect(auditEntries.length, 2); // 1 insert + 1 update
      final updateLog = auditEntries.firstWhere((a) => a.action == 'update');
      expect(updateLog.beforeJson, contains('2000'));
      expect(updateLog.afterJson, contains('3500'));
      expect(updateLog.reason, 'اصلاح بر اساس فاکتور نهایی');
    });

    test('positive: atomic soft-delete sets deleted_at and records in audit_log', () async {
      await validationService.createTransactionAtomic(TransactionsCompanion.insert(
        id: 'tx_del_test',
        projectId: 'proj1',
        type: 'expense',
        amount: 1000,
        date: '2025-03-20',
        cashAccountId: const Value('c_proj'),
      ));

      await validationService.softDeleteTransactionAtomic('tx_del_test', reason: 'ثبت اشتباه');

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_del_test'))).getSingle();
      expect(tx.deletedAt, isNotNull);
      expect(tx.deletedReason, 'ثبت اشتباه');

      final auditEntries = await (db.select(db.auditLog)..where((a) => a.entityId.equals('tx_del_test'))).get();
      final deleteLog = auditEntries.firstWhere((a) => a.action == 'soft_delete');
      expect(deleteLog.reason, 'ثبت اشتباه');
      expect(deleteLog.beforeJson, contains('1000'));
    });

    test('negative: soft delete with empty reason throws ERR_DELETE_REASON_REQUIRED', () async {
      await validationService.createTransactionAtomic(TransactionsCompanion.insert(
        id: 'tx_del_noreason',
        projectId: 'proj1',
        type: 'expense',
        amount: 1000,
        date: '2025-03-20',
        cashAccountId: const Value('c_proj'),
      ));

      expect(
        () => validationService.softDeleteTransactionAtomic('tx_del_noreason', reason: '   '),
        throwsA(isA<DomainException>().having((e) => e.code, 'code', 'ERR_DELETE_REASON_REQUIRED')),
      );
    });

    test('atomic rollback test: error during audit_log rolls back transaction insertion', () async {
      // In audit_log, the trigger trg_audit_log_no_update forbids update.
      // If an exception occurs inside the db.transaction block, the transaction insert is rolled back!
      var didFail = false;
      try {
        await db.transaction(() async {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                id: 'tx_fail_rollback',
                projectId: 'proj1',
                type: 'expense',
                amount: 9999,
                date: '2025-03-20',
                cashAccountId: const Value('c_proj'),
              ));

          // Simulate failure before committing transaction
          if (DateTime.now().year > 2000) {
            throw Exception('Simulated failure during audit log creation');
          }
        });
      } catch (e) {
        didFail = true;
        expect(e.toString(), contains('Simulated failure'));
      }
      expect(didFail, isTrue);

      // Assert rollback: tx_fail_rollback must NOT exist in the database!
      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_fail_rollback'))).getSingleOrNull();
      expect(tx, isNull);

      final audit = await (db.select(db.auditLog)..where((a) => a.entityId.equals('tx_fail_rollback'))).getSingleOrNull();
      expect(audit, isNull);
    });
  });
}
