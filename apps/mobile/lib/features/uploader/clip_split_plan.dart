import 'dart:math' as math;

import '../platforms/social_platform.dart';
import 'platform_publish_preflight.dart';

const maxClipSplitParts = 64;
const _ticksPerSecond = 1000000;

enum ClipSplitMode { affectedChannels, sameParts }

enum ClipSplitPlanProblem {
  invalidDuration,
  noPlatforms,
  unsupportedPlatform,
  tikTokAccountRequired,
  tooShort,
  tooManyParts,
  invalidBoundary,
  noSharedRange,
}

class ClipSplitPlanException implements Exception {
  const ClipSplitPlanException(this.problem);

  final ClipSplitPlanProblem problem;

  @override
  String toString() => 'ClipSplitPlanException: ${problem.name}';
}

class ClipSplitSegment {
  const ClipSplitSegment({
    required this.startSeconds,
    required this.endSeconds,
  });

  final double startSeconds;
  final double endSeconds;
  double get durationSeconds => endSeconds - startSeconds;
}

class ClipSplitChannelPlan {
  ClipSplitChannelPlan._({
    required this.platform,
    required this.minimumDurationSeconds,
    required this.maximumDurationSeconds,
    required List<ClipSplitSegment> segments,
    required this.minimumFirstBoundarySeconds,
    required this.maximumFirstBoundarySeconds,
  }) : segments = List.unmodifiable(segments);

  final SocialPlatform platform;
  final double minimumDurationSeconds;
  final double maximumDurationSeconds;
  final List<ClipSplitSegment> segments;
  final double? minimumFirstBoundarySeconds;
  final double? maximumFirstBoundarySeconds;

  bool get canAdjustFirstBoundary =>
      minimumFirstBoundarySeconds != null &&
      maximumFirstBoundarySeconds != null &&
      minimumFirstBoundarySeconds! < maximumFirstBoundarySeconds!;
}

/// A single file/draft job. Equal source intervals share one file across channels.
class ClipSplitPart {
  ClipSplitPart._({
    required this.index,
    required this.startSeconds,
    required this.endSeconds,
    required Set<SocialPlatform> platforms,
    required this.minDurationSeconds,
    required this.maxDurationSeconds,
    required this.isOriginal,
  }) : platforms = Set.unmodifiable(platforms);

  final int index;
  final double startSeconds;
  final double endSeconds;
  final Set<SocialPlatform> platforms;
  final double minDurationSeconds;
  final double maxDurationSeconds;
  final bool isOriginal;
  double get durationSeconds => endSeconds - startSeconds;
}

/// A local preparation plan only: it neither encodes media nor spends quota.
/// Durations are normalized to the measured microsecond precision once, so
/// adjacent ranges share exact boundaries and no tail is silently discarded.
class ClipSplitPlan {
  ClipSplitPlan._({
    required this.sourceDurationSeconds,
    required Set<SocialPlatform> platforms,
    required this.mode,
    required this.tikTokDirectPost,
    required this.tikTokMaxDurationSeconds,
    required List<ClipSplitChannelPlan> channelPlans,
    required List<ClipSplitPart> groupedParts,
  })  : platforms = Set.unmodifiable(platforms),
        channelPlans = List.unmodifiable(channelPlans),
        groupedParts = List.unmodifiable(groupedParts);

