import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_connection_url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('postdee/social_connection_browser');
  final uri = Uri.parse(
    'https://www.tiktok.com/v2/auth/authorize/?state=unchanged%2Bstate',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android opens the unchanged authorization URL in a Custom Tab',
      () async {
    final opened = <Uri>[];
    var externalCalls = 0;

    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openCustomTab: (url) async {
        opened.add(url);
        return true;
      },
      openExternalBrowser: (_) async {
        externalCalls += 1;
        return true;
      },
    );

    expect(result, isTrue);
    expect(opened, [uri]);
    expect(externalCalls, 0);
  });

  test('Android uses an external browser when Custom Tabs are unavailable',
      () async {
    final opened = <Uri>[];

    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openCustomTab: (_) async => false,
      openExternalBrowser: (url) async {
        opened.add(url);
        return true;
      },
    );

    expect(result, isTrue);
    expect(opened, [uri]);
  });

  for (final error in [
    PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    MissingPluginException(),
  ]) {
    test('Android falls back when the Custom Tab raises ${error.runtimeType}',
        () async {
      var externalCalls = 0;

      final result = await launchSocialConnectionUrl(
        uri,
        platform: TargetPlatform.android,
        openCustomTab: (_) async => throw error,
        openExternalBrowser: (_) async {
          externalCalls += 1;
          return true;
        },
      );

      expect(result, isTrue);
      expect(externalCalls, 1);
    });
  }

  test('other platforms retain external-browser behavior', () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
      var customTabCalls = 0;
      final opened = <Uri>[];

      final result = await launchSocialConnectionUrl(
        uri,
        platform: platform,
        openCustomTab: (_) async {
          customTabCalls += 1;
          return true;
        },
        openExternalBrowser: (url) async {
          opened.add(url);
          return true;
        },
      );

      expect(result, isTrue);
      expect(customTabCalls, 0);
      expect(opened, [uri]);
    }
  });

  test('returns false when neither browser can open the URL', () async {
    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openCustomTab: (_) async => false,
      openExternalBrowser: (_) async => false,
    );

    expect(result, isFalse);
  });

  test('returns false when the external browser raises a platform error',
      () async {
    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openCustomTab: (_) async => false,
      openExternalBrowser: (_) async =>
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(result, isFalse);
  });

  test('does not execute a non-HTTPS or hostless authorization URL', () async {
    var openCalls = 0;
    Future<bool> open(Uri _) async {
      openCalls += 1;
      return true;
    }

    for (final url in [
      'http://www.tiktok.com/authorize',
      'intent://authorize',
      'javascript:alert(1)',
      'https:/authorize',
    ]) {
      expect(
        await launchSocialConnectionUrl(
          Uri.parse(url),
          platform: TargetPlatform.android,
          openCustomTab: open,
          openExternalBrowser: open,
        ),
        isFalse,
      );
    }

    expect(openCalls, 0);
  });

  test('default Android adapter calls the strict native Custom Tab channel',
      () async {
    final calls = <MethodCall>[];
    var externalCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openExternalBrowser: (_) async {
        externalCalls += 1;
        return true;
      },
    );

    expect(result, isTrue);
    expect(calls.single.method, 'openCustomTab');
    expect(calls.single.arguments, uri.toString());
    expect(externalCalls, 0);
  });

  test('an unavailable native channel still opens the external browser',
      () async {
    var externalCalls = 0;

    final result = await launchSocialConnectionUrl(
      uri,
      platform: TargetPlatform.android,
      openExternalBrowser: (_) async {
        externalCalls += 1;
        return true;
      },
    );

    expect(result, isTrue);
    expect(externalCalls, 1);
  });
}
