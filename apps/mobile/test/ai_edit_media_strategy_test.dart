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
      }, usesOriginalDuration: true),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('routes color-only original duration to local render', () {
    expect(
      selectAiEditAnalysisMode(
        {'color': true},
        usesOriginalDuration: true,
      ),
      AiEditAnalysisMode.localRenderOnly,
    );
  });

  test('keeps color plus shortening on the audio planning route', () {
    expect(
      selectAiEditAnalysisMode(
        {'color': true},
        usesOriginalDuration: false,
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
      ),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
    expect(
      () => selectAiEditAnalysisMode(
        {'future_visual_ai': true},
        usesOriginalDuration: true,
      ),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
  });

  test('ignores disabled unknown capabilities', () {
    expect(
      selectAiEditAnalysisMode(
        {'future_visual_ai': false},
        usesOriginalDuration: true,
      ),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('routes AI sound effects through audio analysis', () {
    expect(
      selectAiEditAnalysisMode(
        const {'sfx': true},
        usesOriginalDuration: true,
      ),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('keeps AI sound effects with timeline cuts on audio analysis', () {
    expect(
      selectAiEditAnalysisMode(
        const {'sfx': true, 'silence': true},
        usesOriginalDuration: false,
      ),
      AiEditAnalysisMode.audioOnly,
    );
  });
}
