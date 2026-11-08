use std::collections::{HashMap, HashSet};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use crate::error::Result;
use crate::money::{allocate_remainder, PartnerShareItem};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonBalance {
    pub person_id: String,
    pub pay: i64,      // Pay(p): wage payable (positive) or advance prepayment (negative)
    pub share: i64,    // Share(p): claimable profit share
    pub custody: i64,  // Cust(p): project funds custody (positive=project owes person, negative=person holds money)
    pub due: i64,      // Due(p) = Pay + Share + Cust
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartnerProfitAllocation {
    pub person_id: String,
    pub direct_profit: i64,         // work_in(performed) - work_out(attr) - exp(attr)
    pub pool_share: i64,            // share of shared pool
    pub total_profit: i64,          // direct + pool_share
    pub distribution_payouts: i64,  // sum of payout(distribution)
    pub claimable_share: i64,       // total_profit - distribution_payouts
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectBalanceReport {
    pub project_id: String,
    pub report_basis: String, // accrual | cash | both
    pub share_basis: String,  // accrual | cash
    pub share_method: String, // fixed_percent | by_work

    pub win: i64,
    pub wout: i64,
    pub exp: i64,
    pub inc: i64,
    pub ps: i64,
    pub pd: i64,

    pub profit_accrual: i64,
    pub profit_cash: i64,

    pub project_account_balances: HashMap<String, i64>,
    pub personal_account_balances: HashMap<String, i64>,
    pub total_project_accounts_balance: i64,

    pub receivables: HashMap<String, i64>,
    pub total_receivables: i64,

    pub payables: HashMap<String, i64>,
    pub total_payables: i64,

    pub custodies: HashMap<String, i64>,
    pub total_custody: i64,

    pub partner_allocations: HashMap<String, PartnerProfitAllocation>,
    pub person_balances: HashMap<String, PersonBalance>,
    pub total_due: i64,

    pub is_golden_equation_balanced: bool,
    pub start_date_iso: Option<String>,
    pub end_date_iso: Option<String>,
}

pub struct TxRow {
    pub tx_type: String,
    pub amount: i64,
    pub client_id: Option<String>,
    pub person_id: Option<String>,
    pub performed_by: Option<String>,
    pub attributed_to: Option<String>,
    pub cash_account_id: Option<String>,
    pub from_account_id: Option<String>,
    pub to_account_id: Option<String>,
    pub purpose: Option<String>,
}

/// Calculates the complete balance report for `project_id`, optionally
/// filtered by start and end date (inclusive, YYYY-MM-DD).
pub fn calculate_project_balance(
    conn: &Connection,
    project_id: &str,
    start_date_iso: Option<&str>,
    end_date_iso: Option<&str>,
) -> Result<ProjectBalanceReport> {
    // 1. Fetch project settings
    let (report_basis, share_basis, share_method): (String, String, String) = conn
        .query_row(
            "SELECT report_basis, share_basis, share_method FROM project_settings WHERE project_id = ?1",
            [project_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap_or_else(|_| ("both".into(), "accrual".into(), "fixed_percent".into()));

    // 2. Fetch project persons
    let mut stmt_pp = conn.prepare(
        "SELECT person_id, settlement_mode, share_bp, share_order FROM project_persons WHERE project_id = ?1",
    )?;
    let pp_rows = stmt_pp.query_map([project_id], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<i32>>(2)?,
            row.get::<_, i32>(3)?,
        ))
    })?;

    let mut participating_partners = Vec::new();
    let mut all_project_person_ids = Vec::new();

    for r in pp_rows {
        let (pid, mode, share_bp, share_order) = r?;
        all_project_person_ids.push(pid.clone());
        if mode == "profit_share" || mode == "both" {
            participating_partners.push(PartnerShareItem {
                person_id: pid,
                share_bp: share_bp.unwrap_or(0),
                share_order,
            });
        }
    }

    // 3. Fetch active cash accounts
    let mut stmt_ca = conn.prepare("SELECT id, kind, holder_person_id FROM cash_accounts")?;
    let ca_rows = stmt_ca.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
        ))
    })?;

    let mut cash_account_kind_map = HashMap::new();
    let mut personal_account_holder_map = HashMap::new();
    let mut account_balances = HashMap::new();

    for r in ca_rows {
        let (aid, kind, holder) = r?;
        cash_account_kind_map.insert(aid.clone(), kind.clone());
        if kind == "personal" {
            if let Some(h) = holder {
                personal_account_holder_map.insert(aid.clone(), h);
            }
        }
        account_balances.insert(aid, 0i64);
    }

    // 4. Fetch all active (non-deleted) transactions for this project
    let mut sql = String::from(
        "SELECT type, amount, client_id, person_id, performed_by, attributed_to, \
         cash_account_id, from_account_id, to_account_id, purpose \
         FROM transactions WHERE project_id = ?1 AND deleted_at IS NULL",
    );
    let mut params: Vec<rusqlite::types::Value> = vec![rusqlite::types::Value::Text(project_id.to_string())];

    if let Some(start) = start_date_iso {
        params.push(rusqlite::types::Value::Text(start.to_string()));
        sql.push_str(&format!(" AND date >= ?{}", params.len()));
    }
    if let Some(end) = end_date_iso {
        params.push(rusqlite::types::Value::Text(end.to_string()));
        sql.push_str(&format!(" AND date <= ?{}", params.len()));
    }

    let mut stmt_tx = conn.prepare(&sql)?;
    let tx_rows = stmt_tx.query_map(rusqlite::params_from_iter(params), |row| {
        Ok(TxRow {
            tx_type: row.get(0)?,
            amount: row.get(1)?,
            client_id: row.get(2)?,
            person_id: row.get(3)?,
            performed_by: row.get(4)?,
            attributed_to: row.get(5)?,
            cash_account_id: row.get(6)?,
            from_account_id: row.get(7)?,
            to_account_id: row.get(8)?,
            purpose: row.get(9)?,
        })
    })?;

    // 5. Compute base sums
    let mut win = 0i64;
    let mut wout = 0i64;
    let mut exp = 0i64;
    let mut inc = 0i64;
    let mut ps = 0i64;
    let mut pd = 0i64;

    let mut receivables: HashMap<String, i64> = HashMap::new();
    let mut payables: HashMap<String, i64> = HashMap::new();
    let mut direct_profits: HashMap<String, i64> = participating_partners
        .iter()
        .map(|p| (p.person_id.clone(), 0i64))
        .collect();
    let mut partner_distributions: HashMap<String, i64> = participating_partners
        .iter()
        .map(|p| (p.person_id.clone(), 0i64))
        .collect();

    let mut win_shared = 0i64;
    let mut wout_shared = 0i64;
    let mut exp_shared = 0i64;

    for tx_res in tx_rows {
        let tx = tx_res?;
        let amt = tx.amount;
        match tx.tx_type.as_str() {
            "work_in" => {
                win += amt;
                if let Some(cid) = tx.client_id {
                    *receivables.entry(cid).or_insert(0) += amt;
                }
                if let Some(pb) = tx.performed_by {
                    *direct_profits.entry(pb).or_insert(0) += amt;
                } else {
                    win_shared += amt;
                }
            }
            "work_out" => {
                wout += amt;
                if let Some(pid) = tx.person_id {
                    *payables.entry(pid).or_insert(0) += amt;
                }
                if let Some(attr) = tx.attributed_to {
                    *direct_profits.entry(attr).or_insert(0) -= amt;
                } else {
                    wout_shared += amt;
                }
            }
            "income" => {
                inc += amt;
                if let Some(aid) = tx.cash_account_id {
                    *account_balances.entry(aid).or_insert(0) += amt;
                }
                if let Some(cid) = tx.client_id {
                    *receivables.entry(cid).or_insert(0) -= amt;
                }
            }
            "expense" => {
                exp += amt;
                if let Some(aid) = tx.cash_account_id {
                    *account_balances.entry(aid).or_insert(0) -= amt;
                }
                if let Some(attr) = tx.attributed_to {
                    *direct_profits.entry(attr).or_insert(0) -= amt;
                } else {
                    exp_shared += amt;
                }
            }
            "payout" => {
                if let Some(aid) = tx.cash_account_id {
                    *account_balances.entry(aid).or_insert(0) -= amt;
                }
                if let Some(ref purp) = tx.purpose {
                    if purp == "settle_payable" {
                        ps += amt;
                        if let Some(pid) = tx.person_id {
                            *payables.entry(pid).or_insert(0) -= amt;
                        }
                    } else if purp == "distribution" {
                        pd += amt;
                        if let Some(pid) = tx.person_id {
                            *partner_distributions.entry(pid).or_insert(0) += amt;
                        }
                    }
                }
            }
            "transfer" => {
                if let Some(fa) = tx.from_account_id {
                    *account_balances.entry(fa).or_insert(0) -= amt;
                }
                if let Some(ta) = tx.to_account_id {
                    *account_balances.entry(ta).or_insert(0) += amt;
                }
            }
            _ => {}
        }
    }

    let profit_acc = win - wout - exp;
    let profit_cash = inc - exp - ps;

    // 6. Profit distribution per partner
    let mut partner_allocations = HashMap::new();
    if share_basis == "cash" {
        let pool_shares = allocate_remainder(profit_cash, &participating_partners);
        for p in &participating_partners {
            let total = pool_shares.get(&p.person_id).copied().unwrap_or(0);
            let dist = partner_distributions.get(&p.person_id).copied().unwrap_or(0);
            partner_allocations.insert(
                p.person_id.clone(),
                PartnerProfitAllocation {
                    person_id: p.person_id.clone(),
                    direct_profit: 0,
                    pool_share: total,
                    total_profit: total,
                    distribution_payouts: dist,
                    claimable_share: total - dist,
                },
            );
        }
    } else {
        // Accrual basis
        if share_method == "by_work" {
            let pool_amount = win_shared - wout_shared - exp_shared;
            let pool_shares = allocate_remainder(pool_amount, &participating_partners);
            for p in &participating_partners {
                let direct = direct_profits.get(&p.person_id).copied().unwrap_or(0);
                let pool = pool_shares.get(&p.person_id).copied().unwrap_or(0);
                let total = direct + pool;
                let dist = partner_distributions.get(&p.person_id).copied().unwrap_or(0);
                partner_allocations.insert(
                    p.person_id.clone(),
                    PartnerProfitAllocation {
                        person_id: p.person_id.clone(),
                        direct_profit: direct,
                        pool_share: pool,
                        total_profit: total,
                        distribution_payouts: dist,
                        claimable_share: total - dist,
                    },
                );
            }
        } else {
            // fixed_percent
            let shares = allocate_remainder(profit_acc, &participating_partners);
            for p in &participating_partners {
                let total = shares.get(&p.person_id).copied().unwrap_or(0);
                let dist = partner_distributions.get(&p.person_id).copied().unwrap_or(0);
                partner_allocations.insert(
                    p.person_id.clone(),
                    PartnerProfitAllocation {
                        person_id: p.person_id.clone(),
                        direct_profit: 0,
                        pool_share: total,
                        total_profit: total,
                        distribution_payouts: dist,
                        claimable_share: total - dist,
                    },
                );
            }
        }
    }

    // 7. Custody calculation: Cust(p) = - bal(personal_account_held_by_p)
    let mut custodies = HashMap::new();
    for (acc_id, holder_id) in &personal_account_holder_map {
        let bal = account_balances.get(acc_id).copied().unwrap_or(0);
        *custodies.entry(holder_id.clone()).or_insert(0) -= bal;
    }

    // 8. PersonBalance calculation: Due(p) = Pay(p) + Share(p) + Cust(p)
    let mut all_involved_persons: HashSet<String> = HashSet::new();
    all_involved_persons.extend(all_project_person_ids);
    all_involved_persons.extend(payables.keys().cloned());
    all_involved_persons.extend(custodies.keys().cloned());

    let mut person_balances = HashMap::new();
    let mut total_due = 0i64;

    for pid in all_involved_persons {
        let pay = payables.get(&pid).copied().unwrap_or(0);
        let share = partner_allocations
            .get(&pid)
            .map(|a| a.claimable_share)
            .unwrap_or(0);
        let custody = custodies.get(&pid).copied().unwrap_or(0);
        let due = if share_basis == "cash" {
            share + custody
        } else {
            pay + share + custody
        };

        person_balances.insert(
            pid.clone(),
            PersonBalance {
                person_id: pid,
                pay,
                share,
                custody,
                due,
            },
        );
        total_due += due;
    }

    // 9. Accounts categorized
    let mut project_account_balances = HashMap::new();
    let mut personal_account_balances = HashMap::new();
    let mut total_project_accounts_bal = 0i64;

    for (aid, bal) in account_balances {
        if cash_account_kind_map.get(&aid).map(|s| s.as_str()) == Some("project") {
            project_account_balances.insert(aid, bal);
            total_project_accounts_bal += bal;
        } else {
            personal_account_balances.insert(aid, bal);
        }
    }

    let total_rec: i64 = receivables.values().sum();
    let total_pay: i64 = payables.values().sum();
    let total_cust: i64 = custodies.values().sum();

    // 10. Golden equation verification: bal(project) + Rec == Due
    let is_balanced = (total_project_accounts_bal + total_rec) == total_due;

    Ok(ProjectBalanceReport {
        project_id: project_id.to_string(),
        report_basis,
        share_basis,
        share_method,
        win,
        wout,
        exp,
        inc,
        ps,
        pd,
        profit_accrual: profit_acc,
        profit_cash,
        project_account_balances,
        personal_account_balances,
        total_project_accounts_balance: total_project_accounts_bal,
        receivables,
        total_receivables: total_rec,
        payables,
        total_payables: total_pay,
        custodies,
        total_custody: total_cust,
        partner_allocations,
        person_balances,
        total_due,
        is_golden_equation_balanced: is_balanced,
        start_date_iso: start_date_iso.map(String::from),
        end_date_iso: end_date_iso.map(String::from),
    })
}
