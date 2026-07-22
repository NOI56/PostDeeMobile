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
import 'ai_edit_media_strategy.dart';
import 'ai_edit_visual_proxy_extractor.dart';
import 'beat_music_picker.dart';
import 'edit_styles.dart';
import 'review_video_timeline.dart';
import 'style_options.dart';
import 'subtitle_burn_video_processor.dart';
import 'subtitle_studio/subtitle_draft_store.dart';
import 'subtitle_studio/subtitle_project.dart';
import 'subtitle_studio/subtitle_project_identity.dart';
import 'subtitle_studio/subtitle_project_mapper.dart';
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
typedef AiEditAudioCleanup = Future<void> Function(String audioS3Key);
typedef AiEditVisualProxyExtraction = Future<AiEditVisualProxyArtifact>
    Function(File source);
typedef AiEditVisualProxyCleanup = Future<void> Function(
  String visualProxyS3Key,
);
typedef AiVideoRenderer = Future<BurnedSubtitleResult> Function(
  BurnSubtitleRequest request,
);
typedef EditorSubscriptionLoader = Future<SubscriptionStatusResult> Function();
typedef AiEditQuotaLoader = Future<AiEditQuota> Function();
typedef ReviewVideoControllerFactory = VideoPlayerController Function(
  File file,
);
typedef SubtitleStudioLauncher = Future<SubtitleProject?> Function(
  BuildContext context,
  File sourceFile,
  SubtitleProject initialProject,
  SubtitleDraftStore draftStore,
);

enum _AiDurationMode { unselected, seconds30, seconds60, custom }

enum _AiEditingStage { setup, review }

const _maxAiEditSourceDurationSeconds = 600;
const _maxAiShortenedDurationSeconds = 180;
const _originalDurationSliderStop = 181.0;

enum _AiCapabilityGroup { pace, look, sales }

const _capabilityGroupDisplayOrder = <_AiCapabilityGroup>[
  _AiCapabilityGroup.sales,
  _AiCapabilityGroup.pace,
  _AiCapabilityGroup.look,
];

enum _BeatMusicSource { auto, library, device, original }

enum _BeatCutIntensity { smooth, balanced, energetic }

const _fillerWordOptions = <String>[
  'เอ่อ',
  'อ่า',
  'แบบว่า',
  'คือว่า',
  'ประมาณว่า',
];

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
    title: 'ตัดคำฟุ่มเฟือย',
    description: 'ตัดคำที่เลือกเมื่อพบพร้อมเวลาในคำถอดเสียง',
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

class _AiPreset {
  _AiPreset({
    required this.name,
    required this.capabilities,
    required this.subtitleStyle,
    required this.subtitleColor,
    required this.subtitleWords,
    required this.subtitlePosition,
    required this.ctaDesign,
    required this.musicGenre,
    required this.musicVolume,
    required this.musicSource,
    required this.musicTrackId,
    required this.beatIntensity,
    required this.duckMusicDuringSpeech,
    required this.silencePreset,
    required this.fillerWords,
    required this.toneFilter,
    required this.zoomLevel,
    required this.clipSpeed,
  });

  final String name;
  final Map<String, bool> capabilities;
  final String subtitleStyle;
  final Color subtitleColor;
  final String subtitleWords;
  final String subtitlePosition;
  final String ctaDesign;
  final String musicGenre;
  final double musicVolume;
  final _BeatMusicSource musicSource;
  final String? musicTrackId;
  final _BeatCutIntensity beatIntensity;
  final bool duckMusicDuringSpeech;
  final String silencePreset;
  final Set<String> fillerWords;
  final String toneFilter;
  final String zoomLevel;
  final double clipSpeed;
}

class _AiSetupSnapshot {
  const _AiSetupSnapshot({
    required this.durationMode,
    required this.customDurationSeconds,
    required this.capabilities,
    required this.subtitleStyle,
    required this.subtitleColor,
    required this.subtitleWords,
    required this.subtitlePosition,
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
    required this.fillerWords,
    required this.toneFilter,
    required this.toneStrength,
    required this.zoomLevel,
    required this.clipSpeed,
    required this.translationLanguage,
  });

