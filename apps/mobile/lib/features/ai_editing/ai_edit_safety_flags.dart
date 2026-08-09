class AiEditSafetyFlags {
  const AiEditSafetyFlags({
    this.verifiedSilenceEnabled = true,
    this.automaticRepeatCutsEnabled = true,
  });

  const AiEditSafetyFlags.fromEnvironment()
      : verifiedSilenceEnabled = const bool.fromEnvironment(
          'AI_EDIT_VERIFIED_SILENCE_ENABLED',
          defaultValue: true,
        ),
        automaticRepeatCutsEnabled = const bool.fromEnvironment(
          'AI_EDIT_AUTO_REPEAT_CUTS_ENABLED',
          defaultValue: true,
        );

  final bool verifiedSilenceEnabled;
  final bool automaticRepeatCutsEnabled;
}
