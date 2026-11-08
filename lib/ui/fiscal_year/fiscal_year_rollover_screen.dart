import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/jalali.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../main.dart';
import '../../services/balance_service.dart';

class FiscalYearRolloverScreen extends ConsumerStatefulWidget {
  final Project sourceProject;

  const FiscalYearRolloverScreen({
    super.key,
    required this.sourceProject,
  });

  @override
  ConsumerState<FiscalYearRolloverScreen> createState() => _FiscalYearRolloverScreenState();
}

class _FiscalYearRolloverScreenState extends ConsumerState<FiscalYearRolloverScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _startDateController;

  bool _lockSource = true;
  bool _isLoading = true;
  bool _isExecuting = false;
  ProjectBalanceReport? _balanceReport;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final nowJ = Jalali.now();
    // Default smart name suggestion: if source contains digits, increment year, else current year
    final match = RegExp(r'\d+').firstMatch(widget.sourceProject.name);
    final nextYear = match != null ? (int.tryParse(match.group(0)!) ?? nowJ.year) + 1 : nowJ.year;
    _nameController = TextEditingController(text: 'سال مالی $nextYear');
    _startDateController = TextEditingController(text: '$nextYear/01/01');

    _loadSourceBalance();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startDateController.dispose();
    super.dispose();
  }

  Future<void> _loadSourceBalance() async {
    setState(() => _isLoading = true);
    final db = ref.read(dbProvider);
    final report = await BalanceService(db).calculateProjectBalance(widget.sourceProject.id);
    if (mounted) {
      setState(() {
        _balanceReport = report;
        _isLoading = false;
      });
    }
  }

  Future<void> _executeRollover() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isExecuting = true;
      _errorMessage = null;
    });

    try {
      final fiscalYearService = ref.read(fiscalYearServiceProvider);
      final newProjectId = await fiscalYearService.closeAndRollover(
        sourceProjectId: widget.sourceProject.id,
        targetYearName: _nameController.text.trim(),
        startDateJalali: _startDateController.text.trim(),
        lockSource: _lockSource,
      );

      // Invalidate stream and active project providers
      ref.invalidate(projectsStreamProvider);
      ref.invalidate(transactionsStreamProvider);
      ref.invalidate(projectBalanceProvider);
      ref.read(activeProjectIdProvider.notifier).select(newProjectId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Text('سال مالی جدید «${_nameController.text.trim()}» با موفقیت افتتاح و فعال شد.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isExecuting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بستن و انتقال سال مالی'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      children: [
                        // Card 1: Source Year Summary
                        Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.history, color: colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'سال مالی مبدأ: ${widget.sourceProject.name}',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statItem('موجودی نقد و بانک', formatToman(_balanceReport!.totalProjectAccountsBalance), Colors.teal.shade800),
                                    ),
                                    Expanded(
                                      child: _statItem('طلب از کارفرمایان', formatToman(_balanceReport!.totalReceivables), Colors.indigo.shade800),
                                    ),
                                    Expanded(
                                      child: _statItem('بدهی‌ها و تعهدات', formatToman(_balanceReport!.totalDue), Colors.orange.shade900),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _balanceReport!.isGoldenEquationBalanced
                                        ? Colors.green.shade50
                                        : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _balanceReport!.isGoldenEquationBalanced
                                          ? Colors.green.shade300
                                          : Colors.amber.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _balanceReport!.isGoldenEquationBalanced
                                            ? Icons.check_circle_outline
                                            : Icons.warning_amber_rounded,
                                        color: _balanceReport!.isGoldenEquationBalanced
                                            ? Colors.green.shade800
                                            : Colors.amber.shade900,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _balanceReport!.isGoldenEquationBalanced
                                              ? 'تراز طلایی برقرار است: مانده نقد و مطالبات دقیقاً برابر با دیون و تعهدات است.'
                                              : 'هشدار: معادله تراز پروژه ناهمگون است. مانده‌ها با همان وضعیت موجود منتقل خواهند شد.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _balanceReport!.isGoldenEquationBalanced
                                                ? Colors.green.shade900
                                                : Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Card 2: Target Year Configuration
                        Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.start, color: colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'مشخصات سال مالی جدید (مقصد)',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'نام سال مالی جدید *',
                                    hintText: 'مثال: سال مالی ۱۴۰۵',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.edit_calendar_outlined),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'لطفاً نام سال مالی را وارد کنید';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _startDateController,
                                  decoration: const InputDecoration(
                                    labelText: 'تاریخ شروع سال مالی (جلالی) *',
                                    hintText: '۱۴۰۵/۰۱/۰۱',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.date_range_outlined),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'تاریخ شروع الزامی است';
                                    try {
                                      parseJalaliStringToIso(v);
                                    } catch (_) {
                                      return 'فرمت تاریخ نامعتبر است (مثال: ۱۴۰۵/۰۱/۰۱)';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('قفل کردن قطعی سال مالی گذشته (پیشنهادی)'),
                                  subtitle: const Text(
                                    'پس از انتقال، سال مالی قبل قفل می‌شود تا از تغییر اتفاقی اسناد جلوگیری شود.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _lockSource,
                                  onChanged: (v) => setState(() => _lockSource = v),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Card 3: Notice of Opening Entries
                        Card(
                          elevation: 0,
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.auto_awesome, color: colorScheme.primary, size: 24),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'انتقال هوشمند اسناد افتتاحیه',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'تمامی مانده‌های حساب‌های بانکی، صندوق‌ها، طلب از کارفرمایان و بدهی‌ها و شرکا به طور خودکار به عنوان سند افتتاحیه سال جدید درج می‌شوند و اطلاعات پایه (طرف‌حساب‌ها، حساب‌ها و تنظیمات درصد شرکا) به دوره جدید منتقل خواهند شد.',
                                        style: TextStyle(fontSize: 12.5, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_errorMessage!, style: TextStyle(color: colorScheme.onErrorContainer)),
                          ),
                        ],

                        const SizedBox(height: 28),

                        FilledButton.icon(
                          icon: _isExecuting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(
                            _isExecuting ? 'در حال صدور اسناد و بستن دوره...' : 'تأیید و اجرای بستن و افتتاح سال مالی',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _isExecuting ? null : _executeRollover,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
