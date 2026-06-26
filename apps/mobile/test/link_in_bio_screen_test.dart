import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _linkInBioTestApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: child,
  );
}

Future<void> _scrollToLinkSection(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -640));
  await tester.pumpAndSettle();
}

Future<void> _addCustomLink(
  WidgetTester tester, {
  required String title,
  required String url,
}) async {
  await _scrollToLinkSection(tester);
  await tester.tap(find.text('เพิ่มลิงก์'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).at(2), title);
  await tester.enterText(find.byType(TextField).at(3), url);
  await tester.tap(find.text('บันทึกลิงก์'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves a Link in Bio draft and reloads it locally',
      (tester) async {
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );

    await tester.enterText(find.byType(TextField).at(0), 'ร้านมินาขายดี');
    await tester.enterText(find.byType(TextField).at(1), 'mina-shop');
    await _scrollToLinkSection(tester);

    await tester.tap(find.text('บันทึกแบบร่าง'));
    await tester.pumpAndSettle();

    expect(find.textContaining('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('ร้านมินาขายดี'), findsWidgets);
    expect(find.text('postdee.link/mina-shop'), findsOneWidget);
  });

  testWidgets('adds a custom Link in Bio button and saves it with the draft',
      (tester) async {
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );

    await _addCustomLink(
      tester,
      title: 'คูปอง Shopee',
      url: 'https://shopee.co.th/postdee-demo',
    );

    expect(find.text('คูปอง Shopee'), findsOneWidget);
    expect(find.text('https://shopee.co.th/postdee-demo'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();

    await tester.tap(find.text('บันทึกแบบร่าง'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );
    await tester.pumpAndSettle();

    await _scrollToLinkSection(tester);

    expect(find.text('คูปอง Shopee'), findsOneWidget);
    expect(find.text('https://shopee.co.th/postdee-demo'), findsOneWidget);
  });

  testWidgets('edits a custom Link in Bio button before saving the draft',
      (tester) async {
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );

    await _addCustomLink(
      tester,
      title: 'คูปอง Shopee',
      url: 'https://shopee.co.th/postdee-demo',
    );

    await tester.tap(find.byTooltip('แก้ไขลิงก์'));
    await tester.pumpAndSettle();

    expect(find.text('แก้ไขลิงก์'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), 'คูปอง Lazada');
    await tester.enterText(
      find.byType(TextField).at(3),
      'https://lazada.co.th/postdee-demo',
    );
    await tester.tap(find.text('บันทึกลิงก์'));
    await tester.pumpAndSettle();

    expect(find.text('คูปอง Shopee'), findsNothing);
    expect(find.text('คูปอง Lazada'), findsOneWidget);
    expect(find.text('https://lazada.co.th/postdee-demo'), findsOneWidget);
  });

  testWidgets('deletes a custom Link in Bio button from the draft',
      (tester) async {
    await tester.pumpWidget(
      _linkInBioTestApp(const LinkInBioScreen()),
    );

    await _addCustomLink(
      tester,
      title: 'คูปอง Shopee',
      url: 'https://shopee.co.th/postdee-demo',
    );

    await tester.tap(find.byTooltip('ลบลิงก์'));
    await tester.pumpAndSettle();

    expect(find.text('คูปอง Shopee'), findsNothing);
    expect(find.text('https://shopee.co.th/postdee-demo'), findsNothing);
  });
}