  final _AiDurationMode durationMode;
  final int customDurationSeconds;
  final Map<String, bool> capabilities;
  final String subtitleStyle;
  final Color subtitleColor;
  final String subtitleWords;
  final String subtitlePosition;
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
  final Set<String> fillerWords;
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
    this.cleanupAiEditAudio,
    this.extractVisualProxy,
    this.cleanupAiEditVisualProxy,
    this.loadSubscription,
    this.loadAiEditQuota,
    this.initialTargetDurationSeconds = 30,
    this.burnVideo,
    this.pickMusic,
    this.musicCatalog = const [],
    this.enableExperimentalBeatSync = AppConfig.enableExperimentalBeatSync,
    this.enableExperimentalAiHook = AppConfig.enableExperimentalAiHook,
    this.reviewVideoControllerFactory,
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
  final AiEditAudioCleanup? cleanupAiEditAudio;
  final AiEditVisualProxyExtraction? extractVisualProxy;
  final AiEditVisualProxyCleanup? cleanupAiEditVisualProxy;
  final EditorSubscriptionLoader? loadSubscription;
  final AiEditQuotaLoader? loadAiEditQuota;
  final int? initialTargetDurationSeconds;
  final AiVideoRenderer? burnVideo;
  final BeatMusicPicker? pickMusic;
  final List<PostDeeMusicTrack> musicCatalog;
  final bool enableExperimentalBeatSync;
  final bool enableExperimentalAiHook;
  final ReviewVideoControllerFactory? reviewVideoControllerFactory;
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
  AiEditPrepareResult? _preparedEdit;
  SubtitleProject? _subtitleProject;
  SubtitleDraftStore? _resolvedSubtitleDraftStore;
  BurnedSubtitleResult? _renderedResult;
  _AiSetupSnapshot? _acceptedSetup;
  final Map<String, AiEditPrepareResult> _preparedEditsBySignature = {};
  final Map<String, AiEditPrepareResult> _preparedEditsByAnalysisSignature = {};
  final Map<String, BurnedSubtitleResult> _renderResultsBySignature = {};
  _AiEditingStage _stage = _AiEditingStage.setup;
  final Map<String, bool> _reviewCapabilities = {};
  final Map<String, bool> _appliedReviewCapabilities = {};
  final Map<String, Duration> _reviewVideoDurations = {};
  ReviewVideoSource _reviewVideoSource = ReviewVideoSource.ai;
  int _reviewResultRevision = 0;
  String? _expandedAdvancedCapabilityId;
  bool _processing = false;
  bool _updatingReviewPreview = false;
  bool _reviewPreviewLoading = false;
  bool _isPickingVideo = false;
  bool _isLoadingAiEditQuota = false;
  bool _aiEditQuotaLoadFailed = false;
  AiEditQuota? _aiEditQuota;
  String _processingTitle = 'AI กำลังวิเคราะห์คลิป...';
  double? _renderProgress;
  RenderCancellationToken? _activeRenderCancellation;
  bool _renderCancelRequested = false;
  _AiDurationMode _durationMode = _AiDurationMode.unselected;
  int _customDurationSeconds = 45;

  final Map<String, bool> _capabilities = {
    'subtitle': true,
    'silence': true,
    'filler': true,
    'hook': false,
    'beatsync': false,
    'zoom': false,
    'reframe': false,
    'color': true,
    'audio': false,
    'translate': false,
    'pricetag': false,
    'cta': false,
    'watermark': false,
  };

