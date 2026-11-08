import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/ui/settings/about_us_screen.dart';

void main() {
  testWidgets('AboutUsScreen renders creator, website, email, and copy actions', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AboutUsScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('درباره ما'), findsOneWidget);

    // Verify App Name
    expect(find.text('دفتر کارکرد (Karkard Ledger)'), findsOneWidget);

    // Verify Developer Name
    expect(find.text('مهدی فیضی زاده'), findsOneWidget);

    // Verify Website and Email
    expect(find.text('https://mahdi.asia'), findsOneWidget);
    expect(find.text('feizezadeh@gmail.com'), findsOneWidget);

    // Tap on copy buttons
    final copyIcons = find.byIcon(Icons.copy);
    expect(copyIcons, findsNWidgets(2));

    await tester.ensureVisible(copyIcons.first);
    await tester.tap(copyIcons.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('در حافظه کپی شد'), findsOneWidget);
  });
}
