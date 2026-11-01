import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/connections_screen.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'com.postdee.postdee_mobile/secure_custom_tabs',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final connectUri = Uri.parse(
    'https://www.tiktok.com/v2/auth/authorize?state=opaque%2Bstate%2Fvalue&redirect_uri=https%3A%2F%2Fapi.postpeer.dev%2Fcallback&code_challenge=original',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android stops after an installed app opens the unchanged OAuth URL',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect(call.arguments, {'url': connectUri.toString()});
      return true;
    });
    final opened = await launchSocialConnectUrl(
      connectUri,
      launchCustomTab: (_) async {
        calls.add('custom-tab');
        return true;
      },
      launch: (_, {required mode, required browserConfiguration}) async {
        calls.add('external');
        return true;
      },
    );
    expect(opened, isTrue);
    expect(calls, ['launchApp']);
  });

  for (final appThrows in [false, true]) {
    test('Android app launch rejection ($appThrows) falls back to a Custom Tab',
        () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, {'url': connectUri.toString()});
        if (appThrows) throw PlatformException(code: 'APP_UNAVAILABLE');
        return false;
      });
      expect(
        await launchSocialConnectUrl(
          connectUri,
          launchCustomTab: (uri) async {
            expect(uri.toString(), connectUri.toString());
            calls.add('custom-tab');
            return true;
          },
          launch: (_, {required mode, required browserConfiguration}) async {
            calls.add('external');
            return true;
          },
        ),
        isTrue,
      );
      expect(calls, ['launchApp', 'custom-tab']);
    });
  }

  for (final customTabThrows in [false, true]) {
    test('Android secure browser rejection ($customTabThrows) falls back externally',
        () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, {'url': connectUri.toString()});
        return false;
      });
      expect(
        await launchSocialConnectUrl(
          connectUri,
          launchCustomTab: (uri) async {
            expect(uri.toString(), connectUri.toString());
            calls.add('custom-tab');
            if (customTabThrows) throw StateError('Custom Tab unavailable');
            return false;
          },
          launch: (uri, {required mode, required browserConfiguration}) async {
            expect(uri.toString(), connectUri.toString());
            expect(mode, LaunchMode.externalApplication);
            calls.add('external');
            return true;
          },
        ),
        isTrue,
      );
      expect(calls, ['launchApp', 'custom-tab', 'external']);
    });
  }

  test('Android reports failure when every safe surface rejects the link',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false;
    });
    expect(
      await launchSocialConnectUrl(
        connectUri,
        launch: (_, {required mode, required browserConfiguration}) async {
          calls.add('external');
          expect(mode, LaunchMode.externalApplication);
          return false;
        },
      ),
      isFalse,
    );
    expect(calls, ['launchApp', 'launch', 'external']);
  });

  test('iOS tries a universal-link app before any browser', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final modes = <LaunchMode>[];
    expect(
      await launchSocialConnectUrl(
        connectUri,
        launchCustomTab: (_) async => throw StateError('Android only'),
        launch: (uri, {required mode, required browserConfiguration}) async {
          expect(uri.toString(), connectUri.toString());
          modes.add(mode);
          return true;
        },
      ),
      isTrue,
    );
    expect(modes, [LaunchMode.externalNonBrowserApplication]);
  });

  for (final appThrows in [false, true]) {
    test('iOS app launch rejection ($appThrows) falls back to the external browser',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final modes = <LaunchMode>[];
      expect(
        await launchSocialConnectUrl(
          connectUri,
          launch: (uri, {required mode, required browserConfiguration}) async {
            expect(uri.toString(), connectUri.toString());
            modes.add(mode);
            if (mode == LaunchMode.externalNonBrowserApplication) {
              if (appThrows) throw StateError('Universal link unavailable');
              return false;
            }
            return true;
          },
        ),
        isTrue,
      );
      expect(modes, [
        LaunchMode.externalNonBrowserApplication,
        LaunchMode.externalApplication,
      ]);
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    test('desktop $platform uses only the external browser', () async {
      debugDefaultTargetPlatformOverride = platform;
      final modes = <LaunchMode>[];
      messenger.setMockMethodCallHandler(channel, (_) async {
        fail('Desktop must not call the Android channel');
      });
      expect(
        await launchSocialConnectUrl(
          connectUri,
          launch: (_, {required mode, required browserConfiguration}) async {
            modes.add(mode);
            return true;
          },
        ),
        isTrue,
      );
      expect(modes, [LaunchMode.externalApplication]);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final unsafe in [
      'http://www.tiktok.com/authorize',
      'https://attacker.example/authorize',
      'https://www.tiktok.com@attacker.example/authorize',
      'https://user:password@www.tiktok.com/authorize',
      'https://tiktok.com.attacker.example/authorize',
      'https://accounts.google.com.attacker.example/authorize',
      'intent://www.tiktok.com/authorize',
      'javascript:alert(1)',
    ]) {
      test('$platform rejects unsafe OAuth URI $unsafe before launching anything',
          () async {
        debugDefaultTargetPlatformOverride = platform;
        var calls = 0;
        messenger.setMockMethodCallHandler(channel, (_) async {
          calls++;
          return true;
        });
        final opened = await launchSocialConnectUrl(
          Uri.parse(unsafe),
          launchCustomTab: (_) async {
            calls++;
            return true;
          },
          launch: (_, {required mode, required browserConfiguration}) async {
            calls++;
            return true;
          },
        );
        expect(opened, isFalse);
        expect(calls, 0);
      });
    }
  }
}
