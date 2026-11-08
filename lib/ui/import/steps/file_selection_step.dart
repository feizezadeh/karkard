import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/material.dart';

import '../../../core/platform_ports.dart';

class FileSelectionStep extends StatefulWidget {
  final FileImportSource? importSource;
  final Uint8List? initialBytes;
  final String? initialFileName;
  final void Function(
    Uint8List bytes,
    String fileName,
    String sheetName,
    bool hasHeader,
  ) onNext;

  const FileSelectionStep({
    super.key,
    this.importSource,
    this.initialBytes,
    this.initialFileName,
    required this.onNext,
  });

  @override
  State<FileSelectionStep> createState() => _FileSelectionStepState();
}

class _FileSelectionStepState extends State<FileSelectionStep> {
  Uint8List? _bytes;
  String? _fileName;
  String? _selectedSheet;
  List<String> _sheets = [];
  int _rowCount = 0;
  bool _hasHeader = true;
  String? _errorMessage;
  final _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialBytes != null) {
      _loadBytes(widget.initialBytes!, widget.initialFileName ?? 'fixture.xlsx');
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _loadBytes(Uint8List bytes, String fileName) {
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheets = excel.tables.keys.toList();
      if (sheets.isEmpty) {
        setState(() {
          _errorMessage = 'فایل اکسل انتخاب‌شده هیچ شیت داده‌ای ندارد.';
          _bytes = null;
          _sheets = [];
        });
        return;
      }

      final activeSheet = excel.getDefaultSheet() ?? sheets.first;
      final count = excel.tables[activeSheet]?.rows.length ?? 0;

      setState(() {
        _bytes = bytes;
        _fileName = fileName;
        _sheets = sheets;
        _selectedSheet = activeSheet;
        _rowCount = count;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطا در خواندن فایل اکسل: $e';
        _bytes = null;
        _sheets = [];
      });
    }
  }

  Future<void> _pickFile() async {
    if (widget.importSource != null) {
      try {
        final picked = await widget.importSource!.pickExcel();
        if (picked != null) {
          _loadBytes(picked.bytes, picked.name);
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'خطا در بارگذاری فایل: $e';
        });
      }
    } else {
      _showPathInputDialog();
    }
  }

  void _showPathInputDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('انتخاب مسیر فایل اکسل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مسیر فایل اکسل (.xlsx) را در سیستم وارد کنید:'),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'مسیر کامل فایل',
                hintText: '/home/user/transactions.xlsx',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final path = _pathController.text.trim();
              if (path.isNotEmpty) {
                final file = File(path);
                if (file.existsSync()) {
                  final bytes = file.readAsBytesSync();
                  Navigator.of(ctx).pop();
                  _loadBytes(bytes, file.uri.pathSegments.last);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فایل در مسیر مشخص‌شده یافت نشد.')),
                  );
                }
              }
            },
            child: const Text('بارگذاری'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickFile,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                child: Column(
                  children: [
                    Icon(
                      _bytes != null ? Icons.description_outlined : Icons.upload_file_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fileName ?? 'انتخاب فایل اکسل (.xlsx)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _bytes != null
                          ? '${(_bytes!.length / 1024).toStringAsFixed(1)} کیلوبایت'
                          : 'برای انتخاب یا بارگذاری فایل کلیک کنید',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
          if (_bytes != null && _sheets.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSheet,
                    decoration: const InputDecoration(
                      labelText: 'شیت فعال در اکسل',
                      border: OutlineInputBorder(),
                    ),
                    items: _sheets
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (sheet) {
                      if (sheet != null) {
                        final excel = Excel.decodeBytes(_bytes!);
                        setState(() {
                          _selectedSheet = sheet;
                          _rowCount = excel.tables[sheet]?.rows.length ?? 0;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'تعداد ردیف‌ها: $_rowCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('ردیف اول فایل شامل عنوان ستون‌ها است'),
              value: _hasHeader,
              onChanged: (v) => setState(() => _hasHeader = v ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('proceed_to_mapping_button'),
            onPressed: _bytes != null && _selectedSheet != null
                ? () => widget.onNext(
                      _bytes!,
                      _fileName ?? 'transactions.xlsx',
                      _selectedSheet!,
                      _hasHeader,
                    )
                : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('ادامه به مرحله نگاشت ستون‌ها'),
          ),
        ],
      ),
    );
  }
}
