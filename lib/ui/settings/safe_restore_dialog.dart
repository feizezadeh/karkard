import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../core/money.dart';
import '../../services/backup_service.dart';

class SafeRestoreDialog extends StatefulWidget {
  final BackupMetadata candidate;
  final IBackupService backupService;

  const SafeRestoreDialog({
    super.key,
    required this.candidate,
    required this.backupService,
  });

  @override
  State<SafeRestoreDialog> createState() => _SafeRestoreDialogState();
}

class _SafeRestoreDialogState extends State<SafeRestoreDialog> {
  DbComparison? _comparison;
  bool _isLoading = true;
  bool _isRestoring = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _inspectCandidate();
  }

  Future<void> _inspectCandidate() async {
    try {
      final comp = await widget.backupService.inspectCandidate(widget.candidate.filePath);
      if (mounted) {
        setState(() {
          _comparison = comp;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _executeRestore() async {
    setState(() => _isRestoring = true);
    try {
      await widget.backupService.restoreBackup(widget.candidate.filePath);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطا در بازیابی: $e';
          _isRestoring = false;
        });
      }
    }
  }

  String _formatTxDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'بدون تراکنش';
    try {
      return isoToJalali(isoDate);
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بازیابی امن پایگاه داده'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('در حال بررسی فایل و مقایسه اطلاعات...'),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Comparison Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مقایسه وضعیت پایگاه داده',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Table(
                                border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                                columnWidths: const {
                                  0: FlexColumnWidth(1.2),
                                  1: FlexColumnWidth(1),
                                  2: FlexColumnWidth(1),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow),
                                    children: const [
                                      Padding(padding: EdgeInsets.all(6), child: Text('مشخصه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('پایگاه فعلی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('نسخه پشتیبان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(6), child: Text('تعداد تراکنش‌ها', style: TextStyle(fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(toFaDigits(_comparison!.currentTxCount.toString()), style: const TextStyle(fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(toFaDigits(_comparison!.candidateTxCount.toString()), style: const TextStyle(fontSize: 12))),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(6), child: Text('آخرین تراکنش', style: TextStyle(fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(_formatTxDate(_comparison!.currentLatestTxDate), style: const TextStyle(fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(_formatTxDate(_comparison!.candidateLatestTxDate), style: const TextStyle(fontSize: 12))),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Warning if candidate has fewer transactions
                        if (_comparison!.candidateTxCount < _comparison!.currentTxCount) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'توجه: این نسخه دارای تراکنش‌های کمتری نسبت به پایگاه داده فعلی است.',
                                    style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // 2. Emergency Backup Reassurance Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'پیش از بازیابی، یک نسخه پشتیبان اضطراری به طور خودکار ذخیره می‌شود.',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _isRestoring ? null : () => Navigator.of(context).pop(false),
                              child: const Text('انصراف'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.error,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              onPressed: (_isLoading || _errorMessage != null || _isRestoring) ? null : _executeRestore,
                              icon: _isRestoring
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.restore_rounded),
                              label: const Text('تأیید و بازیابی'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
