import '../../core/money.dart';

/// Formats byte count to human-readable Persian size (e.g. «۲٫۴ مگابایت»).
String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes < 1024) {
    return toFaDigits('$bytes بایت');
  } else if (bytes < 1024 * 1024) {
    final kb = (bytes / 1024).toStringAsFixed(1).replaceAll('.', '٫');
    return '${toFaDigits(kb)} کیلوبایت';
  } else {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', '٫');
    return '${toFaDigits(mb)} مگابایت';
  }
}

/// Checks whether MIME or extension indicates an image.
bool isImageMime(String mime, String pathOrName) {
  if (mime.startsWith('image/')) return true;
  final lower = pathOrName.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}

/// Checks whether MIME or extension indicates a PDF document.
bool isPdfMime(String mime, String pathOrName) {
  if (mime == 'application/pdf') return true;
  return pathOrName.toLowerCase().endsWith('.pdf');
}
