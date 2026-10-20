import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_settings.dart';
import 'package:postdee_mobile/features/uploader/tiktok_publishing_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outputDirectory = Platform.environment['POSTDEE_DIRECT_PREVIEW_DIR'];

  testWidgets('renders real Direct Post settings with local fixture capabilities',
      (tester) async {
    final previousTheme = AppTheme.isLightMode ? ThemeMode.light : ThemeMode.dark;
    AppTheme.applyThemeMode(ThemeMode.light);
    addTearDown(() => AppTheme.applyThemeMode(previousTheme));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final fonts = FontLoader('Anuphan');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

    const options = TikTokPublishingOptionsResult(
      connectionId: 'preview-local-connection',
      creatorInfoRevision:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      creatorInfo: TikTokCreatorInfo(
        creatorAvatarUrl: '',
        creatorUsername: 'preview_creator',
        creatorNickname: 'บัญชีตัวอย่างสำหรับดูหน้าจอ',
        privacyLevelOptions: [
          TikTokPrivacyLevel.publicToEveryone,
          TikTokPrivacyLevel.mutualFollowFriends,
          TikTokPrivacyLevel.selfOnly,
        ],
        commentDisabled: false,
        duetDisabled: true,
        stitchDisabled: false,
        maxVideoPostDurationSec: 3600,
      ),
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<TikTokSettingsSelection>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => TikTokPublishingSettingsSheet(
                    initialSettings: const PlatformPublishSettings(
                        tiktokPublishMode: TikTokPublishMode.directPost),
                    loadOptions: () async => options,
                    isCurrent: () => true,
                  ),
                ),
                child: const Text('ดูตัวอย่างการตั้งค่า TikTok'),
              ),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('ดูตัวอย่างการตั้งค่า TikTok'));
    await tester.pumpAndSettle();

    FilledButton save() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('uploader-platform-settings-save')));
    CheckboxListTile checkbox(String suffix) => tester.widget<CheckboxListTile>(
        find.byKey(ValueKey('uploader-tiktok-$suffix')));

    expect(
        tester
            .widget<DropdownButtonFormField<TikTokPrivacyLevel>>(
                find.byKey(const ValueKey('uploader-tiktok-privacy')))
            .initialValue,
        isNull);
    expect(checkbox('allow-comment').value, isFalse);
    expect(checkbox('allow-duet').value, isFalse);
    expect(checkbox('allow-duet').onChanged, isNull);
    expect(checkbox('allow-stitch').value, isFalse);
    expect(save().onPressed, isNull);
    expect(tester.takeException(), isNull);

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          final directory = Directory(outputDirectory!);
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await capture('tiktok-direct-defaults');

    await tester.tap(find.byKey(const ValueKey('uploader-tiktok-privacy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ทุกคน').last);
    await tester.pumpAndSettle();

    Future<void> select(String suffix) async {
      final control = find.byKey(ValueKey('uploader-tiktok-$suffix'));
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
    }

    await select('music-consent');
    final privacy = find.byKey(const ValueKey('uploader-tiktok-privacy'));
    await tester.ensureVisible(privacy);
    await tester.pumpAndSettle();
    await tester.tap(privacy);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพื่อนที่ติดตามกัน').last);
    await tester.pumpAndSettle();
    expect(checkbox('music-consent').value, isTrue);
    expect(save().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await capture('tiktok-direct-viewers-after-consent');
    await tester.ensureVisible(
        find.byKey(const ValueKey('uploader-tiktok-music-consent')));
    await capture('tiktok-direct-consent-after-viewers');

    await select('commercial');
    expect(checkbox('music-consent').value, isFalse);
    await select('third-party');
    await select('music-consent');
    await select('brand-consent');
    expect(checkbox('third-party').value, isTrue);
    expect(checkbox('music-consent').value, isTrue);
    expect(checkbox('brand-consent').value, isTrue);
    expect(save().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await capture('tiktok-direct-commercial-consent');
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: outputDirectory == null || outputDirectory.isEmpty);
}
