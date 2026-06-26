/// Starts and stops delivery of push notifications into the app.
///
/// The real implementation ([FirebasePushMessagingGateway]) is backed by FCM.
/// When Firebase is off (local dev, tests) the factory returns
/// [DisabledPushMessagingGateway], which does nothing, so the rest of the app
/// is unaffected.
abstract class PushMessagingGateway {
  /// Requests notification permission, retrieves the device token, and starts
  /// forwarding incoming messages to the notification center. Safe to call once;
  /// repeated calls are ignored by the real implementation.
  Future<void> initialize();

  /// Cancels any active message subscriptions.
  Future<void> dispose();
}

/// No-op gateway used when push messaging is not configured.
class DisabledPushMessagingGateway implements PushMessagingGateway {
  const DisabledPushMessagingGateway();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}
