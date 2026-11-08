use crate::error::{KarkardError, Result};
use crate::money::to_fa_digits;

/// Checks if a Gregorian year is a leap year.
pub fn is_gregorian_leap(gy: i32) -> bool {
    (gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0)
}

/// Checks if a Jalali year is a leap year using the standard 33-year cycle.
pub fn is_jalali_leap(jy: i32) -> bool {
    let breaks = [-61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210,
        1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178];
    let mut jp = breaks[0];
    let mut jump;
    if jy < jp || jy >= breaks[breaks.len() - 1] {
        let r = (jy % 33) + if jy % 33 < 0 { 33 } else { 0 };
        return [1, 5, 9, 13, 17, 22, 26, 30].contains(&r);
    }

    for &b in &breaks[1..] {
        let jm = b;
        jump = jm - jp;
        if jy < jm {
            let n = jy - jp;
            let mut leap = n % 33;
            if jump >= 33 {
                leap = (n - 4) % 33;
            }
            return [1, 5, 9, 13, 17, 22, 26, 30].contains(&leap);
        }
        jp = jm;
    }
    false
}

/// Returns the number of days in a given Jalali month.
pub fn jalali_month_days(jy: i32, jm: i32) -> i32 {
    if jm >= 1 && jm <= 6 {
        31
    } else if jm >= 7 && jm <= 11 {
        30
    } else if jm == 12 {
        if is_jalali_leap(jy) { 30 } else { 29 }
    } else {
        0
    }
}

