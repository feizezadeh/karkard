import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import 'core/domain_exception.dart';
import 'core/jalali.dart';
import 'core/money.dart';
import 'data/database.dart';
import 'domain/tx_type.dart';
import 'core/platform_ports.dart';
import 'services/balance_service.dart';
import 'services/platform_pickers.dart';
import 'services/receipt_service.dart';
import 'services/validation_service.dart';
import 'ui/adaptive_layout.dart';
import 'ui/dashboard/dashboard_tab.dart';
import 'ui/base_data/add_project_dialog.dart';
import 'ui/base_data/manage_accounts_dialog.dart';
import 'ui/base_data/manage_persons_dialog.dart';
import 'ui/base_data/manage_projects_dialog.dart';
import 'ui/legacy_database_screen.dart';
import 'ui/new_transaction_dialog.dart';
import 'ui/import/excel_import_wizard.dart';
import 'ui/platform_shortcuts.dart';
import 'services/backup_service.dart';
import 'ui/receipts/receipt_list_dialog.dart';
import 'ui/reports/reports_screen.dart';
import 'services/fiscal_year_service.dart';
import 'ui/fiscal_year/fiscal_years_screen.dart';
import 'ui/settings/about_us_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/theme.dart';

final dbProvider = Provider<AppDatabase>((ref) =>
    throw StateError('dbProvider must be overridden in main()'));

final projectsStreamProvider = StreamProvider<List<Project>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.projects).watch();
});

class ActiveProjectNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final activeProjectIdProvider =
    NotifierProvider<ActiveProjectNotifier, String?>(ActiveProjectNotifier.new);

final fiscalYearServiceProvider = Provider<FiscalYearService>((ref) {
  final db = ref.watch(dbProvider);
  return FiscalYearService(
    db: db,
    balanceService: BalanceService(db),
  );
});

final transactionsStreamProvider = StreamProvider.autoDispose<List<Transaction>>((ref) {
  final db = ref.watch(dbProvider);
  final activeId = ref.watch(activeProjectIdProvider);
  if (activeId == null) return Stream.value([]);
  return (db.select(db.transactions)
        ..where((t) => t.projectId.equals(activeId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.date)]))
      .watch();
});

class ReportDateFilter {
  final String? startDateIso;
  final String? endDateIso;
  final String presetKey; // 'all' | 'current_month' | 'last_90_days' | 'current_year' | 'custom'
  final String label;

  const ReportDateFilter({
    this.startDateIso,
    this.endDateIso,
    this.presetKey = 'all',
    this.label = 'کل دوره',
  });

  bool get isAllTime => startDateIso == null && endDateIso == null;
}

class ReportDateFilterNotifier extends Notifier<ReportDateFilter> {
  @override
  ReportDateFilter build() => const ReportDateFilter();

  void setFilter(ReportDateFilter filter) => state = filter;
}

final reportDateFilterProvider =
    NotifierProvider<ReportDateFilterNotifier, ReportDateFilter>(ReportDateFilterNotifier.new);

final projectBalanceProvider = FutureProvider.autoDispose<ProjectBalanceReport?>((ref) async {
  final db = ref.watch(dbProvider);
  final activeId = ref.watch(activeProjectIdProvider);
  final dateFilter = ref.watch(reportDateFilterProvider);
  // Re-compute whenever transactions change
  ref.watch(transactionsStreamProvider);
  if (activeId == null) return null;
  return BalanceService(db).calculateProjectBalance(
    activeId,
    startDateIso: dateFilter.startDateIso,
    endDateIso: dateFilter.endDateIso,
  );
});

final personsMapProvider = StreamProvider<Map<String, Person>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.persons).watch().map((list) => {for (final p in list) p.id: p});
});

final accountsMapProvider = StreamProvider<Map<String, CashAccount>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.cashAccounts).watch().map((list) => {for (final a in list) a.id: a});
});

final receiptServiceProvider = Provider<ReceiptService>((ref) {
  final db = ref.watch(dbProvider);
  return ReceiptService(db);
});

final receiptPickerProvider = Provider<ReceiptPicker?>((ref) => const NativeReceiptPicker());
final fileImportSourceProvider = Provider<FileImportSource?>((ref) => const NativeFileImportSource());
final directoryPickerProvider = Provider<DirectoryPicker?>((ref) => const NativeDirectoryPicker());

