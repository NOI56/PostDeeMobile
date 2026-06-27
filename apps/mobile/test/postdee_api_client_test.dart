import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';

void main() {
  test('ApiHealthResult parses backend health payload', () {
    final health = ApiHealthResult.fromJson({
      'status': 'ok',
      'service': 'postdee-api',
    });

    expect(health.status, 'ok');
    expect(health.service, 'postdee-api');
    expect(health.isOk, isTrue);
  });

  test('VerifyStorePurchaseRequest serializes Android purchase tokens', () {
    expect(
      const VerifyStorePurchaseRequest.android(
        purchaseToken: 'android-token',
      ).toJson(),
      {
        'platform': 'ANDROID',
        'productId': 'postdee_pro_monthly',
        'purchaseToken': 'android-token',
      },
    );
  });

  test('VerifyStorePurchaseRequest serializes iOS transaction ids', () {
    expect(
      const VerifyStorePurchaseRequest.ios(
        transactionId: 'ios-transaction',
      ).toJson(),
      {
        'platform': 'IOS',
        'productId': 'postdee_pro_monthly',
        'transactionId': 'ios-transaction',
      },
    );
  });

  test('StoreSubscriptionVerificationResult parses purchase and subscription',
      () {
    final result = StoreSubscriptionVerificationResult.fromJson({
      'purchase': {
        'provider': 'mock-store',
        'platform': 'ANDROID',
        'productId': 'postdee_pro_monthly',
        'verifiedAt': '2026-06-04T00:00:00.000Z',
      },
      'subscription': {
        'userId': 'seller-store',
        'plan': 'PRO',
        'status': 'ACTIVE',
        'monthlyPostLimit': null,
        'usedPostsThisMonth': null,
        'remainingPostsThisMonth': null,
        'canSchedule': true,
        'canUseAiCaptions': true,
        'canUseAnalytics': true,
      },
    });

    expect(result.purchase.platform, 'ANDROID');
    expect(result.purchase.productId, 'postdee_pro_monthly');
    expect(result.subscription.isPro, isTrue);
  });

  test('SubscriptionStatusResult parses monthly post usage', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-usage',
      'plan': 'BASIC',
      'status': 'INACTIVE',
      'monthlyPostLimit': 3,
      'usedPostsThisMonth': 2,
      'remainingPostsThisMonth': 1,
      'phoneVerified': true,
      'requiresPhoneVerification': false,
      'canUseFreePostQuota': true,
      'canSchedule': false,
      'canUseAiCaptions': false,
      'canUseAnalytics': false,
    });

    expect(subscription.phoneVerified, isTrue);
    expect(subscription.requiresPhoneVerification, isFalse);
    expect(subscription.canUseFreePostQuota, isTrue);
    expect(subscription.usedPostsThisMonth, 2);
    expect(subscription.remainingPostsThisMonth, 1);
  });

  test('SubscriptionStatusResult parses phone verification gates', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-basic',
      'plan': 'BASIC',
      'status': 'INACTIVE',
      'monthlyPostLimit': 3,
      'usedPostsThisMonth': 0,
      'remainingPostsThisMonth': 0,
      'phoneVerified': false,
      'requiresPhoneVerification': true,
      'canUseFreePostQuota': false,
      'canSchedule': false,
      'canUseAiCaptions': false,
      'canUseAnalytics': false,
    });

    expect(subscription.phoneVerified, isFalse);
    expect(subscription.requiresPhoneVerification, isTrue);
    expect(subscription.canUseFreePostQuota, isFalse);
  });

  test('SubscriptionStatusResult keeps legacy AI review gates disabled', () {
    final subscription = SubscriptionStatusResult.fromJson({
      'userId': 'seller-starter',
      'plan': 'STARTER',
      'status': 'ACTIVE',
      'monthlyPostLimit': 120,
      'usedPostsThisMonth': 5,
      'remainingPostsThisMonth': 115,
      'canSchedule': true,
      'canUseAiCaptions': true,
      'canUseAnalytics': false,
      'canUseAiAudioReview': false,
      'canUseAiVideoReview': false,
    });

    expect(subscription.isStarter, isTrue);
    expect(subscription.isPro, isFalse);
    expect(subscription.canSchedule, isTrue);
    expect(subscription.monthlyPostLimit, 120);
    expect(subscription.canUseAiAudioReview, isFalse);
    expect(subscription.canUseAiVideoReview, isFalse);
  });

  test('GenerateRealClipCaptionRequest serializes selected clip context only',
      () {
    expect(
      const GenerateRealClipCaptionRequest(
        videoS3Key: 'uploads/demo.mp4',
        guidance: 'make it friendly',
        selectedFrameKeys: ['frames/one.jpg'],
        deleteAfterUse: true,
      ).toJson(),
      {
        'videoS3Key': 'uploads/demo.mp4',
        'guidance': 'make it friendly',
        'selectedFrameKeys': ['frames/one.jpg'],
        'deleteAfterUse': true,
      },
    );
  });

  test('RealClipCaptionResult parses SEO, hook, source, and quota payloads',
      () {
    final result = RealClipCaptionResult.fromJson({
      'caption': 'Caption option',
      'captionOptions': ['Caption option', 'Second option'],
      'hooks': ['Hook one', 'Hook two'],
      'hashtags': ['#PostDee', '#ShortVideo'],
      'seoKeywords': ['short video', 'affiliate seller'],
      'searchTitle': 'Best moments from demo.mp4',
      'context': {
        'selectedCaptionLanguage': 'English',
        'selectedTargetMarket': 'United States',
        'selectedTone': 'affiliate',
        'detectedSpokenLanguage': 'Thai',
        'suggestedCaptionLanguage': 'English',
        'suggestedTargetMarket': 'United States',
      },
      'source': {
        'videoS3Key': 'uploads/demo.mp4',
        'mode': 'AUDIO_WITH_FRAMES',
        'selectedFrameCount': 2,
      },
      'quota': {
        'limit': 120,
        'usedThisMonth': 1,
        'remainingThisMonth': 119,
      },
    });

    expect(result.caption, 'Caption option');
    expect(result.captionOptions, ['Caption option', 'Second option']);
    expect(result.hooks, ['Hook one', 'Hook two']);
    expect(result.hashtags, ['#PostDee', '#ShortVideo']);
    expect(result.seoKeywords, ['short video', 'affiliate seller']);
    expect(result.searchTitle, 'Best moments from demo.mp4');
    expect(result.context.selectedCaptionLanguage, 'English');
    expect(result.context.selectedTargetMarket, 'United States');
    expect(result.context.selectedTone, 'affiliate');
    expect(result.context.detectedSpokenLanguage, 'Thai');
    expect(result.source.videoS3Key, 'uploads/demo.mp4');
    expect(result.source.mode, 'AUDIO_WITH_FRAMES');
    expect(result.source.selectedFrameCount, 2);
    expect(result.quota.limit, 120);
    expect(result.quota.usedThisMonth, 1);
    expect(result.quota.remainingThisMonth, 119);
  });

  test('ScheduledPostResult parses calendar post payloads', () {
    final post = ScheduledPostResult.fromJson({
      'id': 'post-1',
      'caption': 'Launch clip',
      'videoS3Key': 'uploads/launch.mp4',
      'platforms': ['TIKTOK', 'YOUTUBE_SHORTS'],
      'scheduledAt': '2026-06-07T11:30:00.000Z',
      'status': 'QUEUED',
      'createdAt': '2026-06-01T00:00:00.000Z',
    });

    expect(post.id, 'post-1');
    expect(post.caption, 'Launch clip');
    expect(post.platforms, ['TIKTOK', 'YOUTUBE_SHORTS']);
    expect(
        post.scheduledAt.toUtc().toIso8601String(), '2026-06-07T11:30:00.000Z');
    expect(post.status, 'QUEUED');
  });


  test('SocialConnectionResult parses connected platform status', () {
    final result = SocialConnectionResult.fromJson({
      'platform': 'TIKTOK',
      'connected': true,
      'displayName': '@seller_one',
      'externalAccountId': 'external-tiktok',
      'connectedAt': '2026-06-26T09:00:00.000Z',
    });

    expect(result.platform, 'TIKTOK');
    expect(result.connected, isTrue);
    expect(result.displayName, '@seller_one');
    expect(result.externalAccountId, 'external-tiktok');
    expect(result.connectedAt?.toUtc().toIso8601String(),
        '2026-06-26T09:00:00.000Z');
  });

  test('SocialConnectLinkResult parses connect URLs', () {
    final result = SocialConnectLinkResult.fromJson({
      'connectUrl': 'https://postpeer.test/connect/youtube',
      'expiresAt': '2026-06-26T09:10:00.000Z',
    });

    expect(result.connectUrl.toString(), 'https://postpeer.test/connect/youtube');
    expect(result.expiresAt?.toUtc().toIso8601String(),
        '2026-06-26T09:10:00.000Z');
  });

  test(
      'PostDeeApiAuthHeaders sends a Firebase bearer token when one is available',
      () async {
    final headers = await PostDeeApiAuthHeaders(
      authTokenProvider: () async => 'firebase-id-token',
      mockUserId: 'local-dev-user',
      mockSubscriptionPlan: 'PRO',
    ).load();

    expect(headers, {
      'Accept': 'application/json',
      'x-postdee-subscription-plan': 'PRO',
      'Authorization': 'Bearer firebase-id-token',
    });
  });

  test(
      'PostDeeApiAuthHeaders falls back to mock development headers without a token',
      () async {
    final headers = await PostDeeApiAuthHeaders(
      authTokenProvider: () async => '',
      mockUserId: 'seller-dev',
      mockSubscriptionPlan: 'PRO',
    ).load();

    expect(headers, {
      'Accept': 'application/json',
      'x-postdee-user-id': 'seller-dev',
      'x-postdee-subscription-plan': 'PRO',
    });
  });

  test('AppConfig leaves development auth overrides empty by default', () {
    expect(AppConfig.mockUserId, isEmpty);
    expect(AppConfig.mockSubscriptionPlan, isEmpty);
  });
}
