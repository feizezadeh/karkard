import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import '../core/domain_exception.dart';
import 'tables.dart';

part 'database.g.dart';

const schemaVersionV3 = 3;

final _triggerNameRegex = RegExp(r'CREATE TRIGGER\s+([a-zA-Z0-9_]+)');
List<String> get expectedTriggerNames => _triggers
    .map((s) => _triggerNameRegex.firstMatch(s)?.group(1))
    .whereType<String>()
    .toList();

@DriftDatabase(tables: [
  Persons,
  Projects,
  Categories,
  CashAccounts,
  ProjectSettings,
  ProjectPersons,
  Transactions,
  Receipts,
  AuditLog,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static Future<File> getDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'karkard', 'karkard.db'));
  }

  /// File-backed DB in the app documents dir: WAL + foreign keys ON.
  static Future<AppDatabase> openFile() async {
    final file = await getDatabaseFile();
    await file.parent.create(recursive: true);
    return forFile(file);
  }

  static AppDatabase forFile(File file) =>
      AppDatabase(NativeDatabase(file, setup: _pragmas));

  static void _pragmas(Database db) {
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
  }

  @override
  int get schemaVersion => schemaVersionV3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final s in _triggers) {
            await customStatement(s);
          }
          await into(appSettings).insert(AppSettingsCompanion.insert(
              key: 'schema_version', value: '$schemaVersionV3'));
          await into(appSettings).insert(AppSettingsCompanion.insert(
              key: 'unit', value: 'toman'));
        },
        onUpgrade: (m, from, to) async {
          if (from < 3) {
            throw LegacyDatabaseException(
              fromVersion: from,
              toVersion: to,
              message: 'Database version $from requires reset to version $to',
            );
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          final fk = await customSelect('PRAGMA foreign_keys').getSingle();
          if (fk.data.values.first != 1) {
            throw StateError('foreign_keys could not be enabled');
          }

          // In-place schema guard for receipts columns within schemaVersion = 3
          final receiptsInfo =
              await customSelect("PRAGMA table_info('receipts')").get();
          final existingCols =
              receiptsInfo.map((r) => r.data['name'] as String).toSet();
          if (existingCols.isNotEmpty) {
            if (!existingCols.contains('file_name')) {
              await customStatement(
                  'ALTER TABLE receipts ADD COLUMN file_name TEXT');
            }
            if (!existingCols.contains('file_size')) {
              await customStatement(
                  'ALTER TABLE receipts ADD COLUMN file_size INTEGER');
            }
            if (!existingCols.contains('hash')) {
              await customStatement(
                  'ALTER TABLE receipts ADD COLUMN hash TEXT');
            }
          }

          // In-place schema guard for code column in persons, cash_accounts, and categories
          final personsInfo =
              await customSelect("PRAGMA table_info('persons')").get();
          final existingPersonsCols =
              personsInfo.map((r) => r.data['name'] as String).toSet();
          if (existingPersonsCols.isNotEmpty && !existingPersonsCols.contains('code')) {
            await customStatement('ALTER TABLE persons ADD COLUMN code TEXT');
          }

          final cashAccountsInfo =
              await customSelect("PRAGMA table_info('cash_accounts')").get();
          final existingCashCols =
              cashAccountsInfo.map((r) => r.data['name'] as String).toSet();
          if (existingCashCols.isNotEmpty && !existingCashCols.contains('code')) {
            await customStatement('ALTER TABLE cash_accounts ADD COLUMN code TEXT');
          }

          final categoriesInfo =
              await customSelect("PRAGMA table_info('categories')").get();
          final existingCatCols =
              categoriesInfo.map((r) => r.data['name'] as String).toSet();
          if (existingCatCols.isNotEmpty && !existingCatCols.contains('code')) {
            await customStatement('ALTER TABLE categories ADD COLUMN code TEXT');
          }

          // Schema drift guard: verify that all expected triggers exist in sqlite_master
          final existingTriggers = await customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger'",
          ).get();
          final existingNames =
              existingTriggers.map((r) => r.data['name'] as String).toSet();
          for (final trg in expectedTriggerNames) {
            if (!existingNames.contains(trg)) {
              throw LegacyDatabaseException(
                fromVersion: details.versionBefore ?? 0,
                toVersion: schemaVersionV3,
                message: 'Schema drift detected: missing required trigger $trg',
              );
            }
          }
        },
      );
}

