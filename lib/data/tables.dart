import 'package:drift/drift.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

mixin Stamps on Table {
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();
}

class Persons extends Table with Stamps {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  // partner | client | driver | worker | other
  TextColumn get kind => text()();
  TextColumn get code => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_person_kind CHECK (kind IN ('partner','client','driver','worker','other'))",
      ];
}

class Projects extends Table with Stamps {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  // open | locked
  TextColumn get status => text().withDefault(const Constant('open'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_project_status CHECK (status IN ('open','locked'))",
      ];
}

class Categories extends Table with Stamps {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  // expense | general
  TextColumn get kind => text()();
  TextColumn get code => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_category_kind CHECK (kind IN ('expense','general'))",
      ];
}

class CashAccounts extends Table with Stamps {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  // project | personal
  TextColumn get kind => text()();
  TextColumn get code => text().nullable()();
  TextColumn get holderPersonId => text().nullable().references(Persons, #id)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_cash_account_kind CHECK (kind IN ('project','personal'))",
        "CONSTRAINT chk_cash_account_holder_required CHECK (kind != 'personal' OR holder_person_id IS NOT NULL)",
        "CONSTRAINT chk_cash_account_project_holder_null CHECK (kind != 'project' OR holder_person_id IS NULL)",
      ];
}

class ProjectSettings extends Table with Stamps {
  TextColumn get projectId => text().references(Projects, #id)();
  // accrual | cash | both
  TextColumn get reportBasis => text().withDefault(const Constant('both'))();
  // accrual | cash
  TextColumn get shareBasis => text().withDefault(const Constant('accrual'))();
  // fixed_percent | by_work
  TextColumn get shareMethod =>
      text().withDefault(const Constant('fixed_percent'))();

  @override
  Set<Column> get primaryKey => {projectId};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_ps_report_basis CHECK (report_basis IN ('accrual','cash','both'))",
        "CONSTRAINT chk_ps_share_basis CHECK (share_basis IN ('accrual','cash'))",
        "CONSTRAINT chk_ps_share_method CHECK (share_method IN ('fixed_percent','by_work'))",
        "CONSTRAINT chk_ps_by_work_requires_accrual CHECK (share_method != 'by_work' OR share_basis = 'accrual')",
      ];
}

class ProjectPersons extends Table with Stamps {
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get personId => text().references(Persons, #id)();
  // payout_only | profit_share | both
  TextColumn get settlementMode =>
      text().withDefault(const Constant('payout_only'))();
  /// Basis points (10000 = 100%) for profit_share or both
  IntColumn get shareBp => integer().nullable()();
  /// Priority order for remainder allocation
  IntColumn get shareOrder => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {projectId, personId};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_pp_settlement_mode CHECK (settlement_mode IN ('payout_only','profit_share','both'))",
        "CONSTRAINT chk_pp_share_bp CHECK (share_bp IS NULL OR (typeof(share_bp) = 'integer' AND share_bp >= 0 AND share_bp <= 10000))",
        "CONSTRAINT chk_pp_share_bp_required CHECK (settlement_mode = 'payout_only' OR (share_bp IS NOT NULL AND share_bp > 0))",
        "CONSTRAINT chk_pp_share_order_type CHECK (typeof(share_order) = 'integer')",
      ];
}