  String _subtitleStyle = 'large';
  Color _subtitleColor = Colors.white;
  String _subtitleWords = 'few';
  String _subtitlePosition = 'bottom';
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
  final Set<String> _selectedFillerWords = {..._fillerWordOptions};
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
    if (widget.enableExperimentalBeatSync) {
      _capabilities['beatsync'] = true;
    }
    unawaited(_loadAiEditQuota());
  }

  @override
  void dispose() {
    final activeRenderCancellation = _activeRenderCancellation;
    if (activeRenderCancellation != null) {
      unawaited(activeRenderCancellation.cancel());
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
    });

    try {
      final loader = widget.loadAiEditQuota ?? _apiClient.fetchAiEditQuota;
      final quota = await loader();
      if (!mounted) return;
      setState(() {
        _aiEditQuota = quota;
        _isLoadingAiEditQuota = false;
        _aiEditQuotaLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingAiEditQuota = false;
        _aiEditQuotaLoadFailed = true;
      });
    }
  }

  Future<void> _pickVideo() async {
    if (_isPickingVideo) return;
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
        _preparedEdit = null;
        _subtitleProject = null;
        _preparedEditsBySignature.clear();
        _preparedEditsByAnalysisSignature.clear();
        _renderResultsBySignature.clear();
        _renderedResult = null;
        _acceptedSetup = null;
        _reviewCapabilities.clear();
        _appliedReviewCapabilities.clear();
        _reviewVideoDurations.clear();
        _reviewVideoSource = ReviewVideoSource.ai;
        _reviewResultRevision = 0;
        _reviewPreviewLoading = false;
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
        'subtitle' || 'silence' || 'filler' || 'color' => true,
        _ => false,
      };

  bool _isCapabilityEnabled(String id) =>
      _isCapabilityAvailable(id) && (_capabilities[id] ?? false);

  Map<String, bool> get _effectiveCapabilities => {
        for (final entry in _capabilities.entries)
          entry.key: _isCapabilityAvailable(entry.key) && entry.value,
      };

  List<String> get _selectedFillerWordsInOrder => [
        for (final word in _fillerWordOptions)
          if (_selectedFillerWords.contains(word)) word,
      ];

  bool get _fillerSelectionComplete =>
      !_isCapabilityEnabled('filler') || _selectedFillerWords.isNotEmpty;

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
    if (picked == null || !_hasSelectedDuration || _processing) {
      return;
    }

    final shouldCheckSubscription = widget.loadSubscription != null ||
        (widget.createUpload == null &&
            widget.uploadVideoFile == null &&
            widget.prepareEdit == null);
    if (shouldCheckSubscription) {
      try {
        final loadSubscription =
            widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
        final subscription = await loadSubscription();
        if (!subscription.isPro) {
          throw const ApiException(
            'Pro plan is required for AI editing',
            statusCode: 402,
          );
        }
      } on ApiException catch (error) {
        if (mounted) {
          _showError(_friendlyAiError(error));
        }
        return;
      } catch (_) {
        if (mounted) {
          _showError('ตรวจสอบแพ็กเกจไม่สำเร็จ ลองใหม่อีกครั้ง');
        }
        return;
      }
    }

    final file = File(picked.path);
    setState(() {
      _processing = true;
      _processingTitle = 'AI กำลังวิเคราะห์คลิป...';
      _renderProgress = null;
      _renderCancelRequested = false;
    });

    try {
      if (!file.existsSync()) {
        throw const ApiException('ไม่พบไฟล์วิดีโอในเครื่อง');
      }

      final prepareSignature = _buildPrepareSignature(picked, file);
      final analysisSignature = _buildAnalysisSignature(picked, file);
      var prepared = _preparedEditsBySignature[prepareSignature];
      if (prepared == null) {
        final previousAnalysis =
            _preparedEditsByAnalysisSignature[analysisSignature];
        if (previousAnalysis != null) {
          if (mounted) {
            setState(
              () => _processingTitle = 'กำลังเลือกช่วงที่ดีที่สุดให้ใหม่...',
            );
          }
          final transcript = previousAnalysis.recipe.transcript;
          final planEdit = widget.planEdit ?? _apiClient.requestAiEditPlan;
          final plan = await planEdit(
            AiEditPlanRequest(
              segments: transcript.segments,
              durationSeconds: transcript.durationSeconds,
              targetDurationSeconds: _selectedDurationSeconds.toDouble(),
            ),
          );
          if (!mounted) {
            return;
          }
          prepared = AiEditPrepareResult(
            recipe: previousAnalysis.recipe.withPlan(plan),
            quota: previousAnalysis.quota,
          );
          prepared = await _enhancePreparedEditWithVisualProxy(
            sourceFile: file,
            prepared: prepared,
          );
          _preparedEditsBySignature[prepareSignature] = prepared;
        } else {
          AiEditAudioArtifact? audioArtifact;
          String? remoteAudioKey;
          try {
            selectAiEditAnalysisMode(
              _buildPrepareRequest('__capability_check__.m4a').capabilities,
            );
            if (mounted) {
              setState(() => _processingTitle = 'กำลังเตรียมเสียงให้ AI...');
            }

            final extractAudio =
                widget.extractAudio ?? AiEditAudioExtractor().extract;
            audioArtifact = await extractAudio(file);
            final audioFile = audioArtifact.file;

            final createUpload = widget.createUpload ?? _apiClient.createUpload;
            final uploadVideoFile =
                widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
            final upload = await createAndUploadFileWithRetry(
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
                    _processingTitle = 'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...';
                  });
                }
              },
            );
            remoteAudioKey = upload.videoS3Key;

            final prepareEdit = widget.prepareEdit ?? _apiClient.prepareAiEdit;
            final preparedFromApi = await prepareEdit(
              _buildPrepareRequest(remoteAudioKey),
            );
            if (!mounted) {
              return;
            }
            _preparedEditsByAnalysisSignature[analysisSignature] =
                preparedFromApi;
            prepared = await _enhancePreparedEditWithVisualProxy(
              sourceFile: file,
              prepared: preparedFromApi,
            );
            _preparedEditsBySignature[prepareSignature] = prepared;
          } finally {
            if (audioArtifact != null) {
              await _cleanupLocalAudioBestEffort(audioArtifact);
            }
            if (remoteAudioKey != null) {
              await _cleanupRemoteAudioBestEffort(remoteAudioKey);
            }
          }
        }
      }

      if (!mounted) {
        return;
      }
      final preparedResult = prepared;
      setState(() {
        _aiEditQuota = preparedResult.quota;
        _isLoadingAiEditQuota = false;
        _aiEditQuotaLoadFailed = false;
        _preparedEdit = preparedResult;
        _processingTitle = 'กำลังสร้างวิดีโอตัวอย่าง...';
        _renderProgress = 0;
      });

      final reviewCapabilities =
          _buildReviewCapabilities(preparedResult.recipe);
      final shouldOpenSubtitleStudio = reviewCapabilities['subtitle'] == true &&
          (widget.subtitleStudioLauncher != null || widget.burnVideo == null);
      if (shouldOpenSubtitleStudio) {
        final identity = buildSubtitleProjectIdentity(
          sourceFile: file,
          setupSignature: prepareSignature,
        );
        final initialProject = mapAiEditRecipeToSubtitleProject(
          recipe: preparedResult.recipe,
          projectId: identity.projectId,
          sourceFingerprint: identity.sourceFingerprint,
          now: DateTime.now().toUtc(),
        );
        setState(() {
          _processing = false;
          _renderProgress = null;
        });
        final editedProject = await _openSubtitleStudio(
          sourceFile: file,
          initialProject: initialProject,
        );
        if (!mounted) return;
        if (editedProject == null) {
          setState(() {
            _processing = false;
            _renderProgress = null;
            _renderCancelRequested = false;
          });
          return;
        }
        validateSubtitleProject(editedProject);
        setState(() {
          _subtitleProject = editedProject;
          _processing = true;
          _processingTitle = 'กำลังสร้างวิดีโอตัวอย่างพร้อมซับ...';
          _renderProgress = 0;
        });
      }
      final result = await _renderPreparedRecipe(
        recipe: preparedResult.recipe,
        capabilities: reviewCapabilities,
      );

      if (result.colorFilterSkipped) {
        reviewCapabilities.remove('color');
      }

      if (mounted) {
        final acceptedSetup = _captureSetupSnapshot();
        setState(() {
          _renderedResult = result;
          _prepareReviewForResult(result);
          _acceptedSetup = acceptedSetup;
          _reviewCapabilities
            ..clear()
            ..addAll(reviewCapabilities);
          _appliedReviewCapabilities
            ..clear()
            ..addAll(reviewCapabilities);
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
    final targetDurationSeconds = _selectedDurationSeconds.toDouble();
    if (!_shouldAttemptVisualProxy ||
        transcript.durationSeconds <= 0 ||
        targetDurationSeconds >= transcript.durationSeconds - 0.5) {
      return prepared;
    }

    AiEditVisualProxyArtifact? proxyArtifact;
    String? remoteProxyKey;
    try {
      if (mounted) {
        setState(
          () =>
              _processingTitle = 'กำลังสร้างวิดีโอตัวอย่างทั้งคลิปให้ AI ดู...',
        );
      }
      final extractVisualProxy =
          widget.extractVisualProxy ?? AiEditVisualProxyExtractor().extract;
      proxyArtifact = await extractVisualProxy(sourceFile);

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
          segments: transcript.segments,
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
      if (proxyArtifact != null) {
        await _cleanupLocalVisualProxyBestEffort(proxyArtifact);
      }
      if (remoteProxyKey != null) {
        await _cleanupRemoteVisualProxyBestEffort(remoteProxyKey);
      }
    }
  }

  AiEditPrepareRequest _buildPrepareRequest(String audioS3Key) {
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
      durationSeconds: _selectedDurationSeconds.toDouble(),
      targetDurationSeconds: _selectedDurationSeconds.toDouble(),
      capabilities: {
        ...capabilities,
        'sfx': false,
      },
      settings: AiEditPrepareSettings(
        subtitleStyle: 'outline',
        subtitleColor: '#FFFFFF',
        subtitleWordsPerLine: _subtitleWordsPerLine,
        subtitlePosition: _effectiveSubtitlePosition,
        ctaText: _ctaController.text.trim(),
        ctaDesign: _ctaDesign,
        priceText: _priceNowController.text.trim(),
        watermarkText: 'PostDee',
        toneFilter: _toneFilter,
        zoomLevel: _zoomLevel,
        silencePreset: _silencePreset,
        fillerWords: _selectedFillerWordsInOrder,
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
        _stage = _AiEditingStage.review;
      }
    });
    _showError(
      hasPreviousResult ? '$message · ผลลัพธ์เดิมยังอยู่' : message,
    );
  }

  Map<String, bool> _buildReviewCapabilities(AiEditRecipeResult recipe) {
    final subtitle = recipe.capabilities['subtitle'];
    final silence = recipe.capabilities['silence'];
    final filler = recipe.capabilities['filler'];

    return {
      if ((_capabilities['subtitle'] ?? false) &&
          (subtitle?.isApplied ?? false) &&
          recipe.subtitles.segments.isNotEmpty)
        'subtitle': true,
      if ((_capabilities['silence'] ?? false) &&
          (silence?.isApplied ?? false) &&
          recipe.silenceRanges.isNotEmpty)
        'silence': true,
      if ((_capabilities['filler'] ?? false) &&
          (filler?.isApplied ?? false) &&
          recipe.fillerRanges.isNotEmpty)
        'filler': true,
      if (_capabilities['color'] ?? false) 'color': true,
    };
  }

  Future<BurnedSubtitleResult> _renderPreparedRecipe({
    required AiEditRecipeResult recipe,
    required Map<String, bool> capabilities,
    VideoRenderPurpose purpose = VideoRenderPurpose.preview,
  }) async {
    final picked = _selectedVideo;
    if (picked == null) {
      throw const SubtitleBurnException('ไม่พบวิดีโอต้นฉบับ');
    }

    final originalFile = File(picked.path);
    final options = _buildEditOptions(capabilities);
    var cutRanges = <SilenceCutRange>[
      // Style/free-prompt cuts come from the AI plan and are independent of
      // the silence/filler review toggles below.
      for (final range in recipe.plan.cuts)
        SilenceCutRange(start: range.start, end: range.end),
      if (capabilities['silence'] ?? false)
        for (final range in recipe.silenceRanges)
          SilenceCutRange(start: range.start, end: range.end),
      if (capabilities['filler'] ?? false)
        for (final range in recipe.fillerRanges)
          SilenceCutRange(start: range.start, end: range.end),
    ];

    final sourceDuration = recipe.transcript.durationSeconds;
    if (sourceDuration > 0) {
      cutRanges = withTargetLength(
        cutRanges,
        sourceDuration,
        _selectedDurationSeconds.toDouble(),
      );
    }

    final studioProject =
        capabilities['subtitle'] == true ? _subtitleProject : null;
    final studioStyle = studioProject?.defaultStyle;
    var subtitleSegments = <SubtitleSegment>[
      if (studioProject != null)
        for (final cue in studioProject.cues)
          SubtitleSegment(
            text: cue.text,
            start: cue.sourceStartMs / 1000,
            end: cue.sourceEndMs / 1000,
          )
      else if (capabilities['subtitle'] ?? false)
        for (final segment in recipe.subtitles.segments)
          SubtitleSegment(
            text: segment.text,
            start: segment.start,
            end: segment.end,
          ),
    ];
    final subtitleMaxChars = options.subtitleMaxChars;
    if (studioProject == null && subtitleMaxChars != null) {
      subtitleSegments = rechunkSubtitleByMaxChars(
        subtitleSegments,
        subtitleMaxChars,
      );
    }

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
    final needsLocalRender = subtitleSegments.isNotEmpty ||
        cutRanges.isNotEmpty ||
        (speed - 1).abs() > 0.0001 ||
        (options.filterIndex ?? 0) != 0 ||
        (options.brightness ?? 0).abs() > 0.0001 ||
        (options.contrast ?? 0).abs() > 0.0001;
    if (!needsLocalRender) {
      return BurnedSubtitleResult(
        file: originalFile,
        fileName: picked.name.trim().isNotEmpty
            ? picked.name.trim()
            : _readFileNameFromPath(picked.path),
        sizeBytes:
            picked.sizeBytes > 0 ? picked.sizeBytes : originalFile.lengthSync(),
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
      'targetDurationSeconds': _selectedDurationSeconds,
      'capabilities': {
        for (final entry in sortedCapabilities) entry.key: entry.value,
      },
      'segments': [
        for (final segment in subtitleSegments)
          {
            'text': segment.text,
            'start': segment.start,
            'end': segment.end,
          },
      ],
      'cuts': [
        for (final range in cutRanges) {'start': range.start, 'end': range.end},
      ],
      'speed': speed,
      'filterIndex': options.filterIndex ?? 0,
      'brightness': options.brightness ?? 0,
      'contrast': options.contrast ?? 0,
      'subtitleFontSize': options.subtitleFontSize ?? 18,
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
      return cachedResult;
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
      subtitleFontSize: studioStyle?.fontSize ?? options.subtitleFontSize ?? 18,
      subtitleAtBottom: studioStyle == null
          ? options.subtitleAtBottom ?? true
          : studioStyle.alignment == SubtitleAlignment.bottom,
      subtitleAlignment: studioStyle == null
          ? null
          : _burnSubtitleAlignment(studioStyle.alignment),
      subtitleFontName: studioStyle?.fontId ?? 'Prompt',
      subtitleFontAssetPath:
          studioStyle == null ? null : _subtitleFontAssetPath(studioStyle),
      subtitleTextColor: studioStyle?.textColor ?? '#FFFFFF',
      subtitleOutlineColor: studioStyle?.outlineColor ?? '#000000',
      subtitleOutlineWidth: studioStyle?.outlineWidth ?? 2,
      subtitleShadowColor: studioStyle?.shadowColor ?? '#000000',
      subtitleShadowDepth: studioStyle?.shadowDepth ?? 0,
      preserveTempDirectoryPaths: {
        if (_renderedResult != null) _renderedResult!.file.parent.path,
        for (final result in _renderResultsBySignature.values)
          result.file.parent.path,
      },
      outputDurationSeconds: outputDuration,
      onProgress: reportProgress,
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
      return result;
    } finally {
      if (mounted && identical(_activeRenderCancellation, cancellationToken)) {
        setState(() => _activeRenderCancellation = null);
      }
    }
  }

  EditStyleOptions _buildEditOptions(Map<String, bool> capabilities) {
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
      targetSeconds: _selectedDurationSeconds,
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

  int get _subtitleWordsPerLine => switch (_subtitleWords) {
        'karaoke' => 1,
        'full' => 8,
        _ => 4,
      };

  String get _effectiveSubtitlePosition =>
      _subtitlePosition == 'top' ? 'top' : 'bottom';

  BurnSubtitleAlignment _burnSubtitleAlignment(SubtitleAlignment alignment) =>
      switch (alignment) {
        SubtitleAlignment.top => BurnSubtitleAlignment.top,
        SubtitleAlignment.middle => BurnSubtitleAlignment.middle,
        SubtitleAlignment.bottom => BurnSubtitleAlignment.bottom,
      };

  String _subtitleFontAssetPath(SubtitleStyle style) {
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
    return 'assets/fonts/$family/$familyName-$weight.ttf';
  }

  _AiSetupSnapshot _captureSetupSnapshot() {
    return _AiSetupSnapshot(
      durationMode: _durationMode,
      customDurationSeconds: _customDurationSeconds,
      capabilities: Map<String, bool>.from(_capabilities),
      subtitleStyle: _subtitleStyle,
      subtitleColor: _subtitleColor,
      subtitleWords: _subtitleWords,
      subtitlePosition: _subtitlePosition,
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
      fillerWords: Set<String>.from(_selectedFillerWords),
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
    _subtitleStyle = snapshot.subtitleStyle;
    _subtitleColor = snapshot.subtitleColor;
    _subtitleWords = snapshot.subtitleWords;
    _subtitlePosition = snapshot.subtitlePosition;
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
    _selectedFillerWords
      ..clear()
      ..addAll(snapshot.fillerWords);
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
    _collapseAdvancedIfUnavailable();
  }

  String _friendlyAiError(ApiException error) {
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
    final requested = switch (_durationMode) {
      _AiDurationMode.unselected => 0,
      _AiDurationMode.seconds30 => 30,
      _AiDurationMode.seconds60 => 60,
      _AiDurationMode.custom => _customDurationSeconds,
    };
    final sourceMaximum = _sourceDurationMaximumSeconds;
    if (sourceMaximum == null || requested <= 0) {
      return requested;
    }
    return requested.clamp(1, sourceMaximum);
  }

  bool get _hasSelectedDuration => _durationMode != _AiDurationMode.unselected;

  int? get _sourceDurationMaximumSeconds {
    final sourceDuration = _selectedVideoDurationSeconds;
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
    final sourceMaximum = _sourceDurationMaximumSeconds;
    return sourceMaximum != null &&
        _hasSelectedDuration &&
        _selectedDurationSeconds >= sourceMaximum;
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
    return keys.any(
      (key) =>
          (_reviewCapabilities[key] ?? false) !=
          (_appliedReviewCapabilities[key] ?? false),
    );
  }

  void _prepareReviewForResult(BurnedSubtitleResult result) {
    final originalPath = _selectedVideo?.path;
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
        ReviewVideoSource.original => _selectedVideo?.path == path,
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
    final prepared = _preparedEdit;
    if (prepared == null ||
        _processing ||
        _updatingReviewPreview ||
        !_reviewIsDirty) {
      return;
    }

    setState(() {
      _updatingReviewPreview = true;
      _renderProgress = 0;
      _renderCancelRequested = false;
    });

    try {
      final result = await _renderPreparedRecipe(
        recipe: prepared.recipe,
        capabilities: Map<String, bool>.from(_reviewCapabilities),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _renderedResult = result;
        _prepareReviewForResult(result);
        if (result.colorFilterSkipped) {
          _reviewCapabilities.remove('color');
        }
        _appliedReviewCapabilities
          ..clear()
          ..addAll(_reviewCapabilities);
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
        });
        _showError('อัปเดตคลิปไม่สำเร็จ · ผลลัพธ์เดิมยังอยู่');
      }
    }
  }

  Future<void> _editReviewSubtitles() async {
    final prepared = _preparedEdit;
    final project = _subtitleProject;
    final picked = _selectedVideo;
    if (prepared == null ||
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

    final previous = _subtitleProject;
    setState(() {
      _subtitleProject = edited;
      _updatingReviewPreview = true;
      _renderProgress = 0;
      _renderCancelRequested = false;
    });
    try {
      final result = await _renderPreparedRecipe(
        recipe: prepared.recipe,
        capabilities: Map<String, bool>.from(_appliedReviewCapabilities),
      );
      if (!mounted) return;
      setState(() {
        _renderedResult = result;
        _prepareReviewForResult(result);
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
    } on SubtitleBurnException catch (error) {
      if (!mounted) return;
      setState(() {
        _subtitleProject = previous;
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
      _showError('${error.message} • ผลลัพธ์เดิมยังอยู่');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subtitleProject = previous;
        _updatingReviewPreview = false;
        _renderProgress = null;
        _renderCancelRequested = false;
      });
      _showError('อัปเดตซับไม่สำเร็จ • ผลลัพธ์เดิมยังอยู่');
    }
  }

  Future<void> _toggleReviewCapability(String id, bool enabled) async {
    if (_updatingReviewPreview) {
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
    });
  }

  void _returnToSetup() {
    setState(() {
      _reviewCapabilities
        ..clear()
        ..addAll(_appliedReviewCapabilities);
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
    final prepared = _preparedEdit;
    if (prepared != null) {
      setState(() {
        _processing = true;
        _processingTitle = 'กำลังสร้างวิดีโอคุณภาพเต็ม...';
        _renderProgress = 0;
        _renderCancelRequested = false;
      });

      try {
        result = await _renderPreparedRecipe(
          recipe: prepared.recipe,
          capabilities: Map<String, bool>.from(_appliedReviewCapabilities),
          purpose: VideoRenderPurpose.export,
        );
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => const PaywallScreen(),
        ),
      );
    }
  }

  void _handleBack() {
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
          subtitleStyle: _subtitleStyle,
          subtitleColor: _subtitleColor,
          subtitleWords: _subtitleWords,
          subtitlePosition: _subtitlePosition,
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
          fillerWords: Set<String>.from(_selectedFillerWords),
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
      _subtitleStyle = preset.subtitleStyle;
      _subtitleColor = preset.subtitleColor;
      _subtitleWords = preset.subtitleWords;
      _subtitlePosition = preset.subtitlePosition;
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
      _selectedFillerWords
        ..clear()
        ..addAll(preset.fillerWords);
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
          description: 'เลือกได้หลายอย่าง — เปิด/ปิดได้ตามใจ',
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

    final selectedVideo = _selectedVideo;
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
        _preparedEdit?.recipe.transcript.durationSeconds ?? 0;
    final transcriptDuration = transcriptDurationSeconds > 0
        ? Duration(
            milliseconds: (transcriptDurationSeconds * 1000).round(),
          )
        : null;
    final originalDuration = selectedVideo == null
        ? null
        : _reviewVideoDurations[selectedVideo.path] ?? transcriptDuration;
    final aiDuration = _reviewVideoDurations[result.file.path];

    final appliedDefinitions = [
      for (final definition in _capabilityDefinitions)
        if (_reviewCapabilities.containsKey(definition.id)) definition,
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
                onPressed: _returnToSetup,
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
        if (_subtitleProject != null &&
            (_appliedReviewCapabilities['subtitle'] ?? false)) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('ai-review-edit-subtitles'),
            onPressed: _updatingReviewPreview ? null : _editReviewSubtitles,
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
          description: 'เอาติ๊กออกหรือใส่กลับ พรีวิวจะอัปเดตให้อัตโนมัติ',
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
    final recipe = _preparedEdit?.recipe;
    final silenceRanges = recipe?.silenceRanges ?? const <AiEditCut>[];
    final fillerRanges = recipe?.fillerRanges ?? const <AiEditCut>[];
    final silenceStatus = _analysisDetectionStatus(
      capabilityId: 'silence',
      count: silenceRanges.length,
      unit: 'ช่วง',
    );
    final fillerStatus = _analysisDetectionStatus(
      capabilityId: 'filler',
      count: fillerRanges.length,
      unit: 'คำ',
    );
    final detectedSeconds = _mergedDetectedSeconds(
      [...silenceRanges, ...fillerRanges],
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
                  ? 'ai-review-not-detected-filler'
                  : 'ai-review-analysis-filler-status',
            ),
            icon: Icons.voice_over_off_outlined,
            label: 'คำฟุ่มเฟือย',
            value: fillerStatus.text,
          ),
          const SizedBox(height: 10),
          Text(
            'เวลาที่ตรวจพบรวม ${_formatAnalysisSeconds(detectedSeconds)} วินาที',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentCyanInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ตัวเลขนี้คือช่วงที่ตรวจพบก่อนสร้างคลิปจริง ผลลัพธ์อาจสั้นลงไม่เท่ากันตามความยาวที่เลือก',
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
    if (count > 0) {
      return (text: 'พบ $count $unit', isNotDetected: false);
    }

    final status = _preparedEdit?.recipe.capabilities[capabilityId];
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
    final quota = _aiEditQuota;

    if (quota == null) {
      if (_aiEditQuotaLoadFailed) {
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
              onTap: _handleBack,
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
              onTap: () {
                setState(() {
                  _selectedVideo = null;
                  _selectedVideoDurationSeconds = null;
                  _durationMode = _AiDurationMode.unselected;
                  _preparedEdit = null;
                  _subtitleProject = null;
                  _preparedEditsBySignature.clear();
                  _preparedEditsByAnalysisSignature.clear();
                  _renderResultsBySignature.clear();
                  _renderedResult = null;
                  _acceptedSetup = null;
                  _reviewCapabilities.clear();
                  _appliedReviewCapabilities.clear();
                  _reviewVideoDurations.clear();
                  _reviewVideoSource = ReviewVideoSource.ai;
                  _reviewResultRevision = 0;
                  _reviewPreviewLoading = false;
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
              item.group == group && !_deferredCapabilityIds.contains(item.id),
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
      'filler' => _buildFillerAdvanced(),
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
          'ตรวจจากช่องว่างระหว่างเวลาของคำถอดเสียง ไม่ได้ตรวจเสียงหายใจโดยตรง',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.45,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildFillerAdvanced() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _advancedLabel('คำที่ระบบจะลองตรวจหา'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final word in _fillerWordOptions)
              _choiceChip(
                key: ValueKey('ai-filler-word-$word'),
                label: word,
                selected: _selectedFillerWords.contains(word),
                onTap: () => setState(() {
                  if (_selectedFillerWords.contains(word)) {
                    _selectedFillerWords.remove(word);
                  } else {
                    _selectedFillerWords.add(word);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'ระบบตัดเฉพาะคำที่เลือกและตรวจพบพร้อมเวลาในคำถอดเสียง',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.45,
            color: AppTheme.textMuted,
          ),
        ),
        if (_selectedFillerWords.isEmpty) ...[
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.32),
              ),
            ),
            child: const Text(
              'เลือกอย่างน้อย 1 คำ หรือปิดฟังก์ชันตัดคำฟุ่มเฟือย',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubtitleAdvanced() {
    final alignment = _effectiveSubtitlePosition == 'top'
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    final previewText = switch (_subtitleWords) {
      'karaoke' => 'ลด',
      'full' => 'ลดแรง 50% ส่งฟรีทั้งร้าน',
      _ => 'ลดแรง 50%',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          child: Container(
            width: 104,
            height: 184,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
            alignment: alignment,
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
            child: _subtitlePreview(previewText),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderSoft),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 17,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'สีซับเป็นสีขาวพร้อมขอบดำในเวอร์ชันนี้',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _advancedLabel('ความยาวต่อช่วงซับ'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-short'),
              label: 'สั้น (ไม่เกิน 8 ตัวอักษร)',
              selected: _subtitleWords == 'karaoke',
              onTap: () => setState(() => _subtitleWords = 'karaoke'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-medium'),
              label: 'กลาง (ไม่เกิน 18 ตัวอักษร)',
              selected: _subtitleWords == 'few',
              onTap: () => setState(() => _subtitleWords = 'few'),
            ),
            _choiceChip(
              key: const ValueKey('ai-subtitle-length-long'),
              label: 'ยาว (ไม่เกิน 36 ตัวอักษร)',
              selected: _subtitleWords == 'full',
              onTap: () => setState(() => _subtitleWords = 'full'),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _advancedLabel('ตำแหน่งซับ'),
        Wrap(
          spacing: 7,
          children: [
            for (final option in const [
              ('top', 'บน'),
              ('bottom', 'ล่าง'),
            ])
              _choiceChip(
                key: ValueKey('ai-subtitle-position-${option.$1}'),
                label: option.$2,
                selected: _effectiveSubtitlePosition == option.$1,
                onTap: () => setState(() => _subtitlePosition = option.$1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _subtitlePreview(String text) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: switch (_subtitleStyle) {
        'small' => 13,
        'medium' => 15,
        _ => 17,
      },
      fontWeight: FontWeight.w800,
      shadows: const [
        Shadow(color: Colors.black, blurRadius: 1, offset: Offset(1, 1)),
        Shadow(color: Colors.black, blurRadius: 1, offset: Offset(-1, -1)),
      ],
    );
    return Text(text, textAlign: TextAlign.center, style: textStyle);
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
        _fillerSelectionComplete;
    final usesPendingMusic = _isCapabilityEnabled('beatsync') &&
        _musicSource != _BeatMusicSource.original;
    final label = !hasVideo
        ? 'เพิ่มวิดีโอก่อน'
        : !_hasSelectedDuration
            ? 'เลือกความยาวก่อน'
            : !_fillerSelectionComplete
                ? 'เลือกคำฟุ่มเฟือยอย่างน้อย 1 คำ'
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
              renderProgress == null
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
                  _processingTitle,
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
