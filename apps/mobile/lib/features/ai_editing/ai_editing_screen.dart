import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/app_config.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../billing/paywall_screen.dart';
import '../shared/postdee_status_sheet.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/video_picker_service.dart';
import 'ai_edit_audio_extractor.dart';
import 'ai_edit_local_recipe.dart';
import 'ai_edit_media_strategy.dart';
import 'ai_edit_safety_flags.dart';
import 'ai_edit_silence_verifier.dart';
import 'ai_edit_timeline_mapper.dart';
import 'ai_subtitle_frame_preview.dart';
import 'ai_edit_visual_proxy_extractor.dart';
import 'beat_music_picker.dart';
import 'edit_styles.dart';
import 'review_video_timeline.dart';
import 'speech_reduction_review.dart';
import 'style_options.dart';
import 'subtitle_burn_video_processor.dart';
import 'subtitle_timeline_alignment.dart';
import 'subtitle_studio/subtitle_draft_store.dart';
import 'subtitle_studio/subtitle_project.dart';
import 'subtitle_studio/subtitle_project_identity.dart';
import 'subtitle_studio/subtitle_project_mapper.dart';
import 'subtitle_studio/subtitle_preview_overlay.dart';
import 'subtitle_studio/subtitle_studio_screen.dart';

typedef EditorVideoPicker = Future<PickedVideoFile?> Function();
typedef EditorUploadCreator = Future<UploadResult> Function(
  CreateUploadRequest request,
);
typedef EditorVideoUploader = Future<void> Function(
  UploadResult upload,
  File videoFile,
);
typedef AiEditPreparer = Future<AiEditPrepareResult> Function(
  AiEditPrepareRequest request,
);
typedef AiEditPlanner = Future<AiEditPlanResult> Function(
  AiEditPlanRequest request,
);
typedef AiEditAudioExtraction = Future<AiEditAudioArtifact> Function(
    File source);
typedef AiEditAudioChunksExtraction = Future<AiEditAudioChunksArtifact>
    Function(
  File source, {
  double? knownDurationSeconds,
});
typedef AiEditAudioCleanup = Future<void> Function(String audioS3Key);
typedef AiEditVisualProxyExtraction = Future<AiEditVisualProxyArtifact>
    Function(File source);
typedef AiEditVisualProxyCleanup = Future<void> Function(
  String visualProxyS3Key,
);
typedef AiVideoRenderer = Future<BurnedSubtitleResult> Function(
  BurnSubtitleRequest request,
);
typedef AiEditSilenceVerification = Future<AiEditSilenceVerificationResult>
    Function({
  required File sourceFile,
  required double sourceDurationSeconds,
  required List<SilenceCutRange> transcriptCandidates,
  required List<SilenceCutRange> protectedSpeechRanges,
});
typedef EditorSubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef AiEditQuotaLoader = Future<AiEditQuota> Function();
typedef ReviewVideoControllerFactory = VideoPlayerController Function(
  File file,
);

List<ClipTranscriptSegment> _trustedPlanningSegmentsForRecipe(
  AiEditRecipeResult recipe,
) {
  final subtitleSegments = recipe.subtitles.segments;
  if (subtitleSegments.isNotEmpty) {
    return subtitleSegments;
  }

  final planModel = recipe.plan.model.trim().toLowerCase();
  // A non-placeholder plan is the current API signal that /prepare passed
  // the server timing guard even when automatic subtitles were not requested.
  final hasServerValidatedPlan = planModel.isNotEmpty && planModel != 'none';
  return hasServerValidatedPlan
      ? recipe.transcript.segments
      : const <ClipTranscriptSegment>[];
}

/// Keeps a stalled entitlement request from locking the AI editor forever.
const aiEditEntitlementCheckTimeout = Duration(seconds: 30);

typedef SubtitleStudioLauncher = Future<SubtitleProject?> Function(
  BuildContext context,
  File sourceFile,
  SubtitleProject initialProject,
  SubtitleDraftStore draftStore,
);

List<SubtitleWordTiming> subtitleWordsForRender(SubtitleCue cue) {
  if (cue.timingMode != SubtitleTimingMode.word) {
    return const <SubtitleWordTiming>[];
  }
  return [
    for (final word in cue.words)
      SubtitleWordTiming(
        text: word.text,
        start: word.sourceStartMs / 1000,
        end: word.sourceEndMs / 1000,
      ),
  ];
}

enum _AiDurationMode { unselected, seconds30, seconds60, custom }

enum _AiEditingStage { setup, review }

enum _SpeechReductionSelectionMode { ai, manual }

class _PreparedRecipeRenderResult {
  const _PreparedRecipeRenderResult({
    required this.video,
    required this.appliedSpeechOccurrenceIds,
    required this.appliedCutRanges,
    required this.boundaryEvidenceWarning,
  });

  final BurnedSubtitleResult video;
  final Set<String> appliedSpeechOccurrenceIds;
  final List<SilenceCutRange> appliedCutRanges;
  final String? boundaryEvidenceWarning;
}

const _maxAiEditSourceDurationSeconds = 600;
const _maxAiShortenedDurationSeconds = 180;
const _originalDurationSliderStop = 181.0;

String _subtitleHexColor(Color color) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${argb.substring(2).toUpperCase()}';
}

enum _AiCapabilityGroup { pace, look, sales }

const _capabilityGroupDisplayOrder = <_AiCapabilityGroup>[
  _AiCapabilityGroup.sales,
  _AiCapabilityGroup.pace,
  _AiCapabilityGroup.look,
];

enum _BeatMusicSource { auto, library, device, original }

enum _BeatCutIntensity { smooth, balanced, energetic }

const _requiredMusicPublishingPlatforms = <String>{
  'TikTok',
  'YouTube Shorts',
  'Instagram Reels',
  'Facebook Video',
  'Shopee Video',
  'Lazada Video',
};

bool _isCatalogTrackUsable(PostDeeMusicTrack track) {
  final supported = track.supportedPlatforms.toSet();
  return track.rightsVerified &&
      supported.containsAll(_requiredMusicPublishingPlatforms);
}

class _AiCapabilityDefinition {
  const _AiCapabilityDefinition({
    required this.id,
    required this.group,
    required this.icon,
    required this.title,
    required this.description,
    this.hasAdvancedSettings = false,
  });

  final String id;
  final _AiCapabilityGroup group;
  final IconData icon;
  final String title;
  final String description;
  final bool hasAdvancedSettings;
}

const _capabilityDefinitions = <_AiCapabilityDefinition>[
  _AiCapabilityDefinition(
    id: 'silence',
    group: _AiCapabilityGroup.pace,
    icon: Icons.content_cut,
    title: 'ตัดช่วงเงียบ',
    description: 'ตัดช่องว่างระหว่างช่วงพูด ให้คลิปกระชับขึ้น',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'filler',
    group: _AiCapabilityGroup.pace,
    icon: Icons.voice_over_off_outlined,
    title: 'จัดการคำพูดซ้ำ',
    description:
        'AI ตรวจหาคำหรือวลีที่พูดซ้ำ แล้วเลือกได้ว่าจะให้ AI ตัดหรือเลือกเอง',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'hook',
    group: _AiCapabilityGroup.pace,
    icon: Icons.rocket_launch_outlined,
    title: 'ไฮไลต์ 3 วิแรก',
    description: 'ดึงช่วงที่น่าสนใจที่สุดมาขึ้นต้น กันคนปัดผ่าน',
  ),
  _AiCapabilityDefinition(
    id: 'beatsync',
    group: _AiCapabilityGroup.pace,
    icon: Icons.music_note,
    title: 'ตัดจังหวะตามบีตเพลง',
    description: 'สลับภาพ/ตัดให้ตรงจังหวะเพลง คลิปดูมีจังหวะ',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'reframe',
    group: _AiCapabilityGroup.look,
    icon: Icons.aspect_ratio,
    title: 'ปรับเป็น 9:16 อัตโนมัติ',
    description: 'ถ่ายแนวนอนก็ครอปเป็นแนวตั้ง ตามหน้า/สินค้าให้อยู่กลางเฟรม',
  ),
  _AiCapabilityDefinition(
    id: 'zoom',
    group: _AiCapabilityGroup.look,
    icon: Icons.zoom_in,
    title: 'ซูมเข้าตอนสำคัญ',
    description: 'ซูมอัตโนมัติตอนพูดชื่อสินค้า/ราคา ให้ดูมือโปร',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'color',
    group: _AiCapabilityGroup.look,
    icon: Icons.palette_outlined,
    title: 'ปรับสี/แสงอัตโนมัติ',
    description: 'ปรับแสงและสีให้ภาพสว่างสวยดูแพงขึ้น',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'audio',
    group: _AiCapabilityGroup.look,
    icon: Icons.hearing,
    title: 'ปรับเสียงให้ชัด',
    description: 'ปรับความดังให้เท่ากัน + ลดเสียงรบกวนรอบข้าง',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'sfx',
    group: _AiCapabilityGroup.look,
    icon: Icons.graphic_eq_rounded,
    title: 'AI ใส่เอฟเฟกต์เสียงให้',
    description: 'AI เลือกเสียงให้เข้ากับเหตุการณ์และจังหวะของคลิป',
  ),
  _AiCapabilityDefinition(
    id: 'subtitle',
    group: _AiCapabilityGroup.sales,
    icon: Icons.closed_caption_outlined,
    title: 'ใส่ซับอัตโนมัติ',
    description: 'ถอดเสียงไทยเป็นซับ อ่านง่าย คนดูอยู่จนจบ',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'translate',
    group: _AiCapabilityGroup.sales,
    icon: Icons.translate,
    title: 'แปลซับ 2 ภาษา',
    description: 'แปลซับเป็นอังกฤษ/จีน ขายลูกค้าต่างชาติ',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'pricetag',
    group: _AiCapabilityGroup.sales,
    icon: Icons.local_offer_outlined,
    title: 'ป้ายราคาอัตโนมัติ',
    description: 'เด้งป้ายราคา/โปรขึ้นตอนพูดถึง',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'cta',
    group: _AiCapabilityGroup.sales,
    icon: Icons.ads_click,
    title: 'การ์ดปิดท้าย (CTA)',
    description: 'เฟรมปิดท้าย "กดตะกร้า/ทักแชท" กระตุ้นให้ซื้อ',
    hasAdvancedSettings: true,
  ),
  _AiCapabilityDefinition(
    id: 'watermark',
    group: _AiCapabilityGroup.sales,
    icon: Icons.branding_watermark_outlined,
    title: 'ลายน้ำร้าน',
    description: 'ติดชื่อร้านกันก๊อป สร้างแบรนด์ให้จำได้',
  ),
];

const _deferredCapabilityIds = <String>{
  'translate',
  'pricetag',
  'cta',
  'watermark',
};

const _retiredSetupCapabilityIds = <String>{
  'color',
  'audio',
};

class _AiPreset {
  _AiPreset({
    required this.name,
    required this.capabilities,
    required this.speechReductionSelectionMode,
    required this.subtitleStyle,
    required this.subtitleColor,
    required this.subtitleOutlineColor,
    required this.subtitleWords,
    required this.subtitlePosition,
    required this.subtitleNormalizedX,
    required this.subtitleNormalizedY,
    required this.ctaDesign,
    required this.musicGenre,
    required this.musicVolume,
    required this.musicSource,
    required this.musicTrackId,
    required this.beatIntensity,
    required this.duckMusicDuringSpeech,
    required this.silencePreset,
    required this.toneFilter,
    required this.zoomLevel,
    required this.clipSpeed,
  });

  final String name;
  final Map<String, bool> capabilities;
  final _SpeechReductionSelectionMode speechReductionSelectionMode;
  final String subtitleStyle;
  final Color subtitleColor;
  final Color subtitleOutlineColor;
  final String subtitleWords;
  final String subtitlePosition;
  final double subtitleNormalizedX;
  final double subtitleNormalizedY;
  final String ctaDesign;
  final String musicGenre;
  final double musicVolume;
  final _BeatMusicSource musicSource;
  final String? musicTrackId;
  final _BeatCutIntensity beatIntensity;
  final bool duckMusicDuringSpeech;
  final String silencePreset;
  final String toneFilter;
  final String zoomLevel;
  final double clipSpeed;
}

class _AiSetupSnapshot {
  const _AiSetupSnapshot({
    required this.durationMode,
    required this.customDurationSeconds,
    required this.capabilities,
    required this.speechReductionSelectionMode,
    required this.subtitleStyle,
    required this.subtitleColor,
    required this.subtitleOutlineColor,
    required this.subtitleWords,
    required this.subtitlePosition,
    required this.subtitleNormalizedX,
    required this.subtitleNormalizedY,
    required this.ctaText,
    required this.ctaDesign,
    required this.priceNowText,
    required this.priceBeforeText,
    required this.musicGenre,
    required this.musicVolume,
    required this.musicSource,
    required this.pickedMusic,
    required this.musicTrackId,
    required this.beatIntensity,
    required this.duckMusicDuringSpeech,
    required this.confirmedMusicRights,
    required this.silencePreset,
    required this.toneFilter,
    required this.toneStrength,
    required this.zoomLevel,
    required this.clipSpeed,
    required this.translationLanguage,
  });

  final _AiDurationMode durationMode;
  final int customDurationSeconds;
  final Map<String, bool> capabilities;
  final _SpeechReductionSelectionMode speechReductionSelectionMode;
  final String subtitleStyle;
  final Color subtitleColor;
  final Color subtitleOutlineColor;
  final String subtitleWords;
  final String subtitlePosition;
  final double subtitleNormalizedX;
  final double subtitleNormalizedY;
  final String ctaText;
  final String ctaDesign;
  final String priceNowText;
  final String priceBeforeText;
  final String musicGenre;
  final double musicVolume;
  final _BeatMusicSource musicSource;
  final PickedBeatMusicFile? pickedMusic;
  final String? musicTrackId;
  final _BeatCutIntensity beatIntensity;
  final bool duckMusicDuringSpeech;
  final bool confirmedMusicRights;
  final String silencePreset;
  final String toneFilter;
  final double toneStrength;
  final String zoomLevel;
  final double clipSpeed;
  final String translationLanguage;
}

/// Setup screen that mirrors the AI-editing flow in PostDee.dc.html. A clip is
/// selected first, the user chooses duration and AI helpers, then the existing
/// upload/editor pipeline starts from the sticky action button.
class AiEditingScreen extends StatefulWidget {
  const AiEditingScreen({
    super.key,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.prepareEdit,
    this.planEdit,
    this.extractAudio,
    this.extractAudioChunks,
    this.cleanupAiEditAudio,
    this.extractVisualProxy,
    this.cleanupAiEditVisualProxy,
    this.loadSubscription,
    this.loadAiEditQuota,
    this.initialTargetDurationSeconds = 30,
    this.burnVideo,
    this.verifySilence,
    this.safetyFlags = const AiEditSafetyFlags.fromEnvironment(),
    this.pickMusic,
    this.musicCatalog = const [],
    this.enableExperimentalBeatSync = AppConfig.enableExperimentalBeatSync,
    this.enableExperimentalAiHook = AppConfig.enableExperimentalAiHook,
    this.showRetiredCapabilitiesForTesting = false,
    this.reviewVideoControllerFactory,
    this.subtitleFrameControllerFactory,
    this.subtitleStudioLauncher,
    this.subtitleDraftStore,
    this.onBack,
  });

  final EditorVideoPicker? pickVideo;
  final EditorUploadCreator? createUpload;
  final EditorVideoUploader? uploadVideoFile;
  final AiEditPreparer? prepareEdit;
  final AiEditPlanner? planEdit;
  final AiEditAudioExtraction? extractAudio;
  final AiEditAudioChunksExtraction? extractAudioChunks;
  final AiEditAudioCleanup? cleanupAiEditAudio;
  final AiEditVisualProxyExtraction? extractVisualProxy;
  final AiEditVisualProxyCleanup? cleanupAiEditVisualProxy;
  final EditorSubscriptionLoader? loadSubscription;
  final AiEditQuotaLoader? loadAiEditQuota;
  final int? initialTargetDurationSeconds;
  final AiVideoRenderer? burnVideo;
  final AiEditSilenceVerification? verifySilence;
  final AiEditSafetyFlags safetyFlags;
  final BeatMusicPicker? pickMusic;
  final List<PostDeeMusicTrack> musicCatalog;
  final bool enableExperimentalBeatSync;
  final bool enableExperimentalAiHook;

  /// Keeps retired setup controls reachable only for legacy widget tests.
  @visibleForTesting
  final bool showRetiredCapabilitiesForTesting;
  final ReviewVideoControllerFactory? reviewVideoControllerFactory;
  final AiSubtitleFrameControllerFactory? subtitleFrameControllerFactory;
  final SubtitleStudioLauncher? subtitleStudioLauncher;
  final SubtitleDraftStore? subtitleDraftStore;
  final VoidCallback? onBack;

  @override
  State<AiEditingScreen> createState() => _AiEditingScreenState();
}

class _AiEditingScreenState extends State<AiEditingScreen> {
  final _apiClient = PostDeeApiClient();
  final _customDurationController = TextEditingController(text: '45');
  final _ctaController = TextEditingController(text: 'กดตะกร้าสีส้มเลย!');
  final _priceNowController = TextEditingController(text: '199');
  final _priceBeforeController = TextEditingController(text: '359');

  PickedVideoFile? _selectedVideo;
  double? _selectedVideoDurationSeconds;
  PickedVideoFile? _activeSourceVideo;
  double? _activeSourceDurationSeconds;
  AiEditPrepareResult? _preparedEdit;
  AiEditRecipeResult? _activeRecipe;
  SubtitleProject? _subtitleProject;
  SubtitleDraftStore? _resolvedSubtitleDraftStore;
  BurnedSubtitleResult? _renderedResult;
  _AiSetupSnapshot? _acceptedSetup;
  final Map<String, AiEditPrepareResult> _preparedEditsBySignature = {};
  final Map<String, AiEditPrepareResult> _preparedEditsByAnalysisSignature = {};
  final Map<String, BurnedSubtitleResult> _renderResultsBySignature = {};
  AiEditVisualProxyArtifact? _cachedVisualProxyArtifact;
  String? _cachedVisualProxySourceKey;
  _AiEditingStage _stage = _AiEditingStage.setup;
  final Map<String, bool> _reviewCapabilities = {};
  final Map<String, bool> _appliedReviewCapabilities = {};
  final Set<String> _reviewRemovedSpeechOccurrenceIds = {};
  final Set<String> _appliedRemovedSpeechOccurrenceIds = {};
  final Map<String, Duration> _reviewVideoDurations = {};
  final AiSubtitleFramePreviewSession _subtitleFramePreviewSession =
      AiSubtitleFramePreviewSession();
  ReviewVideoSource _reviewVideoSource = ReviewVideoSource.ai;
  int _reviewResultRevision = 0;
  String? _expandedAdvancedCapabilityId;
  String? _boundaryEvidenceWarning;
  AiEditSilenceVerificationResult _acceptedSilenceVerification =
      const AiEditSilenceVerificationResult(
    cutRanges: [],
    probeSucceeded: true,
  );
  final Map<String, AiEditSilenceVerificationResult>
      _silenceVerificationBySignature = {};
  bool _silenceRetryInProgress = false;
  bool _processing = false;
  bool _updatingReviewPreview = false;
  bool _reviewPreviewLoading = false;
  bool _isPickingVideo = false;
  bool _isLoadingAiEditQuota = false;
  bool _aiEditQuotaLoadFailed = false;
  bool _aiEditSubscriptionLoadFailed = false;
  AiEditQuota? _aiEditQuota;
  SubscriptionStatusResult? _aiEditSubscription;
  String _processingTitle = 'AI กำลังวิเคราะห์คลิป...';
  double? _renderProgress;
  RenderCancellationToken? _activeRenderCancellation;
  bool _renderCancelRequested = false;
  _AiDurationMode _durationMode = _AiDurationMode.unselected;
  int _customDurationSeconds = 45;
  _SpeechReductionSelectionMode _speechReductionSelectionMode =
      _SpeechReductionSelectionMode.ai;

  final Map<String, bool> _capabilities = {
    'subtitle': false,
    'silence': false,
    'filler': false,
    'hook': false,
    'beatsync': false,
    'zoom': false,
    'reframe': false,
    'color': false,
    'sfx': false,
    'audio': false,
    'translate': false,
    'pricetag': false,
    'cta': false,
    'watermark': false,
  };

  String _subtitleStyle = 'large';
  Color _subtitleColor = Colors.white;
  Color _subtitleOutlineColor = Colors.black;
  String _subtitleWords = 'few';
  String _subtitlePosition = 'bottom';
  double _subtitleNormalizedX = 0.5;
  double _subtitleNormalizedY = 0.88;
  String _ctaDesign = 'pop';
  String _musicGenre = 'fun';
  double _musicVolume = 0.25;
  _BeatMusicSource _musicSource = _BeatMusicSource.original;
  PickedBeatMusicFile? _pickedMusic;
  String? _selectedMusicTrackId;
  _BeatCutIntensity _beatIntensity = _BeatCutIntensity.balanced;
  bool _duckMusicDuringSpeech = true;
  bool _confirmedMusicRights = false;
  String _silencePreset = 'balanced';
  String _toneFilter = 'bright';
  double _toneStrength = 0.6;
  String _zoomLevel = 'medium';
  double _clipSpeed = 1;
  String _translationLanguage = 'en';
  final List<_AiPreset> _presets = [];

  @override
  void initState() {
    super.initState();
    final initialTarget = widget.initialTargetDurationSeconds;
    if (initialTarget != null && initialTarget > 0) {
      if (initialTarget == 30) {
        _durationMode = _AiDurationMode.seconds30;
      } else if (initialTarget == 60) {
        _durationMode = _AiDurationMode.seconds60;
      } else {
        _durationMode = _AiDurationMode.custom;
        _customDurationSeconds = initialTarget.clamp(1, 180);
        _customDurationController.text = _customDurationSeconds.toString();
      }
    }
    unawaited(_loadAiEditQuota());
  }

  @override
  void dispose() {
    final activeRenderCancellation = _activeRenderCancellation;
    if (activeRenderCancellation != null) {
      unawaited(activeRenderCancellation.cancel());
    }
    final cachedVisualProxy = _cachedVisualProxyArtifact;
    _cachedVisualProxyArtifact = null;
    _cachedVisualProxySourceKey = null;
    if (cachedVisualProxy != null) {
      unawaited(_cleanupLocalVisualProxyBestEffort(cachedVisualProxy));
    }
    _customDurationController.dispose();
    _ctaController.dispose();
    _priceNowController.dispose();
    _priceBeforeController.dispose();
    super.dispose();
  }

