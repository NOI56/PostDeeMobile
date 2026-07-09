typedef AnalyticsEventLogger = Future<void> Function(
  RecordedAnalyticsEvent event,
);

class RecordedAnalyticsEvent {
  const RecordedAnalyticsEvent({
    required this.name,
    this.parameters = const {},
  });

  final String name;
  final Map<String, Object> parameters;
}

class PostDeeAnalytics {
  PostDeeAnalytics({
    bool isEnabled = false,
    AnalyticsEventLogger? logEvent,
  })  : _isEnabled = isEnabled,
        _logEvent = logEvent;

  static final instance = PostDeeAnalytics();

  bool _isEnabled;
  AnalyticsEventLogger? _logEvent;

  bool get isEnabled => _isEnabled;

  void configure({
    required bool isEnabled,
    AnalyticsEventLogger? logEvent,
  }) {
    _isEnabled = isEnabled;
    _logEvent = logEvent;
  }

  Future<void> logSignInStarted(String provider) => _log(
        'auth_sign_in_started',
        {'provider': provider},
      );

  Future<void> logSignInSucceeded(String provider) => _log(
        'auth_sign_in_succeeded',
        {'provider': provider},
      );

  Future<void> logSignInFailed({
    required String provider,
    required String reason,
  }) =>
      _log(
        'auth_sign_in_failed',
        {
          'provider': provider,
          'reason': _categoricalReason(reason),
        },
      );

  Future<void> logSignOut() => _log('auth_sign_out');

  Future<void> logVideoSelected({
    required bool hasDimensions,
  }) =>
      _log(
        'video_selected',
        {'has_dimensions': hasDimensions},
      );

  Future<void> logPublishStarted({
    required int platformCount,
    required bool isScheduled,
    required bool watermarkEnabled,
  }) =>
      _log(
        'post_publish_started',
        {
          'platform_count': platformCount,
          'is_scheduled': isScheduled,
          'watermark_enabled': watermarkEnabled,
        },
      );

  Future<void> logPublishSucceeded({
    required int platformCount,
    required bool isScheduled,
  }) =>
      _log(
        'post_publish_succeeded',
        {
          'platform_count': platformCount,
          'is_scheduled': isScheduled,
        },
      );

  Future<void> logPublishFailed({required String reason}) => _log(
        'post_publish_failed',
        {'reason': _categoricalReason(reason)},
      );

  Future<void> _log(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    final logEvent = _logEvent;

    if (!_isEnabled || logEvent == null) {
      return;
    }

    try {
      await logEvent(
        RecordedAnalyticsEvent(
          name: name,
          parameters: Map.unmodifiable(parameters),
        ),
      );
    } catch (_) {
      // Analytics must never break the product flow.
    }
  }

  String _categoricalReason(String reason) {
    final normalized = reason.trim().toLowerCase();
    const allowedReasons = {
      'api',
      'auth',
      'network',
      'unavailable',
      'unknown',
      'watermark',
    };

    return allowedReasons.contains(normalized) ? normalized : 'unknown';
  }
}
