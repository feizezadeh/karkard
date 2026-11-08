use rusqlite::Connection;
use karkard_core::*;

fn setup_in_memory_db() -> Connection {
    let conn = Connection::open_in_memory().expect("failed to open in-memory db");
    init_database(&conn).expect("failed to init database");
    conn
}

#[test]
fn test_golden_g3_and_g1_and_g2_and_g5() {
    let conn = setup_in_memory_db();

    // 1. Create Persons
    let amir = Database::create_person(&conn, "امیر", "partner", None, None).unwrap();
    let aref = Database::create_person(&conn, "عارف", "partner", None, None).unwrap();
    let driver = Database::create_person(&conn, "راننده", "driver", None, None).unwrap();
    let gozel = Database::create_person(&conn, "گوزل", "client", None, None).unwrap();
    let hadi = Database::create_person(&conn, "هادی", "client", None, None).unwrap();

    // 2. Create Project
    let proj = Database::create_project(&conn, "پروژه جرثقیل", None, None).unwrap();

    // 3. Create Cash Accounts: C1 (project), A1 (personal Amir), B1 (personal Aref)
    let c1 = Database::create_cash_account(&conn, "صندوق پروژه C1", "project", None, None).unwrap();
    let a1 = Database::create_cash_account(&conn, "جیب امیر A1", "personal", None, Some(&amir.id)).unwrap();
    let b1 = Database::create_cash_account(&conn, "حساب عارف B1", "personal", None, Some(&aref.id)).unwrap();

    // 4. Configure Project Persons & Settings: Amir 50%, Aref 50%, Driver payout_only
    Database::set_project_person(&conn, &proj.id, &amir.id, "profit_share", Some(5000), 1).unwrap();
    Database::set_project_person(&conn, &proj.id, &aref.id, "profit_share", Some(5000), 2).unwrap();
    Database::set_project_person(&conn, &proj.id, &driver.id, "payout_only", None, 3).unwrap();
    Database::set_project_settings(&conn, &proj.id, "both", "accrual", "by_work").unwrap();

    // -----------------------------------------------------------------------
    // Insert the 14 Transactions from Section 5
    // -----------------------------------------------------------------------
    let txs = vec![
        // 1: work_in Gozel, performed_by Amir, 60M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "work_in".into(),
            amount: 60_000_000, date: "2024-07-01".into(), description: Some("کارفرما گوزل".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(gozel.id.clone()), person_id: None, performed_by: Some(amir.id.clone()),
            attributed_to: None, cash_account_id: None, from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 2: work_in Gozel, performed_by Aref, 20M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "work_in".into(),
            amount: 20_000_000, date: "2024-07-02".into(), description: Some("کارفرما گوزل".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(gozel.id.clone()), person_id: None, performed_by: Some(aref.id.clone()),
            attributed_to: None, cash_account_id: None, from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 3: work_in Hadi, shared, 10M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "work_in".into(),
            amount: 10_000_000, date: "2024-07-03".into(), description: Some("کارفرما هادی".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(hadi.id.clone()), person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: None, from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 4: work_out Driver, attributed_to Amir, 6M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "work_out".into(),
            amount: 6_000_000, date: "2024-07-04".into(), description: Some("راننده".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: Some(driver.id.clone()), performed_by: None,
            attributed_to: Some(amir.id.clone()), cash_account_id: None, from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 5: expense Lunch from C1, shared, 2M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "expense".into(),
            amount: 2_000_000, date: "2024-07-05".into(), description: Some("ناهار".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: Some(c1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 6: expense Fuel from A1, attributed_to Amir, 3M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "expense".into(),
            amount: 3_000_000, date: "2024-07-06".into(), description: Some("سوخت".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: None, performed_by: None,
            attributed_to: Some(amir.id.clone()), cash_account_id: Some(a1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 7: expense from B1, attributed_to Aref, 1M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "expense".into(),
            amount: 1_000_000, date: "2024-07-07".into(), description: Some("هزینه عارف".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: None, performed_by: None,
            attributed_to: Some(aref.id.clone()), cash_account_id: Some(b1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 8: income Gozel -> C1, 30M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "income".into(),
            amount: 30_000_000, date: "2024-07-08".into(), description: Some("دریافتی گوزل C1".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(gozel.id.clone()), person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: Some(c1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 9: income Gozel -> B1, 20M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "income".into(),
            amount: 20_000_000, date: "2024-07-09".into(), description: Some("دریافتی گوزل B1".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(gozel.id.clone()), person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: Some(b1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 10: income Hadi -> C1, 10M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "income".into(),
            amount: 10_000_000, date: "2024-07-10".into(), description: Some("دریافتی هادی C1".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: Some(hadi.id.clone()), person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: Some(c1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: None, override_reason: None,
        },
        // 11: payout Driver from C1, settle_payable, 4M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "payout".into(),
            amount: 4_000_000, date: "2024-07-11".into(), description: Some("تسویه دستمزد راننده".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: Some(driver.id.clone()), performed_by: None,
            attributed_to: None, cash_account_id: Some(c1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: Some("settle_payable".into()), override_reason: None,
        },
        // 12: transfer C1 -> A1, 3M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "transfer".into(),
            amount: 3_000_000, date: "2024-07-12".into(), description: Some("بازپرداخت هزینه امیر".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: None, performed_by: None,
            attributed_to: None, cash_account_id: None, from_account_id: Some(c1.id.clone()), to_account_id: Some(a1.id.clone()),
            purpose: None, override_reason: None,
        },
        // 13: payout Aref from B1, distribution, 10M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "payout".into(),
            amount: 10_000_000, date: "2024-07-13".into(), description: Some("برداشت سود عارف".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: Some(aref.id.clone()), performed_by: None,
            attributed_to: None, cash_account_id: Some(b1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: Some("distribution".into()), override_reason: None,
        },
        // 14: payout Amir from C1, distribution, 5M
        NewTransaction {
            id: None, project_id: proj.id.clone(), tx_type: "payout".into(),
            amount: 5_000_000, date: "2024-07-14".into(), description: Some("برداشت سود امیر".into()),
            category_id: None, receipt_not_required: None, import_hash: None,
            client_id: None, person_id: Some(amir.id.clone()), performed_by: None,
            attributed_to: None, cash_account_id: Some(c1.id.clone()), from_account_id: None, to_account_id: None,
            purpose: Some("distribution".into()), override_reason: None,
        },
    ];

    for tx in &txs {
        Database::insert_transaction(&conn, tx).expect("failed to insert transaction");
    }

    // -----------------------------------------------------------------------
    // Mode A: by_work
    // -----------------------------------------------------------------------
    let rep_a = calculate_project_balance(&conn, &proj.id, None, None).unwrap();

    assert_eq!(rep_a.win, 90_000_000);
    assert_eq!(rep_a.wout, 6_000_000);
    assert_eq!(rep_a.exp, 6_000_000);
    assert_eq!(rep_a.inc, 60_000_000);
    assert_eq!(rep_a.profit_accrual, 78_000_000);

    // Balances
    assert_eq!(rep_a.project_account_balances[&c1.id], 26_000_000);
    assert_eq!(rep_a.personal_account_balances[&a1.id], 0);
    assert_eq!(rep_a.personal_account_balances[&b1.id], 9_000_000);

    // Receivables
    assert_eq!(rep_a.receivables[&gozel.id], 30_000_000);
    assert_eq!(rep_a.receivables[&hadi.id], 0);
    assert_eq!(rep_a.total_receivables, 30_000_000);

    // Partner shares Mode A: Amir Share = 50M, Aref Share = 13M
    assert_eq!(rep_a.partner_allocations[&amir.id].total_profit, 55_000_000);
    assert_eq!(rep_a.partner_allocations[&amir.id].claimable_share, 50_000_000);

    assert_eq!(rep_a.partner_allocations[&aref.id].total_profit, 23_000_000);
    assert_eq!(rep_a.partner_allocations[&aref.id].claimable_share, 13_000_000);

    // Payables: Driver = 2M
    assert_eq!(rep_a.payables[&driver.id], 2_000_000);

    // Custody: Amir = 0, Aref = -9M
    assert_eq!(rep_a.custodies[&amir.id], 0);
    assert_eq!(rep_a.custodies[&aref.id], -9_000_000);

    // Due: Driver 2M, Amir 50M, Aref 13 - 9 = 4M => Total 56M
    assert_eq!(rep_a.person_balances[&driver.id].due, 2_000_000);
    assert_eq!(rep_a.person_balances[&amir.id].due, 50_000_000);
    assert_eq!(rep_a.person_balances[&aref.id].due, 4_000_000);
    assert_eq!(rep_a.total_due, 56_000_000);

    // Golden equation G1: bal(project) + Rec == Due => 26M + 30M == 56M
    assert!(rep_a.is_golden_equation_balanced);

    // Golden test G2: sum(profit_p) == Profit_acc => 55M + 23M == 78M
    assert_eq!(
        rep_a.partner_allocations[&amir.id].total_profit + rep_a.partner_allocations[&aref.id].total_profit,
        rep_a.profit_accrual
    );

    // Golden test G5: Total account balance = Inc - Exp - Ps - Pd => 26 + 0 + 9 = 35 == 60 - 6 - 4 - 15
    let total_accounts_bal = rep_a.total_project_accounts_balance + rep_a.personal_account_balances.values().sum::<i64>();
    assert_eq!(total_accounts_bal, 35_000_000);
    assert_eq!(total_accounts_bal, rep_a.inc - rep_a.exp - rep_a.ps - rep_a.pd);

    // -----------------------------------------------------------------------
    // Mode B: fixed_percent
    // -----------------------------------------------------------------------
    let proj_b = Database::create_project(&conn, "پروژه حالت B", None, None).unwrap();
    Database::set_project_person(&conn, &proj_b.id, &amir.id, "profit_share", Some(5000), 1).unwrap();
    Database::set_project_person(&conn, &proj_b.id, &aref.id, "profit_share", Some(5000), 2).unwrap();
    Database::set_project_person(&conn, &proj_b.id, &driver.id, "payout_only", None, 3).unwrap();
    Database::set_project_settings(&conn, &proj_b.id, "both", "accrual", "fixed_percent").unwrap();

    for mut tx in txs {
        tx.project_id = proj_b.id.clone();
        Database::insert_transaction(&conn, &tx).unwrap();
    }

    let rep_b = calculate_project_balance(&conn, &proj_b.id, None, None).unwrap();

    // S = 78M => 39M each
    assert_eq!(rep_b.partner_allocations[&amir.id].total_profit, 39_000_000);
    assert_eq!(rep_b.partner_allocations[&amir.id].claimable_share, 34_000_000);
    assert_eq!(rep_b.partner_allocations[&aref.id].total_profit, 39_000_000);
    assert_eq!(rep_b.partner_allocations[&aref.id].claimable_share, 29_000_000);

    assert_eq!(rep_b.person_balances[&amir.id].due, 34_000_000);
    assert_eq!(rep_b.person_balances[&aref.id].due, 20_000_000);
    assert_eq!(rep_b.person_balances[&driver.id].due, 2_000_000);
    assert_eq!(rep_b.total_due, 56_000_000);

    assert!(rep_b.is_golden_equation_balanced);
}

#[test]
fn test_negative_triggers() {
    let conn = setup_in_memory_db();
    let amir = Database::create_person(&conn, "امیر", "partner", None, None).unwrap();
    let client = Database::create_person(&conn, "کارفرما", "client", None, None).unwrap();
    let proj = Database::create_project(&conn, "پروژه تست", None, None).unwrap();

    // Negative: client cannot have work_out
    let bad_tx = NewTransaction {
        id: None, project_id: proj.id.clone(), tx_type: "work_out".into(),
        amount: 1_000_000, date: "2024-01-01".into(), description: None,
        category_id: None, receipt_not_required: None, import_hash: None,
        client_id: None, person_id: Some(client.id.clone()), performed_by: None,
        attributed_to: None, cash_account_id: None, from_account_id: None, to_account_id: None,
        purpose: None, override_reason: None,
    };
    assert!(Database::insert_transaction(&conn, &bad_tx).is_err());

    // Negative: hard delete of transaction is blocked by trigger
    Database::set_project_person(&conn, &proj.id, &amir.id, "profit_share", Some(10000), 1).unwrap();
    let ca = Database::create_cash_account(&conn, "صندوق", "project", None, None).unwrap();
    let valid_income = NewTransaction {
        id: None, project_id: proj.id.clone(), tx_type: "income".into(),
        amount: 10_000_000, date: "2024-01-01".into(), description: None,
        category_id: None, receipt_not_required: None, import_hash: None,
        client_id: Some(client.id.clone()), person_id: None, performed_by: None,
        attributed_to: None, cash_account_id: Some(ca.id.clone()), from_account_id: None, to_account_id: None,
        purpose: None, override_reason: None,
    };
    let inserted = Database::insert_transaction(&conn, &valid_income).unwrap();
    assert!(conn.execute("DELETE FROM transactions WHERE id = ?1", [&inserted.id]).is_err());
}
