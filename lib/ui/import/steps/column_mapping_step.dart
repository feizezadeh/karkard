import 'dart:typed_data';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/material.dart';

import '../../../data/database.dart';
import '../../../domain/tx_type.dart';
import '../../../services/excel_import_service.dart';

class ColumnMappingStep extends StatefulWidget {
  final Uint8List bytes;
  final String sheetName;
  final bool hasHeader;
  final String projectId;
  final List<CashAccount> cashAccounts;
  final ValueChanged<ColumnMapping> onConfirmMapping;
  final VoidCallback onBack;

  const ColumnMappingStep({
    super.key,
    required this.bytes,
    required this.sheetName,
    required this.hasHeader,
    required this.projectId,
    required this.cashAccounts,
    required this.onConfirmMapping,
    required this.onBack,
  });

  @override
  State<ColumnMappingStep> createState() => _ColumnMappingStepState();
}

class _ColumnMappingStepState extends State<ColumnMappingStep> {
  late Sheet _sheet;
  List<String> _columnHeaders = [];

  int _dateColumn = 0;
  int? _descriptionColumn;
  int? _amountColumn;
  int? _typeColumn;
  int? _counterpartyColumn;
  int? _accountColumn;

  TxType _defaultType = TxType.expense;
  String? _defaultCashAccountId;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    final excel = Excel.decodeBytes(widget.bytes);
    _sheet = excel.tables[widget.sheetName]!;

    if (_sheet.rows.isNotEmpty) {
      final headerRow = _sheet.rows.first;
      _columnHeaders = List.generate(headerRow.length, (colIdx) {
        if (widget.hasHeader) {
          final cellStr = ExcelCellReader.readString(headerRow[colIdx]);
          if (cellStr != null && cellStr.trim().isNotEmpty) {
            return cellStr.trim();
          }
        }
        return 'ستون ${colIdx + 1}';
      });

      _autoDetectColumns();
    }

