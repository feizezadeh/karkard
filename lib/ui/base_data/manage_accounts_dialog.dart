import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

class ManageAccountsDialog extends StatefulWidget {
  final AppDatabase db;

  const ManageAccountsDialog({
    super.key,
    required this.db,
  });

  @override
  State<ManageAccountsDialog> createState() => _ManageAccountsDialogState();
}

class _ManageAccountsDialogState extends State<ManageAccountsDialog> {
  List<CashAccount> _accounts = [];
  List<Person> _persons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final accounts = await widget.db.select(widget.db.cashAccounts).get();
    final persons = await widget.db.select(widget.db.persons).get();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _persons = persons;
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => AddAccountScreen(
          db: widget.db,
          persons: _persons,
        ),
      ),
    );
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت صندوق‌ها و حساب‌های بانکی'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_card_outlined),
              tooltip: 'تعریف حساب جدید',
              onPressed: _openAddAccount,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddAccount,
          icon: const Icon(Icons.add),
          label: const Text('حساب جدید'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _accounts.isEmpty
                              ? const Center(child: Text('هیچ حسابی تعریف نشده است.'))
                              : ListView.separated(
                                  itemCount: _accounts.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (ctx, i) {
                                    final acc = _accounts[i];
                                    final isProj = acc.kind == 'project';
                                    final holder = !isProj && acc.holderPersonId != null
                                        ? _persons.cast<Person?>().firstWhere(
                                              (p) => p?.id == acc.holderPersonId,
                                              orElse: () => null,
                                            )
                                        : null;

                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: (isProj ? Colors.teal : Colors.indigo).withValues(alpha: 0.15),
                                        foregroundColor: isProj ? Colors.teal.shade800 : Colors.indigo.shade800,
                                        child: Icon(isProj ? Icons.savings_outlined : Icons.credit_card),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              acc.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (acc.code != null && acc.code!.isNotEmpty)
                                            Container(
                                              margin: const EdgeInsets.only(right: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.shade400, width: 0.7),
                                              ),
                                              child: Text(
                                                'معین: ${acc.code}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        isProj
                                            ? 'صندوق یا حساب مرکزی پروژه'
                                            : 'حساب شخصی طرف‌حساب: ${holder?.name ?? 'نامشخص'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      trailing: Chip(
                                        label: Text(
                                          isProj ? 'مشترک پروژه' : 'شخصی',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isProj ? Colors.teal.shade800 : Colors.indigo.shade800,
                                          ),
                                        ),
                                        backgroundColor: (isProj ? Colors.teal : Colors.indigo).withValues(alpha: 0.08),
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('تعریف حساب / صندوق جدید'),
                      onPressed: _openAddAccount,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
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

class AddAccountScreen extends StatefulWidget {
  final AppDatabase db;
  final List<Person> persons;

  const AddAccountScreen({
    super.key,
    required this.db,
    required this.persons,
  });

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String _kind = 'project';
  String? _holderId;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.persons.isNotEmpty) {
      _holderId = widget.persons.first.id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final id = const Uuid().v4();
      final code = _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim();
      await widget.db.into(widget.db.cashAccounts).insert(
            CashAccountsCompanion.insert(
              id: id,
              name: _nameCtrl.text.trim(),
              kind: _kind,
              code: drift.Value(code),
              holderPersonId: _kind == 'personal' && _holderId != null
                  ? drift.Value(_holderId)
                  : const drift.Value(null),
            ),
          );
      if (mounted) Navigator.of(context).pop();
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
          title: const Text('تعریف حساب / صندوق جدید'),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('ثبت'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
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
                      TextFormField(
                        controller: _nameCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'نام حساب یا صندوق *',
                          hintText: 'مثال: حساب بانک ملت پروژه، صندوق نقدی کارگاه',
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'نام حساب الزامی است' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'کد حسابداری / معین نقد و بانک (اختیاری)',
                          hintText: 'مثال: ۱۰۱۰۱ یا ۱۰۲۰۲',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _kind,
                        decoration: const InputDecoration(
                          labelText: 'نوع حساب *',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'project', child: Text('حساب مشترک / صندوق پروژه', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'personal', child: Text('حساب شخصی / کارت شخص', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _kind = v);
                          }
                        },
                      ),
                      if (_kind == 'personal') ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _holderId,
                          decoration: const InputDecoration(
                            labelText: 'دارنده حساب (شخص) *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: [
                            for (final p in widget.persons)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _holderId = v);
                          },
                          validator: (v) => _kind == 'personal' && v == null ? 'انتخاب دارنده حساب الزامی است' : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: const Text('ثبت و ذخیره حساب', style: TextStyle(fontSize: 16)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
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
