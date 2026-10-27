enum AiEditAnalysisMode { audioOnly }

class UnsupportedAiEditAnalysisException implements Exception {
  const UnsupportedAiEditAnalysisException(this.capability);

  final String capability;

  @override
  String toString() => 'ยังไม่รองรับการวิเคราะห์ภาพสำหรับ $capability';
}

const _audioOnlyCapabilities = {
  'subtitle',
  'silence',
  'filler',
  'color',
};

AiEditAnalysisMode selectAiEditAnalysisMode(Map<String, bool> capabilities) {
  for (final entry in capabilities.entries) {
    if (entry.value && !_audioOnlyCapabilities.contains(entry.key)) {
      throw UnsupportedAiEditAnalysisException(entry.key);
    }
  }

  return AiEditAnalysisMode.audioOnly;
}
