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

    test('7b. editing project_persons after first distribution throws ERR_PROJECT_PERSONS_LOCKED from DB trigger', () async {
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
              personId: const Value('prt'),
            ));
        fail('Expected DB to throw, but succeeded');
      } catch (e) {
        final domain = mapSqliteException(e);
        expect(domain.code, DomainErrors.incomeForbiddenFields);
        expect(domain.code, isNot(equals(DomainErrors.missingCashAccount)));
      }
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

    test('16. deleting person with active transactions throws ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_p_del',
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

    test('17. undeleting a soft-deleted transaction throws ERR_TX_UNDELETE_FORBIDDEN', () async {
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

    test('18. updating app_settings key throws ERR_APP_SETTINGS_KEY_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE app_settings SET key='unit2' WHERE key='unit'"),
        DomainErrors.appSettingsKeyImmutable,
      );
    });

    test('19. updating unit or setting unit to non-toman throws ERR_UNIT_IMMUTABLE', () async {
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE app_settings SET value='rial' WHERE key='unit'"),
        DomainErrors.unitImmutable,
      );
      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM app_settings WHERE key='unit'"),
        DomainErrors.unitImmutable,
      );
      await expectDbThrowsDomainCode(
        () => db.customStatement("INSERT INTO app_settings (key, value) VALUES ('unit', 'rial')"),
        DomainErrors.unitImmutable,
      );
    });

    test('20. unknown error is rethrown by mapSqliteException', () {
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

  group('Schema v1 -> v2 Migration Strategy (UnsupportedError on upgrade)', () {
    test('legacy v1 database fixture throws UnsupportedError on open', () async {
      final tempDir = Directory.systemTemp.createTempSync('karkard_legacy_test_');
      final dbFile = File('${tempDir.path}/legacy_v1.db');
      try {
        // Create an SQLite database with user_version = 1
        final rawDb = sqlite.sqlite3.open(dbFile.path);
        rawDb.userVersion = 1;
        rawDb.execute('CREATE TABLE app_settings ("key" TEXT NOT NULL PRIMARY KEY, "value" TEXT NOT NULL);');
        rawDb.execute("INSERT INTO app_settings (\"key\", \"value\") VALUES ('schema_version', '1');");
        rawDb.close();

        // Opening this v1 db via AppDatabase should call onUpgrade and throw UnsupportedError
        final appDb = AppDatabase.forFile(dbFile);
        try {
          await expectLater(
            appDb.select(appDb.appSettings).get(),
            throwsA(isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains('Migration from schema v1 to v2 is not supported'),
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
