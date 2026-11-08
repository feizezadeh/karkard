import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../services/excel_import_service.dart';

class ImportSummaryStep extends StatelessWidget {
  final ExcelImportResult result;
  final VoidCallback onClose;

  const ImportSummaryStep({
    super.key,
    required this.result,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green.shade200, width: 2),
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 52,
                color: Colors.green.shade700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'ورود اطلاعات با موفقیت انجام شد',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'تراکنش‌های تأییدشده با موفقیت در پایگاه داده ثبت و در لاگ بازرسی درج شدند.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 28),

          // Statistics Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'تراکنش‌های ثبت‌شده',
                  value: '${result.importedCount}',
                  icon: Icons.playlist_add_check,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'مجموع مبالغ ثبت‌شده',
                  value: '${formatToman(result.totalImportedAmount)} تومان',
                  icon: Icons.payments_outlined,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'ردیف‌های تکراری ردشده',
                  value: '${result.duplicatesSkippedCount}',
                  icon: Icons.copy,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  title: 'ردیف‌های ردشده توسط کاربر',
                  value: '${result.userSkippedCount}',
                  icon: Icons.person_off_outlined,
                  color: Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('view_ledger_button'),
            onPressed: onClose,
            icon: const Icon(Icons.check),
            label: const Text('مشاهده دفتر کارکرد'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: color.shade900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
