import 'package:shared_preferences/shared_preferences.dart';

class GrowthToolSettings {
  const GrowthToolSettings({
    required this.isEnabled,
    required this.enabledOptionIds,
  });

  final bool isEnabled;
  final Set<String> enabledOptionIds;

  bool isOptionEnabled(String optionId) {
    return enabledOptionIds.contains(optionId);
  }

  GrowthToolSettings copyWith({
    bool? isEnabled,
    Set<String>? enabledOptionIds,
  }) {
    return GrowthToolSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      enabledOptionIds: enabledOptionIds ?? this.enabledOptionIds,
    );
  }
}

abstract class PostDeeGrowthToolSettingsStore {
  Future<GrowthToolSettings?> loadSettings(String toolId);

  Future<void> saveSettings(String toolId, GrowthToolSettings settings);
}

class SharedPreferencesGrowthToolSettingsStore
    implements PostDeeGrowthToolSettingsStore {
  const SharedPreferencesGrowthToolSettingsStore({
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  static String enabledKey(String toolId) =>
      'postdee_growth_tool.$toolId.enabled';

  static String enabledOptionsKey(String toolId) =>
      'postdee_growth_tool.$toolId.enabled_options';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _activePreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<GrowthToolSettings?> loadSettings(String toolId) async {
    final preferences = await _activePreferences;
    final hasSavedSettings = preferences.containsKey(enabledKey(toolId)) ||
        preferences.containsKey(enabledOptionsKey(toolId));

    if (!hasSavedSettings) {
      return null;
    }

    return GrowthToolSettings(
      isEnabled: preferences.getBool(enabledKey(toolId)) ?? false,
      enabledOptionIds:
          (preferences.getStringList(enabledOptionsKey(toolId)) ?? const [])
              .toSet(),
    );
  }

  @override
  Future<void> saveSettings(
    String toolId,
    GrowthToolSettings settings,
  ) async {
    final preferences = await _activePreferences;
    final optionIds = settings.enabledOptionIds.toList()..sort();

    await preferences.setBool(enabledKey(toolId), settings.isEnabled);
    await preferences.setStringList(enabledOptionsKey(toolId), optionIds);
  }
}
