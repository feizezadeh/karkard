import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/jalali.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../main.dart';
import '../../services/balance_service.dart';
import '../../services/statement_pdf_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  final bool asTab;
  const ReportsScreen({super.key, this.asTab = false});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | 'non_zero' | 'creditors' | 'debtors'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setDatePreset(String key) {
    if (key == 'all') {
      ref.read(reportDateFilterProvider.notifier).setFilter(const ReportDateFilter(
        startDateIso: null,
        endDateIso: null,
        presetKey: 'all',
        label: 'کل دوره',
      ));
    } else if (key == 'current_month') {
      final p = JalaliDatePresets.currentMonth();
      ref.read(reportDateFilterProvider.notifier).setFilter(ReportDateFilter(
        startDateIso: p.startIso,
        endDateIso: p.endIso,
        presetKey: 'current_month',
        label: p.label,
      ));
    } else if (key == 'last_90_days') {
      final p = JalaliDatePresets.last90Days();
      ref.read(reportDateFilterProvider.notifier).setFilter(ReportDateFilter(
        startDateIso: p.startIso,
        endDateIso: p.endIso,
        presetKey: 'last_90_days',
        label: p.label,
      ));
    } else if (key == 'current_year') {
      final p = JalaliDatePresets.currentYear();
      ref.read(reportDateFilterProvider.notifier).setFilter(ReportDateFilter(
        startDateIso: p.startIso,
        endDateIso: p.endIso,
        presetKey: 'current_year',
        label: p.label,
      ));
    } else if (key == 'custom') {
      _openCustomDateDialog();
    }
  }

  Future<void> _openCustomDateDialog() async {
    final now = Jalali.now();
    final todayJalali = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final fromController = TextEditingController(text: '${now.year}/${now.month.toString().padLeft(2, '0')}/01');
    final toController = TextEditingController(text: todayJalali);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انتخاب بازه زمانی دلخواه'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fromController,
                  decoration: const InputDecoration(
                    labelText: 'از تاریخ (شمسی)',
                    hintText: '۱۴۰۳/۰۷/۰۱',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: toController,
                  decoration: const InputDecoration(
                    labelText: 'تا تاریخ (شمسی)',
                    hintText: '۱۴۰۳/۰۷/۳۰',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('اعمال فیلتر'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final startIso = parseJalaliStringToIso(fromController.text);
        final endIso = parseJalaliStringToIso(toController.text);
        ref.read(reportDateFilterProvider.notifier).setFilter(ReportDateFilter(
          startDateIso: startIso,
          endDateIso: endIso,
          presetKey: 'custom',
          label: 'از ${fromController.text} تا ${toController.text}',
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('خطا در تاریخ وارد شده: $e'),
          ),
        );
      }
    }
  }

  Future<void> _exportPersonStatement(Person person, String projectId) async {
    final activeDateFilter = ref.read(reportDateFilterProvider);
    final hasActiveFilter = !activeDateFilter.isAllTime;

    // Show date period option dialog
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text('صورت‌حساب چاپی: ${person.name}'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Row(
                children: [
                  Icon(Icons.all_inclusive, size: 20),
                  SizedBox(width: 12),
                  Text('کل دوره مالی پروژه'),
                ],
              ),
            ),
            if (hasActiveFilter)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'current_filter'),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text('بازه فیلتر گزارش (${activeDateFilter.label})'),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'custom'),
              child: const Row(
                children: [
                  Icon(Icons.date_range_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('بازه زمانی دلخواه...'),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    String? startIso;
    String? endIso;

    if (choice == 'current_filter') {
      startIso = activeDateFilter.startDateIso;
      endIso = activeDateFilter.endDateIso;
    } else if (choice == 'custom') {
      final now = Jalali.now();
      final fromController = TextEditingController(text: '${now.year}/${now.month.toString().padLeft(2, '0')}/01');
      final toController = TextEditingController(text: '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('بازه زمانی صورت‌حساب'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: fromController, decoration: const InputDecoration(labelText: 'از تاریخ')),
                const SizedBox(height: 12),
                TextField(controller: toController, decoration: const InputDecoration(labelText: 'تا تاریخ')),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید و چاپ')),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        startIso = parseJalaliStringToIso(fromController.text);
        endIso = parseJalaliStringToIso(toController.text);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تاریخ نامعتبر: $e')));
        return;
      }
    }

    try {
      final db = ref.read(dbProvider);
      final pdfService = StatementPdfService(db);
      final report = await pdfService.generateReportData(
        projectId: projectId,
        personId: person.id,
        startDateIso: startIso,
        endDateIso: endIso,
      );
      final pdfBytes = await pdfService.generatePdfBytes(report);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'صورت‌حساب_${person.name}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('خطا در تولید صورت‌حساب: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeProjectId = ref.watch(activeProjectIdProvider);
    final balanceReportAsync = ref.watch(projectBalanceProvider);
    final personsMap = ref.watch(personsMapProvider).value ?? {};
    final projectsAsync = ref.watch(projectsStreamProvider);
    final dateFilter = ref.watch(reportDateFilterProvider);

    final currentProject = projectsAsync.value?.cast<Project?>().firstWhere(
          (p) => p?.id == activeProjectId,
          orElse: () => null,
        );

    if (activeProjectId == null || activeProjectId.isEmpty) {
      const emptyMsg = Center(child: Text('لطفاً ابتدا یک پروژه را انتخاب کنید.'));
      return widget.asTab ? emptyMsg : const Scaffold(body: emptyMsg);
    }

    final content = balanceReportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('خطا در بارگذاری گزارش: $err')),
      data: (report) {
        if (report == null) {
          return const Center(child: Text('هیچ اطلاعات مالی برای این پروژه موجود نیست.'));
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Date Range Filter Bar
            _buildDateFilterBar(context, dateFilter),
            const SizedBox(height: 12),

            // 2. Overview KPIs
            _buildOverviewCard(context, report),
            const SizedBox(height: 16),

            // 3. Golden Equation Card
            _buildGoldenEquationCard(context, report),
            const SizedBox(height: 16),

            // 4. Section Title & Search/Status Filter Bar
            _buildSearchAndStatusFilterBar(context),
            const SizedBox(height: 12),

            // 5. Tabs for Persons
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'کارفرمایان (طلب‌ها)'),
                  Tab(text: 'پرسنل و رانندگان'),
                  Tab(text: 'شرکا و سود'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // TabBar content area
            SizedBox(
              height: 380,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Clients (Receivables)
                  _buildClientsTab(context, report, personsMap, activeProjectId),
                  // Tab 2: Payees / Drivers (Payables)
                  _buildPayeesTab(context, report, personsMap, activeProjectId),
                  // Tab 3: Partners (Shares & Dist)
                  _buildPartnersTab(context, report, personsMap, activeProjectId),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.asTab) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(currentProject != null ? 'گزارش‌های مالی: ${currentProject.name}' : 'گزارش‌های مالی'),
      ),
      body: content,
    );
  }

  Widget _buildDateFilterBar(BuildContext context, ReportDateFilter currentFilter) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.date_range, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'بازه زمانی گزارش:',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('همه دوره'),
                selected: currentFilter.presetKey == 'all',
                onSelected: (_) => _setDatePreset('all'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('ماه جاری'),
                selected: currentFilter.presetKey == 'current_month',
                onSelected: (_) => _setDatePreset('current_month'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('۳ ماه اخیر'),
                selected: currentFilter.presetKey == 'last_90_days',
                onSelected: (_) => _setDatePreset('last_90_days'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('سال مالی'),
                selected: currentFilter.presetKey == 'current_year',
                onSelected: (_) => _setDatePreset('current_year'),
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 16),
                label: Text(currentFilter.presetKey == 'custom' ? currentFilter.label : 'سفارشی...'),
                backgroundColor: currentFilter.presetKey == 'custom'
                    ? theme.colorScheme.primaryContainer
                    : null,
                onPressed: () => _setDatePreset('custom'),
              ),
            ],
          ),
        ),
        if (!currentFilter.isAllTime) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_alt, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'فیلتر فعال: ${currentFilter.label}',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _setDatePreset('all'),
                  child: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchAndStatusFilterBar(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.assignment_ind_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'مانده حساب‌ها و صورت‌حساب اشخاص',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'جستجوی نام شخص یا کارفرما...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('همه'),
                selected: _statusFilter == 'all',
                onSelected: (_) => setState(() => _statusFilter = 'all'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('فقط مانده‌دار'),
                selected: _statusFilter == 'non_zero',
                onSelected: (_) => setState(() => _statusFilter = 'non_zero'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('طلبکاران'),
                selected: _statusFilter == 'creditors',
                onSelected: (_) => setState(() => _statusFilter = 'creditors'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('بدهکاران'),
                selected: _statusFilter == 'debtors',
                onSelected: (_) => setState(() => _statusFilter = 'debtors'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCard(BuildContext context, ProjectBalanceReport report) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'خلاصه عملکرد مالی پروژه',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _kpiBox(
                    context,
                    title: 'سود تعهدی ناخالص',
                    amount: report.profitAccrual,
                    color: Colors.teal.shade800,
                    icon: Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiBox(
                    context,
                    title: 'سود نقدی محقق‌شده',
                    amount: report.profitCash,
                    color: Colors.blue.shade800,
                    icon: Icons.account_balance,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _kpiBox(
                    context,
                    title: 'موجودی نقد و بانک',
                    amount: report.totalProjectAccountsBalance,
                    color: Colors.cyan.shade900,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiBox(
                    context,
                    title: 'طلب کل از کارفرمایان',
                    amount: report.totalReceivables,
                    color: Colors.indigo.shade800,
                    icon: Icons.call_received,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiBox(
    BuildContext context, {
    required String title,
    required int amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatToman(amount)} تومان',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldenEquationCard(BuildContext context, ProjectBalanceReport report) {
    final theme = Theme.of(context);
    final balanced = report.isGoldenEquationBalanced;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: balanced ? Colors.teal.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: balanced ? Colors.teal.shade200 : Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(
            balanced ? Icons.verified : Icons.warning_amber_rounded,
            color: balanced ? Colors.teal.shade800 : Colors.amber.shade900,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balanced ? 'معادله تراز طلایی کاملاً برقرار است' : 'نیازمند بررسی مغایرت تراز',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: balanced ? Colors.teal.shade900 : Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'موجودی نقد (${formatToman(report.totalProjectAccountsBalance)}) + طلب (${formatToman(report.totalReceivables)}) = تعهدات اشخاص (${formatToman(report.totalDue)})',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientsTab(
    BuildContext context,
    ProjectBalanceReport report,
    Map<String, Person> personsMap,
    String projectId,
  ) {
    var entries = report.receivables.entries.toList();

    // 1. Search filter
    if (_searchQuery.isNotEmpty) {
      entries = entries.where((e) {
        final name = personsMap[e.key]?.name ?? '';
        return name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // 2. Status filter
    if (_statusFilter == 'non_zero') {
      entries = entries.where((e) => e.value != 0).toList();
    } else if (_statusFilter == 'creditors') {
      // Clients where project owes them (advance prepayment negative receivable)
      entries = entries.where((e) => e.value < 0).toList();
    } else if (_statusFilter == 'debtors') {
      // Clients who owe project (positive receivable)
      entries = entries.where((e) => e.value > 0).toList();
    }

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != 'all'
                  ? 'هیچ کارفرمایی مطابق با فیلترها یافت نشد.'
                  : 'هیچ کارفرمایی ثبت نشده است.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final entry = entries[idx];
        final person = personsMap[entry.key];
        final name = person?.name ?? 'کارفرما (کد: ${entry.key})';
        final amount = entry.value;

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8EAF6),
              foregroundColor: Color(0xFF283593),
              child: Icon(Icons.business),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              amount > 0 ? 'طلب پروژه از کارفرما' : (amount < 0 ? 'پیش‌پرداخت کارفرما' : 'تسویه کامل'),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${formatToman(amount.abs())} ت',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF283593),
                  ),
                ),
                const SizedBox(width: 8),
                if (person != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'صورت‌حساب چاپی PDF',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => _exportPersonStatement(person, projectId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayeesTab(
    BuildContext context,
    ProjectBalanceReport report,
    Map<String, Person> personsMap,
    String projectId,
  ) {
    var entries = report.payables.entries.toList();

    // 1. Search filter
    if (_searchQuery.isNotEmpty) {
      entries = entries.where((e) {
        final name = personsMap[e.key]?.name ?? '';
        return name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // 2. Status filter
    if (_statusFilter == 'non_zero') {
      entries = entries.where((e) => e.value != 0).toList();
    } else if (_statusFilter == 'creditors') {
      // Payees who have wages due (positive payable)
      entries = entries.where((e) => e.value > 0).toList();
    } else if (_statusFilter == 'debtors') {
      // Payees who took advances (negative payable)
      entries = entries.where((e) => e.value < 0).toList();
    }

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != 'all'
                  ? 'هیچ شخصی مطابق با فیلترها یافت نشد.'
                  : 'هیچ بستانکاری ثبت نشده است.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final entry = entries[idx];
        final person = personsMap[entry.key];
        final name = person?.name ?? 'شخص (کد: ${entry.key})';
        final amount = entry.value;

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE0F2F1),
              foregroundColor: Color(0xFF00695C),
              child: Icon(Icons.local_shipping),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              amount > 0 ? 'طلب شخص از پروژه' : (amount < 0 ? 'مساعده / بدهکار به پروژه' : 'تسویه کامل'),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${formatToman(amount.abs())} ت',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: amount >= 0 ? Colors.teal.shade800 : Colors.red.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                if (person != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'صورت‌حساب چاپی PDF',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => _exportPersonStatement(person, projectId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartnersTab(
    BuildContext context,
    ProjectBalanceReport report,
    Map<String, Person> personsMap,
    String projectId,
  ) {
    var entries = report.partnerAllocations.entries.toList();

    // 1. Search filter
    if (_searchQuery.isNotEmpty) {
      entries = entries.where((e) {
        final name = personsMap[e.key]?.name ?? '';
        return name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // 2. Status filter
    if (_statusFilter == 'non_zero') {
      entries = entries.where((e) => e.value.claimableShare != 0).toList();
    } else if (_statusFilter == 'creditors') {
      entries = entries.where((e) => e.value.claimableShare > 0).toList();
    } else if (_statusFilter == 'debtors') {
      entries = entries.where((e) => e.value.claimableShare < 0).toList();
    }

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != 'all'
                  ? 'هیچ شریکی مطابق با فیلترها یافت نشد.'
                  : 'هیچ شریک دارای سودی در این پروژه ثبت نشده است.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final entry = entries[idx];
        final person = personsMap[entry.key];
        final name = person?.name ?? 'شریک (کد: ${entry.key})';
        final alloc = entry.value;

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFF3E5F5),
                            foregroundColor: Color(0xFF6A1B9A),
                            child: Icon(Icons.handshake),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (person != null)
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        tooltip: 'صورت‌حساب چاپی PDF',
                        color: Theme.of(context).colorScheme.primary,
                        onPressed: () => _exportPersonStatement(person, projectId),
                      ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('سود مستقیم:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text('${formatToman(alloc.directProfit)} تومان',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('سهم از استخر مشترک:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text('${formatToman(alloc.poolShare)} تومان',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('برداشت‌های توزیع سود:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text('${formatToman(alloc.distributionPayouts)} تومان',
                        style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مانده سهم سود قابل تسویه:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(
                      '${formatToman(alloc.claimableShare)} تومان',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
