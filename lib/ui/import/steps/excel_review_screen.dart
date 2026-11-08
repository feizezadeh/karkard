import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money.dart';
import '../../../data/database.dart';
import '../../../domain/tx_type.dart';
import '../../../services/excel_import_service.dart';

class ExcelReviewScreen extends StatefulWidget {
  final List<ParsedExcelRow> rows;
  final AppDatabase db;
  final String projectId;
  final ValueChanged<List<ParsedExcelRow>> onCommit;
  final VoidCallback? onBack;

  const ExcelReviewScreen({
    super.key,
    required this.rows,
    required this.db,
    required this.projectId,
    required this.onCommit,
    this.onBack,
  });

  @override
  State<ExcelReviewScreen> createState() => _ExcelReviewScreenState();
}

class _ExcelReviewScreenState extends State<ExcelReviewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<ParsedExcelRow> _rows;
  List<Person> _allPersons = [];

  // Controllers for resolving rows
  final Map<int, TextEditingController> _amountControllers = {};
  final Map<int, int?> _selectedCandidateAmounts = {};
  final Map<int, String?> _selectedPersons = {};
  final Map<int, TxType?> _selectedTypes = {};

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.rows);
    _tabController = TabController(length: 3, vsync: this);
    _loadPersons();

    for (final r in _rows) {
      if (r.status == RowStatus.needsDecision) {
        if (r.detectedAmounts.isNotEmpty) {
          _selectedCandidateAmounts[r.rowIndex] = r.detectedAmounts.first;
        }
        if (r.amount != null) {
          _amountControllers[r.rowIndex] = TextEditingController(text: r.amount.toString());
        } else {
          _amountControllers[r.rowIndex] = TextEditingController();
        }
        _selectedTypes[r.rowIndex] = r.inferredType;
      }
    }
  }

  Future<void> _loadPersons() async {
    final persons = await widget.db.select(widget.db.persons).get();
    if (mounted) {
      setState(() {
        _allPersons = persons;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _needsDecisionCount =>
      _rows.where((r) => r.status == RowStatus.needsDecision && !r.userSkipped).length;

  int get _readyCount =>
      _rows.where((r) => r.status == RowStatus.ready && !r.userSkipped).length;

  int get _duplicateCount =>
      _rows.where((r) => r.status == RowStatus.duplicate).length;

  void _skipAllUnresolved() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نادیده گرفتن همه موارد نامشخص'),
        content: const Text(
          'آیا مطمئن هستید که می‌خواهید تمام ردیف‌های نیازمند تصمیم را نادیده بگیرید؟ این ردیف‌ها در دفتر ثبت نخواهند شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                for (var i = 0; i < _rows.length; i++) {
                  if (_rows[i].status == RowStatus.needsDecision) {
                    _rows[i] = _rows[i].copyWith(status: RowStatus.skippedByUser);
                  }
                }
              });
            },
            child: const Text('تأیید و نادیده گرفتن'),
          ),
        ],
      ),
    );
  }

  void _skipRow(ParsedExcelRow row) {
    setState(() {
      final index = _rows.indexWhere((r) => r.rowIndex == row.rowIndex);
      if (index != -1) {
        _rows[index] = _rows[index].copyWith(status: RowStatus.skippedByUser);
      }
    });
  }

  String? _getPersonName(String? personId) {
    if (personId == null) return null;
    return _allPersons.where((p) => p.id == personId).firstOrNull?.name;
  }

  Future<void> _createPartyAsNewClient(String partyName) async {
    final clean = partyName.trim();
    if (clean.isEmpty) return;

    var existing = _allPersons.where((p) => normalizePersianText(p.name) == normalizePersianText(clean)).firstOrNull;
    String personId;
    if (existing != null) {
      personId = existing.id;
      if (existing.kind != 'client') {
        await (widget.db.update(widget.db.persons)..where((p) => p.id.equals(existing.id))).write(
          const PersonsCompanion(kind: Value('client')),
        );
      }
    } else {
      personId = const Uuid().v4();
      await widget.db.into(widget.db.persons).insert(PersonsCompanion.insert(
        id: personId,
        name: clean,
        kind: 'client',
      ));
    }

    await _loadPersons();

    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        final rowParty = r.rawParty?.trim() ?? '';
        if (rowParty == clean || normalizePersianText(rowParty) == normalizePersianText(clean)) {
          final isClientTx = r.inferredType == TxType.workIn || r.inferredType == TxType.income;
          _rows[i] = r.copyWith(
            rawParty: clean,
            clientId: isClientTx ? personId : r.clientId,
            personId: !isClientTx ? personId : r.personId,
            status: r.amount != null ? RowStatus.ready : RowStatus.needsDecision,
            ambiguityReason: r.amount == null ? AmbiguityReason.emptyAmount : null,
            resolutionNote: 'ایجاد طرف‌حساب جدید در سیستم',
          );
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('طرف‌حساب «$clean» به عنوان کارفرما در سیستم ثبت و ردیف‌ها تأیید شدند.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _autoCreateAllMissingParties() async {
    final missingParties = _rows
        .where((r) =>
            r.status == RowStatus.needsDecision &&
            r.ambiguityReason == AmbiguityReason.unknownCounterparty &&
            r.rawParty != null &&
            r.rawParty!.trim().isNotEmpty)
        .map((r) => r.rawParty!.trim())
        .toSet();

    if (missingParties.isEmpty) return;

    const uuid = Uuid();
    for (final partyName in missingParties) {
      final existing = _allPersons
          .where((p) => normalizePersianText(p.name) == normalizePersianText(partyName))
          .firstOrNull;
      if (existing == null) {
        await widget.db.into(widget.db.persons).insert(PersonsCompanion.insert(
          id: uuid.v4(),
          name: partyName,
          kind: 'client',
        ));
      } else if (existing.kind != 'client') {
        await (widget.db.update(widget.db.persons)..where((p) => p.id.equals(existing.id))).write(
          const PersonsCompanion(kind: Value('client')),
        );
      }
    }

    await _loadPersons();

    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        if (r.status == RowStatus.needsDecision &&
            r.ambiguityReason == AmbiguityReason.unknownCounterparty &&
            r.rawParty != null) {
          final matched = _allPersons
              .where((p) => normalizePersianText(p.name) == normalizePersianText(r.rawParty!.trim()))
              .firstOrNull;
          if (matched != null) {
            final isClientTx = r.inferredType == TxType.workIn || r.inferredType == TxType.income;
            _rows[i] = r.copyWith(
              rawParty: matched.name,
              clientId: isClientTx ? matched.id : r.clientId,
              personId: !isClientTx ? matched.id : r.personId,
              status: r.amount != null ? RowStatus.ready : RowStatus.needsDecision,
              ambiguityReason: r.amount == null ? AmbiguityReason.emptyAmount : null,
              resolutionNote: 'ایجاد خودکار طرف‌حساب‌ها',
            );
          }
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعداد ${missingParties.length} طرف‌حساب جدید با موفقیت در سیستم ثبت شدند.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  void _resolveRow(ParsedExcelRow row, {int? amount, TxType? type, String? personId}) {
    setState(() {
      final index = _rows.indexWhere((r) => r.rowIndex == row.rowIndex);
      if (index != -1) {
        final existing = _rows[index];
        final newAmount = amount ?? existing.amount;
        final newType = type ?? existing.inferredType ?? TxType.expense;
        final newPersonId = personId ?? existing.personId;

        final selectedPerson = _allPersons.where((p) => p.id == newPersonId).firstOrNull;
        String? newClientId = existing.clientId;
        if (newType == TxType.workIn || newType == TxType.income) {
          if (selectedPerson != null && (selectedPerson.kind == 'client' || selectedPerson.kind == 'other')) {
            newClientId = selectedPerson.id;
          } else if (selectedPerson != null && selectedPerson.kind == 'partner') {
            // Cannot be client; prevent DB trigger abort
            newClientId = null;
          } else {
            newClientId = newPersonId;
          }
        }

        _rows[index] = existing.copyWith(
          amount: newAmount,
          inferredType: newType,
          personId: newPersonId,
          clientId: newClientId,
          rawParty: selectedPerson?.name ?? existing.rawParty,
          status: newAmount != null ? RowStatus.ready : RowStatus.needsDecision,
          ambiguityReason: newAmount == null ? AmbiguityReason.emptyAmount : null,
          resolutionNote: 'رفع ابهام توسط کاربر',
        );
      }
    });
  }

  Widget _buildFinancialSummaryBar() {
    int totalWorkIn = 0;
    int countWorkIn = 0;
    int totalExpense = 0;
    int countExpense = 0;
    int totalPayout = 0;
    int countPayout = 0;

    for (final r in _rows) {
      if (r.userSkipped) continue;
      final amt = r.amount ?? 0;
      if (r.inferredType == TxType.workIn || r.inferredType == TxType.income) {
        totalWorkIn += amt;
        countWorkIn++;
      } else if (r.inferredType == TxType.expense) {
        totalExpense += amt;
        countExpense++;
      } else if (r.inferredType == TxType.payout) {
        totalPayout += amt;
        countPayout++;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Text(
                'خلاصه مبالغ شناسایی‌شده (تفکیک درآمد و هزینه)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildKpiPill(
                icon: Icons.trending_up,
                color: Colors.green.shade800,
                bgColor: Colors.green.shade50,
                borderColor: Colors.green.shade200,
                title: 'کارکرد و درآمد',
                amount: totalWorkIn,
                count: countWorkIn,
              ),
              _buildKpiPill(
                icon: Icons.trending_down,
                color: Colors.red.shade800,
                bgColor: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                title: 'هزینه‌ها',
                amount: totalExpense,
                count: countExpense,
              ),
              _buildKpiPill(
                icon: Icons.payments_outlined,
                color: Colors.blue.shade800,
                bgColor: Colors.blue.shade50,
                borderColor: Colors.blue.shade200,
                title: 'تسویه و برداشت',
                amount: totalPayout,
                count: countPayout,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiPill({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required int amount,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$title: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            '${formatToman(amount)} تومان ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            '($count ردیف)',
            style: TextStyle(fontSize: 11, color: color.withAlpha(200)),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionTab() {
    final ambiguousRows = _rows.where((r) => r.status == RowStatus.needsDecision && !r.userSkipped).toList();

    if (ambiguousRows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade600),
              const SizedBox(height: 16),
              const Text(
                'تمامی موارد نامشخص حل یا نادیده گرفته شدند!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'اکنون می‌توانید تراکنش‌های آماده را در دفتر کارکرد ثبت کنید.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final missingParties = ambiguousRows
        .where((r) =>
            r.ambiguityReason == AmbiguityReason.unknownCounterparty &&
            r.rawParty != null &&
            r.rawParty!.trim().isNotEmpty)
        .map((r) => r.rawParty!.trim())
        .toSet();

    return Column(
      children: [
        if (missingParties.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعداد ${missingParties.length} طرف‌حساب جدید در سیستم یافت نشدند.',
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _autoCreateAllMissingParties,
                  icon: const Icon(Icons.group_add, size: 16),
                  label: Text('ثبت همه به عنوان کارفرما (${missingParties.length})'),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${ambiguousRows.length} ردیف بررسی نشده موجود است. برای ثبت نهایی باید تمام این موارد تعیین تکلیف یا نادیده گرفته شوند.',
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                ),
              ),
              TextButton.icon(
                key: const Key('skip_all_unresolved_button'),
                onPressed: _skipAllUnresolved,
                icon: const Icon(Icons.playlist_remove),
                label: const Text('نادیده گرفتن همه'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ambiguousRows.length,
            itemBuilder: (ctx, idx) => _buildAmbiguousCard(ambiguousRows[idx]),
          ),
        ),
      ],
    );
  }

  Widget _buildAmbiguousCard(ParsedExcelRow row) {
    final reasonText = switch (row.ambiguityReason) {
      AmbiguityReason.emptyAmount => 'مبلغ در فایل خالی یا خط تیره (–) است',
      AmbiguityReason.multipleAmounts => 'چندین مبلغ در ردیف یا شرح شناسایی شد',
      AmbiguityReason.unknownCounterparty => 'طرف حساب «${row.rawParty ?? ''}» در سیستم یافت نشد',
      AmbiguityReason.ambiguousType => 'نوع تراکنش در ستون اکسل نامشخص است',
      AmbiguityReason.invalidDate => 'تاریخ ردیف نامعتبر یا خالی است',
      _ => 'ردیف ناقص یا نیازمند تعیین تکلیف است',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ردیف ${row.rowIndex}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'تاریخ: ${row.isoDate ?? row.rawDate}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      reasonText,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'شرح: ${row.description.isEmpty ? '(بدون شرح)' : row.description}',
              style: const TextStyle(fontSize: 14),
            ),
            if (row.rawParty != null && row.rawParty!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'طرف حساب در اکسل: ${row.rawParty}',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
              ),
            ],
            const Divider(height: 24),

            // Resolution inputs depending on AmbiguityReason
            if (row.ambiguityReason == AmbiguityReason.multipleAmounts) ...[
              const Text(
                'یکی از مبالغ شناسایی‌شده را انتخاب کنید یا مبلغ دلخواه وارد کنید:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: row.detectedAmounts.map((amt) {
                  final isSelected = _selectedCandidateAmounts[row.rowIndex] == amt;
                  return ChoiceChip(
                    label: Text('${formatToman(amt)} تومان'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCandidateAmounts[row.rowIndex] = amt;
                          _amountControllers[row.rowIndex]?.text = amt.toString();
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountControllers[row.rowIndex],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مبلغ نهایی (تومان)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final text = _amountControllers[row.rowIndex]?.text ?? '';
                      final parsed = ExcelNumberParser.parseAmount(text);
                      if (parsed != null && parsed > 0) {
                        _resolveRow(row, amount: parsed);
                      }
                    },
                    child: const Text('تأیید مبلغ'),
                  ),
                ],
              ),
            ] else if (row.ambiguityReason == AmbiguityReason.emptyAmount) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountControllers[row.rowIndex],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مبلغ این ردیف را وارد کنید (تومان)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final text = _amountControllers[row.rowIndex]?.text ?? '';
                      final parsed = ExcelNumberParser.parseAmount(text);
                      if (parsed != null && parsed > 0) {
                        _resolveRow(row, amount: parsed);
                      }
                    },
                    child: const Text('ثبت مبلغ'),
                  ),
                ],
              ),
            ] else if (row.ambiguityReason == AmbiguityReason.unknownCounterparty) ...[
              if (row.rawParty != null && row.rawParty!.trim().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_add_alt_1, color: Colors.blue.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'طرف حساب «${row.rawParty}» در سیستم ثبت نشده است.',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _createPartyAsNewClient(row.rawParty!),
                        icon: const Icon(Icons.add, size: 16),
                        label: Text('ثبت «${row.rawParty}» به عنوان کارفرمای جدید'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('یا انتخاب از بین اشخاص موجود در سیستم:', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedPersons[row.rowIndex],
                      decoration: const InputDecoration(
                        labelText: 'انتخاب شخص از لیست موجود',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _allPersons.map((p) {
                        final kindLabel = p.kind == 'client' ? 'کارفرما' : (p.kind == 'partner' ? 'شریک' : 'شخص');
                        return DropdownMenuItem(value: p.id, child: Text('${p.name} ($kindLabel)', overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedPersons[row.rowIndex] = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedPersons[row.rowIndex] != null
                        ? () {
                            _resolveRow(row, personId: _selectedPersons[row.rowIndex]);
                          }
                        : null,
                    child: const Text('تأیید شخص'),
                  ),
                ],
              ),
            ] else if (row.ambiguityReason == AmbiguityReason.ambiguousType) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TxType>(
                      isExpanded: true,
                      initialValue: _selectedTypes[row.rowIndex] ?? TxType.expense,
                      decoration: const InputDecoration(
                        labelText: 'انتخاب نوع تراکنش',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: TxType.values.map((t) {
                        return DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedTypes[row.rowIndex] = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final type = _selectedTypes[row.rowIndex] ?? TxType.expense;
                      _resolveRow(row, type: type);
                    },
                    child: const Text('تأیید نوع'),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _skipRow(row),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  label: const Text('نادیده گرفتن این ردیف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyTab() {
    final readyRows = _rows.where((r) => r.status == RowStatus.ready && !r.userSkipped).toList();

    if (readyRows.isEmpty) {
      return const Center(
        child: Text('هیچ تراکنشی در وضعیت آماده ثبت قرار ندارد.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: readyRows.length,
      itemBuilder: (ctx, idx) {
        final r = readyRows[idx];
        final isIncome = r.inferredType == TxType.workIn || r.inferredType == TxType.income;
        final isExpense = r.inferredType == TxType.expense;
        final isPayout = r.inferredType == TxType.payout;

        final badgeBg = isIncome
            ? Colors.green.shade50
            : (isExpense ? Colors.red.shade50 : Colors.blue.shade50);
        final badgeBorder = isIncome
            ? Colors.green.shade200
            : (isExpense ? Colors.red.shade200 : Colors.blue.shade200);
        final badgeText = isIncome
            ? Colors.green.shade800
            : (isExpense ? Colors.red.shade800 : Colors.blue.shade800);
        final typeLabel = isIncome
            ? '🟢 کارکرد / درآمد'
            : (isExpense ? '🔴 هزینه کارگاه' : (isPayout ? '🔵 تسویه شریک' : r.inferredType?.label ?? 'تراکنش'));

        final partyName = r.rawParty ??
            (r.clientId != null ? _getPersonName(r.clientId!) : null) ??
            (r.personId != null ? _getPersonName(r.personId!) : null);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: badgeBorder),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: badgeBg,
              child: Text(
                '${r.rowIndex}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeText),
              ),
            ),
            title: Row(
              children: [
                Text(
                  r.isoDate ?? r.rawDate,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    border: Border.all(color: badgeBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeText),
                  ),
                ),
                const Spacer(),
                Text(
                  isIncome
                      ? '+ ${formatToman(r.amount ?? 0)} تومان'
                      : (isExpense ? '- ${formatToman(r.amount ?? 0)} تومان' : '${formatToman(r.amount ?? 0)} تومان'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIncome
                        ? Colors.green.shade700
                        : (isExpense ? Colors.red.shade700 : Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  r.description.isEmpty ? '(بدون شرح)' : r.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (partyName != null && partyName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 13, color: Colors.grey.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'طرف حساب: $partyName',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuplicatesTab() {
    final dupRows = _rows.where((r) => r.status == RowStatus.duplicate).toList();

    if (dupRows.isEmpty) {
      return const Center(
        child: Text('هیچ ردیف تکراری در این فایل یافت نشد.'),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'این ردیف‌ها قبلاً در پایگاه داده ثبت شده‌اند یا در همین فایل تکرار شده‌اند. برای جلوگیری از ثبت تکراری، نادیده گرفته می‌شوند.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: dupRows.length,
            itemBuilder: (ctx, idx) {
              final r = dupRows[idx];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade200,
                    child: Text('${r.rowIndex}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  title: Row(
                    children: [
                      Text(r.isoDate ?? r.rawDate),
                      const SizedBox(width: 8),
                      Text('${formatToman(r.amount ?? 0)} تومان'),
                      const Spacer(),
                      const Chip(
                        label: Text('تکراری', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    r.description.isEmpty ? '(بدون شرح)' : r.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsDecision = _needsDecisionCount;
    final ready = _readyCount;
    final duplicates = _duplicateCount;

    return Column(
      children: [
        _buildFinancialSummaryBar(),
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('نیازمند تصمیم'),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: needsDecision > 0 ? Colors.red : Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$needsDecision',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('آماده ثبت'),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$ready',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تکراری'),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$duplicates',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDecisionTab(),
              _buildReadyTab(),
              _buildDuplicatesTab(),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                offset: const Offset(0, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.onBack != null)
                OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('مرحله قبل'),
                )
              else
                const SizedBox.shrink(),
              FilledButton.icon(
                key: const Key('commit_import_button'),
                // Zero guessing: MUST be disabled while any needsDecision row remains unresolved!
                onPressed: needsDecision > 0 ? null : () => widget.onCommit(_rows),
                icon: const Icon(Icons.check),
                label: Text(
                  needsDecision > 0
                      ? 'ابتدا $needsDecision مورد نامشخص را تعیین تکلیف کنید'
                      : 'تأیید و ثبت در دفتر ($ready تراکنش)',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