/// Business-rule guards enforced in the DB so no code path can bypass them.
const _triggers = <String>[
  // locked project: no insert
  '''
CREATE TRIGGER trg_tx_no_insert_locked BEFORE INSERT ON transactions
WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_TX: project is locked: cannot insert transaction'); END;''',

  // locked project: no update (soft delete is an update); also blocks moving
  // a tx out of a locked project
  '''
CREATE TRIGGER trg_tx_no_update_locked BEFORE UPDATE ON transactions
WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
  OR (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_TX: project is locked: cannot update transaction'); END;''',

  // no hard delete, ever
  '''
CREATE TRIGGER trg_tx_no_hard_delete BEFORE DELETE ON transactions
BEGIN SELECT RAISE(ABORT, 'hard delete of transactions is forbidden: use soft delete'); END;''',

  // transactions: undeleting a soft-deleted transaction is forbidden
  '''
CREATE TRIGGER trg_tx_no_undelete BEFORE UPDATE OF deleted_at ON transactions
WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL
BEGIN SELECT RAISE(ABORT, 'ERR_TX_UNDELETE_FORBIDDEN: undeleting a soft-deleted transaction is forbidden'); END;''',

  // audit_log append-only: no update
  '''
CREATE TRIGGER trg_audit_log_no_update BEFORE UPDATE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit_log is append-only: UPDATE is forbidden'); END;''',

  // audit_log append-only: no delete
  '''
CREATE TRIGGER trg_audit_log_no_delete BEFORE DELETE ON audit_log
BEGIN SELECT RAISE(ABORT, 'audit_log is append-only: DELETE is forbidden'); END;''',

  // receipts: no insert for transaction in locked project
  '''
CREATE TRIGGER trg_receipts_no_insert_locked BEFORE INSERT ON receipts
WHEN (
  SELECT p.status FROM projects p
  JOIN transactions t ON t.project_id = p.id
  WHERE t.id = NEW.transaction_id
) = 'locked'
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_RECEIPTS: cannot add receipt to a transaction in a locked project'); END;''',

  // receipts: no delete for transaction in locked project
  '''
CREATE TRIGGER trg_receipts_no_delete_locked BEFORE DELETE ON receipts
WHEN (
  SELECT p.status FROM projects p
  JOIN transactions t ON t.project_id = p.id
  WHERE t.id = OLD.transaction_id
) = 'locked'
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_RECEIPTS: cannot delete receipt from a transaction in a locked project'); END;''',

  // client_id on work_in and income must have kind = 'client'
  '''
CREATE TRIGGER trg_tx_check_client_kind_insert BEFORE INSERT ON transactions
WHEN (NEW.type IN ('work_in', 'income')) AND (SELECT kind FROM persons WHERE id = NEW.client_id) != 'client'
BEGIN SELECT RAISE(ABORT, 'ERR_CLIENT_KIND_MISMATCH: client_id must have kind=client'); END;''',

  '''
CREATE TRIGGER trg_tx_check_client_kind_update BEFORE UPDATE OF client_id, type ON transactions
WHEN (NEW.type IN ('work_in', 'income')) AND (SELECT kind FROM persons WHERE id = NEW.client_id) != 'client'
BEGIN SELECT RAISE(ABORT, 'ERR_CLIENT_KIND_MISMATCH: client_id must have kind=client'); END;''',

  // payout.person_id must be registered in project_persons
  '''
CREATE TRIGGER trg_tx_check_payout_person_in_project_persons_insert BEFORE INSERT ON transactions
WHEN NEW.type = 'payout' AND NOT EXISTS (
  SELECT 1 FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id
)
BEGIN SELECT RAISE(ABORT, 'ERR_PAYOUT_PERSON_NOT_IN_PROJECT: person is not registered in project_persons'); END;''',

  '''
CREATE TRIGGER trg_tx_check_payout_person_in_project_persons_update BEFORE UPDATE OF person_id, project_id, type ON transactions
WHEN NEW.type = 'payout' AND NOT EXISTS (
  SELECT 1 FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id
)
BEGIN SELECT RAISE(ABORT, 'ERR_PAYOUT_PERSON_NOT_IN_PROJECT: person is not registered in project_persons'); END;''',

  // work_out.person_id must be registered in project_persons and mode in ('payout_only', 'both')
  '''
CREATE TRIGGER trg_tx_check_work_out_person_insert BEFORE INSERT ON transactions
WHEN NEW.type = 'work_out' AND (
  COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('payout_only', 'both')
)
BEGIN SELECT RAISE(ABORT, 'ERR_WORK_OUT_PERSON_NOT_IN_PROJECT: work_out person must be registered in project_persons with payout_only or both'); END;''',

  '''
CREATE TRIGGER trg_tx_check_work_out_person_update BEFORE UPDATE OF person_id, project_id, type ON transactions
WHEN NEW.type = 'work_out' AND (
  COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('payout_only', 'both')
)
BEGIN SELECT RAISE(ABORT, 'ERR_WORK_OUT_PERSON_NOT_IN_PROJECT: work_out person must be registered in project_persons with payout_only or both'); END;''',

  // payout with distribution: only allowed for participating partner (profit_share or both)
  '''
CREATE TRIGGER trg_tx_check_distribution_mode_insert BEFORE INSERT ON transactions
WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
  COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('profit_share', 'both')
)
BEGIN SELECT RAISE(ABORT, 'ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON: person is not a participating partner in project_persons'); END;''',

  '''
CREATE TRIGGER trg_tx_check_distribution_mode_update BEFORE UPDATE OF purpose, person_id, project_id, type ON transactions
WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
  COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('profit_share', 'both')
)
BEGIN SELECT RAISE(ABORT, 'ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON: person is not a participating partner in project_persons'); END;''',

  // payout with distribution: sum of share_bp for active participating partners in project must equal 10000
  '''
CREATE TRIGGER trg_tx_check_distribution_share_bp_insert BEFORE INSERT ON transactions
WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
  COALESCE((
    SELECT SUM(share_bp) FROM project_persons
    WHERE project_id = NEW.project_id AND settlement_mode IN ('profit_share', 'both')
  ), 0) != 10000
)
BEGIN SELECT RAISE(ABORT, 'ERR_SHARE_BP_SUM_NOT_10000: sum of share_bp for participating partners in project must be 10000'); END;''',

  '''
CREATE TRIGGER trg_tx_check_distribution_share_bp_update BEFORE UPDATE OF purpose, project_id, type ON transactions
WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
  COALESCE((
    SELECT SUM(share_bp) FROM project_persons
    WHERE project_id = NEW.project_id AND settlement_mode IN ('profit_share', 'both')
  ), 0) != 10000
)
BEGIN SELECT RAISE(ABORT, 'ERR_SHARE_BP_SUM_NOT_10000: sum of share_bp for participating partners in project must be 10000'); END;''',

  // performed_by / attributed_to: must be participating partner (profit_share or both) - NULL-safe
  '''
CREATE TRIGGER trg_tx_check_partner_participating_insert BEFORE INSERT ON transactions
WHEN (
  (NEW.performed_by IS NOT NULL AND COALESCE((
    SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.performed_by
  ), '') NOT IN ('profit_share', 'both'))
  OR
  (NEW.attributed_to IS NOT NULL AND COALESCE((
    SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.attributed_to
  ), '') NOT IN ('profit_share', 'both'))
)
BEGIN SELECT RAISE(ABORT, 'ERR_PARTNER_NOT_PARTICIPATING: performed_by and attributed_to must be a participating partner in project_persons'); END;''',

  '''
CREATE TRIGGER trg_tx_check_partner_participating_update BEFORE UPDATE OF performed_by, attributed_to, project_id ON transactions
WHEN (
  (NEW.performed_by IS NOT NULL AND COALESCE((
    SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.performed_by
  ), '') NOT IN ('profit_share', 'both'))
  OR
  (NEW.attributed_to IS NOT NULL AND COALESCE((
    SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.attributed_to
  ), '') NOT IN ('profit_share', 'both'))
)
BEGIN SELECT RAISE(ABORT, 'ERR_PARTNER_NOT_PARTICIPATING: performed_by and attributed_to must be a participating partner in project_persons'); END;''',

  // project_settings: locked after first distribution or project lock (insert, update, delete)
  '''
CREATE TRIGGER trg_project_settings_lock_insert BEFORE INSERT ON project_settings
WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = NEW.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_SETTINGS_LOCKED: project_settings cannot be inserted after first distribution or project lock'); END;''',

  '''
CREATE TRIGGER trg_project_settings_lock_update BEFORE UPDATE ON project_settings
WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_SETTINGS_LOCKED: project_settings is locked after first distribution or project lock'); END;''',

  '''
CREATE TRIGGER trg_project_settings_lock_delete BEFORE DELETE ON project_settings
WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_SETTINGS_LOCKED: project_settings is locked after first distribution or project lock'); END;''',

  // project_persons: locked after first distribution or project lock (insert, update, delete)
  '''
CREATE TRIGGER trg_project_persons_lock_insert BEFORE INSERT ON project_persons
WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = NEW.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_PERSONS_LOCKED: project_persons cannot be inserted after first distribution or project lock'); END;''',

  '''
CREATE TRIGGER trg_project_persons_lock_update BEFORE UPDATE ON project_persons
WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_PERSONS_LOCKED: project_persons is locked after first distribution or project lock'); END;''',

  '''
CREATE TRIGGER trg_project_persons_lock_delete BEFORE DELETE ON project_persons
WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
  OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_PERSONS_LOCKED: project_persons is locked after first distribution or project lock'); END;''',

  // cannot demote settlement_mode to payout_only if transactions reference this partner
  '''
CREATE TRIGGER trg_project_persons_no_demote_with_tx BEFORE UPDATE OF settlement_mode ON project_persons
WHEN NEW.settlement_mode = 'payout_only' AND EXISTS (
  SELECT 1 FROM transactions
  WHERE project_id = OLD.project_id
    AND (performed_by = OLD.person_id OR attributed_to = OLD.person_id)
    AND deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_DEMOTE_PARTNER_WITH_TRANSACTIONS: cannot change settlement_mode to payout_only when transactions reference this partner'); END;''',

  // cannot demote settlement_mode to profit_share if active work_out or payout(settle_payable) reference this person
  '''
CREATE TRIGGER trg_project_persons_no_demote_payout_with_tx BEFORE UPDATE OF settlement_mode ON project_persons
WHEN NEW.settlement_mode = 'profit_share' AND OLD.settlement_mode IN ('payout_only', 'both') AND EXISTS (
  SELECT 1 FROM transactions
  WHERE project_id = OLD.project_id
    AND person_id = OLD.person_id
    AND (type = 'work_out' OR (type = 'payout' AND purpose = 'settle_payable'))
    AND deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_DEMOTE_PAYOUT_PARTNER_WITH_TX: cannot change settlement_mode to profit_share when active work_out or settle_payable payout transactions reference this person'); END;''',

  // cannot update primary key (project_id or person_id) of project_persons if active transactions reference this person
  '''
CREATE TRIGGER trg_project_persons_no_update_pk_with_tx BEFORE UPDATE OF project_id, person_id ON project_persons
WHEN (OLD.project_id != NEW.project_id OR OLD.person_id != NEW.person_id) AND EXISTS (
  SELECT 1 FROM transactions
  WHERE project_id = OLD.project_id
    AND (person_id = OLD.person_id OR performed_by = OLD.person_id OR attributed_to = OLD.person_id)
    AND deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_UPDATE_PROJECT_PERSON_PK_WITH_TX: cannot change project_id or person_id of project_person when active transactions reference this person'); END;''',

  // cannot update kind of person if active transactions reference this person
  '''
CREATE TRIGGER trg_persons_no_update_kind_with_tx BEFORE UPDATE OF kind ON persons
WHEN OLD.kind != NEW.kind AND EXISTS (
  SELECT 1 FROM transactions
  WHERE (client_id = OLD.id OR person_id = OLD.id OR performed_by = OLD.id OR attributed_to = OLD.id)
    AND deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_CHANGE_PERSON_KIND_WITH_TX: cannot change kind of person referenced by active transactions'); END;''',

  // project_persons: profit_share/both only for partner; non-partner must be payout_only; client cannot be in project_persons
  '''
CREATE TRIGGER trg_pp_check_person_kind_settlement_mode_insert BEFORE INSERT ON project_persons
WHEN (
  (NEW.settlement_mode IN ('profit_share', 'both') AND (SELECT kind FROM persons WHERE id = NEW.person_id) != 'partner')
  OR
  (SELECT kind FROM persons WHERE id = NEW.person_id) = 'client'
)
BEGIN SELECT RAISE(ABORT, 'ERR_PERSON_KIND_SETTLEMENT_MODE_MISMATCH: profit_share/both is only permitted for partner, and client cannot be in project_persons'); END;''',

  '''
CREATE TRIGGER trg_pp_check_person_kind_settlement_mode_update BEFORE UPDATE OF settlement_mode, person_id ON project_persons
WHEN (
  (NEW.settlement_mode IN ('profit_share', 'both') AND (SELECT kind FROM persons WHERE id = NEW.person_id) != 'partner')
  OR
  (SELECT kind FROM persons WHERE id = NEW.person_id) = 'client'
)
BEGIN SELECT RAISE(ABORT, 'ERR_PERSON_KIND_SETTLEMENT_MODE_MISMATCH: profit_share/both is only permitted for partner, and client cannot be in project_persons'); END;''',

  // persons: cannot update kind to non-partner if partner has profit_share/both in project_persons; cannot update to client if in project_persons
  '''
CREATE TRIGGER trg_persons_check_kind_with_project_persons_update BEFORE UPDATE OF kind ON persons
WHEN OLD.kind != NEW.kind AND (
  (NEW.kind != 'partner' AND EXISTS (
    SELECT 1 FROM project_persons WHERE person_id = OLD.id AND settlement_mode IN ('profit_share', 'both')
  ))
  OR
  (NEW.kind = 'client' AND EXISTS (
    SELECT 1 FROM project_persons WHERE person_id = OLD.id
  ))
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_CHANGE_PERSON_KIND_IN_PROJECT: cannot change person kind: person has project_persons membership incompatible with new kind'); END;''',

  // cannot delete person from project_persons if active transactions reference this person
  '''
CREATE TRIGGER trg_project_persons_no_delete_with_tx BEFORE DELETE ON project_persons
WHEN EXISTS (
  SELECT 1 FROM transactions
  WHERE project_id = OLD.project_id
    AND (person_id = OLD.person_id OR performed_by = OLD.person_id OR attributed_to = OLD.person_id)
    AND deleted_at IS NULL
)
BEGIN SELECT RAISE(ABORT, 'ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS: cannot delete person from project_persons while active transactions reference this person'); END;''',

  // app_settings: key is immutable
  '''
CREATE TRIGGER trg_app_settings_no_update_key BEFORE UPDATE OF key ON app_settings
BEGIN SELECT RAISE(ABORT, 'ERR_APP_SETTINGS_KEY_IMMUTABLE: app_settings key cannot be updated'); END;''',

  // app_settings: unit is immutable (update, delete, or replace forbidden)
  '''
CREATE TRIGGER trg_app_settings_unit_immutable BEFORE UPDATE OF value ON app_settings
WHEN OLD.key = 'unit'
BEGIN SELECT RAISE(ABORT, 'ERR_UNIT_IMMUTABLE: unit is immutable'); END;''',

  '''
CREATE TRIGGER trg_app_settings_unit_no_delete BEFORE DELETE ON app_settings
WHEN OLD.key = 'unit'
BEGIN SELECT RAISE(ABORT, 'ERR_UNIT_IMMUTABLE: unit is immutable: DELETE is forbidden'); END;''',

  '''
CREATE TRIGGER trg_app_settings_unit_no_insert_replace BEFORE INSERT ON app_settings
WHEN NEW.key = 'unit' AND EXISTS (SELECT 1 FROM app_settings WHERE key = 'unit')
BEGIN SELECT RAISE(ABORT, 'ERR_UNIT_IMMUTABLE: unit is immutable: REPLACE is forbidden'); END;''',
];
