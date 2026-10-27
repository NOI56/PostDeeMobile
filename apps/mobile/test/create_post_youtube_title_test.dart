import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('keeps an explicit YouTube title separate from the full caption', () {
    const request = CreatePostRequest(
      caption: 'รายละเอียดเต็ม\n#แท็ก',
      videoS3Key: 'uploads/seller/video.mp4',
      platforms: ['YOUTUBE_SHORTS'],
      youtubeTitle: 'ชื่อสั้นสำหรับ YouTube',
    );
    expect(request.toJson()['youtubeTitle'], 'ชื่อสั้นสำหรับ YouTube');
    expect(request.toJson()['caption'], 'รายละเอียดเต็ม\n#แท็ก');
  });

  test('omits an automatic title so the API derives it from the caption', () {
    expect(
      const CreatePostRequest(
        caption: 'ชื่อจากแคปชัน',
        videoS3Key: 'uploads/seller/video.mp4',
        platforms: ['YOUTUBE_SHORTS'],
      ).toJson().containsKey('youtubeTitle'),
      isFalse,
    );
  });
}
