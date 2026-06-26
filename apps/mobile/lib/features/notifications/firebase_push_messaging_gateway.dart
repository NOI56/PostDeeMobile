import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import 'push_messaging_gateway.dart';
import 'push_notification.dart';

/// A plain push message, decoupled from the firebase_messaging SDK so the
/// gateway logic can be unit-tested with a fake client.
class PushNotificationMessage {
  const PushNotificationMessage({required this.title, required this.body});

  final String title;
  final String body;
}

/// Thin, testable wrapper over the parts of firebase_messaging we use.
abstract class FirebaseMessagingClient {
  Future<bool> requestPermission();

  Future<String?> getToken();

  /// Messages received while the app is in the foreground.
  Stream<PushNotificationMessage> get onForegroundMessage;

  /// Messages tapped by the user to open the app from background.
  Stream<PushNotificationMessage> get onMessageOpenedApp;
}

/// Real Apple/Google push gateway backed by FCM. The platform calls are hidden
/// behind [FirebaseMessagingClient] so the mapping logic stays unit-testable.
///
/// Requires the FCM setup that is still pending: Firebase project with Cloud
/// Messaging, iOS APNs key + push capability, and a backend that stores the
/// device token and sends messages (see ROADMAP store-services notes).
class FirebasePushMessagingGateway implements PushMessagingGateway {
  FirebasePushMessagingGateway({
    required FirebaseMessagingClient client,
    PostDeeNotificationCenter? center,
    void Function(String token)? onToken,
    DateTime Function() now = DateTime.now,
  })  : _client = client,
        _center = center ?? PostDeeNotificationCenter.instance,
        _onToken = onToken,
        _now = now;

  final FirebaseMessagingClient _client;
  final PostDeeNotificationCenter _center;
  final void Function(String token)? _onToken;
  final DateTime Function() _now;

  bool _initialized = false;
  StreamSubscription<PushNotificationMessage>? _foregroundSubscription;
  StreamSubscription<PushNotificationMessage>? _openedSubscription;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final granted = await _client.requestPermission();

    if (!granted) {
      return;
    }

    // The device token is what a backend would target to send a push. We expose
    // it via [onToken] so a future "register device" call can ship it; there is
    // no such endpoint yet.
    final token = (await _client.getToken())?.trim();
    if (token != null && token.isNotEmpty) {
      _onToken?.call(token);
    }

    _foregroundSubscription = _client.onForegroundMessage.listen(_handleMessage);
    _openedSubscription = _client.onMessageOpenedApp.listen(_handleMessage);
  }

  void _handleMessage(PushNotificationMessage message) {
    final title = message.title.trim();
    final body = message.body.trim();

    if (title.isEmpty && body.isEmpty) {
      return;
    }

    _center.add(
      PostDeeNotification(
        title: title.isEmpty ? 'การแจ้งเตือน' : title,
        body: body,
        receivedAt: _now(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
  }
}

/// Real client wired to `FirebaseMessaging.instance`.
class FirebaseMessagingPackageClient implements FirebaseMessagingClient {
  FirebaseMessagingPackageClient({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final status = settings.authorizationStatus;

    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<PushNotificationMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_mapMessage);

  @override
  Stream<PushNotificationMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_mapMessage);

  PushNotificationMessage _mapMessage(RemoteMessage message) =>
      PushNotificationMessage(
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
      );
}

/// Builds the push messaging gateway for the current configuration. Returns the
/// real FCM gateway only when Firebase Auth is enabled and initialized;
/// otherwise a no-op gateway so local dev and tests are unaffected.
PushMessagingGateway createPushMessagingGatewayFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
  PostDeeNotificationCenter? center,
  void Function(String token)? onToken,
}) {
  if (!enableFirebaseAuth) {
    return const DisabledPushMessagingGateway();
  }

  final bootstrap =
      firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!bootstrap.isInitialized) {
    return const DisabledPushMessagingGateway();
  }

  return FirebasePushMessagingGateway(
    client: FirebaseMessagingPackageClient(),
    center: center,
    onToken: onToken,
  );
}
