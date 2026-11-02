import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/core/error_mapper.dart';
import 'package:karkard/data/database.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<void> expectDbThrowsDomainCode(Future<void> Function() action, String expectedCode) async {
  try {
    await action();
    fail('Expected DB to throw, but succeeded');
  } catch (e) {
    final domain = mapSqliteException(e);
    expect(domain.code, expectedCode);
  }
}

void main() {
  group('Section 6 & 7 Negative Tests (DB-Enforced via mapSqliteException)', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p1', name: 'پروژه'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'cli', name: 'کارفرما', kind: 'client'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt', name: 'شریک', kind: 'partner'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'drv', name: 'راننده', kind: 'driver'));
      await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c1', name: 'صندوق', kind: 'project'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'prt',
        settlementMode: const Value('profit_share'),
        shareBp: const Value(10000),
      ));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'drv',
        settlementMode: const Value('payout_only'),
      ));
    });
    tearDown(() => db.close());

    test('1. by_work + share_basis=cash throws ERR_BY_WORK_REQUIRES_ACCRUAL from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
              projectId: 'p1',
              shareBasis: const Value('cash'),
              shareMethod: const Value('by_work'),
            )),
        DomainErrors.byWorkRequiresAccrual,
      );
    });

    test('2. distribution with sum of share_bp != 10000 throws ERR_SHARE_BP_SUM_NOT_10000 from DB trigger', () async {
      await db.customStatement("UPDATE project_persons SET share_bp = 6000 WHERE project_id = 'p1' AND person_id = 'prt'");
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 't_bad_bp',
              projectId: 'p1',
              type: 'payout',
              amount: 500,
              date: '2025-03-20',
              personId: const Value('prt'),
              cashAccountId: const Value('c1'),
              purpose: const Value('distribution'),
            )),
        DomainErrors.shareBpSumNot10000,
      );
    });

    test('3. distribution for payout_only person throws ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON from DB trigger', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 't_bad_dist',
              projectId: 'p1',
              type: 'payout',
              amount: 500,
              date: '2025-03-20',
              personId: const Value('drv'),
              cashAccountId: const Value('c1'),
              purpose: const Value('distribution'),
            )),
        DomainErrors.distributionForPayoutOnly,
      );
    });

    test('6. performed_by or attributed_to non-participating partner throws ERR_PARTNER_NOT_PARTICIPATING from DB trigger', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'w_bad_perf',
              projectId: 'p1',
              type: 'work_in',
              amount: 1000,
              date: '2025-03-20',
              clientId: const Value('cli'),
              performedBy: const Value('drv'),
            )),
        DomainErrors.partnerNotParticipating,
      );
    });

    test('7a. editing settings after first distribution throws ERR_PROJECT_SETTINGS_LOCKED from DB trigger', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'p1'));
      // First distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist1',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_settings SET report_basis='cash' WHERE project_id='p1'"),
        DomainErrors.projectSettingsLocked,
      );
    });

    test('7b. deleting settings after first distribution throws ERR_PROJECT_SETTINGS_LOCKED from DB trigger', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'p1'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_del_sett',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_settings WHERE project_id='p1'"),
        DomainErrors.projectSettingsLocked,
      );
    });

    test('7c. inserting settings in locked project throws ERR_PROJECT_SETTINGS_LOCKED from DB trigger', () async {
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p_lock', name: 'قفل', status: const Value('locked')));
      await expectDbThrowsDomainCode(
        () => db.customStatement("INSERT INTO project_settings (project_id) VALUES ('p_lock')"),
        DomainErrors.projectSettingsLocked,
      );
    });

    test('7d. editing project_persons after first distribution throws ERR_PROJECT_PERSONS_LOCKED from DB trigger', () async {
      // First distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_pp_lock',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET share_bp=8000 WHERE project_id='p1' AND person_id='prt'"),
        DomainErrors.projectPersonsLocked,
      );
    });

    test('7e. inserting project_persons after first distribution throws ERR_PROJECT_PERSONS_LOCKED from DB trigger', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_pp_ins',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p_extra', name: 'شخص اضافی', kind: 'driver'));

      await expectDbThrowsDomainCode(
        () => db.customStatement("INSERT INTO project_persons (project_id, person_id, settlement_mode) VALUES ('p1', 'p_extra', 'payout_only')"),
        DomainErrors.projectPersonsLocked,
      );
    });

    test('7f. deleting project_persons after first distribution throws ERR_PROJECT_PERSONS_LOCKED from DB trigger', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p_free_del', name: 'شخص بدون تراکنش', kind: 'driver'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'p_free_del',
        settlementMode: const Value('payout_only'),
      ));
      // First distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_pp_del',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='p_free_del'"),
        DomainErrors.projectPersonsLocked,
      );
    });

    test('8. transfer with same from and to account throws ERR_TRANSFER_SAME_ACCOUNT from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'tr_same',
              projectId: 'p1',
              type: 'transfer',
              amount: 500,
              date: '2025-03-20',
              fromAccountId: const Value('c1'),
              toAccountId: const Value('c1'),
            )),
        DomainErrors.transferSameAccount,
      );
    });

    test('9a. income missing cash_account_id throws ERR_MISSING_CASH_ACCOUNT from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'inc_no_acc',
              projectId: 'p1',
              type: 'income',
              amount: 500,
              date: '2025-03-20',
              clientId: const Value('cli'),
            )),
        DomainErrors.missingCashAccount,
      );
    });

    test('9b. expense missing cash_account_id throws ERR_MISSING_CASH_ACCOUNT from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'exp_no_acc',
              projectId: 'p1',
              type: 'expense',
              amount: 500,
              date: '2025-03-20',
            )),
        DomainErrors.missingCashAccount,
      );
    });

    test('9c. payout missing cash_account_id throws ERR_PAYOUT_REQUIRED_FIELDS from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'pay_no_acc',
              projectId: 'p1',
              type: 'payout',
              amount: 500,
              date: '2025-03-20',
              personId: const Value('drv'),
              purpose: const Value('settle_payable'),
            )),
        DomainErrors.payoutRequiredFields,
      );
    });

    test('9d. income with person_id throws ERR_INCOME_FORBIDDEN_FIELDS and NOT ERR_MISSING_CASH_ACCOUNT', () async {
      try {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'inc_with_person',
              projectId: 'p1',
              type: 'income',
              amount: 500,
              date: '2025-03-20',
              cashAccountId: const Value('c1'),
              clientId: const Value('cli'),
              personId: const Value('prt'),
            ));
        fail('Expected DB to throw, but succeeded');
      } catch (e) {
        final domain = mapSqliteException(e);
        expect(domain.code, DomainErrors.incomeForbiddenFields);
        expect(domain.code, isNot(equals(DomainErrors.missingCashAccount)));
      }
    });

    test('9e. income missing client_id throws ERR_INCOME_MISSING_CLIENT from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'inc_no_cli',
              projectId: 'p1',
              type: 'income',
              amount: 500,
              date: '2025-03-20',
              cashAccountId: const Value('c1'),
            )),
        DomainErrors.incomeMissingClient,
      );
    });

    test('10. work_in missing client_id throws ERR_WORK_IN_MISSING_CLIENT from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'win_no_cli',
              projectId: 'p1',
              type: 'work_in',
              amount: 500,
              date: '2025-03-20',
            )),
        DomainErrors.workInMissingClient,
      );
    });

    test('11. work_in with client_id kind != client throws ERR_CLIENT_KIND_MISMATCH from DB trigger', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'win_bad_kind',
              projectId: 'p1',
              type: 'work_in',
              amount: 500,
              date: '2025-03-20',
              clientId: const Value('prt'),
            )),
        DomainErrors.clientKindMismatch,
      );
    });

    test('11b. income with client_id kind != client throws ERR_CLIENT_KIND_MISMATCH from DB trigger', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'inc_bad_kind',
              projectId: 'p1',
              type: 'income',
              amount: 500,
              date: '2025-03-20',
              cashAccountId: const Value('c1'),
              clientId: const Value('prt'),
            )),
        DomainErrors.clientKindMismatch,
      );
    });

    test('12. personal account missing holder_person_id throws ERR_PERSONAL_ACCOUNT_MISSING_HOLDER from DB CHECK', () async {
      await expectDbThrowsDomainCode(
        () => db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
              id: 'acc_no_holder',
              name: 'حساب شخصی نامعتبر',
              kind: 'personal',
              holderPersonId: const Value(null),
            )),
        DomainErrors.personalAccountMissingHolder,
      );
    });

    test('13. payout to person not in project_persons throws ERR_PAYOUT_PERSON_NOT_IN_PROJECT from DB trigger', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'outsider', name: 'غریبه', kind: 'worker'));
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'payout_outsider',
              projectId: 'p1',
              type: 'payout',
              amount: 500,
              date: '2025-03-20',
              personId: const Value('outsider'),
              cashAccountId: const Value('c1'),
              purpose: const Value('settle_payable'),
            )),
        DomainErrors.payoutPersonNotInProject,
      );
    });

    test('14. work_out to person not in project_persons throws ERR_WORK_OUT_PERSON_NOT_IN_PROJECT from DB trigger', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'worker1', name: 'کارگر', kind: 'worker'));
      await expectDbThrowsDomainCode(
        () => db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: 'wo_outsider',
              projectId: 'p1',
              type: 'work_out',
              amount: 500,
              date: '2025-03-20',
              personId: const Value('worker1'),
            )),
        DomainErrors.workOutPersonNotInProject,
      );
    });

    test('15. demoting partner to payout_only with transactions throws ERR_CANNOT_DEMOTE_PARTNER_WITH_TRANSACTIONS', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_p1',
        projectId: 'p1',
        type: 'work_in',
        amount: 100,
        date: '2025-03-20',
        clientId: const Value('cli'),
        performedBy: const Value('prt'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET settlement_mode='payout_only' WHERE project_id='p1' AND person_id='prt'"),
        DomainErrors.cannotDemotePartnerWithTransactions,
      );
    });

    test('16a. deleting person with active tx referencing person_id throws ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_p_del_id',
        projectId: 'p1',
        type: 'work_out',
        amount: 100,
        date: '2025-03-20',
        personId: const Value('drv'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='drv'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });

    test('16b. deleting person with active tx referencing performed_by throws ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_p_del_perf',
        projectId: 'p1',
        type: 'work_in',
        amount: 100,
        date: '2025-03-20',
        clientId: const Value('cli'),
        performedBy: const Value('prt'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='prt'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });

    test('16c. deleting person with active tx referencing attributed_to throws ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_p_del_attr',
        projectId: 'p1',
        type: 'work_out',
        amount: 100,
        date: '2025-03-20',
        personId: const Value('drv'),
        attributedTo: const Value('prt'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='prt'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });

    test('17a. undeleting a soft-deleted transaction throws ERR_TX_UNDELETE_FORBIDDEN', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_soft_del',
        projectId: 'p1',
        type: 'work_in',
        amount: 100,
        date: '2025-03-20',
        clientId: const Value('cli'),
        deletedAt: const Value('2025-03-20T10:00:00Z'),
        deletedReason: const Value('mistake'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE transactions SET deleted_at=NULL, deleted_reason=NULL WHERE id='tx_soft_del'"),
        DomainErrors.txUndeleteForbidden,
      );
    });

    test('17b. editing amount in locked project throws ERR_PROJECT_LOCKED_TX', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_lock_edit',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv'),
      ));
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p1'");

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE transactions SET amount=9999 WHERE id='tx_lock_edit'"),
        DomainErrors.projectLockedTx,
      );
    });

    test('17c. soft-deleting transaction in locked project throws ERR_PROJECT_LOCKED_TX', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_lock_del',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv'),
      ));
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p1'");

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE transactions SET deleted_at='2025-03-20T10:00:00Z', deleted_reason='test' WHERE id='tx_lock_del'"),
        DomainErrors.projectLockedTx,
      );
    });

    test('17d. scenario: soft-delete distribution -> change settings -> undelete throws ERR_TX_UNDELETE_FORBIDDEN', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'p1'));
      // 1. Insert active distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_scen',
        projectId: 'p1',
        type: 'payout',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt'),
        cashAccountId: const Value('c1'),
        purpose: const Value('distribution'),
      ));

      // 2. Editing settings blocked while distribution active
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_settings SET report_basis='cash' WHERE project_id='p1'"),
        DomainErrors.projectSettingsLocked,
      );

      // 3. Soft-delete the distribution
      await db.customStatement("UPDATE transactions SET deleted_at='2025-03-20T10:00:00Z', deleted_reason='canceled' WHERE id='dist_scen'");

      // 4. Now changing settings succeeds (no active distribution)
      await db.customStatement("UPDATE project_settings SET report_basis='cash' WHERE project_id='p1'");
      final sett = await (db.select(db.projectSettings)..where((s) => s.projectId.equals('p1'))).getSingle();
      expect(sett.reportBasis, 'cash');

      // 5. Attempting to undelete the distribution must fail with ERR_TX_UNDELETE_FORBIDDEN
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE transactions SET deleted_at=NULL, deleted_reason=NULL WHERE id='dist_scen'"),
        DomainErrors.txUndeleteForbidden,
      );
    });

    test('18. updating app_settings key throws ERR_APP_SETTINGS_KEY_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE app_settings SET key='unit2' WHERE key='unit'"),
        DomainErrors.appSettingsKeyImmutable,
      );
    });

    test('19a. updating unit value throws ERR_UNIT_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE app_settings SET value='rial' WHERE key='unit'"),
        DomainErrors.unitImmutable,
      );
    });

    test('19b. deleting unit key throws ERR_UNIT_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM app_settings WHERE key='unit'"),
        DomainErrors.unitImmutable,
      );
    });

    test('19c. inserting unit key with non-toman value throws ERR_UNIT_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("INSERT INTO app_settings (key, value) VALUES ('unit', 'rial')"),
        DomainErrors.unitImmutable,
      );
    });

    test('20. updating project_persons PK with active transactions throws ERR_CANNOT_UPDATE_PROJECT_PERSON_PK_WITH_TX', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_pk_test',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv'),
      ));

      // Insert destination person into persons table so foreign key is valid,
      // but person is not registered in project_persons for p1.
      await db.into(db.persons).insert(PersonsCompanion.insert(
        id: 'p_dest_fresh',
        name: 'شخص مقصد جدید',
        kind: 'driver',
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET person_id='p_dest_fresh' WHERE project_id='p1' AND person_id='drv'"),
        DomainErrors.cannotUpdateProjectPersonPkWithTx,
      );
    });

    test('21. demoting settlement_mode to profit_share with active work_out throws ERR_CANNOT_DEMOTE_PAYOUT_PARTNER_WITH_TX', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_demote_wo',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET settlement_mode='profit_share', share_bp=100 WHERE project_id='p1' AND person_id='drv'"),
        DomainErrors.cannotDemotePayoutPartnerWithTx,
      );
    });

    test('23a. project cash account with holder_person_id throws ERR_PROJECT_ACCOUNT_HAS_HOLDER from DB CHECK', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(
        id: 'pers_c',
        name: 'Personal Holder',
        kind: 'partner',
      ));

      // Negative: project account with non-null holder throws
      await expectDbThrowsDomainCode(
        () => db.customStatement("INSERT INTO cash_accounts (id, name, kind, holder_person_id, created_at, updated_at) VALUES ('ca_proj_bad', 'Project Bank Bad', 'project', 'pers_c', '2025-03-20', '2025-03-20')"),
        DomainErrors.projectAccountHasHolder,
      );

      // Positive: project account with null holder succeeds
      await db.customStatement("INSERT INTO cash_accounts (id, name, kind, holder_person_id, created_at, updated_at) VALUES ('ca_proj_ok', 'Project Bank OK', 'project', NULL, '2025-03-20', '2025-03-20')");
      final inserted = await (db.select(db.cashAccounts)..where((tbl) => tbl.id.equals('ca_proj_ok'))).getSingle();
      expect(inserted.kind, 'project');
      expect(inserted.holderPersonId, null);
    });

    test('24a. updating kind of person with active transactions throws ERR_CANNOT_CHANGE_PERSON_KIND_WITH_TX', () async {
      await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: 'p_kind_test',
        name: 'Project Kind Test',
        status: const Value('open'),
      ));
      await db.into(db.persons).insert(PersonsCompanion.insert(
        id: 'client_kind_test',
        name: 'Client For Kind Test',
        kind: 'client',
      ));
      await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
        id: 'acc_kind_test',
        name: 'Acc Kind Test',
        kind: 'project',
      ));

      // Insert active transaction referencing client_kind_test as client_id
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_kind_test',
        projectId: 'p_kind_test',
        type: 'income',
        amount: 1000,
        date: '2025-03-20',
        clientId: const Value('client_kind_test'),
        cashAccountId: const Value('acc_kind_test'),
      ));

      // Negative: changing kind from client to partner throws ERR_CANNOT_CHANGE_PERSON_KIND_WITH_TX
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE persons SET kind='partner' WHERE id='client_kind_test'"),
        DomainErrors.cannotChangePersonKindWithTx,
      );

      // Positive 1: updating name/note of person with active tx succeeds
      await db.customStatement("UPDATE persons SET name='Client Updated Name' WHERE id='client_kind_test'");
      final updatedPerson = await (db.select(db.persons)..where((tbl) => tbl.id.equals('client_kind_test'))).getSingle();
      expect(updatedPerson.name, 'Client Updated Name');

      // Positive 2: person without active transactions can change kind
      await db.into(db.persons).insert(PersonsCompanion.insert(
        id: 'free_person',
        name: 'Free Person',
        kind: 'worker',
      ));
      await db.customStatement("UPDATE persons SET kind='driver' WHERE id='free_person'");
      final freePerson = await (db.select(db.persons)..where((tbl) => tbl.id.equals('free_person'))).getSingle();
      expect(freePerson.kind, 'driver');
    });

    test('22. unknown error is rethrown by mapSqliteException', () {
      final customError = FormatException('Unknown test error');
      expect(() => mapSqliteException(customError), throwsA(isA<FormatException>()));
    });
  });

  group('Section 6 Tests [ناتمام/وابسته به BalanceService]', () {
    test('[ناتمام/وابسته به BalanceService] 4. distribution exceeding Share without override throws ERR_DISTRIBUTION_EXCEEDS_SHARE', () {
      // Requires live BalanceService to compute claimable share
    }, skip: 'وابسته به BalanceService در فاز ۱');

    test('[ناتمام/وابسته به BalanceService] 5. settle_payable exceeding Pay without override throws ERR_SETTLE_PAYABLE_EXCEEDS_PAY', () {
      // Requires live BalanceService to compute Pay(p)
    }, skip: 'وابسته به BalanceService در فاز ۱');
  });

  group('Schema v1 -> v2 Migration Strategy (LegacyDatabaseException on upgrade)', () {
    test('legacy v1 database fixture throws LegacyDatabaseException on open', () async {
      final tempDir = Directory.systemTemp.createTempSync('karkard_legacy_test_');
      final dbFile = File('${tempDir.path}/legacy_v1.db');
      try {
        // Create an SQLite database with user_version = 1
        final rawDb = sqlite.sqlite3.open(dbFile.path);
        rawDb.userVersion = 1;
        rawDb.execute('CREATE TABLE app_settings ("key" TEXT NOT NULL PRIMARY KEY, "value" TEXT NOT NULL);');
        rawDb.execute("INSERT INTO app_settings (\"key\", \"value\") VALUES ('schema_version', '1');");
        rawDb.close();

        // Opening this v1 db via AppDatabase should call onUpgrade and throw LegacyDatabaseException
        final appDb = AppDatabase.forFile(dbFile);
        try {
          await expectLater(
            appDb.select(appDb.appSettings).get(),
            throwsA(isA<LegacyDatabaseException>().having(
              (e) => e.fromVersion,
              'fromVersion',
              1,
            ).having(
              (e) => e.toVersion,
              'toVersion',
              2,
            ).having(
              (e) => e.message,
              'message',
              contains('نسخه آزمایشی قدیمی‌تر'),
            )),
          );
        } finally {
          await appDb.close();
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
