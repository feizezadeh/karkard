import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:uuid/uuid.dart';

import '../../core/jalali.dart';
import '../../core/money.dart';
import '../../data/database.dart';

class AddProjectDialog extends StatefulWidget {
  final AppDatabase db;

  const AddProjectDialog({
    super.key,
    required this.db,
  });

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _PartnerEntry {
  String personId;
  String name;
  String settlementMode; // profit_share | both | payout_only
  int sharePercent; // 0..100

  _PartnerEntry({
    required this.personId,
    required this.name,
    this.settlementMode = 'profit_share',
    this.sharePercent = 100,
  });
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startDateController = TextEditingController();
  final _newPartnerNameController = TextEditingController();

  String _shareMethod = 'by_work'; // by_work | fixed_percent
  String _shareBasis = 'accrual'; // accrual | cash
  final String _reportBasis = 'both'; // both | accrual | cash

  List<Person> _existingPartners = [];
  final List<_PartnerEntry> _selectedPartners = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final nowJ = Jalali.now();
    _startDateController.text =
        '${nowJ.year}/${nowJ.month.toString().padLeft(2, '0')}/${nowJ.day.toString().padLeft(2, '0')}';
    _loadPartners();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startDateController.dispose();
    _newPartnerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    final list = await (widget.db.select(widget.db.persons)
          ..where((p) => p.kind.equals('partner') & p.isActive.equals(true)))
        .get();

    if (mounted) {
      setState(() {
        _existingPartners = list;
        _isLoading = false;

        if (_existingPartners.isNotEmpty) {
          _selectedPartners.add(_PartnerEntry(
            personId: _existingPartners.first.id,
            name: _existingPartners.first.name,
            settlementMode: 'profit_share',
            sharePercent: 100,
          ));
        }
      });
    }
  }

  int get _totalBp {
    return _selectedPartners
        .where((p) => p.settlementMode != 'payout_only')
        .fold(0, (sum, p) => sum + (p.sharePercent * 100));
  }

  Future<void> _addNewPartnerInline() async {
    final name = _newPartnerNameController.text.trim();
    if (name.isEmpty) return;

    final id = const Uuid().v4();
    await widget.db.into(widget.db.persons).insert(
          PersonsCompanion.insert(
            id: id,
            name: name,
            kind: 'partner',
          ),
        );

    final created = await (widget.db.select(widget.db.persons)..where((p) => p.id.equals(id))).getSingle();
    _newPartnerNameController.clear();

    setState(() {
      _existingPartners.add(created);
      // Re-balance shares
      final count = _selectedPartners.length + 1;
      final equalShare = (100 / count).floor();
      for (final p in _selectedPartners) {
        p.sharePercent = equalShare;
      }
      _selectedPartners.add(_PartnerEntry(
        personId: created.id,
        name: created.name,
        settlementMode: 'profit_share',
        sharePercent: 100 - (_selectedPartners.fold(0, (s, p) => s + p.sharePercent)),
      ));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate share percentages if fixed_percent
    if (_selectedPartners.isNotEmpty) {
      final activePartners = _selectedPartners.where((p) => p.settlementMode != 'payout_only').toList();
      if (activePartners.isNotEmpty && _totalBp != 10000) {
        setState(() {
          _errorMessage = 'مجموع سهم شرکا باید دقیقاً ۱۰۰٪ (۱۰۰۰۰ واحد) باشد. مجموع فعلی: ${_totalBp ~/ 100}٪';
        });
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final projectId = const Uuid().v4();
      final name = _nameController.text.trim();
      final startDate = parseJalaliStringToIso(_startDateController.text);

      await widget.db.transaction(() async {
        // 1. Projects
        await widget.db.into(widget.db.projects).insert(
              ProjectsCompanion.insert(
                id: projectId,
                name: name,
                startDate: drift.Value(startDate),
                status: const drift.Value('open'),
              ),
            );

        // 2. Project Settings
        await widget.db.into(widget.db.projectSettings).insert(
              ProjectSettingsCompanion.insert(
                projectId: projectId,
                reportBasis: drift.Value(_reportBasis),
                shareBasis: drift.Value(_shareBasis),
                shareMethod: drift.Value(_shareMethod),
              ),
            );

        // 3. Project Persons (Partners)
        for (int i = 0; i < _selectedPartners.length; i++) {
          final entry = _selectedPartners[i];
          final shareBp = entry.settlementMode == 'payout_only' ? 0 : entry.sharePercent * 100;

          await widget.db.into(widget.db.projectPersons).insert(
                ProjectPersonsCompanion.insert(
                  projectId: projectId,
                  personId: entry.personId,
                  settlementMode: drift.Value(entry.settlementMode),
                  shareBp: drift.Value(shareBp),
                  shareOrder: drift.Value(i + 1),
                ),
              );
        }

        // 4. Default Project Cash Account
        await widget.db.into(widget.db.cashAccounts).insert(
              CashAccountsCompanion.insert(
                id: const Uuid().v4(),
                name: 'صندوق نقدی $name',
                kind: 'project',
              ),
            );
      });

      final created = await (widget.db.select(widget.db.projects)..where((p) => p.id.equals(projectId))).getSingle();

      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString();
        });
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
          title: const Text('تعریف و راه‌اندازی پروژه جدید'),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('ایجاد'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12),
                    ),
                  ),

                // 1. Basic Info
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'نام یا عنوان پروژه *',
                    hintText: 'مثال: پروژه بزرگراه آزادی، احداث سوله صنعتی',
                    prefixIcon: Icon(Icons.drive_file_rename_outline),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'نام پروژه الزامی است' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _startDateController,
                  decoration: const InputDecoration(
                    labelText: 'تاریخ شروع (جلالی)',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    try {
                      parseJalaliStringToIso(v);
                      return null;
                    } catch (_) {
                      return 'فرمت تاریخ صحیح نیست (مثال: ۱۴۰۳/۰۲/۱۵)';
                    }
                  },
                ),
                const SizedBox(height: 16),

