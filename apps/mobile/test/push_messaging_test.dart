import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';
import 'package:postdee_mobile/features/notifications/firebase_push_messaging_gateway.dart';
import 'package:postdee_mobile/features/notifications/push_messaging_gateway.dart';
import 'package:postdee_mobile/features/notifications/push_notification.dart';

class FakeFirebaseMessagingClient implements FirebaseMessagingClient {
  FakeFirebaseMessagingClient({
    this.permissionGranted = true,
    this.token = 'device-token',
  });

  final bool permissionGranted;
  final String? token;
  final foreground = StreamController<PushNotificationMessage>.broadcast();
  final opened = StreamController<PushNotificationMessage>.broadcast();
  var permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    return permissionGranted;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<PushNotificationMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushNotificationMessage> get onMessageOpenedApp => opened.stream;
}

void main() {
  test('notification center stores newest first and notifies listeners', () {
    final center = PostDeeNotificationCenter();
    var notifyCount = 0;
    center.addListener(() => notifyCount += 1);

    center.add(PostDeeNotification(
      title: 'a',
      body: '1',
      receivedAt: DateTime(2026, 1, 1),
    ));
    center.add(PostDeeNotification(
      title: 'b',
      body: '2',
      receivedAt: DateTime(2026, 1, 2),
    ));

    expect(center.items, hasLength(2));
    expect(center.items.first.title, 'b');
    expect(notifyCount, 2);

    center.clear();
    expect(center.items, isEmpty);
    expect(notifyCount, 3);
  });

  test('FirebasePushMessagingGateway forwards the token and foreground messages',
      () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient();
    String? receivedToken;
    final gateway = FirebasePushMessagingGateway(
      client: client,
      center: center,
      onToken: (token) => receivedToken = token,
      now: () => DateTime(2026, 6, 24),
    );

    await gateway.initialize();

    expect(client.permissionRequests, 1);
    expect(receivedToken, 'device-token');

    client.foreground.add(
      const PushNotificationMessage(title: 'โพสต์เผยแพร่แล้ว', body: 'TikTok'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.items, hasLength(1));
    expect(center.items.first.title, 'โพสต์เผยแพร่แล้ว');
    expect(center.items.first.body, 'TikTok');

    await gateway.dispose();
  });

  test('FirebasePushMessagingGateway does nothing when permission is denied',
      () async {
    final center = PostDeeNotificationCenter();
    final client = FakeFirebaseMessagingClient(permissionGranted: false);
    final gateway =
        FirebasePushMessagingGateway(client: client, center: center);

    await gateway.initialize();
    client.foreground.add(
      const PushNotificationMessage(title: 'x', body: 'y'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(center.items, isEmpty);

    await gateway.dispose();
  });

  test('createPushMessagingGatewayFromConfig is disabled without Firebase', () {
    expect(
      createPushMessagingGatewayFromConfig(enableFirebaseAuth: false),
      isA<DisabledPushMessagingGateway>(),
    );
  });

  test(
      'createPushMessagingGatewayFromConfig is disabled when bootstrap fails',
      () {
    expect(
      createPushMessagingGatewayFromConfig(
        enableFirebaseAuth: true,
        firebaseBootstrapResult: const FirebaseBootstrapResult.setupError(
          'Firebase Auth is enabled but Firebase is not configured.',
        ),
      ),
      isA<DisabledPushMessagingGateway>(),
    );
  });
}
