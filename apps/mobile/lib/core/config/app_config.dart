class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000',
  );

  static const storeProMonthlyProductId = String.fromEnvironment(
    'STORE_PRO_MONTHLY_PRODUCT_ID',
    defaultValue: 'postdee_pro_monthly',
  );

  static const storeStarterMonthlyProductId = String.fromEnvironment(
    'STORE_STARTER_MONTHLY_PRODUCT_ID',
    defaultValue: 'postdee_starter_monthly',
  );

  static const mockUserId = String.fromEnvironment(
    'POSTDEE_MOCK_USER_ID',
    defaultValue: '',
  );

  static const mockSubscriptionPlan = String.fromEnvironment(
    'POSTDEE_MOCK_SUBSCRIPTION_PLAN',
    defaultValue: '',
  );

  static const enableFirebaseAuth = bool.fromEnvironment(
    'ENABLE_FIREBASE_AUTH',
    defaultValue: false,
  );

  static const allowLocalMockAuth = bool.fromEnvironment(
    'ALLOW_LOCAL_MOCK_AUTH',
    defaultValue: false,
  );

  static const googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const enableRevenueCatBilling = bool.fromEnvironment(
    'ENABLE_REVENUECAT_BILLING',
    defaultValue: false,
  );

  /// Enables the internal-only beat-sync setup UI.
  ///
  /// This flag does not enable beat analysis or music rendering. Keep it off in
  /// production until the renderer and music-rights flow are complete.
  static const enableExperimentalBeatSync = bool.fromEnvironment(
    'ENABLE_EXPERIMENTAL_BEAT_SYNC',
    defaultValue: false,
  );

  /// Enables the internal-only AI hook setup UI.
  ///
  /// Keep this off in production until highlight selection and timeline
  /// rendering are implemented end to end.
  static const enableExperimentalAiHook = bool.fromEnvironment(
    'ENABLE_EXPERIMENTAL_AI_HOOK',
    defaultValue: false,
  );

  static const revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: '',
  );

  static const revenueCatAndroidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
    defaultValue: '',
  );

  static const revenueCatIosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: '',
  );
}