@TableIndex(name: 'idx_tx_project_date', columns: {#projectId, #date})
@TableIndex(name: 'idx_tx_person_type', columns: {#personId, #type})
@TableIndex(name: 'idx_tx_client_type', columns: {#clientId, #type})
class Transactions extends Table with Stamps {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  // work_in | work_out | income | expense | payout | transfer
  TextColumn get type => text()();
  /// Toman, integer, always > 0.
  IntColumn get amount => integer()();
  /// ISO Gregorian YYYY-MM-DD.
  TextColumn get date => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  BoolColumn get receiptNotRequired =>
      boolean().withDefault(const Constant(false))();
  TextColumn get importHash => text().nullable().unique()();
  TextColumn get deletedAt => text().nullable()();
  TextColumn get deletedReason => text().nullable()();

  // Version 3 columns
  TextColumn get clientId => text().nullable().references(Persons, #id)();
  TextColumn get personId => text().nullable().references(Persons, #id)();
  TextColumn get performedBy => text().nullable().references(Persons, #id)();
  TextColumn get attributedTo => text().nullable().references(Persons, #id)();
  TextColumn get cashAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get fromAccountId =>
      text().nullable().references(CashAccounts, #id)();
  TextColumn get toAccountId =>
      text().nullable().references(CashAccounts, #id)();
  // settle_payable | distribution
  TextColumn get purpose => text().nullable()();
  TextColumn get overrideReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CONSTRAINT chk_tx_type CHECK (type IN ('work_in','work_out','income','expense','payout','transfer'))",
        "CONSTRAINT chk_tx_amount_positive CHECK (amount > 0)",
        "CONSTRAINT chk_tx_amount_type CHECK (typeof(amount) = 'integer')",
        "CONSTRAINT chk_tx_date_format CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(date) IS date)",
        "CONSTRAINT chk_tx_deleted_reason CHECK ((deleted_at IS NULL) = (deleted_reason IS NULL))",
        "CONSTRAINT chk_tx_purpose CHECK (purpose IS NULL OR purpose IN ('settle_payable','distribution'))",

        // work_in: client_id required; cash_account, from/to account, person_id, purpose forbidden
        "CONSTRAINT chk_tx_work_in_client_required CHECK (type != 'work_in' OR client_id IS NOT NULL)",
        "CONSTRAINT chk_tx_work_in_forbidden_fields CHECK (type != 'work_in' OR (cash_account_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND purpose IS NULL))",

        // work_out: person_id required; client_id, cash_account, from/to account, performed_by, purpose forbidden
        "CONSTRAINT chk_tx_work_out_person_required CHECK (type != 'work_out' OR person_id IS NOT NULL)",
        "CONSTRAINT chk_tx_work_out_forbidden_fields CHECK (type != 'work_out' OR (client_id IS NULL AND cash_account_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND performed_by IS NULL AND purpose IS NULL))",

        // income: client_id and cash_account required; from/to account, person_id, performed_by, attributed_to, purpose forbidden
        "CONSTRAINT chk_tx_income_account_required CHECK (type != 'income' OR cash_account_id IS NOT NULL)",
        "CONSTRAINT chk_tx_income_client_required CHECK (type != 'income' OR client_id IS NOT NULL)",
        "CONSTRAINT chk_tx_income_forbidden_fields CHECK (type != 'income' OR (from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND purpose IS NULL))",

        // expense: cash_account required; client_id, from/to account, person_id, performed_by, purpose forbidden
        "CONSTRAINT chk_tx_expense_account_required CHECK (type != 'expense' OR cash_account_id IS NOT NULL)",
        "CONSTRAINT chk_tx_expense_forbidden_fields CHECK (type != 'expense' OR (client_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND purpose IS NULL))",

        // payout: person_id, cash_account, purpose required; client_id, performed_by, attributed_to, from/to account forbidden
        "CONSTRAINT chk_tx_payout_required_fields CHECK (type != 'payout' OR (person_id IS NOT NULL AND cash_account_id IS NOT NULL AND purpose IS NOT NULL))",
        "CONSTRAINT chk_tx_payout_forbidden_fields CHECK (type != 'payout' OR (client_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND from_account_id IS NULL AND to_account_id IS NULL))",

        // transfer: from_account and to_account required and !=; cash_account, client_id, person_id, performed_by, attributed_to, purpose, category forbidden
        "CONSTRAINT chk_tx_transfer_accounts_required CHECK (type != 'transfer' OR (from_account_id IS NOT NULL AND to_account_id IS NOT NULL AND from_account_id != to_account_id))",
        "CONSTRAINT chk_tx_transfer_forbidden_fields CHECK (type != 'transfer' OR (cash_account_id IS NULL AND client_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND purpose IS NULL AND category_id IS NULL))",

        // category_id only allowed for expense and payout
        "CONSTRAINT chk_tx_category_allowed_types CHECK (category_id IS NULL OR type IN ('expense','payout'))",
      ];
}

class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get filePath => text()();
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get hash => text().nullable()();
  TextColumn get mime => text()();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  @override
  Set<Column> get primaryKey => {id};
}

class AuditLog extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get reason => text().nullable()();
  TextColumn get at => text().clientDefault(nowIso)();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};

  @override
  List<String> get customConstraints => [
        'CONSTRAINT chk_app_settings_unit CHECK ("key" != \'unit\' OR value = \'toman\')',
      ];
}
