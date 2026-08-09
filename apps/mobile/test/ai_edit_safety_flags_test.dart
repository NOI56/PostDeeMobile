import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_safety_flags.dart';

void main() {
  test('safety flags default both guarded AI behaviours to enabled', () {
    const flags = AiEditSafetyFlags();

    expect(flags.verifiedSilenceEnabled, isTrue);
    expect(flags.automaticRepeatCutsEnabled, isTrue);
  });

  test('explicit constructor overrides each safety flag independently', () {
    const silenceDisabled = AiEditSafetyFlags(
      verifiedSilenceEnabled: false,
    );
    const repeatCutsDisabled = AiEditSafetyFlags(
      automaticRepeatCutsEnabled: false,
    );
    const bothDisabled = AiEditSafetyFlags(
      verifiedSilenceEnabled: false,
      automaticRepeatCutsEnabled: false,
    );

    expect(silenceDisabled.verifiedSilenceEnabled, isFalse);
    expect(silenceDisabled.automaticRepeatCutsEnabled, isTrue);
    expect(repeatCutsDisabled.verifiedSilenceEnabled, isTrue);
    expect(repeatCutsDisabled.automaticRepeatCutsEnabled, isFalse);
    expect(bothDisabled.verifiedSilenceEnabled, isFalse);
    expect(bothDisabled.automaticRepeatCutsEnabled, isFalse);
  });

  test('environment constructor reads the documented compile-time keys', () {
    const flags = AiEditSafetyFlags.fromEnvironment();

    expect(
      flags.verifiedSilenceEnabled,
      const bool.fromEnvironment(
        'AI_EDIT_VERIFIED_SILENCE_ENABLED',
        defaultValue: true,
      ),
    );
    expect(
      flags.automaticRepeatCutsEnabled,
      const bool.fromEnvironment(
        'AI_EDIT_AUTO_REPEAT_CUTS_ENABLED',
        defaultValue: true,
      ),
    );
  });
}
