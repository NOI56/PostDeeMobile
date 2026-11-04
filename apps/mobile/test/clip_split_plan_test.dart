import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/clip_split_plan.dart';

const _channels = {
  SocialPlatform.tiktok,
  SocialPlatform.youtubeShorts,
  SocialPlatform.instagramReels,
  SocialPlatform.facebookReels,
};

void main() {
  test('splits only long destinations and shares identical draft files', () {
    final plan =
        ClipSplitPlan.create(sourceDurationSeconds: 270, platforms: _channels);
    expect(plan.totalPostUnits, 7);
    expect(plan.groupedParts.length, 6);
    expect(
        plan.channelPlanFor(SocialPlatform.facebookReels).segments.length, 3);
    expect(
        plan.channelPlanFor(SocialPlatform.youtubeShorts).segments.length, 2);
    final original = plan.groupedParts.singleWhere((part) => part.isOriginal);
    expect(original.platforms,
        {SocialPlatform.tiktok, SocialPlatform.instagramReels});
    expect(original.startSeconds, 0);
    expect(original.endSeconds, 270);
    expect(plan.requiresSplitting, isTrue);
  });

  test('same-parts mode shares each range across all destinations', () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 270,
        platforms: _channels,
        mode: ClipSplitMode.sameParts);
    expect(plan.totalPostUnits, 12);
    expect(plan.groupedParts.length, 3);
    for (final part in plan.groupedParts) {
      expect(part.platforms, _channels);
      expect(part.endSeconds - part.startSeconds, 90);
      expect(part.isOriginal, isFalse);
    }
  });

  test('balances a short remainder and preserves all measured milliseconds',
      () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 181.125,
        platforms: {SocialPlatform.facebookReels});
    final segments = plan.channelPlans.single.segments;
    expect(segments.length, 3);
    expect(segments.first.startSeconds, 0);
    expect(segments.last.endSeconds, 181.125);
    for (var i = 0; i < segments.length; i++) {
      expect(segments[i].durationSeconds, inInclusiveRange(3, 90));
      if (i > 0) {
        expect(segments[i].startSeconds, segments[i - 1].endSeconds);
      }
    }
    expect(
        segments
            .map((segment) => segment.durationSeconds)
            .reduce((a, b) => a + b),
        closeTo(181.125, .000001));
  });

  test('allows adjusting a boundary without losing content', () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 270,
        platforms: {SocialPlatform.youtubeShorts},
        firstBoundaries: {SocialPlatform.youtubeShorts: 150});
    final segments = plan.channelPlans.single.segments;
    expect(segments.first.endSeconds, 150);
    expect(segments.last.startSeconds, 150);
    expect(segments.last.endSeconds, 270);
    expect(plan.channelPlans.single.minimumFirstBoundarySeconds, 90);
    expect(plan.channelPlans.single.maximumFirstBoundarySeconds, 180);
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 270,
            platforms: {SocialPlatform.youtubeShorts},
            firstBoundaries: {SocialPlatform.youtubeShorts: 181}),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.invalidBoundary)));
  });

  test('uses real Direct TikTok cap and refuses an unknown account limit', () {
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 270,
            platforms: {SocialPlatform.tiktok},
            tikTokDirectPost: true),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.tikTokAccountRequired)));
    final direct = ClipSplitPlan.create(
        sourceDurationSeconds: 270,
        platforms: {SocialPlatform.tiktok},
        tikTokDirectPost: true,
        tikTokMaxDurationSeconds: 180);
    expect(direct.channelPlans.single.segments.length, 2);
    final draft = ClipSplitPlan.create(
        sourceDurationSeconds: 270,
        platforms: {SocialPlatform.tiktok},
        tikTokMaxDurationSeconds: 180);
    expect(draft.channelPlans.single.segments.length, 1);
    final capped = ClipSplitPlan.create(
        sourceDurationSeconds: 750,
        platforms: {SocialPlatform.tiktok},
        tikTokDirectPost: true,
        tikTokMaxDurationSeconds: 3600);
    expect(capped.channelPlans.single.maximumDurationSeconds, 600);
    expect(capped.totalPostUnits, 2);
  });

  test('sub-millisecond excess is not rounded down across a provider limit',
      () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 180.0004,
        platforms: {SocialPlatform.youtubeShorts});
    expect(plan.channelPlans.single.segments.length, 2);
    expect(plan.channelPlans.single.segments.last.endSeconds, 180.0004);
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 2.9999,
            platforms: {SocialPlatform.facebookReels}),
        throwsA(isA<ClipSplitPlanException>()));
  });

  test('fails closed for empty, invalid, unsupported and too-short selections',
      () {
    for (final duration in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
          () => ClipSplitPlan.create(
              sourceDurationSeconds: duration, platforms: _channels),
          throwsA(isA<ClipSplitPlanException>()));
    }
    expect(() => ClipSplitPlan.create(sourceDurationSeconds: 90, platforms: {}),
        throwsA(isA<ClipSplitPlanException>()));
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 90, platforms: {SocialPlatform.shopeeVideo}),
        throwsA(isA<ClipSplitPlanException>()));
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 2.9,
            platforms: {SocialPlatform.facebookReels}),
        throwsA(isA<ClipSplitPlanException>()));
  });

  test('limits unique output jobs before encoding can start', () {
    final allowed = ClipSplitPlan.create(
        sourceDurationSeconds: 90 * maxClipSplitParts.toDouble(),
        platforms: {SocialPlatform.facebookReels});
    expect(allowed.groupedParts.length, maxClipSplitParts);
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 90 * maxClipSplitParts + .001,
            platforms: {SocialPlatform.facebookReels}),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.tooManyParts)));
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 4000, platforms: _channels),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.tooManyParts)));
  });

  test(
      'a fitting source stays one original and all public collections are immutable',
      () {
    final plan =
        ClipSplitPlan.create(sourceDurationSeconds: 45, platforms: _channels);
    expect(plan.requiresSplitting, isFalse);
    expect(plan.groupedParts.single.isOriginal, isTrue);
    expect(plan.totalPostUnits, 4);
    expect(() => plan.platforms.clear(), throwsUnsupportedError);
    expect(() => plan.groupedParts.clear(), throwsUnsupportedError);
    expect(
        () => plan.channelPlans
            .singleWhere((p) => p.platform == SocialPlatform.tiktok)
            .segments
            .clear(),
        throwsUnsupportedError);
  });
}
