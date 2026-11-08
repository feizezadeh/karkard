import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:shamsi_date/shamsi_date.dart';
import 'package:uuid/uuid.dart';

import '../core/jalali.dart';
import '../core/money.dart';
import '../core/platform_ports.dart';
import '../data/database.dart';
import '../domain/tx_type.dart';
import '../services/receipt_service.dart';
import '../services/validation_service.dart';
import 'base_data/add_person_dialog.dart';
import 'receipts/receipt_attachment_widget.dart';

/// Interactive dialog for registering a new transaction atomically with audit_log.
class NewTransactionDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final VoidCallback onSaved;
  final ReceiptService? receiptService;
  final ReceiptPicker? picker;

  const NewTransactionDialog({
    super.key,
    required this.db,
    required this.projectId,
    required this.onSaved,
    this.receiptService,
    this.picker,
  });

  @override
  State<NewTransactionDialog> createState() => _NewTransactionDialogState();
}

class _NewTransactionDialogState extends State<NewTransactionDialog> {
  late final ValidationService _validationService;

  TxType _selectedType = TxType.workIn;
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _descController = TextEditingController();
  final _overrideController = TextEditingController();

  List<Person> _allPersons = [];
  List<CashAccount> _allAccounts = [];

  String? _selectedClientId;
  String? _selectedPersonId;
  String? _selectedPerformedById;
  String? _selectedAttributedToId;
  String? _selectedCashAccountId;
  String? _selectedFromAccountId;
  String? _selectedToAccountId;
  String _selectedPurpose = 'settle_payable';

  String? _errorMessage;
  bool _isSaving = false;
  List<PickedFile> _pendingReceipts = [];
  bool _receiptNotRequired = false;

  @override
  void initState() {
    super.initState();
    _validationService = ValidationService(widget.db);

    // Default date: today in Jalali
    final nowJ = Jalali.now();
    _dateController.text =
        '${nowJ.year}/${nowJ.month.toString().padLeft(2, '0')}/${nowJ.day.toString().padLeft(2, '0')}';

    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final persons = await (widget.db.select(widget.db.persons)
          ..where((p) => p.isActive.equals(true)))
        .get();
    final accounts = await widget.db.select(widget.db.cashAccounts).get();

    if (mounted) {
      setState(() {
        _allPersons = persons;
        _allAccounts = accounts;

        // Auto-select first available options
        final clients = _allPersons.where((p) => p.kind == 'client').toList();
        if (clients.isNotEmpty) _selectedClientId = clients.first.id;

        final nonClients = _allPersons.where((p) => p.kind != 'client').toList();
        if (nonClients.isNotEmpty) _selectedPersonId = nonClients.first.id;

        if (_allAccounts.isNotEmpty) {
          _selectedCashAccountId = _allAccounts.first.id;
          _selectedFromAccountId = _allAccounts.first.id;
          if (_allAccounts.length > 1) {
            _selectedToAccountId = _allAccounts[1].id;
          }
        }
      });
    }
  }

