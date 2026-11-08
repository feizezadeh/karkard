// ============================================================================
// Android JNI Bridge for Karkard Core
// Direct C-ABI interface for Android MainActivity via libkarkard_core.so
// Fully routes 100% of domain commands directly through SQLite database
// ============================================================================

use std::sync::Mutex;
use jni::JNIEnv;
use jni::objects::{JClass, JString};
use jni::sys::jstring;
use rusqlite::Connection;

use crate::db::{Database, NewTransaction};
use crate::money::{format_toman, parse_toman};
use crate::jalali::{iso_to_jalali, jalali_to_iso};
use crate::balance::calculate_project_balance;
use crate::backup::BackupService;
use crate::excel::{ColumnMapping, ExcelService};

static DB: Mutex<Option<(String, Connection)>> = Mutex::new(None);

fn with_db<F, R>(db_path_opt: Option<&str>, f: F) -> std::result::Result<R, String>
where
    F: FnOnce(&mut Connection) -> crate::error::Result<R>,
{
    let path = db_path_opt.unwrap_or("/data/data/ir.karkard.rust/files/karkard.db");
    let mut guard = DB.lock().map_err(|e| e.to_string())?;

    let need_open = match &*guard {
        Some((p, _)) => p != path,
        None => true,
    };

    if need_open {
        if let Some(parent) = std::path::Path::new(path).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let conn = Connection::open(path).map_err(|e| format!("Failed to open db {}: {}", path, e))?;
        crate::schema::init_database(&conn).map_err(|e| format!("Failed to init db schema: {}", e))?;
        let _ = Database::seed_initial_data_if_empty(&conn);
        *guard = Some((path.to_string(), conn));
    }

    let (_, ref mut conn) = guard.as_mut().unwrap();
    f(conn).map_err(|e| e.to_string())
}

