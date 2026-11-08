import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/database.dart';
import '../../services/statement_pdf_service.dart';
import 'add_person_dialog.dart';

class ManagePersonsDialog extends StatefulWidget {
  final AppDatabase db;
  final String? projectId;
  final bool asTab;

  const ManagePersonsDialog({
    super.key,
    required this.db,
    this.projectId,
    this.asTab = false,
  });

  @override
  State<ManagePersonsDialog> createState() => _ManagePersonsDialogState();
}

class _ManagePersonsDialogState extends State<ManagePersonsDialog> {
  List<Person> _persons = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    setState(() => _isLoading = true);
    final list = await widget.db.select(widget.db.persons).get();
    if (mounted) {
      setState(() {
        _persons = list;
        _isLoading = false;
      });
    }
  }

  String _kindTitle(String kind) {
    switch (kind) {
      case 'client':
        return 'کارفرما / مشتری';
      case 'partner':
        return 'شریک';
      case 'driver':
        return 'راننده';
      case 'worker':
        return 'کارگر / پرسنل';
      case 'other':
      default:
        return 'سایر';
    }
  }

  Color _kindColor(String kind, BuildContext context) {
    final theme = Theme.of(context);
    switch (kind) {
      case 'client':
        return Colors.blue.shade700;
      case 'partner':
        return Colors.purple.shade700;
      case 'driver':
        return Colors.orange.shade800;
      case 'worker':
        return Colors.teal.shade700;
      case 'other':
      default:
        return theme.colorScheme.outline;
    }
  }

  Future<void> _openAddPerson() async {
    final defaultKind = _selectedFilter == 'client'
        ? 'client'
        : _selectedFilter == 'driver'
            ? 'driver'
            : _selectedFilter == 'partner'
                ? 'partner'
                : 'client';

    final created = await Navigator.of(context).push<Person>(
      MaterialPageRoute(
        builder: (ctx) => AddPersonDialog(
          db: widget.db,
          projectId: widget.projectId,
          initialKind: defaultKind,
        ),
      ),
    );

    if (created != null) {
      await _loadPersons();
    }
  }

  Future<void> _exportPersonStatement(Person person) async {
    final projectId = widget.projectId;
    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً ابتدا یک پروژه فعال انتخاب کنید.')),
      );
      return;
    }

    try {
      final pdfService = StatementPdfService(widget.db);
      final report = await pdfService.generateReportData(
        projectId: projectId,
        personId: person.id,
      );
      final pdfBytes = await pdfService.generatePdfBytes(report);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'صورت‌حساب_${person.name}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('خطا در تولید صورت‌حساب PDF: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filtered = _persons.where((p) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'client') return p.kind == 'client';
      if (_selectedFilter == 'partner') return p.kind == 'partner';
      if (_selectedFilter == 'driver_worker') return p.kind == 'driver' || p.kind == 'worker';
      return p.kind == 'other';
    }).toList();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.asTab) ...[
          Row(
            children: [
              Icon(Icons.people_alt, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مدیریت اشخاص و طرف‌حساب‌ها',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('همه (${_persons.length})'),
                selected: _selectedFilter == 'all',
                onSelected: (_) => setState(() => _selectedFilter = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('کارفرمایان (${_persons.where((p) => p.kind == 'client').length})'),
                selected: _selectedFilter == 'client',
                onSelected: (_) => setState(() => _selectedFilter = 'client'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('شرکا (${_persons.where((p) => p.kind == 'partner').length})'),
                selected: _selectedFilter == 'partner',
                onSelected: (_) => setState(() => _selectedFilter = 'partner'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('رانندگان و پرسنل (${_persons.where((p) => p.kind == 'driver' || p.kind == 'worker').length})'),
                selected: _selectedFilter == 'driver_worker',
                onSelected: (_) => setState(() => _selectedFilter = 'driver_worker'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('سایر (${_persons.where((p) => p.kind == 'other').length})'),
                selected: _selectedFilter == 'other',
                onSelected: (_) => setState(() => _selectedFilter = 'other'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off_outlined, size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          const Text('هیچ طرف‌حسابی در این دسته یافت نشد.'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        final color = _kindColor(p.kind, context);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            foregroundColor: color,
                            child: Icon(
                              p.kind == 'client'
                                  ? Icons.business
                                  : p.kind == 'partner'
                                      ? Icons.handshake
                                      : p.kind == 'driver'
                                          ? Icons.local_shipping
                                          : Icons.person,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (p.code != null && p.code!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'کد: ${p.code!}',
                                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: p.note != null && p.note!.isNotEmpty
                              ? Text(p.note!, maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(
                                  _kindTitle(p.kind),
                                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                side: BorderSide(color: color.withValues(alpha: 0.5)),
                                backgroundColor: color.withValues(alpha: 0.08),
                              ),
                              if (widget.projectId != null) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  tooltip: 'چاپ و صدور صورت‌حساب PDF',
                                  color: theme.colorScheme.primary,
                                  onPressed: () => _exportPersonStatement(p),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('تعریف طرف‌حساب جدید'),
          onPressed: _openAddPerson,
        ),
      ],
    );

    if (widget.asTab) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اشخاص و طرف‌حساب‌ها'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'تعریف طرف‌حساب جدید',
              onPressed: _openAddPerson,
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
