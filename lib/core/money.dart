import 'errors.dart';

const _fa = '۰۱۲۳۴۵۶۷۸۹';

String toFaDigits(String s) =>
    s.replaceAllMapped(RegExp(r'\d'), (m) => _fa[int.parse(m[0]!)]);

/// Default thousands separator: Persian «٬» (U+066C), with Persian digits.
const defaultThousandsSeparator = '٬';

/// Integer toman -> "۱٬۲۳۴٬۵۶۷". Separator is configurable; digits are Persian
/// unless [persianDigits] is false.
String formatToman(int amount,
    {String separator = defaultThousandsSeparator, bool persianDigits = true}) {
  final neg = amount < 0;
  final s = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(separator);
    b.write(s[i]);
  }
  final out = '${neg ? '-' : ''}$b';
  return persianDigits ? toFaDigits(out) : out;
}

/// Parses Persian/Arabic/Latin digits and separators. Throws on garbage.
int parseToman(String input) {
  var s = input.trim();
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(_fa[i], '$i').replaceAll(ar[i], '$i');
  }
  s = s.replaceAll(RegExp('[,٬،\\s]'), '');
  final v = int.tryParse(s);
  if (v == null) throw KarkardException('مبلغ نامعتبر: "$input"');
  return v;
}

/// Exact integer floor division (rounds towards negative infinity),
/// without floating-point conversions. Safe for large 64-bit integers.
int floorDiv(int a, int b) {
  if (b == 0) throw UnsupportedError('Division by zero');
  final q = a ~/ b;
  final r = a.remainder(b);
  if (r != 0 && ((a ^ b) < 0)) {
    return q - 1;
  }
  return q;
}
