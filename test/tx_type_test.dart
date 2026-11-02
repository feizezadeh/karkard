import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/domain/tx_type.dart';

void main() {
  test('tx type labels are fixed and never the bare word «واریز»', () {
    expect({for (final t in TxType.values) t.dbValue: t.label}, {
      'work_in': 'کارکرد (طلب از کارفرما)',
      'work_out': 'کارکرد (بدهی به شخص)',
      'income': 'دریافتی',
      'expense': 'هزینه',
      'payout': 'پرداخت به شخص',
      'transfer': 'انتقال بین حساب‌ها',
    });
    expect(TxType.values.map((t) => t.label), isNot(contains('واریز')));
  });

  test('fromDb roundtrip and throws on unknown', () {
    for (final t in TxType.values) {
      expect(TxType.fromDb(t.dbValue), t);
    }
    expect(() => TxType.fromDb('bogus'), throwsArgumentError);
  });
}
