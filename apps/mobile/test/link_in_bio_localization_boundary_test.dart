import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/models/link_in_bio_appearance.dart';
import 'package:postdee_mobile/core/models/profile_template_catalog.generated.dart';
import 'package:postdee_mobile/core/network/api_error_message.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_draft_store.dart';
import 'package:postdee_mobile/features/link_in_bio/link_in_bio_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(ValueNotifier<Locale> locale, Widget child) =>
    ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (context, value, _) => MaterialApp(
        locale: value,
        supportedLocales: PostDeeLocalizations.supportedLocales,
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('helper falls back to Thai without the app delegate',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        expect(linkInBioUsesThai(context), isTrue);
        expect(linkInBioText(context, 'ข้อมูลร้าน', 'Store info'), 'ข้อมูลร้าน');
        return const LinkInBioText('บันทึกแบบร่างในเครื่องแล้ว');
      }),
    ));
    expect(find.text('บันทึกแบบร่างในเครื่องแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final cachedMessages = <String, String>{
    'บันทึกแบบร่างในเครื่องแล้ว': 'Draft saved on this device',
    apiErrorMessage(StateError('offline')):
        'Could not complete the action. Please try again.',
    apiErrorMessage(TimeoutException('slow')):
        'The request took too long. Please try again.',
    apiErrorMessage(const SocketException('offline')):
        'Cannot connect to PostDee. Check your internet connection and try again.',
    apiErrorMessage(const ApiException('server', statusCode: 503)):
        'PostDee is temporarily unavailable. Please try again later.',
    apiErrorMessage(const ApiException('expired', statusCode: 401)):
        'Please sign in again and retry.',
    apiErrorMessage(const ApiException('limit', statusCode: 429)):
        'Too many requests. Wait a moment and try again.',
  };
  for (final entry in cachedMessages.entries) {
    testWidgets('cached app message follows the current locale: ${entry.key}',
        (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(_app(locale, LinkInBioText(entry.key)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      locale.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text(entry.key), findsOneWidget);
      locale.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final limit in [2, 7, 20]) {
    testWidgets('cached plan limit $limit keeps additions and publication distinct',
        (tester) async {
      final messages = <String, String>{
        'แพ็กเกจนี้เพิ่มได้สูงสุด $limit ลิงก์ รวมลิงก์ที่ปิดไว้ หากต้องการเพิ่ม ให้ลบลิงก์เดิมหรืออัปเกรดแพ็กเกจ':
            'Your plan allows up to $limit links, including hidden links. Delete an existing link or upgrade your plan to add another.',
        'แพ็กเกจนี้เปิดใช้ได้สูงสุด $limit ลิงก์ กรุณาปิดลิงก์ส่วนเกินก่อนเผยแพร่ ข้อมูลเดิมยังอยู่':
            'Your plan allows up to $limit active links. Disable extra links before publishing. Your existing data has been kept.',
        'แพ็กเกจนี้เปิดใช้ได้สูงสุด $limit ลิงก์ กรุณาปิดลิงก์อื่นก่อน':
            'Your plan allows up to $limit active links. Disable another link first.',
      };
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(_app(locale, Column(children: [
        for (final message in messages.keys) LinkInBioText(message),
      ])));
      await tester.pumpAndSettle();
      for (final english in messages.values) {
        expect(find.text(english), findsOneWidget);
      }
      locale.value = const Locale('th');
      await tester.pumpAndSettle();
      for (final thai in messages.keys) {
        expect(find.text(thai), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unknown text and near matches remain exact across languages',
      (tester) async {
    const rawMessages = [
      'ข้อความจากผู้ให้บริการ provider-code-42',
      'ร้านแจ้งว่า: บันทึกแบบร่างในเครื่องแล้ว',
      'แพ็กเกจนี้เปิดใช้ได้สูงสุด 2 ลิงก์ กรุณาปิดลิงก์อื่นก่อน เพิ่มเติม',
      'Unknown provider detail: ข้อมูลร้าน',
    ];
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(_app(locale, Column(children: [
      for (final raw in rawMessages) LinkInBioText(raw),
    ])));
    for (final value in [const Locale('en'), const Locale('th')]) {
      locale.value = value;
      await tester.pumpAndSettle();
      for (final raw in rawMessages) {
        expect(find.text(raw), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('all catalog labels translate without changing catalog identities',
      (tester) async {
    final original = [
      for (final template in profileTemplates)
        (template.id, template.name, template.category, template.themeId),
    ];
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(_app(locale,
        Builder(builder: (context) {
      for (final name in [
        ...profileTemplates.map((template) => template.name),
        ...profileTemplateCategories.values,
        ...linkInBioThemeNames.values,
      ]) {
        expect(localizeLinkInBioMessage(context, name),
            isNot(matches(RegExp(r'[\u0E00-\u0E7F]'))), reason: name);
      }
      return const SizedBox.shrink();
    })));
    expect([
      for (final template in profileTemplates)
        (template.id, template.name, template.category, template.themeId),
    ], original);
  });

  testWidgets('locale changes leave saved merchant text and appearance intact',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesLinkInBioDraftStore(ownerUserId: 'boundary');
    const draft = LinkInBioDraft(
      storeName: 'ร้านของคุณ',
      slug: 'boundary-shop',
      autoUpdateFromScheduledPosts: false,
      enabledLinkIds: {'email'},
      customLinks: [
        LinkInBioCustomLink(
          id: 'email', title: 'ส่งอีเมล', url: 'mailto:shop@example.com',
          category: 'เรียบง่าย', icon: 'email'),
        LinkInBioCustomLink(
          id: 'phone', title: 'โทรหาร้าน', url: 'tel:+66812345678',
          category: 'ข้อมูลร้าน', icon: 'phone'),
      ],
      appearance: LinkInBioAppearance(
        description: 'สร้างหน้าเว็บร้านค้าด้วย PostDee',
        featuredLinkId: 'email', featuredLabel: 'โปรวันนี้'),
    );
    await store.saveDraft(draft);
    final before = await store.loadDraft();
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(_app(locale, Column(children: [
      Text(draft.storeName),
      for (final link in draft.customLinks) Text(link.title),
      const LinkInBioText('บันทึกแบบร่างในเครื่องแล้ว'),
    ])));
    for (final value in [const Locale('en'), const Locale('th'), const Locale('en')]) {
      locale.value = value;
      await tester.pumpAndSettle();
      expect(find.text(draft.storeName), findsOneWidget);
      for (final link in draft.customLinks) {
        expect(find.text(link.title), findsOneWidget);
      }
      final saved = await store.loadDraft();
      expect(saved!.storeName, before!.storeName);
      expect(saved.slug, before.slug);
      expect(saved.enabledLinkIds, before.enabledLinkIds);
      expect(jsonEncode(saved.customLinks.map((link) => link.toJson()).toList()),
          jsonEncode(before.customLinks.map((link) => link.toJson()).toList()));
      expect(saved.appearance.toJson(), before.appearance.toJson());
    }
    expect(tester.takeException(), isNull);
  });
}