                // 2. Financial & Sharing Rules
                Text(
                  'تنظیمات مالی و روش تسهیم سود',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _shareMethod,
                  decoration: const InputDecoration(labelText: 'روش تسهیم سود بین شرکا'),
                  items: const [
                    DropdownMenuItem(value: 'by_work', child: Text('بر اساس حجم کارکرد شرکا (By Work)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'fixed_percent', child: Text('بر اساس درصد ثابت سهام (Fixed Percent)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _shareMethod = val;
                        if (_shareMethod == 'by_work') {
                          _shareBasis = 'accrual';
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _shareBasis,
                  decoration: const InputDecoration(labelText: 'مبنای محاسبه سود'),
                  items: [
                    const DropdownMenuItem(value: 'accrual', child: Text('مبنای تعهدی (Accrual)', overflow: TextOverflow.ellipsis)),
                    if (_shareMethod != 'by_work')
                      const DropdownMenuItem(value: 'cash', child: Text('مبنای نقدی (Cash)', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _shareBasis = val);
                  },
                ),
                const SizedBox(height: 16),

                // 3. Project Partners
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'شرکای حاضر در این پروژه',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'مجموع سهم: ${toFaDigits("${_totalBp ~/ 100}")}٪',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _totalBp == 10000 ? Colors.green.shade800 : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  for (int i = 0; i < _selectedPartners.length; i++) ...[
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                _selectedPartners[i].name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: '${_selectedPartners[i].sharePercent}',
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'درصد سهم',
                                  suffixText: '٪',
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final n = int.tryParse(v) ?? 0;
                                  setState(() {
                                    _selectedPartners[i].sharePercent = n;
                                  });
                                },
                              ),
                            ),
                            if (_selectedPartners.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _selectedPartners.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Inline add new partner
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newPartnerNameController,
                          decoration: const InputDecoration(
                            hintText: 'نام شریک جدید...',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('افزودن'),
                        onPressed: _addNewPartnerInline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('ایجاد و فعال‌سازی پروژه', style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          ),
        ),
      ),
    ),
  ),
);
}
}
