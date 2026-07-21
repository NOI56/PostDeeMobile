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

  test('an enabled visual or unknown capability fails closed', () {
    expect(
      () => selectAiEditAnalysisMode({'subtitle': true, 'zoom': true}),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
    expect(
      () => selectAiEditAnalysisMode({'future_visual_ai': true}),
      throwsA(isA<UnsupportedAiEditAnalysisException>()),
    );
  });
}
