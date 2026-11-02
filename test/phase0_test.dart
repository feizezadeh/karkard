import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/core/jalali.dart';
import 'package:karkard/core/money.dart';
import 'package:karkard/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

Future<AppDatabase> newDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customSelect('select 1').get(); // force open + migration
  return db;
}

Future<void> seedBasic(AppDatabase db) async {
  await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p1', name: 'پروژه ۱'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'client1', name: 'کارفرما ۱', kind: 'client'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'driver1', name: 'راننده ۱', kind: 'driver'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'partner1', name: 'امیر', kind: 'partner'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c1', name: 'صندوق پروژه', kind: 'project'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c2', name: 'حساب دوم', kind: 'project'));
  await db.into(db.categories).insert(CategoriesCompanion.insert(id: 'cat1', name: 'سوخت', kind: 'expense'));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'p1',
    personId: 'partner1',
    settlementMode: const Value('profit_share'),
    shareBp: const Value(10000),
  ));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'p1',
    personId: 'driver1',
    settlementMode: const Value('payout_only'),
  ));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() async {
    db = await newDb();
    await seedBasic(db);
  });
  tearDown(() => db.close());

  group('migration v2', () {
    test('schema_version and tables exist; FK on', () async {
      final v = await (db.select(db.appSettings)
            ..where((t) => t.key.equals('schema_version')))
          .getSingle();
      expect(v.value, '2');

      final unit = await (db.select(db.appSettings)
            ..where((t) => t.key.equals('unit')))
          .getSingle();
      expect(unit.value, 'toman');

      final names = (await db
              .customSelect("select name from sqlite_master where type='table'")
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(
          names,
          containsAll([
            'persons',
            'projects',
            'categories',
            'cash_accounts',
            'project_settings',
            'project_persons',
            'transactions',
            'receipts',
            'audit_log',
            'app_settings',
          ]));
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.data.values.first, 1);
    });

    test('audit_log is generic (entity_type/entity_id), receipts has no status', () async {
      Future<Set<String>> cols(String t) async => (await db
              .customSelect('PRAGMA table_info($t)')
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(await cols('audit_log'),
          containsAll(['entity_type', 'entity_id']));
      final tx = await cols('transactions');
      expect(tx, contains('receipt_not_required'));
      expect(tx, isNot(contains('receipt_status')));
      expect(tx, containsAll([
        'client_id',
        'person_id',
        'performed_by',
        'attributed_to',
        'cash_account_id',
        'from_account_id',
        'to_account_id',
        'purpose',
        'override_reason',
      ]));
    });
  });

  group('constraints basic', () {
    test('valid rows of 6 types insert successfully', () async {
      // 1. work_in
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_win',
        projectId: 'p1',
        type: 'work_in',
        amount: 60000000,
        date: '2025-03-20',
        clientId: const Value('client1'),
        performedBy: const Value('partner1'),
      ));

      // 2. work_out
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_wout',
        projectId: 'p1',
        type: 'work_out',
        amount: 6000000,
        date: '2025-03-20',
        personId: const Value('driver1'),
        attributedTo: const Value('partner1'),
      ));

      // 3. income
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_inc',
        projectId: 'p1',
        type: 'income',
        amount: 30000000,
        date: '2025-03-21',
        cashAccountId: const Value('c1'),
        clientId: const Value('client1'),
      ));

      // 4. expense
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_exp',
        projectId: 'p1',
        type: 'expense',
        amount: 2000000,
        date: '2025-03-22',
        cashAccountId: const Value('c1'),
        categoryId: const Value('cat1'),
      ));

      // 5. payout (settle_payable)
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_pay',
        projectId: 'p1',
        type: 'payout',
        amount: 4000000,
        date: '2025-03-23',
        personId: const Value('driver1'),
        cashAccountId: const Value('c1'),
        purpose: const Value('settle_payable'),
      ));

      // 6. transfer
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_trans',
        projectId: 'p1',
        type: 'transfer',
        amount: 3000000,
        date: '2025-03-24',
        fromAccountId: const Value('c1'),
        toAccountId: const Value('c2'),
      ));

      final count = (await db.select(db.transactions).get()).length;
      expect(count, 6);
    });

    test('amount <= 0 rejected', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'bad_amt1',
          projectId: 'p1',
          type: 'income',
          amount: 0,
          date: '2025-03-20',
          cashAccountId: const Value('c1'),
          clientId: const Value('client1'),
        )),
        throwsA(anything),
      );
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'bad_amt2',
          projectId: 'p1',
          type: 'income',
          amount: -10,
          date: '2025-03-20',
          cashAccountId: const Value('c1'),
          clientId: const Value('client1'),
        )),
        throwsA(anything),
      );
    });

    test('invalid type rejected', () async {
      expect(
        db.customStatement(
          "INSERT INTO transactions (id, project_id, type, amount, date) VALUES ('bad_t', 'p1', 'bogus', 100, '2025-03-20')",
        ),
        throwsA(anything),
      );
    });

    test('FK enforced', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'bad_fk',
          projectId: 'no_such_project',
          type: 'income',
          amount: 100,
          date: '2025-03-20',
          cashAccountId: const Value('c1'),
          clientId: const Value('client1'),
        )),
        throwsA(anything),
      );
    });

    test('hard delete forbidden', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_del',
        projectId: 'p1',
        type: 'income',
        amount: 100,
        date: '2025-03-20',
        cashAccountId: const Value('c1'),
        clientId: const Value('client1'),
      ));
      expect(db.customStatement("DELETE FROM transactions WHERE id='tx_del'"), throwsA(anything));
    });

    test('soft delete needs reason', () async {
      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'bad_soft',
          projectId: 'p1',
          type: 'income',
          amount: 100,
          date: '2025-03-20',
          cashAccountId: const Value('c1'),
          clientId: const Value('client1'),
          deletedAt: const Value('2025-01-01T00:00:00Z'),
        )),
        throwsA(anything),
      );
    });
  });

  group('period lock', () {
    test('insert/update/soft-delete throw in locked project', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx_lock_test',
        projectId: 'p1',
        type: 'income',
        amount: 100,
        date: '2025-03-20',
        cashAccountId: const Value('c1'),
        clientId: const Value('client1'),
      ));

      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p1'");

      expect(
        db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx_lock_fail',
          projectId: 'p1',
          type: 'income',
          amount: 200,
          date: '2025-03-20',
          cashAccountId: const Value('c1'),
          clientId: const Value('client1'),
        )),
        throwsA(anything),
      );

      expect(
        db.customStatement("UPDATE transactions SET amount=500 WHERE id='tx_lock_test'"),
        throwsA(anything),
      );

      expect(
        db.customStatement(
            "UPDATE transactions SET deleted_at='x', deleted_reason='r' WHERE id='tx_lock_test'"),
        throwsA(anything),
      );

      await db.customStatement("UPDATE projects SET status='open' WHERE id='p1'");
      await db.customStatement("UPDATE transactions SET amount=500 WHERE id='tx_lock_test'");
      final updated = await (db.select(db.transactions)..where((t) => t.id.equals('tx_lock_test'))).getSingle();
      expect(updated.amount, 500);
    });
  });

  group('money', () {
    test('floorDiv integer division without double: negative, large, exact', () {
      expect(floorDiv(7, 3), 2);
      expect(floorDiv(-7, 3), -3);
      expect(floorDiv(7, -3), -3);
      expect(floorDiv(-7, -3), 2);
      expect(floorDiv(-6, 3), -2);
      expect(floorDiv(0, 5), 0);
      expect(floorDiv(-1000000000000000001, 3), -333333333333333334);
      expect(floorDiv(1000000000000000001, 3), 333333333333333333);
      expect(() => floorDiv(10, 0), throwsA(isA<UnsupportedError>()));
    });
    test('format/parse', () {
      expect(formatToman(1234567), '۱٬۲۳۴٬۵۶۷');
      expect(parseToman('۱٬۲۳۴٬۵۶۷'), 1234567);
      expect(parseToman('20,000,000'), 20000000);
      expect(() => parseToman('–'), throwsA(isA<Exception>()));
    });
    test('formatToman separator: default, custom, latin digits', () {
      expect(formatToman(1234567), '۱٬۲۳۴٬۵۶۷');
      expect(formatToman(1234567, separator: ','), '۱,۲۳۴,۵۶۷');
      expect(formatToman(1234567, separator: ',', persianDigits: false), '1,234,567');
      expect(formatToman(-1000, separator: ' '), '-۱ ۰۰۰');
      expect(formatToman(999), '۹۹۹');
    });
    test('sum of 10000 ints is exact', () {
      var s = 0;
      for (var i = 1; i <= 10000; i++) {
        s += i * 1000 + 7;
      }
      expect(s, 50005000000 + 70000);
    });
  });

  group('jalali', () {
    test('known pairs', () {
      expect(jalaliToIso(1404, 1, 1), '2025-03-21');
      expect(jalaliToIso(1403, 12, 30), '2025-03-20');
      expect(isoToJalali('2025-03-20'), '۱۴۰۳/۱۲/۳۰');
      expect(jalaliToIso(1403, 1, 1), '2024-03-20');
    });
    test('29 Esfand valid in non-leap year, 30 Esfand throws', () {
      expect(jalaliToIso(1404, 12, 29), '2026-03-20');
      expect(() => jalaliToIso(1404, 12, 30), throwsA(isA<Exception>()));
    });
    test('month ends and roundtrip', () {
      expect(jalaliToIso(1404, 6, 31), isNotEmpty);
      expect(() => jalaliToIso(1404, 7, 31), throwsA(isA<Exception>()));
      for (final (y, m, d) in [(1399, 12, 30), (1404, 1, 1), (1404, 6, 31), (1404, 12, 29)]) {
        final iso = jalaliToIso(y, m, d);
        expect(isoToJalali(iso),
            toFaDigits('$y/${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}'));
      }
    });
  });

  group('legacy v1 fixture', () {
    test('opening database with user_version=1 throws LegacyDatabaseException', () async {
      final dir = Directory.systemTemp.createTempSync('karkard_legacy_fixture_');
      final file = File('${dir.path}/legacy_v1.db');
      try {
        final rawDb = raw_sqlite.sqlite3.open(file.path);
        rawDb.execute('PRAGMA user_version = 1;');
        rawDb.close();

        final db = AppDatabase.forFile(file);
        expect(
          () async => await db.customSelect('SELECT 1').get(),
          throwsA(isA<LegacyDatabaseException>().having(
            (e) => e.fromVersion,
            'fromVersion',
            equals(1),
          )),
        );
        await db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
