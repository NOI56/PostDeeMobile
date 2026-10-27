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
      }),
      AiEditAnalysisMode.audioOnly,
    );
  });

  test('an enabled visual capability fails closed', () {
    expect(
      () => selectAiEditAnalysisMode({'subtitle': true, 'zoom': true}),
      throwsA(
        isA<UnsupportedAiEditAnalysisException>().having(
          (error) => error.capability,
          'capability',
          'zoom',
        ),
      ),
    );
  });

  test('an enabled unknown capability fails closed', () {
    expect(
      () => selectAiEditAnalysisMode({'future_visual_ai': true}),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
  });

  test('disabled unknown capabilities do not change the safe mode', () {
    expect(
      selectAiEditAnalysisMode({'future_visual_ai': false}),
      AiEditAnalysisMode.audioOnly,
    );
  });
}
