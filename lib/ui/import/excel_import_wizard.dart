import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/platform_ports.dart';
import '../../data/database.dart';
import '../../services/excel_import_service.dart';
import 'steps/column_mapping_step.dart';
import 'steps/excel_review_screen.dart';
import 'steps/file_selection_step.dart';
import 'steps/import_summary_step.dart';

class ExcelImportWizard extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final FileImportSource? importSource;
  final Uint8List? initialBytes;
  final String? initialFileName;
  final VoidCallback? onImportComplete;

  const ExcelImportWizard({
    super.key,
    required this.db,
    required this.projectId,
    this.importSource,
    this.initialBytes,
    this.initialFileName,
    this.onImportComplete,
  });

  @override
  State<ExcelImportWizard> createState() => _ExcelImportWizardState();
}

class _ExcelImportWizardState extends State<ExcelImportWizard> {
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  Uint8List? _fileBytes;
  String? _fileName;
  String? _sheetName;
  bool _hasHeader = true;

  List<ParsedExcelRow> _parsedRows = [];
  ExcelImportResult? _importResult;
  List<CashAccount> _cashAccounts = [];

  late final ExcelImportService _importService;

  @override
  void initState() {
    super.initState();
    _importService = ExcelImportService(widget.db);
    _loadAccounts();
    if (widget.initialBytes != null) {
      _fileBytes = widget.initialBytes;
      _fileName = widget.initialFileName ?? 'fixture.xlsx';
    }
  }

  Future<void> _loadAccounts() async {
    final accs = await widget.db.select(widget.db.cashAccounts).get();
    if (mounted) {
      setState(() {
        _cashAccounts = accs;
      });
    }
  }

  Future<void> _handleFileSelected(
    Uint8List bytes,
    String fileName,
    String sheetName,
    bool hasHeader,
  ) async {
    setState(() {
      _fileBytes = bytes;
      _fileName = fileName;
      _sheetName = sheetName;
      _hasHeader = hasHeader;
      _currentStep = 1;
      _errorMessage = null;
    });
  }

  Future<void> _handleMappingConfirmed(ColumnMapping mapping) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rows = await _importService.parseExcel(
        _fileBytes!,
        projectId: widget.projectId,
        mapping: mapping,
      );

      setState(() {
        _parsedRows = rows;
        _isLoading = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطا در پردازش سطرهای اکسل: $e';
      });
    }
  }

  Future<void> _handleCommit(List<ParsedExcelRow> rows) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _importService.commitImport(
        rows,
        projectId: widget.projectId,
      );

      setState(() {
        _importResult = result;
        _isLoading = false;
        _currentStep = 3;
      });

      widget.onImportComplete?.call();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطا در ثبت تراکنش‌ها در دفتر: $e';
      });
    }
  }

  Widget _buildStepIndicator() {
    final steps = ['انتخاب فایل', 'نگاشت ستون‌ها', 'بازبینی ردیف‌ها', 'خلاصه'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: List.generate(steps.length, (idx) {
          final isCurrent = idx == _currentStep;
          final isCompleted = idx < _currentStep;

          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isCompleted
                      ? Colors.green
                      : (isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${idx + 1}',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[idx],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : (isCompleted ? Colors.black87 : Colors.grey),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (idx < steps.length - 1)
                  Icon(
                    Icons.chevron_left,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('در حال پردازش داده‌های اکسل...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _errorMessage = null),
                child: const Text('بازگشت و تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return switch (_currentStep) {
      0 => FileSelectionStep(
          importSource: widget.importSource,
          initialBytes: _fileBytes,
          initialFileName: _fileName,
          onNext: _handleFileSelected,
        ),
      1 => ColumnMappingStep(
          bytes: _fileBytes!,
          sheetName: _sheetName!,
          hasHeader: _hasHeader,
          projectId: widget.projectId,
          cashAccounts: _cashAccounts,
          onConfirmMapping: _handleMappingConfirmed,
          onBack: () => setState(() => _currentStep = 0),
        ),
      2 => ExcelReviewScreen(
          rows: _parsedRows,
          db: widget.db,
          projectId: widget.projectId,
          onCommit: _handleCommit,
          onBack: () => setState(() => _currentStep = 1),
        ),
      3 => ImportSummaryStep(
          result: _importResult!,
          onClose: () => Navigator.of(context).pop(),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ورود هوشمند از فایل اکسل'),
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  _buildStepIndicator(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
