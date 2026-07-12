import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

typedef BeatMusicPicker = Future<PickedBeatMusicFile?> Function();

class PickedBeatMusicFile {
  const PickedBeatMusicFile({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? path;
  final Uint8List? bytes;
}

class PostDeeMusicTrack {
  const PostDeeMusicTrack({
    required this.id,
    required this.title,
    required this.moodLabel,
    required this.bpm,
    required this.durationSeconds,
    required this.licenseLabel,
    required this.rightsVerified,
    this.supportedPlatforms = const [],
  });

  final String id;
  final String title;
  final String moodLabel;
  final int bpm;
  final int durationSeconds;
  final String licenseLabel;
  final bool rightsVerified;
  final List<String> supportedPlatforms;
}

class BeatMusicPickerException implements Exception {
  const BeatMusicPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BeatMusicFileValidator {
  const BeatMusicFileValidator._();

  static const maxSizeBytes = 50 * 1024 * 1024;
  static const supportedExtensions = {'mp3', 'm4a', 'wav'};

  static void validate({
    required String name,
    required int sizeBytes,
    required bool hasReadableSource,
  }) {
    final trimmedName = name.trim();
    final extension = trimmedName.contains('.')
        ? trimmedName.split('.').last.toLowerCase()
        : null;
    if (trimmedName.isEmpty ||
        extension == null ||
        !supportedExtensions.contains(extension)) {
      throw const BeatMusicPickerException(
        'รองรับไฟล์เพลง MP3, M4A และ WAV เท่านั้น',
      );
    }
    if (sizeBytes <= 0) {
      throw const BeatMusicPickerException('ไฟล์เพลงที่เลือกไม่มีข้อมูล');
    }
    if (sizeBytes > maxSizeBytes) {
      throw const BeatMusicPickerException(
        'ไฟล์เพลงต้องมีขนาดไม่เกิน 50 MB',
      );
    }
    if (!hasReadableSource) {
      throw const BeatMusicPickerException('ไม่สามารถอ่านไฟล์เพลงที่เลือกได้');
    }
  }
}

class DeviceBeatMusicPicker {
  const DeviceBeatMusicPicker();

  static const maxSizeBytes = BeatMusicFileValidator.maxSizeBytes;
  static const supportedExtensions = BeatMusicFileValidator.supportedExtensions;

  Future<PickedBeatMusicFile?> call() async {
    const audioTypes = XTypeGroup(
      label: 'audio',
      extensions: ['mp3', 'm4a', 'wav'],
      mimeTypes: [
        'audio/mpeg',
        'audio/mp4',
        'audio/x-m4a',
        'audio/wav',
        'audio/x-wav',
      ],
      uniformTypeIdentifiers: [
        'public.mp3',
        'public.mpeg-4-audio',
        'com.microsoft.waveform-audio',
      ],
      webWildCards: ['audio/*'],
    );
    final file = await openFile(
      acceptedTypeGroups: const [audioTypes],
    );
    if (file == null) {
      return null;
    }

    final name = file.name.trim();
    final sizeBytes = await file.length();
    final path = kIsWeb ? null : file.path.trim();
    final bytes = kIsWeb || path == null || path.isEmpty
        ? await file.readAsBytes()
        : null;
    BeatMusicFileValidator.validate(
      name: name,
      sizeBytes: sizeBytes,
      hasReadableSource:
          (path?.isNotEmpty ?? false) || (bytes?.isNotEmpty ?? false),
    );

    return PickedBeatMusicFile(
      name: name,
      path: path,
      sizeBytes: sizeBytes,
      bytes: bytes,
    );
  }
}