    if (widget.cashAccounts.isNotEmpty) {
      final mainCash = widget.cashAccounts.where((a) => a.kind == 'project').firstOrNull;
      _defaultCashAccountId = mainCash?.id ?? widget.cashAccounts.first.id;
    }
  }

  void _autoDetectColumns() {
    for (var i = 0; i < _columnHeaders.length; i++) {
      final h = _columnHeaders[i].toLowerCase();
      if (h.contains('تاریخ') || h.contains('date')) {
        _dateColumn = i;
      } else if (h.contains('مبلغ') || h.contains('قیمت') || h.contains('amount')) {
        _amountColumn ??= i;
      } else if (h.contains('شرح') || h.contains('بابت') || h.contains('desc')) {
        _descriptionColumn ??= i;
      } else if (h.contains('نوع') || h.contains('type')) {
        _typeColumn ??= i;
      } else if (h.contains('طرف') || h.contains('شخص') || h.contains('کارفرما') || h.contains('پیمانکار')) {
        _counterpartyColumn ??= i;
      } else if (h.contains('حساب') || h.contains('صندوق') || h.contains('بانک') || h.contains('account')) {
        _accountColumn ??= i;
      }
    }

    _amountColumn ??= (_columnHeaders.length > 2 ? 2 : 0);
    _descriptionColumn ??= (_columnHeaders.length > 1 ? 1 : null);
  }

  ColumnMapping _buildMapping() {
    return ColumnMapping(
      dateColumn: _dateColumn,
      amountColumn: _amountColumn,
      descriptionColumn: _descriptionColumn,
      typeColumn: _typeColumn,
      counterpartyColumn: _counterpartyColumn,
      accountColumn: _accountColumn,
      defaultType: _defaultType,
      defaultCashAccountId: _defaultCashAccountId,
      hasHeader: widget.hasHeader,
      sheetName: widget.sheetName,
    );
  }

  List<List<String>> _getPreviewRows() {
    final startIndex = widget.hasHeader ? 1 : 0;
    final preview = <List<String>>[];
    for (var i = startIndex; i < _sheet.rows.length && preview.length < 3; i++) {
      final row = _sheet.rows[i];
      if (row.isEmpty) continue;

      final dateStr = _dateColumn < row.length ? (ExcelCellReader.readString(row[_dateColumn]) ?? '-') : '-';
      final descStr = (_descriptionColumn != null && _descriptionColumn! < row.length)
          ? (ExcelCellReader.readString(row[_descriptionColumn!]) ?? '-')
          : '-';
      final amtStr = (_amountColumn != null && _amountColumn! < row.length)
          ? (ExcelCellReader.readString(row[_amountColumn!]) ?? '-')
          : '-';
      final typeStr = (_typeColumn != null && _typeColumn! < row.length)
          ? (ExcelCellReader.readString(row[_typeColumn!]) ?? _defaultType.label)
          : _defaultType.label;
      final partyStr = (_counterpartyColumn != null && _counterpartyColumn! < row.length)
          ? (ExcelCellReader.readString(row[_counterpartyColumn!]) ?? '-')
          : '-';
      final accStr = (_accountColumn != null && _accountColumn! < row.length)
          ? (ExcelCellReader.readString(row[_accountColumn!]) ?? '-')
          : '-';

      preview.add([dateStr, descStr, amtStr, typeStr, partyStr, accStr]);
    }
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    final previewRows = _getPreviewRows();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'نگاشت ستون‌های اکسل به فیلدهای دفتر',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ستون‌های فایل اکسل را به فیلدهای متناظر متصل کنید. در صورت نبود ستون نوع یا صندوق، مقادیر پیش‌فرض استفاده می‌شوند.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),

          // Grid of Dropdowns
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _dateColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون تاریخ (الزامی)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  items: List.generate(_columnHeaders.length, (idx) {
                    return DropdownMenuItem(
                      value: idx,
                      child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _dateColumn = val);
                  },
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _amountColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون مبلغ (الزامی)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  items: List.generate(_columnHeaders.length, (idx) {
                    return DropdownMenuItem(
                      value: idx,
                      child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                    );
                  }),
                  onChanged: (val) => setState(() => _amountColumn = val),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _descriptionColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون شرح تراکنش',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('بدون ستون', overflow: TextOverflow.ellipsis)),
                    ...List.generate(_columnHeaders.length, (idx) {
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _descriptionColumn = val),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _typeColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون نوع تراکنش',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('استفاده از نوع پیش‌فرض', overflow: TextOverflow.ellipsis)),
                    ...List.generate(_columnHeaders.length, (idx) {
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _typeColumn = val),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _counterpartyColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون طرف حساب',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('بدون ستون', overflow: TextOverflow.ellipsis)),
                    ...List.generate(_columnHeaders.length, (idx) {
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _counterpartyColumn = val),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _accountColumn,
                  decoration: const InputDecoration(
                    labelText: 'ستون صندوق / حساب',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('استفاده از صندوق پیش‌فرض', overflow: TextOverflow.ellipsis)),
                    ...List.generate(_columnHeaders.length, (idx) {
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(_columnHeaders[idx], overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _accountColumn = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Defaults Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TxType>(
                  isExpanded: true,
                  initialValue: _defaultType,
                  decoration: const InputDecoration(
                    labelText: 'نوع پیش‌فرض (در صورت نبود ستون نوع)',
                    border: OutlineInputBorder(),
                  ),
                  items: TxType.values.map((t) {
                    final label = switch (t) {
                      TxType.workIn => '🟢 کارکرد و درآمد (طلب از کارفرما)',
                      TxType.income => '🟢 دریافتی نقدی کارفرما',
                      TxType.expense => '🔴 هزینه کارگاه و قطعات',
                      TxType.payout => '🔵 پرداخت و تسویه به شخص/شریک',
                      TxType.workOut => 'کارکرد بدهی به شخص',
                      TxType.transfer => 'انتقال بین حساب‌ها',
                    };
                    return DropdownMenuItem(value: t, child: Text(label, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _defaultType = val);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _defaultCashAccountId,
                  decoration: const InputDecoration(
                    labelText: 'صندوق پیش‌فرض پروژه',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.cashAccounts.map((a) {
                    return DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) => setState(() => _defaultCashAccountId = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3-Row Live Preview Table
          const Text(
            'پیش‌نمایش زنده ۳ ردیف اول با نگاشت فعلی:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('تاریخ')),
                  DataColumn(label: Text('شرح')),
                  DataColumn(label: Text('مبلغ')),
                  DataColumn(label: Text('نوع')),
                  DataColumn(label: Text('طرف حساب')),
                  DataColumn(label: Text('حساب')),
                ],
                rows: previewRows.map((r) {
                  return DataRow(cells: [
                    DataCell(Text(r[0])),
                    DataCell(Text(r[1], maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DataCell(Text(r[2])),
                    DataCell(Text(r[3])),
                    DataCell(Text(r[4])),
                    DataCell(Text(r[5])),
                  ]);
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('مرحله قبل'),
              ),
              FilledButton.icon(
                key: const Key('proceed_to_review_button'),
                onPressed: () => widget.onConfirmMapping(_buildMapping()),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('پردازش و ورود به صفحه بازبینی'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
