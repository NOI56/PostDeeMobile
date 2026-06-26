import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PostDeeLocalizations {
  const PostDeeLocalizations._(this.locale, this._values);

  final Locale locale;
  final _PostDeeLocalizedValues _values;

  static const supportedLocales = [
    Locale('th'),
    Locale('en'),
    Locale('vi'),
    Locale('zh'),
    Locale('id'),
    Locale('ms'),
    Locale('tl'),
    Locale('ja'),
  ];

  static const delegate = _PostDeeLocalizationsDelegate();

  static PostDeeLocalizations of(BuildContext context) {
    final localizations = Localizations.of<PostDeeLocalizations>(
      context,
      PostDeeLocalizations,
    );

    assert(
      localizations != null,
      'PostDeeLocalizations was not found in the widget tree.',
    );

    return localizations!;
  }

  static PostDeeLocalizations lookup(Locale locale) {
    return switch (locale.languageCode) {
      'th' => const PostDeeLocalizations._(
          Locale('th'),
          _PostDeeLocalizedValues(
            homeTab: 'หน้าแรก',
            uploadTab: 'อัปโหลด',
            editTab: 'ตัดต่อ',
            uploadSaveDraftAction: 'บันทึกฉบับร่าง',
            uploadDraftSavedMessage: 'บันทึกฉบับร่างไว้ในเครื่องแล้ว',
            captionTab: 'ปฏิทิน',
            analyticsTab: 'วิเคราะห์',
            profileTab: 'โปรไฟล์',
            notificationsAction: 'แจ้งเตือน',
            userAccountAction: 'บัญชีผู้ใช้',
            templatesTitle: 'เทมเพลต',
            loginTitle: 'เข้าสู่ระบบ PostDee',
            loginSubtitle: 'เชื่อมอีเมลก่อนเข้าใช้งาน',
            loginRequirementMessage: 'ต้องมีอีเมลที่เชื่อมไว้ก่อน จึงจะโพสต์และจัดการคอนเทนต์ได้',
            loginButton: 'เข้าสู่ระบบด้วย Google',
            appleLoginButton: 'เข้าสู่ระบบด้วย Apple',
            signingInButton: 'กำลังเข้าสู่ระบบ...',
            loginDefaultHelper: 'เชื่อมอีเมล Google เพื่อเริ่มใช้งาน PostDee',
            loginMockHelper: 'โหมดทดสอบจะใช้อีเมลจำลองสำหรับเข้าแอป',
            homeGreeting: 'สวัสดี',
            homeOverviewSubtitle: 'ภาพรวมการโพสต์ของคุณวันนี้',
            homeViewPackage: 'ดูแพ็กเกจ',
            homeTotalPosts: 'ยอดวิวรวม',
            homeLatestPostStatus: 'สถานะโพสต์ล่าสุด',
            homeViewAll: 'ดูทั้งหมด',
            homeShortcuts: 'ทางลัด',
            homeCalendarShortcut: 'ปฏิทิน',
            homeViewsMetric: 'ยอดวิว',
            homeLikesMetric: 'ไลก์',
            homeRefreshViews: 'รีเฟรชยอดวิว',
            homeLoading: 'กำลังโหลด...',
            homeApiConnectionError: 'เชื่อมต่อ PostDee API ไม่ได้',
            homeAnalyticsLoadError: 'โหลดข้อมูลวิเคราะห์ไม่ได้',
            profileLanguageTitle: 'ภาษา',
            profileLanguageDescription: 'เลือกภาษาที่ใช้ในแอป',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'en' => const PostDeeLocalizations._(
          Locale('en'),
          _PostDeeLocalizedValues(
            homeTab: 'Home',
            uploadTab: 'Upload',
            editTab: 'Edit',
            uploadSaveDraftAction: 'Save draft',
            uploadDraftSavedMessage: 'Draft saved on this device',
            captionTab: 'Calendar',
            analyticsTab: 'Analytics',
            profileTab: 'Profile',
            notificationsAction: 'Notifications',
            userAccountAction: 'User account',
            templatesTitle: 'Templates',
            loginTitle: 'Sign in to PostDee',
            loginSubtitle: 'Connect your email before using the app',
            loginRequirementMessage: 'Connect an email first so you can post and manage content.',
            loginButton: 'Sign in with Google',
            appleLoginButton: 'Sign in with Apple',
            signingInButton: 'Signing in...',
            loginDefaultHelper: 'Connect your Google email to start using PostDee',
            loginMockHelper: 'Local mock auth uses a sample email to enter the app',
            homeGreeting: 'Hello',
            homeOverviewSubtitle: "Today's posting overview",
            homeViewPackage: 'View package',
            homeTotalPosts: 'Total views',
            homeLatestPostStatus: 'Latest post status',
            homeViewAll: 'View all',
            homeShortcuts: 'Shortcuts',
            homeCalendarShortcut: 'Calendar',
            homeViewsMetric: 'Views',
            homeLikesMetric: 'Likes',
            homeRefreshViews: 'Refresh views',
            homeLoading: 'Loading...',
            homeApiConnectionError: 'Cannot connect to PostDee API',
            homeAnalyticsLoadError: 'Could not load analytics data',
            profileLanguageTitle: 'Language',
            profileLanguageDescription: 'Choose the app language',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'vi' => const PostDeeLocalizations._(
          Locale('vi'),
          _PostDeeLocalizedValues(
            homeTab: 'Trang chủ',
            uploadTab: 'Tải lên',
            editTab: 'Chỉnh sửa',
            uploadSaveDraftAction: 'Lưu bản nháp',
            uploadDraftSavedMessage: 'Đã lưu bản nháp',
            captionTab: 'Lịch',
            analyticsTab: 'Phân tích',
            profileTab: 'Hồ sơ',
            notificationsAction: 'Thông báo',
            userAccountAction: 'Tài khoản',
            templatesTitle: 'Mẫu',
            loginTitle: 'Đăng nhập vào PostDee',
            loginSubtitle: 'Kết nối email trước khi sử dụng',
            loginRequirementMessage: 'Kết nối email trước để đăng và quản lý nội dung.',
            loginButton: 'Đăng nhập bằng Google',
            appleLoginButton: 'Đăng nhập bằng Apple',
            signingInButton: 'Đang đăng nhập...',
            loginDefaultHelper: 'Kết nối email Google để sử dụng',
            loginMockHelper: 'Chế độ thử nghiệm sử dụng email mẫu',
            homeGreeting: 'Xin chào',
            homeOverviewSubtitle: 'Tổng quan bài đăng hôm nay',
            homeViewPackage: 'Xem gói',
            homeTotalPosts: 'Tổng lượt xem',
            homeLatestPostStatus: 'Trạng thái bài đăng mới nhất',
            homeViewAll: 'Xem tất cả',
            homeShortcuts: 'Lối tắt',
            homeCalendarShortcut: 'Lịch',
            homeViewsMetric: 'Lượt xem',
            homeLikesMetric: 'Thích',
            homeRefreshViews: 'Làm mới lượt xem',
            homeLoading: 'Đang tải...',
            homeApiConnectionError: 'Không thể kết nối API PostDee',
            homeAnalyticsLoadError: 'Không thể tải dữ liệu phân tích',
            profileLanguageTitle: 'Ngôn ngữ',
            profileLanguageDescription: 'Chọn ngôn ngữ ứng dụng',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'zh' => const PostDeeLocalizations._(
          Locale('zh'),
          _PostDeeLocalizedValues(
            homeTab: '首页',
            uploadTab: '上传',
            editTab: '编辑',
            uploadSaveDraftAction: '保存草稿',
            uploadDraftSavedMessage: '草稿已保存',
            captionTab: '日历',
            analyticsTab: '数据分析',
            profileTab: '我的',
            notificationsAction: '通知',
            userAccountAction: '用户账户',
            templatesTitle: '模板',
            loginTitle: '登录 PostDee',
            loginSubtitle: '使用前请绑定邮箱',
            loginRequirementMessage: '请先绑定邮箱以发布和管理内容。',
            loginButton: '使用 Google 登录',
            appleLoginButton: '使用 Apple 登录',
            signingInButton: '登录中...',
            loginDefaultHelper: '绑定 Google 邮箱以开始使用',
            loginMockHelper: '本地模拟身份验证使用测试邮箱登录',
            homeGreeting: '你好',
            homeOverviewSubtitle: '今日发布概览',
            homeViewPackage: '查看套餐',
            homeTotalPosts: '总播放量',
            homeLatestPostStatus: '最新发布状态',
            homeViewAll: '查看全部',
            homeShortcuts: '快捷方式',
            homeCalendarShortcut: '日历',
            homeViewsMetric: '播放量',
            homeLikesMetric: '点赞',
            homeRefreshViews: '刷新数据',
            homeLoading: '加载中...',
            homeApiConnectionError: '无法连接到 PostDee API',
            homeAnalyticsLoadError: '无法加载数据分析',
            profileLanguageTitle: '语言',
            profileLanguageDescription: '选择应用语言',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'id' => const PostDeeLocalizations._(
          Locale('id'),
          _PostDeeLocalizedValues(
            homeTab: 'Beranda',
            uploadTab: 'Unggah',
            editTab: 'Edit',
            uploadSaveDraftAction: 'Simpan draf',
            uploadDraftSavedMessage: 'Draf disimpan',
            captionTab: 'Kalender',
            analyticsTab: 'Analitik',
            profileTab: 'Profil',
            notificationsAction: 'Notifikasi',
            userAccountAction: 'Akun',
            templatesTitle: 'Templat',
            loginTitle: 'Masuk ke PostDee',
            loginSubtitle: 'Hubungkan email sebelum menggunakan',
            loginRequirementMessage: 'Hubungkan email agar dapat memposting.',
            loginButton: 'Masuk dengan Google',
            appleLoginButton: 'Masuk dengan Apple',
            signingInButton: 'Sedang masuk...',
            loginDefaultHelper: 'Hubungkan email Google untuk memulai',
            loginMockHelper: 'Uji coba menggunakan email sampel',
            homeGreeting: 'Halo',
            homeOverviewSubtitle: 'Ringkasan hari ini',
            homeViewPackage: 'Lihat paket',
            homeTotalPosts: 'Total tayangan',
            homeLatestPostStatus: 'Status postingan terbaru',
            homeViewAll: 'Lihat semua',
            homeShortcuts: 'Pintasan',
            homeCalendarShortcut: 'Kalender',
            homeViewsMetric: 'Tayangan',
            homeLikesMetric: 'Suka',
            homeRefreshViews: 'Segarkan',
            homeLoading: 'Memuat...',
            homeApiConnectionError: 'Tidak dapat terhubung ke API',
            homeAnalyticsLoadError: 'Tidak dapat memuat analitik',
            profileLanguageTitle: 'Bahasa',
            profileLanguageDescription: 'Pilih bahasa aplikasi',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'ms' => const PostDeeLocalizations._(
          Locale('ms'),
          _PostDeeLocalizedValues(
            homeTab: 'Laman Utama',
            uploadTab: 'Muat naik',
            editTab: 'Edit',
            uploadSaveDraftAction: 'Simpan draf',
            uploadDraftSavedMessage: 'Draf disimpan',
            captionTab: 'Kalendar',
            analyticsTab: 'Analitik',
            profileTab: 'Profil',
            notificationsAction: 'Notifikasi',
            userAccountAction: 'Akaun',
            templatesTitle: 'Templat',
            loginTitle: 'Log masuk ke PostDee',
            loginSubtitle: 'Sambungkan e-mel sebelum menggunakan',
            loginRequirementMessage: 'Sambung e-mel dahulu untuk memuat naik kandungan.',
            loginButton: 'Log masuk dengan Google',
            appleLoginButton: 'Log masuk dengan Apple',
            signingInButton: 'Sedang log masuk...',
            loginDefaultHelper: 'Sambung e-mel Google untuk bermula',
            loginMockHelper: 'Log masuk ujian menggunakan e-mel sampel',
            homeGreeting: 'Helo',
            homeOverviewSubtitle: 'Gambaran keseluruhan hari ini',
            homeViewPackage: 'Lihat pakej',
            homeTotalPosts: 'Jumlah tontonan',
            homeLatestPostStatus: 'Status terkini',
            homeViewAll: 'Lihat semua',
            homeShortcuts: 'Pintasan',
            homeCalendarShortcut: 'Kalendar',
            homeViewsMetric: 'Tontonan',
            homeLikesMetric: 'Suka',
            homeRefreshViews: 'Segarkan',
            homeLoading: 'Memuatkan...',
            homeApiConnectionError: 'Tidak dapat menyambung ke API',
            homeAnalyticsLoadError: 'Tidak dapat memuatkan data',
            profileLanguageTitle: 'Bahasa',
            profileLanguageDescription: 'Pilih bahasa aplikasi',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'tl' => const PostDeeLocalizations._(
          Locale('tl'),
          _PostDeeLocalizedValues(
            homeTab: 'Home',
            uploadTab: 'I-upload',
            editTab: 'I-edit',
            uploadSaveDraftAction: 'I-save ang draft',
            uploadDraftSavedMessage: 'Na-save ang draft',
            captionTab: 'Kalendaryo',
            analyticsTab: 'Pagsusuri',
            profileTab: 'Profile',
            notificationsAction: 'Mga Notification',
            userAccountAction: 'Account',
            templatesTitle: 'Mga Template',
            loginTitle: 'Mag-sign in sa PostDee',
            loginSubtitle: 'Ikonekta ang email',
            loginRequirementMessage: 'Ikonekta muna ang email bago mag-post.',
            loginButton: 'Mag-sign in gamit ang Google',
            appleLoginButton: 'Mag-sign in gamit ang Apple',
            signingInButton: 'Nagsa-sign in...',
            loginDefaultHelper: 'Ikonekta ang Google email',
            loginMockHelper: 'Gumagamit ng sample email para sa test mode',
            homeGreeting: 'Kamusta',
            homeOverviewSubtitle: 'Pangkalahatang-ideya ngayon',
            homeViewPackage: 'Tingnan ang package',
            homeTotalPosts: 'Kabuuang views',
            homeLatestPostStatus: 'Status ng pinakabagong post',
            homeViewAll: 'Tingnan lahat',
            homeShortcuts: 'Mga Shortcut',
            homeCalendarShortcut: 'Kalendaryo',
            homeViewsMetric: 'Views',
            homeLikesMetric: 'Likes',
            homeRefreshViews: 'I-refresh',
            homeLoading: 'Naglo-load...',
            homeApiConnectionError: 'Hindi makakonekta sa API',
            homeAnalyticsLoadError: 'Hindi ma-load ang data',
            profileLanguageTitle: 'Wika',
            profileLanguageDescription: 'Piliin ang wika ng app',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      'ja' => const PostDeeLocalizations._(
          Locale('ja'),
          _PostDeeLocalizedValues(
            homeTab: 'ホーム',
            uploadTab: 'アップロード',
            editTab: '編集',
            uploadSaveDraftAction: '下書きを保存',
            uploadDraftSavedMessage: '下書きを保存しました',
            captionTab: 'カレンダー',
            analyticsTab: '分析',
            profileTab: 'プロフィール',
            notificationsAction: '通知',
            userAccountAction: 'アカウント',
            templatesTitle: 'テンプレート',
            loginTitle: 'PostDee にログイン',
            loginSubtitle: 'メールを連携してください',
            loginRequirementMessage: '投稿するには先にメールを連携してください。',
            loginButton: 'Google でログイン',
            appleLoginButton: 'Apple でログイン',
            signingInButton: 'ログイン中...',
            loginDefaultHelper: 'Google メールを連携して開始',
            loginMockHelper: 'テスト用のメールでログインします',
            homeGreeting: 'こんにちは',
            homeOverviewSubtitle: '今日の投稿概要',
            homeViewPackage: 'プランを見る',
            homeTotalPosts: '総再生回数',
            homeLatestPostStatus: '最新の投稿ステータス',
            homeViewAll: 'すべて見る',
            homeShortcuts: 'ショートカット',
            homeCalendarShortcut: 'カレンダー',
            homeViewsMetric: '再生回数',
            homeLikesMetric: 'いいね',
            homeRefreshViews: '更新',
            homeLoading: '読み込み中...',
            homeApiConnectionError: 'API に接続できません',
            homeAnalyticsLoadError: 'データを読み込めません',
            profileLanguageTitle: '言語',
            profileLanguageDescription: 'アプリの言語を選択',
            languageEnglish: 'English',
            languageThai: 'ไทย',
            languageVietnamese: 'Tiếng Việt',
            languageChinese: '中文',
            languageIndonesian: 'Bahasa Indonesia',
            languageMalay: 'Bahasa Melayu',
            languageTagalog: 'Tagalog',
            languageJapanese: '日本語',
          ),
        ),
      _ => lookup(const Locale('en')),
    };
  }

  String get homeTab => _values.homeTab;
  String get uploadTab => _values.uploadTab;
  String get editTab => _values.editTab;
  String get uploadSaveDraftAction => _values.uploadSaveDraftAction;
  String get uploadDraftSavedMessage => _values.uploadDraftSavedMessage;
  String get captionTab => _values.captionTab;
  String get analyticsTab => _values.analyticsTab;
  String get profileTab => _values.profileTab;
  String get notificationsAction => _values.notificationsAction;
  String get userAccountAction => _values.userAccountAction;
  String get templatesTitle => _values.templatesTitle;
  String get loginTitle => _values.loginTitle;
  String get loginSubtitle => _values.loginSubtitle;
  String get loginRequirementMessage => _values.loginRequirementMessage;
  String get loginButton => _values.loginButton;
  String get appleLoginButton => _values.appleLoginButton;
  String get signingInButton => _values.signingInButton;
  String get loginDefaultHelper => _values.loginDefaultHelper;
  String get loginMockHelper => _values.loginMockHelper;
  String get homeGreeting => _values.homeGreeting;
  String get homeOverviewSubtitle => _values.homeOverviewSubtitle;
  String get homeViewPackage => _values.homeViewPackage;
  String get homeTotalPosts => _values.homeTotalPosts;
  String get homeLatestPostStatus => _values.homeLatestPostStatus;
  String get homeViewAll => _values.homeViewAll;
  String get homeShortcuts => _values.homeShortcuts;
  String get homeCalendarShortcut => _values.homeCalendarShortcut;
  String get homeViewsMetric => _values.homeViewsMetric;
  String get homeLikesMetric => _values.homeLikesMetric;
  String get homeRefreshViews => _values.homeRefreshViews;
  String get homeLoading => _values.homeLoading;
  String get homeApiConnectionError => _values.homeApiConnectionError;
  String get homeAnalyticsLoadError => _values.homeAnalyticsLoadError;
  String get profileLanguageTitle => _values.profileLanguageTitle;
  String get profileLanguageDescription => _values.profileLanguageDescription;
  String get languageEnglish => _values.languageEnglish;
  String get languageThai => _values.languageThai;
  String get languageVietnamese => _values.languageVietnamese;
  String get languageChinese => _values.languageChinese;
  String get languageIndonesian => _values.languageIndonesian;
  String get languageMalay => _values.languageMalay;
  String get languageTagalog => _values.languageTagalog;
  String get languageJapanese => _values.languageJapanese;
}

class _PostDeeLocalizedValues {
  const _PostDeeLocalizedValues({
    required this.homeTab,
    required this.uploadTab,
    required this.editTab,
    required this.uploadSaveDraftAction,
    required this.uploadDraftSavedMessage,
    required this.captionTab,
    required this.analyticsTab,
    required this.profileTab,
    required this.notificationsAction,
    required this.userAccountAction,
    required this.templatesTitle,
    required this.loginTitle,
    required this.loginSubtitle,
    required this.loginRequirementMessage,
    required this.loginButton,
    required this.appleLoginButton,
    required this.signingInButton,
    required this.loginDefaultHelper,
    required this.loginMockHelper,
    required this.homeGreeting,
    required this.homeOverviewSubtitle,
    required this.homeViewPackage,
    required this.homeTotalPosts,
    required this.homeLatestPostStatus,
    required this.homeViewAll,
    required this.homeShortcuts,
    required this.homeCalendarShortcut,
    required this.homeViewsMetric,
    required this.homeLikesMetric,
    required this.homeRefreshViews,
    required this.homeLoading,
    required this.homeApiConnectionError,
    required this.homeAnalyticsLoadError,
    required this.profileLanguageTitle,
    required this.profileLanguageDescription,
    required this.languageEnglish,
    required this.languageThai,
    required this.languageVietnamese,
    required this.languageChinese,
    required this.languageIndonesian,
    required this.languageMalay,
    required this.languageTagalog,
    required this.languageJapanese,
  });

  final String homeTab;
  final String uploadTab;
  final String editTab;
  final String uploadSaveDraftAction;
  final String uploadDraftSavedMessage;
  final String captionTab;
  final String analyticsTab;
  final String profileTab;
  final String notificationsAction;
  final String userAccountAction;
  final String templatesTitle;
  final String loginTitle;
  final String loginSubtitle;
  final String loginRequirementMessage;
  final String loginButton;
  final String appleLoginButton;
  final String signingInButton;
  final String loginDefaultHelper;
  final String loginMockHelper;
  final String homeGreeting;
  final String homeOverviewSubtitle;
  final String homeViewPackage;
  final String homeTotalPosts;
  final String homeLatestPostStatus;
  final String homeViewAll;
  final String homeShortcuts;
  final String homeCalendarShortcut;
  final String homeViewsMetric;
  final String homeLikesMetric;
  final String homeRefreshViews;
  final String homeLoading;
  final String homeApiConnectionError;
  final String homeAnalyticsLoadError;
  final String profileLanguageTitle;
  final String profileLanguageDescription;
  final String languageEnglish;
  final String languageThai;
  final String languageVietnamese;
  final String languageChinese;
  final String languageIndonesian;
  final String languageMalay;
  final String languageTagalog;
  final String languageJapanese;
}

class _PostDeeLocalizationsDelegate
    extends LocalizationsDelegate<PostDeeLocalizations> {
  const _PostDeeLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return PostDeeLocalizations.supportedLocales.any(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
    );
  }

  @override
  Future<PostDeeLocalizations> load(Locale locale) {
    return SynchronousFuture(PostDeeLocalizations.lookup(locale));
  }

  @override
  bool shouldReload(_PostDeeLocalizationsDelegate old) => false;
}
