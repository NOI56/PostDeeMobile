import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_media_strategy.dart';

void main() {
  test('current production capabilities select audio only', () {
    expect(
      selectAiEditAnalysisMode({
        'subtitle': true,
        'silence': true,
        'filler': true,
        'color': true,
        'zoom': false,
      }, usesOriginalDuration: true, hasManualSoundEffects: false),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('routes color-only original duration to local render', () {
    expect(
      selectAiEditAnalysisMode(
        {'color': true},
        usesOriginalDuration: true,
        hasManualSoundEffects: false,
      ),
      AiEditAnalysisMode.localRenderOnly,
    );
  });

  test('keeps color plus shortening on the audio planning route', () {
    expect(
      selectAiEditAnalysisMode(
        {'color': true},
        usesOriginalDuration: false,
        hasManualSoundEffects: false,
      ),
      AiEditAnalysisMode.audioOnly,
    );
  });

  for (final additionalCapability in ['subtitle', 'silence', 'filler']) {
    test('keeps color plus $additionalCapability on the audio route', () {
      expect(
        selectAiEditAnalysisMode(
          {'color': true, additionalCapability: true},
          usesOriginalDuration: true,
          hasManualSoundEffects: false,
        ),
        AiEditAnalysisMode.audioOnly,
      );
    });
  }

  test('an enabled visual or unknown capability fails closed', () {
    expect(
      () => selectAiEditAnalysisMode(
        {'subtitle': true, 'zoom': true},
        usesOriginalDuration: true,
        hasManualSoundEffects: false,
      ),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
    expect(
      () => selectAiEditAnalysisMode(
        {'future_visual_ai': true},
        usesOriginalDuration: true,
        hasManualSoundEffects: false,
      ),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
  });

  test('ignores disabled unknown capabilities', () {
    expect(
      selectAiEditAnalysisMode(
        {'future_visual_ai': false},
        usesOriginalDuration: true,
        hasManualSoundEffects: false,
      ),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('routes manual sound effects at original duration to local render', () {
    expect(
      selectAiEditAnalysisMode(
        const {},
        usesOriginalDuration: true,
        hasManualSoundEffects: true,
      ),
      AiEditAnalysisMode.localRenderOnly,
    );
  });

  test('fails closed when manual sound effects need a changed timeline', () {
    for (final scenario in [
      () => selectAiEditAnalysisMode(
            const {},
            usesOriginalDuration: false,
            hasManualSoundEffects: true,
          ),
      () => selectAiEditAnalysisMode(
            const {'subtitle': true},
            usesOriginalDuration: true,
            hasManualSoundEffects: true,
          ),
      () => selectAiEditAnalysisMode(
            const {'sfx': true},
            usesOriginalDuration: true,
            hasManualSoundEffects: false,
          ),
    ]) {
      expect(
        scenario,
        throwsA(isA<UnsupportedAiEditAnalysisException>()),
      );
    }
  });
}