#[no_mangle]
pub extern "system" fn Java_ir_karkard_rust_MainActivity_invokeCore(
    mut env: JNIEnv,
    _: JClass,
    cmd: JString,
    args_json: JString,
) -> jstring {
    let cmd_str: String = match env.get_string(&cmd) {
        Ok(s) => s.into(),
        Err(_) => return std::ptr::null_mut(),
    };
    let args_str: String = match env.get_string(&args_json) {
        Ok(s) => s.into(),
        Err(_) => return std::ptr::null_mut(),
    };

    let result_json = handle_core_invoke(&cmd_str, &args_str);

    match env.new_string(result_json) {
        Ok(js) => js.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

pub fn handle_core_invoke(cmd: &str, args_json: &str) -> String {
    let args: serde_json::Value = serde_json::from_str(args_json).unwrap_or(serde_json::Value::Null);
    let db_path = args.get("dbPath").or_else(|| args.get("db_path")).and_then(|v| v.as_str());

    match cmd {
        "list_projects" => {
            match with_db(db_path, |conn| Database::list_projects(conn)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "create_project" => {
            let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let start_date = args.get("startDate").or_else(|| args.get("start_date")).or_else(|| args.get("periodStart")).and_then(|v| v.as_str());
            let end_date = args.get("endDate").or_else(|| args.get("end_date")).or_else(|| args.get("periodEnd")).and_then(|v| v.as_str());
            match with_db(db_path, |conn| Database::create_project(conn, name, start_date, end_date)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "lock_project" => {
            let pid = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            match with_db(db_path, |conn| Database::lock_project(conn, pid)) {
                Ok(_) => serde_json::json!({ "status": "ok" }).to_string(),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "rollover_project_cmd" => {
            let src = args.get("sourceProjectId").or_else(|| args.get("source_project_id")).and_then(|v| v.as_str()).unwrap_or("");
            let target = args.get("targetName").or_else(|| args.get("target_name")).and_then(|v| v.as_str()).unwrap_or("");
            let start = args.get("startDate").or_else(|| args.get("start_date")).and_then(|v| v.as_str());
            let lock_src = args.get("lockSource").or_else(|| args.get("lock_source")).and_then(|v| v.as_bool()).unwrap_or(false);
            match with_db(db_path, |conn| Database::rollover_project(conn, src, target, start, lock_src)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "list_persons" => {
            let active = args.get("activeOnly").or_else(|| args.get("active_only")).and_then(|v| v.as_bool()).unwrap_or(false);
            match with_db(db_path, |conn| Database::list_persons(conn, active)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "create_person" => {
            let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let kind = args.get("kind").and_then(|v| v.as_str()).unwrap_or("worker");
            let code = args.get("code").and_then(|v| v.as_str());
            let note = args.get("note").and_then(|v| v.as_str());
            match with_db(db_path, |conn| Database::create_person(conn, name, kind, code, note)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "list_cash_accounts" => {
            match with_db(db_path, |conn| Database::list_cash_accounts(conn)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "create_cash_account" => {
            let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let kind = args.get("kind").and_then(|v| v.as_str()).unwrap_or("project");
            let code = args.get("code").and_then(|v| v.as_str());
            let holder = args.get("holderPersonId").or_else(|| args.get("holder_person_id")).and_then(|v| v.as_str());
            match with_db(db_path, |conn| Database::create_cash_account(conn, name, kind, code, holder)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "list_project_persons" => {
            let pid = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            match with_db(db_path, |conn| Database::list_project_persons(conn, pid)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "set_project_person" => {
            let proj_id = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            let per_id = args.get("personId").or_else(|| args.get("person_id")).and_then(|v| v.as_str()).unwrap_or("");
            let mode = args.get("settlementMode").or_else(|| args.get("settlement_mode")).and_then(|v| v.as_str()).unwrap_or("payout_only");
            let bp = args.get("shareBp").or_else(|| args.get("share_bp")).and_then(|v| v.as_i64()).map(|n| n as i32);
            let order = args.get("shareOrder").or_else(|| args.get("share_order")).and_then(|v| v.as_i64()).map(|n| n as i32).unwrap_or(1);
            match with_db(db_path, |conn| Database::set_project_person(conn, proj_id, per_id, mode, bp, order)) {
                Ok(_) => serde_json::json!({ "status": "ok" }).to_string(),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "get_project_settings" => {
            let proj_id = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            match with_db(db_path, |conn| Database::get_project_settings(conn, proj_id)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "null".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "set_project_settings" => {
            let proj_id = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            let rep = args.get("reportBasis").or_else(|| args.get("report_basis")).and_then(|v| v.as_str()).unwrap_or("both");
            let sb = args.get("shareBasis").or_else(|| args.get("share_basis")).and_then(|v| v.as_str()).unwrap_or("accrual");
            let sm = args.get("shareMethod").or_else(|| args.get("share_method")).and_then(|v| v.as_str()).unwrap_or("fixed_percent");
            match with_db(db_path, |conn| Database::set_project_settings(conn, proj_id, rep, sb, sm)) {
                Ok(_) => serde_json::json!({ "status": "ok" }).to_string(),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "list_transactions" => {
            let pid = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            let inc_del = args.get("includeDeleted").or_else(|| args.get("include_deleted")).and_then(|v| v.as_bool()).unwrap_or(false);
            match with_db(db_path, |conn| Database::list_transactions(conn, pid, inc_del)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "create_transaction" => {
            let tx_val = args.get("tx").unwrap_or(&args);
            match serde_json::from_value::<NewTransaction>(tx_val.clone()) {
                Ok(new_tx) => match with_db(db_path, |conn| Database::insert_transaction(conn, &new_tx)) {
                    Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                    Err(err) => serde_json::json!({ "error": err }).to_string(),
                },
                Err(err) => serde_json::json!({ "error": format!("فرمت تراکنش نامعتبر است: {}", err) }).to_string(),
            }
        }
        "soft_delete_transaction" => {
            let tx_id = args.get("txId").or_else(|| args.get("tx_id")).and_then(|v| v.as_str()).unwrap_or("");
            let reason = args.get("deletedReason").or_else(|| args.get("deleted_reason")).or_else(|| args.get("reason")).and_then(|v| v.as_str()).unwrap_or("حذف توسط کاربر");
            match with_db(db_path, |conn| Database::soft_delete_transaction(conn, tx_id, reason)) {
                Ok(_) => serde_json::json!({ "status": "ok" }).to_string(),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "get_project_balance" => {
            let pid = args.get("projectId").or_else(|| args.get("project_id")).and_then(|v| v.as_str()).unwrap_or("");
            let start_date = args.get("startDateIso").or_else(|| args.get("fromDate")).or_else(|| args.get("from_date")).and_then(|v| v.as_str());
            let end_date = args.get("endDateIso").or_else(|| args.get("toDate")).or_else(|| args.get("to_date")).and_then(|v| v.as_str());
            match with_db(db_path, |conn| calculate_project_balance(conn, pid, start_date, end_date)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "inspect_excel_cmd" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("");
            match ExcelService::list_sheets(path) {
                Ok(sheets) => serde_json::to_string(&sheets).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err.to_string() }).to_string(),
            }
        }
        "preview_excel_import_cmd" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("");
            let sheet_name = args.get("sheetName")
                .or_else(|| args.get("sheet_name"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let mapping: Option<ColumnMapping> = args.get("mapping")
                .and_then(|v| serde_json::from_value(v.clone()).ok());
            let project_id = args.get("projectId")
                .or_else(|| args.get("project_id"))
                .and_then(|v| v.as_str())
                .unwrap_or("proj-1");
            let limit = args.get("limit").and_then(|v| v.as_u64()).map(|u| u as usize).unwrap_or(25);

            let res = with_db(db_path, |conn| ExcelService::preview_import(Some(conn), path, sheet_name, mapping, project_id, limit));
            match res {
                Ok(report) => serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "commit_excel_import_cmd" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("");
            let sheet_name = args.get("sheetName")
                .or_else(|| args.get("sheet_name"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let mapping: ColumnMapping = args.get("mapping")
                .and_then(|v| serde_json::from_value(v.clone()).ok())
                .unwrap_or_default();
            let project_id = args.get("projectId")
                .or_else(|| args.get("project_id"))
                .and_then(|v| v.as_str())
                .unwrap_or("proj-1");

            let res = with_db(db_path, |conn| ExcelService::commit_import(conn, path, sheet_name, &mapping, project_id));
            match res {
                Ok(report) => serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "format_toman_val" => {
            let amount = args.get("amount").and_then(|v| v.as_i64()).unwrap_or(0);
            let persian = args.get("persianDigits").or_else(|| args.get("persian_digits")).and_then(|v| v.as_bool()).unwrap_or(true);
            serde_json::json!(format_toman(amount, persian)).to_string()
        }
        "parse_toman_val" => {
            let input = args.get("input").and_then(|v| v.as_str()).unwrap_or("");
            match parse_toman(input) {
                Ok(val) => serde_json::json!(val).to_string(),
                Err(err) => serde_json::json!({ "error": err.to_string() }).to_string(),
            }
        }
        "jalali_to_iso_val" => {
            let y = args.get("y").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            let m = args.get("m").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            let d = args.get("d").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            match jalali_to_iso(y, m, d) {
                Ok(iso) => serde_json::json!(iso).to_string(),
                Err(err) => serde_json::json!({ "error": err.to_string() }).to_string(),
            }
        }
        "iso_to_jalali_val" => {
            let iso = args.get("iso").and_then(|v| v.as_str()).unwrap_or("");
            match iso_to_jalali(iso) {
                Ok(j) => serde_json::json!(j).to_string(),
                Err(err) => serde_json::json!({ "error": err.to_string() }).to_string(),
            }
        }
        "create_backup_cmd" => {
            let target_dir = args.get("targetDir").or_else(|| args.get("target_dir")).and_then(|v| v.as_str()).unwrap_or("/data/data/ir.karkard.rust/files/backups");
            let _ = std::fs::create_dir_all(target_dir);
            match with_db(db_path, |conn| BackupService::create_backup(conn, std::path::Path::new(target_dir))) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string()),
                Err(err) => serde_json::json!({ "error": err }).to_string(),
            }
        }
        "list_backups_cmd" => {
            let target_dir = args.get("targetDir").or_else(|| args.get("target_dir")).and_then(|v| v.as_str()).unwrap_or("/data/data/ir.karkard.rust/files/backups");
            match BackupService::list_backups(std::path::Path::new(target_dir)) {
                Ok(res) => serde_json::to_string(&res).unwrap_or_else(|_| "[]".to_string()),
                Err(err) => serde_json::json!({ "error": err.to_string() }).to_string(),
            }
        }
        _ => serde_json::json!({ "error": format!("دستور ناشناخته: {}", cmd) }).to_string(),
    }
}
