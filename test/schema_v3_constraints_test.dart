import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/core/error_mapper.dart';
import 'package:karkard/data/database.dart';

Future<void> expectDbThrowsDomainCode(Future<void> Function() action, String expectedCode) async {
  try {
    await action();
    fail('Expected DB to throw $expectedCode, but succeeded');
  } catch (e) {
    final domain = mapSqliteException(e);
    expect(domain.code, expectedCode);
  }
}

Matcher throwsDbError([String? pattern]) {
  if (pattern != null) {
    return throwsA(isA<SqliteException>().having(
      (e) => e.toString(),
      'message',
      contains(pattern),
    ));
  }
  return throwsA(isA<SqliteException>());
}

Future<AppDatabase> newDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customSelect('select 1').get();
  return db;
}

Future<void> seedV3(AppDatabase db) async {
  await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p1', name: 'پروژه ۱'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'cli1', name: 'کارفرما ۱', kind: 'client'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt1', name: 'شریک امیر', kind: 'partner'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt2', name: 'شریک عارف', kind: 'partner'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'drv1', name: 'راننده علی', kind: 'driver'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'outsider', name: 'شخص خارج از پروژه', kind: 'partner'));

  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'acc_proj', name: 'صندوق', kind: 'project'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'acc_bank', name: 'بانک', kind: 'project'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'acc_amir', name: 'جیب امیر', kind: 'personal', holderPersonId: const Value('prt1')));

  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'p1',
    personId: 'prt1',
    settlementMode: const Value('profit_share'),
    shareBp: const Value(5000),
    shareOrder: const Value(1),
  ));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'p1',
    personId: 'prt2',
    settlementMode: const Value('profit_share'),
    shareBp: const Value(5000),
    shareOrder: const Value(2),
  ));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'p1',
    personId: 'drv1',
    settlementMode: const Value('payout_only'),
  ));
}

