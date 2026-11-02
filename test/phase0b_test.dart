import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/jalali.dart';
import 'package:karkard/core/money.dart';
import 'package:karkard/data/database.dart';

Future<String> pragma(AppDatabase db, String name) async {
  final rows = await db.customSelect('PRAGMA $name').get();
  return rows.first.data.values.first.toString().toLowerCase();
}

Future<void> seed(AppDatabase db) async {
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'cli', name: 'کارفرما', kind: 'client'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'partner1', name: 'امیر', kind: 'partner'));
  await db.into(db.persons).insert(PersonsCompanion.insert(id: 'driver', name: 'راننده', kind: 'driver'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c1', name: 'صندوق', kind: 'project'));
  await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(id: 'c2', name: 'بانک', kind: 'project'));
  await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'open1', name: 'پروژه باز'));
  await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'lock1', name: 'قفل'));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'open1',
    personId: 'partner1',
    settlementMode: const Value('profit_share'),
    shareBp: const Value(10000),
  ));
  await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
    projectId: 'lock1',
    personId: 'partner1',
    settlementMode: const Value('profit_share'),
    shareBp: const Value(10000),
  ));
  await db.customStatement("UPDATE projects SET status='locked' WHERE id='lock1'");
}

Future<void> tx(
  AppDatabase db,
  String id,
  String project, {
  String date = '2025-03-20',
  String type = 'income',
  int amount = 100,
  String? cashAccountId = 'c1',
  String? clientId,
  String? personId,
  String? purpose,
}) =>
    db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          projectId: project,
          type: type,
          amount: amount,
          date: date,
          cashAccountId: Value(cashAccountId),
          clientId: Value(clientId),
          personId: Value(personId),
          purpose: Value(purpose),
        ));

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('karkard_test_');
    file = File('${dir.path}/k.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('file db', () {
    test('file db: journal_mode=wal, foreign_keys=1, persist across reopen', () async {
      var db = AppDatabase.forFile(file);
      expect(await pragma(db, 'journal_mode'), 'wal');
      expect(await pragma(db, 'foreign_keys'), '1');
      await seed(db);
      await tx(db, 't1', 'open1');
      await db.close();

      db = AppDatabase.forFile(file);
      expect(await pragma(db, 'journal_mode'), 'wal');
      expect(await pragma(db, 'foreign_keys'), '1');
      final rows = await db.select(db.transactions).get();
      expect(rows.map((r) => r.id), ['t1']);
      expect((await db.select(db.persons).get()).length, 3);
      await db.close();
    });

    test('openFile uses forFile and PRAGMA foreign_keys=ON is verified immediately on fresh connection', () async {
      final db = AppDatabase.forFile(file);
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.data.values.first, 1);
      await db.close();
    });

    test('file db: DDL dump (CHECKs + triggers + indexes present)', () async {
      final db = AppDatabase.forFile(file);
      await seed(db);
      final rows = await db.customSelect(
        'SELECT type, name, sql FROM sqlite_master ORDER BY type, name',
      ).get();

      final all = <String>[];
      for (final r in rows) {
        final t = r.read<String>('type');
        final n = r.read<String>('name');
        final s = r.readNullable<String>('sql');
        all.add('$t | $n');
        // ignore: avoid_print
        print('Shell: --- $t | $n\nShell: ${s?.replaceAll('\n', '\nShell: ')}\nShell: ');
      }

      // Assert that obsolete legacy structures are NOT present
      for (final obsolete in [
        'trg_tx_validate_related_insert',
        'trg_tx_validate_related_update',
        'payer_id',
        'reimbursable',
      ]) {
        expect(all.join(' '), isNot(contains(obsolete)));
      }

      // Assert indexes
      expect(all, contains('index | idx_tx_project_date'));
      expect(all, contains('index | idx_tx_person_type'));
      expect(all, contains('index | idx_tx_client_type'));

      // Assert new tables
      expect(all, contains('table | cash_accounts'));
      expect(all, contains('table | project_settings'));
      expect(all, contains('table | project_persons'));

      // Assert triggers
      for (final trg in [
        'trg_tx_no_hard_delete',
        'trg_tx_no_undelete',
        'trg_tx_no_insert_locked',
        'trg_tx_no_update_locked',
        'trg_audit_log_no_update',
        'trg_audit_log_no_delete',
        'trg_receipts_no_insert_locked',
        'trg_receipts_no_delete_locked',
        'trg_tx_check_client_kind_insert',
        'trg_tx_check_client_kind_update',
        'trg_tx_check_payout_person_in_project_persons_insert',
        'trg_tx_check_payout_person_in_project_persons_update',
        'trg_tx_check_work_out_person_insert',
        'trg_tx_check_work_out_person_update',
        'trg_tx_check_distribution_mode_insert',
        'trg_tx_check_distribution_mode_update',
        'trg_tx_check_distribution_share_bp_insert',
        'trg_tx_check_distribution_share_bp_update',
        'trg_tx_check_partner_participating_insert',
        'trg_tx_check_partner_participating_update',
        'trg_project_settings_lock_insert',
        'trg_project_settings_lock_update',
        'trg_project_settings_lock_delete',
        'trg_project_persons_lock_insert',
        'trg_project_persons_lock_update',
        'trg_project_persons_lock_delete',
        'trg_project_persons_no_demote_with_tx',
        'trg_project_persons_no_delete_with_tx',
        'trg_app_settings_no_update_key',
        'trg_app_settings_unit_immutable',
        'trg_app_settings_unit_no_delete',
        'trg_app_settings_unit_no_insert_replace',
      ]) {
        expect(all, contains('trigger | $trg'));
      }
      await db.close();
    });
  });

  group('typeof(amount) CHECK', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forFile(file);
      await seed(db);
    });
    tearDown(() => db.close());

    test('amount: 100 accepted, 12.5 rejected, string literal 100 rejected', () async {
      await tx(db, 't_int', 'open1', amount: 100);
      final row = await (db.select(db.transactions)..where((t) => t.id.equals('t_int'))).getSingle();
      expect(row.amount, 100);

      // Raw SQL check with real float 12.5 -> must fail CHECK (typeof(amount)='integer')
      expect(
        db.customStatement(
          "INSERT INTO transactions (id, project_id, type, amount, date, cash_account_id) VALUES ('t_flt', 'open1', 'income', 12.5, '2025-03-20', 'c1')",
        ),
        throwsA(anything),
      );

      // Raw SQL check with text '100' -> must fail CHECK (typeof(amount)='integer')
      expect(
        db.customStatement(
          "INSERT INTO transactions (id, project_id, type, amount, date, cash_account_id) VALUES ('t_str', 'open1', 'income', '100', '2025-03-20', 'c1')",
        ),
        throwsA(anything),
      );
    });
  });

  group('audit_log append-only triggers', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forFile(file);
      await seed(db);
    });
    tearDown(() => db.close());

    test('audit_log: insert succeeds, update throws, delete throws', () async {
      await db.into(db.auditLog).insert(AuditLogCompanion.insert(
          id: 'l1', entityType: 'tx', entityId: 't1', action: 'create'));
      expect((await db.select(db.auditLog).get()).length, 1);

      expect(
        db.customStatement("UPDATE audit_log SET action='tampered' WHERE id='l1'"),
        throwsA(anything),
      );

      expect(
        db.customStatement("DELETE FROM audit_log WHERE id='l1'"),
        throwsA(anything),
      );
    });
  });

  group('receipts locked project triggers', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forFile(file);
      await seed(db);
      await tx(db, 'tx_open', 'open1');
    });
    tearDown(() => db.close());

    test('receipts: adding or deleting receipt for transaction in locked project throws', () async {
      // Add receipt in open project -> succeeds
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          id: 'r1', transactionId: 'tx_open', filePath: '/path/1.png', mime: 'image/png'));
      expect((await db.select(db.receipts).get()).length, 1);

      // Lock project
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='open1'");

      // Adding new receipt now throws
      expect(
        db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r2', transactionId: 'tx_open', filePath: '/path/2.png', mime: 'image/png')),
        throwsA(anything),
      );

      // Deleting existing receipt now throws
      expect(
        db.customStatement("DELETE FROM receipts WHERE id='r1'"),
        throwsA(anything),
      );

      // Unlock project -> delete succeeds
      await db.customStatement("UPDATE projects SET status='open' WHERE id='open1'");
      await db.customStatement("DELETE FROM receipts WHERE id='r1'");
      expect((await db.select(db.receipts).get()).length, 0);
    });
  });

  group('lock trigger', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forFile(file);
      await seed(db);
    });
    tearDown(() => db.close());

    test('lock a) moving tx from open to locked project throws', () async {
      await tx(db, 't1', 'open1');
      expect(db.customStatement("UPDATE transactions SET project_id='lock1' WHERE id='t1'"),
          throwsA(anything));
    });
    test('lock b) unlocking project succeeds, then tx edit succeeds', () async {
      await tx(db, 't1', 'open1');
      await db.customStatement("UPDATE projects SET status='open' WHERE id='lock1'");
      await tx(db, 't2', 'lock1');
      await db.customStatement("UPDATE transactions SET amount=7 WHERE id='t2'");
      final r = await (db.select(db.transactions)..where((t) => t.id.equals('t2'))).getSingle();
      expect(r.amount, 7);
    });
    test('lock d) insert tx in locked project throws', () async {
      expect(tx(db, 't9', 'lock1'), throwsA(anything));
    });
  });

  group('date CHECK', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forFile(file);
      await seed(db);
    });
    tearDown(() => db.close());

    test('date: 2026-13-45 rejected', () async {
      expect(tx(db, 'x', 'open1', date: '2026-13-45'), throwsA(anything));
    });
    test('date: 2026-02-30 rejected', () async {
      expect(tx(db, 'x', 'open1', date: '2026-02-30'), throwsA(anything));
    });
    test('date: valid 2024-02-29 accepted, 2025-02-29 rejected', () async {
      await tx(db, 'ok', 'open1', date: '2024-02-29');
      expect(tx(db, 'x', 'open1', date: '2025-02-29'), throwsA(anything));
    });
  });

  group('jalali extra', () {
    test('jalali: 30 Esfand 1403 (leap) valid', () {
      expect(jalaliToIso(1403, 12, 30), '2025-03-20');
    });
    test('jalali: 30 Esfand 1404 (non-leap) rejected', () {
      expect(() => jalaliToIso(1404, 12, 30), throwsA(isA<Exception>()));
    });
    test('jalali: roundtrip jalali->iso->jalali (year edge, 1 Farvardin, 31 Shahrivar)', () {
      for (final (y, m, d) in [
        (1403, 12, 30), (1404, 1, 1), (1403, 1, 1), (1404, 6, 31),
        (1403, 6, 31), (1403, 12, 29), (1399, 12, 30),
      ]) {
        final back = isoToJalali(jalaliToIso(y, m, d));
        expect(back, toFaDigits('$y/${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}'));
      }
    });
    test('jalali: 31 Shahrivar edge gregorian values', () {
      expect(jalaliToIso(1404, 6, 31), '2025-09-22');
      expect(jalaliToIso(1404, 7, 1), '2025-09-23');
    });
  });
}
