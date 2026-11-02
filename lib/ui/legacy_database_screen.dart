import 'package:flutter/material.dart';
import '../core/domain_exception.dart';

class LegacyDatabaseScreen extends StatefulWidget {
  final LegacyDatabaseException exception;
  final Future<void> Function() onReset;

  const LegacyDatabaseScreen({
    super.key,
    required this.exception,
    required this.onReset,
  });

  @override
  State<LegacyDatabaseScreen> createState() => _LegacyDatabaseScreenState();
}

class _LegacyDatabaseScreenState extends State<LegacyDatabaseScreen> {
  bool _isResetting = false;

  Future<void> _handleReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأیید بازنشانی دیتابیس'),
          content: const Text(
            'آیا از حذف تمام داده‌ها و ایجاد مجدد پایگاه داده اطمینان دارید؟ این عملیات غیرقابل بازگشت است.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('بله، بازنشانی شود'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _isResetting = true);
      try {
        await widget.onReset();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در بازنشانی دیتابیس: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isResetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خطای ارتقای دیتابیس'),
          backgroundColor: theme.colorScheme.errorContainer,
          foregroundColor: theme.colorScheme.onErrorContainer,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 72,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'پایگاه داده قدیمی شناسایی شد',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.exception.message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نسخه فعلی: ${widget.exception.fromVersion} | نسخه مورد نیاز: ${widget.exception.toVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_isResetting)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _handleReset,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('بازنشانی دیتابیس'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