final backupServiceProvider = Provider<BackupService>((ref) {
  final db = ref.watch(dbProvider);
  return BackupService(db);
});

final transactionReceiptCountsProvider = StreamProvider.autoDispose<Map<String, int>>((ref) {
  final db = ref.watch(dbProvider);
  return db.customSelect(
    'SELECT transaction_id, COUNT(*) AS count FROM receipts GROUP BY transaction_id',
    readsFrom: {db.receipts},
  ).watch().map((rows) => {
    for (final r in rows) r.read<String>('transaction_id'): r.read<int>('count'),
  });
});

Future<List<File>> backupDatabaseFiles(File file) async {
  final backups = <File>[];
  if (!file.existsSync()) return backups;

  final now = DateTime.now();
  final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}-'
      '${now.millisecond.toString().padLeft(3, '0')}';

  final parentDir = file.parent;
  final baseName = file.uri.pathSegments.last;

  // 1. Copy main db file
  final bakDb = File('${parentDir.path}/$baseName.$ts.bak');
  file.copySync(bakDb.path);
  backups.add(bakDb);

  // 2. Copy -shm if present
  final shm = File('${file.path}-shm');
  if (shm.existsSync()) {
    final bakShm = File('${parentDir.path}/$baseName-shm.$ts.bak');
    shm.copySync(bakShm.path);
    backups.add(bakShm);
  }

  // 3. Copy -wal if present
  final wal = File('${file.path}-wal');
  if (wal.existsSync()) {
    final bakWal = File('${parentDir.path}/$baseName-wal.$ts.bak');
    wal.copySync(bakWal.path);
    backups.add(bakWal);
  }

  // Delete original files after backing them up
  file.deleteSync();
  if (shm.existsSync()) shm.deleteSync();
  if (wal.existsSync()) wal.deleteSync();

  return backups;
}

Future<void> runKarkardApp() async {
  try {
    final db = await AppDatabase.openFile();
    // Force physical database file creation and verification
    await db.customSelect('SELECT 1').get();

    // Ensure default initial metadata exists if database is empty
    await _ensureInitialSeed(db);

    // Non-blocking daily startup auto-backup
    final backupService = BackupService(db);
    backupService.performBackup(isStartup: true).then((metadata) {
      debugPrint('Startup auto-backup succeeded: ${metadata.fileName}');
    }).catchError((err) {
      debugPrint('Startup auto-backup skipped or warning: $err');
    });

    runApp(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const KarkardApp(),
    ));
  } on LegacyDatabaseException catch (e) {
    runApp(MaterialApp(
      theme: buildTheme(),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: LegacyDatabaseScreen(
        exception: e,
        onReset: () async {
          final file = await AppDatabase.getDatabaseFile();
          await backupDatabaseFiles(file);
          await runKarkardApp();
        },
      ),
    ));
  }
}

Future<void> _ensureInitialSeed(AppDatabase db) async {
  final projects = await db.select(db.projects).get();
  if (projects.isEmpty) {
    const defaultProjId = 'proj_main';
    await db.into(db.projects).insert(ProjectsCompanion.insert(
      id: defaultProjId,
      name: 'پروژه اصلی',
    ));
    await db.into(db.projectSettings).insert(ProjectSettingsCompanion.insert(
      projectId: defaultProjId,
      reportBasis: const Value('accrual'),
      shareBasis: const Value('accrual'),
      shareMethod: const Value('by_work'),
    ));

    const defaultPartnerId = 'prt_manager';
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: defaultPartnerId,
      name: 'مدیر پروژه',
      kind: 'partner',
    ));

    await db.into(db.projectPersons).insert(ProjectPersonsCompanion.insert(
      projectId: defaultProjId,
      personId: defaultPartnerId,
      settlementMode: const Value('profit_share'),
      shareBp: const Value(10000),
      shareOrder: const Value(1),
    ));

    await db.into(db.cashAccounts).insert(CashAccountsCompanion.insert(
      id: 'acc_main_cash',
      name: 'صندوق اصلی پروژه',
      kind: 'project',
    ));
  }

  // Ensure there is at least one client for usability
  final clients = await (db.select(db.persons)..where((p) => p.kind.equals('client'))).get();
  if (clients.isEmpty) {
    await db.into(db.persons).insert(PersonsCompanion.insert(
      id: 'clt_sample',
      name: 'کارفرمای نمونه (شرکت عمران)',
      kind: 'client',
    ));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runKarkardApp();
}

