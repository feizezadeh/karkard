use std::env;
use std::path::Path;
use rusqlite::Connection;
use karkard_core::*;

fn print_usage() {
    println!("سامانه خط فرمان دفتر کارکرد (Karkard CLI)");
    println!("استفاده:");
    println!("  karkard-cli demo                              اجرای سناریوی آزمایشی بخش ۵ سند مالی و نمایش تراز طلایی");
    println!("  karkard-cli list-projects [db_path]           نمایش لیست پروژه‌ها");
    println!("  karkard-cli balance <project_id> [db_path]    محاسبه و نمایش ترازنامه و سهم شرکا");
    println!("  karkard-cli backup <target_dir> [db_path]     ایجاد نسخه پشتیبان ایمن");
}

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage();
        return Ok(());
    }

    match args[1].as_str() {
        "demo" => {
            println!("--- اجرای سناریوی متوازن بخش ۵ سند مالی در حافظه ---");
            let conn = Connection::open_in_memory()?;
            init_database(&conn)?;

            let amir = Database::create_person(&conn, "امیر", "partner", None, None)?;
            let aref = Database::create_person(&conn, "عارف", "partner", None, None)?;
            let driver = Database::create_person(&conn, "راننده", "driver", None, None)?;
            let gozel = Database::create_person(&conn, "گوزل", "client", None, None)?;
            let hadi = Database::create_person(&conn, "هادی", "client", None, None)?;

            let proj = Database::create_project(&conn, "پروژه جرثقیل (بخش ۵)", None, None)?;

            let c1 = Database::create_cash_account(&conn, "صندوق پروژه C1", "project", None, None)?;
            let a1 = Database::create_cash_account(&conn, "جیب امیر A1", "personal", None, Some(&amir.id))?;
            let b1 = Database::create_cash_account(&conn, "حساب عارف B1", "personal", None, Some(&aref.id))?;

            Database::set_project_person(&conn, &proj.id, &amir.id, "profit_share", Some(5000), 1)?;
            Database::set_project_person(&conn, &proj.id, &aref.id, "profit_share", Some(5000), 2)?;
            Database::set_project_person(&conn, &proj.id, &driver.id, "payout_only", None, 3)?;
            Database::set_project_settings(&conn, &proj.id, "both", "accrual", "by_work")?;

            let txs = vec![
                ( "work_in", 60_000_000, Some(&gozel.id), None, Some(&amir.id), None, None, None, None, None ),
                ( "work_in", 20_000_000, Some(&gozel.id), None, Some(&aref.id), None, None, None, None, None ),
                ( "work_in", 10_000_000, Some(&hadi.id), None, None, None, None, None, None, None ),
                ( "work_out", 6_000_000, None, Some(&driver.id), None, Some(&amir.id), None, None, None, None ),
                ( "expense", 2_000_000, None, None, None, None, Some(&c1.id), None, None, None ),
                ( "expense", 3_000_000, None, None, None, Some(&amir.id), Some(&a1.id), None, None, None ),
                ( "expense", 1_000_000, None, None, None, Some(&aref.id), Some(&b1.id), None, None, None ),
                ( "income", 30_000_000, Some(&gozel.id), None, None, None, Some(&c1.id), None, None, None ),
                ( "income", 20_000_000, Some(&gozel.id), None, None, None, Some(&b1.id), None, None, None ),
                ( "income", 10_000_000, Some(&hadi.id), None, None, None, Some(&c1.id), None, None, None ),
                ( "payout", 4_000_000, None, Some(&driver.id), None, None, Some(&c1.id), None, None, Some("settle_payable") ),
                ( "transfer", 3_000_000, None, None, None, None, None, Some(&c1.id), Some(&a1.id), None ),
                ( "payout", 10_000_000, None, Some(&aref.id), None, None, Some(&b1.id), None, None, Some("distribution") ),
                ( "payout", 5_000_000, None, Some(&amir.id), None, None, Some(&c1.id), None, None, Some("distribution") ),
            ];

            for (t, amt, cid, pid, pb, attr, ca, fa, ta, purp) in txs {
                let tx = NewTransaction {
                    id: None,
                    project_id: proj.id.clone(),
                    tx_type: t.into(),
                    amount: amt,
                    date: "2024-07-01".into(),
                    description: None,
                    category_id: None,
                    receipt_not_required: None,
                    import_hash: None,
                    client_id: cid.map(|s| s.to_string()),
                    person_id: pid.map(|s| s.to_string()),
                    performed_by: pb.map(|s| s.to_string()),
                    attributed_to: attr.map(|s| s.to_string()),
                    cash_account_id: ca.map(|s| s.to_string()),
                    from_account_id: fa.map(|s| s.to_string()),
                    to_account_id: ta.map(|s| s.to_string()),
                    purpose: purp.map(|s| s.to_string()),
                    override_reason: None,
                };
                Database::insert_transaction(&conn, &tx)?;
            }

            let rep = calculate_project_balance(&conn, &proj.id, None, None)?;
            println!("کارکرد کل (Win): {} تومان", format_toman(rep.win, true));
            println!("کارکرد اشخاص (Wout): {} تومان", format_toman(rep.wout, true));
            println!("هزینه‌ها (Exp): {} تومان", format_toman(rep.exp, true));
            println!("دریافتی‌ها (Inc): {} تومان", format_toman(rep.inc, true));
            println!("سود کارکردی پروژه: {} تومان", format_toman(rep.profit_accrual, true));
            println!("موجودی نقد حساب پروژه C1: {} تومان", format_toman(rep.total_project_accounts_balance, true));
            println!("طلب از کارفرمایان: {} تومان", format_toman(rep.total_receivables, true));
            println!("مجموع مطالبات اشخاص (Due): {} تومان", format_toman(rep.total_due, true));
            println!("تساوی طلایی (bal(project) + Rec == Due): {}", if rep.is_golden_equation_balanced { "برقرار است ✓" } else { "نامتعادل ✗" });
            println!("سهم قابل‌مطالبه امیر: {} تومان", format_toman(rep.partner_allocations[&amir.id].claimable_share, true));
            println!("سهم قابل‌مطالبه عارف: {} تومان", format_toman(rep.partner_allocations[&aref.id].claimable_share, true));
        }
        "list-projects" => {
            let db_path = args.get(2).map(|s| s.as_str()).unwrap_or("karkard.db");
            let conn = Connection::open(db_path)?;
            init_database(&conn)?;
            let list = Database::list_projects(&conn)?;
            for p in list {
                println!("- [{}] {} ({})", p.id, p.name, p.status);
            }
        }
        "inspect" => {
            use calamine::Reader;
            let file_path = args.get(2).expect("مسیر فایل اکسل الزامی است");
            let mut workbook = calamine::open_workbook_auto(file_path).map_err(|e| KarkardError::Excel(e.to_string()))?;
            for name in workbook.sheet_names().to_vec() {
                println!("=== Sheet: {} ===", name);
                if let Ok(range) = workbook.worksheet_range(&name) {
                    let (rows, cols) = range.get_size();
                    println!("Size: {} rows x {} cols", rows, cols);
                    for (r_idx, row) in range.rows().take(15).enumerate() {
                        let non_empty: Vec<String> = row.iter().map(|c| format!("{:?}", c)).collect();
                        println!("Row {}: {:?}", r_idx, &non_empty[..non_empty.len().min(10)]);
                    }
                }
            }
        }
        "balance" => {
            if args.len() < 3 {
                println!("شناسه پروژه الزامی است");
                return Ok(());
            }
            let pid = &args[2];
            let db_path = args.get(3).map(|s| s.as_str()).unwrap_or("karkard.db");
            let conn = Connection::open(db_path)?;
            init_database(&conn)?;
            let rep = calculate_project_balance(&conn, pid, None, None)?;
            println!("سود کارکردی: {}", format_toman(rep.profit_accrual, true));
            println!("طلب از کارفرما: {}", format_toman(rep.total_receivables, true));
            println!("کل مطالبات: {}", format_toman(rep.total_due, true));
            println!("تراز طلایی: {}", if rep.is_golden_equation_balanced { "برقرار است ✓" } else { "نامتعادل ✗" });
        }
        "backup" => {
            if args.len() < 3 {
                println!("مسیر پوشه پشتیبان الزامی است");
                return Ok(());
            }
            let target_dir = &args[2];
            let db_path = args.get(3).map(|s| s.as_str()).unwrap_or("karkard.db");
            let conn = Connection::open(db_path)?;
            init_database(&conn)?;
            let meta = BackupService::create_backup(&conn, Path::new(target_dir))?;
            println!("✓ پشتیبان در {} ایجاد شد (هش: {})", meta.file_path, meta.sha256);
        }
        cmd => {
            println!("دستور ناشناخته: {}", cmd);
            print_usage();
        }
    }

    Ok(())
}
