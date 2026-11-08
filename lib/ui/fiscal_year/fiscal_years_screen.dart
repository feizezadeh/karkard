import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../main.dart';
import '../../services/fiscal_year_service.dart';
import '../base_data/add_project_dialog.dart';
import 'fiscal_year_rollover_screen.dart';

class FiscalYearsScreen extends ConsumerStatefulWidget {
  const FiscalYearsScreen({super.key});

  @override
  ConsumerState<FiscalYearsScreen> createState() => _FiscalYearsScreenState();
}

class _FiscalYearsScreenState extends ConsumerState<FiscalYearsScreen> {
  List<FiscalYearSummary> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    setState(() => _isLoading = true);
    final service = ref.read(fiscalYearServiceProvider);
    final list = await service.getFiscalYearSummaries();
    if (mounted) {
      setState(() {
        _summaries = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddYear() async {
    final db = ref.read(dbProvider);
    final created = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (ctx) => AddProjectDialog(db: db),
      ),
    );

    if (created != null) {
      ref.invalidate(projectsStreamProvider);
      ref.read(activeProjectIdProvider.notifier).select(created.id);
      await _loadSummaries();
    }
  }

  Future<void> _openRollover(Project source) async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => FiscalYearRolloverScreen(sourceProject: source),
      ),
    );

    if (success == true) {
      await _loadSummaries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeId = ref.watch(activeProjectIdProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت سال‌های مالی و بستن دوره'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'تعریف سال مالی جدید',
              onPressed: _openAddYear,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    children: [
                      // Overview Banner
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, color: colorScheme.primary, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'سال‌های مالی و دوره‌های حسابداری',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'شما می‌توانید سال مالی جدید ایجاد کنید یا در پایان دوره، با بستن سال مالی فعلی، مانده‌های نقد، مطالبات و بدهی‌ها را به صورت خودکار به سال جدید انتقال دهید.',
                                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_summaries.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('هیچ دوره یا سال مالی یافت نشد.'),
                          ),
                        )
                      else
                        ..._summaries.map((s) {
                          final p = s.project;
                          final isActive = p.id == activeId;
                          final isLocked = s.isLocked;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              elevation: 0,
                              color: isActive
                                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                                  : colorScheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isActive
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  width: isActive ? 1.5 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: isActive
                                              ? colorScheme.primary
                                              : colorScheme.surfaceContainerHighest,
                                          foregroundColor:
                                              isActive ? colorScheme.onPrimary : colorScheme.onSurface,
                                          child: Icon(isLocked ? Icons.lock : Icons.business),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    p.name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isActive)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.shade50,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.green.shade700),
                                                      ),
                                                      child: Text(
                                                        'سال مالی فعال',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.green.shade800,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  if (isLocked) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber.shade50,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.amber.shade700),
                                                      ),
                                                      child: Text(
                                                        'بسته و قفل‌شده',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.amber.shade900,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                toFaDigits('${s.transactionCount} تراکنش ثبت‌شده'),
                                                style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _metric('موجودی نقد', formatToman(s.totalProjectAccountsBalance)),
                                        ),
                                        Expanded(
                                          child: _metric('طلب از کارفرمایان', formatToman(s.totalReceivables)),
                                        ),
                                        Expanded(
                                          child: _metric('تعهدات و بدهی‌ها', formatToman(s.totalDue)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (!isActive)
                                          TextButton.icon(
                                            icon: const Icon(Icons.check, size: 16),
                                            label: const Text('انتخاب به عنوان دوره فعال'),
                                            onPressed: () {
                                              ref.read(activeProjectIdProvider.notifier).select(p.id);
                                              setState(() {});
                                            },
                                          ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isLocked ? Colors.grey.shade700 : colorScheme.primary,
                                          ),
                                          icon: const Icon(Icons.swap_horiz, size: 18),
                                          label: Text(isLocked ? 'انتقال مجدد به سال جدید' : 'بستن سال مالی و انتقال دوره'),
                                          onPressed: () => _openRollover(p),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