/// Converts Gregorian date to Jalali (Solar Hijri) date.
pub fn gregorian_to_jalali(gy: i32, gm: i32, gd: i32) -> (i32, i32, i32) {
    let g_days_in_month = [31, if is_gregorian_leap(gy) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut g_day_no = 0;
    for i in 0..(gm - 1) as usize {
        g_day_no += g_days_in_month[i];
    }
    g_day_no += gd - 1;

    let gy2 = gy - 1600;
    let g_day_no_total: i64 = 365 * gy2 as i64 + (gy2 + 3) as i64 / 4 - (gy2 + 99) as i64 / 100 + (gy2 + 399) as i64 / 400 + g_day_no as i64;

    let mut j_day_no_total = g_day_no_total - 79;
    let j_np = j_day_no_total / 12053;
    j_day_no_total %= 12053;

    let mut jy = 979 + 33 * j_np as i32 + 4 * (j_day_no_total as i32 / 1461);
    j_day_no_total %= 1461;

    if j_day_no_total >= 366 {
        jy += ((j_day_no_total - 1) / 365) as i32;
        j_day_no_total = (j_day_no_total - 1) % 365;
    }

    let (jm, jd) = if j_day_no_total < 186 {
        (1 + (j_day_no_total / 31) as i32, 1 + (j_day_no_total % 31) as i32)
    } else {
        (7 + ((j_day_no_total - 186) / 30) as i32, 1 + ((j_day_no_total - 186) % 30) as i32)
    };

    (jy, jm, jd)
}

/// Converts Jalali date to Gregorian date.
pub fn jalali_to_gregorian(jy: i32, jm: i32, jd: i32) -> (i32, i32, i32) {
    let jy2 = jy - 979;
    let j_day_no_total = 365 * jy2 as i64 + (jy2 / 33) as i64 * 8 + ((jy2 % 33 + 3) / 4) as i64
        + if jm < 7 { (jm - 1) as i64 * 31 } else { ((jm - 7) as i64 * 30) + 186 }
        + (jd - 1) as i64;

    let mut g_day_no_total = j_day_no_total + 79;
    let mut gy = 1600 + 400 * (g_day_no_total / 146097) as i32;
    g_day_no_total %= 146097;

    let mut leap = true;
    if g_day_no_total >= 36525 {
        g_day_no_total -= 1;
        gy += 100 * (g_day_no_total / 36524) as i32;
        g_day_no_total %= 36524;
        if g_day_no_total >= 365 {
            g_day_no_total += 1;
        } else {
            leap = false;
        }
    }

    gy += 4 * (g_day_no_total / 1461) as i32;
    g_day_no_total %= 1461;

    if g_day_no_total >= 366 {
        leap = false;
        g_day_no_total -= 1;
        gy += (g_day_no_total / 365) as i32;
        g_day_no_total %= 365;
    }

    let g_days_in_month = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut gm = 0;
    while gm < 12 && g_day_no_total >= g_days_in_month[gm] {
        g_day_no_total -= g_days_in_month[gm];
        gm += 1;
    }

    (gy, gm as i32 + 1, g_day_no_total as i32 + 1)
}

/// Converts Jalali year, month, day to ISO Gregorian string "YYYY-MM-DD".
pub fn jalali_to_iso(y: i32, m: i32, d: i32) -> Result<String> {
    let max_days = jalali_month_days(y, m);
    if m < 1 || m > 12 || d < 1 || d > max_days {
        return Err(KarkardError::Validation(format!(
            "تاریخ شمسی نامعتبر: {}/{:02}/{:02}",
            y, m, d
        )));
    }
    let (gy, gm, gd) = jalali_to_gregorian(y, m, d);
    Ok(format!("{:04}-{:02}-{:02}", gy, gm, gd))
}

/// Converts ISO Gregorian string "YYYY-MM-DD" to Jalali string "۱۴۰۳/۱۲/۲۹" with Persian digits.
pub fn iso_to_jalali(iso: &str) -> Result<String> {
    let parts: Vec<&str> = iso.split('-').collect();
    if parts.len() != 3 {
        return Err(KarkardError::Validation(format!("تاریخ ISO نامعتبر: {}", iso)));
    }
    let gy: i32 = parts[0].parse().map_err(|_| KarkardError::Validation(format!("سال نامعتبر: {}", parts[0])))?;
    let gm: i32 = parts[1].parse().map_err(|_| KarkardError::Validation(format!("ماه نامعتبر: {}", parts[1])))?;
    let gd: i32 = parts[2].parse().map_err(|_| KarkardError::Validation(format!("روز نامعتبر: {}", parts[2])))?;

    let (jy, jm, jd) = gregorian_to_jalali(gy, gm, gd);
    let out = format!("{:04}/{:02}/{:02}", jy, jm, jd);
    Ok(to_fa_digits(&out))
}

/// Converts ISO Gregorian string "YYYY-MM-DD" to Jalali string "1403/12/29" with Latin digits for inputs.
pub fn iso_to_jalali_latin(iso: &str) -> Result<String> {
    let parts: Vec<&str> = iso.split('-').collect();
    if parts.len() != 3 {
        return Err(KarkardError::Validation(format!("تاریخ ISO نامعتبر: {}", iso)));
    }
    let gy: i32 = parts[0].parse().map_err(|_| KarkardError::Validation(format!("سال نامعتبر: {}", parts[0])))?;
    let gm: i32 = parts[1].parse().map_err(|_| KarkardError::Validation(format!("ماه نامعتبر: {}", parts[1])))?;
    let gd: i32 = parts[2].parse().map_err(|_| KarkardError::Validation(format!("روز نامعتبر: {}", parts[2])))?;

    let (jy, jm, jd) = gregorian_to_jalali(gy, gm, gd);
    Ok(format!("{:04}/{:02}/{:02}", jy, jm, jd))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_round_trip() {
        let dates = [
            (1402, 1, 1),
            (1403, 12, 29),
            (1404, 6, 31),
            (1405, 8, 17),
        ];
        for (jy, jm, jd) in dates {
            let (gy, gm, gd) = jalali_to_gregorian(jy, jm, jd);
            let (jy_back, jm_back, jd_back) = gregorian_to_jalali(gy, gm, gd);
            assert_eq!((jy, jm, jd), (jy_back, jm_back, jd_back));
        }
    }

    #[test]
    fn test_known_date() {
        // 2024-03-20 is 1403-01-01
        let (jy, jm, jd) = gregorian_to_jalali(2024, 3, 20);
        assert_eq!((jy, jm, jd), (1403, 1, 1));
    }
}
