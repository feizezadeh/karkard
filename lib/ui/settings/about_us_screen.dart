import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const String developerName = 'مهدی فیضی زاده';
  static const String websiteUrl = 'https://mahdi.asia';
  static const String contactEmail = 'feizezadeh@gmail.com';
  static const String appVersion = '۲.۰.۰';

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label در حافظه کپی شد: $text'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('درباره ما'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              // Header Card with Logo and App Name
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/logo/karkard_logo.png',
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 88,
                              height: 88,
                              color: colorScheme.primary,
                              child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 48),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'دفتر کارکرد (Karkard Ledger)',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'سامانه تخصصی مدیریت مالی، پیمانکاری و عملیات کارگاهی و جرثقیل',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          toFaDigits('نسخه $appVersion • نگارش پایدار آفلاین'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Creator & Contact Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_outline, color: colorScheme.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'سازنده و توسعه‌دهنده',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(Icons.code, color: colorScheme.primary),
                        ),
                        title: const Text(
                          developerName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: const Text('طراحی معماری، توسعه نرم‌افزار و رابط کاربری'),
                      ),
                      const SizedBox(height: 8),

                      // Website item
                      Material(
                        color: colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(Icons.language, color: colorScheme.primary),
                          title: const Text('وب‌سایت شخصی', style: TextStyle(fontSize: 13)),
                          subtitle: const Text(
                            websiteUrl,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'کپی آدرس وب‌سایت',
                            onPressed: () => _copyToClipboard(context, websiteUrl, 'آدرس وب‌سایت'),
                          ),
                          onTap: () => _copyToClipboard(context, websiteUrl, 'آدرس وب‌سایت'),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Email item
                      Material(
                        color: colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(Icons.alternate_email, color: colorScheme.primary),
                          title: const Text('پست الکترونیکی (ایمیل)', style: TextStyle(fontSize: 13)),
                          subtitle: const Text(
                            contactEmail,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'کپی ایمیل',
                            onPressed: () => _copyToClipboard(context, contactEmail, 'ایمیل'),
                          ),
                          onTap: () => _copyToClipboard(context, contactEmail, 'ایمیل'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Core Values Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_outlined, color: colorScheme.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'ویژگی‌های کلیدی سامانه',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildFeatureRow(
                        context,
                        icon: Icons.shield_outlined,
                        title: 'امنیت و استقلال کامل داده‌ها',
                        desc: '۱۰۰٪ آفلاین و محلی؛ پایگاه داده شما همیشه در دستگاه خودتان ذخیره می‌شود.',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureRow(
                        context,
                        icon: Icons.balance,
                        title: 'تراز طلایی حسابداری استاندارد',
                        desc: 'تطابق خودکار دخل و خرج، کارکردها و دریافت/پرداخت‌ها طبق اصول حرفه‌ای.',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureRow(
                        context,
                        icon: Icons.backup_outlined,
                        title: 'پشتیبان‌گیری خودکار و بازیابی ایمن',
                        desc: 'ثبت خودکار نسخ پشتیبان روزانه با امکان انتقال سریع به حافظه جانبی.',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureRow(
                        context,
                        icon: Icons.table_chart_outlined,
                        title: 'ورود هوشمند از فایل‌های اکسل',
                        desc: 'تبدیل خودکار دفاتر کارکرد، ماشین‌آلات و تفکیک هزینه و درآمد با بازبینی دقیق.',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Copyright notice
              Center(
                child: Text(
                  toFaDigits('تمامی حقوق محفوظ است © ۱۴۰۵ (۲۰۲۶)'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
