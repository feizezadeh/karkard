import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/money.dart';
import '../../main.dart';
import '../../services/backup_service.dart';
import '../fiscal_year/fiscal_years_screen.dart';
import 'about_us_screen.dart';
import 'safe_restore_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final bool asTab;
  const SettingsScreen({super.key, this.asTab = false});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _currentDir = '';
  bool _isDefaultDir = true;
  bool _isDirWritable = true;
  bool _isLoadingDir = true;
  bool _isBackingUp = false;
  bool _isLoadingBackups = true;
  List<BackupMetadata> _backups = [];

  @override
  void initState() {
    super.initState();
    _loadDirectoryAndBackups();
  }

  Future<void> _loadDirectoryAndBackups() async {
    setState(() {
      _isLoadingDir = true;
      _isLoadingBackups = true;
    });

    final backupService = ref.read(backupServiceProvider);
    String currentPath = '';
    bool isCustom = false;
    bool writable = true;
    List<BackupMetadata> backups = [];

    try {
      final customPath = await backupService.getCustomBackupPath();
      isCustom = customPath != null;
      final dir = await backupService.getEffectiveBackupDirectory();
      currentPath = dir.path;
      writable = await backupService.isPathWritable(currentPath);
      backups = await backupService.listBackups();
    } catch (_) {
      final customPath = await backupService.getCustomBackupPath();
      currentPath = customPath ?? 'نامشخص';
      isCustom = customPath != null;
      writable = false;
    }

    if (mounted) {
      setState(() {
        _currentDir = currentPath;
        _isDefaultDir = !isCustom;
        _isDirWritable = writable;
        _backups = backups;
        _isLoadingDir = false;
        _isLoadingBackups = false;
      });
    }
  }

  Future<void> _pickCustomDirectory() async {
    final picker = ref.read(directoryPickerProvider);
    final chosenPath = await picker?.pickDirectory();
    if (chosenPath == null || !mounted) return;

    final backupService = ref.read(backupServiceProvider);
    try {
      await backupService.setCustomBackupDirectory(chosenPath);
      await _loadDirectoryAndBackups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مسیر پشتیبان‌گیری به‌روزرسانی شد.')),
        );
      }
    } catch (e, st) {
      debugPrint('MANUAL_BACKUP_ERROR: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('خطا در تنظیم مسیر: $e'),
          ),
        );
      }
    }
  }

  Future<void> _resetToDefaultDirectory() async {
    final backupService = ref.read(backupServiceProvider);
    await backupService.resetToDefaultBackupDirectory();
    await _loadDirectoryAndBackups();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مسیر پشتیبان‌گیری به حالت پیش‌فرض بازگردانده شد.')),
      );
    }
  }

  Future<void> _performManualBackup() async {
    setState(() => _isBackingUp = true);
    final backupService = ref.read(backupServiceProvider);
    try {
      final metadata = await backupService.performBackup(isStartup: false);
      await _loadDirectoryAndBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text('نسخه پشتیبان با موفقیت ایجاد شد: ${metadata.fileName}'),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('MANUAL_BACKUP_ERROR: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('خطا در پشتیبان‌گیری: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _confirmDeleteBackup(BackupMetadata backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نسخه پشتیبان'),
        content: Text('آیا از حذف فایل ${backup.fileName} اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final file = File(backup.filePath);
      if (file.existsSync()) file.deleteSync();
      await _loadDirectoryAndBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل پشتیبان با موفقیت حذف شد.')),
        );
      }
    }
  }

  Future<void> _openRestoreDialog(BackupMetadata backup) async {
    final backupService = ref.read(backupServiceProvider);
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => SafeRestoreDialog(
          candidate: backup,
          backupService: backupService,
        ),
      ),
    );

    if (restored == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('بازیابی پایگاه داده با موفقیت انجام شد.'),
        ),
      );
      // Restart application state cleanly
      await runKarkardApp();
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return toFaDigits('$bytes بایت');
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).toStringAsFixed(1);
      return toFaDigits('$kb کیلوبایت');
    }
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(2);
    return toFaDigits('$mb مگابایت');
  }

  String _formatJalali(DateTime dt) {
    final j = Gregorian.fromDateTime(dt).toJalali();
    final d = '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    return toFaDigits('$d ساعت $t');
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // App Branding Header Card
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const AboutUsScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/logo/karkard_logo.png',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'دفتر کارکرد (Karkard Ledger)',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'سامانه مدیریت مالی، پیمانکاری و عملیات کارگاهی',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              toFaDigits('نسخه ۲.۰.۰ • کاملاً آفلاین و محلی'),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_left,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Section: Fiscal Years & Rollover
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.calendar_month_outlined),
                ),
                title: const Text('مدیریت سال‌های مالی و بستن دوره', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('تعریف سال مالی جدید، بستن حساب‌ها و انتقال خودکار مانده‌ها (سند افتتاحیه)'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const FiscalYearsScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Section 1: Backup Directory
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'مسیر ذخیره فایل‌های پشتیبان',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isLoadingDir ? 'در حال بارگذاری مسیر...' : _currentDir,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          textDirection: TextDirection.ltr,
                        ),
                        if (!_isDirWritable) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.error),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'هشدار: مسیر پشتیبان‌گیری در دسترس نیست یا مجوز نوشتن ندارد! لطفاً مسیر دیگری انتخاب کنید یا به مسیر پیش‌فرض بازگردید.',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onErrorContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickCustomDirectory,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('انتخاب پوشه سفارشی'),
                            ),
                            const SizedBox(width: 12),
                            if (!_isDefaultDir)
                              OutlinedButton.icon(
                                onPressed: _resetToDefaultDirectory,
                                icon: const Icon(Icons.restore_page_outlined),
                                label: const Text('بازنشانی به پیش‌فرض'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Section 2: Manual Backup
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'پشتیبان‌گیری فوری دستی',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ایجاد نسخه پشتیبان کامل از آخرین وضعیت پایگاه داده و فایل‌های رسید.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: (_isBackingUp || !_isDirWritable) ? null : _performManualBackup,
                          icon: _isBackingUp
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.backup_outlined),
                          label: const Text('پشتیبان‌گیری اکنون'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Section 3: Available Backups List
                Row(
                  children: [
                    Text(
                      'نسخه‌های پشتیبان موجود',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        toFaDigits(_backups.length.toString()),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_isLoadingBackups)
                  const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                else if (_backups.isEmpty)
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'هیچ نسخه پشتیبانی یافت نشد. برای ایجاد، دکمه «پشتیبان‌گیری اکنون» را بزنید.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  )
                else
                  ..._backups.map((b) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(Icons.storage, color: Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(
                            b.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                            textDirection: TextDirection.ltr,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('زمان: ${_formatJalali(b.createdAt)} | حجم: ${_formatFileSize(b.fileSize)}'),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'شناسه هش: ${b.shortSha256}...',
                                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey.shade600),
                                      textDirection: TextDirection.ltr,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 14),
                                    tooltip: 'کپی کد هش کامل',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: b.sha256));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('کد هش در حافظه کپی شد.')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.restore, size: 16),
                                label: const Text('بازیابی'),
                                onPressed: () => _openRestoreDialog(b),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                                tooltip: 'حذف',
                                onPressed: () => _confirmDeleteBackup(b),
                              ),
                            ],
                          ),
                        ),
                      )),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    title: const Text('درباره ما و اطلاعات سازنده', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('مهدی فیضی زاده • وب‌سایت، ایمیل و ویژگی‌ها'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const AboutUsScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );

    if (widget.asTab) {
      return bodyContent;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تنظیمات و پشتیبان‌گیری'),
        ),
        body: bodyContent,
      ),
    );
  }
}
