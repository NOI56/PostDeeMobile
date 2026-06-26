import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';

void main() {
  group('PostDeeLocalizations', () {
    test('returns Thai labels for Thai locale', () {
      final localizations = PostDeeLocalizations.lookup(const Locale('th'));

      expect(localizations.homeTab, 'หน้าแรก');
      expect(localizations.uploadTab, 'อัปโหลด');
      expect(localizations.captionTab, 'ปฏิทิน');
      expect(localizations.analyticsTab, 'วิเคราะห์');
      expect(localizations.profileTab, 'โปรไฟล์');
      expect(localizations.notificationsAction, 'แจ้งเตือน');
      expect(localizations.userAccountAction, 'บัญชีผู้ใช้');
      expect(localizations.templatesTitle, 'เทมเพลต');
      expect(localizations.loginTitle, 'เข้าสู่ระบบ PostDee');
      expect(localizations.loginSubtitle, 'เชื่อมอีเมลก่อนเข้าใช้งาน');
      expect(
        localizations.loginRequirementMessage,
        'ต้องมีอีเมลที่เชื่อมไว้ก่อน จึงจะโพสต์และจัดการคอนเทนต์ได้',
      );
      expect(localizations.loginButton, 'เข้าสู่ระบบด้วย Google');
      expect(localizations.signingInButton, 'กำลังเข้าสู่ระบบ...');
      expect(
        localizations.loginDefaultHelper,
        'เชื่อมอีเมล Google เพื่อเริ่มใช้งาน PostDee',
      );
      expect(
        localizations.loginMockHelper,
        'โหมดทดสอบจะใช้อีเมลจำลองสำหรับเข้าแอป',
      );
      expect(localizations.homeGreeting, 'สวัสดี');
      expect(localizations.homeOverviewSubtitle, 'ภาพรวมการโพสต์ของคุณวันนี้');
      expect(localizations.homeViewPackage, 'ดูแพ็กเกจ');
      expect(localizations.homeTotalPosts, 'ยอดวิวรวม');
      expect(localizations.homeLatestPostStatus, 'สถานะโพสต์ล่าสุด');
      expect(localizations.homeViewAll, 'ดูทั้งหมด');
      expect(localizations.homeShortcuts, 'ทางลัด');
      expect(localizations.homeCalendarShortcut, 'ปฏิทิน');
      expect(localizations.homeViewsMetric, 'ยอดวิว');
      expect(localizations.homeLikesMetric, 'ไลก์');
      expect(localizations.homeRefreshViews, 'รีเฟรชยอดวิว');
      expect(localizations.homeLoading, 'กำลังโหลด...');
      expect(
          localizations.homeApiConnectionError, 'เชื่อมต่อ PostDee API ไม่ได้');
      expect(
        localizations.homeAnalyticsLoadError,
        'โหลดข้อมูลวิเคราะห์ไม่ได้',
      );
    });

    test('returns English labels for English locale', () {
      final localizations = PostDeeLocalizations.lookup(const Locale('en'));

      expect(localizations.homeTab, 'Home');
      expect(localizations.uploadTab, 'Upload');
      expect(localizations.captionTab, 'Calendar');
      expect(localizations.analyticsTab, 'Analytics');
      expect(localizations.profileTab, 'Profile');
      expect(localizations.notificationsAction, 'Notifications');
      expect(localizations.userAccountAction, 'User account');
      expect(localizations.templatesTitle, 'Templates');
      expect(localizations.loginTitle, 'Sign in to PostDee');
      expect(
        localizations.loginSubtitle,
        'Connect your email before using the app',
      );
      expect(
        localizations.loginRequirementMessage,
        'Connect an email first so you can post and manage content.',
      );
      expect(localizations.loginButton, 'Sign in with Google');
      expect(localizations.signingInButton, 'Signing in...');
      expect(
        localizations.loginDefaultHelper,
        'Connect your Google email to start using PostDee',
      );
      expect(
        localizations.loginMockHelper,
        'Local mock auth uses a sample email to enter the app',
      );
      expect(localizations.homeGreeting, 'Hello');
      expect(localizations.homeOverviewSubtitle, "Today's posting overview");
      expect(localizations.homeViewPackage, 'View package');
      expect(localizations.homeTotalPosts, 'Total views');
      expect(localizations.homeLatestPostStatus, 'Latest post status');
      expect(localizations.homeViewAll, 'View all');
      expect(localizations.homeShortcuts, 'Shortcuts');
      expect(localizations.homeCalendarShortcut, 'Calendar');
      expect(localizations.homeViewsMetric, 'Views');
      expect(localizations.homeLikesMetric, 'Likes');
      expect(localizations.homeRefreshViews, 'Refresh views');
      expect(localizations.homeLoading, 'Loading...');
      expect(
        localizations.homeApiConnectionError,
        'Cannot connect to PostDee API',
      );
      expect(
        localizations.homeAnalyticsLoadError,
        'Could not load analytics data',
      );
    });

    test('falls back to English for unsupported locale', () {
      final localizations = PostDeeLocalizations.lookup(const Locale('fr'));

      expect(localizations.homeTab, 'Home');
    });
  });
}
