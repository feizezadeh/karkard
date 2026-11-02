enum TxType {
  workIn('work_in', 'کارکرد (طلب از کارفرما)'),
  workOut('work_out', 'کارکرد (بدهی به شخص)'),
  income('income', 'دریافتی'),
  expense('expense', 'هزینه'),
  payout('payout', 'پرداخت به شخص'),
  transfer('transfer', 'انتقال بین حساب‌ها');

  final String dbValue;
  final String label;

  const TxType(this.dbValue, this.label);

  static TxType fromDb(String value) {
    for (final t in TxType.values) {
      if (t.dbValue == value) return t;
    }
    throw ArgumentError.value(value, 'value', 'Unknown transaction type');
  }
}
