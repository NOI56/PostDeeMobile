import '../../core/network/postdee_api_client.dart';

bool isAnalyticsPlanRequired(ApiException error) {
  if (error.statusCode != 402 && error.statusCode != 403) {
    return false;
  }

  final code = error.code;
  if (code != null) {
    return code == 'PRO_REQUIRED';
  }

  final message = error.message.toLowerCase();

  return message.contains('pro plan') ||
      message.contains('analytics requires') ||
      message.contains('unified analytics');
}

String analyticsErrorMessage(ApiException error) {
  if (isAnalyticsPlanRequired(error)) {
    return 'เฉพาะแพ็กเกจ Pro';
  }

  return switch (error.statusCode) {
    401 => 'กรุณาเข้าสู่ระบบใหม่',
    403 => 'บัญชีนี้ยังไม่มีสิทธิ์ดูข้อมูลวิเคราะห์',
    _ => 'โหลดข้อมูลวิเคราะห์ไม่สำเร็จ ลองใหม่อีกครั้ง',
  };
}
