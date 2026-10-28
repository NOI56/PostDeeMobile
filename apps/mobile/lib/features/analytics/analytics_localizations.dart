import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../shared/growth_tool_detail_sheet.dart';

bool analyticsUsesThai(BuildContext context) =>
    (Localizations.of<PostDeeLocalizations>(context, PostDeeLocalizations)
            ?.locale
            .languageCode ??
        'th') ==
    'th';

/// Only app-owned copy belongs here. API platform labels and metric values
/// are displayed directly, even when they match a translation key.
String localizeAnalyticsMessage(BuildContext context, String message) {
  if (analyticsUsesThai(context)) return message;
  return _englishMessages[message] ??
      localizeGrowthToolMessage(context, message);
}

String analyticsLikesLabel(BuildContext context, int likes) =>
    analyticsUsesThai(context)
        ? '$likes ไลก์'
        : '$likes ${likes == 1 ? 'like' : 'likes'}';

const _englishMessages = <String, String>{
  'วิเคราะห์': 'Analytics',
  'วันนี้': 'Today',
  '7 วัน': '7 days',
  '30 วัน': '30 days',
  '90 วัน': '90 days',
  'ปีนี้': 'This year',
  'ยอดวิวรวม': 'Total views',
  'เอนเกจเมนต์': 'Engagement',
  'ยอดวิวรายวัน': 'Daily views',
  'ช่องทางที่ทำผลงานดีสุด': 'Best-performing platforms',
  'เครื่องมือวิเคราะห์ด้วย AI': 'AI analytics tools',
  'ลองใหม่': 'Retry',
  'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดหน้าวิเคราะห์ใหม่':
      'Your account has changed. Please reopen Analytics.',
  'ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro':
      'Unified analytics is available on the Pro plan.',
  'ยังไม่มีข้อมูลวิเคราะห์ กลับมาดูหลังคลิปเริ่มมียอด':
      'No analytics data yet. Check back after your videos start getting views.',
  'เฉพาะแพ็กเกจ Pro': 'Pro plan only',
  'กรุณาเข้าสู่ระบบใหม่': 'Please sign in again.',
  'บัญชีนี้ยังไม่มีสิทธิ์ดูข้อมูลวิเคราะห์':
      'This account cannot access analytics.',
  'โหลดข้อมูลวิเคราะห์ไม่สำเร็จ ลองใหม่อีกครั้ง':
      'Could not load analytics. Please try again.',
  'เชื่อมต่อ PostDee API ไม่ได้': 'Could not connect to PostDee.',
  'เกิดข้อผิดพลาดระหว่างโหลดข้อมูลวิเคราะห์':
      'An error occurred while loading analytics.',
};
