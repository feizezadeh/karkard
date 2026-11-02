import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/jalali.dart';
import 'core/money.dart';
import 'data/database.dart';
import 'domain/tx_type.dart';
import 'ui/adaptive_layout.dart';
import 'ui/platform_shortcuts.dart';
import 'ui/theme.dart';

final dbProvider = Provider<AppDatabase>((ref) =>
    throw StateError('dbProvider must be overridden in main()'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.openFile();
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const KarkardApp(),
  ));
}

class KarkardApp extends StatelessWidget {
  const KarkardApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دفتر کارکرد',
        theme: buildTheme(),
        locale: const Locale('fa', 'IR'),
        supportedLocales: const [Locale('fa', 'IR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const _Home(),
      );
}

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbProvider);
    void newTx() => ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تراکنش جدید (فاز ۱)')));
    // Hard-coded sample data (not read from the database).
    final rows = [
      (isoToJalali('2025-03-20'), TxType.workIn.label, 20000000),
      (isoToJalali('2025-03-21'), TxType.income.label, 1234567),
      (isoToJalali('2025-03-22'), TxType.expense.label, 350000),
      (isoToJalali('2025-03-23'), TxType.payout.label, 5000000),
    ];
    return DesktopShortcuts(
      onNewTx: newTx,
      child: Scaffold(
        appBar: AppBar(title: const Text('دفتر کارکرد')),
        floatingActionButton: NewTxButton(onPressed: newTx),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                'صفحه آزمایشی — داده نمونه ثابت (نه از دیتابیس) — ${isoToJalali('2025-03-20')}'),
          ),
          Expanded(
            child: AdaptiveLayout(
              wide: (_) => DataTable(columns: const [
                DataColumn(label: Text('تاریخ')),
                DataColumn(label: Text('شرح')),
                DataColumn(label: Text('مبلغ (تومان)'), numeric: true),
              ], rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(Text(r.$1)),
                    DataCell(Text(r.$2)),
                    DataCell(Text(formatToman(r.$3))),
                  ])
              ]),
              narrow: (_) => ListView(children: [
                for (final r in rows)
                  Card(
                    child: ListTile(
                      title: Text(r.$2),
                      subtitle: Text(r.$1),
                      trailing: Text(formatToman(r.$3)),
                    ),
                  )
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
