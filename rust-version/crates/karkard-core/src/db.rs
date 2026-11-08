use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::balance::calculate_project_balance;
use crate::error::{KarkardError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Person {
    pub id: String,
    pub name: String,
    pub kind: String, // partner | client | driver | worker | other
    pub code: Option<String>,
    pub note: Option<String>,
    pub is_active: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub status: String, // open | locked
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CashAccount {
    pub id: String,
    pub name: String,
    pub kind: String, // project | personal
    pub code: Option<String>,
    pub holder_person_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSettings {
    pub project_id: String,
    pub report_basis: String, // accrual | cash | both
    pub share_basis: String,  // accrual | cash
    pub share_method: String, // fixed_percent | by_work
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectPerson {
    pub project_id: String,
    pub person_id: String,
    pub settlement_mode: String, // payout_only | profit_share | both
    pub share_bp: Option<i32>,
    pub share_order: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transaction {
    pub id: String,
    pub project_id: String,
    #[serde(alias = "type")]
    pub tx_type: String, // work_in | work_out | income | expense | payout | transfer
    pub amount: i64,
    pub date: String,
    pub description: String,
    pub category_id: Option<String>,
    pub receipt_not_required: bool,
    pub import_hash: Option<String>,
    pub deleted_at: Option<String>,
    pub deleted_reason: Option<String>,
    pub client_id: Option<String>,
    pub person_id: Option<String>,
    pub performed_by: Option<String>,
    pub attributed_to: Option<String>,
    pub cash_account_id: Option<String>,
    pub from_account_id: Option<String>,
    pub to_account_id: Option<String>,
    pub purpose: Option<String>, // settle_payable | distribution
    pub override_reason: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewTransaction {
    pub id: Option<String>,
    #[serde(alias = "projectId")]
    pub project_id: String,
    #[serde(alias = "txType", alias = "type")]
    pub tx_type: String,
    pub amount: i64,
    pub date: String,
    pub description: Option<String>,
    #[serde(alias = "categoryId")]
    pub category_id: Option<String>,
    #[serde(alias = "receiptNotRequired")]
    pub receipt_not_required: Option<bool>,
    #[serde(alias = "importHash")]
    pub import_hash: Option<String>,
    #[serde(alias = "clientId")]
    pub client_id: Option<String>,
    #[serde(alias = "personId")]
    pub person_id: Option<String>,
    #[serde(alias = "performedBy")]
    pub performed_by: Option<String>,
    #[serde(alias = "attributedTo")]
    pub attributed_to: Option<String>,
    #[serde(alias = "cashAccountId")]
    pub cash_account_id: Option<String>,
    #[serde(alias = "fromAccountId")]
    pub from_account_id: Option<String>,
    #[serde(alias = "toAccountId")]
    pub to_account_id: Option<String>,
    pub purpose: Option<String>,
    #[serde(alias = "overrideReason")]
    pub override_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Receipt {
    pub id: String,
    pub transaction_id: String,
    pub file_path: String,
    pub file_name: Option<String>,
    pub file_size: Option<i64>,
    pub hash: Option<String>,
    pub mime: String,
    pub created_at: String,
}

// ---------------------------------------------------------------------------
// Database Operations
// ---------------------------------------------------------------------------

pub struct Database;

impl Database {
    // -----------------------------------------------------------------------
    // Persons
    // -----------------------------------------------------------------------
    pub fn create_person(
        conn: &Connection,
        name: &str,
        kind: &str,
        code: Option<&str>,
        note: Option<&str>,
    ) -> Result<Person> {
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO persons (id, name, kind, code, note, is_active) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
            params![id, name, kind, code, note],
        )?;
        Self::get_person(conn, &id)
    }

    pub fn get_person(conn: &Connection, id: &str) -> Result<Person> {
        conn.query_row(
            "SELECT id, name, kind, code, note, is_active, created_at, updated_at FROM persons WHERE id = ?1",
            [id],
            |row| {
                Ok(Person {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    kind: row.get(2)?,
                    code: row.get(3)?,
                    note: row.get(4)?,
                    is_active: row.get::<_, i32>(5)? == 1,
                    created_at: row.get(6)?,
                    updated_at: row.get(7)?,
                })
            },
        ).map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => KarkardError::NotFound(format!("شخص با شناسه {} یافت نشد", id)),
            other => KarkardError::Database(other),
        })
    }

    pub fn list_persons(conn: &Connection, active_only: bool) -> Result<Vec<Person>> {
        let sql = if active_only {
            "SELECT id, name, kind, code, note, is_active, created_at, updated_at FROM persons WHERE is_active = 1 ORDER BY name ASC"
        } else {
            "SELECT id, name, kind, code, note, is_active, created_at, updated_at FROM persons ORDER BY name ASC"
        };
        let mut stmt = conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            Ok(Person {
                id: row.get(0)?,
                name: row.get(1)?,
                kind: row.get(2)?,
                code: row.get(3)?,
                note: row.get(4)?,
                is_active: row.get::<_, i32>(5)? == 1,
                created_at: row.get(6)?,
                updated_at: row.get(7)?,
            })
        })?;
        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    // -----------------------------------------------------------------------
    // Projects
    // -----------------------------------------------------------------------
    pub fn create_project(
        conn: &Connection,
        name: &str,
        start_date: Option<&str>,
        end_date: Option<&str>,
    ) -> Result<Project> {
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO projects (id, name, start_date, end_date, status) VALUES (?1, ?2, ?3, ?4, 'open')",
            params![id, name, start_date, end_date],
        )?;
        // Also insert default project settings
        conn.execute(
            "INSERT INTO project_settings (project_id, report_basis, share_basis, share_method) VALUES (?1, 'both', 'accrual', 'fixed_percent')",
            params![id],
        )?;
        Self::get_project(conn, &id)
    }

    pub fn get_project(conn: &Connection, id: &str) -> Result<Project> {
        conn.query_row(
            "SELECT id, name, start_date, end_date, status, created_at, updated_at FROM projects WHERE id = ?1",
            [id],
            |row| {
                Ok(Project {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    start_date: row.get(2)?,
                    end_date: row.get(3)?,
                    status: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                })
            },
        ).map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => KarkardError::NotFound(format!("پروژه با شناسه {} یافت نشد", id)),
            other => KarkardError::Database(other),
        })
    }

    pub fn list_projects(conn: &Connection) -> Result<Vec<Project>> {
        let mut stmt = conn.prepare("SELECT id, name, start_date, end_date, status, created_at, updated_at FROM projects ORDER BY created_at DESC")?;
        let rows = stmt.query_map([], |row| {
            Ok(Project {
                id: row.get(0)?,
                name: row.get(1)?,
                start_date: row.get(2)?,
                end_date: row.get(3)?,
                status: row.get(4)?,
                created_at: row.get(5)?,
                updated_at: row.get(6)?,
            })
        })?;
        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    pub fn lock_project(conn: &Connection, id: &str) -> Result<()> {
        conn.execute("UPDATE projects SET status = 'locked' WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn rollover_project(
        conn: &Connection,
        source_project_id: &str,
        target_name: &str,
        start_date: Option<&str>,
        lock_source: bool,
    ) -> Result<Project> {
        let new_proj = Self::create_project(conn, target_name, start_date, None)?;

        if let Ok(settings) = conn.query_row(
            "SELECT report_basis, share_basis, share_method FROM project_settings WHERE project_id = ?1",
            [source_project_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?)),
        ) {
            let _ = Self::set_project_settings(conn, &new_proj.id, &settings.0, &settings.1, &settings.2);
        }

        let persons = Self::list_project_persons(conn, source_project_id)?;
        for p in persons {
            let _ = Self::set_project_person(conn, &new_proj.id, &p.person_id, &p.settlement_mode, p.share_bp, p.share_order);
        }

        if lock_source {
            Self::lock_project(conn, source_project_id)?;
        }

        Ok(new_proj)
    }

    // -----------------------------------------------------------------------
    // Cash Accounts
    // -----------------------------------------------------------------------
    pub fn create_cash_account(
        conn: &Connection,
        name: &str,
        kind: &str,
        code: Option<&str>,
        holder_person_id: Option<&str>,
    ) -> Result<CashAccount> {
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO cash_accounts (id, name, kind, code, holder_person_id) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, name, kind, code, holder_person_id],
        )?;
        conn.query_row(
            "SELECT id, name, kind, code, holder_person_id, created_at, updated_at FROM cash_accounts WHERE id = ?1",
            [&id],
            |row| {
                Ok(CashAccount {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    kind: row.get(2)?,
                    code: row.get(3)?,
                    holder_person_id: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                })
            },
        ).map_err(KarkardError::Database)
    }

    pub fn list_cash_accounts(conn: &Connection) -> Result<Vec<CashAccount>> {
        let mut stmt = conn.prepare("SELECT id, name, kind, code, holder_person_id, created_at, updated_at FROM cash_accounts ORDER BY name ASC")?;
        let rows = stmt.query_map([], |row| {
            Ok(CashAccount {
                id: row.get(0)?,
                name: row.get(1)?,
                kind: row.get(2)?,
                code: row.get(3)?,
                holder_person_id: row.get(4)?,
                created_at: row.get(5)?,
                updated_at: row.get(6)?,
            })
        })?;
        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    // -----------------------------------------------------------------------
    // Project Settings & Project Persons
    // -----------------------------------------------------------------------
    pub fn get_project_settings(conn: &Connection, project_id: &str) -> Result<Option<ProjectSettings>> {
        let mut stmt = conn.prepare(
            "SELECT project_id, report_basis, share_basis, share_method FROM project_settings WHERE project_id = ?1",
        )?;
        let mut rows = stmt.query_map([project_id], |row| {
            Ok(ProjectSettings {
                project_id: row.get(0)?,
                report_basis: row.get(1)?,
                share_basis: row.get(2)?,
                share_method: row.get(3)?,
            })
        })?;
        if let Some(r) = rows.next() {
            Ok(Some(r?))
        } else {
            Ok(None)
        }
    }

    pub fn set_project_settings(
        conn: &Connection,
        project_id: &str,
        report_basis: &str,
        share_basis: &str,
        share_method: &str,
    ) -> Result<()> {
        conn.execute(
            "INSERT INTO project_settings (project_id, report_basis, share_basis, share_method) \
             VALUES (?1, ?2, ?3, ?4) \
             ON CONFLICT(project_id) DO UPDATE SET \
                report_basis = excluded.report_basis, \
                share_basis = excluded.share_basis, \
                share_method = excluded.share_method, \
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
            params![project_id, report_basis, share_basis, share_method],
        )?;
        Ok(())
    }

    pub fn set_project_person(
        conn: &Connection,
        project_id: &str,
        person_id: &str,
        settlement_mode: &str,
        share_bp: Option<i32>,
        share_order: i32,
    ) -> Result<()> {
        conn.execute(
            "INSERT INTO project_persons (project_id, person_id, settlement_mode, share_bp, share_order) \
             VALUES (?1, ?2, ?3, ?4, ?5) \
             ON CONFLICT(project_id, person_id) DO UPDATE SET \
                settlement_mode = excluded.settlement_mode, \
                share_bp = excluded.share_bp, \
                share_order = excluded.share_order, \
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')",
            params![project_id, person_id, settlement_mode, share_bp, share_order],
        )?;
        Ok(())
    }

    pub fn list_project_persons(conn: &Connection, project_id: &str) -> Result<Vec<ProjectPerson>> {
        let mut stmt = conn.prepare(
            "SELECT project_id, person_id, settlement_mode, share_bp, share_order FROM project_persons WHERE project_id = ?1 ORDER BY share_order ASC",
        )?;
        let rows = stmt.query_map([project_id], |row| {
            Ok(ProjectPerson {
                project_id: row.get(0)?,
                person_id: row.get(1)?,
                settlement_mode: row.get(2)?,
                share_bp: row.get(3)?,
                share_order: row.get(4)?,
            })
        })?;
        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    // -----------------------------------------------------------------------
    // Transactions
    // -----------------------------------------------------------------------
    pub fn insert_transaction(conn: &Connection, tx: &NewTransaction) -> Result<Transaction> {
        // Business-level payout ceiling check
        if tx.tx_type == "payout" {
            let has_override = tx.override_reason.as_ref().map(|s| !s.trim().is_empty()).unwrap_or(false);
            if !has_override {
                if let (Some(ref purp), Some(ref pid)) = (&tx.purpose, &tx.person_id) {
                    let report = calculate_project_balance(conn, &tx.project_id, None, None)?;
                    if purp == "distribution" {
                        let claimable = report
                            .partner_allocations
                            .get(pid)
                            .map(|a| a.claimable_share)
                            .unwrap_or(0);
                        if tx.amount > claimable {
                            return Err(KarkardError::Domain {
                                code: "ERR_DISTRIBUTION_EXCEEDS_SHARE",
                                message: format!(
                                    "مبلغ برداشت از سود ({} تومان) بیش از سهم قابل‌مطالبه ({} تومان) است. ثبت این تراکنش نیازمند ذکر دلیل در override_reason است.",
                                    tx.amount, claimable
                                ),
                            });
                        }
                    } else if purp == "settle_payable" {
                        let payable = report.payables.get(pid).copied().unwrap_or(0);
                        if tx.amount > payable {
                            return Err(KarkardError::Domain {
                                code: "ERR_SETTLE_PAYABLE_EXCEEDS_PAY",
                                message: format!(
                                    "مبلغ تسویه دستمزد ({} تومان) بیش از مانده بدهی دستمزد ({} تومان) است. ثبت این تراکنش نیازمند ذکر دلیل در override_reason است.",
                                    tx.amount, payable
                                ),
                            });
                        }
                    }
                }
            }
        }

        let id = tx.id.clone().unwrap_or_else(|| Uuid::new_v4().to_string());
        let desc = tx.description.as_deref().unwrap_or("");
        let receipt_not_req = if tx.receipt_not_required.unwrap_or(false) { 1 } else { 0 };

        conn.execute(
            "INSERT INTO transactions (
                id, project_id, type, amount, date, description, category_id,
                receipt_not_required, import_hash, client_id, person_id,
                performed_by, attributed_to, cash_account_id, from_account_id,
                to_account_id, purpose, override_reason
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18
            )",
            params![
                id,
                tx.project_id,
                tx.tx_type,
                tx.amount,
                tx.date,
                desc,
                tx.category_id,
                receipt_not_req,
                tx.import_hash,
                tx.client_id,
                tx.person_id,
                tx.performed_by,
                tx.attributed_to,
                tx.cash_account_id,
                tx.from_account_id,
                tx.to_account_id,
                tx.purpose,
                tx.override_reason
            ],
        )?;

        Self::get_transaction(conn, &id)
    }

    pub fn get_transaction(conn: &Connection, id: &str) -> Result<Transaction> {
        conn.query_row(
            "SELECT id, project_id, type, amount, date, description, category_id, \
             receipt_not_required, import_hash, deleted_at, deleted_reason, \
             client_id, person_id, performed_by, attributed_to, cash_account_id, \
             from_account_id, to_account_id, purpose, override_reason, created_at, updated_at \
             FROM transactions WHERE id = ?1",
            [id],
            |row| {
                Ok(Transaction {
                    id: row.get(0)?,
                    project_id: row.get(1)?,
                    tx_type: row.get(2)?,
                    amount: row.get(3)?,
                    date: row.get(4)?,
                    description: row.get(5)?,
                    category_id: row.get(6)?,
                    receipt_not_required: row.get::<_, i32>(7)? == 1,
                    import_hash: row.get(8)?,
                    deleted_at: row.get(9)?,
                    deleted_reason: row.get(10)?,
                    client_id: row.get(11)?,
                    person_id: row.get(12)?,
                    performed_by: row.get(13)?,
                    attributed_to: row.get(14)?,
                    cash_account_id: row.get(15)?,
                    from_account_id: row.get(16)?,
                    to_account_id: row.get(17)?,
                    purpose: row.get(18)?,
                    override_reason: row.get(19)?,
                    created_at: row.get(20)?,
                    updated_at: row.get(21)?,
                })
            },
        ).map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => KarkardError::NotFound(format!("تراکنش با شناسه {} یافت نشد", id)),
            other => KarkardError::Database(other),
        })
    }

    pub fn list_transactions(
        conn: &Connection,
        project_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<Transaction>> {
        let sql = if include_deleted {
            "SELECT id, project_id, type, amount, date, description, category_id, \
             receipt_not_required, import_hash, deleted_at, deleted_reason, \
             client_id, person_id, performed_by, attributed_to, cash_account_id, \
             from_account_id, to_account_id, purpose, override_reason, created_at, updated_at \
             FROM transactions WHERE project_id = ?1 ORDER BY date DESC, created_at DESC"
        } else {
            "SELECT id, project_id, type, amount, date, description, category_id, \
             receipt_not_required, import_hash, deleted_at, deleted_reason, \
             client_id, person_id, performed_by, attributed_to, cash_account_id, \
             from_account_id, to_account_id, purpose, override_reason, created_at, updated_at \
             FROM transactions WHERE project_id = ?1 AND deleted_at IS NULL ORDER BY date DESC, created_at DESC"
        };

        let mut stmt = conn.prepare(sql)?;
        let rows = stmt.query_map([project_id], |row| {
            Ok(Transaction {
                id: row.get(0)?,
                project_id: row.get(1)?,
                tx_type: row.get(2)?,
                amount: row.get(3)?,
                date: row.get(4)?,
                description: row.get(5)?,
                category_id: row.get(6)?,
                receipt_not_required: row.get::<_, i32>(7)? == 1,
                import_hash: row.get(8)?,
                deleted_at: row.get(9)?,
                deleted_reason: row.get(10)?,
                client_id: row.get(11)?,
                person_id: row.get(12)?,
                performed_by: row.get(13)?,
                attributed_to: row.get(14)?,
                cash_account_id: row.get(15)?,
                from_account_id: row.get(16)?,
                to_account_id: row.get(17)?,
                purpose: row.get(18)?,
                override_reason: row.get(19)?,
                created_at: row.get(20)?,
                updated_at: row.get(21)?,
            })
        })?;

        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    /// Soft-deletes a transaction atomically with a mandatory reason,
    /// logging the action in `audit_log`.
    pub fn soft_delete_transaction(conn: &Connection, tx_id: &str, reason: &str) -> Result<()> {
        if reason.trim().is_empty() {
            return Err(KarkardError::Validation("دلیل حذف تراکنش الزامی است".into()));
        }

        // Fetch current row for audit log
        let tx = Self::get_transaction(conn, tx_id)?;
        if tx.deleted_at.is_some() {
            return Err(KarkardError::Validation("تراکنش قبلاً حذف شده است".into()));
        }

        let before_json = serde_json::to_string(&tx).unwrap_or_default();

        conn.execute(
            "UPDATE transactions SET \
                deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), \
                deleted_reason = ?1 \
             WHERE id = ?2 AND deleted_at IS NULL",
            params![reason.trim(), tx_id],
        )?;

        let audit_id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO audit_log (id, entity_type, entity_id, action, before_json, reason) \
             VALUES (?1, 'transaction', ?2, 'soft_delete', ?3, ?4)",
            params![audit_id, tx_id, before_json, reason.trim()],
        )?;

        Ok(())
    }

    // -----------------------------------------------------------------------
    // Receipts
    // -----------------------------------------------------------------------
    pub fn add_receipt(
        conn: &Connection,
        transaction_id: &str,
        file_path: &str,
        file_name: Option<&str>,
        file_size: Option<i64>,
        hash: Option<&str>,
        mime: &str,
    ) -> Result<Receipt> {
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO receipts (id, transaction_id, file_path, file_name, file_size, hash, mime) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![id, transaction_id, file_path, file_name, file_size, hash, mime],
        )?;

        Ok(Receipt {
            id,
            transaction_id: transaction_id.to_string(),
            file_path: file_path.to_string(),
            file_name: file_name.map(String::from),
            file_size,
            hash: hash.map(String::from),
            mime: mime.to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        })
    }

    pub fn list_receipts(conn: &Connection, transaction_id: &str) -> Result<Vec<Receipt>> {
        let mut stmt = conn.prepare(
            "SELECT id, transaction_id, file_path, file_name, file_size, hash, mime, created_at \
             FROM receipts WHERE transaction_id = ?1 ORDER BY created_at ASC",
        )?;
        let rows = stmt.query_map([transaction_id], |row| {
            Ok(Receipt {
                id: row.get(0)?,
                transaction_id: row.get(1)?,
                file_path: row.get(2)?,
                file_name: row.get(3)?,
                file_size: row.get(4)?,
                hash: row.get(5)?,
                mime: row.get(6)?,
                created_at: row.get(7)?,
            })
        })?;
        let mut res = Vec::new();
        for r in rows {
            res.push(r?);
        }
        Ok(res)
    }

    pub fn delete_receipt(conn: &Connection, receipt_id: &str) -> Result<()> {
        conn.execute("DELETE FROM receipts WHERE id = ?1", [receipt_id])?;
        Ok(())
    }

    pub fn seed_initial_data_if_empty(conn: &Connection) -> Result<()> {
        let count: i64 = conn.query_row("SELECT COUNT(*) FROM projects", [], |r| r.get(0)).unwrap_or(0);
        if count > 0 {
            return Ok(());
        }

        let proj = Self::create_project(
            conn,
            "پروژه کارکرد جرثقیل آذرمی (مهر ۱۴۰۵)",
            Some("2026-09-23"),
            Some("2026-10-22"),
        )?;

        let p1 = Self::create_person(conn, "امیر", "partner", Some("PRT-01"), Some("شریک سرمایه‌گذار"))?;
        let p2 = Self::create_person(conn, "عارف", "partner", Some("PRT-02"), Some("شریک اجرایی"))?;
        let p3 = Self::create_person(conn, "راننده جرثقیل", "driver", Some("DRV-01"), Some("راننده دکل بلند"))?;
        let p4 = Self::create_person(conn, "کارفرما گوزل", "client", Some("CLT-01"), Some("پروژه پل روگذر"))?;
        let p5 = Self::create_person(conn, "کارگاه مکانیکی بهرام", "worker", Some("WRK-01"), Some("سرویس‌کار هیدرولیک"))?;

        Self::set_project_settings(conn, &proj.id, "both", "accrual", "fixed_percent")?;
        Self::set_project_person(conn, &proj.id, &p1.id, "both", Some(6000), 1)?;
        Self::set_project_person(conn, &proj.id, &p2.id, "both", Some(4000), 2)?;
        Self::set_project_person(conn, &proj.id, &p3.id, "payout_only", None, 3)?;
        Self::set_project_person(conn, &proj.id, &p5.id, "payout_only", None, 4)?;

        let c1 = Self::create_cash_account(conn, "صندوق کارگاه", "project", None, None)?;
        let _ = Self::create_cash_account(conn, "جیب امیر", "personal", None, Some(&p1.id))?;
        let _ = Self::create_cash_account(conn, "حساب بانکی عارف", "personal", None, Some(&p2.id))?;

        // 1. work_in: crane work for Gzel
        Self::insert_transaction(conn, &NewTransaction {
            id: None,
            project_id: proj.id.clone(),
            tx_type: "work_in".to_string(),
            amount: 90_000_000,
            date: "2026-09-23".to_string(),
            description: Some("کارکرد جرثقیل در پروژه گوزل".to_string()),
            category_id: None,
            receipt_not_required: Some(false),
            import_hash: None,
            client_id: Some(p4.id.clone()),
            person_id: None,
            performed_by: None,
            attributed_to: None,
            cash_account_id: None,
            from_account_id: None,
            to_account_id: None,
            purpose: None,
            override_reason: None,
        })?;

        // 2. income: advance payment received from Gzel into workshop cash account
        Self::insert_transaction(conn, &NewTransaction {
            id: None,
            project_id: proj.id.clone(),
            tx_type: "income".to_string(),
            amount: 60_000_000,
            date: "2026-09-26".to_string(),
            description: Some("دریافت پیش‌پرداخت نقدی از گوزل".to_string()),
            category_id: None,
            receipt_not_required: Some(false),
            import_hash: None,
            client_id: Some(p4.id.clone()),
            person_id: None,
            performed_by: None,
            attributed_to: None,
            cash_account_id: Some(c1.id.clone()),
            from_account_id: None,
            to_account_id: None,
            purpose: None,
            override_reason: None,
        })?;

        // 3. work_out: driver crane wage accrual
        Self::insert_transaction(conn, &NewTransaction {
            id: None,
            project_id: proj.id.clone(),
            tx_type: "work_out".to_string(),
            amount: 6_000_000,
            date: "2026-09-27".to_string(),
            description: Some("کارکرد و انعام راننده".to_string()),
            category_id: None,
            receipt_not_required: Some(false),
            import_hash: None,
            client_id: None,
            person_id: Some(p3.id.clone()),
            performed_by: None,
            attributed_to: None,
            cash_account_id: None,
            from_account_id: None,
            to_account_id: None,
            purpose: None,
            override_reason: None,
        })?;

        // 4. payout: driver wage partial settlement
        Self::insert_transaction(conn, &NewTransaction {
            id: None,
            project_id: proj.id.clone(),
            tx_type: "payout".to_string(),
            amount: 4_000_000,
            date: "2026-09-30".to_string(),
            description: Some("تسویه دستمزد راننده".to_string()),
            category_id: None,
            receipt_not_required: Some(false),
            import_hash: None,
            client_id: None,
            person_id: Some(p3.id.clone()),
            performed_by: None,
            attributed_to: None,
            cash_account_id: Some(c1.id.clone()),
            from_account_id: None,
            to_account_id: None,
            purpose: Some("settle_payable".to_string()),
            override_reason: None,
        })?;

        // 5. expense: fuel and maintenance
        Self::insert_transaction(conn, &NewTransaction {
            id: None,
            project_id: proj.id.clone(),
            tx_type: "expense".to_string(),
            amount: 6_000_000,
            date: "2026-10-02".to_string(),
            description: Some("گازوئیل و تعویض روغن جرثقیل".to_string()),
            category_id: None,
            receipt_not_required: Some(false),
            import_hash: None,
            client_id: None,
            person_id: None,
            performed_by: None,
            attributed_to: None,
            cash_account_id: Some(c1.id.clone()),
            from_account_id: None,
            to_account_id: None,
            purpose: None,
            override_reason: None,
        })?;

        Ok(())
    }
}
