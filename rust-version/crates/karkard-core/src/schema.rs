use rusqlite::Connection;
use crate::error::Result;

pub const SCHEMA_VERSION: i32 = 3;

pub const DDL_TABLES: &str = r#"
CREATE TABLE IF NOT EXISTS persons (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(name) >= 1 AND length(name) <= 200),
    kind TEXT NOT NULL,
    code TEXT,
    note TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_person_kind CHECK (kind IN ('partner','client','driver','worker','other'))
);

CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(name) >= 1 AND length(name) <= 200),
    start_date TEXT,
    end_date TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_project_status CHECK (status IN ('open','locked'))
);

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(name) >= 1 AND length(name) <= 200),
    kind TEXT NOT NULL,
    code TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_category_kind CHECK (kind IN ('expense','general'))
);

CREATE TABLE IF NOT EXISTS cash_accounts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(name) >= 1 AND length(name) <= 200),
    kind TEXT NOT NULL,
    code TEXT,
    holder_person_id TEXT REFERENCES persons(id),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_cash_account_kind CHECK (kind IN ('project','personal')),
    CONSTRAINT chk_cash_account_holder_required CHECK (kind != 'personal' OR holder_person_id IS NOT NULL),
    CONSTRAINT chk_cash_account_project_holder_null CHECK (kind != 'project' OR holder_person_id IS NULL)
);

CREATE TABLE IF NOT EXISTS project_settings (
    project_id TEXT PRIMARY KEY REFERENCES projects(id),
    report_basis TEXT NOT NULL DEFAULT 'both',
    share_basis TEXT NOT NULL DEFAULT 'accrual',
    share_method TEXT NOT NULL DEFAULT 'fixed_percent',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_ps_report_basis CHECK (report_basis IN ('accrual','cash','both')),
    CONSTRAINT chk_ps_share_basis CHECK (share_basis IN ('accrual','cash')),
    CONSTRAINT chk_ps_share_method CHECK (share_method IN ('fixed_percent','by_work')),
    CONSTRAINT chk_ps_by_work_requires_accrual CHECK (share_method != 'by_work' OR share_basis = 'accrual')
);

CREATE TABLE IF NOT EXISTS project_persons (
    project_id TEXT NOT NULL REFERENCES projects(id),
    person_id TEXT NOT NULL REFERENCES persons(id),
    settlement_mode TEXT NOT NULL DEFAULT 'payout_only',
    share_bp INTEGER,
    share_order INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    PRIMARY KEY (project_id, person_id),
    CONSTRAINT chk_pp_settlement_mode CHECK (settlement_mode IN ('payout_only','profit_share','both')),
    CONSTRAINT chk_pp_share_bp CHECK (share_bp IS NULL OR (typeof(share_bp) = 'integer' AND share_bp >= 0 AND share_bp <= 10000)),
    CONSTRAINT chk_pp_share_bp_required CHECK (settlement_mode = 'payout_only' OR (share_bp IS NOT NULL AND share_bp > 0)),
    CONSTRAINT chk_pp_share_order_type CHECK (typeof(share_order) = 'integer')
);

CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    type TEXT NOT NULL,
    amount INTEGER NOT NULL,
    date TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category_id TEXT REFERENCES categories(id),
    receipt_not_required INTEGER NOT NULL DEFAULT 0,
    import_hash TEXT UNIQUE,
    deleted_at TEXT,
    deleted_reason TEXT,
    client_id TEXT REFERENCES persons(id),
    person_id TEXT REFERENCES persons(id),
    performed_by TEXT REFERENCES persons(id),
    attributed_to TEXT REFERENCES persons(id),
    cash_account_id TEXT REFERENCES cash_accounts(id),
    from_account_id TEXT REFERENCES cash_accounts(id),
    to_account_id TEXT REFERENCES cash_accounts(id),
    purpose TEXT,
    override_reason TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    CONSTRAINT chk_tx_type CHECK (type IN ('work_in','work_out','income','expense','payout','transfer')),
    CONSTRAINT chk_tx_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_tx_amount_type CHECK (typeof(amount) = 'integer'),
    CONSTRAINT chk_tx_date_format CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(date) IS date),
    CONSTRAINT chk_tx_deleted_reason CHECK ((deleted_at IS NULL) = (deleted_reason IS NULL)),
    CONSTRAINT chk_tx_purpose CHECK (purpose IS NULL OR purpose IN ('settle_payable','distribution')),
    CONSTRAINT chk_tx_work_in_client_required CHECK (type != 'work_in' OR client_id IS NOT NULL),
    CONSTRAINT chk_tx_work_in_forbidden_fields CHECK (type != 'work_in' OR (cash_account_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND purpose IS NULL)),
    CONSTRAINT chk_tx_work_out_person_required CHECK (type != 'work_out' OR person_id IS NOT NULL),
    CONSTRAINT chk_tx_work_out_forbidden_fields CHECK (type != 'work_out' OR (client_id IS NULL AND cash_account_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND performed_by IS NULL AND purpose IS NULL)),
    CONSTRAINT chk_tx_income_account_required CHECK (type != 'income' OR cash_account_id IS NOT NULL),
    CONSTRAINT chk_tx_income_client_required CHECK (type != 'income' OR client_id IS NOT NULL),
    CONSTRAINT chk_tx_income_forbidden_fields CHECK (type != 'income' OR (from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND purpose IS NULL)),
    CONSTRAINT chk_tx_expense_account_required CHECK (type != 'expense' OR cash_account_id IS NOT NULL),
    CONSTRAINT chk_tx_expense_forbidden_fields CHECK (type != 'expense' OR (client_id IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND purpose IS NULL)),
    CONSTRAINT chk_tx_payout_required_fields CHECK (type != 'payout' OR (person_id IS NOT NULL AND cash_account_id IS NOT NULL AND purpose IS NOT NULL)),
    CONSTRAINT chk_tx_payout_forbidden_fields CHECK (type != 'payout' OR (client_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND from_account_id IS NULL AND to_account_id IS NULL)),
    CONSTRAINT chk_tx_transfer_accounts_required CHECK (type != 'transfer' OR (from_account_id IS NOT NULL AND to_account_id IS NOT NULL AND from_account_id != to_account_id)),
    CONSTRAINT chk_tx_transfer_forbidden_fields CHECK (type != 'transfer' OR (cash_account_id IS NULL AND client_id IS NULL AND person_id IS NULL AND performed_by IS NULL AND attributed_to IS NULL AND purpose IS NULL AND category_id IS NULL)),
    CONSTRAINT chk_tx_category_allowed_types CHECK (category_id IS NULL OR type IN ('expense','payout'))
);

CREATE INDEX IF NOT EXISTS idx_tx_project_date ON transactions (project_id, date);
CREATE INDEX IF NOT EXISTS idx_tx_person_type ON transactions (person_id, type);
CREATE INDEX IF NOT EXISTS idx_tx_client_type ON transactions (client_id, type);

