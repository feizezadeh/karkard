/// Explicit domain failure. Never swallowed into a default value.
class KarkardException implements Exception {
  final String message;
  const KarkardException(this.message);
  @override
  String toString() => 'KarkardException: $message';
}
