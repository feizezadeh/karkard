import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

class AddPersonDialog extends StatefulWidget {
  final AppDatabase db;
  final String? projectId;
  final String? initialKind;

  const AddPersonDialog({
    super.key,
    required this.db,
    this.projectId,
    this.initialKind,
  });

  @override
  State<AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<AddPersonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _noteController = TextEditingController();
  late String _kind;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? 'client';
    if (!['client', 'partner', 'driver', 'worker', 'other'].contains(_kind)) {
      _kind = 'client';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _noteController.dispose();
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
      final name = _nameController.text.trim();
      final code = _codeController.text.trim().isEmpty ? null : _codeController.text.trim();
      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

      await widget.db.into(widget.db.persons).insert(
            PersonsCompanion.insert(
              id: id,
              name: name,
              kind: _kind,
              code: drift.Value(code),
              note: drift.Value(note),
            ),
          );

      // If we are within an active project and the person is driver/worker/other,
      // register them in project_persons as payout_only so they can be selected in work_out/payout.
      if (widget.projectId != null && widget.projectId!.isNotEmpty) {
        if (_kind == 'driver' || _kind == 'worker' || _kind == 'other') {
          await widget.db.into(widget.db.projectPersons).insert(
                ProjectPersonsCompanion.insert(
                  projectId: widget.projectId!,
                  personId: id,
                  settlementMode: const drift.Value('payout_only'),
                  shareBp: const drift.Value(0),
                ),
              );
        } else if (_kind == 'partner') {
          // If partner, register as payout_only by default unless shareBp is explicitly set in project management
          await widget.db.into(widget.db.projectPersons).insert(
                ProjectPersonsCompanion.insert(
                  projectId: widget.projectId!,
                  personId: id,
                  settlementMode: const drift.Value('payout_only'),
                  shareBp: const drift.Value(0),
                ),
              );
        }
      }

      final created = await (widget.db.select(widget.db.persons)..where((p) => p.id.equals(id))).getSingle();
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
          title: const Text('تعریف طرف‌حساب جدید'),
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
                        controller: _nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'نام و نام‌خانوادگی / عنوان شرکت *',
                          hintText: 'مثال: شرکت راهسازی عمران، علی احمدی، ...',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'وارد کردن نام الزامی است';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _kind,
                        decoration: const InputDecoration(
                          labelText: 'نقش / نوع طرف‌حساب *',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'client', child: Text('کارفرما / مشتری (Client)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'partner', child: Text('شریک پروژه (Partner)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'driver', child: Text('راننده (Driver)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'worker', child: Text('کارگر / پرسنل اجرایی (Worker)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'other', child: Text('سایر طرف‌حساب‌ها (Other)', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _kind = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'کد حسابداری / کد تفصیلی (اختیاری)',
                          hintText: 'مثال: ۱۰۱۰۱ یا ۱۲۰۳',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'یادداشت / شماره تماس (اختیاری)',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: const Text('ثبت و ذخیره طرف‌حساب', style: TextStyle(fontSize: 16)),
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