  Future<void> _quickAddPerson({required String defaultKind}) async {
    final created = await Navigator.of(context).push<Person>(
      MaterialPageRoute(
        builder: (ctx) => AddPersonDialog(
          db: widget.db,
          projectId: widget.projectId,
          initialKind: defaultKind,
        ),
      ),
    );
    if (created != null && mounted) {
      await _loadMetadata();
      setState(() {
        if (created.kind == 'client') {
          _selectedClientId = created.id;
        } else {
          _selectedPersonId = created.id;
        }
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    _descController.dispose();
    _overrideController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });

    try {
      final amount = parseToman(_amountController.text);
      if (amount <= 0) {
        throw Exception('مبلغ باید بزرگ‌تر از صفر باشد.');
      }

      final isoDate = parseJalaliStringToIso(_dateController.text);
      final desc = _descController.text.trim();
      final override = _overrideController.text.trim();

      TransactionsCompanion companion;

      const uuid = Uuid();
      final txId = uuid.v4();

      switch (_selectedType) {
        case TxType.workIn:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            clientId: Value(_selectedClientId),
            performedBy: Value(_selectedPerformedById),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;

        case TxType.workOut:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            personId: Value(_selectedPersonId),
            attributedTo: Value(_selectedAttributedToId),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;

        case TxType.income:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            clientId: Value(_selectedClientId),
            cashAccountId: Value(_selectedCashAccountId),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;

        case TxType.expense:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            cashAccountId: Value(_selectedCashAccountId),
            attributedTo: Value(_selectedAttributedToId),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;

        case TxType.payout:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            personId: Value(_selectedPersonId),
            cashAccountId: Value(_selectedCashAccountId),
            purpose: Value(_selectedPurpose),
            overrideReason: override.isNotEmpty ? Value(override) : const Value.absent(),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;

        case TxType.transfer:
          companion = TransactionsCompanion.insert(
            id: txId,
            projectId: widget.projectId,
            type: _selectedType.dbValue,
            amount: amount,
            date: isoDate,
            description: Value(desc),
            fromAccountId: Value(_selectedFromAccountId),
            toAccountId: Value(_selectedToAccountId),
            receiptNotRequired: Value(_receiptNotRequired),
          );
          break;
      }

      await _validationService.createTransactionAtomic(companion);

      if (_pendingReceipts.isNotEmpty) {
        final svc = widget.receiptService ?? ReceiptService(widget.db);
        for (final file in _pendingReceipts) {
          await svc.saveReceipt(
            transactionId: txId,
            file: file,
          );
        }
      }

      if (mounted) {
        setState(() => _isSaving = false);
        widget.onSaved();
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('DomainException(', '').replaceFirst(RegExp(r'^[A-Z_]+:\s*'), '').replaceAll(RegExp(r'\)$'), '');
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _allPersons.where((p) => p.kind == 'client').toList();
    final nonClients = _allPersons.where((p) => p.kind != 'client').toList();
    final partners = _allPersons.where((p) => p.kind == 'partner').toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ثبت تراکنش جدید', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: const Text('ثبت'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                    ),
                  ),

                // 1. Transaction Type Dropdown
                DropdownButtonFormField<TxType>(
                  isExpanded: true,
                  initialValue: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'نوع تراکنش',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    for (final t in TxType.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(t.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedType = val);
                  },
                ),
                const SizedBox(height: 12),

                // 2. Type-specific dependent fields
                if (_selectedType == TxType.workIn) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('workin_client_${clients.length}_$_selectedClientId'),
                          initialValue: _selectedClientId,
                          decoration: const InputDecoration(
                            labelText: 'کارفرما (طرف حساب)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            for (final c in clients)
                              DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() => _selectedClientId = val),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.person_add_alt_1),
                        tooltip: 'تعریف کارفرما جدید',
                        onPressed: () => _quickAddPerson(defaultKind: 'client'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedPerformedById,
                    decoration: const InputDecoration(
                      labelText: 'انجام‌دهنده کار (اختیاری؛ برای تسهیم کارکردی)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('مشترک / بدون شریک خاص', overflow: TextOverflow.ellipsis)),
                      for (final p in partners)
                        DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedPerformedById = val),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedType == TxType.workOut) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('workout_person_${nonClients.length}_$_selectedPersonId'),
                          initialValue: _selectedPersonId,
                          decoration: const InputDecoration(
                            labelText: 'شخص ذینفع (راننده / کارگر / شریک)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            for (final p in nonClients)
                              DropdownMenuItem(value: p.id, child: Text('${p.name} (${p.kind})', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() => _selectedPersonId = val),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.person_add_alt_1),
                        tooltip: 'تعریف شخص / راننده جدید',
                        onPressed: () => _quickAddPerson(defaultKind: 'driver'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedAttributedToId,
                    decoration: const InputDecoration(
                      labelText: 'منسوب به شریک (اختیاری)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('مشترک / هزینه عمومی پروژه', overflow: TextOverflow.ellipsis)),
                      for (final p in partners)
                        DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedAttributedToId = val),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedType == TxType.income) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('income_client_${clients.length}_$_selectedClientId'),
                          initialValue: _selectedClientId,
                          decoration: const InputDecoration(
                            labelText: 'کارفرما (پرداخت‌کننده)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            for (final c in clients)
                              DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() => _selectedClientId = val),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.person_add_alt_1),
                        tooltip: 'تعریف کارفرما جدید',
                        onPressed: () => _quickAddPerson(defaultKind: 'client'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedCashAccountId,
                    decoration: const InputDecoration(
                      labelText: 'واریز به حساب / صندوق',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in _allAccounts)
                        DropdownMenuItem(value: a.id, child: Text('${a.name} (${a.kind == 'project' ? 'پروژه' : 'شخصی'})', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedCashAccountId = val),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedType == TxType.expense) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedCashAccountId,
                    decoration: const InputDecoration(
                      labelText: 'پرداخت از حساب / صندوق',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in _allAccounts)
                        DropdownMenuItem(value: a.id, child: Text('${a.name} (${a.kind == 'project' ? 'پروژه' : 'شخصی'})', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedCashAccountId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedAttributedToId,
                    decoration: const InputDecoration(
                      labelText: 'منسوب به شریک (اختیاری)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('مشترک / هزینه پروژه', overflow: TextOverflow.ellipsis)),
                      for (final p in partners)
                        DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedAttributedToId = val),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedType == TxType.payout) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('payout_person_${nonClients.length}_$_selectedPersonId'),
                          initialValue: _selectedPersonId,
                          decoration: const InputDecoration(
                            labelText: 'پرداخت به شخص',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: [
                            for (final p in nonClients)
                              DropdownMenuItem(value: p.id, child: Text('${p.name} (${p.kind})', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) => setState(() => _selectedPersonId = val),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.person_add_alt_1),
                        tooltip: 'تعریف شخص / راننده جدید',
                        onPressed: () => _quickAddPerson(defaultKind: 'driver'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedCashAccountId,
                    decoration: const InputDecoration(
                      labelText: 'از حساب / صندوق',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in _allAccounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedCashAccountId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedPurpose,
                    decoration: const InputDecoration(
                      labelText: 'هدف پرداخت',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'settle_payable', child: Text('تسویه دستمزد / بدهی', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'distribution', child: Text('برداشت از سود', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPurpose = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _overrideController,
                    decoration: const InputDecoration(
                      labelText: 'دلیل عبور از سقف (در صورت مازاد بر سهم/بدهی)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedType == TxType.transfer) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedFromAccountId,
                    decoration: const InputDecoration(
                      labelText: 'از حساب مبدأ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in _allAccounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedFromAccountId = val),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedToAccountId,
                    decoration: const InputDecoration(
                      labelText: 'به حساب مقصد',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in _allAccounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedToAccountId = val),
                  ),
                  const SizedBox(height: 12),
                ],

                // 3. Amount Field
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مبلغ (تومان)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Date Field (Jalali)
                TextField(
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: 'تاریخ (شمسی: ۱۴۰۳/۱۲/۲۹)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Description Field
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'شرح تراکنش (اختیاری)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Receipts attachment section
                ReceiptAttachmentWidget(
                  pendingFiles: _pendingReceipts,
                  onChanged: (files) => setState(() => _pendingReceipts = files),
                  picker: widget.picker,
                  isEnabled: !_isSaving,
                ),
                const SizedBox(height: 8),

                // Checkbox: No receipt required
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _receiptNotRequired,
                  onChanged: _isSaving
                      ? null
                      : (val) => setState(() => _receiptNotRequired = val ?? false),
                  title: const Text('رسید لازم ندارد', style: TextStyle(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('ذخیره و ثبت در دفتر', style: TextStyle(fontSize: 16)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),
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