class KarkardApp extends StatelessWidget {
  const KarkardApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دفتر کارکرد',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('fa', 'IR'),
        supportedLocales: const [Locale('fa', 'IR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const HomeScreen(),
      );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTabIndex = 0;

  void _openNewTxDialog(BuildContext context, WidgetRef ref, String projectId) {
    final db = ref.read(dbProvider);
    final receiptService = ref.read(receiptServiceProvider);
    final picker = ref.read(receiptPickerProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => NewTransactionDialog(
          db: db,
          projectId: projectId,
          receiptService: receiptService,
          picker: picker,
          onSaved: () {
            ref.invalidate(transactionsStreamProvider);
            ref.invalidate(projectBalanceProvider);
          },
        ),
      ),
    );
  }

  static void _openReceiptsDialog(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
    bool isProjectLocked,
  ) {
    final receiptService = ref.read(receiptServiceProvider);
    final picker = ref.read(receiptPickerProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptListDialog(
          transaction: tx,
          isProjectLocked: isProjectLocked,
          receiptService: receiptService,
          picker: picker,
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, String txId) {
    final reasonController = TextEditingController();
    final db = ref.read(dbProvider);
    final validationService = ValidationService(db);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('حذف تراکنش (حذف نرم)'),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'برای حفظ دقت محاسبات و ردگیری در لاگ بازرسی، ثبت دلیل حذف تراکنش الزامی است:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: reasonController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'دلیل حذف تراکنش *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.edit_note),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            final reason = reasonController.text.trim();
                            if (reason.isEmpty) return;
                            try {
                              await validationService.softDeleteTransactionAtomic(txId, reason: reason);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              ref.invalidate(transactionsStreamProvider);
                              ref.invalidate(projectBalanceProvider);
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('خطا در حذف: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('تأیید و حذف تراکنش', style: TextStyle(fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsStreamProvider);
    final activeProjectId = ref.watch(activeProjectIdProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final balanceReportAsync = ref.watch(projectBalanceProvider);
    final personsMap = ref.watch(personsMapProvider).value ?? {};
    final accountsMap = ref.watch(accountsMapProvider).value ?? {};
    final receiptCounts = ref.watch(transactionReceiptCountsProvider).value ?? {};

    // Auto-select first project if none is active
    projectsAsync.whenData((projects) {
      if (projects.isNotEmpty && activeProjectId == null) {
        Future.microtask(() {
          ref.read(activeProjectIdProvider.notifier).select(projects.first.id);
        });
      }
    });

    final currentPid = activeProjectId ?? (projectsAsync.value?.isNotEmpty == true ? projectsAsync.value!.first.id : '');
    final activeProject = projectsAsync.value?.cast<Project?>().firstWhere(
      (p) => p?.id == currentPid,
      orElse: () => null,
    );
    final isProjectLocked = activeProject?.status == 'locked';

    void newTx() {
      if (currentPid.isNotEmpty) {
        _openNewTxDialog(context, ref, currentPid);
      }
    }

    return DesktopShortcuts(
      onNewTx: newTx,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'درباره ما',
            icon: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo/karkard_logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.account_balance_wallet),
              ),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const AboutUsScreen()),
              );
            },
          ),
          title: InkWell(
            onTap: () {
              final db = ref.read(dbProvider);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => ManageProjectsDialog(
                    db: db,
                    activeProjectId: currentPid,
                    onSelectProject: (id) {
                      ref.read(activeProjectIdProvider.notifier).select(id);
                    },
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_center, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      activeProject?.name ?? 'دفتر کارکرد',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('تراکنش جدید', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: currentPid.isEmpty || isProjectLocked ? null : newTx,
            ),
            const SizedBox(width: 4),
            if (isProjectLocked)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 12, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text('قفل', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'ورود از اکسل',
              onPressed: currentPid.isEmpty || isProjectLocked
                  ? null
                  : () {
                      final db = ref.read(dbProvider);
                      final importSource = ref.read(fileImportSourceProvider);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => ExcelImportWizard(
                            db: db,
                            projectId: currentPid,
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
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'صندوق‌ها و حساب‌های بانکی',
              onPressed: () {
                final db = ref.read(dbProvider);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => ManageAccountsDialog(db: db),
                  ),
                ).then((_) {
                  ref.invalidate(projectBalanceProvider);
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'مدیریت سال‌های مالی و بستن دوره',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const FiscalYearsScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_business_outlined),
              tooltip: 'تعریف پروژه جدید',
              onPressed: () async {
                final db = ref.read(dbProvider);
                final created = await Navigator.of(context).push<Project>(
                  MaterialPageRoute(
                    builder: (ctx) => AddProjectDialog(db: db),
                  ),
                );
                if (created != null) {
                  ref.read(activeProjectIdProvider.notifier).select(created.id);
                }
              },
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'داشبورد',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'تراکنش‌ها',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'گزارش‌ها',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt),
              label: 'طرف‌حساب‌ها',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'تنظیمات',
            ),
          ],
        ),
        floatingActionButton: (_currentTabIndex == 0 || _currentTabIndex == 1) ? NewTxButton(onPressed: newTx) : null,
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            // Tab 0: Dashboard (Executive Overview & Charts)
            DashboardTab(
              activeProjectId: currentPid,
              onNewTx: newTx,
              onNavigateToTab: (idx) => setState(() => _currentTabIndex = idx),
            ),
            // Tab 1: Transactions Ledger
            _buildLedgerTab(
              context,
              currentPid,
              balanceReportAsync,
              transactionsAsync,
              personsMap,
              accountsMap,
              receiptCounts,
              isProjectLocked,
              newTx,
            ),
            // Tab 2: Financial Reports & PDF Statements
            const ReportsScreen(asTab: true),
            // Tab 3: Contacts & Counterparties
            ManagePersonsDialog(db: ref.read(dbProvider), projectId: currentPid, asTab: true),
            // Tab 4: Settings & Backup
            const SettingsScreen(asTab: true),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTab(
    BuildContext context,
    String currentPid,
    AsyncValue<ProjectBalanceReport?> balanceReportAsync,
    AsyncValue<List<Transaction>> transactionsAsync,
    Map<String, Person> personsMap,
    Map<String, CashAccount> accountsMap,
    Map<String, int> receiptCounts,
    bool isProjectLocked,
    VoidCallback newTx,
  ) {
    return Column(
      children: [
        // Financial KPI & Golden Equality Bar (Horizontally scrollable for small screens)
        balanceReportAsync.when(
          data: (report) {
            if (report == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _kpiItem('موجودی نقد پروژه', formatToman(report.totalProjectAccountsBalance), Colors.teal.shade800),
                    const SizedBox(width: 20),
                    _kpiItem('طلب از کارفرمایان', formatToman(report.totalReceivables), Colors.indigo.shade800),
                    const SizedBox(width: 20),
                    _kpiItem('مطالبات کل اشخاص', formatToman(report.totalDue), Colors.orange.shade900),
                    const SizedBox(width: 20),
                    Chip(
                      avatar: Icon(
                        report.isGoldenEquationBalanced ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: report.isGoldenEquationBalanced ? Colors.green.shade800 : Colors.red.shade800,
                        size: 18,
                      ),
                      label: Text(
                        report.isGoldenEquationBalanced ? 'تراز طلایی برقرار است' : 'نیازمند تطبیق تراز',
                        style: TextStyle(
                          color: report.isGoldenEquationBalanced ? Colors.green.shade900 : Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: report.isGoldenEquationBalanced ? Colors.green.shade50 : Colors.red.shade50,
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text('خطا در محاسبه تراز: $err', style: const TextStyle(color: Colors.red)),
          ),
        ),

        // Main Ledger Table / Cards
        Expanded(
              child: transactionsAsync.when(
                data: (txList) {
                  if (txList.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text('تراکنشی در این پروژه ثبت نشده است.', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: newTx,
                                  icon: const Icon(Icons.add),
                                  label: const Text('ثبت اولین تراکنش'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    final db = ref.read(dbProvider);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (ctx) => ManagePersonsDialog(db: db, projectId: currentPid),
                                      ),
                                    ).then((_) {
                                      ref.invalidate(transactionsStreamProvider);
                                      ref.invalidate(projectBalanceProvider);
                                    });
                                  },
                                  icon: const Icon(Icons.people_alt_outlined),
                                  label: const Text('اشخاص و کارفرمایان'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return AdaptiveLayout(
                    wide: (_) => LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              columnSpacing: 24,
                              horizontalMargin: 16,
                              columns: const [
                                DataColumn(label: Text('تاریخ')),
                                DataColumn(label: Text('نوع تراکنش')),
                                DataColumn(label: Text('طرف حساب / شخص')),
                                DataColumn(label: Text('حساب نقدی')),
                                DataColumn(label: Text('شرح')),
                                DataColumn(label: Text('مبلغ (تومان)'), numeric: true),
                                DataColumn(label: Text('رسید')),
                                DataColumn(label: Text('عملیات')),
                              ],
                              rows: [
                                for (final tx in txList)
                                  DataRow(cells: [
                                    DataCell(Text(isoToJalali(tx.date))),
                                    DataCell(_txTypeChip(tx.type)),
                                    DataCell(Text(_partyLabel(tx, personsMap))),
                                    DataCell(Text(_accountLabel(tx, accountsMap))),
                                    DataCell(Text(tx.description)),
                                    DataCell(Text(
                                      formatToman(tx.amount),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    )),
                                    DataCell(_buildReceiptCell(context, ref, tx, receiptCounts[tx.id] ?? 0, isProjectLocked)),
                                    DataCell(IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      tooltip: 'حذف تراکنش',
                                      onPressed: () => _showDeleteDialog(context, ref, tx.id),
                                    )),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    narrow: (_) => ListView.builder(
                      itemCount: txList.length,
                      itemBuilder: (ctx, i) {
                        final tx = txList[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            title: Row(
                              children: [
                                _txTypeChip(tx.type),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _partyLabel(tx, personsMap),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatToman(tx.amount),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${isoToJalali(tx.date)} ${tx.description.isNotEmpty ? '• ${tx.description}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildReceiptBadge(context, ref, tx, receiptCounts[tx.id] ?? 0, isProjectLocked),
                                ],
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              onPressed: () => _showDeleteDialog(context, ref, tx.id),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطا در بارگذاری تراکنش‌ها: $e')),
              ),
            ),
          ],
        );
  }

  static Widget _kpiItem(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  static Widget _txTypeChip(String type) {
    try {
      final t = TxType.fromDb(type);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Text(t.label, style: const TextStyle(fontSize: 12)),
      );
    } catch (_) {
      return Text(type);
    }
  }

  static String _partyLabel(Transaction tx, Map<String, Person> persons) {
    if (tx.clientId != null) return persons[tx.clientId!]?.name ?? tx.clientId!;
    if (tx.personId != null) return persons[tx.personId!]?.name ?? tx.personId!;
    return '—';
  }

  static String _accountLabel(Transaction tx, Map<String, CashAccount> accounts) {
    if (tx.cashAccountId != null) return accounts[tx.cashAccountId!]?.name ?? tx.cashAccountId!;
    if (tx.fromAccountId != null && tx.toAccountId != null) {
      final f = accounts[tx.fromAccountId!]?.name ?? tx.fromAccountId!;
      final t = accounts[tx.toAccountId!]?.name ?? tx.toAccountId!;
      return '$f ← $t';
    }
    return '—';
  }

  static Widget _buildReceiptCell(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
    int count,
    bool isProjectLocked,
  ) {
    if (count > 0) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.attach_file, size: 16),
        label: Text(toFaDigits('$count')),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        onPressed: () => _openReceiptsDialog(context, ref, tx, isProjectLocked),
      );
    }

    if (tx.receiptNotRequired) {
      return const Tooltip(
        message: 'رسید لازم ندارد',
        child: Icon(Icons.receipt_outlined, size: 20, color: Colors.grey),
      );
    }

    return IconButton(
      icon: const Icon(Icons.add_photo_alternate_outlined, size: 20, color: Colors.grey),
      tooltip: 'افزودن رسید',
      onPressed: () => _openReceiptsDialog(context, ref, tx, isProjectLocked),
    );
  }

  static Widget _buildReceiptBadge(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
    int count,
    bool isProjectLocked,
  ) {
    if (count > 0) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openReceiptsDialog(context, ref, tx, isProjectLocked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file, size: 14),
              const SizedBox(width: 2),
              Text(toFaDigits('$count'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (tx.receiptNotRequired) {
      return const Tooltip(
        message: 'رسید لازم ندارد',
        child: Icon(Icons.receipt_outlined, size: 16, color: Colors.grey),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openReceiptsDialog(context, ref, tx, isProjectLocked),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.add_photo_alternate_outlined, size: 16, color: Colors.grey),
      ),
    );
  }
}
