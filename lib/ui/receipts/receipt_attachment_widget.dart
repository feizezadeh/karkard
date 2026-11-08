import 'package:flutter/material.dart';
import '../../core/platform_ports.dart';
import 'receipt_ui_helpers.dart';

/// Interactive pre-save receipt attachment widget embedded into NewTransactionDialog.
/// Keeps picked files in memory until the transaction is successfully committed.
class ReceiptAttachmentWidget extends StatelessWidget {
  final List<PickedFile> pendingFiles;
  final ValueChanged<List<PickedFile>> onChanged;
  final ReceiptPicker? picker;
  final bool isEnabled;

  const ReceiptAttachmentWidget({
    super.key,
    required this.pendingFiles,
    required this.onChanged,
    this.picker,
    this.isEnabled = true,
  });

  Future<void> _pickFile(BuildContext context) async {
    try {
      PickedFile? file;
      if (picker != null) {
        file = await picker!.pick();
      }

      if (file == null) return;

      // Validate allowed extension
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      const allowed = {'jpg', 'jpeg', 'png', 'webp', 'pdf'};
      if (!allowed.contains(ext)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تنها فایل‌های تصویری (JPG, PNG, WEBP) و PDF مجاز هستند.')),
          );
        }
        return;
      }

      // Check file size (max 20MB)
      if (file.bytes.length > 20 * 1024 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حجم فایل بیش از حد مجاز است (حداکثر ۲۰ مگابایت).')),
          );
        }
        return;
      }

      final updated = List<PickedFile>.from(pendingFiles)..add(file);
      onChanged(updated);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در انتخاب فایل: $e')),
        );
      }
    }
  }

  void _removeFile(int index) {
    final updated = List<PickedFile>.from(pendingFiles)..removeAt(index);
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.attach_file, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'پیوست رسید و فاکتور (${pendingFiles.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isEnabled ? () => _pickFile(context) : null,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('انتخاب فایل'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pendingFiles.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            ),
            child: const Center(
              child: Text(
                'می‌توانید تصویر یا فایل PDF فاکتور را پیوست کنید (اختیاری).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < pendingFiles.length; i++)
                _buildFileChip(context, pendingFiles[i], i),
            ],
          ),
      ],
    );
  }

  Widget _buildFileChip(BuildContext context, PickedFile file, int index) {
    final isPdf = isPdfMime(file.mime, file.name);

    return Container(
      width: 240,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 38,
              height: 38,
              child: isPdf
                  ? Container(
                      color: Colors.red.shade100,
                      child: Icon(Icons.picture_as_pdf, color: Colors.red.shade800, size: 20),
                    )
                  : Image.memory(file.bytes, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatFileSize(file.bytes.length),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            tooltip: 'حذف',
            onPressed: isEnabled ? () => _removeFile(index) : null,
          ),
        ],
      ),
    );
  }
}