  factory ClipSplitPlan.create({
    required double sourceDurationSeconds,
    required Set<SocialPlatform> platforms,
    ClipSplitMode mode = ClipSplitMode.affectedChannels,
    bool tikTokDirectPost = false,
    int? tikTokMaxDurationSeconds,
    Map<SocialPlatform, double> firstBoundaries = const {},
  }) {
    if (!sourceDurationSeconds.isFinite ||
        sourceDurationSeconds <= 0 ||
        sourceDurationSeconds * _ticksPerSecond > 9007199254740991) {
      throw const ClipSplitPlanException(ClipSplitPlanProblem.invalidDuration);
    }
    final durationTicks = (sourceDurationSeconds * _ticksPerSecond).round();
    if (durationTicks <= 0) {
      throw const ClipSplitPlanException(ClipSplitPlanProblem.invalidDuration);
    }
    if (platforms.isEmpty) {
      throw const ClipSplitPlanException(ClipSplitPlanProblem.noPlatforms);
    }
    if (tikTokDirectPost &&
        platforms.contains(SocialPlatform.tiktok) &&
        (tikTokMaxDurationSeconds == null || tikTokMaxDurationSeconds <= 0)) {
      throw const ClipSplitPlanException(
          ClipSplitPlanProblem.tikTokAccountRequired);
    }

    final rules = <SocialPlatform, PlatformVideoDurationRule>{};
    for (final platform in SocialPlatform.values.where(platforms.contains)) {
      final rule = platformVideoDurationRule(platform,
          tikTokMaxDurationSeconds:
              tikTokDirectPost ? tikTokMaxDurationSeconds : null);
      if (rule == null) {
        throw const ClipSplitPlanException(
            ClipSplitPlanProblem.unsupportedPlatform);
      }
      if (durationTicks < (rule.minimumSeconds ?? 0) * _ticksPerSecond) {
        throw const ClipSplitPlanException(ClipSplitPlanProblem.tooShort);
      }
      rules[platform] = rule;
    }

    final sharedMinimum = rules.values
        .map((rule) => (rule.minimumSeconds ?? 0) * _ticksPerSecond)
        .reduce(math.max);
    final sharedMaximum = rules.values
        .map((rule) => rule.maximumSeconds * _ticksPerSecond)
        .reduce(math.min);
    if (mode == ClipSplitMode.sameParts && sharedMinimum > sharedMaximum) {
      throw const ClipSplitPlanException(ClipSplitPlanProblem.noSharedRange);
    }

    int? sharedFirst;
    if (mode == ClipSplitMode.sameParts) {
      for (final entry in firstBoundaries.entries
          .where((entry) => platforms.contains(entry.key))) {
        if (!entry.value.isFinite || entry.value <= 0) {
          throw const ClipSplitPlanException(
              ClipSplitPlanProblem.invalidBoundary);
        }
        final candidate = (entry.value * _ticksPerSecond).round();
        if (sharedFirst != null && sharedFirst != candidate) {
          throw const ClipSplitPlanException(
              ClipSplitPlanProblem.invalidBoundary);
        }
        sharedFirst = candidate;
      }
    }

    final channels = <ClipSplitChannelPlan>[];
    for (final entry in rules.entries) {
      final minimumTicks = mode == ClipSplitMode.sameParts
          ? sharedMinimum
          : (entry.value.minimumSeconds ?? 0) * _ticksPerSecond;
      final maximumTicks = mode == ClipSplitMode.sameParts
          ? sharedMaximum
          : entry.value.maximumSeconds * _ticksPerSecond;
      final count = (durationTicks + maximumTicks - 1) ~/ maximumTicks;
      if (count > maxClipSplitParts) {
        throw const ClipSplitPlanException(ClipSplitPlanProblem.tooManyParts);
      }
      final positiveMinimumTicks = math.max(1, minimumTicks);
      if (durationTicks < count * positiveMinimumTicks) {
        throw const ClipSplitPlanException(ClipSplitPlanProblem.noSharedRange);
      }
      final lower = count > 1
          ? math.max(
              positiveMinimumTicks, durationTicks - (count - 1) * maximumTicks)
          : null;
      final upper = count > 1
          ? math.min(
              maximumTicks, durationTicks - (count - 1) * positiveMinimumTicks)
          : null;
      final requestedFirst = firstBoundaries[entry.key];
      if (requestedFirst != null &&
          (!requestedFirst.isFinite || requestedFirst <= 0)) {
        throw const ClipSplitPlanException(
            ClipSplitPlanProblem.invalidBoundary);
      }
      final first = count == 1
          ? durationTicks
          : sharedFirst ??
              (requestedFirst == null
                  ? (durationTicks / count).round()
                  : (requestedFirst * _ticksPerSecond).round());
      if (count > 1 && (first < lower! || first > upper!)) {
        throw const ClipSplitPlanException(
            ClipSplitPlanProblem.invalidBoundary);
      }
      final boundaries = [0, first];
      for (var index = 1; index < count; index++) {
        boundaries.add(
            first + ((durationTicks - first) * index / (count - 1)).round());
      }
      channels.add(ClipSplitChannelPlan._(
        platform: entry.key,
        minimumDurationSeconds: minimumTicks / _ticksPerSecond,
        maximumDurationSeconds: maximumTicks / _ticksPerSecond,
        minimumFirstBoundarySeconds:
            lower == null ? null : lower / _ticksPerSecond,
        maximumFirstBoundarySeconds:
            upper == null ? null : upper / _ticksPerSecond,
        segments: [
          for (var index = 0; index < count; index++)
            ClipSplitSegment(
              startSeconds: boundaries[index] / _ticksPerSecond,
              endSeconds: boundaries[index + 1] / _ticksPerSecond,
            ),
        ],
      ));
    }

    final grouped = <(int, int), _GroupedPart>{};
    for (final channel in channels) {
      for (final segment in channel.segments) {
        final startTicks = (segment.startSeconds * _ticksPerSecond).round();
        final endTicks = (segment.endSeconds * _ticksPerSecond).round();
        final part = grouped.putIfAbsent(
            (startTicks, endTicks), () => _GroupedPart(startTicks, endTicks));
        part.platforms.add(channel.platform);
        part.minimum = math.max(part.minimum, channel.minimumDurationSeconds);
        part.maximum = math.min(part.maximum, channel.maximumDurationSeconds);
        if (grouped.length > maxClipSplitParts) {
          throw const ClipSplitPlanException(ClipSplitPlanProblem.tooManyParts);
        }
      }
    }
    final jobs = grouped.values.toList()
      ..sort((a, b) {
        final start = a.startTicks.compareTo(b.startTicks);
        return start == 0 ? a.endTicks.compareTo(b.endTicks) : start;
      });
    return ClipSplitPlan._(
      sourceDurationSeconds: durationTicks / _ticksPerSecond,
      platforms: platforms,
      mode: mode,
      tikTokDirectPost: tikTokDirectPost,
      tikTokMaxDurationSeconds: tikTokMaxDurationSeconds,
      channelPlans: channels,
      groupedParts: [
        for (var index = 0; index < jobs.length; index++)
          ClipSplitPart._(
            index: index,
            startSeconds: jobs[index].startTicks / _ticksPerSecond,
            endSeconds: jobs[index].endTicks / _ticksPerSecond,
            platforms: jobs[index].platforms,
            minDurationSeconds: jobs[index].minimum,
            maxDurationSeconds: jobs[index].maximum,
            isOriginal: jobs[index].startTicks == 0 &&
                jobs[index].endTicks == durationTicks,
          ),
      ],
    );
  }

  final double sourceDurationSeconds;
  final Set<SocialPlatform> platforms;
  final ClipSplitMode mode;
  final bool tikTokDirectPost;
  final int? tikTokMaxDurationSeconds;
  final List<ClipSplitChannelPlan> channelPlans;
  final List<ClipSplitPart> groupedParts;

  int get totalPostUnits =>
      channelPlans.fold(0, (total, channel) => total + channel.segments.length);
  bool get requiresSplitting =>
      channelPlans.any((channel) => channel.segments.length > 1);

  ClipSplitChannelPlan channelPlanFor(SocialPlatform platform) =>
      channelPlans.firstWhere((channel) => channel.platform == platform);
}

class _GroupedPart {
  _GroupedPart(this.startTicks, this.endTicks);
  final int startTicks;
  final int endTicks;
  final platforms = <SocialPlatform>{};
  double minimum = 0;
  double maximum = double.infinity;
}
