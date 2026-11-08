use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use crate::error::{KarkardError, Result};

const FA_DIGITS: [char; 10] = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
const AR_DIGITS: [char; 10] = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartnerShareItem {
    pub person_id: String,
    pub share_bp: i32,
    pub share_order: i32,
}

/// Exact integer floor division (rounds towards negative infinity),
/// without floating-point conversions. Safe for large 64-bit integers.
pub fn floor_div(a: i64, b: i64) -> i64 {
    assert!(b != 0, "Division by zero");
    let q = a / b;
    let r = a % b;
    if r != 0 && ((a ^ b) < 0) {
        q - 1
    } else {
        q
    }
}

/// Converts ASCII digits to Persian digits.
pub fn to_fa_digits(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '0'..='9' => FA_DIGITS[(c as u8 - b'0') as usize],
            _ => c,
        })
        .collect()
}

/// Converts Persian and Arabic digits to ASCII digits '0'..'9'.
pub fn normalize_digits(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if let Some(pos) = FA_DIGITS.iter().position(|&fc| fc == c) {
            out.push((b'0' + pos as u8) as char);
        } else if let Some(pos) = AR_DIGITS.iter().position(|&ac| ac == c) {
            out.push((b'0' + pos as u8) as char);
        } else {
            out.push(c);
        }
    }
    out
}

/// Integer toman -> formatted string with thousands separator.
/// Default separator is Persian "٬" (U+066C), with Persian digits if `persian_digits` is true.
pub fn format_toman(amount: i64, persian_digits: bool) -> String {
    let neg = amount < 0;
    let s = amount.abs().to_string();
    let mut formatted = String::new();
    let len = s.len();

    for (i, c) in s.chars().enumerate() {
        if i > 0 && (len - i) % 3 == 0 {
            formatted.push('٬');
        }
        formatted.push(c);
    }

    let out = if neg {
        format!("-{}", formatted)
    } else {
        formatted
    };

    if persian_digits {
        to_fa_digits(&out)
    } else {
        out
    }
}

/// Parses Persian/Arabic/Latin digits and separators into integer Toman.
pub fn parse_toman(input: &str) -> Result<i64> {
    let norm = normalize_digits(input.trim());
    let cleaned: String = norm
        .chars()
        .filter(|&c| c != ',' && c != '٬' && c != '،' && !c.is_whitespace())
        .collect();

    cleaned.parse::<i64>().map_err(|_| {
        KarkardError::Validation(format!("مبلغ نامعتبر: \"{}\"", input))
    })
}

/// Distributes an integer amount (positive, zero, or negative)
/// among partners according to their share_bp (basis points, 10000 = 100%)
/// using the Largest Remainder Method (Hamilton-Hare) with share_order tie-breaking.
///
/// Guarantees:
/// 1. Exactly integer amounts (no floats).
/// 2. Sum of allocated amounts == amount exactly.
pub fn allocate_remainder(amount: i64, partners: &[PartnerShareItem]) -> HashMap<String, i64> {
    if partners.is_empty() {
        return HashMap::new();
    }
    if amount == 0 {
        return partners
            .iter()
            .map(|p| (p.person_id.clone(), 0))
            .collect();
    }

    let mut parts: HashMap<String, i64> = HashMap::with_capacity(partners.len());
    let mut remainders: HashMap<String, i64> = HashMap::with_capacity(partners.len());
    let mut sum_parts: i64 = 0;

    for p in partners {
        let product = (p.share_bp as i64) * amount;
        let part = floor_div(product, 10000);
        parts.insert(p.person_id.clone(), part);
        sum_parts += part;
        let rem = product - part * 10000;
        remainders.insert(p.person_id.clone(), rem);
    }

    let leftover = (amount - sum_parts) as usize;

    let mut sorted: Vec<&PartnerShareItem> = partners.iter().collect();
    sorted.sort_by(|a, b| {
        let rem_a = remainders.get(&a.person_id).copied().unwrap_or(0);
        let rem_b = remainders.get(&b.person_id).copied().unwrap_or(0);
        let cmp_rem = rem_b.cmp(&rem_a);
        if cmp_rem != std::cmp::Ordering::Equal {
            cmp_rem
        } else {
            a.share_order.cmp(&b.share_order)
        }
    });

    for i in 0..leftover.min(sorted.len()) {
        let pid = &sorted[i].person_id;
        if let Some(val) = parts.get_mut(pid) {
            *val += 1;
        }
    }

    parts
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_floor_div() {
        assert_eq!(floor_div(7, 3), 2);
        assert_eq!(floor_div(-7, 3), -3);
        assert_eq!(floor_div(7, -3), -3);
        assert_eq!(floor_div(-7, -3), 2);
        assert_eq!(floor_div(6, 3), 2);
        assert_eq!(floor_div(-6, 3), -2);
    }

    #[test]
    fn test_golden_g4_remainder() {
        let partners = vec![
            PartnerShareItem { person_id: "p1".into(), share_bp: 3333, share_order: 1 },
            PartnerShareItem { person_id: "p2".into(), share_bp: 3333, share_order: 2 },
            PartnerShareItem { person_id: "p3".into(), share_bp: 3334, share_order: 3 },
        ];

        // S = 7
        let res_pos = allocate_remainder(7, &partners);
        assert_eq!(res_pos["p1"], 2);
        assert_eq!(res_pos["p2"], 2);
        assert_eq!(res_pos["p3"], 3);
        assert_eq!(res_pos.values().sum::<i64>(), 7);

        // S = -7
        let res_neg = allocate_remainder(-7, &partners);
        assert_eq!(res_neg.values().sum::<i64>(), -7);
    }
}