CREATE TABLE IF NOT EXISTS receipts (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    file_path TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    hash TEXT,
    mime TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS audit_log (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    before_json TEXT,
    after_json TEXT,
    reason TEXT,
    at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    CONSTRAINT chk_app_settings_unit CHECK (key != 'unit' OR value = 'toman')
);
"#;

pub const DDL_TRIGGERS: &[&str] = &[
    // locked project: no insert
    "CREATE TRIGGER IF NOT EXISTS trg_tx_no_insert_locked BEFORE INSERT ON transactions
    WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_TX: project is locked: cannot insert transaction'); END;",

    // locked project: no update
    "CREATE TRIGGER IF NOT EXISTS trg_tx_no_update_locked BEFORE UPDATE ON transactions
    WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
      OR (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_TX: project is locked: cannot update transaction'); END;",

    // no hard delete
    "CREATE TRIGGER IF NOT EXISTS trg_tx_no_hard_delete BEFORE DELETE ON transactions
    BEGIN SELECT RAISE(ABORT, 'hard delete of transactions is forbidden: use soft delete'); END;",

    // transactions: undeleting forbidden
    "CREATE TRIGGER IF NOT EXISTS trg_tx_no_undelete BEFORE UPDATE OF deleted_at ON transactions
    WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL
    BEGIN SELECT RAISE(ABORT, 'ERR_TX_UNDELETE_FORBIDDEN: undeleting a soft-deleted transaction is forbidden'); END;",

    // audit_log append-only
    "CREATE TRIGGER IF NOT EXISTS trg_audit_log_no_update BEFORE UPDATE ON audit_log
    BEGIN SELECT RAISE(ABORT, 'audit_log is append-only: UPDATE is forbidden'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_audit_log_no_delete BEFORE DELETE ON audit_log
    BEGIN SELECT RAISE(ABORT, 'audit_log is append-only: DELETE is forbidden'); END;",

    // receipts locked project
    "CREATE TRIGGER IF NOT EXISTS trg_receipts_no_insert_locked BEFORE INSERT ON receipts
    WHEN (
      SELECT p.status FROM projects p
      JOIN transactions t ON t.project_id = p.id
      WHERE t.id = NEW.transaction_id
    ) = 'locked'
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_RECEIPTS: cannot add receipt to a transaction in a locked project'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_receipts_no_delete_locked BEFORE DELETE ON receipts
    WHEN (
      SELECT p.status FROM projects p
      JOIN transactions t ON t.project_id = p.id
      WHERE t.id = OLD.transaction_id
    ) = 'locked'
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_LOCKED_RECEIPTS: cannot delete receipt from a transaction in a locked project'); END;",

    // client_id on work_in and income must have kind = 'client'
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_client_kind_insert BEFORE INSERT ON transactions
    WHEN (NEW.type IN ('work_in', 'income')) AND (SELECT kind FROM persons WHERE id = NEW.client_id) != 'client'
    BEGIN SELECT RAISE(ABORT, 'ERR_CLIENT_KIND_MISMATCH: client_id must have kind=client'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_client_kind_update BEFORE UPDATE OF client_id, type ON transactions
    WHEN (NEW.type IN ('work_in', 'income')) AND (SELECT kind FROM persons WHERE id = NEW.client_id) != 'client'
    BEGIN SELECT RAISE(ABORT, 'ERR_CLIENT_KIND_MISMATCH: client_id must have kind=client'); END;",

    // payout.person_id must be in project_persons
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_payout_person_in_project_persons_insert BEFORE INSERT ON transactions
    WHEN NEW.type = 'payout' AND NOT EXISTS (
      SELECT 1 FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_PAYOUT_PERSON_NOT_IN_PROJECT: person is not registered in project_persons'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_payout_person_in_project_persons_update BEFORE UPDATE OF person_id, project_id, type ON transactions
    WHEN NEW.type = 'payout' AND NOT EXISTS (
      SELECT 1 FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_PAYOUT_PERSON_NOT_IN_PROJECT: person is not registered in project_persons'); END;",

    // work_out.person_id must be in project_persons with payout_only or both
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_work_out_person_insert BEFORE INSERT ON transactions
    WHEN NEW.type = 'work_out' AND (
      COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('payout_only', 'both')
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_WORK_OUT_PERSON_NOT_IN_PROJECT: work_out person must be registered in project_persons with payout_only or both'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_work_out_person_update BEFORE UPDATE OF person_id, project_id, type ON transactions
    WHEN NEW.type = 'work_out' AND (
      COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('payout_only', 'both')
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_WORK_OUT_PERSON_NOT_IN_PROJECT: work_out person must be registered in project_persons with payout_only or both'); END;",

    // payout with distribution: only allowed for participating partner (profit_share or both)
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_distribution_mode_insert BEFORE INSERT ON transactions
    WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
      COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('profit_share', 'both')
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON: person is not a participating partner in project_persons'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_distribution_mode_update BEFORE UPDATE OF purpose, person_id, project_id, type ON transactions
    WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
      COALESCE((SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.person_id), '') NOT IN ('profit_share', 'both')
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON: person is not a participating partner in project_persons'); END;",

    // payout with distribution: sum of share_bp must equal 10000
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_distribution_share_bp_insert BEFORE INSERT ON transactions
    WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
      COALESCE((
        SELECT SUM(share_bp) FROM project_persons
        WHERE project_id = NEW.project_id AND settlement_mode IN ('profit_share', 'both')
      ), 0) != 10000
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_SHARE_BP_SUM_NOT_10000: sum of share_bp for participating partners in project must be 10000'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_distribution_share_bp_update BEFORE UPDATE OF purpose, project_id, type ON transactions
    WHEN NEW.type = 'payout' AND NEW.purpose = 'distribution' AND (
      COALESCE((
        SELECT SUM(share_bp) FROM project_persons
        WHERE project_id = NEW.project_id AND settlement_mode IN ('profit_share', 'both')
      ), 0) != 10000
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_SHARE_BP_SUM_NOT_10000: sum of share_bp for participating partners in project must be 10000'); END;",

    // performed_by / attributed_to must be participating partner
    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_partner_participating_insert BEFORE INSERT ON transactions
    WHEN (
      (NEW.performed_by IS NOT NULL AND COALESCE((
        SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.performed_by
      ), '') NOT IN ('profit_share', 'both'))
      OR
      (NEW.attributed_to IS NOT NULL AND COALESCE((
        SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.attributed_to
      ), '') NOT IN ('profit_share', 'both'))
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_PARTNER_NOT_PARTICIPATING: performed_by and attributed_to must be a participating partner in project_persons'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_tx_check_partner_participating_update BEFORE UPDATE OF performed_by, attributed_to, project_id ON transactions
    WHEN (
      (NEW.performed_by IS NOT NULL AND COALESCE((
        SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.performed_by
      ), '') NOT IN ('profit_share', 'both'))
      OR
      (NEW.attributed_to IS NOT NULL AND COALESCE((
        SELECT settlement_mode FROM project_persons WHERE project_id = NEW.project_id AND person_id = NEW.attributed_to
      ), '') NOT IN ('profit_share', 'both'))
    )
    BEGIN SELECT RAISE(ABORT, 'ERR_PARTNER_NOT_PARTICIPATING: performed_by and attributed_to must be a participating partner in project_persons'); END;",

    // project_settings lock after distribution or project lock
    "CREATE TRIGGER IF NOT EXISTS trg_project_settings_lock_insert BEFORE INSERT ON project_settings
    WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
      OR EXISTS (SELECT 1 FROM transactions WHERE project_id = NEW.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_SETTINGS_LOCKED: project_settings cannot be inserted after first distribution or project lock'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_project_settings_lock_update BEFORE UPDATE ON project_settings
    WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
      OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_SETTINGS_LOCKED: project_settings is locked after first distribution or project lock'); END;",

    // project_persons lock after distribution or project lock
    "CREATE TRIGGER IF NOT EXISTS trg_project_persons_lock_insert BEFORE INSERT ON project_persons
    WHEN (SELECT status FROM projects WHERE id = NEW.project_id) = 'locked'
      OR EXISTS (SELECT 1 FROM transactions WHERE project_id = NEW.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_PERSONS_LOCKED: project_persons cannot be inserted after first distribution or project lock'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_project_persons_lock_update BEFORE UPDATE ON project_persons
    WHEN (SELECT status FROM projects WHERE id = OLD.project_id) = 'locked'
      OR EXISTS (SELECT 1 FROM transactions WHERE project_id = OLD.project_id AND type = 'payout' AND purpose = 'distribution' AND deleted_at IS NULL)
    BEGIN SELECT RAISE(ABORT, 'ERR_PROJECT_PERSONS_LOCKED: project_persons is locked after first distribution or project lock'); END;",

    // app_settings unit immutable
    "CREATE TRIGGER IF NOT EXISTS trg_app_settings_unit_immutable BEFORE UPDATE OF value ON app_settings
    WHEN OLD.key = 'unit'
    BEGIN SELECT RAISE(ABORT, 'ERR_UNIT_IMMUTABLE: unit is immutable'); END;",

    "CREATE TRIGGER IF NOT EXISTS trg_app_settings_unit_no_delete BEFORE DELETE ON app_settings
    WHEN OLD.key = 'unit'
    BEGIN SELECT RAISE(ABORT, 'ERR_UNIT_IMMUTABLE: unit is immutable: DELETE is forbidden'); END;",
];

/// Initializes SQLite database with Version 3 schema, pragmas, triggers, and default settings.
pub fn init_database(conn: &Connection) -> Result<()> {
    conn.execute_batch("
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
    ")?;

    conn.execute_batch(DDL_TABLES)?;

    for trigger in DDL_TRIGGERS {
        conn.execute_batch(trigger)?;
    }

    conn.execute(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('schema_version', ?1)",
        [SCHEMA_VERSION.to_string()],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('unit', 'toman')",
        [],
    )?;

    Ok(())
}
