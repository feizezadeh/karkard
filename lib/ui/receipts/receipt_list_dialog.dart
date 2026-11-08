import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../core/money.dart';
import '../../core/platform_ports.dart';
import '../../data/database.dart';
import '../../domain/tx_type.dart';
import '../../services/receipt_service.dart';
import 'receipt_missing_placeholder.dart';
import 'receipt_ui_helpers.dart';
import 'receipt_viewer_dialog.dart';

/// Modal dialog displaying all receipts attached to a transaction.
/// Supports viewing, deleting (for open projects), and attaching new files.
class ReceiptListDialog extends StatefulWidget {
  final Transaction transaction;
  final bool isProjectLocked;
  final ReceiptService receiptService;
  final ReceiptPicker? picker;

  const ReceiptListDialog({
    super.key,
    required this.transaction,
    required this.isProjectLocked,
    required this.receiptService,
    this.picker,
  });

  @override
  State<ReceiptListDialog> createState() => _ReceiptListDialogState();
}

class _ReceiptListDialogState extends State<ReceiptListDialog> {
  Future<void> _addReceipt() async {
    if (widget.isProjectLocked) return;

    try {
      final picked = await widget.picker?.pick();
      if (picked == null) return;

      await widget.receiptService.saveReceipt(
        transactionId: widget.transaction.id,
        file: picked,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره رسید: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(Receipt receipt) async {
    if (widget.isProjectLocked) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید حذف رسید'),
        content: Text('آیا از حذف رسید "${receipt.fileName ?? receipt.filePath}" مطمئن هستید؟ این عملیات غیرقابل بازگشت است.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.receiptService.deleteReceipt(receipt.id);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطا در حذف رسید: $e')),
          );
        }
      }
    }
  }

  void _openViewer(Receipt receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptViewerDialog(
          receipt: receipt,
          receiptService: widget.receiptService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txType = TxType.fromDb(widget.transaction.type);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اسناد و رسیدهای پیوست'),
          actions: [
            if (!widget.isProjectLocked)
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined),
                tooltip: 'افزودن رسید',
                onPressed: _addReceipt,
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
            ),
          ],
        ),
        floatingActionButton: widget.isProjectLocked
            ? null
            : FloatingActionButton.extended(
                onPressed: _addReceipt,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('افزودن رسید جدید'),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Transaction metadata chip banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تراکنش: ${txType.label} • مبلغ: ${formatToman(widget.transaction.amount)} تومان • تاریخ: ${isoToJalali(widget.transaction.date)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Receipts list stream
                    Expanded(
                      child: StreamBuilder<List<Receipt>>(
                        stream: widget.receiptService.watchReceiptsForTransaction(widget.transaction.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                          }

                          final receipts = snapshot.data ?? [];
                          if (receipts.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    const Text('هیچ رسیدی برای این تراکنش پیوست نشده است.', style: TextStyle(color: Colors.grey)),
                                    if (!widget.isProjectLocked) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: _addReceipt,
                                        icon: const Icon(Icons.add),
                                        label: const Text('پیوست اولین رسید'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: receipts.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final r = receipts[i];
                              return _ReceiptRowTile(
                                key: ValueKey(r.id),
                                receipt: r,
                                isProjectLocked: widget.isProjectLocked,
                                receiptService: widget.receiptService,
                                onOpenViewer: () => _openViewer(r),
                                onConfirmDelete: () => _confirmDelete(r),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptRowTile extends StatefulWidget {
  final Receipt receipt;
  final bool isProjectLocked;
  final ReceiptService receiptService;
  final VoidCallback onOpenViewer;
  final VoidCallback onConfirmDelete;

  const _ReceiptRowTile({
    super.key,
    required this.receipt,
    required this.isProjectLocked,
    required this.receiptService,
    required this.onOpenViewer,
    required this.onConfirmDelete,
  });

  @override
  State<_ReceiptRowTile> createState() => _ReceiptRowTileState();
}

class _ReceiptRowTileState extends State<_ReceiptRowTile> {
  late final Future<File?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = _resolveFile();
  }

  Future<File?> _resolveFile() async {
    try {
      final exists = await widget.receiptService.receiptExists(widget.receipt.filePath);
      if (!exists) return null;
      return await widget.receiptService.getReceiptFile(widget.receipt.filePath);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final isPdf = isPdfMime(receipt.mime, receipt.fileName ?? receipt.filePath);

    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (context, snapshot) {
        final file = snapshot.data;
        final exists = file != null;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: exists
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: isPdf
                        ? Container(
                            color: Colors.red.shade50,
                            child: Icon(Icons.picture_as_pdf, color: Colors.red.shade800, size: 28),
                          )
                        : Image.file(file, fit: BoxFit.cover),
                  ),
                )
              : const ReceiptMissingPlaceholder(compact: true),
          title: Text(
            receipt.fileName ?? receipt.filePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            '${formatFileSize(receipt.fileSize)} • ثبت: ${isoToJalali(receipt.createdAt.split('T').first)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20),
                tooltip: 'مشاهده رسید',
                onPressed: widget.onOpenViewer,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: widget.isProjectLocked ? 'پروژه قفل است؛ امکان حذف وجود ندارد' : 'حذف رسید',
                onPressed: widget.isProjectLocked ? null : widget.onConfirmDelete,
              ),
            ],
          ),
        );
      },
    );
  }
}
