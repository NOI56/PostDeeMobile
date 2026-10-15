import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';

// Unrelated uploader widget tests use small fixture bytes rather than native
// video. Native stream validation is covered by the preparer tests and smoke.
Future<TikTokPreparedVideoResult> testPrepareTikTokVideo(
  TikTokVideoPreparationRequest request,
) async =>
    TikTokPreparedVideoResult(
      file: request.inputFile,
      fileName: request.fileName,
      sizeBytes: request.inputFile.lengthSync(),
      width: 1080,
      height: 1920,
    );
