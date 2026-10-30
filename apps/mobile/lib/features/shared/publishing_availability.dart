import '../../core/network/postdee_api_client.dart';

const publishingUnavailableTitle = 'ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้';
const publishingUnavailableBeforeUploadMessage =
    'วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง';
const publishingUnavailableAfterUploadMessage =
    'ยังไม่ได้สร้างโพสต์ และไฟล์วิดีโออาจถูกอัปโหลดไว้ชั่วคราว กรุณาลองใหม่ภายหลัง';
const publishingUnavailableActionMessage =
    'ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง';

String getPublishingUnavailableActionMessage({String languageCode = 'th'}) =>
    languageCode == 'th'
        ? publishingUnavailableActionMessage
        : 'Publishing is temporarily unavailable. Please try again later.';

bool isPublishingUnavailable(ApiException error) =>
    error.code == socialPublishingUnavailableCode;
