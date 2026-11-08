use rusqlite::Connection;
use karkard_core::*;

#[test]
fn test_sample_excel_import() {
    let excel_path = "/home/mehdi/karkard/دفتر_کارکرد_جرثقیل_آذرمی_آماده_ورود.xlsx";
    if !std::path::Path::new(excel_path).exists() {
        println!("Sample excel not found, skipping integration test");
        return;
    }

    // 1. Test listing sheets
    let sheets = ExcelService::list_sheets(excel_path).expect("failed to list sheets");
    assert!(!sheets.is_empty(), "Sheets should not be empty");
    println!("Found {} sheets", sheets.len());
    for s in &sheets {
        println!("- Sheet '{}': {} rows, {} cols, headers: {:?}", s.name, s.row_count, s.col_count, s.sample_headers);
    }

    // 2. Test previewing the main sheet
    let target_sheet = &sheets[0].name; // "همه تراکنش‌ها (آماده ورود)"
    let preview = ExcelService::preview_import(
        None,
        excel_path,
        target_sheet,
        None,
        "test-proj",
        10,
    ).expect("failed to preview excel");

    println!("Preview Results:");
    println!("Total rows: {}", preview.total_rows);
    println!("Valid rows: {}", preview.valid_rows_count);
    println!("Invalid rows: {}", preview.invalid_rows_count);
    println!("Total amount: {} Toman", preview.total_amount_toman);
    println!("Identified parties count: {}", preview.identified_parties.len());
    println!("Identified accounts count: {}", preview.identified_accounts.len());

    assert!(preview.total_rows > 500, "Should have more than 500 rows in sample excel");
    assert!(preview.valid_rows_count > 500, "Should have more than 500 valid rows");
    assert!(preview.total_amount_toman > 1_000_000_000, "Total amount should be in billions of Toman");

    // 3. Test committing import into SQLite
    let mut conn = Connection::open_in_memory().expect("open sqlite in memory");
    init_database(&conn).expect("init db");

    let proj = Database::create_project(&conn, "پروژه آزمایشی اکسل", None, None).expect("create proj");
    let mapping = preview.detected_mapping;

    let result = ExcelService::commit_import(
        &mut conn,
        excel_path,
        target_sheet,
        &mapping,
        &proj.id,
    ).expect("failed to commit import");

    println!("Commit Import Results:");
    println!("Imported transactions: {}", result.imported_count);
    println!("Total imported amount: {} Toman", result.total_imported_amount);
    println!("New parties created: {}", result.new_parties_created);
    println!("New accounts created: {}", result.new_accounts_created);

    assert_eq!(result.imported_count, preview.valid_rows_count);
    assert_eq!(result.total_imported_amount, preview.total_amount_toman);

    // 4. Test idempotency (re-running import should skip 100% duplicates via import_hash)
    let re_result = ExcelService::commit_import(
        &mut conn,
        excel_path,
        target_sheet,
        &mapping,
        &proj.id,
    ).expect("failed to re-commit import");

    println!("Re-import Results (Deduplication Check):");
    println!("Imported: {}", re_result.imported_count);
    println!("Duplicates skipped: {}", re_result.duplicates_skipped);

    assert_eq!(re_result.imported_count, 0, "Second import should import 0 rows");
    assert_eq!(re_result.duplicates_skipped, result.imported_count, "Second import should skip all as duplicates");
}
