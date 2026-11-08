use std::sync::Mutex;
use tauri::{Manager, State};
use rusqlite::Connection;

use karkard_core::*;

pub struct AppState {
    pub db: Mutex<Connection>,
    pub db_path: String,
}

pub mod commands {
    use super::*;

    #[tauri::command]
    pub fn list_projects(state: State<'_, AppState>) -> std::result::Result<Vec<Project>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::list_projects(&conn).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn create_project(
        name: String,
        start_date: Option<String>,
        end_date: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<Project, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::create_project(&conn, &name, start_date.as_deref(), end_date.as_deref())
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn lock_project(project_id: String, state: State<'_, AppState>) -> std::result::Result<(), String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::lock_project(&conn, &project_id).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn get_project_balance(
        project_id: String,
        start_date_iso: Option<String>,
        end_date_iso: Option<String>,
        from_date: Option<String>,
        to_date: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<ProjectBalanceReport, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        let start = start_date_iso.or(from_date);
        let end = end_date_iso.or(to_date);
        calculate_project_balance(
            &conn,
            &project_id,
            start.as_deref(),
            end.as_deref(),
        ).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn list_persons(active_only: Option<bool>, state: State<'_, AppState>) -> std::result::Result<Vec<Person>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::list_persons(&conn, active_only.unwrap_or(false)).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn create_person(
        name: String,
        kind: String,
        code: Option<String>,
        note: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<Person, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::create_person(&conn, &name, &kind, code.as_deref(), note.as_deref())
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn list_cash_accounts(state: State<'_, AppState>) -> std::result::Result<Vec<CashAccount>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::list_cash_accounts(&conn).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn create_cash_account(
        name: String,
        kind: String,
        code: Option<String>,
        holder_person_id: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<CashAccount, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::create_cash_account(&conn, &name, &kind, code.as_deref(), holder_person_id.as_deref())
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn list_project_persons(
        project_id: String,
        state: State<'_, AppState>,
    ) -> std::result::Result<Vec<ProjectPerson>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::list_project_persons(&conn, &project_id).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn set_project_person(
        project_id: String,
        person_id: String,
        settlement_mode: String,
        share_bp: Option<i32>,
        share_order: Option<i32>,
        state: State<'_, AppState>,
    ) -> std::result::Result<(), String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::set_project_person(&conn, &project_id, &person_id, &settlement_mode, share_bp, share_order.unwrap_or(1))
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn get_project_settings(
        project_id: String,
        state: State<'_, AppState>,
    ) -> std::result::Result<Option<ProjectSettings>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::get_project_settings(&conn, &project_id).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn set_project_settings(
        project_id: String,
        report_basis: Option<String>,
        share_basis: Option<String>,
        share_method: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<(), String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::set_project_settings(
            &conn,
            &project_id,
            &report_basis.unwrap_or_else(|| "both".into()),
            &share_basis.unwrap_or_else(|| "accrual".into()),
            &share_method.unwrap_or_else(|| "fixed_percent".into()),
        ).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn list_transactions(
        project_id: String,
        include_deleted: Option<bool>,
        state: State<'_, AppState>,
    ) -> std::result::Result<Vec<Transaction>, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::list_transactions(&conn, &project_id, include_deleted.unwrap_or(false)).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn create_transaction(
        tx: NewTransaction,
        state: State<'_, AppState>,
    ) -> std::result::Result<Transaction, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::insert_transaction(&conn, &tx).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn soft_delete_transaction(
        tx_id: String,
        reason: Option<String>,
        deleted_reason: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<(), String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        let r = reason.or(deleted_reason).unwrap_or_else(|| "حذف توسط کاربر".to_string());
        Database::soft_delete_transaction(&conn, &tx_id, &r).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn format_toman_val(amount: i64, persian_digits: Option<bool>) -> String {
        format_toman(amount, persian_digits.unwrap_or(true))
    }

    #[tauri::command]
    pub fn parse_toman_val(input: String) -> std::result::Result<i64, String> {
        parse_toman(&input).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn iso_to_jalali_val(iso: String) -> std::result::Result<String, String> {
        iso_to_jalali(&iso).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn jalali_to_iso_val(y: i32, m: i32, d: i32) -> std::result::Result<String, String> {
        jalali_to_iso(y, m, d).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn create_backup_cmd(
        target_dir: Option<String>,
        state: State<'_, AppState>,
    ) -> std::result::Result<BackupMetadata, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        let dir = target_dir.unwrap_or_else(|| "./backups".to_string());
        let _ = std::fs::create_dir_all(&dir);
        BackupService::create_backup(&conn, std::path::Path::new(&dir)).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn list_backups_cmd(
        target_dir: Option<String>,
    ) -> std::result::Result<Vec<BackupMetadata>, String> {
        let dir = target_dir.unwrap_or_else(|| "./backups".to_string());
        BackupService::list_backups(std::path::Path::new(&dir)).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn rollover_project_cmd(
        source_project_id: String,
        target_name: String,
        start_date: Option<String>,
        lock_source: Option<bool>,
        state: State<'_, AppState>,
    ) -> std::result::Result<Project, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        Database::rollover_project(&conn, &source_project_id, &target_name, start_date.as_deref(), lock_source.unwrap_or(false))
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn pick_excel_file_cmd() -> std::result::Result<Option<String>, String> {
        let file = rfd::AsyncFileDialog::new()
            .add_filter("فایل‌های اکسل", &["xlsx", "xls"])
            .set_title("انتخاب فایل اکسل کارکرد")
            .pick_file()
            .await;

        Ok(file.map(|f| f.path().to_string_lossy().to_string()))
    }

    #[tauri::command]
    pub fn inspect_excel_cmd(path: String) -> std::result::Result<Vec<ExcelSheetHeader>, String> {
        ExcelService::list_sheets(&path).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn preview_excel_import_cmd(
        path: String,
        sheet_name: String,
        mapping: Option<ColumnMapping>,
        project_id: String,
        limit: Option<usize>,
        state: State<'_, AppState>,
    ) -> std::result::Result<ExcelPreviewReport, String> {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        ExcelService::preview_import(
            Some(&conn),
            &path,
            &sheet_name,
            mapping,
            &project_id,
            limit.unwrap_or(25),
        ).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn commit_excel_import_cmd(
        path: String,
        sheet_name: String,
        mapping: ColumnMapping,
        project_id: String,
        state: State<'_, AppState>,
    ) -> std::result::Result<ExcelImportResult, String> {
        let mut conn = state.db.lock().map_err(|e| e.to_string())?;
        ExcelService::commit_import(&mut conn, &path, &sheet_name, &mapping, &project_id)
            .map_err(|e| e.to_string())
    }
}

// ---------------------------------------------------------------------------
// App Entrypoint
// ---------------------------------------------------------------------------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let app_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from("."));
            std::fs::create_dir_all(&app_dir).ok();
            let db_path = app_dir.join("karkard.db");

            let conn = Connection::open(&db_path).expect("failed to open sqlite database");
            init_database(&conn).expect("failed to initialize sqlite schema");
            let _ = Database::seed_initial_data_if_empty(&conn);

            app.manage(AppState {
                db: Mutex::new(conn),
                db_path: db_path.to_str().unwrap_or("karkard.db").to_string(),
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_projects,
            commands::create_project,
            commands::lock_project,
            commands::get_project_balance,
            commands::list_persons,
            commands::create_person,
            commands::list_cash_accounts,
            commands::create_cash_account,
            commands::list_project_persons,
            commands::set_project_person,
            commands::get_project_settings,
            commands::set_project_settings,
            commands::list_transactions,
            commands::create_transaction,
            commands::soft_delete_transaction,
            commands::format_toman_val,
            commands::parse_toman_val,
            commands::iso_to_jalali_val,
            commands::jalali_to_iso_val,
            commands::create_backup_cmd,
            commands::list_backups_cmd,
            commands::rollover_project_cmd,
            commands::pick_excel_file_cmd,
            commands::inspect_excel_cmd,
            commands::preview_excel_import_cmd,
            commands::commit_excel_import_cmd
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
