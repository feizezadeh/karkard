import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/ui/adaptive_layout.dart';
import 'package:karkard/ui/legacy_database_screen.dart';
import 'package:karkard/ui/platform_shortcuts.dart';

Widget host(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  Future<void> size(WidgetTester t, double w) async {
    t.view.physicalSize = Size(w, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('AdaptiveLayout: wide width shows table', (t) async {
    await size(t, 1000);
    await t.pumpWidget(host(AdaptiveLayout(
        wide: (_) => const Text('WIDE'), narrow: (_) => const Text('NARROW'))));
    expect(find.text('WIDE'), findsOneWidget);
    expect(find.text('NARROW'), findsNothing);
  });

  testWidgets('AdaptiveLayout: narrow width shows cards', (t) async {
    await size(t, 400);
    await t.pumpWidget(host(AdaptiveLayout(
        wide: (_) => const Text('WIDE'), narrow: (_) => const Text('NARROW'))));
    expect(find.text('NARROW'), findsOneWidget);
    expect(find.text('WIDE'), findsNothing);
  });

  testWidgets('shortcuts: Ctrl+N fires on linux, FAB hidden', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var n = 0;
    await t.pumpWidget(host(DesktopShortcuts(
        onNewTx: () => n++, child: NewTxButton(onPressed: () {}))));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(n, 1);
    expect(find.byType(FloatingActionButton), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shortcuts: Ctrl+N inactive on android, FAB shown', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var n = 0;
    await t.pumpWidget(host(DesktopShortcuts(
        onNewTx: () => n++, child: NewTxButton(onPressed: () {}))));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(n, 0);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  group('LegacyDatabaseScreen widget tests', () {
    testWidgets('shows Persian error message and reset button', (t) async {
      const ex = LegacyDatabaseException(
        fromVersion: 1,
        toVersion: 2,
        message: 'نسخه دیتابیس قدیمی است',
      );
      var resetCalled = false;
      await t.pumpWidget(MaterialApp(
        home: LegacyDatabaseScreen(
          exception: ex,
          onReset: () async => resetCalled = true,
        ),
      ));

      expect(find.text('خطای ارتقای دیتابیس'), findsOneWidget);
      expect(find.text('پایگاه داده قدیمی شناسایی شد'), findsOneWidget);
      expect(find.text('نسخه دیتابیس قدیمی است'), findsOneWidget);
      expect(find.text('نسخه فعلی: 1 | نسخه مورد نیاز: 2'), findsOneWidget);
      expect(find.text('بازنشانی دیتابیس'), findsOneWidget);
      expect(resetCalled, isFalse);
    });

    testWidgets('cancel in dialog does not trigger onReset', (t) async {
      const ex = LegacyDatabaseException(fromVersion: 1, toVersion: 2);
      var resetCalled = false;
      await t.pumpWidget(MaterialApp(
        home: LegacyDatabaseScreen(
          exception: ex,
          onReset: () async => resetCalled = true,
        ),
      ));

      await t.tap(find.text('بازنشانی دیتابیس'));
      await t.pumpAndSettle();

      expect(find.text('تأیید بازنشانی دیتابیس'), findsOneWidget);
      await t.tap(find.text('انصراف'));
      await t.pumpAndSettle();

      expect(find.text('تأیید بازنشانی دیتابیس'), findsNothing);
      expect(resetCalled, isFalse);
    });

    testWidgets('confirm in dialog triggers onReset', (t) async {
      const ex = LegacyDatabaseException(fromVersion: 1, toVersion: 2);
      var resetCalled = false;
      await t.pumpWidget(MaterialApp(
        home: LegacyDatabaseScreen(
          exception: ex,
          onReset: () async => resetCalled = true,
        ),
      ));

      await t.tap(find.text('بازنشانی دیتابیس'));
      await t.pumpAndSettle();

      expect(find.text('تأیید بازنشانی دیتابیس'), findsOneWidget);
      await t.tap(find.text('بله، بازنشانی شود'));
      await t.pumpAndSettle();

      expect(resetCalled, isTrue);
    });

    testWidgets('secondary error displayed when onReset fails', (t) async {
      const ex = LegacyDatabaseException(fromVersion: 1, toVersion: 2);
      await t.pumpWidget(MaterialApp(
        home: LegacyDatabaseScreen(
          exception: ex,
          onReset: () async => throw Exception('Disk I/O failure'),
        ),
      ));

      await t.tap(find.text('بازنشانی دیتابیس'));
      await t.pumpAndSettle();

      expect(find.text('تأیید بازنشانی دیتابیس'), findsOneWidget);
      await t.tap(find.text('بله، بازنشانی شود'));
      await t.pumpAndSettle();

      expect(find.textContaining('خطا در بازنشانی دیتابیس: Exception: Disk I/O failure'), findsOneWidget);
    });
  });
}
