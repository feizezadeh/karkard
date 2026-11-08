import 'package:flutter/material.dart';
import 'receipt_ui_helpers.dart';

/// Graceful placeholder displayed when a receipt database record exists
/// but the physical file is not found on disk. Never crashes with FileSystemException.
class ReceiptMissingPlaceholder extends StatelessWidget {
  final String? fileName;
  final String? relativePath;
  final int? fileSize;
  final bool compact;

  const ReceiptMissingPlaceholder({
    super.key,
    this.fileName,
    this.relativePath,
    this.fileSize,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'فایل فیزیکی رسید روی دیسک یافت نشد',
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade400),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined, size: 24, color: Colors.amber.shade900),
              const SizedBox(height: 2),
              Text(
                'ناموجود',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade300, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 36, color: Colors.amber.shade900),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'فایل رسید روی دیسک یافت نشد',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'اطلاعات این رسید در پایگاه داده ثبت شده است، اما فایل فیزیکی در پوشه نگهداری اسناد موجود نیست.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('نام فایل:', fileName ?? 'نامشخص'),
                  const SizedBox(height: 4),
                  _detailRow('مسیر مورد انتظار:', relativePath ?? '—'),
                  const SizedBox(height: 4),
                  _detailRow('اندازه ثبت‌شده:', formatFileSize(fileSize)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'راهنما: این وضعیت ممکن است به دلیل بازیابی دیتابیس بدون انتقال پوشه receipts یا حذف دستی فایل‌ها رخ داده باشد.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
