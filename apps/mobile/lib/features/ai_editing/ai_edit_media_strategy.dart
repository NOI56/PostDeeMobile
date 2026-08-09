enum AiEditAnalysisMode { audioOnly, localRenderOnly }

class UnsupportedAiEditAnalysisException implements Exception {
  const UnsupportedAiEditAnalysisException(this.capability);

  final String capability;

  @override
  String toString() => 'ยังไม่รองรับการวิเคราะห์ภาพสำหรับ $capability';
}

const _supportedCapabilities = {
  'subtitle',
  'silence',
  'filler',
  'color',
};

AiEditAnalysisMode selectAiEditAnalysisMode(
  Map<String, bool> capabilities, {
  required bool usesOriginalDuration,
  required bool hasManualSoundEffects,
}) {
  final enabledCapabilities = capabilities.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();
  final unsupported = enabledCapabilities.difference(_supportedCapabilities);
  if (unsupported.isNotEmpty) {
    throw UnsupportedAiEditAnalysisException(unsupported.first);
  }

  if (hasManualSoundEffects) {
    if (!usesOriginalDuration || enabledCapabilities.isNotEmpty) {
      throw const UnsupportedAiEditAnalysisException(
        'เอฟเฟกต์เสียงร่วมกับการตัดต่อ AI',
      );
    }
    return AiEditAnalysisMode.localRenderOnly;
  }

  if (usesOriginalDuration &&
      enabledCapabilities.length == 1 &&
      enabledCapabilities.single == 'color') {
    return AiEditAnalysisMode.localRenderOnly;
  }

  return AiEditAnalysisMode.audioOnly;
}
