use std::collections::{HashMap, HashSet};
use std::path::Path;
use calamine::{open_workbook_auto, Data, Reader};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::db::{Database, NewTransaction};
use crate::error::{KarkardError, Result};
use crate::jalali::jalali_to_iso;
use crate::money::{normalize_digits, parse_toman};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExcelSheetHeader {
    pub name: String,
    pub row_count: usize,
    pub col_count: usize,
    pub sample_headers: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ColumnMapping {
    pub date_col: Option<usize>,
    pub desc_col: Option<usize>,
    pub amount_col: Option<usize>,
    pub type_col: Option<usize>,
    pub party_col: Option<usize>,
    pub account_col: Option<usize>,
    pub partner_col: Option<usize>,
    pub has_header: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedExcelRow {
    pub row_index: usize,
    pub raw_date: String,
    pub iso_date: Option<String>,
    pub description: String,
    pub amount: Option<i64>,
    pub tx_type: String,
    pub party_name: Option<String>,
    pub account_name: Option<String>,
    pub partner_name: Option<String>,
    pub import_hash: String,
    pub is_valid: bool,
    pub is_duplicate: bool,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExcelPreviewReport {
    pub sheet_name: String,
    pub total_rows: usize,
    pub valid_rows_count: usize,
    pub invalid_rows_count: usize,
    pub duplicate_rows_count: usize,
    pub total_amount_toman: i64,
    pub identified_parties: Vec<String>,
    pub identified_accounts: Vec<String>,
    pub sample_rows: Vec<ParsedExcelRow>,
    pub detected_mapping: ColumnMapping,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExcelImportResult {
    pub total_rows_processed: usize,
    pub imported_count: usize,
    pub duplicates_skipped: usize,
    pub invalid_skipped: usize,
    pub total_imported_amount: i64,
    pub new_parties_created: usize,
    pub new_accounts_created: usize,
}

pub struct ExcelService;

impl ExcelService {
    /// Inspects an excel workbook and returns sheets metadata with first-row headers.
    pub fn list_sheets<P: AsRef<Path>>(path: P) -> Result<Vec<ExcelSheetHeader>> {
        let mut workbook = open_workbook_auto(&path)
            .map_err(|e| KarkardError::Excel(format!("نمی‌توان فایل اکسل را باز کرد: {}", e)))?;

        let sheet_names = workbook.sheet_names().to_vec();
        let mut infos = Vec::new();

        for name in sheet_names {
            if let Ok(range) = workbook.worksheet_range(&name) {
                let (rows, cols) = range.get_size();
                let mut sample_headers = Vec::new();
                if let Some(first_row) = range.rows().next() {
                    for cell in first_row {
                        let text = match cell {
                            Data::String(s) => s.trim().to_string(),
                            Data::Int(n) => n.to_string(),
                            Data::Float(f) => f.to_string(),
                            _ => String::new(),
                        };
                        sample_headers.push(text);
                    }
                }
                infos.push(ExcelSheetHeader {
                    name,
                    row_count: rows,
                    col_count: cols,
                    sample_headers,
                });
            }
        }

        Ok(infos)
    }

    /// Automatically detects column indices from sheet headers.
    pub fn auto_detect_mapping(headers: &[String]) -> ColumnMapping {
        let mut date_col = None;
        let mut desc_col = None;
        let mut amount_col = None;
        let mut type_col = None;
        let mut party_col = None;
        let mut account_col = None;
        let mut partner_col = None;

        for (idx, h) in headers.iter().enumerate() {
            let s = h.trim();
            if s.contains("تاریخ") || s.eq_ignore_ascii_case("date") {
                if date_col.is_none() { date_col = Some(idx); }
            } else if s.contains("مبلغ") || s.contains("قیمت") || s.eq_ignore_ascii_case("amount") {
                if amount_col.is_none() { amount_col = Some(idx); }
            } else if s.contains("نوع") || s.eq_ignore_ascii_case("type") {
                if type_col.is_none() { type_col = Some(idx); }
            } else if s.contains("طرف حساب") || s.contains("طرف‌حساب") || s.contains("کارفرما") || s.contains("شخص") {
                if party_col.is_none() { party_col = Some(idx); }
            } else if s.contains("صندوق") || s.contains("حساب") || s.contains("بانک") {
                if account_col.is_none() { account_col = Some(idx); }
            } else if s.contains("شریک") || s.contains("مجری") {
                if partner_col.is_none() { partner_col = Some(idx); }
            } else if s.contains("شرح") || s.contains("توضیح") || s.contains("عملیات") || s.eq_ignore_ascii_case("desc") {
                if desc_col.is_none() { desc_col = Some(idx); }
            }
        }

        ColumnMapping {
            date_col,
            desc_col,
            amount_col,
            type_col,
            party_col,
            account_col,
            partner_col,
            has_header: true,
        }
    }

    /// Maps Persian and English text into canonical transaction types.
    pub fn infer_tx_type(raw_type: Option<&str>, desc: &str) -> String {
        let mut text = String::new();
        if let Some(t) = raw_type {
            text.push_str(t);
            text.push(' ');
        }
        text.push_str(desc);
        let s = normalize_digits(&text).to_lowercase();

        if s.contains("کارکرد (درآمد)") || s.contains("کارکرد") || s.contains("طلب کارفرما") || s.contains("صورت وضعیت") {
            "work_in".to_string()
        } else if s.contains("کارکرد راننده") || s.contains("کارکرد پرسنل") || s.contains("دستمزد") || s.contains("حقوق") {
            "work_out".to_string()
        } else if s.contains("دریافتی") || s.contains("وصول") || s.contains("واریز کارفرما") {
            "income".to_string()
        } else if s.contains("هزینه") || s.contains("خرج") || s.contains("سوخت") || s.contains("تعمیر") || s.contains("روغن") || s.contains("ناهار") {
            "expense".to_string()
        } else if s.contains("تسویه شریک") || s.contains("تسویه") || s.contains("برداشت") || s.contains("سهم سود") || s.contains("واریز بحساب") || s.contains("واریز به حساب") {
            "payout".to_string()
        } else if s.contains("انتقال") || s.contains("جابجایی حساب") {
            "transfer".to_string()
        } else {
            "work_in".to_string()
        }
    }

    /// Parses dates from cell content (supports Jalali strings "1405/01/22", Excel serials, or ISO).
    pub fn parse_cell_date(cell: &Data) -> Option<String> {
        match cell {
            Data::String(s) => {
                let norm = normalize_digits(s.trim());
                let parts: Vec<&str> = norm.split(|c| c == '/' || c == '-' || c == '.').collect();
                if parts.len() == 3 {
                    if let (Ok(y), Ok(m), Ok(d)) = (parts[0].parse::<i32>(), parts[1].parse::<i32>(), parts[2].parse::<i32>()) {
                        if y >= 1300 && y <= 1500 {
                            return jalali_to_iso(y, m, d).ok();
                        } else if y >= 1900 && y <= 2100 {
                            return Some(format!("{:04}-{:02}-{:02}", y, m, d));
                        }
                    }
                }
                None
            }
            Data::Int(serial) => Self::excel_serial_to_iso(*serial as f64),
            Data::Float(serial) => Self::excel_serial_to_iso(*serial),
            Data::DateTime(dt) => {
                let serial = dt.as_f64();
                Self::excel_serial_to_iso(serial)
            }
            _ => None,
        }
    }

    fn excel_serial_to_iso(serial: f64) -> Option<String> {
        let days = serial.floor() as i64;
        if days < 1 || days > 100000 {
            return None;
        }
        let mut d = days;
        if d > 60 {
            d -= 1;
        }
        let unix_epoch_days = 25569;
        let unix_days = d - unix_epoch_days;
        let secs = unix_days * 86400;
        let dt = chrono::DateTime::from_timestamp(secs, 0)?;
        Some(dt.format("%Y-%m-%d").to_string())
    }

    /// Extracts an integer toman amount from cell data.
    pub fn parse_cell_amount(cell: &Data) -> Option<i64> {
        match cell {
            Data::Int(v) => if *v > 0 { Some(*v) } else { None },
            Data::Float(f) => if *f > 0.0 { Some(f.round() as i64) } else { None },
            Data::String(s) => {
                let s_clean = s.trim();
                if s_clean.is_empty() || s_clean == "–" || s_clean == "-" {
                    None
                } else {
                    parse_toman(s_clean).ok().filter(|&amt| amt > 0)
                }
            }
            _ => None,
        }
    }

    /// Computes unique deterministic SHA-256 hash for deduplication during import.
    pub fn compute_import_hash(project_id: &str, row_idx: usize, date: &str, amount: i64, desc: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(project_id.as_bytes());
        hasher.update(row_idx.to_string().as_bytes());
        hasher.update(date.as_bytes());
        hasher.update(amount.to_string().as_bytes());
        hasher.update(desc.as_bytes());
        let result = hasher.finalize();
        result.iter().map(|b| format!("{:02x}", b)).collect()
    }

    /// Previews an excel import, analyzing rows, mapping types, and validating rules.
    pub fn preview_import<P: AsRef<Path>>(
        conn: Option<&Connection>,
        path: P,
        sheet_name: &str,
        custom_mapping: Option<ColumnMapping>,
        project_id: &str,
        preview_limit: usize,
    ) -> Result<ExcelPreviewReport> {
        let mut workbook = open_workbook_auto(&path)
            .map_err(|e| KarkardError::Excel(format!("نمی‌توان فایل اکسل را باز کرد: {}", e)))?;

        let range = workbook.worksheet_range(sheet_name)
            .map_err(|e| KarkardError::Excel(format!("شیت '{}' در فایل یافت نشد: {}", sheet_name, e)))?;

        let mut rows_iter = range.rows();
        let first_row = rows_iter.next().ok_or_else(|| KarkardError::Excel("شیت انتخاب شده خالی است".into()))?;

        let headers: Vec<String> = first_row.iter().map(|c| match c {
            Data::String(s) => s.trim().to_string(),
            Data::Int(n) => n.to_string(),
            _ => String::new(),
        }).collect();

        let mapping = custom_mapping.unwrap_or_else(|| Self::auto_detect_mapping(&headers));

        // Existing hashes in DB for duplicate detection
        let mut existing_hashes = HashSet::new();
        if let Some(c) = conn {
            if let Ok(mut stmt) = c.prepare("SELECT import_hash FROM transactions WHERE project_id = ?1 AND import_hash IS NOT NULL") {
                if let Ok(rows) = stmt.query_map([project_id], |r| r.get::<_, String>(0)) {
                    for r in rows.flatten() {
                        existing_hashes.insert(r);
                    }
                }
            }
        }

        let mut total_rows = 0;
        let mut valid_count = 0;
        let mut invalid_count = 0;
        let mut duplicate_count = 0;
        let mut total_amount: i64 = 0;

        let mut parties_set = HashSet::new();
        let mut accounts_set = HashSet::new();
        let mut sample_rows = Vec::new();

        let start_row_idx = if mapping.has_header { 2 } else { 1 };

        let data_rows = if mapping.has_header {
            rows_iter
        } else {
            // Re-include first row if no header
            range.rows()
        };

        for (offset, row) in data_rows.enumerate() {
            total_rows += 1;
            let row_idx = start_row_idx + offset;

            let raw_date = mapping.date_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                Data::Int(n) => n.to_string(),
                Data::Float(f) => f.to_string(),
                _ => String::new(),
            }).unwrap_or_default();

            let iso_date = mapping.date_col.and_then(|c| row.get(c)).and_then(Self::parse_cell_date);

            let desc = mapping.desc_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                Data::Int(n) => n.to_string(),
                _ => String::new(),
            }).unwrap_or_default();

            let amount = mapping.amount_col.and_then(|c| row.get(c)).and_then(Self::parse_cell_amount);

            let raw_type = mapping.type_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            });

            let tx_type = Self::infer_tx_type(raw_type.as_deref(), &desc);

            let party_name = mapping.party_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            }).filter(|s| !s.is_empty() && s != "-");

            let account_name = mapping.account_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            }).filter(|s| !s.is_empty() && s != "-");

            let partner_name = mapping.partner_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            }).filter(|s| !s.is_empty() && s != "-");

            if let Some(ref p) = party_name { parties_set.insert(p.clone()); }
            if let Some(ref a) = account_name { accounts_set.insert(a.clone()); }

            let hash = Self::compute_import_hash(
                project_id,
                row_idx,
                iso_date.as_deref().unwrap_or(&raw_date),
                amount.unwrap_or(0),
                &desc,
            );

            let is_duplicate = existing_hashes.contains(&hash);
            let mut error = None;

            if amount.is_none() {
                error = Some("مبلغ نامعتبر یا تعیین‌نشده (–)".to_string());
                invalid_count += 1;
            } else if iso_date.is_none() {
                error = Some("تاریخ شمسی/میلادی نامعتبر".to_string());
                invalid_count += 1;
            } else if is_duplicate {
                duplicate_count += 1;
            } else {
                valid_count += 1;
                total_amount += amount.unwrap_or(0);
            }

            if sample_rows.len() < preview_limit {
                sample_rows.push(ParsedExcelRow {
                    row_index: row_idx,
                    raw_date,
                    iso_date,
                    description: desc,
                    amount,
                    tx_type,
                    party_name,
                    account_name,
                    partner_name,
                    import_hash: hash,
                    is_valid: error.is_none() && !is_duplicate,
                    is_duplicate,
                    error_message: error,
                });
            }
        }

        let mut identified_parties: Vec<String> = parties_set.into_iter().collect();
        identified_parties.sort();
        let mut identified_accounts: Vec<String> = accounts_set.into_iter().collect();
        identified_accounts.sort();

        Ok(ExcelPreviewReport {
            sheet_name: sheet_name.to_string(),
            total_rows,
            valid_rows_count: valid_count,
            invalid_rows_count: invalid_count,
            duplicate_rows_count: duplicate_count,
            total_amount_toman: total_amount,
            identified_parties,
            identified_accounts,
            sample_rows,
            detected_mapping: mapping,
        })
    }

    /// Executes the atomic database import of transactions from the excel sheet.
    pub fn commit_import<P: AsRef<Path>>(
        conn: &mut Connection,
        path: P,
        sheet_name: &str,
        mapping: &ColumnMapping,
        project_id: &str,
    ) -> Result<ExcelImportResult> {
        let mut workbook = open_workbook_auto(&path)
            .map_err(|e| KarkardError::Excel(format!("نمی‌توان فایل اکسل را باز کرد: {}", e)))?;

        let range = workbook.worksheet_range(sheet_name)
            .map_err(|e| KarkardError::Excel(format!("شیت '{}' در فایل یافت نشد: {}", sheet_name, e)))?;

        let start_row_idx = if mapping.has_header { 2 } else { 1 };
        let rows_iter = if mapping.has_header {
            let mut it = range.rows();
            it.next(); // Skip header
            it
        } else {
            range.rows()
        };

        // Cache existing persons & accounts to avoid duplicate creations
        let mut persons_cache: HashMap<String, String> = HashMap::new(); // name -> id
        {
            let mut stmt = conn.prepare("SELECT id, name FROM persons")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
            for r in rows.flatten() {
                persons_cache.insert(r.1, r.0);
            }
        }

        let mut accounts_cache: HashMap<String, String> = HashMap::new(); // name -> id
        {
            let mut stmt = conn.prepare("SELECT id, name FROM cash_accounts")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
            for r in rows.flatten() {
                accounts_cache.insert(r.1, r.0);
            }
        }

        let mut existing_hashes: HashSet<String> = HashSet::new();
        {
            let mut stmt = conn.prepare("SELECT import_hash FROM transactions WHERE project_id = ?1 AND import_hash IS NOT NULL")?;
            let rows = stmt.query_map([project_id], |r| r.get::<_, String>(0))?;
            for r in rows.flatten() {
                existing_hashes.insert(r);
            }
        }

        let mut new_parties_created = 0;
        let mut new_accounts_created = 0;
        let mut imported_count = 0;
        let mut duplicates_skipped = 0;
        let mut invalid_skipped = 0;
        let mut total_imported_amount: i64 = 0;

        let tx = conn.transaction()?;

        let default_account_id = if let Some(id) = accounts_cache.get("صندوق اصلی کارگاه") {
            Some(id.clone())
        } else if let Some((_, id)) = accounts_cache.iter().next() {
            Some(id.clone())
        } else {
            let default_acc = Database::create_cash_account(&tx, "صندوق اصلی کارگاه", "project", None, None)?;
            accounts_cache.insert("صندوق اصلی کارگاه".to_string(), default_acc.id.clone());
            new_accounts_created += 1;
            Some(default_acc.id)
        };

        let mut default_driver_id = None;
        let mut default_client_id = None;
        let mut default_partner_id = None;

        let has_valid_partners: bool = tx.query_row(
            "SELECT COALESCE(SUM(share_bp), 0) = 10000 FROM project_persons WHERE project_id = ?1 AND settlement_mode IN ('profit_share', 'both')",
            [project_id],
            |r| r.get(0),
        ).unwrap_or(false);

        for (offset, row) in rows_iter.enumerate() {
            let row_idx = start_row_idx + offset;

            let iso_date = mapping.date_col.and_then(|c| row.get(c)).and_then(Self::parse_cell_date);
            let amount = mapping.amount_col.and_then(|c| row.get(c)).and_then(Self::parse_cell_amount);

            if iso_date.is_none() || amount.is_none() {
                invalid_skipped += 1;
                continue;
            }

            let iso_date = iso_date.unwrap();
            let amount = amount.unwrap();

            let desc = mapping.desc_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                Data::Int(n) => n.to_string(),
                _ => String::new(),
            }).unwrap_or_default();

            let raw_type = mapping.type_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            });

            let tx_type = Self::infer_tx_type(raw_type.as_deref(), &desc);

            let hash = Self::compute_import_hash(project_id, row_idx, &iso_date, amount, &desc);
            if existing_hashes.contains(&hash) {
                duplicates_skipped += 1;
                continue;
            }

            let party_name = mapping.party_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            }).filter(|s| !s.is_empty() && s != "-");

            let account_name = mapping.account_col.and_then(|c| row.get(c)).map(|c| match c {
                Data::String(s) => s.trim().to_string(),
                _ => String::new(),
            }).filter(|s| !s.is_empty() && s != "-");

            // Auto-create person/client if needed
            let party_id = if let Some(p_name) = party_name {
                if let Some(id) = persons_cache.get(&p_name) {
                    Some(id.clone())
                } else {
                    let role = if tx_type == "work_in" || tx_type == "income" {
                        "client"
                    } else if tx_type == "payout" {
                        "partner"
                    } else {
                        "worker"
                    };
                    let person = Database::create_person(&tx, &p_name, role, None, None)?;
                    persons_cache.insert(p_name, person.id.clone());
                    new_parties_created += 1;
                    Some(person.id)
                }
            } else {
                None
            };

            // If work_in or income, ensure client_id has kind == 'client' in persons table
            if (tx_type == "work_in" || tx_type == "income") && party_id.is_some() {
                let pid = party_id.as_ref().unwrap();
                let current_kind: String = tx.query_row(
                    "SELECT kind FROM persons WHERE id = ?1",
                    [pid],
                    |r| r.get(0),
                ).unwrap_or_default();

                if current_kind != "client" {
                    let _ = tx.execute("UPDATE persons SET kind = 'client' WHERE id = ?1", [pid]);
                }
            }

            // Auto-create cash account if needed
            let account_id = if let Some(a_name) = account_name {
                if let Some(id) = accounts_cache.get(&a_name) {
                    Some(id.clone())
                } else {
                    // Find if any person is named in the account name (e.g. "عارف", "فرشاد", "امیر")
                    let mut holder_id = None;
                    for (p_name, p_id) in &persons_cache {
                        if a_name.contains(p_name) {
                            holder_id = Some(p_id.clone());
                            break;
                        }
                    }

                    let holder_ref = holder_id.as_deref();
                    let kind = if holder_ref.is_some() { "personal" } else { "project" };

                    let acc = Database::create_cash_account(&tx, &a_name, kind, None, holder_ref)?;
                    accounts_cache.insert(a_name, acc.id.clone());
                    new_accounts_created += 1;
                    Some(acc.id)
                }
            } else {
                None
            };

            // Strictly conform to Version 3 SQLite schema check constraints:
            let (client_id, person_id, cash_account_id, from_account_id, to_account_id, purpose) = match tx_type.as_str() {
                "work_in" => {
                    // Accrual work done for client. Cash is NOT touched.
                    let c_id = party_id.clone().or_else(|| {
                        if default_client_id.is_none() {
                            let c = Database::create_person(&tx, "کارفرمای متفرقه", "client", None, None).ok()?;
                            default_client_id = Some(c.id);
                        }
                        default_client_id.clone()
                    });
                    (c_id, None, None, None, None, None)
                }
                "work_out" => {
                    // Accrual wage/work done by driver/person.
                    let p_id = party_id.clone().or_else(|| {
                        if default_driver_id.is_none() {
                            let d = Database::create_person(&tx, "راننده جرثقیل", "driver", None, None).ok()?;
                            default_driver_id = Some(d.id);
                        }
                        default_driver_id.clone()
                    });
                    (None, p_id, None, None, None, None)
                }
                "income" => {
                    // Cash received from client into project cash account
                    let c_id = party_id.clone().or_else(|| {
                        if default_client_id.is_none() {
                            let c = Database::create_person(&tx, "کارفرمای متفرقه", "client", None, None).ok()?;
                            default_client_id = Some(c.id);
                        }
                        default_client_id.clone()
                    });
                    let a_id = account_id.clone().or_else(|| default_account_id.clone());
                    (c_id, None, a_id, None, None, None)
                }
                "expense" => {
                    // Expense paid from cash account
                    let a_id = account_id.clone().or_else(|| default_account_id.clone());
                    (None, None, a_id, None, None, None)
                }
                "payout" => {
                    // Payout to person/partner
                    let p_id = party_id.clone().or_else(|| {
                        if default_partner_id.is_none() {
                            let p = Database::create_person(&tx, "شریک", "partner", None, None).ok()?;
                            default_partner_id = Some(p.id);
                        }
                        default_partner_id.clone()
                    });
                    let a_id = account_id.clone().or_else(|| default_account_id.clone());
                    let p_purpose = if has_valid_partners && desc.contains("سود") {
                        "distribution"
                    } else {
                        "settle_payable"
                    };
                    (None, p_id, a_id, None, None, Some(p_purpose.to_string()))
                }
                _ => (None, None, None, None, None, None),
            };

            // Ensure person is registered in project_persons for work_out or payout
            if let Some(ref pid) = person_id {
                let already_in_project: bool = tx.query_row(
                    "SELECT 1 FROM project_persons WHERE project_id = ?1 AND person_id = ?2",
                    rusqlite::params![project_id, pid],
                    |_| Ok(true),
                ).unwrap_or(false);

                if !already_in_project {
                    let _ = Database::set_project_person(&tx, project_id, pid, "payout_only", None, 99);
                }
            }

            let override_reason = if tx_type == "payout" {
                Some("ورود اطلاعات تاریخی از اکسل کارکرد".to_string())
            } else {
                None
            };

            let new_tx = NewTransaction {
                id: None,
                project_id: project_id.to_string(),
                tx_type,
                amount,
                date: iso_date,
                description: if desc.is_empty() { None } else { Some(desc) },
                category_id: None,
                receipt_not_required: None,
                import_hash: Some(hash.clone()),
                client_id,
                person_id,
                performed_by: None,
                attributed_to: None,
                cash_account_id,
                from_account_id,
                to_account_id,
                purpose,
                override_reason,
            };

            Database::insert_transaction(&tx, &new_tx)?;
            existing_hashes.insert(hash);
            imported_count += 1;
            total_imported_amount += amount;
        }

        // Add audit log entry
        let audit_details = format!(
            "ورود فایل اکسل: {} سطر وارد شد به مبلغ {} تومان ({} تکراری، {} نامعتبر)",
            imported_count,
            crate::money::format_toman(total_imported_amount, true),
            duplicates_skipped,
            invalid_skipped,
        );
        let audit_id = Uuid::new_v4().to_string();
        let _ = tx.execute(
            "INSERT INTO audit_log (id, entity_type, entity_id, action, before_json, reason) VALUES (?1, 'transactions', ?2, 'EXCEL_IMPORT', NULL, ?3)",
            rusqlite::params![audit_id, project_id, audit_details],
        );

        tx.commit()?;

        Ok(ExcelImportResult {
            total_rows_processed: imported_count + duplicates_skipped + invalid_skipped,
            imported_count,
            duplicates_skipped,
            invalid_skipped,
            total_imported_amount,
            new_parties_created,
            new_accounts_created,
        })
    }
}