  String _readFileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final fileName = parts.isEmpty ? path : parts.last;
    return fileName.trim();
  }

  Future<void> _loadAiEditQuota() async {
    if (_isLoadingAiEditQuota) return;
    setState(() {
      _isLoadingAiEditQuota = true;
      _aiEditQuotaLoadFailed = false;
      _aiEditSubscriptionLoadFailed = false;
    });

    Future<AiEditQuota?> loadQuota() async {
      try {
        final loader = widget.loadAiEditQuota ?? _apiClient.fetchAiEditQuota;
        return await loader();
      } catch (_) {
        return null;
      }
    }

    Future<SubscriptionStatusResult?> loadSubscription() async {
      try {
        final loader =
            widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
        return await loader();
      } catch (_) {
        return null;
      }
    }

    final quotaFuture = loadQuota();
    final subscriptionFuture = loadSubscription();
    final quota = await quotaFuture;
    final subscription = await subscriptionFuture;

    if (!mounted) return;
    setState(() {
      if (quota != null) {
        _aiEditQuota = quota;
      }
      _aiEditSubscription = subscription;
      _isLoadingAiEditQuota = false;
      _aiEditQuotaLoadFailed = quota == null;
      _aiEditSubscriptionLoadFailed = subscription == null;
    });
  }

  Future<void> _pickVideo() async {
    if (_isPickingVideo || _processing || _updatingReviewPreview) return;
    final picker = widget.pickVideo ?? GalleryVideoPicker().pickVideo;
    setState(() => _isPickingVideo = true);

    try {
      final picked = await picker();
      if (picked == null || !mounted) {
        return;
      }

      if (!File(picked.path).existsSync()) {
        throw const ApiException('ไม่พบไฟล์วิดีโอในเครื่อง');
      }

      final pickedDuration = picked.durationSeconds;
      if (pickedDuration != null &&
          pickedDuration.isFinite &&
          pickedDuration > _maxAiEditSourceDurationSeconds) {
        throw const ApiException('รองรับคลิปต้นฉบับยาวไม่เกิน 10 นาที');
      }

      await _releaseCachedVisualProxy();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedVideo = picked;
        _selectedVideoDurationSeconds = picked.durationSeconds;
        final sliderMaximum = _durationSliderMaximum;
        if (sliderMaximum == null) {
          _durationMode = _AiDurationMode.unselected;
        } else {
          final initialTarget = widget.initialTargetDurationSeconds;
          final target = _normalizeTargetDuration(
            initialTarget ?? _sourceDurationMaximumSeconds!,
          );
          _customDurationSeconds = target;
          _customDurationController.text = target.toString();
          _durationMode = _AiDurationMode.custom;
        }
        // This is only the pending source. Keep the accepted review/export
        // state intact until this source has rendered successfully.
        _stage = _AiEditingStage.setup;
      });
    } on ApiException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showError('เลือกวิดีโอไม่สำเร็จ');
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingVideo = false);
      }
    }
  }

  List<PostDeeMusicTrack> get _licensedMusicCatalog =>
      widget.musicCatalog.where(_isCatalogTrackUsable).toList(growable: false);

  bool _isCapabilityAvailable(String id) => switch (id) {
        'beatsync' => widget.enableExperimentalBeatSync,
        'hook' => widget.enableExperimentalAiHook,
        'silence' => widget.safetyFlags.verifiedSilenceEnabled,
        'subtitle' || 'filler' => true,
        'color' => widget.showRetiredCapabilitiesForTesting,
        _ => false,
      };

  bool _isCapabilityEnabled(String id) =>
      _isCapabilityAvailable(id) && (_capabilities[id] ?? false);

  Map<String, bool> get _effectiveCapabilities => {
        for (final entry in _capabilities.entries)
          entry.key: _isCapabilityAvailable(entry.key) && entry.value,
      };

  bool get _beatMusicSelectionComplete {
    if (!_isCapabilityEnabled('beatsync')) {
      return true;
    }

    return switch (_musicSource) {
      _BeatMusicSource.original => true,
      _BeatMusicSource.device => _pickedMusic != null && _confirmedMusicRights,
      _BeatMusicSource.library => _licensedMusicCatalog.any(
          (track) => track.id == _selectedMusicTrackId,
        ),
      _BeatMusicSource.auto => _licensedMusicCatalog.isNotEmpty,
    };
  }

  void _collapseAdvancedIfUnavailable() {
    final expandedId = _expandedAdvancedCapabilityId;
    if (expandedId == null || !_isCapabilityEnabled(expandedId)) {
      _expandedAdvancedCapabilityId = null;
    }
  }

  Future<void> _pickBeatMusic() async {
    final picker = widget.pickMusic ?? const DeviceBeatMusicPicker().call;
    try {
      final picked = await picker();
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _musicSource = _BeatMusicSource.device;
        _pickedMusic = picked;
        _confirmedMusicRights = false;
      });
    } on BeatMusicPickerException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showError('เลือกไฟล์เพลงไม่สำเร็จ');
      }
    }
  }

  Future<void> _processVideo() async {
    final picked = _selectedVideo;
    if (picked == null ||
        !_hasSelectedDuration ||
        _processing ||
        _updatingReviewPreview) {
      return;
    }

    // Lock synchronously before the first await. Without this, a second tap
    // can enter while the Pro entitlement request is still pending and start
    // a duplicate upload/render pipeline.
    setState(() {
      _processing = true;
      _processingTitle = 'กำลังตรวจสอบแพ็กเกจ...';
      _renderProgress = null;
      _renderCancelRequested = false;
    });

    final shouldCheckSubscription = widget.loadSubscription != null ||
        (widget.createUpload == null &&
            widget.uploadVideoFile == null &&
            widget.prepareEdit == null);
    if (shouldCheckSubscription) {
      try {
        final loadSubscription =
            widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
        final subscription = await loadSubscription().timeout(
          aiEditEntitlementCheckTimeout,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _aiEditSubscription = subscription;
          _aiEditSubscriptionLoadFailed = false;
        });
        if (!subscription.isPro) {
          throw const ApiException(
            'Pro plan is required for AI editing',
            statusCode: 402,
          );
        }
      } on ApiException catch (error) {
        if (mounted) {
          setState(() {
            _processing = false;
            _renderProgress = null;
            _renderCancelRequested = false;
          });
          _showError(_friendlyAiError(error));
        }
        return;
      } on TimeoutException {
        if (mounted) {
          setState(() {
            _processing = false;
            _renderProgress = null;
            _renderCancelRequested = false;
          });
          _showError('ตรวจสอบแพ็กเกจนานเกินไป ลองใหม่อีกครั้ง');
        }
        return;
      } catch (_) {
        if (mounted) {
          setState(() {
            _processing = false;
            _renderProgress = null;
            _renderCancelRequested = false;
          });
          _showError('ตรวจสอบแพ็กเกจไม่สำเร็จ ลองใหม่อีกครั้ง');
        }
        return;
      }
    }

    final file = File(picked.path);
    setState(() {
      _processingTitle = 'AI กำลังวิเคราะห์คลิป...';
      _renderProgress = null;
      _renderCancelRequested = false;
    });

    try {
      if (!file.existsSync()) {
        throw const ApiException('ไม่พบไฟล์วิดีโอในเครื่อง');
      }

      final prepareSignature = _buildPrepareSignature(picked, file);
      final effectiveCapabilities = Map<String, bool>.from(
        _effectiveCapabilities,
      );
      final analysisMode = selectAiEditAnalysisMode(
        effectiveCapabilities,
        usesOriginalDuration: _isUsingOriginalDuration,
      );
      AiEditPrepareResult? prepared;
      AiEditRecipeResult? localRecipe;
      if (analysisMode == AiEditAnalysisMode.localRenderOnly) {
        final localDuration =
            _selectedVideoDurationSeconds ?? picked.durationSeconds;
        if (localDuration == null ||
            !localDuration.isFinite ||
            localDuration <= 0) {
          throw const SubtitleBurnException(
            'อ่านความยาววิดีโอต้นฉบับไม่สำเร็จ',
          );
        }
        if (mounted) {
          setState(
            () => _processingTitle = 'กำลังปรับสีและแสงบนเครื่อง...',
          );
        }
        localRecipe = buildLocalColorAiEditRecipe(
          durationSeconds: localDuration,
        );
      } else {
        final analysisSignature = _buildAnalysisSignature(picked, file);
        prepared = _withSelectedSubtitleDensity(
          _preparedEditsBySignature[prepareSignature],
        );
        if (prepared == null) {
          final previousAnalysis =
              _preparedEditsByAnalysisSignature[analysisSignature];
          final previousAnalysisForDensity =
              _withSelectedSubtitleDensity(previousAnalysis);
          if (previousAnalysisForDensity != null) {
            final planningSegments = _trustedPlanningSegmentsForRecipe(
              previousAnalysisForDensity.recipe,
            );
            if (planningSegments.isNotEmpty) {
              if (mounted) {
                setState(
                  () =>
                      _processingTitle = 'กำลังเลือกช่วงที่ดีที่สุดให้ใหม่...',
                );
              }
              final recipe = previousAnalysisForDensity.recipe;
              final transcript = recipe.transcript;
              final planEdit = widget.planEdit ?? _apiClient.requestAiEditPlan;
              final plan = await planEdit(
                AiEditPlanRequest(
                  segments: planningSegments,
                  durationSeconds: transcript.durationSeconds,
                  targetDurationSeconds: _selectedDurationSeconds.toDouble(),
                ),
              );
              if (!mounted) {
                return;
              }
              prepared = AiEditPrepareResult(
                recipe: recipe.withPlan(plan),
                quota: previousAnalysisForDensity.quota,
              );
              prepared = await _enhancePreparedEditWithVisualProxy(
                sourceFile: file,
                prepared: prepared,
              );
              _preparedEditsBySignature[prepareSignature] = prepared;
            }
          }
          if (prepared == null) {
            AiEditAudioArtifact? audioArtifact;
            AiEditAudioChunksArtifact? audioChunksArtifact;
            final remoteAudioKeys = <String>[];
            try {
              if (mounted) {
                setState(
                  () => _processingTitle = 'กำลังเตรียมเสียงให้ AI...',
                );
              }

              final createUpload =
                  widget.createUpload ?? _apiClient.createUpload;
              final uploadVideoFile =
                  widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
              Future<UploadResult> uploadAudioFile(File audioFile) =>
                  createAndUploadFileWithRetry(
                    request: CreateUploadRequest(
                      fileName: _readFileNameFromPath(audioFile.path),
                      contentType: 'audio/mp4',
                      sizeBytes: audioFile.lengthSync(),
                      purpose: 'ai-edit-audio',
                    ),
                    file: audioFile,
                    createUpload: createUpload,
                    uploadFile: uploadVideoFile,
                    onRetry: () {
                      if (mounted) {
                        setState(() {
                          _processingTitle =
                              'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...';
                        });
                      }
                    },
                  );

              late final AiEditPrepareRequest prepareRequest;
              if (widget.extractAudio != null) {
                audioArtifact = await widget.extractAudio!(file);
                final upload = await uploadAudioFile(audioArtifact.file);
                remoteAudioKeys.add(upload.videoS3Key);
                prepareRequest = _buildPrepareRequest(upload.videoS3Key);
              } else {
                final extractAudioChunks = widget.extractAudioChunks ??
                    AiEditAudioExtractor().extractChunks;
                audioChunksArtifact = await extractAudioChunks(
                  file,
                  knownDurationSeconds: picked.durationSeconds,
                );
                final requests = <AiEditAudioChunkRequest>[];
                for (final chunk in audioChunksArtifact.chunks) {
                  final upload = await uploadAudioFile(chunk.file);
                  remoteAudioKeys.add(upload.videoS3Key);
                  requests.add(
                    AiEditAudioChunkRequest(
                      audioS3Key: upload.videoS3Key,
                      startSeconds: chunk.startSeconds,
                    ),
                  );
                }
                prepareRequest = _buildPrepareRequest(
                  null,
                  audioChunks: requests,
                );
              }

              final prepareEdit =
                  widget.prepareEdit ?? _apiClient.prepareAiEdit;
              final preparedFromApi = await prepareEdit(prepareRequest);
              if (!mounted) {
                return;
              }
              _preparedEditsByAnalysisSignature[analysisSignature] =
                  preparedFromApi;
              final preparedForDensity =
                  _withSelectedSubtitleDensity(preparedFromApi);
              if (preparedForDensity == null) {
                throw const ApiException(
                  'เซิร์ฟเวอร์ยังไม่รองรับความยาวซับที่เลือก กรุณาลองใหม่',
                );
              }
              prepared = await _enhancePreparedEditWithVisualProxy(
                sourceFile: file,
                prepared: preparedForDensity,
              );
              _preparedEditsBySignature[prepareSignature] = prepared;
            } finally {
              if (audioArtifact != null) {
                await _cleanupLocalAudioBestEffort(audioArtifact);
              }
              if (audioChunksArtifact != null) {
                await _cleanupLocalAudioChunksBestEffort(audioChunksArtifact);
              }
              for (final remoteAudioKey in remoteAudioKeys) {
                await _cleanupRemoteAudioBestEffort(remoteAudioKey);
              }
            }
          }
        }
      }

      if (!mounted) {
        return;
      }
      final preparedResult = prepared;
      final activeRecipe = localRecipe ?? preparedResult?.recipe;
      if (activeRecipe == null) {
        throw const ApiException('สร้างแผนตัดต่อไม่สำเร็จ');
      }
      setState(() {
        _processingTitle = analysisMode == AiEditAnalysisMode.localRenderOnly
            ? 'กำลังปรับสีและแสงบนเครื่อง...'
            : 'กำลังสร้างวิดีโอตัวอย่าง...';
        // FFmpeg can spend tens of seconds initialising the encoder before it
        // reports the first processed timestamp. Keep the indicator
        // indeterminate until a real progress value arrives instead of
        // presenting a frozen and misleading 0%.
        _renderProgress = null;
      });

      final silenceVerification = effectiveCapabilities['silence'] == true
          ? await _verifySilenceForRecipe(
              recipe: activeRecipe,
              sourceFile: file,
            )
          : const AiEditSilenceVerificationResult(
              cutRanges: [],
              probeSucceeded: true,
            );
      if (!mounted) {
        return;
      }
      final reviewCapabilities = _buildReviewCapabilities(
        activeRecipe,
        silenceVerification: silenceVerification,
      );
      final recommendedSpeechOccurrenceIds = {
        if (widget.safetyFlags.automaticRepeatCutsEnabled)
          for (final cut in activeRecipe.speechReduction.defaultCutRanges)
            cut.occurrenceId,
      };
      final initialSpeechOccurrenceIds = widget
                  .safetyFlags.automaticRepeatCutsEnabled &&
              _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai
          ? recommendedSpeechOccurrenceIds
          : <String>{};
      SubtitleProject? mappedProject;
      if (reviewCapabilities['subtitle'] == true) {
        final identity = buildSubtitleProjectIdentity(
          sourceFile: file,
          setupSignature: prepareSignature,
        );
        final baseProject = mapAiEditRecipeToSubtitleProject(
          recipe: activeRecipe,
          projectId: identity.projectId,
          sourceFingerprint: identity.sourceFingerprint,
          now: DateTime.now().toUtc(),
          effectiveCutRanges: const [],
          maxCharsPerCue:
              _buildEditOptions(reviewCapabilities).subtitleMaxChars ?? 18,
        );
        mappedProject = applySubtitleSetupStyle(
          baseProject,
          _subtitleStyleForSetup(
            baseProject.defaultStyle,
            reviewCapabilities,
          ),
        );
      }
      final rendered = await _renderPreparedRecipe(
        recipe: activeRecipe,
        sourceVideo: picked,
        capabilities: reviewCapabilities,
        verifiedSilenceRanges: silenceVerification.cutRanges,
        renderProject: mappedProject,
        removedSpeechOccurrenceIds: initialSpeechOccurrenceIds,
      );
      final result = rendered.video;
      final projectWithAppliedCuts = _replaceProjectCutsAfterRender(
        mappedProject,
        rendered.appliedCutRanges,
      );
      final selectedSpeechOccurrenceIds =
          widget.safetyFlags.automaticRepeatCutsEnabled &&
                  reviewCapabilities['filler'] == true
              ? rendered.appliedSpeechOccurrenceIds
              : <String>{};

      if (result.colorFilterSkipped) {
        reviewCapabilities.remove('color');
      }

      if (mounted) {
        final acceptedSetup = _captureSetupSnapshot();
        final pickedDuration = picked.durationSeconds;
        final transcriptDuration = activeRecipe.transcript.durationSeconds;
        final acceptedSourceDuration = pickedDuration != null &&
                pickedDuration.isFinite &&
                pickedDuration > 0
            ? pickedDuration
            : transcriptDuration.isFinite && transcriptDuration > 0
                ? transcriptDuration
                : null;
        setState(() {
          if (preparedResult != null) {
            _aiEditQuota = preparedResult.quota;
            _isLoadingAiEditQuota = false;
            _aiEditQuotaLoadFailed = false;
          }
          _activeSourceVideo = picked;
          _activeSourceDurationSeconds = acceptedSourceDuration;
          _activeRecipe = activeRecipe;
          _preparedEdit = preparedResult;
          _acceptedSilenceVerification = silenceVerification;
          _subtitleProject = projectWithAppliedCuts;
          _renderedResult = result;
          _prepareReviewForResult(result, sourceVideo: picked);
          _acceptedSetup = acceptedSetup;
          _reviewCapabilities
            ..clear()
            ..addAll(reviewCapabilities);
          _appliedReviewCapabilities
            ..clear()
            ..addAll(reviewCapabilities);
          _reviewRemovedSpeechOccurrenceIds
            ..clear()
            ..addAll(selectedSpeechOccurrenceIds);
          _appliedRemovedSpeechOccurrenceIds
            ..clear()
            ..addAll(selectedSpeechOccurrenceIds);
          _boundaryEvidenceWarning = rendered.boundaryEvidenceWarning;
          _stage = _AiEditingStage.review;
          _processing = false;
          _renderProgress = null;
          _renderCancelRequested = false;
        });
      }
    } on ApiException catch (error) {
      _handleProcessingFailure(_friendlyAiError(error));
    } on AiEditAudioExtractionException catch (error) {
      _handleProcessingFailure(error.message);
    } on UnsupportedAiEditAnalysisException catch (error) {
      _handleProcessingFailure(error.toString());
    } on SubtitleBurnException catch (error) {
      _handleProcessingFailure(error.message);
    } on SubtitleProjectValidationException catch (error) {
      _handleProcessingFailure(
        'เตรียมโปรเจกต์ซับไม่สำเร็จ: ${error.message}',
      );
    } catch (_) {
      _handleProcessingFailure('AI ตัดต่อวิดีโอไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  bool get _shouldAttemptVisualProxy =>
      widget.extractVisualProxy != null ||
      (widget.createUpload == null &&
          widget.uploadVideoFile == null &&
          widget.prepareEdit == null &&
          widget.planEdit == null);

  Future<AiEditPrepareResult> _enhancePreparedEditWithVisualProxy({
    required File sourceFile,
    required AiEditPrepareResult prepared,
  }) async {
    final transcript = prepared.recipe.transcript;
    final planningSegments = _trustedPlanningSegmentsForRecipe(prepared.recipe);
    final targetDurationSeconds = _selectedDurationSeconds.toDouble();
    if (!_shouldAttemptVisualProxy ||
        _isUsingOriginalDuration ||
        planningSegments.isEmpty ||
        transcript.durationSeconds <= 0 ||
        targetDurationSeconds >= transcript.durationSeconds - 0.5) {
      return prepared;
    }

    String? remoteProxyKey;
    try {
      if (mounted) {
        setState(
          () =>
              _processingTitle = 'กำลังสร้างวิดีโอตัวอย่างทั้งคลิปให้ AI ดู...',
        );
      }
      final proxyArtifact = await _getOrCreateVisualProxy(sourceFile);

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      final upload = await createAndUploadFileWithRetry(
        request: CreateUploadRequest(
          fileName: _readFileNameFromPath(proxyArtifact.file.path),
          contentType: 'video/mp4',
          sizeBytes: proxyArtifact.file.lengthSync(),
          purpose: 'ai-edit-visual-proxy',
        ),
        file: proxyArtifact.file,
        createUpload: createUpload,
        uploadFile: uploadVideoFile,
        onRetry: () {
          if (mounted) {
            setState(
              () => _processingTitle =
                  'ลิงก์วิดีโอตัวอย่างหมดอายุ กำลังลองใหม่...',
            );
          }
        },
      );
      remoteProxyKey = upload.videoS3Key;

      if (mounted) {
        setState(
          () => _processingTitle =
              'AI กำลังดูภาพ ฟังเสียง และเลือกช่วงจากทั้งคลิป...',
        );
      }
      final planEdit = widget.planEdit ?? _apiClient.requestAiEditPlan;
      final visualPlan = await planEdit(
        AiEditPlanRequest(
          segments: planningSegments,
          durationSeconds: transcript.durationSeconds,
          targetDurationSeconds: targetDurationSeconds,
          visualProxyS3Key: remoteProxyKey,
        ),
      );
      return AiEditPrepareResult(
        recipe: prepared.recipe.withPlan(visualPlan),
        quota: prepared.quota,
      );
    } catch (error) {
      debugPrint(
        'AI visual planning unavailable; using audio plan: $error',
      );
      return prepared;
    } finally {
      if (remoteProxyKey != null) {
        await _cleanupRemoteVisualProxyBestEffort(remoteProxyKey);
      }
    }
  }

  AiEditPrepareRequest _buildPrepareRequest(
    String? audioS3Key, {
    List<AiEditAudioChunkRequest> audioChunks =
        const <AiEditAudioChunkRequest>[],
  }) {
    final capabilities = _effectiveCapabilities;
    final canUseBeatMusic =
        _isCapabilityEnabled('beatsync') && _beatMusicSelectionComplete;
    if (!canUseBeatMusic) {
      capabilities['beatsync'] = false;
    }
    final effectiveMusicSource =
        canUseBeatMusic ? _musicSource : _BeatMusicSource.original;

    return AiEditPrepareRequest(
      audioS3Key: audioS3Key,
      audioChunks: audioChunks.isEmpty ? null : audioChunks,
      durationSeconds:
          _selectedVideoDurationSeconds ?? _selectedDurationSeconds.toDouble(),
      targetDurationSeconds:
          _isUsingOriginalDuration ? null : _selectedDurationSeconds.toDouble(),
      capabilities: {
        ...capabilities,
        'sfx': false,
      },
      settings: AiEditPrepareSettings(
        subtitleStyle: 'outline',
        subtitleColor: _subtitleHexColor(_subtitleColor),
        subtitleOutlineColor: _subtitleHexColor(_subtitleOutlineColor),
        subtitleWordsPerLine: _subtitleWordsPerLine,
        subtitlePosition: _effectiveSubtitlePosition,
        subtitleNormalizedX: _subtitleNormalizedX,
        subtitleNormalizedY: _subtitleNormalizedY,
        ctaText: _ctaController.text.trim(),
        ctaDesign: _ctaDesign,
        priceText: _priceNowController.text.trim(),
        watermarkText: 'PostDee',
        toneFilter: _toneFilter,
        zoomLevel: _zoomLevel,
        silencePreset: _silencePreset,
        speechReductionMode: 'auto',
        music: AiEditMusicSettings(
          source: switch (effectiveMusicSource) {
            _BeatMusicSource.auto => 'auto',
            _BeatMusicSource.library => 'library',
            _BeatMusicSource.device => 'device',
            _BeatMusicSource.original => 'original',
          },
          genre: effectiveMusicSource == _BeatMusicSource.auto
              ? _musicGenre
              : null,
          trackId: effectiveMusicSource == _BeatMusicSource.library
              ? _selectedMusicTrackId
              : null,
          beatIntensity: switch (_beatIntensity) {
            _BeatCutIntensity.smooth => 'smooth',
            _BeatCutIntensity.balanced => 'balanced',
            _BeatCutIntensity.energetic => 'energetic',
          },
          volume: _musicVolume,
          ducking: AiEditMusicDuckingSettings(
            enabled: _duckMusicDuringSpeech,
          ),
        ),
      ),
    );
  }

  String _buildPrepareSignature(PickedVideoFile picked, File sourceFile) {
    final request = _buildPrepareRequest('__signature_audio__.m4a').toJson()
      ..remove('audioS3Key')
      ..remove('videoS3Key');
    _removeReusableSubtitleFormattingFromSignature(request);

    return jsonEncode({
      'source': {
        'path': picked.path,
        'name': picked.name,
        'sizeBytes': sourceFile.lengthSync(),
        'lastModifiedMs': sourceFile.lastModifiedSync().millisecondsSinceEpoch,
      },
      'request': request,
    });
  }

  String _buildAnalysisSignature(PickedVideoFile picked, File sourceFile) {
    final request = _buildPrepareRequest('__signature_audio__.m4a').toJson()
      ..remove('audioS3Key')
      ..remove('videoS3Key')
      ..remove('durationSeconds')
      ..remove('targetDurationSeconds');
    _removeReusableSubtitleFormattingFromSignature(request);

    return jsonEncode({
      'source': {
        'path': picked.path,
        'name': picked.name,
        'sizeBytes': sourceFile.lengthSync(),
        'lastModifiedMs': sourceFile.lastModifiedSync().millisecondsSinceEpoch,
      },
      'request': request,
    });
  }

  void _removeReusableSubtitleFormattingFromSignature(
    Map<String, Object?> request,
  ) {
    final settings = request['settings'];
    if (settings is! Map<String, Object?>) return;

    // Presentation is applied locally. Subtitle density is selected from the
    // 1/3/5 variants returned by the first prepare response. Keeping these
    // values out of the key prevents formatting the same transcript from
    // uploading/transcribing it and consuming the seller's minutes again.
    settings
      ..remove('subtitleColor')
      ..remove('subtitleOutlineColor')
      ..remove('subtitleWordsPerLine')
      ..remove('subtitlePosition')
      ..remove('subtitleNormalizedX')
      ..remove('subtitleNormalizedY');
  }

  AiEditPrepareResult? _withSelectedSubtitleDensity(
    AiEditPrepareResult? prepared,
  ) {
    if (prepared == null) return null;
    final recipe = prepared.recipe.withSubtitleWordsPerLine(
      _subtitleWordsPerLine,
    );
    if (recipe == null) return null;
    if (identical(recipe, prepared.recipe)) return prepared;
    return AiEditPrepareResult(recipe: recipe, quota: prepared.quota);
  }

  Future<void> _cleanupRemoteAudioBestEffort(String audioS3Key) async {
    try {
      final cleanup =
          widget.cleanupAiEditAudio ?? _apiClient.cleanupAiEditAudio;
      await cleanup(audioS3Key);
    } catch (_) {
      // The API also cleans temporary audio after prepare.
    }
  }

  Future<void> _cleanupLocalAudioBestEffort(
    AiEditAudioArtifact artifact,
  ) async {
    try {
      await artifact.cleanup();
    } catch (_) {
      // Do not replace the original processing result or error.
    }
  }

  Future<void> _cleanupLocalAudioChunksBestEffort(
    AiEditAudioChunksArtifact artifact,
  ) async {
    try {
      await artifact.cleanup();
    } catch (_) {
      // Do not replace the original processing result or error.
    }
  }

  Future<void> _cleanupRemoteVisualProxyBestEffort(
    String visualProxyS3Key,
  ) async {
    try {
      final cleanup = widget.cleanupAiEditVisualProxy ??
          _apiClient.cleanupAiEditVisualProxy;
      await cleanup(visualProxyS3Key);
    } catch (_) {
      // The planning API also removes the temporary visual proxy.
    }
  }

  Future<void> _cleanupLocalVisualProxyBestEffort(
    AiEditVisualProxyArtifact artifact,
  ) async {
    try {
      await artifact.cleanup();
    } catch (_) {
      // Do not replace the audio plan when temporary cleanup fails.
    }
  }

  String _visualProxySourceKey(File sourceFile) => jsonEncode({
        'path': sourceFile.path,
        'sizeBytes': sourceFile.lengthSync(),
        'lastModifiedMs': sourceFile.lastModifiedSync().millisecondsSinceEpoch,
      });

  Future<AiEditVisualProxyArtifact> _getOrCreateVisualProxy(
    File sourceFile,
  ) async {
    final sourceKey = _visualProxySourceKey(sourceFile);
    final cached = _cachedVisualProxyArtifact;
    if (_cachedVisualProxySourceKey == sourceKey &&
        cached != null &&
        cached.file.existsSync()) {
      return cached;
    }

    await _releaseCachedVisualProxy();
    final extractVisualProxy =
        widget.extractVisualProxy ?? AiEditVisualProxyExtractor().extract;
    final artifact = await extractVisualProxy(sourceFile);
    if (!mounted) {
      await _cleanupLocalVisualProxyBestEffort(artifact);
      throw StateError('AI editing screen closed during visual extraction');
    }
    _cachedVisualProxySourceKey = sourceKey;
    _cachedVisualProxyArtifact = artifact;
    return artifact;
  }

  Future<void> _releaseCachedVisualProxy() async {
    final artifact = _cachedVisualProxyArtifact;
    _cachedVisualProxyArtifact = null;
    _cachedVisualProxySourceKey = null;
    if (artifact != null) {
      await _cleanupLocalVisualProxyBestEffort(artifact);
    }
  }

  Future<SubtitleDraftStore> _getSubtitleDraftStore() async {
    final injected = widget.subtitleDraftStore;
    if (injected != null) return injected;
    final cached = _resolvedSubtitleDraftStore;
    if (cached != null) return cached;
    final supportDirectory = await getApplicationSupportDirectory();
    final store = FileSubtitleDraftStore(
      rootDirectory: Directory(
        '${supportDirectory.path}${Platform.pathSeparator}subtitle-drafts',
      ),
    );
    _resolvedSubtitleDraftStore = store;
    return store;
  }

  Future<SubtitleProject?> _openSubtitleStudio({
    required File sourceFile,
    required SubtitleProject initialProject,
  }) async {
    final store = await _getSubtitleDraftStore();
    if (!mounted) return null;
    final launcher = widget.subtitleStudioLauncher;
    if (launcher != null) {
      return launcher(context, sourceFile, initialProject, store);
    }
    return Navigator.of(context).push<SubtitleProject>(
      MaterialPageRoute<SubtitleProject>(
        builder: (_) => SubtitleStudioScreen(
          sourceFile: sourceFile,
          initialProject: initialProject,
          draftStore: store,
        ),
      ),
    );
  }

  void _handleProcessingFailure(String message) {
    if (!mounted) {
      return;
    }

    unawaited(_loadAiEditQuota());
    final hasPreviousResult = _renderedResult != null;
    final acceptedSetup = _acceptedSetup;
    setState(() {
      _processing = false;
      _renderProgress = null;
      _renderCancelRequested = false;
      if (hasPreviousResult) {
        if (acceptedSetup != null) {
          _restoreSetupSnapshot(acceptedSetup);
        }
        _reviewCapabilities
          ..clear()
          ..addAll(_appliedReviewCapabilities);
        _reviewRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(_appliedRemovedSpeechOccurrenceIds);
        _stage = _AiEditingStage.review;
      }
    });
    _showError(
      hasPreviousResult ? '$message · ผลลัพธ์เดิมยังอยู่' : message,
    );
  }

  List<SilenceCutRange> get _verifiedSilenceRanges =>
      _acceptedSilenceVerification.cutRanges;

  bool get _silenceVerificationUnavailable =>
      !_acceptedSilenceVerification.probeSucceeded;

  bool get _acceptedSilenceWasRequested =>
      widget.safetyFlags.verifiedSilenceEnabled &&
      ((_acceptedSetup?.capabilities ?? _capabilities)['silence'] ?? false);

  String _buildSilenceVerificationSignature({
    required File sourceFile,
    required double durationSeconds,
    required List<SilenceCutRange> candidates,
    required List<SilenceCutRange> protectedSpeechRanges,
  }) =>
      jsonEncode({
        'path': sourceFile.absolute.path,
        'modified': sourceFile.lastModifiedSync().toUtc().toIso8601String(),
        'durationSeconds': durationSeconds,
        'candidates': [
          for (final range in candidates) [range.start, range.end],
        ],
        'protectedSpeechRanges': [
          for (final range in protectedSpeechRanges) [range.start, range.end],
        ],
      });

  Future<AiEditSilenceVerificationResult> _verifySilenceForRecipe({
    required AiEditRecipeResult recipe,
    required File sourceFile,
    bool force = false,
  }) async {
    final candidates = [
      for (final range in recipe.silenceRanges)
        SilenceCutRange(start: range.start, end: range.end),
    ];
    if (candidates.isEmpty) {
      return const AiEditSilenceVerificationResult(
        cutRanges: [],
        probeSucceeded: true,
      );
    }

    final evidence = mapAiEditTimelineEvidence(recipe.transcript);
    final signature = _buildSilenceVerificationSignature(
      sourceFile: sourceFile,
      durationSeconds: recipe.transcript.durationSeconds,
      candidates: candidates,
      protectedSpeechRanges: evidence.protectedSpeechRanges,
    );
    if (!force) {
      final cached = _silenceVerificationBySignature[signature];
      if (cached != null) {
        return cached;
      }
    }

    final verifier = widget.verifySilence ?? AiEditSilenceVerifier().call;
    final result = await verifier(
      sourceFile: sourceFile,
      sourceDurationSeconds: recipe.transcript.durationSeconds,
      transcriptCandidates: candidates,
      protectedSpeechRanges: evidence.protectedSpeechRanges,
    );
    if (result.probeSucceeded) {
      _silenceVerificationBySignature[signature] = result;
    }
    return result;
  }

  SubtitleProject? _replaceProjectCutsAfterRender(
    SubtitleProject? project,
    List<SilenceCutRange> appliedCutRanges,
  ) =>
      project == null
          ? null
          : replaceSubtitleProjectCutRanges(
              project: project,
              effectiveCutRanges: appliedCutRanges,
              now: DateTime.now().toUtc(),
            );

  Map<String, bool> _buildReviewCapabilities(
    AiEditRecipeResult recipe, {
    required AiEditSilenceVerificationResult silenceVerification,
  }) {
    final subtitle = recipe.capabilities['subtitle'];
    final filler = recipe.capabilities['filler'];
    final hasStructuredSpeechReduction = recipe.speechReduction.isReady &&
        buildSpeechReductionReviewGroups(recipe.speechReduction).isNotEmpty;
    final canUseLegacySpeechReduction =
        _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai &&
            (filler?.isApplied ?? false) &&
            recipe.fillerRanges.isNotEmpty;

    return {
      if ((_capabilities['subtitle'] ?? false) &&
          (subtitle?.isApplied ?? false) &&
          recipe.subtitles.segments.isNotEmpty)
        'subtitle': true,
      if ((_capabilities['silence'] ?? false) &&
          widget.safetyFlags.verifiedSilenceEnabled &&
          silenceVerification.probeSucceeded &&
          silenceVerification.cutRanges.isNotEmpty)
        'silence': true,
      if (widget.safetyFlags.automaticRepeatCutsEnabled &&
          (_capabilities['filler'] ?? false) &&
          (hasStructuredSpeechReduction || canUseLegacySpeechReduction))
        'filler': true,
      if (_isCapabilityEnabled('color')) 'color': true,
    };
  }

  Future<void> _retrySilenceVerification() async {
    if (_silenceRetryInProgress ||
        _processing ||
        _updatingReviewPreview ||
        !widget.safetyFlags.verifiedSilenceEnabled) {
      return;
    }
    final recipe = _activeRecipe;
    final picked = _activeSourceVideo;
    if (recipe == null || picked == null) {
      return;
    }
    final renderProject = _subtitleProject;
    final acceptedCapabilities = Map<String, bool>.from(_reviewCapabilities);
    final acceptedSpeechOccurrenceIds =
        Set<String>.from(_reviewRemovedSpeechOccurrenceIds);

    setState(() {
      _silenceRetryInProgress = true;
      _updatingReviewPreview = true;
      _renderProgress = null;
      _renderCancelRequested = false;
    });
    try {
      final verification = await _verifySilenceForRecipe(
        recipe: recipe,
        sourceFile: File(picked.path),
        force: true,
      );
      if (!verification.probeSucceeded) {
        if (mounted) {
          setState(() => _acceptedSilenceVerification = verification);
        }
        return;
      }

      final retryCapabilities = Map<String, bool>.from(acceptedCapabilities);
      if (verification.cutRanges.isNotEmpty) {
        retryCapabilities['silence'] = true;
      } else {
        retryCapabilities.remove('silence');
      }
      final requestedSpeechOccurrenceIds =
          widget.safetyFlags.automaticRepeatCutsEnabled
              ? acceptedSpeechOccurrenceIds
              : <String>{};
      final rendered = await _renderPreparedRecipe(
        recipe: recipe,
        sourceVideo: picked,
        capabilities: retryCapabilities,
        verifiedSilenceRanges: verification.cutRanges,
        renderProject: renderProject,
        removedSpeechOccurrenceIds: requestedSpeechOccurrenceIds,
      );
      if (!mounted) return;
      final updatedProject = _replaceProjectCutsAfterRender(
        renderProject,
        rendered.appliedCutRanges,
      );
      setState(() {
        _acceptedSilenceVerification = verification;
        _reviewCapabilities
          ..clear()
          ..addAll(retryCapabilities);
        _appliedReviewCapabilities
          ..clear()
          ..addAll(retryCapabilities);
        _reviewRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(rendered.appliedSpeechOccurrenceIds);
        _appliedRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(rendered.appliedSpeechOccurrenceIds);
        _renderedResult = rendered.video;
        _subtitleProject = updatedProject;
        _boundaryEvidenceWarning = rendered.boundaryEvidenceWarning;
        _prepareReviewForResult(rendered.video, sourceVideo: picked);
      });
    } on SubtitleBurnException catch (error) {
      if (mounted) {
        _showError('${error.message} · ผลลัพธ์เดิมยังอยู่');
      }
    } catch (_) {
      if (mounted) {
        _showError('ตรวจช่วงเงียบไม่สำเร็จ · ผลลัพธ์เดิมยังอยู่');
      }
    } finally {
      if (mounted) {
        setState(() {
          _silenceRetryInProgress = false;
          _updatingReviewPreview = false;
          _renderProgress = null;
          _renderCancelRequested = false;
        });
      }
    }
  }

  Future<_PreparedRecipeRenderResult> _renderPreparedRecipe({
    required AiEditRecipeResult recipe,
    required PickedVideoFile sourceVideo,
    required Map<String, bool> capabilities,
    required List<SilenceCutRange> verifiedSilenceRanges,
    required SubtitleProject? renderProject,
    Set<String>? removedSpeechOccurrenceIds,
    VideoRenderPurpose purpose = VideoRenderPurpose.preview,
  }) async {
    final picked = sourceVideo;
    final originalFile = File(picked.path);
    final sourceDuration = recipe.transcript.durationSeconds;
    final requestedTargetSeconds = _selectedDurationSecondsFor(
      sourceDuration > 0 ? sourceDuration : picked.durationSeconds,
    );
    final usingOriginalDuration = _isUsingOriginalDurationFor(
      sourceDuration > 0 ? sourceDuration : picked.durationSeconds,
    );
    final options = _buildEditOptions(
      capabilities,
      targetSeconds: requestedTargetSeconds,
    );
    final effectiveRemovedSpeechOccurrenceIds =
        widget.safetyFlags.automaticRepeatCutsEnabled
            ? (removedSpeechOccurrenceIds ?? const <String>{})
            : const <String>{};
    var planCutRanges = <SilenceCutRange>[
      // Style/free-prompt cuts determine the requested story window.
      for (final range in recipe.plan.cuts)
        SilenceCutRange(start: range.start, end: range.end),
    ];
    final requestedSpeechCleanupRanges = <SilenceCutRange>[
      if (widget.safetyFlags.automaticRepeatCutsEnabled &&
          (capabilities['filler'] ?? false))
        for (final range in recipe.speechReduction.isReady
            ? buildSpeechReductionCutRanges(
                recipe.speechReduction,
                effectiveRemovedSpeechOccurrenceIds,
              )
            : _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai
                ? recipe.fillerRanges
                : const <AiEditCut>[])
          SilenceCutRange(start: range.start, end: range.end),
    ];

    final timelineEvidence = mapAiEditTimelineEvidence(recipe.transcript);
    final boundarySegments = timelineEvidence.boundarySegments;
    final boundaryEvidenceWarning = !usingOriginalDuration &&
            !timelineEvidence.hasReliableBoundaries
        ? 'ไม่พบขอบประโยคที่ยืนยันได้ • ใช้ช่วงเรื่องจาก AI โดยไม่เดาเวลาใหม่'
        : null;
    if (sourceDuration > 0) {
      planCutRanges = withTargetLength(
        planCutRanges,
        sourceDuration,
        usingOriginalDuration
            ? sourceDuration
            : requestedTargetSeconds.toDouble(),
      );
    }

    final studioProject =
        capabilities['subtitle'] == true ? renderProject : null;
    final studioStyle = studioProject?.defaultStyle;
    var sourceTimelineSubtitleSegments = <SubtitleSegment>[
      if (studioProject != null)
        for (final cue in studioProject.cues)
          SubtitleSegment(
            text: cue.text,
            start: cue.sourceStartMs / 1000,
            end: cue.sourceEndMs / 1000,
            words: subtitleWordsForRender(cue),
          )
      else if (capabilities['subtitle'] ?? false)
        for (final segment in recipe.subtitles.segments)
          SubtitleSegment(
            text: segment.text,
            start: segment.start,
            end: segment.end,
            words: [
              for (final word
                  in segment.words ?? const <AiEditTranscriptWordResult>[])
                SubtitleWordTiming(
                  text: word.word,
                  start: word.start,
                  end: word.end,
                ),
            ],
          ),
    ];
    // A repeated word may sit inside a longer subtitle cue. Remove the same
    // word from the source-timeline subtitle before cutting the media. If the
    // word timing cannot be proven, the helper rejects that cut so audio and
    // on-screen text can never disagree.
    final sanitizedSpeechCleanup = sanitizeSubtitleSegmentsForCleanupCuts(
      segments: sourceTimelineSubtitleSegments,
      requestedCuts: requestedSpeechCleanupRanges,
      subtitlesEnabled: (capabilities['subtitle'] ?? false) &&
          sourceTimelineSubtitleSegments.isNotEmpty,
    );
    sourceTimelineSubtitleSegments = sanitizedSpeechCleanup.segments;
    final appliedSpeechOccurrenceIds = recipe.speechReduction.isReady
        ? resolveAppliedSpeechReductionSelection(
            recipe.speechReduction,
            effectiveRemovedSpeechOccurrenceIds,
            [
              for (final range in sanitizedSpeechCleanup.appliedCleanupRanges)
                AiEditCut(start: range.start, end: range.end),
            ],
          )
        : const <String>{};
    final subtitleMaxChars = options.subtitleMaxChars;
    final subtitleWordsPerLine = recipe.subtitles.style.wordsPerLine;
    final preserveValidatedSubtitleCues = (subtitleWordsPerLine == 1 ||
            subtitleWordsPerLine == 3 ||
            subtitleWordsPerLine == 5) &&
        recipe.subtitles.variants.containsKey(subtitleWordsPerLine);
    var subtitleSegments = prepareSubtitleSegmentsForLocalRender(
      sourceTimelineSubtitleSegments,
      language: recipe.transcript.language,
      maximumCharacters: subtitleMaxChars,
      preserveValidatedCues: preserveValidatedSubtitleCues,
    );

    if (sourceDuration > 0 && boundarySegments.isNotEmpty) {
      planCutRanges = alignLeadingCutToFirstSubtitle(
        planCutRanges,
        boundarySegments,
        sourceDuration,
      );
      if (!usingOriginalDuration) {
        planCutRanges = alignTargetTailToSubtitleBoundary(
          cuts: planCutRanges,
          subtitleSegments: boundarySegments,
          durationSeconds: sourceDuration,
          targetSeconds: requestedTargetSeconds.toDouble(),
        );
      }
    }

    final cleanupCutRanges = <SilenceCutRange>[
      // Cleanup is intentionally unioned only after story fitting/alignment.
      // It must never be shortened or restored merely to hit an exact target.
      if ((capabilities['silence'] ?? false) &&
          widget.safetyFlags.verifiedSilenceEnabled)
        ...verifiedSilenceRanges,
      ...sanitizedSpeechCleanup.appliedCleanupRanges,
    ];
    final cutRanges = sourceDuration > 0
        ? mergeProtectedCutRanges(
            planCuts: planCutRanges,
            cleanupCuts: cleanupCutRanges,
            durationSeconds: sourceDuration,
          )
        : <SilenceCutRange>[...planCutRanges, ...cleanupCutRanges];

    final speed = options.speed ?? 1;
    final previewProfile = purpose == VideoRenderPurpose.preview
        ? videoPreviewProfileForSourceDuration(sourceDuration)
        : null;
    final outputDuration = sourceDuration > 0
        ? estimateResultSeconds(
            durationSeconds: sourceDuration,
            cutRanges: cutRanges,
            speed: speed,
          )
        : null;
    final requestedSubtitleFontSize =
        studioStyle?.fontSize ?? options.subtitleFontSize ?? 18;
    final subtitleTexts = subtitleSegments.map((segment) => segment.text);
    final pickedWidth = picked.width?.toDouble();
    final pickedHeight = picked.height?.toDouble();
    final subtitleCanvasSize = pickedWidth != null &&
            pickedHeight != null &&
            pickedWidth.isFinite &&
            pickedHeight.isFinite &&
            pickedWidth > 0 &&
            pickedHeight > 0
        ? subtitleAssCanvasSizeForDisplay(Size(pickedWidth, pickedHeight))
        : postDeeSubtitleAssCanvasSize;
    final subtitleLayout = studioStyle == null || subtitleSegments.isEmpty
        ? null
        : resolveSubtitleCanvasLayout(
            texts: subtitleTexts,
            style: studioStyle,
            canvasSize: subtitleCanvasSize,
          );
    final subtitleTextStyle = TextStyle(
      fontFamily: studioStyle?.fontId ?? 'Bai Jamjuree',
      fontWeight: studioStyle == null
          ? FontWeight.w700
          : FontWeight.values.firstWhere(
              (weight) => weight.value == studioStyle.fontWeight,
              orElse: () => FontWeight.w700,
            ),
      fontSize: requestedSubtitleFontSize,
    );
    final legacySubtitleCanvasWidth = subtitleSafeWidthForEffect(
      maxWidth: subtitleSafeAssCanvasWidthAtX(
        0.5,
        canvasSize: subtitleCanvasSize,
      ),
      animation: 'none',
    );
    final subtitleFontSize = subtitleLayout?.fontSize ??
        (subtitleSegments.isEmpty
            ? requestedSubtitleFontSize
            : fitSubtitleFontSizeForSingleLine(
                texts: subtitleTexts,
                style: subtitleTextStyle,
                maxWidth: legacySubtitleCanvasWidth,
              ));
    final subtitleFits = subtitleLayout?.fitsSingleLine ??
        subtitleTextFitsSingleLine(
          texts: subtitleTexts,
          style: subtitleTextStyle,
          fontSize: subtitleFontSize,
          maxWidth: legacySubtitleCanvasWidth,
        );
    if (subtitleSegments.isNotEmpty && !subtitleFits) {
      throw const SubtitleBurnException(
        'ข้อความซับยาวเกินพื้นที่ กรุณาแบ่งประโยคหรือขยับซับเข้าใกล้กึ่งกลาง',
      );
    }
    final needsLocalRender = subtitleSegments.isNotEmpty ||
        cutRanges.isNotEmpty ||
        (speed - 1).abs() > 0.0001 ||
        (options.filterIndex ?? 0) != 0 ||
        (options.brightness ?? 0).abs() > 0.0001 ||
        (options.contrast ?? 0).abs() > 0.0001;
    if (!needsLocalRender) {
      return _PreparedRecipeRenderResult(
        video: BurnedSubtitleResult(
          file: originalFile,
          fileName: picked.name.trim().isNotEmpty
              ? picked.name.trim()
              : _readFileNameFromPath(picked.path),
          sizeBytes: picked.sizeBytes > 0
              ? picked.sizeBytes
              : originalFile.lengthSync(),
        ),
        appliedSpeechOccurrenceIds: appliedSpeechOccurrenceIds,
        appliedCutRanges: List<SilenceCutRange>.unmodifiable(cutRanges),
        boundaryEvidenceWarning: boundaryEvidenceWarning,
      );
    }

    final sortedCapabilities = capabilities.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final renderSignature = jsonEncode({
      'purpose': purpose.name,
      'source': {
        'path': originalFile.path,
        'sizeBytes': originalFile.lengthSync(),
        'lastModifiedMs':
            originalFile.lastModifiedSync().millisecondsSinceEpoch,
      },
      'targetDurationSeconds': requestedTargetSeconds,
      'projectFingerprint': renderProject?.recipeFingerprint,
      'capabilities': {
        for (final entry in sortedCapabilities) entry.key: entry.value,
      },
      'segments': [
        for (final segment in subtitleSegments)
          {
            'text': segment.text,
            'start': segment.start,
            'end': segment.end,
            'words': [
              for (final word in segment.words)
                {
                  'text': word.text,
                  'start': word.start,
                  'end': word.end,
                },
            ],
          },
      ],
      'cuts': [
        for (final range in cutRanges) {'start': range.start, 'end': range.end},
      ],
      'speed': speed,
      'filterIndex': options.filterIndex ?? 0,
      'brightness': options.brightness ?? 0,
      'contrast': options.contrast ?? 0,
      'subtitleFontSize': subtitleFontSize,
      'subtitleAtBottom': options.subtitleAtBottom ?? true,
      'subtitleStudioStyle': studioStyle?.toJson(),
      'previewProfile': previewProfile == null
          ? null
          : {
              'maxVideoDimension': previewProfile.maxVideoDimension,
              'videoBitrate': previewProfile.videoBitrate,
              'maxVideoFrameRate': previewProfile.maxVideoFrameRate,
            },
    });
    final cachedResult = _renderResultsBySignature[renderSignature];
    if (cachedResult != null && cachedResult.file.existsSync()) {
      return _PreparedRecipeRenderResult(
        video: cachedResult,
        appliedSpeechOccurrenceIds: appliedSpeechOccurrenceIds,
        appliedCutRanges: List<SilenceCutRange>.unmodifiable(cutRanges),
        boundaryEvidenceWarning: boundaryEvidenceWarning,
      );
    }
    _renderResultsBySignature.remove(renderSignature);

    final renderer =
        widget.burnVideo ?? const FfmpegSubtitleBurnVideoProcessor().call;
    final cancellationToken = RenderCancellationToken();
    if (mounted) {
      setState(() {
        _activeRenderCancellation = cancellationToken;
        _renderCancelRequested = false;
      });
    }

    void reportProgress(double fraction) {
      if (!mounted ||
          !identical(_activeRenderCancellation, cancellationToken)) {
        return;
      }
      final normalized = fraction.clamp(0.0, 1.0).toDouble();
      final current = _renderProgress ?? 0;
      if (normalized < current ||
          (normalized - current < 0.01 && normalized < 1)) {
        return;
      }
      setState(() => _renderProgress = normalized);
    }

    final request = BurnSubtitleRequest(
      inputFile: originalFile,
      fileName: picked.name.trim().isNotEmpty
          ? picked.name.trim()
          : _readFileNameFromPath(picked.path),
      segments: subtitleSegments,
      silenceRanges: cutRanges,
      speed: speed,
      volume: 1,
      filterIndex: options.filterIndex ?? 0,
      brightness: options.brightness ?? 0,
      contrast: options.contrast ?? 0,
      subtitleFontSize: subtitleFontSize,
      subtitleAtBottom: studioStyle == null
          ? options.subtitleAtBottom ?? true
          : studioStyle.alignment == SubtitleAlignment.bottom,
      subtitleAlignment: studioStyle == null
          ? null
          : _burnSubtitleAlignment(studioStyle.alignment),
      subtitleNormalizedX:
          subtitleLayout?.normalizedPosition.dx ?? studioStyle?.normalizedX,
      subtitleNormalizedY:
          subtitleLayout?.normalizedPosition.dy ?? studioStyle?.normalizedY,
      subtitleCanvasSize: subtitleCanvasSize,
      subtitleFontName: _subtitleRenderFontName(studioStyle),
      subtitleFontAssetPath:
          studioStyle == null ? null : _subtitleFontAssetPath(studioStyle),
      subtitleTextColor: studioStyle?.textColor ?? '#FFFFFF',
      activeWordColor: studioStyle?.activeWordColor ??
          SubtitleStyle.defaults.activeWordColor,
      subtitleAnimation: studioStyle?.animation ?? 'none',
      subtitleOutlineColor: studioStyle?.outlineColor ?? '#000000',
      subtitleOutlineWidth: studioStyle?.outlineWidth ?? 0.5,
      subtitleShadowColor: studioStyle?.shadowColor ?? '#000000',
      subtitleShadowDepth: studioStyle?.shadowDepth ?? 0,
      preserveTempDirectoryPaths: {
        if (_renderedResult != null) _renderedResult!.file.parent.path,
        for (final result in _renderResultsBySignature.values)
          result.file.parent.path,
      },
      outputDurationSeconds: outputDuration,
      maxOutputDurationSeconds: usingOriginalDuration
          ? null
          : aiEditMaximumOutputDurationSeconds(
              targetSeconds: requestedTargetSeconds.toDouble(),
              estimatedOutputSeconds: outputDuration,
            ),
      onProgress: reportProgress,
      onAttemptStarted: (attempt) {
        if (attempt <= 1 || !mounted) {
          return;
        }
        setState(() {
          _processingTitle = 'กำลังลองวิธีสร้างวิดีโอสำรอง...';
          _renderProgress = null;
        });
      },
      renderPurpose: purpose,
      maxVideoDimension: previewProfile?.maxVideoDimension,
      videoBitrate: previewProfile?.videoBitrate,
      maxVideoFrameRate: previewProfile?.maxVideoFrameRate,
      cancellationToken: cancellationToken,
    );

    try {
      final result = await renderer(request).timeout(
        purpose == VideoRenderPurpose.preview
            ? const Duration(minutes: 5)
            : const Duration(minutes: 15),
        onTimeout: () {
          unawaited(cancellationToken.cancel());
          throw SubtitleBurnException(
            purpose == VideoRenderPurpose.preview
                ? 'สร้างวิดีโอตัวอย่างนานเกินไป กรุณาลองใหม่'
                : 'สร้างวิดีโอคุณภาพเต็มนานเกินไป กรุณาลองใหม่',
          );
        },
      );
      reportProgress(1);
      _renderResultsBySignature[renderSignature] = result;
      return _PreparedRecipeRenderResult(
        video: result,
        appliedSpeechOccurrenceIds: appliedSpeechOccurrenceIds,
        appliedCutRanges: List<SilenceCutRange>.unmodifiable(cutRanges),
        boundaryEvidenceWarning: boundaryEvidenceWarning,
      );
    } finally {
      if (mounted && identical(_activeRenderCancellation, cancellationToken)) {
        setState(() => _activeRenderCancellation = null);
      }
    }
  }

  EditStyleOptions _buildEditOptions(
    Map<String, bool> capabilities, {
    int? targetSeconds,
  }) {
    final subtitleOn = capabilities['subtitle'] ?? false;
    final colorOn = capabilities['color'] ?? false;

    final subtitleMaxChars = switch (_subtitleWords) {
      'karaoke' => 8,
      'full' => 36,
      _ => 18,
    };
    final subtitleFontSize = switch (_subtitleStyle) {
      'small' => 17.0,
      'medium' => 19.0,
      _ => 22.0,
    };
    final filterIndex = switch (_toneFilter) {
      'vivid' => 1,
      'warm' => 4,
      'cool' => 5,
      'vintage' => 2,
      _ => 1,
    };

    return EditStyleOptions(
      targetSeconds: targetSeconds ?? _selectedDurationSeconds,
      subtitleMaxChars: subtitleOn ? subtitleMaxChars : null,
      silenceMinGapSec: (capabilities['silence'] ?? false)
          ? switch (_silencePreset) {
              'natural' => 1.0,
              'compact' => 0.4,
              _ => 0.6,
            }
          : null,
      speed: 1,
      filterIndex: colorOn ? filterIndex : 0,
      subtitleFontSize: subtitleOn ? subtitleFontSize : null,
      subtitleAtBottom:
          subtitleOn ? _effectiveSubtitlePosition == 'bottom' : null,
      brightness: colorOn ? 0.12 * _toneStrength : 0,
      contrast: colorOn ? 0.08 * _toneStrength : 0,
    );
  }

  SubtitleStyle _subtitleStyleForSetup(
    SubtitleStyle mappedStyle,
    Map<String, bool> capabilities,
  ) {
    final options = _buildEditOptions(capabilities);
    final alignment = switch (_effectiveSubtitlePosition) {
      'top' => SubtitleAlignment.top,
      'middle' => SubtitleAlignment.middle,
      _ => SubtitleAlignment.bottom,
    };

    return SubtitleStyle(
      fontId: mappedStyle.fontId,
      fontWeight: mappedStyle.fontWeight,
      fontSize: options.subtitleFontSize ?? mappedStyle.fontSize,
      textColor: _subtitleHexColor(_subtitleColor),
      activeWordColor: mappedStyle.activeWordColor,
      outlineColor: _subtitleHexColor(_subtitleOutlineColor),
      outlineWidth: mappedStyle.outlineWidth,
      shadowColor: mappedStyle.shadowColor,
      shadowDepth: mappedStyle.shadowDepth,
      alignment: alignment,
      normalizedX: _subtitleNormalizedX,
      normalizedY: _subtitleNormalizedY,
      maxLines: mappedStyle.maxLines,
      animation: mappedStyle.animation,
    );
  }

  int get _subtitleWordsPerLine => subtitleWordLimitForStyle(
        subtitleStyle: _subtitleStyle,
        subtitleWords: _subtitleWords,
      );

  String get _effectiveSubtitlePosition => switch (_subtitleNormalizedY) {
        < 0.34 => 'top',
        < 0.67 => 'middle',
        _ => 'bottom',
      };

  BurnSubtitleAlignment _burnSubtitleAlignment(SubtitleAlignment alignment) =>
      switch (alignment) {
        SubtitleAlignment.top => BurnSubtitleAlignment.top,
        SubtitleAlignment.middle => BurnSubtitleAlignment.middle,
        SubtitleAlignment.bottom => BurnSubtitleAlignment.bottom,
      };

  String _subtitleFontAssetPath(SubtitleStyle style) {
    if (style.fontId == 'Bai Jamjuree') {
      return postDeeSubtitleThaiFontAssetPath;
    }
    final family = style.fontId == 'Anuphan' ? 'anuphan' : 'prompt';
    final familyName = family == 'anuphan' ? 'Anuphan' : 'Prompt';
    final weight = switch (style.fontWeight) {
      >= 900 when family == 'prompt' => 'Black',
      >= 800 when family == 'prompt' => 'ExtraBold',
      >= 700 => 'Bold',
      >= 600 => 'SemiBold',
      >= 500 => 'Medium',
      _ => 'Regular',
    };
    return 'assets/fonts/postdee_subtitle/'
        'PostDeeSubtitle$familyName-$weight.ttf';
  }

  String _subtitleRenderFontName(SubtitleStyle? style) {
    if (style == null || style.fontId == 'Bai Jamjuree') {
      return postDeeSubtitleThaiFontName;
    }
    return style.fontId == 'Anuphan'
        ? postDeeSubtitleAnuphanFontName
        : postDeeSubtitlePromptFontName;
  }

  _AiSetupSnapshot _captureSetupSnapshot() {
    return _AiSetupSnapshot(
      durationMode: _durationMode,
      customDurationSeconds: _customDurationSeconds,
      capabilities: Map<String, bool>.from(_capabilities),
      speechReductionSelectionMode: _speechReductionSelectionMode,
      subtitleStyle: _subtitleStyle,
      subtitleColor: _subtitleColor,
      subtitleOutlineColor: _subtitleOutlineColor,
      subtitleWords: _subtitleWords,
      subtitlePosition: _subtitlePosition,
      subtitleNormalizedX: _subtitleNormalizedX,
      subtitleNormalizedY: _subtitleNormalizedY,
      ctaText: _ctaController.text,
      ctaDesign: _ctaDesign,
      priceNowText: _priceNowController.text,
      priceBeforeText: _priceBeforeController.text,
      musicGenre: _musicGenre,
      musicVolume: _musicVolume,
      musicSource: _musicSource,
      pickedMusic: _pickedMusic,
      musicTrackId: _selectedMusicTrackId,
      beatIntensity: _beatIntensity,
      duckMusicDuringSpeech: _duckMusicDuringSpeech,
      confirmedMusicRights: _confirmedMusicRights,
      silencePreset: _silencePreset,
      toneFilter: _toneFilter,
      toneStrength: _toneStrength,
      zoomLevel: _zoomLevel,
      clipSpeed: _clipSpeed,
      translationLanguage: _translationLanguage,
    );
  }

  void _restoreSetupSnapshot(_AiSetupSnapshot snapshot) {
    _durationMode = snapshot.durationMode;
    _customDurationSeconds = snapshot.customDurationSeconds;
    _capabilities
      ..clear()
      ..addAll(snapshot.capabilities);
    _disableRetiredSetupCapabilities();
    _speechReductionSelectionMode = snapshot.speechReductionSelectionMode;
    _subtitleStyle = snapshot.subtitleStyle;
    _subtitleColor = snapshot.subtitleColor;
    _subtitleOutlineColor = snapshot.subtitleOutlineColor;
    _subtitleWords = snapshot.subtitleWords;
    _subtitlePosition = snapshot.subtitlePosition;
    _subtitleNormalizedX = snapshot.subtitleNormalizedX;
    _subtitleNormalizedY = snapshot.subtitleNormalizedY;
    _ctaController.text = snapshot.ctaText;
    _ctaDesign = snapshot.ctaDesign;
    _priceNowController.text = snapshot.priceNowText;
    _priceBeforeController.text = snapshot.priceBeforeText;
    _musicGenre = snapshot.musicGenre;
    _musicVolume = snapshot.musicVolume;
    _musicSource = snapshot.musicSource;
    _pickedMusic = snapshot.pickedMusic;
    _selectedMusicTrackId = snapshot.musicTrackId;
    _beatIntensity = snapshot.beatIntensity;
    _duckMusicDuringSpeech = snapshot.duckMusicDuringSpeech;
    _confirmedMusicRights = snapshot.confirmedMusicRights;
    _silencePreset = snapshot.silencePreset;
    _toneFilter = snapshot.toneFilter;
    _toneStrength = snapshot.toneStrength;
    _zoomLevel = snapshot.zoomLevel;
    _clipSpeed = snapshot.clipSpeed;
    _translationLanguage = snapshot.translationLanguage;
    _customDurationController.text = snapshot.customDurationSeconds.toString();
    _collapseAdvancedIfUnavailable();
  }

  void _syncSetupCapabilitiesFromReview() {
    for (final entry in _appliedReviewCapabilities.entries) {
      _capabilities[entry.key] = entry.value;
    }
    _disableRetiredSetupCapabilities();
    _collapseAdvancedIfUnavailable();
  }

  void _disableRetiredSetupCapabilities() {
    if (!widget.showRetiredCapabilitiesForTesting) {
      _capabilities['color'] = false;
    }
    _capabilities['audio'] = false;
    _capabilities['sfx'] = false;
  }

  String _friendlyAiError(ApiException error) {
    if (error.code == 'AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE') {
      return 'ยืนยันเวลาเสียงไม่ได้ กรุณาลองใหม่';
    }
    if (error.code == 'AI_TRANSCRIPTION_PROVIDER_FAILED') {
      return 'ระบบถอดเสียง AI ยังไม่พร้อม กรุณาลองใหม่อีกครั้ง';
    }
    if (error.statusCode == 402 || error.message.contains('Pro plan')) {
      return 'การตัดต่ออัตโนมัติต้องใช้แพ็กเกจ Pro';
    }
    if (error.message.contains('quota')) {
      return 'โควต้าตัดต่อด้วย AI เดือนนี้ไม่เพียงพอ';
    }
    return error.message;
  }

  int get _selectedDurationSeconds {
    return _selectedDurationSecondsFor(_selectedVideoDurationSeconds);
  }

  int _selectedDurationSecondsFor(double? sourceDurationSeconds) {
    final requested = switch (_durationMode) {
      _AiDurationMode.unselected => 0,
      _AiDurationMode.seconds30 => 30,
      _AiDurationMode.seconds60 => 60,
      _AiDurationMode.custom => _customDurationSeconds,
    };
    final sourceMaximum = _sourceDurationMaximumSecondsFor(
      sourceDurationSeconds,
    );
    if (sourceMaximum == null || requested <= 0) {
      return requested;
    }
    return requested.clamp(1, sourceMaximum);
  }

  bool get _hasSelectedDuration => _durationMode != _AiDurationMode.unselected;

  int? get _sourceDurationMaximumSeconds {
    return _sourceDurationMaximumSecondsFor(_selectedVideoDurationSeconds);
  }

  int? _sourceDurationMaximumSecondsFor(double? sourceDuration) {
    if (sourceDuration == null ||
        !sourceDuration.isFinite ||
        sourceDuration <= 0) {
      return null;
    }
    return math.max(1, sourceDuration.floor());
  }

  int _normalizeTargetDuration(int requested) {
    final sourceMaximum = _sourceDurationMaximumSeconds;
    if (sourceMaximum == null) return requested;
    final minimum = sourceMaximum >= 5 ? 5 : 1;
    if (requested >= sourceMaximum) return sourceMaximum;
    return requested.clamp(
      minimum,
      math.min(_maxAiShortenedDurationSeconds, sourceMaximum),
    );
  }

  bool get _usesOriginalDurationSliderStop =>
      (_sourceDurationMaximumSeconds ?? 0) > _maxAiShortenedDurationSeconds;

  bool get _isUsingOriginalDuration {
    return _isUsingOriginalDurationFor(_selectedVideoDurationSeconds);
  }

  bool _isUsingOriginalDurationFor(double? sourceDurationSeconds) {
    final sourceMaximum = _sourceDurationMaximumSecondsFor(
      sourceDurationSeconds,
    );
    return sourceMaximum != null &&
        _hasSelectedDuration &&
        _selectedDurationSecondsFor(sourceDurationSeconds) >= sourceMaximum;
  }

  double? get _durationSliderMaximum {
    final sourceMaximum = _sourceDurationMaximumSeconds;
    if (sourceMaximum == null) return null;
    return sourceMaximum > _maxAiShortenedDurationSeconds
        ? _originalDurationSliderStop
        : sourceMaximum.toDouble();
  }

  double _durationSliderMinimum(double maximum) => maximum >= 5 ? 5 : 1;

  double _durationSliderValue({
    required double minimum,
    required double maximum,
  }) {
    if (_usesOriginalDurationSliderStop && _isUsingOriginalDuration) {
      return maximum;
    }
    return _selectedDurationSeconds
        .clamp(
          minimum.round(),
          math.min(
            _maxAiShortenedDurationSeconds,
            _sourceDurationMaximumSeconds ?? _maxAiShortenedDurationSeconds,
          ),
        )
        .toDouble();
  }

  int _targetDurationForSliderValue(double value, double maximum) {
    if (_usesOriginalDurationSliderStop && value.round() >= maximum.round()) {
      return _sourceDurationMaximumSeconds!;
    }
    return _normalizeTargetDuration(value.round());
  }

  String _formatDurationSeconds(num seconds) => formatReviewVideoClock(
        Duration(seconds: math.max(0, seconds.floor())),
      );

  bool get _reviewIsDirty {
    final keys = {
      ..._reviewCapabilities.keys,
      ..._appliedReviewCapabilities.keys,
    };
    final capabilitiesChanged = keys.any(
      (key) =>
          (_reviewCapabilities[key] ?? false) !=
          (_appliedReviewCapabilities[key] ?? false),
    );
    return capabilitiesChanged ||
        !_sameStringSet(
          _reviewRemovedSpeechOccurrenceIds,
          _appliedRemovedSpeechOccurrenceIds,
        );
  }

  bool _sameStringSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  void _prepareReviewForResult(
    BurnedSubtitleResult result, {
    required PickedVideoFile sourceVideo,
  }) {
    final originalPath = sourceVideo.path;
    _reviewVideoDurations.removeWhere((path, _) => path != originalPath);
    _reviewVideoDurations.remove(result.file.path);
    _reviewVideoSource = ReviewVideoSource.ai;
    _reviewResultRevision++;
    _reviewPreviewLoading = true;
  }

  bool _isCurrentReviewVideo({
    required ReviewVideoSource source,
    required String path,
    required int revision,
  }) =>
      switch (source) {
        ReviewVideoSource.original => _activeSourceVideo?.path == path,
        ReviewVideoSource.ai => _renderedResult?.file.path == path &&
            _reviewResultRevision == revision,
      };

  void _rememberReviewVideoDuration({
    required ReviewVideoSource source,
    required String path,
    required int revision,
    required Duration duration,
  }) {
    if (!mounted || duration <= Duration.zero) {
      return;
    }

    final isCurrent = _isCurrentReviewVideo(
      source: source,
      path: path,
      revision: revision,
    );
    if (!isCurrent || _reviewVideoDurations[path] == duration) {
      return;
    }

    setState(() => _reviewVideoDurations[path] = duration);
  }

  void _setReviewPreviewLoading({
    required ReviewVideoSource source,
    required String path,
    required int revision,
    required bool isLoading,
  }) {
    if (!mounted ||
        !_isCurrentReviewVideo(
          source: source,
          path: path,
          revision: revision,
        ) ||
        _reviewPreviewLoading == isLoading) {
      return;
    }
    setState(() => _reviewPreviewLoading = isLoading);
  }

  Future<void> _updateReviewVideo() async {
    final recipe = _activeRecipe;
    final picked = _activeSourceVideo;
    if (recipe == null ||
        picked == null ||
        _processing ||
        _updatingReviewPreview ||
        !_reviewIsDirty) {
      return;
    }

    setState(() {
      _updatingReviewPreview = true;
      _renderProgress = null;
      _renderCancelRequested = false;
    });

    try {
      final requestedSpeechOccurrenceIds =
          widget.safetyFlags.automaticRepeatCutsEnabled
              ? Set<String>.from(_reviewRemovedSpeechOccurrenceIds)
              : <String>{};
      final rendered = await _renderPreparedRecipe(
        recipe: recipe,
        sourceVideo: picked,
        capabilities: Map<String, bool>.from(_reviewCapabilities),
        verifiedSilenceRanges: _verifiedSilenceRanges,
        renderProject: _subtitleProject,
        removedSpeechOccurrenceIds: requestedSpeechOccurrenceIds,
      );
      final result = rendered.video;
      final selectedSpeechOccurrenceIds =
          (_reviewCapabilities['filler'] ?? false)
              ? rendered.appliedSpeechOccurrenceIds
              : requestedSpeechOccurrenceIds;
      if (!mounted) {
        return;
      }
      setState(() {
        _renderedResult = result;
        _subtitleProject = _replaceProjectCutsAfterRender(
          _subtitleProject,
          rendered.appliedCutRanges,
        );
        _prepareReviewForResult(result, sourceVideo: picked);
        if (result.colorFilterSkipped) {
          _reviewCapabilities.remove('color');
        }
        _appliedReviewCapabilities
          ..clear()
          ..addAll(_reviewCapabilities);
        _appliedRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(selectedSpeechOccurrenceIds);
        _reviewRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(selectedSpeechOccurrenceIds);
        _boundaryEvidenceWarning = rendered.boundaryEvidenceWarning;
        _syncSetupCapabilitiesFromReview();
        _acceptedSetup = _captureSetupSnapshot();
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
    } on SubtitleBurnException catch (error) {
      if (mounted) {
        setState(() {
          _updatingReviewPreview = false;
          _renderProgress = null;
          _renderCancelRequested = false;
          _reviewCapabilities
            ..clear()
            ..addAll(_appliedReviewCapabilities);
          _reviewRemovedSpeechOccurrenceIds
            ..clear()
            ..addAll(_appliedRemovedSpeechOccurrenceIds);
        });
        _showError('${error.message} · ผลลัพธ์เดิมยังอยู่');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _updatingReviewPreview = false;
          _renderProgress = null;
          _renderCancelRequested = false;
          _reviewCapabilities
            ..clear()
            ..addAll(_appliedReviewCapabilities);
          _reviewRemovedSpeechOccurrenceIds
            ..clear()
            ..addAll(_appliedRemovedSpeechOccurrenceIds);
        });
        _showError('อัปเดตคลิปไม่สำเร็จ · ผลลัพธ์เดิมยังอยู่');
      }
    }
  }

  Future<void> _editReviewSubtitles() async {
    final recipe = _activeRecipe;
    final project = _subtitleProject;
    final picked = _activeSourceVideo;
    if (recipe == null ||
        project == null ||
        picked == null ||
        _processing ||
        _updatingReviewPreview) {
      return;
    }

    final edited = await _openSubtitleStudio(
      sourceFile: File(picked.path),
      initialProject: project,
    );
    if (!mounted || edited == null) return;
    validateSubtitleProject(edited);

    setState(() {
      _updatingReviewPreview = true;
      _renderProgress = null;
      _renderCancelRequested = false;
    });
    try {
      final requestedSpeechOccurrenceIds =
          widget.safetyFlags.automaticRepeatCutsEnabled
              ? Set<String>.from(_appliedRemovedSpeechOccurrenceIds)
              : <String>{};
      final rendered = await _renderPreparedRecipe(
        recipe: recipe,
        sourceVideo: picked,
        capabilities: Map<String, bool>.from(_appliedReviewCapabilities),
        verifiedSilenceRanges: _verifiedSilenceRanges,
        renderProject: edited,
        removedSpeechOccurrenceIds: requestedSpeechOccurrenceIds,
      );
      final result = rendered.video;
      final selectedSpeechOccurrenceIds =
          (_appliedReviewCapabilities['filler'] ?? false)
              ? rendered.appliedSpeechOccurrenceIds
              : requestedSpeechOccurrenceIds;
      if (!mounted) return;
      setState(() {
        _subtitleProject = _replaceProjectCutsAfterRender(
          edited,
          rendered.appliedCutRanges,
        );
        _renderedResult = result;
        _prepareReviewForResult(result, sourceVideo: picked);
        _appliedRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(selectedSpeechOccurrenceIds);
        _reviewRemovedSpeechOccurrenceIds
          ..clear()
          ..addAll(selectedSpeechOccurrenceIds);
        _boundaryEvidenceWarning = rendered.boundaryEvidenceWarning;
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
    } on SubtitleBurnException catch (error) {
      if (!mounted) return;
      setState(() {
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
      _showError('${error.message} • ผลลัพธ์เดิมยังอยู่');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
      _showError('อัปเดตซับไม่สำเร็จ • ผลลัพธ์เดิมยังอยู่');
    }
  }

  Future<void> _toggleReviewCapability(String id, bool enabled) async {
    if (_updatingReviewPreview ||
        (id == 'filler' && !widget.safetyFlags.automaticRepeatCutsEnabled) ||
        (id == 'silence' && !widget.safetyFlags.verifiedSilenceEnabled)) {
      return;
    }
    setState(() => _reviewCapabilities[id] = enabled);
    await _updateReviewVideo();
  }

  void _discardReviewChanges() {
    setState(() {
      _reviewCapabilities
        ..clear()
        ..addAll(_appliedReviewCapabilities);
      _reviewRemovedSpeechOccurrenceIds
        ..clear()
        ..addAll(_appliedRemovedSpeechOccurrenceIds);
    });
  }

  void _returnToSetup() {
    if (_processing || _updatingReviewPreview) {
      return;
    }
    setState(() {
      _selectedVideo = _activeSourceVideo;
      _selectedVideoDurationSeconds = _activeSourceDurationSeconds;
      _reviewCapabilities
        ..clear()
        ..addAll(_appliedReviewCapabilities);
      _reviewRemovedSpeechOccurrenceIds
        ..clear()
        ..addAll(_appliedRemovedSpeechOccurrenceIds);
      _syncSetupCapabilitiesFromReview();
      _acceptedSetup = _captureSetupSnapshot();
      _stage = _AiEditingStage.setup;
    });
  }

  Future<void> _openPostFlow(BurnedSubtitleResult previewResult) async {
    if (!mounted) {
      return;
    }

    var result = previewResult;
    final recipe = _activeRecipe;
    final picked = _activeSourceVideo;
    if (recipe != null && picked != null) {
      setState(() {
        _processing = true;
        _processingTitle = 'กำลังสร้างวิดีโอคุณภาพเต็ม...';
        _renderProgress = null;
        _renderCancelRequested = false;
      });

      try {
        final rendered = await _renderPreparedRecipe(
          recipe: recipe,
          sourceVideo: picked,
          capabilities: Map<String, bool>.from(_appliedReviewCapabilities),
          verifiedSilenceRanges: _verifiedSilenceRanges,
          renderProject: _subtitleProject,
          removedSpeechOccurrenceIds:
              widget.safetyFlags.automaticRepeatCutsEnabled
                  ? Set<String>.from(_appliedRemovedSpeechOccurrenceIds)
                  : <String>{},
          purpose: VideoRenderPurpose.export,
        );
        result = rendered.video;
        if (mounted) {
          setState(() {
            _subtitleProject = _replaceProjectCutsAfterRender(
              _subtitleProject,
              rendered.appliedCutRanges,
            );
          });
        }
      } on SubtitleBurnException catch (error) {
        _handleProcessingFailure(error.message);
        return;
      } catch (_) {
        _handleProcessingFailure(
          'สร้างวิดีโอคุณภาพเต็มไม่สำเร็จ กรุณาลองใหม่',
        );
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _processing = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'โพสต์คลิปที่ตัดแล้ว',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: DecoratedBox(
            decoration: AppTheme.screenBackground,
            child: UploaderScreen(
              initialVideoPath: result.file.path,
              initialVideoName: result.fileName,
              initialVideoSizeBytes: result.sizeBytes,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelActiveRender() async {
    final cancellation = _activeRenderCancellation;
    if (cancellation == null || _renderCancelRequested) {
      return;
    }
    setState(() {
      _renderCancelRequested = true;
      _processingTitle = 'กำลังยกเลิก...';
    });
    try {
      await cancellation.cancel();
    } catch (_) {
      if (mounted) {
        setState(() => _renderCancelRequested = false);
        _showError('ยกเลิกการสร้างวิดีโอไม่สำเร็จ');
      }
    }
  }

  void _showError(String message) {
    if (message == 'การตัดต่ออัตโนมัติต้องใช้แพ็กเกจ Pro') {
      _showProRequiredSheet();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showProRequiredSheet() async {
    final openPaywall = await showPostDeeStatusSheet(
      context,
      data: PostDeeStatusSheetData(
        icon: Icons.workspace_premium_outlined,
        iconColor: AppTheme.accentCyanInk,
        iconTint: AppTheme.mint,
        title: 'ปลดล็อก AI ตัดต่อด้วย Pro',
        body: 'AI ตัดต่ออัตโนมัติเป็นฟีเจอร์ของแพ็กเกจ Pro '
            'พร้อมโควตา 200 นาทีต่อเดือน ระบบจะตรวจสิทธิ์ก่อนอัปโหลดคลิปเสมอ',
        primaryLabel: 'ดูแพ็กเกจ Pro',
        secondaryLabel: 'ไว้ก่อน',
      ),
    );

    if (openPaywall == true && mounted) {
      final loadSubscription =
          widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => PaywallScreen(
            loadSubscription: loadSubscription,
          ),
        ),
      );
      if (mounted) {
        await _loadAiEditQuota();
      }
    }
  }

  void _handleBack() {
    if (_processing || _updatingReviewPreview) {
      return;
    }
    if (_stage == _AiEditingStage.review) {
      _returnToSetup();
      return;
    }

    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _savePreset() {
    final omittedPrivateMusic = _musicSource == _BeatMusicSource.device;
    setState(() {
      _presets.add(
        _AiPreset(
          name: 'ชุดที่ ${_presets.length + 1}',
          capabilities: Map<String, bool>.from(_capabilities),
          speechReductionSelectionMode: _speechReductionSelectionMode,
          subtitleStyle: _subtitleStyle,
          subtitleColor: _subtitleColor,
          subtitleOutlineColor: _subtitleOutlineColor,
          subtitleWords: _subtitleWords,
          subtitlePosition: _subtitlePosition,
          subtitleNormalizedX: _subtitleNormalizedX,
          subtitleNormalizedY: _subtitleNormalizedY,
          ctaDesign: _ctaDesign,
          musicGenre: _musicGenre,
          musicVolume: _musicVolume,
          musicSource: _musicSource == _BeatMusicSource.device
              ? _BeatMusicSource.original
              : _musicSource,
          musicTrackId: _selectedMusicTrackId,
          beatIntensity: _beatIntensity,
          duckMusicDuringSpeech: _duckMusicDuringSpeech,
          silencePreset: _silencePreset,
          toneFilter: _toneFilter,
          zoomLevel: _zoomLevel,
          clipSpeed: _clipSpeed,
        ),
      );
    });
    if (omittedPrivateMusic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'บันทึกชุดตั้งค่าแล้ว โดยไม่เก็บไฟล์เพลงส่วนตัวจากเครื่อง',
          ),
        ),
      );
    }
  }

  void _applyPreset(_AiPreset preset) {
    setState(() {
      _capabilities
        ..clear()
        ..addAll(preset.capabilities);
      _disableRetiredSetupCapabilities();
      _speechReductionSelectionMode = preset.speechReductionSelectionMode;
      _subtitleStyle = preset.subtitleStyle;
      _subtitleColor = preset.subtitleColor;
      _subtitleOutlineColor = preset.subtitleOutlineColor;
      _subtitleWords = preset.subtitleWords;
      _subtitlePosition = preset.subtitlePosition;
      _subtitleNormalizedX = preset.subtitleNormalizedX;
      _subtitleNormalizedY = preset.subtitleNormalizedY;
      _ctaDesign = preset.ctaDesign;
      _musicGenre = preset.musicGenre;
      _musicVolume = preset.musicVolume;
      _musicSource = preset.musicSource;
      _selectedMusicTrackId = preset.musicTrackId;
      _pickedMusic = null;
      _confirmedMusicRights = false;
      _beatIntensity = preset.beatIntensity;
      _duckMusicDuringSpeech = preset.duckMusicDuringSpeech;
      _silencePreset = preset.silencePreset;
      _toneFilter = preset.toneFilter;
      _zoomLevel = preset.zoomLevel;
      _clipSpeed = preset.clipSpeed;
      _collapseAdvancedIfUnavailable();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _stage == _AiEditingStage.review
                  ? _buildResultReview()
                  : _buildSetupList(),
            ),
            _buildStickyAction(),
          ],
        ),
        if (_processing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildSetupList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      children: [
        if (_selectedVideo == null)
          _AddVideoCard(
            onTap: _pickVideo,
            isLoading: _isPickingVideo,
          )
        else
          _buildSelectedVideoCard(_selectedVideo!),
        _buildDurationPrompt(),
        _sectionHeading(
          icon: Icons.auto_fix_high,
          title: 'ให้ AI จัดการให้',
          description: 'เริ่มต้นปิดทั้งหมด เลือกเปิดเฉพาะสิ่งที่ต้องการ',
        ),
        const SizedBox(height: 12),
        ..._buildCapabilityGroups(),
        const SizedBox(height: 18),
        _buildPresetCard(),
      ],
    );
  }

  Widget _buildResultReview() {
    final result = _renderedResult;
    if (result == null) {
      return Center(
        child: Text(
          'ยังไม่มีผลงาน AI ให้ตรวจ',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final selectedVideo = _activeSourceVideo;
    final originalFile =
        selectedVideo == null ? null : File(selectedVideo.path);
    final resultUsesOriginal = originalFile != null &&
        originalFile.existsSync() &&
        originalFile.path == result.file.path;
    final canCompare = originalFile != null &&
        originalFile.existsSync() &&
        !resultUsesOriginal;
    final selectedSource = resultUsesOriginal
        ? ReviewVideoSource.original
        : canCompare
            ? _reviewVideoSource
            : ReviewVideoSource.ai;
    final showingOriginal =
        resultUsesOriginal || selectedSource == ReviewVideoSource.original;
    final previewFile = showingOriginal ? originalFile! : result.file;
    final previewRevision = resultUsesOriginal
        ? _reviewResultRevision
        : showingOriginal
            ? 0
            : _reviewResultRevision;
    final previewSourceLabel = showingOriginal ? 'ต้นฉบับ' : 'ผล AI';
    final originalName = selectedVideo == null
        ? ''
        : selectedVideo.name.trim().isNotEmpty
            ? selectedVideo.name.trim()
            : _readFileNameFromPath(selectedVideo.path);
    final previewName = showingOriginal ? originalName : result.fileName;
    final previewSizeBytes = showingOriginal
        ? selectedVideo!.sizeBytes > 0
            ? selectedVideo.sizeBytes
            : originalFile!.lengthSync()
        : result.sizeBytes;
    final transcriptDurationSeconds =
        _activeRecipe?.transcript.durationSeconds ?? 0;
    final transcriptDuration = transcriptDurationSeconds > 0
        ? Duration(
            milliseconds: (transcriptDurationSeconds * 1000).round(),
          )
        : null;
    final originalDuration = selectedVideo == null
        ? null
        : _reviewVideoDurations[selectedVideo.path] ??
            (_activeSourceDurationSeconds == null
                ? transcriptDuration
                : Duration(
                    milliseconds:
                        (_activeSourceDurationSeconds! * 1000).round(),
                  ));
    final aiDuration = _reviewVideoDurations[result.file.path];
    final speechReduction = _activeRecipe?.speechReduction;
    final hasStructuredSpeechReduction = speechReduction != null &&
        speechReduction.isReady &&
        buildSpeechReductionReviewGroups(speechReduction).isNotEmpty;

    final appliedDefinitions = [
      for (final definition in _capabilityDefinitions)
        if ((definition.id != 'filler' || !hasStructuredSpeechReduction) &&
            _reviewCapabilities.containsKey(definition.id))
          definition,
    ];
    final notAppliedDefinitions = [
      for (final definition in _capabilityDefinitions)
        if (definition.id != 'silence' &&
            definition.id != 'filler' &&
            _isCapabilityEnabled(definition.id) &&
            !_reviewCapabilities.containsKey(definition.id))
          definition,
    ];

    return ListView(
      key: const ValueKey('ai-result-review'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.mint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resultUsesOriginal
                          ? 'คลิปนี้ไม่ต้องแก้เพิ่ม'
                          : 'AI ตัดต่อให้แล้ว',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resultUsesOriginal
                          ? 'ไม่พบช่วงที่ต้องเปลี่ยน จึงใช้ไฟล์ต้นฉบับ'
                          : 'ลองดูผลงาน แล้วปิดสิ่งที่ไม่ชอบได้ก่อนนำไปใช้',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _updatingReviewPreview ? null : _returnToSetup,
                child: const Text('ตั้งค่าใหม่'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (result.colorFilterSkipped) ...[
          Container(
            key: const ValueKey('ai-color-filter-skipped'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'อุปกรณ์นี้ไม่รองรับการปรับสี จึงข้ามเฉพาะโทนสี',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_boundaryEvidenceWarning != null) ...[
          Container(
            key: const ValueKey('ai-boundary-evidence-unavailable'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _boundaryEvidenceWarning!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_acceptedSilenceWasRequested &&
            _silenceVerificationUnavailable) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ยังยืนยันช่วงเงียบจากเสียงจริงไม่ได้ จึงยังไม่ตัดช่วงเงียบ',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('ai-silence-verification-retry'),
                  onPressed: _silenceRetryInProgress
                      ? null
                      : _retrySilenceVerification,
                  child: Text(
                    _silenceRetryInProgress ? 'กำลังตรวจ...' : 'ลองใหม่',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _cardDecoration(radius: 18),
          child: Column(
            children: [
              if (canCompare) ...[
                ReviewVideoCompareHeader(
                  selectedSource: selectedSource,
                  originalDuration: originalDuration,
                  aiDuration: aiDuration,
                  enabled: !_updatingReviewPreview && !_reviewPreviewLoading,
                  onSourceSelected: (source) {
                    if (_updatingReviewPreview ||
                        _reviewPreviewLoading ||
                        source == _reviewVideoSource) {
                      return;
                    }
                    setState(() {
                      _reviewVideoSource = source;
                      _reviewPreviewLoading = true;
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
              _ReviewVideoPreview(
                key: const ValueKey('ai-review-preview'),
                file: previewFile,
                revision: previewRevision,
                sourceLabel: previewSourceLabel,
                isUpdating: _updatingReviewPreview,
                controllerFactory: widget.reviewVideoControllerFactory,
                onLoadingChanged: (isLoading) {
                  _setReviewPreviewLoading(
                    source: selectedSource,
                    path: previewFile.path,
                    revision: previewRevision,
                    isLoading: isLoading,
                  );
                },
                onDurationReady: (duration) {
                  _rememberReviewVideoDuration(
                    source: selectedSource,
                    path: previewFile.path,
                    revision: previewRevision,
                    duration: duration,
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.movie_outlined,
                      size: 18, color: AppTheme.accentCyanInk),
                  const SizedBox(width: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      previewSourceLabel,
                      key: const ValueKey('ai-review-file-source'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentCyanInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      previewName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    _formatBytes(previewSizeBytes),
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildAnalysisSummary(),
        if (hasStructuredSpeechReduction) ...[
          const SizedBox(height: 12),
          _buildSpeechReductionReview(),
        ],
        if (_subtitleProject != null &&
            (_appliedReviewCapabilities['subtitle'] ?? false)) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('ai-review-edit-subtitles'),
            onPressed: _updatingReviewPreview || _reviewIsDirty
                ? null
                : _editReviewSubtitles,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: AppTheme.accentCyanInk,
              side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.subtitles_outlined, size: 19),
            label: const Text(
              'แก้ข้อความและรูปแบบซับ',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _sectionHeading(
          icon: Icons.auto_awesome,
          title: 'AI ทำอะไรให้แล้ว',
          description: 'เลือกสิ่งที่ต้องการเก็บหรือตัด แล้วกดอัปเดตคลิป',
        ),
        const SizedBox(height: 12),
        for (final definition in appliedDefinitions) ...[
          _buildReviewCapabilityCard(definition),
          const SizedBox(height: 9),
        ],
        if (_reviewIsDirty) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _updatingReviewPreview
                        ? 'กำลังสร้างพรีวิวใหม่จากวิดีโอต้นฉบับ...'
                        : 'มีการเปลี่ยนแปลงที่ยังไม่ได้ใช้',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (!_updatingReviewPreview)
                  TextButton(
                    onPressed: _discardReviewChanges,
                    child: const Text('ยกเลิก'),
                  ),
              ],
            ),
          ),
        ],
        if (notAppliedDefinitions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.glassDeep,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ฟังก์ชันที่ยังไม่ได้ใส่ในคลิปนี้',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'ระบบจะแสดงเป็น “ทำแล้ว” เฉพาะสิ่งที่ตัดต่อได้จริงเท่านั้น',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final definition in notAppliedDefinitions)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.glass,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          definition.title,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnalysisSummary() {
    final recipe = _activeRecipe;
    final acceptedCapabilities = _acceptedSetup?.capabilities ?? _capabilities;
    final silenceRequested = widget.safetyFlags.verifiedSilenceEnabled &&
        (acceptedCapabilities['silence'] ?? false);
    final repeatedSpeechRequested = acceptedCapabilities['filler'] ?? false;
    final silenceRanges =
        silenceRequested && _acceptedSilenceVerification.probeSucceeded
            ? _verifiedSilenceRanges
            : const <SilenceCutRange>[];
    final hasStructuredSpeechReduction = repeatedSpeechRequested &&
        recipe != null &&
        recipe.speechReduction.isReady &&
        buildSpeechReductionReviewGroups(recipe.speechReduction).isNotEmpty;
    final legacyRepeatedSpeechRanges = !repeatedSpeechRequested ||
            recipe == null ||
            hasStructuredSpeechReduction
        ? const <AiEditCut>[]
        : recipe.fillerRanges;
    final speechSummary = !hasStructuredSpeechReduction
        ? null
        : summarizeSpeechReductionSelection(
            recipe.speechReduction,
            _reviewRemovedSpeechOccurrenceIds,
          );
    final selectedRepeatedSpeechRanges =
        recipe == null || !(_reviewCapabilities['filler'] ?? false)
            ? const <AiEditCut>[]
            : hasStructuredSpeechReduction
                ? buildSpeechReductionCutRanges(
                    recipe.speechReduction,
                    _reviewRemovedSpeechOccurrenceIds,
                  )
                : legacyRepeatedSpeechRanges;
    final silenceStatus = !silenceRequested
        ? (text: 'ไม่ได้เลือก', isNotDetected: false)
        : _silenceVerificationUnavailable
            ? (text: 'ตรวจเสียงไม่สำเร็จ · ลองใหม่', isNotDetected: false)
            : silenceRanges.isNotEmpty
                ? (
                    text: 'พบ ${silenceRanges.length} ช่วง',
                    isNotDetected: false,
                  )
                : (
                    text: 'ตรวจแล้ว · ไม่พบช่วงเงียบที่ปลอดภัย',
                    isNotDetected: true,
                  );
    final speechUnavailableReason = hasStructuredSpeechReduction
        ? null
        : recipe?.speechReduction.unavailableReason;
    final fillerStatus = speechSummary != null && speechSummary.totalGroups > 0
        ? (
            text: 'พบ ${speechSummary.totalGroups} คำ · '
                'เลือกตัด ${speechSummary.selectedOccurrences} จุด',
            isNotDetected: false,
          )
        : legacyRepeatedSpeechRanges.isNotEmpty
            ? (
                text: 'พบ ${legacyRepeatedSpeechRanges.length} จุด · '
                    'เลือกตัด ${(_reviewCapabilities['filler'] ?? false) ? legacyRepeatedSpeechRanges.length : 0} จุด',
                isNotDetected: false,
              )
            : speechUnavailableReason != null
                ? (
                    text: speechUnavailableReason == 'unsupported-language'
                        ? 'ยังรองรับการตรวจอัตโนมัติเฉพาะภาษาไทย'
                        : 'ตรวจไม่ได้ · เวลาแต่ละคำไม่ชัดพอ',
                    isNotDetected: false,
                  )
                : _analysisDetectionStatus(
                    capabilityId: 'filler',
                    count: 0,
                    unit: 'คำ',
                  );
    final selectedCutSeconds = _mergedDetectedSeconds(
      [
        if (_reviewCapabilities['silence'] ?? false)
          for (final range in silenceRanges)
            AiEditCut(start: range.start, end: range.end),
        ...selectedRepeatedSpeechRanges,
      ],
      maxSeconds: recipe?.transcript.durationSeconds,
    );

    return Container(
      key: const ValueKey('ai-review-analysis-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 19, color: AppTheme.accentCyanInk),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'ผลการตรวจของ AI',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _analysisSummaryRow(
            key: ValueKey(
              silenceStatus.isNotDetected
                  ? 'ai-review-not-detected-silence'
                  : 'ai-review-analysis-silence-status',
            ),
            icon: Icons.content_cut,
            label: 'ช่วงเงียบ',
            value: silenceStatus.text,
          ),
          const SizedBox(height: 8),
          _analysisSummaryRow(
            key: ValueKey(
              fillerStatus.isNotDetected
                  ? 'ai-review-not-detected-repeated-speech'
                  : 'ai-review-analysis-repeated-speech-status',
            ),
            icon: Icons.voice_over_off_outlined,
            label: 'คำพูดซ้ำ',
            value: fillerStatus.text,
          ),
          const SizedBox(height: 10),
          Text(
            'เวลาที่จะตัดรวม ${_formatAnalysisSeconds(selectedCutSeconds)} วินาที',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentCyanInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ตัวเลขนี้เปลี่ยนตามช่วงเงียบและคำพูดซ้ำที่เลือกตัด ผลลัพธ์จริงอาจต่างเล็กน้อยเมื่อนำช่วงที่ติดกันมารวมกัน',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  ({String text, bool isNotDetected}) _analysisDetectionStatus({
    required String capabilityId,
    required int count,
    required String unit,
  }) {
    if (!(_capabilities[capabilityId] ?? false)) {
      return (text: 'ไม่ได้เลือก', isNotDetected: false);
    }
    if (count > 0) {
      return (text: 'พบ $count $unit', isNotDetected: false);
    }

    final status = _activeRecipe?.capabilities[capabilityId];
    if (status == null) {
      return (text: 'ไม่มีข้อมูลผลตรวจ', isNotDetected: false);
    }
    if (!status.enabled || status.state == 'skipped') {
      return (text: 'ไม่ได้เลือก', isNotDetected: false);
    }
    if (status.state == 'planned') {
      return (text: 'ยังไม่ได้ตรวจ', isNotDetected: false);
    }
    if (status.state == 'hinted' || status.state == 'applied') {
      return (text: 'ตรวจแล้ว · ไม่พบ', isNotDetected: true);
    }
    return (text: 'ไม่มีข้อมูลผลตรวจ', isNotDetected: false);
  }

  Widget _analysisSummaryRow({
    Key? key,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      key: key,
      children: [
        Icon(icon, size: 17, color: AppTheme.accentCyanInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeechReductionReview() {
    final recipe = _activeRecipe;
    if (recipe == null) return const SizedBox.shrink();
    final groups = buildSpeechReductionReviewGroups(recipe.speechReduction);
    if (groups.isEmpty) return const SizedBox.shrink();

    final repeatCutsEnabled = widget.safetyFlags.automaticRepeatCutsEnabled;
    final enabled =
        repeatCutsEnabled && (_reviewCapabilities['filler'] ?? false);
    final summary = summarizeSpeechReductionSelection(
      recipe.speechReduction,
      _reviewRemovedSpeechOccurrenceIds,
    );

    return Container(
      key: const ValueKey('ai-review-speech-reduction'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.record_voice_over_outlined, enabled: enabled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เลือกคำพูดซ้ำที่จะตัด',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'พบ ${summary.totalGroups} คำ · '
                      'เลือกตัด ${summary.selectedOccurrences} จุด',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                key: const ValueKey('ai-review-capability-filler'),
                value: enabled,
                onChanged: _updatingReviewPreview || !repeatCutsEnabled
                    ? null
                    : (value) {
                        if (value != null) {
                          unawaited(_toggleReviewCapability('filler', value));
                        }
                      },
                activeColor: AppTheme.accent,
                checkColor: Colors.white,
                side: BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!repeatCutsEnabled) ...[
            Container(
              key: const ValueKey('ai-repeat-read-only'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.glassDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderSoft),
              ),
              child: Text(
                'แสดงผลตรวจอย่างเดียวชั่วคราว · ระบบจะไม่ตัดคำพูดซ้ำ',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai
                ? 'AI เลือกตัดเฉพาะจุดที่พูดซ้ำติดกันและมั่นใจเรื่องเวลา '
                    'คุณเปลี่ยนแต่ละจุดเป็นเก็บไว้ได้'
                : 'AI ตรวจพบคำพูดซ้ำให้แล้ว แต่ยังไม่ตัดออก '
                    'เลือกแต่ละจุดที่ต้องการตัดแล้วกดอัปเดตคลิป',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.45,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (var groupIndex = 0;
              groupIndex < groups.length;
              groupIndex += 1) ...[
            if (groupIndex > 0) const SizedBox(height: 10),
            _buildSpeechReductionGroup(groups[groupIndex], enabled: enabled),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeechReductionGroup(
    SpeechReductionReviewGroup group, {
    required bool enabled,
  }) {
    final removable = group.occurrences
        .where((occurrence) => occurrence.canAutoRemove)
        .toList(growable: false);
    final selectedCount = removable
        .where(
          (occurrence) =>
              _reviewRemovedSpeechOccurrenceIds.contains(occurrence.id),
        )
        .length;

    return Container(
      key: ValueKey('ai-repeated-word-${group.id}'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.glassDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '“${group.text}” · พูด ${group.occurrences.length} ครั้ง',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (removable.isNotEmpty)
                Text(
                  'ตัด $selectedCount จุด',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
            ],
          ),
          if (removable.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'พบหลายครั้งแต่กระจายอยู่คนละประโยค ระบบจึงเก็บไว้ทั้งหมด',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
          ] else ...[
            const SizedBox(height: 7),
            Row(
              children: [
                TextButton(
                  key: ValueKey('ai-repeated-word-default-${group.id}'),
                  onPressed: !enabled || _updatingReviewPreview
                      ? null
                      : () => setState(() {
                            for (final occurrence in removable) {
                              if (occurrence.selectedByDefault) {
                                _reviewRemovedSpeechOccurrenceIds
                                    .add(occurrence.id);
                              } else {
                                _reviewRemovedSpeechOccurrenceIds
                                    .remove(occurrence.id);
                              }
                            }
                          }),
                  child: const Text('ใช้ที่ AI แนะนำ'),
                ),
                TextButton(
                  key: ValueKey('ai-repeated-word-keep-${group.id}'),
                  onPressed: !enabled || _updatingReviewPreview
                      ? null
                      : () => setState(() {
                            _reviewRemovedSpeechOccurrenceIds.removeAll(
                              removable.map((occurrence) => occurrence.id),
                            );
                          }),
                  child: const Text('เก็บทั้งหมด'),
                ),
              ],
            ),
            for (final occurrence in removable)
              _buildSpeechReductionOccurrence(
                occurrence,
                enabled: enabled,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeechReductionOccurrence(
    AiEditSpeechReductionOccurrenceResult occurrence, {
    required bool enabled,
  }) {
    final removed = _reviewRemovedSpeechOccurrenceIds.contains(occurrence.id);
    final context = [
      occurrence.contextBefore,
      occurrence.text,
      occurrence.contextAfter
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final reason =
        occurrence.kind == 'adjacent-phrase' ? 'วลีซ้ำติดกัน' : 'คำซ้ำติดกัน';

    return Container(
      key: ValueKey('ai-repeated-occurrence-${occurrence.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(9, 7, 4, 7),
      decoration: BoxDecoration(
        color: AppTheme.glass,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$reason · ${_formatDurationSeconds(occurrence.start)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (context.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    context,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            removed ? 'ตัด' : 'เก็บ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: removed ? AppTheme.accentCyanInk : AppTheme.textMuted,
            ),
          ),
          Checkbox(
            key: ValueKey('ai-repeated-remove-${occurrence.id}'),
            value: removed,
            onChanged: !enabled || _updatingReviewPreview
                ? null
                : (value) => setState(() {
                      if (value ?? false) {
                        _reviewRemovedSpeechOccurrenceIds.add(occurrence.id);
                      } else {
                        _reviewRemovedSpeechOccurrenceIds.remove(occurrence.id);
                      }
                    }),
            activeColor: AppTheme.accent,
            checkColor: Colors.white,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAnalysisSeconds(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  double _mergedDetectedSeconds(
    List<AiEditCut> ranges, {
    double? maxSeconds,
  }) {
    final upperBound =
        maxSeconds != null && maxSeconds > 0 ? maxSeconds : double.infinity;
    final normalized = <(double, double)>[];

    for (final range in ranges) {
      if (!range.start.isFinite || !range.end.isFinite) {
        continue;
      }
      final start = range.start.clamp(0, upperBound).toDouble();
      final end = range.end.clamp(0, upperBound).toDouble();
      if (end > start) {
        normalized.add((start, end));
      }
    }

    if (normalized.isEmpty) {
      return 0;
    }

    normalized.sort((a, b) => a.$1.compareTo(b.$1));
    var currentStart = normalized.first.$1;
    var currentEnd = normalized.first.$2;
    var total = 0.0;

    for (final range in normalized.skip(1)) {
      if (range.$1 <= currentEnd) {
        if (range.$2 > currentEnd) {
          currentEnd = range.$2;
        }
        continue;
      }
      total += currentEnd - currentStart;
      currentStart = range.$1;
      currentEnd = range.$2;
    }

    return total + currentEnd - currentStart;
  }

  Widget _buildReviewCapabilityCard(_AiCapabilityDefinition definition) {
    final enabled = _reviewCapabilities[definition.id] ?? false;
    final applied = _appliedReviewCapabilities[definition.id] ?? false;
    final status = switch ((enabled, applied)) {
      (true, true) => 'อยู่ในพรีวิว · เอาติ๊กออกเพื่อดูแบบไม่ใช้',
      (false, true) => 'กำลังนำออกและสร้างพรีวิวใหม่...',
      (true, false) => 'กำลังใส่กลับและสร้างพรีวิวใหม่...',
      (false, false) => 'นำออกจากพรีวิวแล้ว · ติ๊กเพื่อเอากลับ',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: enabled ? AppTheme.sel : AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          _iconBox(definition.icon, enabled: enabled),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Checkbox(
            key: ValueKey('ai-review-capability-${definition.id}'),
            value: enabled,
            onChanged: _updatingReviewPreview
                ? null
                : (value) async {
                    if (value != null) {
                      await _toggleReviewCapability(definition.id, value);
                    }
                  },
            activeColor: AppTheme.accent,
            checkColor: Colors.white,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaIndicator() {
    final quota = _aiEditQuota ?? _preparedEdit?.quota;
    final subscription = _aiEditSubscription;

    if (quota == null || subscription == null) {
      if (_aiEditQuotaLoadFailed || _aiEditSubscriptionLoadFailed) {
        return Material(
          key: const ValueKey('ai-edit-quota-indicator'),
          color: AppTheme.glassDeep,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => unawaited(_loadAiEditQuota()),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 15, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'โหลดนาทีใหม่',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Container(
        key: const ValueKey('ai-edit-quota-indicator'),
        width: 92,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.glassDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSoft),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (!subscription.isPro) {
      final planLabel = switch (subscription.plan.trim().toUpperCase()) {
        'BASIC' => 'Basic',
        'STARTER' => 'Starter',
        'PRO' => 'Pro',
        final value when value.isNotEmpty => value,
        _ => 'ไม่ทราบแพ็กเกจ',
      };

      return Semantics(
        label: 'แพ็กเกจ $planLabel AI ตัดต่อใช้ได้เฉพาะ Pro',
        button: true,
        child: Material(
          key: const ValueKey('ai-edit-quota-indicator'),
          color: AppTheme.glassDeep,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _isLoadingAiEditQuota
                ? null
                : () => unawaited(_loadAiEditQuota()),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'แพ็กเกจ $planLabel',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'AI ตัดต่อใช้ได้เฉพาะ Pro',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'เวลา AI คงเหลือ ${quota.remainingMinutes} นาที '
          'ใช้แล้ว ${quota.usedMinutes} จาก ${quota.limitMinutes} นาทีเดือนนี้',
      button: true,
      child: Material(
        key: const ValueKey('ai-edit-quota-indicator'),
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _isLoadingAiEditQuota
              ? null
              : () => unawaited(_loadAiEditQuota()),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'เหลือ ${quota.remainingMinutes} นาที',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentCyanInk,
                  ),
                ),
                Text(
                  'Pro · ใช้แล้ว ${quota.usedMinutes}/${quota.limitMinutes} นาที',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSoft)),
      ),
      child: Row(
        children: [
          Material(
            color: AppTheme.glassDeep,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: const ValueKey('ai-editing-back'),
              onTap: _processing || _updatingReviewPreview ? null : _handleBack,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.arrow_back,
                  size: 22,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'ตัดต่อด้วย AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildQuotaIndicator(),
        ],
      ),
    );
  }

  Widget _buildSelectedVideoCard(PickedVideoFile video) {
    final details = <String>[
      if ((video.width ?? 0) > 0 && (video.height ?? 0) > 0)
        '${video.width}×${video.height}',
      if ((video.durationSeconds ?? 0) > 0)
        'เวลา ${_formatDurationSeconds(video.durationSeconds!)}',
      _formatBytes(video.sizeBytes),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(radius: 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE7EFE9), Color(0xFFD6E3DA)],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.movie_outlined,
                    size: 24, color: Color(0xFF8FA197)),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '9:16',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.name.trim().isNotEmpty
                      ? video.name.trim()
                      : _readFileNameFromPath(video.path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details.join(' · '),
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppTheme.glassDeep,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const ValueKey('ai-remove-video'),
              onTap: () async {
                if (_processing || _updatingReviewPreview) {
                  return;
                }
                await _releaseCachedVisualProxy();
                if (!mounted) {
                  return;
                }
                setState(() {
                  _selectedVideo = null;
                  _selectedVideoDurationSeconds = null;
                  _durationMode = _AiDurationMode.unselected;
                  // Removing a pending source must not discard the accepted
                  // result that review/export still owns.
                  _stage = _AiEditingStage.setup;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 34,
                height: 34,
                child:
                    Icon(Icons.close, size: 19, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSection() {
    final maximum = _durationSliderMaximum;
    final sourceDuration = _selectedVideoDurationSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          icon: Icons.timer_outlined,
          title: 'ความยาวที่อยากได้',
          description:
              'ลากจุดบนเส้นจากขวาไปซ้าย เพื่อเลือกว่าจะให้ AI ย่อเหลือเท่าไร',
        ),
        const SizedBox(height: 12),
        if (maximum == null || sourceDuration == null)
          Container(
            key: const ValueKey('ai-duration-unavailable'),
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(radius: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'อ่านเวลาคลิปไม่สำเร็จ กรุณาเลือกคลิปใหม่อีกครั้ง',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Builder(
            builder: (context) {
              final minimum = _durationSliderMinimum(maximum);
              final target = _hasSelectedDuration
                  ? _selectedDurationSeconds
                  : _normalizeTargetDuration(_customDurationSeconds);
              final sliderValue = _durationSliderValue(
                minimum: minimum,
                maximum: maximum,
              );
              final divisions = maximum.round() - minimum.round();
              final sourceLabel = _formatDurationSeconds(sourceDuration);
              final targetLabel = _formatDurationSeconds(target);
              final usingOriginal = _isUsingOriginalDuration;
              final sourceMaximum = _sourceDurationMaximumSeconds!;
              final recommendedMaximum = math.min(60, sourceMaximum);

              return Container(
                key: const ValueKey('ai-duration-slider-card'),
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                decoration: _cardDecoration(radius: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ต้นฉบับ $sourceLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.mint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            usingOriginal
                                ? 'ไม่ย่อ · ต้นฉบับ $sourceLabel'
                                : 'ให้ AI ย่อเหลือ $targetLabel',
                            key: const ValueKey('ai-duration-selected-label'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accentCyanInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5,
                        activeTrackColor: AppTheme.accent,
                        inactiveTrackColor: AppTheme.borderSoft,
                        thumbColor: AppTheme.accent,
                        overlayColor: AppTheme.accent.withValues(alpha: 0.14),
                      ),
                      child: Slider(
                        key: const ValueKey('ai-duration-slider'),
                        min: minimum,
                        max: maximum,
                        divisions: divisions > 0 ? divisions : null,
                        value: sliderValue,
                        label: usingOriginal ? 'ไม่ย่อ' : targetLabel,
                        onChanged: divisions <= 0
                            ? null
                            : (value) {
                                final seconds = _targetDurationForSliderValue(
                                  value,
                                  maximum,
                                );
                                setState(() {
                                  _durationMode = _AiDurationMode.custom;
                                  _customDurationSeconds = seconds;
                                  _customDurationController.text =
                                      seconds.toString();
                                });
                              },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'สั้นสุด ${_formatDurationSeconds(minimum)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          'ไม่ย่อ $sourceLabel',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (_usesOriginalDurationSliderStop) ...[
                      const SizedBox(height: 7),
                      Text(
                        'เมื่อเลื่อนซ้าย AI ย่อได้สูงสุด 03:00',
                        key: const ValueKey('ai-duration-three-minute-hint'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                    if (sourceMaximum >= 30) ...[
                      const SizedBox(height: 7),
                      Text(
                        'ช่วงแนะนำ 00:30–${_formatDurationSeconds(recommendedMaximum)}',
                        key: const ValueKey(
                          'ai-duration-recommended-range',
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                    if (_usesOriginalDurationSliderStop && usingOriginal) ...[
                      const SizedBox(height: 7),
                      Text(
                        'ต้นฉบับเกิน 03:00 บางช่องทางอาจไม่รับเป็นคลิปสั้น',
                        key: const ValueKey(
                          'ai-duration-platform-warning',
                        ),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                    if (!_hasSelectedDuration) ...[
                      const SizedBox(height: 8),
                      Text(
                        'ลากจุดไปทางซ้ายเพื่อเลือกความยาวก่อนเริ่ม',
                        key: const ValueKey('ai-duration-required-message'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDurationPrompt() {
    if (_selectedVideo == null) {
      return const SizedBox(
        key: ValueKey('ai-duration-step-hidden'),
        height: 20,
      );
    }

    return Padding(
      key: const ValueKey('ai-duration-step'),
      padding: const EdgeInsets.only(top: 18, bottom: 20),
      child: _buildDurationSection(),
    );
  }

  List<Widget> _buildCapabilityGroups() {
    const labels = {
      _AiCapabilityGroup.pace: 'ตัดต่อ · จังหวะ',
      _AiCapabilityGroup.look: 'ภาพ · เสียง',
      _AiCapabilityGroup.sales: 'ซับ · การขาย',
    };

    return [
      for (final group in _capabilityGroupDisplayOrder) ...[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Text(
            labels[group]!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.48,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        for (final definition in _capabilityDefinitions.where(
          (item) =>
              item.group == group &&
              !_deferredCapabilityIds.contains(item.id) &&
              (widget.showRetiredCapabilitiesForTesting ||
                  !_retiredSetupCapabilityIds.contains(item.id)),
        )) ...[
          _buildCapabilityCard(definition),
          const SizedBox(height: 9),
        ],
        if (group != _capabilityGroupDisplayOrder.last)
          const SizedBox(height: 9),
      ],
    ];
  }

  Widget _buildCapabilityCard(_AiCapabilityDefinition definition) {
    final available = _isCapabilityAvailable(definition.id);
    final enabled = _isCapabilityEnabled(definition.id);
    final experimentalHookPreview =
        definition.id == 'hook' && widget.enableExperimentalAiHook;
    final hasDisclosure = definition.hasAdvancedSettings && available;
    final canExpand = hasDisclosure && enabled;
    final showAdvanced =
        canExpand && _expandedAdvancedCapabilityId == definition.id;
    final description = experimentalHookPreview
        ? 'โหมดทดสอบส่งคำขอแบบวางแผนเท่านั้น ยังไม่แก้คลิปจริง'
        : !available
            ? switch (definition.id) {
                'beatsync' => 'ระบบวิเคราะห์บีตและใส่เพลงลงคลิปจริงกำลังพัฒนา',
                'hook' => 'ระบบค้นหาช่วงเด่นและย้ายขึ้นต้นกำลังพัฒนา',
                'reframe' => 'ระบบครอปและติดตามวัตถุในคลิปจริงกำลังพัฒนา',
                'zoom' => 'ระบบวิเคราะห์จุดสำคัญและซูมลงในคลิปจริงกำลังพัฒนา',
                'audio' =>
                  'ระบบลดเสียงรบกวนและปรับเสียงพูดในคลิปจริงกำลังพัฒนา',
                'sfx' =>
                  'ระบบวิเคราะห์เหตุการณ์และใส่เอฟเฟกต์เสียงลงคลิปจริงกำลังพัฒนา',
                'translate' =>
                  'ระบบแปลและเรนเดอร์ซับหลายภาษาในคลิปจริงกำลังพัฒนา',
                'pricetag' =>
                  'ระบบตรวจราคาและเรนเดอร์ป้ายลงในคลิปจริงกำลังพัฒนา',
                'cta' => 'ระบบเรนเดอร์การ์ด CTA ลงในคลิปจริงกำลังพัฒนา',
                'watermark' =>
                  'ระบบเรนเดอร์ลายน้ำจากหน้านี้ลงในคลิปจริงกำลังพัฒนา',
                _ => definition.description,
              }
            : definition.description;
    final VoidCallback? onDisclosurePressed = canExpand
        ? () => setState(() {
              _expandedAdvancedCapabilityId =
                  showAdvanced ? null : definition.id;
            })
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: enabled ? AppTheme.sel : AppTheme.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? AppTheme.accent.withValues(alpha: 0.4)
              : AppTheme.border,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF122018).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                _iconBox(definition.icon, enabled: enabled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            definition.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (!available || experimentalHookPreview)
                            Container(
                              key: ValueKey(
                                'ai-capability-badge-${definition.id}',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                experimentalHookPreview
                                    ? 'ทดลอง'
                                    : 'เร็ว ๆ นี้',
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasDisclosure) ...[
                  const SizedBox(width: 2),
                  Semantics(
                    key: ValueKey(
                      'ai-advanced-disclosure-${definition.id}',
                    ),
                    button: true,
                    enabled: canExpand,
                    expanded: showAdvanced,
                    label: 'ตั้งค่า ${definition.title}',
                    onTap: onDisclosurePressed,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: showAdvanced ? 'ซ่อนการตั้งค่า' : 'ตั้งค่า',
                          onPressed: onDisclosurePressed,
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 180),
                            turns: showAdvanced ? 0.5 : 0,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 22,
                              color: canExpand
                                  ? AppTheme.textSecondary
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                _DesignSwitch(
                  key: ValueKey('ai-capability-${definition.id}'),
                  value: enabled,
                  semanticsLabel: definition.title,
                  onChanged: available
                      ? (value) {
                          setState(() {
                            _capabilities[definition.id] = value;
                            if (!value &&
                                _expandedAdvancedCapabilityId ==
                                    definition.id) {
                              _expandedAdvancedCapabilityId = null;
                            }
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (showAdvanced)
            Container(
              key: ValueKey('ai-advanced-${definition.id}'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 15),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.borderSoft)),
              ),
              child: _buildAdvancedPanel(definition.id),
            ),
        ],
      ),
    );
  }

  Widget _buildAdvancedPanel(String id) {
    return switch (id) {
      'silence' => _buildSilenceAdvanced(),
      'filler' => _buildSpeechReductionAdvanced(),
      'subtitle' => _buildSubtitleAdvanced(),
      'cta' => _buildCtaAdvanced(),
      'beatsync' => _buildBeatSyncAdvanced(),
      'audio' => _buildAudioAdvanced(),
      'pricetag' => _buildPriceAdvanced(),
      'color' => _buildToneAdvanced(),
      'zoom' => _buildZoomAdvanced(),
      'translate' => _buildTranslationAdvanced(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildSpeechReductionAdvanced() {
    return Column(
      key: const ValueKey('ai-speech-reduction-mode-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ใครเป็นคนเลือกคำที่จะตัด',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _choiceChip(
              key: const ValueKey('ai-speech-reduction-mode-ai'),
              label: 'AI เลือกให้',
              selected: _speechReductionSelectionMode ==
                  _SpeechReductionSelectionMode.ai,
              onTap: () => setState(() {
                _speechReductionSelectionMode =
                    _SpeechReductionSelectionMode.ai;
              }),
            ),
            _choiceChip(
              key: const ValueKey('ai-speech-reduction-mode-manual'),
              label: 'เลือกเอง',
              selected: _speechReductionSelectionMode ==
                  _SpeechReductionSelectionMode.manual,
              onTap: () => setState(() {
                _speechReductionSelectionMode =
                    _SpeechReductionSelectionMode.manual;
              }),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          _speechReductionSelectionMode == _SpeechReductionSelectionMode.ai
              ? 'ตัดจุดที่ AI มั่นใจให้ก่อน และแก้คืนภายหลังได้'
              : 'AI ตรวจหาอย่างเดียว ยังไม่ตัดจนกว่าคุณจะเลือก',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSilenceAdvanced() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _advancedLabel('ตัดช่วงเงียบเมื่อยาวตั้งแต่'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final option in const [
              ('natural', '1.0 วิ · ธรรมชาติ'),
              ('balanced', '0.6 วิ · สมดุล'),
              ('compact', '0.4 วิ · กระชับ'),
            ])
              _choiceChip(
                key: ValueKey('ai-silence-preset-${option.$1}'),
                label: option.$2,
                selected: _silencePreset == option.$1,
                onTap: () => setState(() => _silencePreset = option.$1),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'ตรวจซ้ำจากคลื่นเสียงในวิดีโอ และตัดเฉพาะช่วงที่ไม่ทับคำพูด',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.45,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitleAdvanced() {
    final previewText = switch (_subtitleWords) {
      'karaoke' => 'ลด',
      'full' => 'ลดแรง 50% ส่งฟรี วันนี้',
      _ => 'ลดแรง 50% วันนี้',
    };
    final previewFontSize = switch (_subtitleStyle) {
      'small' => 17.0,
      'medium' => 19.0,
      _ => 22.0,
    };
    final previewStyle = SubtitleStyle(
      fontId: SubtitleStyle.defaults.fontId,
      fontWeight: SubtitleStyle.defaults.fontWeight,
      fontSize: previewFontSize,
      textColor: _subtitleHexColor(_subtitleColor),
      activeWordColor: SubtitleStyle.defaults.activeWordColor,
      outlineColor: _subtitleHexColor(_subtitleOutlineColor),
      outlineWidth: SubtitleStyle.defaults.outlineWidth,
      shadowColor: SubtitleStyle.defaults.shadowColor,
      shadowDepth: SubtitleStyle.defaults.shadowDepth,
      alignment: switch (_effectiveSubtitlePosition) {
        'top' => SubtitleAlignment.top,
        'middle' => SubtitleAlignment.middle,
        _ => SubtitleAlignment.bottom,
      },
      normalizedX: _subtitleNormalizedX,
      normalizedY: _subtitleNormalizedY,
      maxLines: 1,
    );
    final picked = _selectedVideo;
    final displaySizeHint = picked?.width != null && picked?.height != null
        ? Size(picked!.width!.toDouble(), picked.height!.toDouble())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (picked != null)
          AiSubtitleFramePreview(
            key: ValueKey('ai-subtitle-frame-${picked.path}'),
            sourceFile: File(picked.path),
            sourceFingerprint:
                '${picked.path}|${picked.sizeBytes}|${picked.durationSeconds}',
            controllerFactory: widget.subtitleFrameControllerFactory,
            session: _subtitleFramePreviewSession,
            displaySizeHint: displaySizeHint,
            maxPreviewWidth: 240,
            maxPreviewHeight: 320,
            overlayBuilder: (context, displaySize, position) =>
                SubtitlePreviewOverlay(
              text: previewText,
              style: previewStyle,
              onPositionChanged: (normalized) {
                setState(() {
                  _subtitleNormalizedX = normalized.dx;
                  _subtitleNormalizedY = normalized.dy;
                  _subtitlePosition = _effectiveSubtitlePosition;
                });
              },
            ),
          )
        else
          const AspectRatio(
            aspectRatio: 9 / 16,
            child: ColoredBox(color: Color(0xFF07120D)),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            key: const ValueKey('ai-subtitle-position-reset'),
            onPressed: () {
              setState(() {
                _subtitleNormalizedX = 0.5;
                _subtitleNormalizedY = 0.88;
                _subtitlePosition = 'bottom';
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('รีเซ็ตตำแหน่ง'),
          ),
        ),
        Center(
          child: Text(
            'ลากข้อความบนภาพเพื่อวางตำแหน่งซับ',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        _advancedLabel('ขนาดตัวอักษร'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _choiceChip(
              key: const ValueKey('ai-subtitle-size-large'),
              label: 'ใหญ่',
              selected: _subtitleStyle == 'large',
              onTap: () => setState(() => _subtitleStyle = 'large'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-size-medium'),
              label: 'กลาง',
              selected: _subtitleStyle == 'medium',
              onTap: () => setState(() => _subtitleStyle = 'medium'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-size-small'),
              label: 'เล็ก',
              selected: _subtitleStyle == 'small',
              onTap: () => setState(() => _subtitleStyle = 'small'),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _subtitleColorChoices(
          label: 'สีข้อความ',
          keyPrefix: 'ai-subtitle-text-color',
          selected: _subtitleColor,
          colors: const [
            Colors.white,
            Color(0xFFFFF45C),
            Color(0xFF00E5A8),
            Color(0xFFFF6B6B),
            Color(0xFF60A5FA),
          ],
          onChanged: (color) => setState(() => _subtitleColor = color),
        ),
        const SizedBox(height: 13),
        _subtitleColorChoices(
          label: 'สีกรอบ',
          keyPrefix: 'ai-subtitle-outline-color',
          selected: _subtitleOutlineColor,
          colors: const [
            Colors.black,
            Colors.white,
            Color(0xFF052E21),
            Color(0xFF7C2D12),
            Color(0xFF1E3A8A),
          ],
          onChanged: (color) => setState(() => _subtitleOutlineColor = color),
        ),
        const SizedBox(height: 13),
        _advancedLabel('ความยาวต่อช่วงซับ'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-short'),
              label: 'คาราโอเกะ · 1 คำ',
              selected: _subtitleWords == 'karaoke',
              onTap: () => setState(() => _subtitleWords = 'karaoke'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-medium'),
              label: 'อ่านง่าย · สูงสุด 3 คำ',
              selected: _subtitleWords == 'few',
              onTap: () => setState(() => _subtitleWords = 'few'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-long'),
              label: 'เนื้อหาครบ · สูงสุด 5 คำ',
              selected: _subtitleWords == 'full',
              onTap: () => setState(() => _subtitleWords = 'full'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'AI อาจใช้คำน้อยกว่าที่เลือกเพื่อไม่ให้ซับล้นจอ และจะไม่ตัดกลางคำ',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 10.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _subtitleColorChoices({
    required String label,
    required String keyPrefix,
    required Color selected,
    required List<Color> colors,
    required ValueChanged<Color> onChanged,
  }) {
    const names = <int, String>{
      0xFFFFFFFF: 'ขาว',
      0xFF000000: 'ดำ',
      0xFFFFF45C: 'เหลือง',
      0xFF00E5A8: 'เขียวมิ้นต์',
      0xFFFF6B6B: 'แดง',
      0xFF60A5FA: 'ฟ้า',
      0xFF052E21: 'เขียวเข้ม',
      0xFF7C2D12: 'น้ำตาล',
      0xFF1E3A8A: 'น้ำเงินเข้ม',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _advancedLabel(label),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final color in colors)
              Semantics(
                key: ValueKey('$keyPrefix-${color.toARGB32()}'),
                button: true,
                selected: color.toARGB32() == selected.toARGB32(),
                onTap: () => onChanged(color),
                label:
                    '$label ${names[color.toARGB32()] ?? _subtitleHexColor(color)}',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => onChanged(color),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.toARGB32() == selected.toARGB32()
                              ? AppTheme.accent
                              : AppTheme.border,
                          width:
                              color.toARGB32() == selected.toARGB32() ? 3 : 1,
                        ),
                      ),
                      child: color.toARGB32() == selected.toARGB32()
                          ? Icon(
                              Icons.check_rounded,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCtaAdvanced() {
    final previewAlignment =
        _ctaDesign == 'bar' ? Alignment.bottomCenter : Alignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          child: Container(
            width: 104,
            height: 184,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            alignment: previewAlignment,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2A3B5B),
                  Color(0xFF12141C),
                  Color(0xFF050507)
                ],
                stops: [0, 0.55, 1],
              ),
            ),
            child: _ctaPreview(),
          ),
        ),
        const SizedBox(height: 14),
        _advancedLabel('ข้อความ CTA'),
        TextField(
          controller: _ctaController,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          decoration: _inputDecoration('เช่น กดตะกร้าสีส้มเลย!'),
        ),
        const SizedBox(height: 13),
        _advancedLabel('ดีไซน์การ์ด'),
        Wrap(
          spacing: 7,
          children: [
            for (final option in const [
              ('pop', 'ป็อปเด้ง'),
              ('bar', 'แถบล่าง'),
              ('sticker', 'สติกเกอร์'),
            ])
              _choiceChip(
                label: option.$2,
                selected: _ctaDesign == option.$1,
                onTap: () => setState(() => _ctaDesign = option.$1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _ctaPreview() {
    final text = _ctaController.text.trim().isEmpty
        ? 'กดตะกร้าเลย!'
        : _ctaController.text.trim();
    if (_ctaDesign == 'bar') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: AppTheme.accent,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
        ),
      );
    }
    if (_ctaDesign == 'sticker') {
      return Transform.rotate(
        angle: -0.08,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE14D),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C3A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildBeatSyncAdvanced() {
    const genres = [
      ('fun', Icons.celebration_outlined, 'สนุกสดใส'),
      ('chill', Icons.wb_sunny_outlined, 'ชิลๆ ละมุน'),
      ('lux', Icons.diamond_outlined, 'หรูพรีเมียม'),
      ('energetic', Icons.bolt, 'เร้าใจ'),
    ];
    final catalogReady = _licensedMusicCatalog.isNotEmpty;
    final hasSelectedAddedMusic = switch (_musicSource) {
      _BeatMusicSource.device => _pickedMusic != null,
      _BeatMusicSource.library => _licensedMusicCatalog.any(
          (track) => track.id == _selectedMusicTrackId,
        ),
      _BeatMusicSource.auto => catalogReady,
      _BeatMusicSource.original => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'เพลงสำหรับตัดตามบีต',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'เลือกแหล่งเสียงก่อน แล้วกำหนดสไตล์การตัดที่ต้องการ',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('ai-beatsync-experimental-note'),
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.science_outlined,
                size: 18,
                color: Color(0xFF92400E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ฟังก์ชันทดลอง • รอบนี้ระบบยังไม่ใส่เพลงและไม่ตัดตามบีตในคลิปผลลัพธ์',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _beatMusicSourceCard(
                  key: const ValueKey('ai-beatsync-source-ai'),
                  icon: Icons.auto_awesome,
                  title: 'AI เลือกให้',
                  subtitle:
                      catalogReady ? 'จากเพลงที่ตรวจสิทธิ์แล้ว' : 'เร็ว ๆ นี้',
                  selected: _musicSource == _BeatMusicSource.auto,
                  onTap: catalogReady
                      ? () => setState(
                            () => _musicSource = _BeatMusicSource.auto,
                          )
                      : null,
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _beatMusicSourceCard(
                  key: const ValueKey('ai-beatsync-source-catalog'),
                  icon: Icons.library_music_outlined,
                  title: 'คลัง PostDee',
                  subtitle: catalogReady ? 'เลือกเพลงเอง' : 'เร็ว ๆ นี้',
                  selected: _musicSource == _BeatMusicSource.library,
                  onTap: catalogReady
                      ? () => setState(
                            () => _musicSource = _BeatMusicSource.library,
                          )
                      : null,
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _beatMusicSourceCard(
                  key: const ValueKey('ai-beatsync-source-my-music'),
                  icon: Icons.audio_file_outlined,
                  title: 'อัปโหลดเพลงของฉัน',
                  subtitle: 'เลือกไฟล์เสียงจากเครื่อง',
                  selected: _musicSource == _BeatMusicSource.device,
                  onTap: () => setState(
                    () => _musicSource = _BeatMusicSource.device,
                  ),
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _beatMusicSourceCard(
                  key: const ValueKey('ai-beatsync-source-original'),
                  icon: Icons.graphic_eq,
                  title: 'ใช้เสียงจากวิดีโอ',
                  subtitle: 'ไม่เพิ่มเพลงใหม่',
                  selected: _musicSource == _BeatMusicSource.original,
                  onTap: () => setState(
                    () => _musicSource = _BeatMusicSource.original,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_musicSource == _BeatMusicSource.auto) ...[
          const SizedBox(height: 13),
          _advancedLabel('แนวเพลงที่อยากได้'),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in genres)
                  SizedBox(
                    width: (constraints.maxWidth - 8) / 2,
                    child: _optionCard(
                      icon: genre.$2,
                      label: genre.$3,
                      selected: _musicGenre == genre.$1,
                      onTap: () => setState(() => _musicGenre = genre.$1),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_musicSource == _BeatMusicSource.library) ...[
          const SizedBox(height: 13),
          _advancedLabel('เลือกเพลงจากคลัง'),
          for (final track in widget.musicCatalog) ...[
            _buildCatalogTrackCard(track),
            const SizedBox(height: 8),
          ],
        ],
        if (_musicSource == _BeatMusicSource.device) ...[
          const SizedBox(height: 13),
          OutlinedButton.icon(
            key: const ValueKey('ai-beatsync-music-picker'),
            onPressed: _pickBeatMusic,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              foregroundColor: AppTheme.textPrimary,
              side: BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.audio_file_outlined, size: 18),
            label: Text(
              _pickedMusic == null
                  ? 'เลือกไฟล์เพลงจากเครื่อง'
                  : 'เปลี่ยนไฟล์เพลง',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'รองรับ MP3, M4A และ WAV ขนาดไม่เกิน 50 MB',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          if (_pickedMusic != null) ...[
            const SizedBox(height: 9),
            Container(
              key: const ValueKey('ai-beatsync-music-file'),
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.music_note,
                      size: 19, color: AppTheme.accentCyanInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pickedMusic!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _formatBytes(_pickedMusic!.sizeBytes),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.glassDeep,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ฉันยืนยันว่ามีสิทธิ์ใช้และเผยแพร่เพลงนี้บนแพลตฟอร์มที่เลือก',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _DesignSwitch(
                  key: const ValueKey('ai-beatsync-rights-confirm'),
                  value: _confirmedMusicRights,
                  semanticsLabel: 'ยืนยันสิทธิ์เพลง',
                  onChanged: _pickedMusic == null
                      ? null
                      : (value) => setState(
                            () => _confirmedMusicRights = value,
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'ใช้เฉพาะเพลงที่คุณเป็นเจ้าของหรือได้รับอนุญาต '
            'และไม่รองรับเพลงจากแอปสตรีมมิงที่มีข้อจำกัด',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
        if (_musicSource == _BeatMusicSource.original) ...[
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('ai-beatsync-original-note'),
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.mint,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'รอบนี้จะใช้เสียงจากวิดีโอ โดยไม่เพิ่มเพลงใหม่',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _advancedLabel('สไตล์การตัด'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _choiceChip(
              key: const ValueKey('ai-beatsync-intensity-soft'),
              label: 'นุ่มนวล',
              selected: _beatIntensity == _BeatCutIntensity.smooth,
              onTap: () => setState(
                () => _beatIntensity = _BeatCutIntensity.smooth,
              ),
            ),
            _choiceChip(
              key: const ValueKey('ai-beatsync-intensity-balanced'),
              label: 'สมดุล',
              selected: _beatIntensity == _BeatCutIntensity.balanced,
              onTap: () => setState(
                () => _beatIntensity = _BeatCutIntensity.balanced,
              ),
            ),
            _choiceChip(
              key: const ValueKey('ai-beatsync-intensity-energetic'),
              label: 'เร้าใจ',
              selected: _beatIntensity == _BeatCutIntensity.energetic,
              onTap: () => setState(
                () => _beatIntensity = _BeatCutIntensity.energetic,
              ),
            ),
          ],
        ),
        if (hasSelectedAddedMusic) ...[
          const SizedBox(height: 14),
          _sliderHeader('ระดับเสียงเพลง', '${(_musicVolume * 100).round()}%'),
          Slider(
            key: const ValueKey('ai-beatsync-volume-slider'),
            value: _musicVolume,
            onChanged: (value) => setState(() => _musicVolume = value),
            activeColor: AppTheme.accent,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.glassDeep,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ลดเพลงขณะมีเสียงพูด',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'ช่วยให้ได้ยินเสียงพูดชัดขึ้น',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _DesignSwitch(
                  key: const ValueKey('ai-beatsync-duck-voice'),
                  value: _duckMusicDuringSpeech,
                  semanticsLabel: 'ลดเพลงขณะมีเสียงพูด',
                  onChanged: (value) => setState(
                    () => _duckMusicDuringSpeech = value,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _beatMusicSourceCard({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Semantics(
      key: key,
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppTheme.mint : AppTheme.glass,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 84),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  width: selected ? 2 : 1,
                  color: selected ? AppTheme.accent : AppTheme.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: enabled
                            ? AppTheme.accentCyanInk
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        selected
                            ? Icons.check_circle
                            : enabled
                                ? Icons.radio_button_unchecked
                                : Icons.lock_clock_outlined,
                        size: 16,
                        color: selected
                            ? AppTheme.accentCyanInk
                            : AppTheme.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogTrackCard(PostDeeMusicTrack track) {
    final usable = _isCatalogTrackUsable(track);
    final selected = usable && _selectedMusicTrackId == track.id;
    final platforms = track.supportedPlatforms.join(', ');
    final rightsText = usable
        ? 'ตรวจสอบสิทธิ์ครบทุกแพลตฟอร์ม • ${track.licenseLabel}'
        : track.rightsVerified
            ? 'สิทธิ์ยังไม่ครบทุกแพลตฟอร์ม • $platforms'
            : 'ยังไม่พร้อมใช้งาน • ${track.licenseLabel}';
    return Material(
      key: ValueKey('ai-beatsync-track-${track.id}'),
      color: selected ? AppTheme.mint : AppTheme.glassDeep,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: usable
            ? () => setState(() => _selectedMusicTrackId = track.id)
            : null,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                usable ? Icons.verified_outlined : Icons.lock_outline,
                size: 19,
                color: usable ? AppTheme.accentCyanInk : AppTheme.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.moodLabel} • ${track.bpm} BPM • ${track.durationSeconds} วิ',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rightsText,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: usable
                            ? AppTheme.accentCyanInk
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioAdvanced() {
    return Container(
      key: const ValueKey('ai-audio-advanced-note'),
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.glassDeep,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        'ส่วนนี้ใช้ปรับความชัดของเสียงพูดและลดเสียงรบกวน ไม่ใช้เลือกเพลงประกอบ',
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildPriceAdvanced() {
    final now = _priceNowController.text.trim().isEmpty
        ? '199'
        : _priceNowController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _advancedLabel('ราคาขาย (฿)'),
                  TextField(
                    controller: _priceNowController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: _inputDecoration('199'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _advancedLabel('ราคาก่อนลด (฿)'),
                  TextField(
                    controller: _priceBeforeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                        fontSize: 13.5, color: AppTheme.textSecondary),
                    decoration: _inputDecoration('ไม่บังคับ'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.glassDeep,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Icon(Icons.visibility_outlined,
                  size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text('แสดง:',
                  style:
                      TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
              const SizedBox(width: 8),
              if (_priceBeforeController.text.trim().isNotEmpty) ...[
                Text(
                  '฿${_priceBeforeController.text.trim()}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '฿$now',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF5C3A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToneAdvanced() {
    final toneColor = switch (_toneFilter) {
      'vivid' => const Color(0xFFFF5A3A),
      'warm' => const Color(0xFFFF8A3D),
      'cool' => const Color(0xFF40A9FF),
      'vintage' => const Color(0xFFA1662F),
      _ => Colors.white,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          child: Container(
            width: 104,
            height: 132,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A6FA5), Color(0xFFB98C5A)],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: toneColor.withValues(alpha: _toneStrength * 0.35),
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final option in const [
              ('bright', 'สดใส'),
              ('vivid', 'จัดจ้าน'),
              ('warm', 'อบอุ่น'),
              ('cool', 'เย็น'),
              ('vintage', 'วินเทจ'),
            ])
              _choiceChip(
                label: option.$2,
                selected: _toneFilter == option.$1,
                onTap: () => setState(() => _toneFilter = option.$1),
              ),
          ],
        ),
        const SizedBox(height: 13),
        _sliderHeader('ความเข้มโทน', '${(_toneStrength * 100).round()}%'),
        Slider(
          value: _toneStrength,
          onChanged: (value) => setState(() => _toneStrength = value),
          activeColor: AppTheme.accent,
        ),
      ],
    );
  }

  Widget _buildZoomAdvanced() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _advancedLabel('ความแรงซูม'),
        Wrap(
          spacing: 7,
          children: [
            for (final option in const [
              ('soft', 'เบา'),
              ('medium', 'กลาง'),
              ('strong', 'แรง'),
            ])
              _choiceChip(
                label: option.$2,
                selected: _zoomLevel == option.$1,
                onTap: () => setState(() => _zoomLevel = option.$1),
              ),
          ],
        ),
        const SizedBox(height: 13),
        _advancedLabel('ความเร็วคลิป'),
        Wrap(
          spacing: 7,
          children: [
            for (final speed in const [1.0, 1.25, 1.5, 2.0])
              _choiceChip(
                label: speed == 1 ? '1x' : '${speed}x',
                selected: _clipSpeed == speed,
                onTap: () => setState(() => _clipSpeed = speed),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTranslationAdvanced() {
    return Wrap(
      spacing: 7,
      children: [
        for (final option in const [
          ('en', 'อังกฤษ'),
          ('zh', 'จีน'),
          ('ja', 'ญี่ปุ่น'),
        ])
          _choiceChip(
            label: option.$2,
            selected: _translationLanguage == option.$1,
            onTap: () => setState(() => _translationLanguage = option.$1),
          ),
      ],
    );
  }

  Widget _buildPresetCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_outline,
                  size: 19, color: AppTheme.accentCyanInk),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'ชุดตั้งค่า (Preset)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _savePreset,
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.mint,
                  foregroundColor: AppTheme.accentCyanInk,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'บันทึกชุดนี้',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_presets.isEmpty)
            Text(
              'บันทึกการตั้งค่าทั้งหมดเป็นชุด แล้วเรียกใช้ซ้ำได้ในครั้งต่อไป',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppTheme.textMuted,
              ),
            )
          else
            for (var index = 0; index < _presets.length; index += 1) ...[
              if (index > 0) const SizedBox(height: 8),
              _buildPresetRow(_presets[index]),
            ],
        ],
      ),
    );
  }

  Widget _buildPresetRow(_AiPreset preset) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.glassDeep,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark_outline, size: 17, color: AppTheme.accentCyanInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              preset.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => _applyPreset(preset),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentCyanInk,
              side: BorderSide(color: AppTheme.accentCyanInk),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: const Text('ใช้',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => setState(() => _presets.remove(preset)),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.glass,
              minimumSize: const Size.square(30),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyAction() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(top: BorderSide(color: AppTheme.borderSoft)),
        ),
        child: _stage == _AiEditingStage.review
            ? _buildReviewActions()
            : _buildSetupAction(),
      ),
    );
  }

  Widget _buildSetupAction() {
    final hasVideo = _selectedVideo != null;
    final canProcess = hasVideo &&
        _hasSelectedDuration &&
        !_processing &&
        !_updatingReviewPreview;
    final usesPendingMusic = _isCapabilityEnabled('beatsync') &&
        _musicSource != _BeatMusicSource.original;
    final label = !hasVideo
        ? 'เพิ่มวิดีโอก่อน'
        : !_hasSelectedDuration
            ? 'เลือกความยาวก่อน'
            : usesPendingMusic
                ? 'ตัดต่อโดยยังไม่ใส่เพลง'
                : 'ให้ AI ตัดต่อให้เลย';
    return ElevatedButton(
      key: const ValueKey('ai-process-button'),
      onPressed: canProcess ? _processVideo : null,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: AppTheme.accent,
        disabledBackgroundColor: const Color(0xFFB7C6BC),
        foregroundColor: const Color(0xFF052E21),
        disabledForegroundColor: const Color(0xFF344039),
        elevation: canProcess ? 7 : 0,
        shadowColor: AppTheme.accent.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 21),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewActions() {
    if (_updatingReviewPreview) {
      final renderProgress = _renderProgress;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            key: const ValueKey('ai-review-preview-updating'),
            onPressed: null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              disabledBackgroundColor: AppTheme.glassDeep,
              disabledForegroundColor: AppTheme.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: renderProgress,
                strokeWidth: 2,
              ),
            ),
            label: Text(
              renderProgress != null && renderProgress >= 0.99
                  ? 'กำลังตรวจไฟล์วิดีโอ...'
                  : renderProgress == null
                      ? 'กำลังอัปเดตพรีวิว...'
                      : 'กำลังอัปเดตพรีวิว ${(renderProgress * 100).round()}%',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_activeRenderCancellation != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              key: const ValueKey('ai-review-render-cancel'),
              onPressed: _renderCancelRequested ? null : _cancelActiveRender,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(
                _renderCancelRequested ? 'กำลังยกเลิก...' : 'ยกเลิก',
              ),
            ),
          ],
        ],
      );
    }

    if (_reviewIsDirty) {
      return ElevatedButton.icon(
        key: const ValueKey('ai-review-update'),
        onPressed: _processing ? null : _updateReviewVideo,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text(
          'อัปเดตคลิป',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }

    final result = _renderedResult;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const ValueKey('ai-review-post'),
        onPressed: result == null ? null : () => _openPostFlow(result),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text(
          'ไปหน้าโพสต์',
          maxLines: 1,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    final renderProgress = _renderProgress;
    final activeCapabilities = _stage == _AiEditingStage.review
        ? _reviewCapabilities
        : _effectiveCapabilities;
    final selectedTasks = [
      'ย่อเหลือ ${_formatDurationSeconds(_selectedDurationSeconds)}',
      for (final definition in _capabilityDefinitions)
        if (definition.id != 'hook' &&
            (activeCapabilities[definition.id] ?? false))
          definition.title,
    ].join(' · ');

    return Positioned.fill(
      child: ColoredBox(
        color: AppTheme.pitchBlack,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    key: renderProgress == null
                        ? const ValueKey('ai-processing-spinner')
                        : const ValueKey('ai-render-progress'),
                    value: renderProgress,
                    strokeWidth: 5,
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.mint,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  renderProgress != null && renderProgress >= 0.99
                      ? 'กำลังตรวจไฟล์วิดีโอ...'
                      : _processingTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (renderProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(renderProgress * 100).round()}%',
                    key: const ValueKey('ai-render-progress-percent'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentCyanInk,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  selectedTasks,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'เสร็จแล้วจะกลับมาหน้าตรวจผลงานให้เลือกอีกครั้ง',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                if (_activeRenderCancellation != null) ...[
                  const SizedBox(height: 18),
                  TextButton.icon(
                    key: const ValueKey('ai-render-cancel'),
                    onPressed:
                        _renderCancelRequested ? null : _cancelActiveRender,
                    icon: const Icon(Icons.close_rounded),
                    label: Text(
                      _renderCancelRequested ? 'กำลังยกเลิก...' : 'ยกเลิก',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: AppTheme.accentCyanInk),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, {required bool enabled}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: enabled ? AppTheme.mint : AppTheme.glassDeep,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        size: 20,
        color: enabled ? AppTheme.accentCyanInk : AppTheme.textMuted,
      ),
    );
  }

  Widget _choiceChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      key: key,
      container: true,
      button: true,
      selected: selected,
      onTap: onTap,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppTheme.accent : AppTheme.glass,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? AppTheme.accent : AppTheme.border,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? const Color(0xFF052E21) : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.mint : AppTheme.glass,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? AppTheme.accent : AppTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color:
                      selected ? AppTheme.accentCyanInk : AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _advancedLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _sliderHeader(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentCyanInk,
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration({required double radius}) {
    return BoxDecoration(
      color: AppTheme.glass,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppTheme.border),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF122018).withValues(alpha: 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.textMuted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: AppTheme.pitchBlack,
      border: _inputBorder(),
      enabledBorder: _inputBorder(),
      focusedBorder: _inputBorder(color: AppTheme.accent),
    );
  }

  OutlineInputBorder _inputBorder({Color? color}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: color ?? AppTheme.border),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

class _AddVideoCard extends StatelessWidget {
  const _AddVideoCard({
    required this.onTap,
    required this.isLoading,
  });

  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isLoading ? 'กำลังอ่านวิดีโอ' : 'เพิ่มวิดีโอ',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('ai-add-video'),
          borderRadius: BorderRadius.circular(18),
          onTap: isLoading ? null : onTap,
          child: CustomPaint(
            foregroundPainter: _DashedRRectBorderPainter(
              color: AppTheme.accent.withValues(alpha: 0.5),
              radius: 18,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
              decoration: BoxDecoration(
                color: AppTheme.glass,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.accentCyanInk,
                            ),
                          )
                        : Icon(
                            Icons.video_call_outlined,
                            size: 29,
                            color: AppTheme.accentCyanInk,
                          ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    isLoading ? 'กำลังอ่านวิดีโอ...' : 'เพิ่มวิดีโอ',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isLoading
                        ? 'กำลังตรวจขนาดและรายละเอียดของคลิป'
                        : 'แตะเพื่อเลือกคลิปแนวตั้ง 9:16 ที่จะให้ AI ตัดต่อ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignSwitch extends StatelessWidget {
  const _DesignSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: onChanged != null,
      toggled: value,
      label: semanticsLabel,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 27,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? AppTheme.accent : AppTheme.track,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 21,
                  height: 21,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ReviewVideoLoadState { loading, ready, error }

class _ReviewVideoPreview extends StatefulWidget {
  const _ReviewVideoPreview({
    super.key,
    required this.file,
    required this.sourceLabel,
    this.revision = 0,
    this.isUpdating = false,
    this.controllerFactory,
    this.onLoadingChanged,
    this.onDurationReady,
  });

  final File file;
  final String sourceLabel;
  final int revision;
  final bool isUpdating;
  final ReviewVideoControllerFactory? controllerFactory;
  final ValueChanged<bool>? onLoadingChanged;
  final ValueChanged<Duration>? onDurationReady;

  @override
  State<_ReviewVideoPreview> createState() => _ReviewVideoPreviewState();
}

class _ReviewVideoPreviewState extends State<_ReviewVideoPreview> {
  static const _liveSeekThrottle = Duration(milliseconds: 120);

  VideoPlayerController? _controller;
  VideoPlayerController? _initializingController;
  _ReviewVideoLoadState _loadState = _ReviewVideoLoadState.loading;
  Duration? _dragPosition;
  Duration? _pendingLiveSeekPosition;
  Duration? _lastLiveSeekPosition;
  bool _resumeAfterSeek = false;
  bool _liveSeekDisabledForSession = false;
  Future<void>? _pauseForSeekFuture;
  Future<void>? _activeSeekFuture;
  Timer? _liveSeekTimer;
  double? _pendingNormalizedPosition;
  bool _playbackCommandInProgress = false;
  Future<void> _disposalBarrier = Future<void>.value();
  final List<VideoPlayerController> _controllersQueuedForDisposal = [];
  int _initializationVersion = 0;
  int _seekVersion = 0;

  bool get _ready => _loadState == _ReviewVideoLoadState.ready;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  @override
  void didUpdateWidget(covariant _ReviewVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final videoChanged = oldWidget.file.path != widget.file.path ||
        oldWidget.revision != widget.revision;
    if (videoChanged) {
      _replaceController();
      return;
    }

    if (!oldWidget.isUpdating && widget.isUpdating) {
      final controller = _controller;
      _resetSeekState();
      if (controller?.value.isPlaying ?? false) {
        unawaited(_pauseControllerSafely(controller!));
      }
    }
  }

  void _capturePlaybackPosition(VideoPlayerController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      _pendingNormalizedPosition = null;
      return;
    }

    final durationMilliseconds = controller.value.duration.inMilliseconds;
    _pendingNormalizedPosition = durationMilliseconds > 0
        ? (controller.value.position.inMilliseconds / durationMilliseconds)
            .clamp(0.0, 1.0)
        : 0;
  }

  void _replaceController() {
    final previousController = _controller;
    final initializingController = _initializingController;
    _capturePlaybackPosition(previousController);
    _controller = null;
    _initializingController = null;
    _loadState = _ReviewVideoLoadState.loading;
    final seekBarrier = _resetSeekState();
    _playbackCommandInProgress = false;
    _startInitialization(
      disposeFirst: [previousController, initializingController],
      waitForSeek: seekBarrier,
    );
  }

  void _startInitialization({
    Iterable<VideoPlayerController?> disposeFirst = const [],
    Future<void>? waitForSeek,
  }) {
    final initializationVersion = ++_initializationVersion;
    final disposalBarrier = _queueControllerDisposals(
      disposeFirst,
      waitForSeek: waitForSeek,
    );
    unawaited(
      _initializeAfterDisposals(initializationVersion, disposalBarrier),
    );
  }

  Future<void> _initializeAfterDisposals(
    int initializationVersion,
    Future<void> disposalBarrier,
  ) async {
    await disposalBarrier;
    if (!mounted || initializationVersion != _initializationVersion) {
      return;
    }

    VideoPlayerController? controller;
    try {
      controller = widget.controllerFactory?.call(widget.file) ??
          VideoPlayerController.file(widget.file);
      if (!mounted || initializationVersion != _initializationVersion) {
        unawaited(_queueControllerDisposals([controller]));
        return;
      }
      _initializingController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted || initializationVersion != _initializationVersion) {
        if (identical(_initializingController, controller)) {
          _initializingController = null;
        }
        unawaited(_queueControllerDisposals([controller]));
        return;
      }

      final duration = controller.value.duration;
      final normalizedPosition = _pendingNormalizedPosition;
      if (normalizedPosition != null && duration > Duration.zero) {
        final targetPosition = Duration(
          milliseconds: (duration.inMilliseconds * normalizedPosition).round(),
        );
        try {
          await controller.seekTo(targetPosition);
        } catch (_) {
          // A failed position restore must not hide an otherwise valid video.
        }
      }
      if (!mounted || initializationVersion != _initializationVersion) {
        if (identical(_initializingController, controller)) {
          _initializingController = null;
        }
        unawaited(_queueControllerDisposals([controller]));
        return;
      }

      _pendingNormalizedPosition = null;
      _initializingController = null;
      setState(() {
        _controller = controller;
        _loadState = _ReviewVideoLoadState.ready;
      });
      widget.onLoadingChanged?.call(false);
      if (duration > Duration.zero) {
        widget.onDurationReady?.call(duration);
      }
    } catch (_) {
      if (identical(_initializingController, controller)) {
        _initializingController = null;
      }
      if (mounted && initializationVersion == _initializationVersion) {
        setState(() {
          _controller = null;
          _loadState = _ReviewVideoLoadState.error;
        });
        widget.onLoadingChanged?.call(false);
      }
      if (controller != null) {
        unawaited(_queueControllerDisposals([controller]));
      }
    }
  }

  void _retry() {
    if (widget.isUpdating) {
      return;
    }
    final previousController = _controller;
    final initializingController = _initializingController;
    _capturePlaybackPosition(previousController);
    _controller = null;
    _initializingController = null;
    final seekBarrier = _resetSeekState();
    _playbackCommandInProgress = false;
    setState(() => _loadState = _ReviewVideoLoadState.loading);
    widget.onLoadingChanged?.call(true);
    _startInitialization(
      disposeFirst: [previousController, initializingController],
      waitForSeek: seekBarrier,
    );
  }

  @override
  void dispose() {
    _initializationVersion++;
    final seekBarrier = _resetSeekState();
    final controller = _controller;
    final initializingController = _initializingController;
    _controller = null;
    _initializingController = null;
    unawaited(
      _queueControllerDisposals(
        [controller, initializingController],
        waitForSeek: seekBarrier,
      ),
    );
    super.dispose();
  }

  Future<void> _queueControllerDisposals(
    Iterable<VideoPlayerController?> controllers, {
    Future<void>? waitForSeek,
  }) {
    final batch = <VideoPlayerController>[];
    for (final controller in controllers) {
      if (controller == null ||
          _controllersQueuedForDisposal.any(
            (queued) => identical(queued, controller),
          )) {
        continue;
      }
      _controllersQueuedForDisposal.add(controller);
      batch.add(controller);
    }

    final previousBarrier = _disposalBarrier;
    final nextBarrier = () async {
      await previousBarrier;
      if (waitForSeek != null) {
        try {
          await waitForSeek;
        } catch (_) {
          // A failed seek must not block release of the native player.
        }
      }
      for (final controller in batch) {
        await _disposeControllerSafely(controller);
        _controllersQueuedForDisposal.removeWhere(
          (queued) => identical(queued, controller),
        );
      }
    }();
    _disposalBarrier = nextBarrier;
    return nextBarrier;
  }

  Future<void>? _resetSeekState() {
    final activeSeek = _activeSeekFuture;
    _seekVersion++;
    _liveSeekTimer?.cancel();
    _liveSeekTimer = null;
    _dragPosition = null;
    _pendingLiveSeekPosition = null;
    _lastLiveSeekPosition = null;
    _resumeAfterSeek = false;
    _liveSeekDisabledForSession = false;
    _pauseForSeekFuture = null;
    return activeSeek;
  }

  Future<void> _disposeControllerSafely(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (_) {
      // Native video resources may already be released after a player error.
    }
  }

  Future<void> _pauseControllerSafely(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.pause();
    } catch (_) {
      // The controller may be replaced while a new preview is rendering.
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (!_ready ||
        controller == null ||
        widget.isUpdating ||
        _dragPosition != null ||
        _activeSeekFuture != null ||
        _playbackCommandInProgress) {
      return;
    }
    _playbackCommandInProgress = true;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
      if (mounted && identical(_controller, controller)) {
        setState(() {});
      }
    } catch (_) {
      // A transient play/pause command failure does not mean the file is bad.
    } finally {
      if (identical(_controller, controller)) {
        _playbackCommandInProgress = false;
      }
    }
  }

  bool get _appIsResumed {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed;
  }

  void _handleSeekStart(Duration position) {
    final controller = _controller;
    if (!_ready || controller == null || widget.isUpdating) {
      return;
    }

    _seekVersion++;
    _liveSeekTimer?.cancel();
    _liveSeekTimer = null;
    _pendingLiveSeekPosition = null;
    _lastLiveSeekPosition = null;
    _liveSeekDisabledForSession = false;
    _resumeAfterSeek = controller.value.isPlaying;
    _pauseForSeekFuture = _resumeAfterSeek
        ? _pauseControllerSafely(controller)
        : Future<void>.value();
    setState(() => _dragPosition = position);
  }

  void _handleSeekChanged(Duration position) {
    final controller = _controller;
    if (!_ready || controller == null || widget.isUpdating) {
      return;
    }

    setState(() => _dragPosition = position);
    _queueLiveSeek(
      controller: controller,
      position: position,
      seekVersion: _seekVersion,
    );
  }

  void _queueLiveSeek({
    required VideoPlayerController controller,
    required Duration position,
    required int seekVersion,
  }) {
    if (_liveSeekDisabledForSession) {
      return;
    }

    _pendingLiveSeekPosition = position;
    if (_activeSeekFuture != null || _liveSeekTimer != null) {
      return;
    }
    _startPendingLiveSeek(controller, seekVersion);
  }

  void _startPendingLiveSeek(
    VideoPlayerController controller,
    int seekVersion,
  ) {
    final position = _pendingLiveSeekPosition;
    if (position == null ||
        !_canContinueSeek(controller, seekVersion) ||
        _liveSeekDisabledForSession) {
      return;
    }

    _pendingLiveSeekPosition = null;
    final pauseForSeek = _pauseForSeekFuture;
    late final Future<void> operation;
    operation = () async {
      try {
        await pauseForSeek;
        if (!_canContinueSeek(controller, seekVersion)) {
          return;
        }
        await controller.seekTo(position);
        if (_canContinueSeek(controller, seekVersion)) {
          _lastLiveSeekPosition = position;
        }
      } catch (_) {
        if (_canContinueSeek(controller, seekVersion)) {
          _liveSeekDisabledForSession = true;
          _pendingLiveSeekPosition = null;
        }
      }
    }();
    _activeSeekFuture = operation;

    unawaited(
      operation.whenComplete(() {
        if (identical(_activeSeekFuture, operation)) {
          _activeSeekFuture = null;
        }
        if (!_canContinueSeek(controller, seekVersion) ||
            _liveSeekDisabledForSession) {
          return;
        }
        _liveSeekTimer?.cancel();
        _liveSeekTimer = Timer(_liveSeekThrottle, () {
          _liveSeekTimer = null;
          _startPendingLiveSeek(controller, seekVersion);
        });
      }),
    );
  }

  bool _canContinueSeek(
    VideoPlayerController controller,
    int seekVersion,
  ) {
    return mounted &&
        _ready &&
        identical(_controller, controller) &&
        seekVersion == _seekVersion &&
        !widget.isUpdating &&
        _appIsResumed;
  }

  Future<void> _handleSeekEnd(Duration position) {
    final controller = _controller;
    if (!_ready || controller == null || widget.isUpdating) {
      return Future<void>.value();
    }

    final liveSeek = _activeSeekFuture;
    final seekVersion = ++_seekVersion;
    final shouldResume = _resumeAfterSeek && !widget.isUpdating;
    final pauseForSeekFuture = _pauseForSeekFuture;
    final lastLiveSeekPosition = _lastLiveSeekPosition;
    _liveSeekTimer?.cancel();
    _liveSeekTimer = null;
    _pendingLiveSeekPosition = null;

    late final Future<void> operation;
    operation = () async {
      try {
        await pauseForSeekFuture;
        await liveSeek;
        if (!_canContinueSeek(controller, seekVersion)) {
          return;
        }

        if (lastLiveSeekPosition != position) {
          await controller.seekTo(position);
        }
        if (!_canContinueSeek(controller, seekVersion)) {
          return;
        }

        if (shouldResume) {
          await controller.play();
          if (!_canContinueSeek(controller, seekVersion)) {
            await _pauseControllerSafely(controller);
          }
        }
      } catch (_) {
        // Keep the last valid preview if only a seek command fails.
      } finally {
        if (mounted &&
            identical(_controller, controller) &&
            seekVersion == _seekVersion) {
          setState(() {
            _resetSeekState();
          });
        }
      }
    }();
    _activeSeekFuture = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_activeSeekFuture, operation)) {
          _activeSeekFuture = null;
        }
      }),
    );
    return operation;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_ready && controller != null) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) => _buildPreview(controller, value),
      );
    }
    return _buildPreview(controller, controller?.value);
  }

  Widget _buildPreview(
    VideoPlayerController? controller,
    VideoPlayerValue? value,
  ) {
    final hasRuntimeError = value?.hasError ?? false;
    final isError =
        _loadState == _ReviewVideoLoadState.error || hasRuntimeError;
    final isReady = _ready &&
        !isError &&
        controller != null &&
        value != null &&
        value.isInitialized;
    final isPlaying = isReady && value.isPlaying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: isReady,
          enabled: isReady && !widget.isUpdating,
          label: isReady
              ? isPlaying
                  ? 'หยุดวิดีโอ'
                  : 'เล่นวิดีโอ'
              : null,
          child: GestureDetector(
            key: const ValueKey('ai-review-video-preview'),
            onTap: isReady && !widget.isUpdating ? _togglePlayback : null,
            child: Container(
              width: double.infinity,
              height: 310,
              decoration: BoxDecoration(
                color: const Color(0xFF050806),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isReady)
                    Center(
                      child: AspectRatio(
                        aspectRatio:
                            value.aspectRatio > 0 ? value.aspectRatio : 9 / 16,
                        child: VideoPlayer(controller),
                      ),
                    )
                  else if (isError)
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        key: const ValueKey('ai-review-video-error'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 42,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'เปิด${widget.sourceLabel} ไม่ได้',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ไฟล์ยังอยู่ ลองเปิดพรีวิวอีกครั้งได้',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const ValueKey('ai-review-video-retry'),
                            onPressed: widget.isUpdating ? null : _retry,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    )
                  else
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        key: const ValueKey('ai-review-video-loading'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.hourglass_top_rounded,
                            size: 36,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'กำลังเปิด${widget.sourceLabel}...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isReady)
                    AnimatedOpacity(
                      opacity: isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (isReady && value.isBuffering)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  if (widget.isUpdating)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.72),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'กำลังสร้างพรีวิวใหม่...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'พรีวิวเดิมจะยังอยู่จนกว่าจะเสร็จ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (isReady)
          ReviewVideoTimeline(
            position: _dragPosition ?? value.position,
            duration: value.duration,
            enabled: !widget.isUpdating,
            onSeekStart: _handleSeekStart,
            onSeekChanged: _handleSeekChanged,
            onSeekEnd: _handleSeekEnd,
          ),
      ],
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1.5;

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
