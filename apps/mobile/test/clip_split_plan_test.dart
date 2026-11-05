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

  test('exact per-channel ranges allow gaps and share equal output files', () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 180,
        platforms: _channels,
        segmentOverrides: const {
          SocialPlatform.facebookReels: [
            ClipSplitSegment(startSeconds: 0, endSeconds: 60),
            ClipSplitSegment(startSeconds: 80, endSeconds: 160),
          ],
          SocialPlatform.instagramReels: [
            ClipSplitSegment(startSeconds: 0, endSeconds: 60),
          ],
        });
    expect(plan.totalPostUnits, 5);
    expect(plan.groupedParts, hasLength(3));
    final shared = plan.groupedParts
        .singleWhere((part) => part.startSeconds == 0 && part.endSeconds == 60);
    expect(shared.platforms,
        {SocialPlatform.instagramReels, SocialPlatform.facebookReels});
    expect(shared.minDurationSeconds, 3);
    expect(shared.maxDurationSeconds, 90);
    expect(shared.isOriginal, isFalse);
    final original = plan.groupedParts.singleWhere((part) => part.isOriginal);
    expect(original.platforms,
        {SocialPlatform.tiktok, SocialPlatform.youtubeShorts});
    expect(original.endSeconds, 180);
    expect(
        plan
            .channelPlanFor(SocialPlatform.facebookReels)
            .segments
            .last
            .startSeconds,
        80);
  });

  test('same-parts uses one override for all channels at normalized ticks', () {
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 180,
        platforms: _channels,
        mode: ClipSplitMode.sameParts,
        segmentOverrides: const {
          SocialPlatform.facebookReels: [
            ClipSplitSegment(startSeconds: .0000001, endSeconds: 60.0000001),
            ClipSplitSegment(startSeconds: 80.0000001, endSeconds: 160.0000001),
          ],
          SocialPlatform.youtubeShorts: [
            ClipSplitSegment(startSeconds: 0, endSeconds: 60),
            ClipSplitSegment(startSeconds: 80, endSeconds: 160),
          ],
        });
    expect(plan.totalPostUnits, 8);
    expect(plan.groupedParts, hasLength(2));
    expect(plan.groupedParts.map((part) => part.startSeconds), [0, 80]);
    expect(plan.groupedParts.map((part) => part.endSeconds), [60, 160]);
    for (final part in plan.groupedParts) {
      expect(part.platforms, _channels);
      expect(part.isOriginal, isFalse);
    }
    final singleOverride = ClipSplitPlan.create(
        sourceDurationSeconds: 180,
        platforms: _channels,
        mode: ClipSplitMode.sameParts,
        segmentOverrides: const {
          SocialPlatform.facebookReels: [
            ClipSplitSegment(startSeconds: 5, endSeconds: 65),
            ClipSplitSegment(startSeconds: 90, endSeconds: 175),
          ],
        });
    expect(singleOverride.groupedParts, hasLength(2));
    expect(singleOverride.groupedParts.first.startSeconds, 5);
    expect(singleOverride.groupedParts.last.endSeconds, 175);
    expect(
        singleOverride.groupedParts
            .every((part) => part.platforms.length == _channels.length),
        isTrue);
  });

  test('one cropped segment is encoded rather than treated as the original',
      () {
    for (final start in [0.0, 10.0]) {
      final plan = ClipSplitPlan.create(sourceDurationSeconds: 270, platforms: {
        SocialPlatform.instagramReels
      }, segmentOverrides: {
        SocialPlatform.instagramReels: [
          ClipSplitSegment(startSeconds: start, endSeconds: start + 60),
        ],
      });
      expect(plan.totalPostUnits, 1);
      expect(plan.groupedParts.single.isOriginal, isFalse);
      expect(plan.groupedParts.single.startSeconds, start);
      expect(plan.groupedParts.single.endSeconds, start + 60);
    }
  });

  test('same-parts rejects conflicting overrides and shared duration limits',
      () {
    final invalid = throwsA(isA<ClipSplitPlanException>().having(
        (error) => error.problem,
        'problem',
        ClipSplitPlanProblem.invalidSegmentRange));
    expect(
        () => ClipSplitPlan.create(
                sourceDurationSeconds: 180,
                platforms: _channels,
                mode: ClipSplitMode.sameParts,
                segmentOverrides: const {
                  SocialPlatform.facebookReels: [
                    ClipSplitSegment(startSeconds: 0, endSeconds: 60),
                    ClipSplitSegment(startSeconds: 80, endSeconds: 160),
                  ],
                  SocialPlatform.youtubeShorts: [
                    ClipSplitSegment(startSeconds: 0, endSeconds: 61),
                    ClipSplitSegment(startSeconds: 80, endSeconds: 160),
                  ],
                }),
        invalid);
    for (final firstEnd in [2.999999, 90.000001]) {
      expect(
          () => ClipSplitPlan.create(
                  sourceDurationSeconds: 180,
                  platforms: _channels,
                  mode: ClipSplitMode.sameParts,
                  segmentOverrides: {
                    SocialPlatform.tiktok: [
                      ClipSplitSegment(startSeconds: 0, endSeconds: firstEnd),
                      const ClipSplitSegment(
                          startSeconds: 100, endSeconds: 180),
                    ],
                  }),
          invalid);
    }
  });

  test('rejects invalid ranges without changing the default part count', () {
    final invalid = throwsA(isA<ClipSplitPlanException>().having(
        (error) => error.problem,
        'problem',
        ClipSplitPlanProblem.invalidSegmentRange));
    for (final segments in <List<ClipSplitSegment>>[
      [],
      [const ClipSplitSegment(startSeconds: 0, endSeconds: 90)],
      [
        const ClipSplitSegment(startSeconds: 0, endSeconds: 50),
        const ClipSplitSegment(startSeconds: 50, endSeconds: 100),
        const ClipSplitSegment(startSeconds: 100, endSeconds: 150),
      ],
      for (final first in [
        const ClipSplitSegment(startSeconds: -1, endSeconds: 50),
        const ClipSplitSegment(startSeconds: 50, endSeconds: 50),
        const ClipSplitSegment(startSeconds: 51, endSeconds: 50),
        const ClipSplitSegment(startSeconds: 0, endSeconds: 2.999999),
        const ClipSplitSegment(startSeconds: 0, endSeconds: 90.000001),
        const ClipSplitSegment(startSeconds: double.nan, endSeconds: 50),
        const ClipSplitSegment(startSeconds: 0, endSeconds: double.infinity),
        const ClipSplitSegment(startSeconds: 10, endSeconds: 10.0000001),
      ])
        [first, const ClipSplitSegment(startSeconds: 100, endSeconds: 180)],
      [
        const ClipSplitSegment(startSeconds: 0, endSeconds: 90),
        const ClipSplitSegment(startSeconds: 90, endSeconds: 180.000001),
      ],
      [
        const ClipSplitSegment(startSeconds: 0, endSeconds: 80),
        const ClipSplitSegment(startSeconds: 79.999999, endSeconds: 160),
      ],
      [
        const ClipSplitSegment(startSeconds: 90, endSeconds: 180),
        const ClipSplitSegment(startSeconds: 0, endSeconds: 90),
      ],
    ]) {
      expect(
          () => ClipSplitPlan.create(
              sourceDurationSeconds: 180,
              platforms: {SocialPlatform.facebookReels},
              segmentOverrides: {SocialPlatform.facebookReels: segments}),
          invalid);
    }
  });

  test('exact ranges respect the current TikTok Direct account cap', () {
    const segments = [
      ClipSplitSegment(startSeconds: 0, endSeconds: 50),
      ClipSplitSegment(startSeconds: 60, endSeconds: 120),
      ClipSplitSegment(startSeconds: 125, endSeconds: 180),
    ];
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 180,
        platforms: {SocialPlatform.tiktok},
        tikTokDirectPost: true,
        tikTokMaxDurationSeconds: 75,
        segmentOverrides: const {SocialPlatform.tiktok: segments});
    expect(plan.totalPostUnits, 3);
    expect(plan.channelPlans.single.maximumDurationSeconds, 75);
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 180,
            platforms: {SocialPlatform.tiktok},
            tikTokDirectPost: true,
            tikTokMaxDurationSeconds: 75,
            segmentOverrides: const {
              SocialPlatform.tiktok: [
                ClipSplitSegment(startSeconds: 0, endSeconds: 76),
                ClipSplitSegment(startSeconds: 76, endSeconds: 125),
                ClipSplitSegment(startSeconds: 125, endSeconds: 180),
              ]
            }),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.invalidSegmentRange)));
    expect(
        () => ClipSplitPlan.create(
            sourceDurationSeconds: 180,
            platforms: {SocialPlatform.tiktok},
            tikTokDirectPost: true,
            segmentOverrides: const {SocialPlatform.tiktok: segments}),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.tikTokAccountRequired)));
  });

  test('overrides preserve output budgets and copy caller-owned ranges', () {
    final segments = [
      const ClipSplitSegment(startSeconds: 0, endSeconds: 60),
      const ClipSplitSegment(startSeconds: 80, endSeconds: 160),
    ];
    final plan = ClipSplitPlan.create(
        sourceDurationSeconds: 180,
        platforms: {SocialPlatform.facebookReels},
        firstBoundaries: {SocialPlatform.facebookReels: 180},
        segmentOverrides: {SocialPlatform.facebookReels: segments});
    segments.clear();
    expect(plan.channelPlans.single.segments, hasLength(2));
    expect(() => plan.channelPlans.single.segments.clear(),
        throwsUnsupportedError);
    expect(
        () => ClipSplitPlan.create(
                sourceDurationSeconds: 90 * maxClipSplitParts + .001,
                platforms: {
                  SocialPlatform.facebookReels
                },
                segmentOverrides: const {
                  SocialPlatform.facebookReels: [
                    ClipSplitSegment(startSeconds: 0, endSeconds: 90),
                  ],
                }),
        throwsA(isA<ClipSplitPlanException>().having((error) => error.problem,
            'problem', ClipSplitPlanProblem.tooManyParts)));
  });
}