void main() {
  late AppDatabase db;
  setUp(() async {
    db = await newDb();
    await seedV3(db);
  });
  tearDown(() => db.close());

  group('Constraint 1: typeof(amount) = integer', () {
    test('positive: typeof(amount) integer 100 accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 't_ok',
        projectId: 'p1',
        type: 'income',
        amount: 100,
        date: '2025-03-20',
        cashAccountId: const Value('acc_proj'),
        clientId: const Value('cli1'),
      ));
      final row = await (db.select(db.transactions)..where((t) => t.id.equals('t_ok'))).getSingle();
      expect(row.amount, 100);
    });

    test('negative: typeof(amount) float 12.5 rejected and string 100 coerced to integer by affinity', () async {
      expect(
        db.customStatement("INSERT INTO transactions (id, project_id, type, amount, date, cash_account_id, client_id, created_at, updated_at) VALUES ('f1', 'p1', 'income', 12.5, '2025-03-20', 'acc_proj', 'cli1', 1, 1)"),
        throwsDbError('chk_tx_amount_type'),
      );
      // SQLite integer affinity coerces text '100' to integer 100, so typeof(amount) becomes 'integer'
      await db.customStatement("INSERT INTO transactions (id, project_id, type, amount, date, cash_account_id, client_id, created_at, updated_at) VALUES ('f2', 'p1', 'income', '100', '2025-03-20', 'acc_proj', 'cli1', 1, 1)");
      final row = await (db.select(db.transactions)..where((t) => t.id.equals('f2'))).getSingle();
      expect(row.amount, 100);
    });
  });

  group('Constraint 2: typeof(share_bp) = integer and range [0..10000]', () {
    test('positive: share_bp integer 5000 in [0..10000] accepted', () async {
      final p = await (db.select(db.projectPersons)..where((pp) => pp.personId.equals('prt1'))).getSingle();
      expect(p.shareBp, 5000);
    });

    test('negative: share_bp float, >10000, or <0 rejected; string coerced by affinity', () async {
      expect(
        db.customStatement("INSERT INTO project_persons (project_id, person_id, settlement_mode, share_bp, created_at, updated_at) VALUES ('p1', 'outsider', 'profit_share', 50.5, 1, 1)"),
        throwsDbError('chk_pp_share_bp'),
      );
      // SQLite integer affinity coerces text '5000' to integer 5000
      await db.customStatement("INSERT INTO project_persons (project_id, person_id, settlement_mode, share_bp, created_at, updated_at) VALUES ('p1', 'outsider', 'profit_share', '5000', 1, 1)");
      final pp = await (db.select(db.projectPersons)..where((p) => p.personId.equals('outsider'))).getSingle();
      expect(pp.shareBp, 5000);
      await db.customStatement("DELETE FROM project_persons WHERE person_id='outsider'");

      expect(
        db.customStatement("INSERT INTO project_persons (project_id, person_id, settlement_mode, share_bp, created_at, updated_at) VALUES ('p1', 'outsider', 'profit_share', 10001, 1, 1)"),
        throwsDbError('chk_pp_share_bp'),
      );
      expect(
        db.customStatement("INSERT INTO project_persons (project_id, person_id, settlement_mode, share_bp, created_at, updated_at) VALUES ('p1', 'outsider', 'profit_share', -1, 1, 1)"),
        throwsDbError('chk_pp_share_bp'),
      );
    });
  });

  group('Constraint 3: project_settings share_method=by_work requires share_basis=accrual', () {
    test('positive: by_work with accrual accepted', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
        projectId: 'p1',
        shareBasis: const Value('accrual'),
        shareMethod: const Value('by_work'),
      ));
      final s = await (db.select(db.projectSettings)..where((ps) => ps.projectId.equals('p1'))).getSingle();
      expect(s.shareMethod, 'by_work');
    });

    test('negative: by_work with cash rejected', () async {
      expect(
        db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
          projectId: 'p1',
          shareBasis: const Value('cash'),
          shareMethod: const Value('by_work'),
        )),
        throwsDbError('chk_ps_by_work_requires_accrual'),
      );
    });
  });

  group('Constraint 4: cash_accounts kind=personal requires holder_person_id', () {
    test('positive: personal with holder and project without holder accepted', () async {
      final acc = await (db.select(db.cashAccounts)..where((a) => a.id.equals('acc_amir'))).getSingle();
      expect(acc.holderPersonId, 'prt1');
    });

    test('negative: personal account without holder rejected', () async {
      expect(
        db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
          id: 'acc_bad',
          name: 'بی‌صاحب',
          kind: 'personal',
          holderPersonId: const Value(null),
        )),
        throwsDbError('chk_cash_account_holder_required'),
      );
    });
  });

  group('Constraint 5: work_in client_id mandatory and kind=client', () {
    test('positive: work_in with client_id kind=client accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'w1',
        projectId: 'p1',
        type: 'work_in',
        amount: 1000,
        date: '2025-03-20',
        clientId: const Value('cli1'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('w1'))).getSingle();
      expect(r.clientId, 'cli1');
    });

    test('negative: work_in without client_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'w_no_cli',
          projectId: 'p1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value(null),
        )),
        throwsDbError('chk_tx_work_in_client_required'),
      );
    });

    test('negative: work_in with client_id having kind != client rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'w_partner_as_cli',
          projectId: 'p1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value('prt1'),
        )),
        throwsDbError('ERR_CLIENT_KIND_MISMATCH'),
      );
    });
  });

  group('Constraint 6: work_out person_id mandatory', () {
    test('positive: work_out with person_id accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'wo1',
        projectId: 'p1',
        type: 'work_out',
        amount: 2000,
        date: '2025-03-20',
        personId: const Value('drv1'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('wo1'))).getSingle();
      expect(r.personId, 'drv1');
    });

    test('negative: work_out without person_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'wo_no_person',
          projectId: 'p1',
          type: 'work_out',
          amount: 2000,
          date: '2025-03-20',
          personId: const Value(null),
        )),
        throwsDbError('ERR_WORK_OUT_PERSON_NOT_IN_PROJECT'),
      );
    });
  });

  group('Constraint 7: income cash_account_id and client_id mandatory', () {
    test('positive: income with cash_account_id and client_id accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'inc1',
        projectId: 'p1',
        type: 'income',
        amount: 5000,
        date: '2025-03-20',
        cashAccountId: const Value('acc_proj'),
        clientId: const Value('cli1'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('inc1'))).getSingle();
      expect(r.cashAccountId, 'acc_proj');
      expect(r.clientId, 'cli1');
    });

    test('negative: income without cash_account_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'inc_no_acc',
          projectId: 'p1',
          type: 'income',
          amount: 5000,
          date: '2025-03-20',
          cashAccountId: const Value(null),
          clientId: const Value('cli1'),
        )),
        throwsDbError('chk_tx_income_account_required'),
      );
    });

    test('negative: income without client_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'inc_no_cli',
          projectId: 'p1',
          type: 'income',
          amount: 5000,
          date: '2025-03-20',
          cashAccountId: const Value('acc_proj'),
          clientId: const Value(null),
        )),
        throwsDbError('chk_tx_income_client_required'),
      );
    });

    test('negative: income with client_id having kind != client rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'inc_wrong_cli_kind',
          projectId: 'p1',
          type: 'income',
          amount: 5000,
          date: '2025-03-20',
          cashAccountId: const Value('acc_proj'),
          clientId: const Value('drv1'), // drv1 is driver, not client
        )),
        throwsDbError('ERR_CLIENT_KIND_MISMATCH'),
      );
    });
  });

  group('Constraint 8: expense cash_account_id mandatory', () {
    test('positive: expense with cash_account_id accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'exp1',
        projectId: 'p1',
        type: 'expense',
        amount: 300,
        date: '2025-03-20',
        cashAccountId: const Value('acc_proj'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('exp1'))).getSingle();
      expect(r.cashAccountId, 'acc_proj');
    });

    test('negative: expense without cash_account_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'exp_no_acc',
          projectId: 'p1',
          type: 'expense',
          amount: 300,
          date: '2025-03-20',
          cashAccountId: const Value(null),
        )),
        throwsDbError('chk_tx_expense_account_required'),
      );
    });
  });

  group('Constraint 9: payout person_id, cash_account_id, purpose mandatory', () {
    test('positive: payout with person, cash account, and purpose accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'pay1',
        projectId: 'p1',
        type: 'payout',
        amount: 400,
        date: '2025-03-20',
        personId: const Value('drv1'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('settle_payable'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('pay1'))).getSingle();
      expect(r.purpose, 'settle_payable');
    });

    test('negative: payout without purpose rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'pay_no_purpose',
          projectId: 'p1',
          type: 'payout',
          amount: 400,
          date: '2025-03-20',
          personId: const Value('drv1'),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value(null),
        )),
        throwsDbError('chk_tx_payout_required_fields'),
      );
    });

    test('negative: payout without cash_account_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'pay_no_acc',
          projectId: 'p1',
          type: 'payout',
          amount: 400,
          date: '2025-03-20',
          personId: const Value('drv1'),
          cashAccountId: const Value(null),
          purpose: const Value('settle_payable'),
        )),
        throwsDbError('chk_tx_payout_required_fields'),
      );
    });

    test('negative: payout without person_id rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'pay_no_person',
          projectId: 'p1',
          type: 'payout',
          amount: 400,
          date: '2025-03-20',
          personId: const Value(null),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value('settle_payable'),
        )),
        throwsDbError('ERR_PAYOUT_PERSON_NOT_IN_PROJECT'),
      );
    });

    test('negative: payout for person NOT in project_persons rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'pay_outsider',
          projectId: 'p1',
          type: 'payout',
          amount: 400,
          date: '2025-03-20',
          personId: const Value('outsider'),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value('settle_payable'),
        )),
        throwsDbError('ERR_PAYOUT_PERSON_NOT_IN_PROJECT'),
      );
    });
  });

  group('Constraint 10: transfer from_account != to_account', () {
    test('positive: transfer between distinct accounts accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tr1',
        projectId: 'p1',
        type: 'transfer',
        amount: 1000,
        date: '2025-03-20',
        fromAccountId: const Value('acc_proj'),
        toAccountId: const Value('acc_bank'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('tr1'))).getSingle();
      expect(r.fromAccountId, 'acc_proj');
      expect(r.toAccountId, 'acc_bank');
    });

    test('negative: transfer with same from and to account rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tr_same',
          projectId: 'p1',
          type: 'transfer',
          amount: 1000,
          date: '2025-03-20',
          fromAccountId: const Value('acc_proj'),
          toAccountId: const Value('acc_proj'),
        )),
        throwsDbError('chk_tx_transfer_accounts_required'),
      );
    });
  });

  group('Constraint 11: distribution purpose forbidden for payout_only or missing partner', () {
    test('positive: distribution for profit_share partner accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_ok',
        projectId: 'p1',
        type: 'payout',
        amount: 1000,
        date: '2025-03-20',
        personId: const Value('prt1'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('distribution'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('dist_ok'))).getSingle();
      expect(r.purpose, 'distribution');
    });

    test('negative: distribution for payout_only person rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'dist_fail',
          projectId: 'p1',
          type: 'payout',
          amount: 1000,
          date: '2025-03-20',
          personId: const Value('drv1'),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value('distribution'),
        )),
        throwsDbError('ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON'),
      );
    });

    test('negative: distribution for person not in project_persons rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'dist_outsider',
          projectId: 'p1',
          type: 'payout',
          amount: 1000,
          date: '2025-03-20',
          personId: const Value('outsider'),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value('distribution'),
        )),
        throwsDbError('ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON'),
      );
    });
  });

  group('Constraint 12: performed_by and attributed_to must be participating partner', () {
    test('positive: performed_by and attributed_to participating partner accepted', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'w_perf_ok',
        projectId: 'p1',
        type: 'work_in',
        amount: 1000,
        date: '2025-03-20',
        clientId: const Value('cli1'),
        performedBy: const Value('prt1'),
      ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'wo_attr_ok',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv1'),
        attributedTo: const Value('prt2'),
      ));
      expect((await db.select(db.transactions).get()).length, 2);
    });

    test('negative: performed_by non-participating driver rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'w_perf_bad',
          projectId: 'p1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value('cli1'),
          performedBy: const Value('drv1'),
        )),
        throwsDbError('ERR_PARTNER_NOT_PARTICIPATING'),
      );
    });

    test('negative: performed_by person not in project_persons rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'w_perf_outsider',
          projectId: 'p1',
          type: 'work_in',
          amount: 1000,
          date: '2025-03-20',
          clientId: const Value('cli1'),
          performedBy: const Value('outsider'),
        )),
        throwsDbError('ERR_PARTNER_NOT_PARTICIPATING'),
      );
    });

    test('negative: attributed_to person not in project_persons rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'wo_attr_outsider',
          projectId: 'p1',
          type: 'work_out',
          amount: 500,
          date: '2025-03-20',
          personId: const Value('drv1'),
          attributedTo: const Value('outsider'),
        )),
        throwsDbError('ERR_PARTNER_NOT_PARTICIPATING'),
      );
    });
  });

  group('Constraint 13: project_settings and project_persons locked after first distribution', () {
    test('positive: insert and update settings and persons before any distribution accepted', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
        projectId: 'p1',
        reportBasis: const Value('accrual'),
      ));
      await db.customStatement("UPDATE project_settings SET report_basis='both' WHERE project_id='p1'");
      await db.customStatement("UPDATE project_persons SET share_order=5 WHERE project_id='p1' AND person_id='prt1'");
    });

    test('negative: update or insert settings/persons after first distribution rejected by trigger', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
        projectId: 'p1',
        reportBasis: const Value('accrual'),
      ));

      // Insert first distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist1',
        projectId: 'p1',
        type: 'payout',
        amount: 1000,
        date: '2025-03-20',
        personId: const Value('prt1'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('distribution'),
      ));

      // UPDATE project_settings -> rejected
      expect(
        db.customStatement("UPDATE project_settings SET report_basis='cash' WHERE project_id='p1'"),
        throwsDbError('ERR_PROJECT_SETTINGS_LOCKED'),
      );
      // UPDATE project_persons -> rejected
      expect(
        db.customStatement("UPDATE project_persons SET share_order=10 WHERE project_id='p1' AND person_id='prt1'"),
        throwsDbError('ERR_PROJECT_PERSONS_LOCKED'),
      );
      // INSERT project_persons -> rejected
      expect(
        db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
          projectId: 'p1',
          personId: 'outsider',
          settlementMode: const Value('payout_only'),
        )),
        throwsDbError('ERR_PROJECT_PERSONS_LOCKED'),
      );
    });

    test('positive: demoting settlement_mode to payout_only without transactions succeeds', () async {
      await db.customStatement("UPDATE project_persons SET settlement_mode='payout_only' WHERE project_id='p1' AND person_id='prt2'");
      final p2 = await (db.select(db.projectPersons)..where((p) => p.personId.equals('prt2'))).getSingle();
      expect(p2.settlementMode, 'payout_only');
    });

    test('negative: demoting settlement_mode to payout_only with transactions rejected by trigger', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt1',
        projectId: 'p1',
        type: 'work_in',
        amount: 500,
        date: '2025-03-20',
        clientId: const Value('cli1'),
        performedBy: const Value('prt1'),
      ));

      expect(
        db.customStatement("UPDATE project_persons SET settlement_mode='payout_only' WHERE project_id='p1' AND person_id='prt1'"),
        throwsDbError('ERR_CANNOT_DEMOTE_PARTNER_WITH_TRANSACTIONS'),
      );
    });
  });

  group('Constraint 14: app_settings.unit=toman immutable', () {
    test('positive: unit=toman is set initially', () async {
      final u = await (db.select(db.appSettings)..where((s) => s.key.equals('unit'))).getSingle();
      expect(u.value, 'toman');
    });

    test('negative: updating unit rejected by trigger', () async {
      expect(
        db.customStatement("UPDATE app_settings SET value='rial' WHERE key='unit'"),
        throwsDbError('ERR_UNIT_IMMUTABLE'),
      );
    });

    test('negative: deleting unit rejected by trigger', () async {
      expect(
        db.customStatement("DELETE FROM app_settings WHERE key='unit'"),
        throwsDbError('ERR_UNIT_IMMUTABLE'),
      );
    });

    test('negative: INSERT OR REPLACE unit rejected', () async {
      expect(
        db.customStatement("INSERT OR REPLACE INTO app_settings (key, value) VALUES ('unit', 'rial')"),
        throwsDbError('ERR_UNIT_IMMUTABLE'),
      );
    });

    test('negative: DELETE + INSERT unit rejected', () async {
      expect(
        db.transaction(() async {
          await db.customStatement("DELETE FROM app_settings WHERE key='unit'");
          await db.customStatement("INSERT INTO app_settings (key, value) VALUES ('unit', 'rial')");
        }),
        throwsDbError('ERR_UNIT_IMMUTABLE'),
      );
    });

    test('positive: insert non-unit app setting succeeds', () async {
      await db.customStatement("INSERT INTO app_settings (key, value) VALUES ('theme', 'dark')");
      final s = await (db.select(db.appSettings)..where((item) => item.key.equals('theme'))).getSingle();
      expect(s.value, 'dark');
    });

    test('negative: rename key rejected by trigger', () async {
      expect(
        db.customStatement("UPDATE app_settings SET key='unit2' WHERE key='unit'"),
        throwsDbError('ERR_APP_SETTINGS_KEY_IMMUTABLE'),
      );
    });

    test('negative: insert key=unit with non-toman value rejected by CHECK', () async {
      expect(
        db.customStatement("INSERT INTO app_settings (key, value) VALUES ('unit', 'rial')"),
        throwsDbError('ERR_UNIT_IMMUTABLE'),
      );
    });
  });

  group('Constraint 15: work_out.person_id in project_persons with payout_only or both', () {
    test('positive: work_out with payout_only person succeeds', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'wo_ok',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv1'),
      ));
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('wo_ok'))).getSingle();
      expect(r.personId, 'drv1');
    });

    test('negative: work_out with outsider person rejected by trigger', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'wo_bad_person',
          projectId: 'p1',
          type: 'work_out',
          amount: 500,
          date: '2025-03-20',
          personId: const Value('outsider'),
        )),
        throwsDbError('ERR_WORK_OUT_PERSON_NOT_IN_PROJECT'),
      );
    });

    test('negative: work_out with profit_share only person rejected by trigger', () async {
      // prt1 has settlement_mode = 'profit_share'
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'wo_bad_mode',
          projectId: 'p1',
          type: 'work_out',
          amount: 500,
          date: '2025-03-20',
          personId: const Value('prt1'),
        )),
        throwsDbError('ERR_WORK_OUT_PERSON_NOT_IN_PROJECT'),
      );
    });
  });

  group('Constraint 16: DELETE from project_persons forbidden when active tx references person', () {
    test('positive: deleting person with no transactions succeeds', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'temp_drv', name: 'راننده موقت', kind: 'driver'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'temp_drv',
        settlementMode: const Value('payout_only'),
      ));

      await db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='temp_drv'");
      final remaining = await (db.select(db.projectPersons)
            ..where((pp) => pp.projectId.equals('p1') & pp.personId.equals('temp_drv')))
          .get();
      expect(remaining.isEmpty, isTrue);
    });

    test('Constraint 16a: negative: deleting person when active tx references person_id rejected', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_drv1_del',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv1'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='drv1'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });

    test('Constraint 16b: negative: deleting person when active tx references performed_by rejected', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt1_perf_del',
        projectId: 'p1',
        type: 'work_in',
        amount: 1000,
        date: '2025-03-20',
        clientId: const Value('cli1'),
        performedBy: const Value('prt1'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='prt1'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });

    test('Constraint 16c: negative: deleting person when active tx references attributed_to rejected', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt2_attr_del',
        projectId: 'p1',
        type: 'work_out',
        amount: 300,
        date: '2025-03-20',
        personId: const Value('drv1'),
        attributedTo: const Value('prt2'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("DELETE FROM project_persons WHERE project_id='p1' AND person_id='prt2'"),
        DomainErrors.cannotDeletePersonWithTransactions,
      );
    });
  });

  group('Constraint 19: UPDATE PK of project_persons forbidden when active tx references person', () {
    test('positive: updating person_id/project_id when no active tx references person succeeds', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p_free', name: 'شخص آزاد', kind: 'driver'));
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p_free2', name: 'شخص آزاد ۲', kind: 'driver'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'p_free',
        settlementMode: const Value('payout_only'),
      ));

      await db.customStatement("UPDATE project_persons SET person_id='p_free2' WHERE project_id='p1' AND person_id='p_free'");
      final updated = await (db.select(db.projectPersons)
            ..where((pp) => pp.projectId.equals('p1') & pp.personId.equals('p_free2')))
          .getSingle();
      expect(updated.personId, 'p_free2');
    });

    test('negative: updating person_id when active tx references person rejected by trigger', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_drv1_pk',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('drv1'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET person_id='outsider' WHERE project_id='p1' AND person_id='drv1'"),
        DomainErrors.cannotUpdateProjectPersonPkWithTx,
      );
    });

    test('negative: updating project_id when active tx references person rejected by trigger', () async {
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p2', name: 'پروژه ۲'));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt1_proj_pk',
        projectId: 'p1',
        type: 'work_in',
        amount: 800,
        date: '2025-03-20',
        clientId: const Value('cli1'),
        performedBy: const Value('prt1'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET project_id='p2' WHERE project_id='p1' AND person_id='prt1'"),
        DomainErrors.cannotUpdateProjectPersonPkWithTx,
      );
    });
  });

  group('Constraint 20: demote settlement_mode to profit_share forbidden when work_out or settle_payable payout exists', () {
    test('positive: demoting settlement_mode to profit_share when no work_out/settle_payable exists succeeds', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'p_demo', name: 'شخص دمو', kind: 'partner'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'p_demo',
        settlementMode: const Value('payout_only'),
      ));

      await db.customStatement("UPDATE project_persons SET settlement_mode='profit_share', share_bp=100 WHERE project_id='p1' AND person_id='p_demo'");
      final res = await (db.select(db.projectPersons)
            ..where((pp) => pp.projectId.equals('p1') & pp.personId.equals('p_demo')))
          .getSingle();
      expect(res.settlementMode, 'profit_share');
    });

    test('negative: demoting payout_only to profit_share with active work_out rejected by trigger', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt_wo', name: 'شریک کارکرد', kind: 'partner'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'prt_wo',
        settlementMode: const Value('both'),
        shareBp: const Value(100),
      ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt_wo',
        projectId: 'p1',
        type: 'work_out',
        amount: 500,
        date: '2025-03-20',
        personId: const Value('prt_wo'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET settlement_mode='profit_share', share_bp=100 WHERE project_id='p1' AND person_id='prt_wo'"),
        DomainErrors.cannotDemotePayoutPartnerWithTx,
      );
    });

    test('negative: demoting payout_only to profit_share with active settle_payable payout rejected by trigger', () async {
      await db.into(db.persons).insert(PersonsCompanion.insert(id: 'prt_pay', name: 'شریک تسویه', kind: 'partner'));
      await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
        projectId: 'p1',
        personId: 'prt_pay',
        settlementMode: const Value('both'),
        shareBp: const Value(100),
      ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_ref_prt_pay',
        projectId: 'p1',
        type: 'payout',
        amount: 400,
        date: '2025-03-20',
        personId: const Value('prt_pay'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('settle_payable'),
      ));

      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE project_persons SET settlement_mode='profit_share', share_bp=100 WHERE project_id='p1' AND person_id='prt_pay'"),
        DomainErrors.cannotDemotePayoutPartnerWithTx,
      );
    });
  });

  group('Constraint 17: distribution forbidden when sum of share_bp != 10000', () {
    test('positive: distribution succeeds when active partners sum of share_bp == 10000', () async {
      // prt1 (5000) + prt2 (5000) = 10000
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_ok',
        projectId: 'p1',
        type: 'payout',
        amount: 1000,
        date: '2025-03-20',
        personId: const Value('prt1'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('distribution'),
      ));
      final d = await (db.select(db.transactions)..where((t) => t.id.equals('dist_ok'))).getSingle();
      expect(d.amount, 1000);
    });

    test('negative: distribution rejected when sum of share_bp != 10000', () async {
      // Change prt1 share_bp to 4000 (total = 4000 + 5000 = 9000 != 10000)
      await db.customStatement("UPDATE project_persons SET share_bp=4000 WHERE project_id='p1' AND person_id='prt1'");

      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'dist_bad_sum',
          projectId: 'p1',
          type: 'payout',
          amount: 1000,
          date: '2025-03-20',
          personId: const Value('prt1'),
          cashAccountId: const Value('acc_proj'),
          purpose: const Value('distribution'),
        )),
        throwsDbError('ERR_SHARE_BP_SUM_NOT_10000'),
      );
    });
  });

  group('Constraint 18: UPDATE transactions undeleting forbidden', () {
    test('positive: soft deleting a transaction succeeds', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_to_soft_del',
        projectId: 'p1',
        type: 'income',
        amount: 200,
        date: '2025-03-20',
        cashAccountId: const Value('acc_proj'),
        clientId: const Value('cli1'),
      ));

      await db.customStatement(
        "UPDATE transactions SET deleted_at='2025-03-20T12:00:00Z', deleted_reason='duplicated' WHERE id='tx_to_soft_del'",
      );
      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_to_soft_del'))).getSingle();
      expect(tx.deletedAt, isNotNull);
      expect(tx.deletedReason, 'duplicated');
    });

    test('negative: soft-delete distribution -> update settings -> undelete throws', () async {
      await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(projectId: 'p1'));

      // 1. Record distribution
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'dist_to_undelete',
        projectId: 'p1',
        type: 'payout',
        amount: 1000,
        date: '2025-03-20',
        personId: const Value('prt1'),
        cashAccountId: const Value('acc_proj'),
        purpose: const Value('distribution'),
      ));

      // 2. Soft delete distribution
      await db.customStatement(
        "UPDATE transactions SET deleted_at='2025-03-20T12:00:00Z', deleted_reason='test error' WHERE id='dist_to_undelete'",
      );

      // 3. Update project settings (now permitted because no active distribution)
      await db.customStatement("UPDATE project_settings SET report_basis='cash' WHERE project_id='p1'");

      // 4. Attempt to undelete distribution -> throws
      await expectDbThrowsDomainCode(
        () => db.customStatement("UPDATE transactions SET deleted_at=NULL, deleted_reason=NULL WHERE id='dist_to_undelete'"),
        DomainErrors.txUndeleteForbidden,
      );
    });
  });
}
