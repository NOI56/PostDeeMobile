import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/beat_music_picker.dart';

void main() {
  test('accepts a supported non-empty music file source', () {
    expect(
      () => BeatMusicFileValidator.validate(
        name: 'seller-owned.MP3',
        sizeBytes: 1024,
        hasReadableSource: true,
      ),
      returnsNormally,
    );
  });

  test('rejects empty, oversized, unsupported, and unreadable music files', () {
    for (final input in [
      (name: 'empty.mp3', size: 0, readable: true),
      (
        name: 'too-large.wav',
        size: BeatMusicFileValidator.maxSizeBytes + 1,
        readable: true,
      ),
      (name: 'renamed.exe', size: 1024, readable: true),
      (name: 'missing.m4a', size: 1024, readable: false),
    ]) {
      expect(
        () => BeatMusicFileValidator.validate(
          name: input.name,
          sizeBytes: input.size,
          hasReadableSource: input.readable,
        ),
        throwsA(isA<BeatMusicPickerException>()),
      );
    }
  });
}
