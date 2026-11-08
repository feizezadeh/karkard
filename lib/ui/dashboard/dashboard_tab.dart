import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../main.dart';
import '../base_data/manage_accounts_dialog.dart';
import '../fiscal_year/fiscal_years_screen.dart';
import '../import/excel_import_wizard.dart';
import '../settings/about_us_screen.dart';
import 'charts.dart';

class DashboardTab extends ConsumerWidget {
  final String activeProjectId;
  final VoidCallback onNewTx;
  final void Function(int tabIndex) onNavigateToTab;

  const DashboardTab({
    super.key,
    required this.activeProjectId,
    required this.onNewTx,
    required this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final balanceReportAsync = ref.watch(projectBalanceProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final projectsAsync = ref.watch(projectsStreamProvider);

    final activeProject = projectsAsync.asData?.value.firstWhere(
      (p) => p.id == activeProjectId,
      orElse: () => Project(
        id: activeProjectId,
        name: 'پروژه جاری',
        status: 'open',
        createdAt: '',
        updatedAt: '',
      ),
    );

    return balanceReportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('خطا در بارگذاری خلاصه وضعیت: $err')),
      data: (report) {
        if (report == null) {
          return const Center(child: Text('پروژه‌ای انتخاب نشده است.'));
        }

        final txList = transactionsAsync.asData?.value ?? [];
        final isLocked = activeProject?.status == 'locked';

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // 1. Executive Status & Golden Balance Banner
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
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.primary,
                      child: const Icon(Icons.analytics_outlined),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                activeProject?.name ?? 'دفتر کارکرد',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              if (isLocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.amber.shade700),
                                  ),
                                  child: Text(
                                    'بسته / فقط خواندنی',
                                    style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            toFaDigits('${txList.length} تراکنش ثبت‌شده در این دوره'),
                            style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: report.isGoldenEquationBalanced ? Colors.green.shade50 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: report.isGoldenEquationBalanced ? Colors.green.shade600 : Colors.amber.shade700,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            report.isGoldenEquationBalanced ? Icons.verified : Icons.warning_amber_rounded,
                            size: 16,
                            color: report.isGoldenEquationBalanced ? Colors.green.shade800 : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            report.isGoldenEquationBalanced ? 'تراز طلایی برقرار است' : 'ناهمگونی در تراز',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: report.isGoldenEquationBalanced ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 2. Financial KPI Cards Grid
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 650;
                return GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 1.6 : 1.35,
                  children: [
                    _kpiCard(
                      context,
                      title: 'موجودی نقد و بانک',
                      amount: report.totalProjectAccountsBalance,
                      color: Colors.teal.shade800,
                      bgColor: Colors.teal.shade50,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _kpiCard(
                      context,
                      title: 'طلب از کارفرمایان',
                      amount: report.totalReceivables,
                      color: Colors.indigo.shade800,
                      bgColor: Colors.indigo.shade50,
                      icon: Icons.assignment_turned_in_outlined,
                    ),
                    _kpiCard(
                      context,
                      title: 'بدهی‌ها و تعهدات',
                      amount: report.totalDue,
                      color: Colors.orange.shade900,
                      bgColor: Colors.orange.shade50,
                      icon: Icons.hourglass_bottom_outlined,
                    ),
                    _kpiCard(
                      context,
                      title: 'سود تعهدی دوره',
                      amount: report.profitAccrual,
                      color: report.profitAccrual >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                      bgColor: report.profitAccrual >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                      icon: Icons.trending_up,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // 3. Quick Navigation & Shortcuts
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bolt, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'دسترسی سریع به بخش‌ها',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _shortcutChip(
                          icon: Icons.add,
                          label: 'تراکنش جدید',
                          color: colorScheme.primary,
                          textColor: colorScheme.onPrimary,
                          isFilled: true,
                          onTap: isLocked ? null : onNewTx,
                        ),
                        _shortcutChip(
                          icon: Icons.receipt_long,
                          label: 'دفتر تراکنش‌ها',
                          onTap: () => onNavigateToTab(1),
                        ),
                        _shortcutChip(
                          icon: Icons.file_upload_outlined,
                          label: 'ورود از اکسل',
                          onTap: isLocked
                              ? null
                              : () {
                                  final db = ref.read(dbProvider);
                                  final importSource = ref.read(fileImportSourceProvider);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => ExcelImportWizard(
                                        db: db,
                                        projectId: activeProjectId,
                                        importSource: importSource,
                                        onImportComplete: () {
                                          ref.invalidate(transactionsStreamProvider);
                                          ref.invalidate(projectBalanceProvider);
                                        },
                                      ),
                                    ),
                                  );
                                },
                        ),
                        _shortcutChip(
                          icon: Icons.analytics_outlined,
                          label: 'گزارش‌ها و چاپ PDF',
                          onTap: () => onNavigateToTab(2),
                        ),
                        _shortcutChip(
                          icon: Icons.people_alt_outlined,
                          label: 'طرف‌حساب‌ها',
                          onTap: () => onNavigateToTab(3),
                        ),
                        _shortcutChip(
                          icon: Icons.calendar_month_outlined,
                          label: 'مدیریت سال‌های مالی',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (ctx) => const FiscalYearsScreen()),
                            );
                          },
                        ),
                        _shortcutChip(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'صندوق و بانک‌ها',
                          onTap: () {
                            final db = ref.read(dbProvider);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (ctx) => ManageAccountsDialog(db: db)),
                            ).then((_) => ref.invalidate(projectBalanceProvider));
                          },
                        ),
                        _shortcutChip(
                          icon: Icons.settings_outlined,
                          label: 'پشتیبان‌گیری و تنظیمات',
                          onTap: () => onNavigateToTab(4),
                        ),
                        _shortcutChip(
                          icon: Icons.info_outline,
                          label: 'درباره ما',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (ctx) => const AboutUsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 4. Charts Section (Responsive Row / Column)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 700;

                final lineChartCard = Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.show_chart, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'روند عملکرد و تراکنش‌ها',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildTrendLineChart(txList),
                      ],
                    ),
                  ),
                );

                final donutChartCard = Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.donut_large, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'ترکیب مبالغ دوره',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SimpleDonutChart(
                          segments: {
                            'کارکردها': (value: report.win, color: Colors.teal.shade700),
                            'درآمد نقدی': (value: report.inc, color: Colors.blue.shade700),
                            'هزینه کارگاه': (value: report.exp, color: Colors.red.shade700),
                            'پرداخت اشخاص': (value: report.ps + report.pd, color: Colors.amber.shade800),
                          },
                        ),
                      ],
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: lineChartCard),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: donutChartCard),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      lineChartCard,
                      const SizedBox(height: 14),
                      donutChartCard,
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 16),

            // 5. Recent Activity List
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'آخرین تراکنش‌ها',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () => onNavigateToTab(1),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('مشاهده همه'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (txList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('هنوز تراکنشی در این دوره ثبت نشده است.', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      ...txList.take(5).map((tx) {
                        final isPositive = tx.type == 'work_in' || tx.type == 'income';
                        final color = isPositive ? Colors.green.shade800 : Colors.red.shade800;
                        final sign = isPositive ? '+' : '-';
                        final jDate = Gregorian.fromDateTime(DateTime.parse(tx.date)).toJalali();
                        final dateStr = toFaDigits('${jDate.year}/${jDate.month.toString().padLeft(2, '0')}/${jDate.day.toString().padLeft(2, '0')}');

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                              color: color,
                              size: 16,
                            ),
                          ),
                          title: Text(
                            tx.description.isNotEmpty ? tx.description : _typeLabel(tx.type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: Text(dateStr, style: const TextStyle(fontSize: 11)),
                          trailing: Text(
                            toFaDigits('$sign${formatToman(tx.amount)} تومان'),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrendLineChart(List<Transaction> txList) {
    if (txList.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: Text('تراکنشی برای رسم نمودار وجود ندارد.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    // Group transactions by month or take last N points
    final points = <double>[];
    final labels = <String>[];

    // Take last up to 6 transactions or chunks
    final sample = txList.take(7).toList().reversed.toList();
    for (final tx in sample) {
      points.add(tx.amount / 1000000.0);
      final j = Gregorian.fromDateTime(DateTime.parse(tx.date)).toJalali();
      labels.add(toFaDigits('${j.month}/${j.day}'));
    }

    return SimpleLineChart(
      values: points,
      labels: labels,
      height: 140,
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required String title,
    required int amount,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const Spacer(),
          Text(
            toFaDigits('${formatToman(amount)} تومان'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _shortcutChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
    Color? textColor,
    bool isFilled = false,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: isFilled ? textColor : color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isFilled ? FontWeight.bold : FontWeight.w600,
          color: isFilled ? textColor : null,
        ),
      ),
      backgroundColor: isFilled ? color : null,
      onPressed: onTap,
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'work_in':
        return 'کارکرد / صورت‌وضعیت';
      case 'income':
        return 'دریافت نقدی از کارفرما';
      case 'expense':
        return 'هزینه کارگاه';
      case 'work_out':
        return 'دستمزد راننده/کارگر';
      case 'payout':
        return 'تسویه / پرداخت';
      case 'transfer':
        return 'انتقال داخلی';
      default:
        return type;
    }
  }
}
