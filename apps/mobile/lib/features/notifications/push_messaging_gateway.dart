/// Starts and stops delivery of push notifications into the app.
///
/// The real implementation ([FirebasePushMessagingGateway]) is backed by FCM.
/// When Firebase is off (local dev, tests) the factory returns
/// [DisabledPushMessagingGateway], which does nothing, so the rest of the app
/// is unaffected.
abstract class PushMessagingGateway {
  /// Requests notification permission, retrieves the device token, and starts
  /// forwarding incoming messages for the current sign-in. Concurrent calls
  /// share initialization; denied or failed initialization may be retried.
  /// The real gateway clears history and rebinds delivery on account changes.
  Future<void> initialize();

  /// Cancels any active message subscriptions.
  Future<void> dispose();
}

/// Listens for already-authorized delivery and cold-start taps without showing
/// a permission prompt. Permission is requested only by [initialize].
abstract interface class PushMessagingLifecycle {
  Future<void> start();
}

/// No-op gateway used when push messaging is not configured.
class DisabledPushMessagingGateway implements PushMessagingGateway {
  const DisabledPushMessagingGateway();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}
