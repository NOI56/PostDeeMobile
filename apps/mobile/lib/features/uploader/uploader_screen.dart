import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/monitoring/postdee_analytics.dart';
import '../../core/theme/app_theme.dart';
import '../ai_editing/ai_edit_audio_extractor.dart';
import '../ai_editing/review_video_timeline.dart';
import '../platforms/connections_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/growth_tool_settings_store.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_status_sheet.dart';
import 'caption_quota_strip.dart';
import 'clip_frame_extractor.dart';
import 'cover_editor_screen.dart';
import 'cover_image_processor.dart';
import 'post_caption.dart';
import 'publish_flow_screen.dart';
import 'publish_review_screen.dart';
import 'video_picker_service.dart';
import 'watermark_video_processor.dart';
import 'youtube_title.dart';

typedef UploaderTemplateLoader = Future<List<TextTemplateResult>> Function();
typedef UploaderSubscriptionLoader = Future<SubscriptionStatusResult>
    Function();
typedef UploaderCaptionQuotaLoader = Future<CaptionQuotaResult> Function();
typedef UploaderCaptionGenerator = Future<CaptionResult> Function(
    List<String> keywords);
typedef UploaderRealClipCaptionGenerator = Future<RealClipCaptionResult>
    Function(GenerateRealClipCaptionRequest request);
typedef UploaderUploadCreator = Future<UploadResult> Function(
    CreateUploadRequest request);
typedef UploaderVideoUploader = Future<void> Function(
  UploadResult upload,
  File videoFile,
);
typedef UploaderPostCreator = Future<QueuedPostResult> Function(
    CreatePostRequest request);
typedef UploaderScheduledPostCreated = void Function(QueuedPostResult post);
typedef UploaderConnectionsLoader = Future<List<SocialConnectionResult>>
    Function();
typedef UploaderAudioExtractor = Future<AiEditAudioArtifact> Function(
    File source);

const postScheduleLimit = Duration(days: 30);

/// Matches the API's real-clip caption clip limit (Gemini inline budget).
/// At the extractor's 64 kbps mono this is roughly 20 minutes of audio.
const aiCaptionAudioMaxBytes = 10 * 1024 * 1024;

bool isPostScheduleWithinLimit({
  required DateTime scheduledAt,
  required DateTime now,
}) =>
    !scheduledAt.isAfter(now.add(postScheduleLimit));

class UploaderScreen extends StatefulWidget {
  const UploaderScreen({
    super.key,
    this.loadTemplates,
    this.loadSubscription,
    this.loadCaptionQuota,
    this.isActive = true,
    this.generateCaption,
    this.generateRealClipCaption,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.createPost,
    this.loadSocialConnections,
    this.onScheduledPostCreated,
    this.onPublishFinished,
    this.analytics,
    this.watermarkVideo,
    this.openCoverEditor,
    this.coverImageProcessor,
    this.now = DateTime.now,
    this.extractFrames,
    this.extractCaptionAudio,
    this.growthToolSettingsStore =
        const SharedPreferencesGrowthToolSettingsStore(),
    this.initialVideoPath,
    this.initialVideoName,
    this.initialVideoSizeBytes,
    this.initialVideoWidth,
    this.initialVideoHeight,
  });

  final UploaderTemplateLoader? loadTemplates;
  final UploaderSubscriptionLoader? loadSubscription;
  final UploaderCaptionQuotaLoader? loadCaptionQuota;
  final bool isActive;
  final UploaderCaptionGenerator? generateCaption;
  final UploaderRealClipCaptionGenerator? generateRealClipCaption;
  final UploaderVideoPicker? pickVideo;
  final UploaderUploadCreator? createUpload;
  final UploaderVideoUploader? uploadVideoFile;
  final UploaderPostCreator? createPost;
  final UploaderConnectionsLoader? loadSocialConnections;
  final UploaderScheduledPostCreated? onScheduledPostCreated;
  final VoidCallback? onPublishFinished;
  final PostDeeAnalytics? analytics;
  final UploaderWatermarkVideoProcessor? watermarkVideo;
  final UploaderCoverEditorLauncher? openCoverEditor;
  final CoverImageProcessor? coverImageProcessor;

  // Wall clock used to reject schedules in the past. Injectable so tests can
  // pin "now" instead of depending on the real time of day.
  final DateTime Function() now;

  // Extracts still frames from the clip for Pro AI captioning (Gemini "sees"
  // them). Injectable so tests don't touch the native FFmpeg plugin.
  final UploaderClipFrameExtractor? extractFrames;

  // Extracts the clip's audio for AI captioning so only a small M4A is
  // uploaded. Injectable so tests don't touch the native FFmpeg plugin.
  final UploaderAudioExtractor? extractCaptionAudio;
  final PostDeeGrowthToolSettingsStore growthToolSettingsStore;

  // Pre-fills the screen with an already-on-device clip (e.g. the editor's
  // rendered output) so the user can post it without re-picking from gallery.
  final String? initialVideoPath;
  final String? initialVideoName;
  final int? initialVideoSizeBytes;
  final int? initialVideoWidth;
  final int? initialVideoHeight;

  @override
  State<UploaderScreen> createState() => _UploaderScreenState();
}

class _UploaderScreenState extends State<UploaderScreen>
    with WidgetsBindingObserver {
  final _apiClient = PostDeeApiClient();
  PostDeeAnalytics get _analytics =>
      widget.analytics ?? PostDeeAnalytics.instance;
  final _captionController = TextEditingController();
  final _youtubeTitleController = TextEditingController();
  String? _youtubeTitleOverride;
  bool _isEditingYoutubeTitle = false;
  final _fileNameController = TextEditingController();
  final _localFilePathController = TextEditingController();
  final _sizeBytesController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _scheduledAtController = TextEditingController();
  final _aiGuidanceController = TextEditingController();
  DateTime? _selectedScheduleDate;
  TimeOfDay? _selectedScheduleTime;
  final Set<SocialPlatform> _selectedPlatforms = {};
  final Set<SocialPlatform> _connectedPlatforms = {};
  final List<TextTemplateResult> _templates = [];
  bool _isSubmitting = false;
  bool _isLoadingTemplates = false;
  bool _isGeneratingCaption = false;
  CaptionQuotaResult? _captionQuota;
  bool _isLoadingCaptionQuota = false;
  bool _captionQuotaLoadFailed = false;
  int _captionQuotaRequestId = 0;
  late AuthSessionBinding _captionQuotaSession;
  bool _isAdvancedModeEnabled = true;
  bool _isLoadingConnections = true;
  String? _connectionsErrorMessage;
  String? _successMessage;
  String? _errorMessage;
  String? _templateErrorMessage;
  String? _aiCaptionErrorMessage;
  String? _selectedVideoName;
  CoverEditorResult? _coverResult;
  PostDeeStatusSheetData? _pendingStatusSheet;
  bool _pickVideoAfterStatus = false;
  String? _pendingInlineError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captionQuotaSession = PostDeeAuthSessionStore.instance.captureSession();
    PostDeeAuthSessionStore.instance
        .addListener(_handleCaptionQuotaSessionChanged);
    _captionController.addListener(_syncAutomaticYoutubeTitle);
    _prefillInitialVideo();
    unawaited(_loadConnections());
    if (widget.isActive) unawaited(_loadCaptionQuota());
  }

  @override
  void didUpdateWidget(covariant UploaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_loadCaptionQuota());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      unawaited(_loadCaptionQuota());
    }
  }

  Future<void> _loadCaptionQuota() async {
    if (_isGeneratingCaption) return;
    final requestId = ++_captionQuotaRequestId;
    final session = _captionQuotaSession;
    setState(() {
      _isLoadingCaptionQuota = true;
      _captionQuotaLoadFailed = false;
      _captionQuota = null;
    });
    try {
      final loader = widget.loadCaptionQuota ??
          PostDeeApiClient(
            authHeaders: PostDeeApiAuthHeaders(sessionBinding: session),
          ).fetchAiCaptionQuota;
      final result = await loader();
      if (!mounted ||
          !session.isCurrent ||
          requestId != _captionQuotaRequestId) {
        return;
      }
      setState(() {
        _captionQuota = result;
        _isLoadingCaptionQuota = false;
      });
    } catch (_) {
      if (!mounted ||
          !session.isCurrent ||
          requestId != _captionQuotaRequestId) {
        return;
      }
      setState(() {
        _isLoadingCaptionQuota = false;
        _captionQuotaLoadFailed = true;
      });
    }
  }

  void _handleCaptionQuotaSessionChanged() {
    if (_captionQuotaSession.isCurrent) return;
    _captionQuotaSession = PostDeeAuthSessionStore.instance.captureSession();
    _captionQuotaRequestId++;
    setState(() {
      _captionQuota = null;
      _isLoadingCaptionQuota = false;
      _captionQuotaLoadFailed = false;
    });
    if (widget.isActive &&
        PostDeeAuthSessionStore.instance.session.isSignedIn) {
      unawaited(_loadCaptionQuota());
    }
  }

  Future<void> _loadConnections() async {
    if (mounted) {
      setState(() {
        _isLoadingConnections = true;
        _connectionsErrorMessage = null;
      });
    }

    try {
      final loader =
          widget.loadSocialConnections ?? _apiClient.listSocialConnections;
      final results = await loader();
      if (!mounted) return;

      final connected = results
          .where((result) => result.connected)
          .map((result) => _platformFromApiValue(result.platform))
          .whereType<SocialPlatform>()
          .where(connectablePlatforms.contains)
          .toSet();

      setState(() {
        _connectedPlatforms
          ..clear()
          ..addAll(connected);
        _selectedPlatforms.removeWhere(
          (platform) => !_connectedPlatforms.contains(platform),
        );
        if (_selectedPlatforms.isEmpty) {
          _selectedPlatforms.addAll(_connectedPlatforms.take(2));
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connectedPlatforms.clear();
        _selectedPlatforms.clear();
        _connectionsErrorMessage =
            'ตรวจสอบช่องทางที่เชื่อมต่อไม่สำเร็จ ลองใหม่อีกครั้ง';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingConnections = false);
      }
    }
  }

  SocialPlatform? _platformFromApiValue(String apiValue) {
    for (final platform in SocialPlatform.values) {
      if (platform.apiValue == apiValue.toUpperCase()) {
        return platform;
      }
    }
    return null;
  }

  Future<void> _openConnections() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const ConnectionsScreen(),
      ),
    );
    if (mounted) {
      await _loadConnections();
    }
  }

  /// Loads an injected clip (e.g. the rendered output handed over from the
  /// editor) into the form fields the post flow reads from.
  void _prefillInitialVideo() {
    final path = widget.initialVideoPath?.trim() ?? '';

    if (path.isEmpty) {
      return;
    }

    final name = (widget.initialVideoName ?? '').trim().isNotEmpty
        ? widget.initialVideoName!.trim()
        : _readFileNameFromPath(path);

    _selectedVideoName = name;
    _localFilePathController.text = path;
    _fileNameController.text = name;

    final sizeBytes = widget.initialVideoSizeBytes;
    if (sizeBytes != null && sizeBytes > 0) {
      _sizeBytesController.text = sizeBytes.toString();
    }
    if (widget.initialVideoWidth != null) {
      _widthController.text = widget.initialVideoWidth!.toString();
    }
    if (widget.initialVideoHeight != null) {
      _heightController.text = widget.initialVideoHeight!.toString();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PostDeeAuthSessionStore.instance
        .removeListener(_handleCaptionQuotaSessionChanged);
    _captionQuotaRequestId++;
    final cover = _coverResult;
    _coverResult = null;
    if (cover != null) unawaited(_evictAndCleanupCover(cover));
    _captionController.removeListener(_syncAutomaticYoutubeTitle);
    _captionController.dispose();
    _youtubeTitleController.dispose();
    _fileNameController.dispose();
    _localFilePathController.dispose();
    _sizeBytesController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _scheduledAtController.dispose();
    _aiGuidanceController.dispose();
    super.dispose();
  }

  void _cleanupCoverAfterFrame(CoverEditorResult? cover) {
    if (cover == null) return;
    if (cover.imageBytes != null) {
      // Managed covers are previewed from memory, so no widget keeps the
      // temporary JPEG open and it can be removed immediately.
      unawaited(cover.cleanupTemporaryFiles());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_evictAndCleanupCover(cover));
    });
    // addPostFrameCallback does not request a frame by itself. This matters
    // when the editor returns after the current frame has already finished.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _evictAndCleanupCover(CoverEditorResult cover) async {
    if (cover.imageBytes == null) {
      try {
        await FileImage(cover.imageFile).evict();
      } catch (_) {
        // A cache miss or decoder shutdown must not block owned temp cleanup.
      }
    }
    await cover.cleanupTemporaryFiles();
  }

  int? _readPositiveInt(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());

    if (value == null || value < 1) {
      return null;
    }

    return value;
  }

  bool _isVerticalNineBySixteen({
    required int width,
    required int height,
  }) =>
      isVerticalNineBySixteen(width: width, height: height);

  DateTime? _readScheduledAt() {
    final value = _scheduledAtController.text.trim();

    if (value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  DateTime _scheduleDateFromToday(int daysFromToday) {
    final now = widget.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);

    return today.add(Duration(days: daysFromToday));
  }

  void _syncScheduledAt() {
    final date = _selectedScheduleDate;
    final time = _selectedScheduleTime;

    if (date == null || time == null) {
      _scheduledAtController.clear();
      return;
    }

    // Build the local wall-clock time the user picked, then send it in UTC so
    // the backend stores an absolute instant regardless of server timezone.
    _scheduledAtController.text = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc().toIso8601String();
  }

  void _setScheduledDate(DateTime date) {
    _selectedScheduleDate = DateTime(date.year, date.month, date.day);
    _selectedScheduleTime ??= const TimeOfDay(hour: 18, minute: 30);
    _syncScheduledAt();
  }

  void _setScheduledTime(TimeOfDay time) {
    _selectedScheduleDate ??= _scheduleDateFromToday(1);
    _selectedScheduleTime = time;
    _syncScheduledAt();
  }

  void _setQuickScheduleDay(int daysFromToday) {
    setState(() {
      _setScheduledDate(_scheduleDateFromToday(daysFromToday));
    });
  }

  void _setQuickScheduleTime(TimeOfDay time) {
    setState(() {
      _setScheduledTime(time);
    });
  }

  Future<void> _pickCustomScheduleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _selectedScheduleTime ?? const TimeOfDay(hour: 18, minute: 30),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _setScheduledTime(picked);
    });
  }

  Future<void> _pickCustomScheduleDate() async {
    final today = _scheduleDateFromToday(0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedScheduleDate ?? _scheduleDateFromToday(1),
      firstDate: today,
      lastDate: today.add(postScheduleLimit),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _setScheduledDate(picked);
    });
  }

  String _readFileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final fileName = parts.isEmpty ? path : parts.last;

    return fileName.trim();
  }

  Future<SubscriptionStatusResult> _loadSubscription() async {
    final loader =
        widget.loadSubscription ?? _apiClient.loadCurrentSubscription;
    return loader();
  }

  /// Extracts the clip's audio on device and uploads only that small M4A for
  /// AI captioning. Uploading the full video made the API hold it in memory.
  Future<String?> _uploadSelectedClipAudioForAiCaption() async {
    final localFilePath = _localFilePathController.text.trim();
    final localVideoFile = localFilePath.isEmpty ? null : File(localFilePath);
    final width = _readPositiveInt(_widthController);
    final height = _readPositiveInt(_heightController);

    if (localVideoFile == null) {
      setState(() {
        _aiCaptionErrorMessage = 'เลือกคลิปจริงจากเครื่องก่อนให้ AI คิดแคปชั่น';
      });
      return null;
    }

    if (!localVideoFile.existsSync()) {
      setState(() {
        _aiCaptionErrorMessage = 'ไม่พบไฟล์วิดีโอในเครื่อง';
      });
      return null;
    }

    if (width != null &&
        height != null &&
        !_isVerticalNineBySixteen(width: width, height: height)) {
      setState(() {
        _aiCaptionErrorMessage = 'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920';
      });
      return null;
    }

    final extractAudio =
        widget.extractCaptionAudio ?? AiEditAudioExtractor().extract;
    final audioArtifact = await extractAudio(localVideoFile);

    try {
      final audioFile = audioArtifact.file;
      final audioSizeBytes = audioFile.lengthSync();

      if (audioSizeBytes > aiCaptionAudioMaxBytes) {
        if (mounted) {
          setState(() {
            _aiCaptionErrorMessage =
                'คลิปยาวเกินไปสำหรับ AI แคปชั่น ลองตัดให้สั้นลงแล้วลองใหม่';
          });
        }
        return null;
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final uploadFile = widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      final upload = await createAndUploadFileWithRetry(
        request: CreateUploadRequest(
          fileName: _readFileNameFromPath(audioFile.path),
          contentType: 'audio/mp4',
          sizeBytes: audioSizeBytes,
          purpose: 'ai-edit-audio',
        ),
        file: audioFile,
        createUpload: createUpload,
        uploadFile: uploadFile,
        onRetry: () {
          if (mounted) {
            setState(() {
              _successMessage = 'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...';
            });
          }
        },
      );

      return upload.videoS3Key;
    } finally {
      try {
        await audioArtifact.cleanup();
      } catch (_) {
        // Temp audio cleanup must not replace the caption result or error.
      }
    }
  }

  /// Extracts still frames from the selected clip and uploads them, returning
  /// their storage keys for Pro AI captioning. Frames are an enhancement: if
  /// extraction or upload fails, this returns an empty list so captioning falls
  /// back to audio-only instead of erroring.
  Future<List<String>> _uploadAiCaptionFrames() async {
    final localFilePath = _localFilePathController.text.trim();

    if (localFilePath.isEmpty) {
      return const [];
    }

    final videoFile = File(localFilePath);

    if (!videoFile.existsSync()) {
      return const [];
    }

    try {
      final extractor = widget.extractFrames ?? FfmpegClipFrameExtractor().call;
      final frames = await extractor(videoFile, maxFrames: 3);

      if (frames.isEmpty) {
        return const [];
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      final frameKeys = <String>[];

      for (var index = 0; index < frames.length; index += 1) {
        final frame = frames[index];

        if (!frame.existsSync()) {
          continue;
        }

        final sizeBytes = frame.lengthSync();

        if (sizeBytes < 1) {
          continue;
        }

        final upload = await createAndUploadFileWithRetry(
          request: CreateUploadRequest(
            fileName: 'frame_${index + 1}.jpg',
            contentType: 'image/jpeg',
            sizeBytes: sizeBytes,
          ),
          file: frame,
          createUpload: createUpload,
          uploadFile: uploadVideoFile,
        );
        frameKeys.add(upload.videoS3Key);
      }

      return frameKeys;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _templateErrorMessage = null;
    });

    try {
      final loader = widget.loadTemplates ?? _apiClient.listTemplates;
      final templates = await loader();

      if (!mounted) {
        return;
      }

      setState(() {
        _templates
          ..clear()
          ..addAll(templates);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _templateErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _templateErrorMessage = 'เชื่อมต่อ PostDee API ไม่ได้';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _templateErrorMessage = 'เกิดข้อผิดพลาดระหว่างโหลดเทมเพลต';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTemplates = false;
        });
      }
    }
  }

  void _insertTemplate(TextTemplateResult template) {
    final currentCaption = _captionController.text.trimRight();
    final nextCaption = currentCaption.isEmpty
        ? template.body
        : '$currentCaption\n\n${template.body}';

    _captionController.value = TextEditingValue(
      text: nextCaption,
      selection: TextSelection.collapsed(offset: nextCaption.length),
    );
  }

  String _formatRealClipCaption(RealClipCaptionResult result) {
    final hashtags = result.hashtags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .map((tag) => tag.startsWith('#') ? tag : '#$tag')
        .join(' ');
    final seoKeywords = result.seoKeywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .join(', ');
    final parts = [
      result.caption.trim(),
      if (seoKeywords.isNotEmpty) 'SEO: $seoKeywords',
      if (hashtags.isNotEmpty) hashtags,
    ].where((part) => part.isNotEmpty).toList();

    return parts.join('\n\n');
  }

  Future<void> _generateAiCaption() async {
    if (_isGeneratingCaption ||
        (_captionQuota?.isPaid == true &&
            _captionQuota!.quota.remainingThisMonth == 0)) {
      return;
    }
    final session = _captionQuotaSession;
    final selectedVideoName = (_selectedVideoName ?? '').trim();

    if (selectedVideoName.isEmpty) {
      setState(() {
        _aiCaptionErrorMessage =
            'เลือกคลิปก่อน แล้ว AI จะคิดแคปชั่นจากเสียงในคลิปนั้น';
      });
      return;
    }

    var quotaUpdated = false;
    // A read started before generation must not overwrite its newer balance.
    _captionQuotaRequestId++;
    setState(() {
      _isGeneratingCaption = true;
      _isLoadingCaptionQuota = false;
      _aiCaptionErrorMessage = null;
    });

    try {
      final subscription = await _loadSubscription();
      if (!mounted || !session.isCurrent) return;

      if (!subscription.canUseAiCaptions) {
        if (!mounted) {
          return;
        }

        setState(() {
          _aiCaptionErrorMessage =
              'AI แคปชั่นใช้ได้ในแพ็กเกจ Starter 199 หรือ Pro 299';
        });
        return;
      }

      final audioS3Key = await _uploadSelectedClipAudioForAiCaption();

      if (audioS3Key == null || !mounted || !session.isCurrent) {
        return;
      }

      // Pro lets Gemini also "see" the clip: extract a few frames and upload
      // them so the backend can pass them to the model. Starter is audio-only.
      final selectedFrameKeys = subscription.isPro
          ? await _uploadAiCaptionFrames()
          : const <String>[];
      if (!mounted || !session.isCurrent) return;

      final guidance = _aiGuidanceController.text.trim();
      final generator =
          widget.generateRealClipCaption ?? _apiClient.generateCaptionFromClip;
      final caption = await generator(
        GenerateRealClipCaptionRequest(
          audioS3Key: audioS3Key,
          guidance: guidance.isEmpty ? null : guidance,
          selectedFrameKeys: selectedFrameKeys,
          deleteAfterUse: true,
        ),
      );
      final nextCaption = _formatRealClipCaption(caption);

      if (!mounted || !session.isCurrent) {
        return;
      }

      setState(() {
        _captionQuota = CaptionQuotaResult(
          plan: subscription.plan,
          quota: caption.quota,
        );
        _captionQuotaLoadFailed = false;
        _captionController.value = TextEditingValue(
          text: nextCaption,
          selection: TextSelection.collapsed(offset: nextCaption.length),
        );
      });
      quotaUpdated = true;
    } on ApiException catch (error) {
      if (!mounted || !session.isCurrent) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = error.message;
      });
    } on AiEditAudioExtractionException catch (error) {
      if (!mounted || !session.isCurrent) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted || !session.isCurrent) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = 'เชื่อมต่อ PostDee API ไม่ได้';
      });
    } catch (_) {
      if (!mounted || !session.isCurrent) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = 'เกิดข้อผิดพลาดระหว่างให้ AI คิดแคปชั่น';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingCaption = false;
        });
        // A provider failure may happen after the server reserved a use.
        if (!quotaUpdated) unawaited(_loadCaptionQuota());
      }
    }
  }

  Future<bool> _shouldApplyAutoWatermark() async {
    try {
      final settings =
          await widget.growthToolSettingsStore.loadSettings('auto_watermark');

      return settings?.isEnabled == true &&
          (settings?.isOptionEnabled('shop_logo') ?? true);
    } catch (_) {
      return false;
    }
  }

  Future<WatermarkedVideoResult> _applyAutoWatermark({
    required File inputFile,
    required String fileName,
  }) {
    final watermarkVideo =
        widget.watermarkVideo ?? FfmpegWatermarkVideoProcessor().call;

    return watermarkVideo(
      WatermarkVideoRequest(
        inputFile: inputFile,
        fileName: fileName,
      ),
    );
  }

  Future<void> _openCoverEditor() async {
    final localFilePath = _localFilePathController.text.trim();
    final videoName = (_selectedVideoName ?? '').trim();
    final videoFile = localFilePath.isEmpty ? null : File(localFilePath);

    if (videoFile == null || videoName.isEmpty || !videoFile.existsSync()) {
      setState(() {
        _errorMessage = 'เลือกวิดีโอจริงจากเครื่องก่อนแต่งหน้าปก';
        _successMessage = null;
      });
      return;
    }

    final request = CoverEditorRequest(
      videoFile: videoFile,
      videoName: videoName,
      platforms:
          SocialPlatform.values.where(_selectedPlatforms.contains).toList(),
      initialResult: _coverResult,
    );
    final result = widget.openCoverEditor != null
        ? await widget.openCoverEditor!(context, request)
        : await Navigator.of(context).push<CoverEditorResult>(
            MaterialPageRoute<CoverEditorResult>(
              builder: (context) => CoverEditorScreen(
                videoFile: request.videoFile,
                videoName: request.videoName,
                platforms: request.platforms,
                initialResult: request.initialResult,
                processCover: widget.coverImageProcessor,
              ),
            ),
          );

    if (result == null) return;
    if (!mounted) {
      await result.cleanupTemporaryFiles();
      return;
    }
    final previousCover = _coverResult;
    setState(() {
      _coverResult = result;
      _errorMessage = null;
      _successMessage = 'บันทึกหน้าปกแล้ว';
    });
    if (!identical(previousCover, result)) {
      _cleanupCoverAfterFrame(previousCover);
    }
  }

  Future<void> _removeCover() async {
    final cover = _coverResult;
    if (cover == null || _isSubmitting) return;

    final confirmed = await showPostDeeStatusSheet(
      context,
      data: const PostDeeStatusSheetData(
        icon: Icons.hide_image_outlined,
        iconColor: Color(0xFFF59E0B),
        iconTint: Color(0x24F59E0B),
        title: 'ใช้หน้าปกอัตโนมัติ?',
        body: 'หน้าปกที่แต่งไว้จะถูกลบ และระบบจะกลับไปเลือกภาพอัตโนมัติ',
        primaryLabel: 'ลบหน้าปก',
        secondaryLabel: 'ยกเลิก',
      ),
    );
    if (confirmed != true || !mounted || !identical(_coverResult, cover)) {
      return;
    }

    setState(() {
      _coverResult = null;
      _errorMessage = null;
      _successMessage = 'กลับมาใช้หน้าปกอัตโนมัติแล้ว';
    });
    _cleanupCoverAfterFrame(cover);
  }

  Future<CoverEditorResult> _readCoverForUpload({
    required File videoFile,
    required String fileName,
  }) async {
    final cover = _coverResult;
    if (cover == null) {
      throw const CoverImageException('ยังไม่ได้เลือกหน้าปก');
    }
    final coverFile = cover.imageFile;
    if (coverFile.existsSync() && coverFile.lengthSync() > 0) {
      return cover;
    }

    if (mounted) {
      setState(() {
        _successMessage = 'กำลังสร้างไฟล์หน้าปกใหม่...';
      });
    }
    final processor =
        widget.coverImageProcessor ?? FfmpegCoverImageProcessor().call;
    final regenerated = await processor(
      CoverImageRequest(
        videoFile: videoFile,
        fileName: fileName,
        design: cover.design,
        durationMs: cover.durationMs,
      ),
    );
    if (!mounted) {
      await regenerated.cleanupTemporaryFiles();
      throw const CoverImageException('ยกเลิกการสร้างหน้าปกแล้ว');
    }
    setState(() => _coverResult = regenerated);
    if (!identical(cover, regenerated)) {
      _cleanupCoverAfterFrame(cover);
    }
    return regenerated;
  }

  Future<void> _pickVideoFile() async {
    final picker = widget.pickVideo ?? GalleryVideoPicker().pickVideo;

    try {
      final video = await picker();

      if (!mounted || video == null) {
        return;
      }

      final fileName = video.name.trim().isNotEmpty
          ? video.name.trim()
          : _readFileNameFromPath(video.path);

      if (fileName.isEmpty ||
          video.path.trim().isEmpty ||
          video.sizeBytes < 1) {
        setState(() {
          _errorMessage = 'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ';
          _successMessage = null;
        });
        return;
      }

      final previousCover = _coverResult;
      setState(() {
        _selectedVideoName = fileName;
        _coverResult = null;
        _localFilePathController.text = video.path;
        _fileNameController.text = fileName;
        _sizeBytesController.text = video.sizeBytes.toString();
        _widthController.text = video.width?.toString() ?? '';
        _heightController.text = video.height?.toString() ?? '';
        _aiCaptionErrorMessage = null;
        _errorMessage = null;
        _successMessage = null;
      });
      _cleanupCoverAfterFrame(previousCover);
      unawaited(_analytics.logVideoSelected(
        hasDimensions: video.width != null && video.height != null,
      ));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'เลือกวิดีโอไม่ได้: $error';
        _successMessage = null;
      });
    }
  }

  /// Design screen #7: show the review summary before actually posting. When
  /// no clip is selected yet, skip straight to [_createPost] so its validation
  /// message shows instead of reviewing an empty post.
  Future<void> _reviewThenPost() async {
    if (_isLoadingConnections) {
      setState(() {
        _errorMessage = 'กำลังตรวจสอบช่องทางที่เชื่อมต่อ กรุณารอสักครู่';
        _successMessage = null;
      });
      return;
    }

    if (_selectedPlatforms.isEmpty) {
      final hasConnectionError = _connectionsErrorMessage != null;
      final shouldContinue = await showPostDeeStatusSheet(
        context,
        data: PostDeeStatusSheetData(
          icon: hasConnectionError
              ? Icons.cloud_off_rounded
              : Icons.link_off_rounded,
          iconColor: const Color(0xFFF59E0B),
          iconTint: const Color(0x24F59E0B),
          title: hasConnectionError
              ? 'ตรวจสอบช่องทางไม่ได้'
              : 'ยังไม่ได้เชื่อมช่องทาง',
          body: _connectionsErrorMessage ??
              'ต้องเชื่อมอย่างน้อย 1 ช่องทางก่อนจึงจะเริ่มโพสต์ได้',
          primaryLabel: hasConnectionError ? 'ลองใหม่' : 'ไปเชื่อมช่องทาง',
          secondaryLabel: 'ไว้ก่อน',
        ),
      );

      if (shouldContinue == true && mounted) {
        if (hasConnectionError) {
          await _loadConnections();
        } else {
          await _openConnections();
        }
      }
      return;
    }

    final selectedVideoName = (_selectedVideoName ?? '').trim();

    if (selectedVideoName.isEmpty) {
      await _createPost();
      return;
    }

    final watermarkEnabled = await _shouldApplyAutoWatermark();
    if (!mounted) return;
    if (_selectedPlatforms.isEmpty) {
      setState(() => _errorMessage = 'เลือกอย่างน้อย 1 ช่องทางก่อนโพสต์');
      return;
    }

    final reviewedCaption = _captionController.text.trim();
    final reviewedYoutubeTitle = _hasYoutube ? _youtubeTitleOverride : null;
    final textError = _postTextValidationError(
      caption: reviewedCaption,
      youtubeTitle: reviewedYoutubeTitle,
    );
    if (textError != null) {
      setState(() {
        _errorMessage = textError;
        _successMessage = null;
        if (_hasYoutube && _captionController.text.trim().isEmpty) {
          _isEditingYoutubeTitle = true;
        }
      });
      return;
    }

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PublishReviewScreen(
          videoName: selectedVideoName,
          caption: reviewedCaption,
          youtubeTitle: _hasYoutube
              ? reviewedYoutubeTitle ?? deriveYoutubeTitle(reviewedCaption)
              : null,
          platforms:
              SocialPlatform.values.where(_selectedPlatforms.contains).toList(),
          scheduledAt: _readScheduledAt(),
          watermarkEnabled: watermarkEnabled,
          coverResult: _coverResult,
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final selectedPlatforms =
        SocialPlatform.values.where(_selectedPlatforms.contains).toList();
    final action = await Navigator.of(context).push<PublishFlowAction>(
      MaterialPageRoute<PublishFlowAction>(
        builder: (context) => PublishFlowScreen(
          platforms: selectedPlatforms,
          isScheduled: _readScheduledAt() != null,
          publish: () => _createPost(
            reviewedCaption: reviewedCaption,
            reviewedYoutubeTitle: reviewedYoutubeTitle,
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (action == null && _pendingStatusSheet != null) {
      await _showPendingStatus();
      return;
    }

    switch (action) {
      case PublishFlowAction.finish:
        widget.onPublishFinished?.call();
      case null:
        break;
    }
  }

  Future<QueuedPostResult?> _createPost({
    String? reviewedCaption,
    String? reviewedYoutubeTitle,
  }) async {
    _pendingStatusSheet = null;
    _pickVideoAfterStatus = false;
    _pendingInlineError = null;
    final caption = reviewedCaption ?? _captionController.text.trim();
    final youtubeTitle = reviewedCaption != null
        ? reviewedYoutubeTitle
        : _hasYoutube
            ? _youtubeTitleOverride
            : null;
    final localFilePath = _localFilePathController.text.trim();
    final localVideoFile = localFilePath.isEmpty ? null : File(localFilePath);
    final fileName = _fileNameController.text.trim().isNotEmpty
        ? _fileNameController.text.trim()
        : localVideoFile == null
            ? ''
            : _readFileNameFromPath(localFilePath);
    var sizeBytes = _readPositiveInt(_sizeBytesController);
    final width = _readPositiveInt(_widthController);
    final height = _readPositiveInt(_heightController);
    final scheduledAt = _readScheduledAt();

    if (localVideoFile == null) {
      setState(() {
        _errorMessage = 'เลือกวิดีโอจริงจากเครื่องก่อนโพสต์';
        _successMessage = null;
      });
      return null;
    }

    if (!localVideoFile.existsSync()) {
      setState(() {
        _errorMessage = 'ไม่พบไฟล์วิดีโอในเครื่อง';
        _successMessage = null;
      });
      return null;
    }

    sizeBytes ??= localVideoFile.lengthSync();

    final textError = _postTextValidationError(
      caption: caption,
      youtubeTitle: youtubeTitle,
    );
    if (textError != null) {
      setState(() {
        _errorMessage = textError;
        _successMessage = null;
      });
      return null;
    }

    if (fileName.isEmpty) {
      setState(() {
        _errorMessage = 'ไฟล์วิดีโอไม่ถูกต้อง เลือกคลิปใหม่อีกครั้ง';
        _successMessage = null;
      });
      return null;
    }

    if (_scheduledAtController.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() {
        _errorMessage = 'เวลาตั้งโพสต์ต้องเป็นรูปแบบ ISO ที่ถูกต้อง';
        _successMessage = null;
      });
      return null;
    }

    if (scheduledAt != null && !scheduledAt.isAfter(widget.now())) {
      setState(() {
        _errorMessage = 'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต';
        _successMessage = null;
      });
      return null;
    }

    if (scheduledAt != null &&
        !isPostScheduleWithinLimit(
          scheduledAt: scheduledAt,
          now: widget.now(),
        )) {
      setState(() {
        _errorMessage = 'ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด 30 วัน';
        _successMessage = null;
      });
      return null;
    }

    if (width != null &&
        height != null &&
        !_isVerticalNineBySixteen(width: width, height: height)) {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
      _pendingInlineError = 'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920';
      _pendingStatusSheet = const PostDeeStatusSheetData(
        icon: Icons.crop_portrait_rounded,
        iconColor: Color(0xFFEC4899),
        iconTint: Color(0x24EC4899),
        title: 'สัดส่วนวิดีโอไม่ใช่ 9:16',
        body: 'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920',
        primaryLabel: 'เลือกวิดีโอใหม่',
        secondaryLabel: 'ปิด',
      );
      _pickVideoAfterStatus = true;
      return null;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    WatermarkedVideoResult? watermarkedVideoForCleanup;
    try {
      final subscription = await _loadSubscription();

      if (scheduledAt != null) {
        if (!subscription.canSchedule) {
          if (!mounted) {
            return null;
          }

          setState(() {
            _errorMessage =
                'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299';
          });
          return null;
        }
      }

      if (subscription.requiresPhoneVerification) {
        if (!mounted) {
          return null;
        }

        setState(() {
          _errorMessage = 'ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน';
        });
        return null;
      }

      var uploadVideoFileForRequest = localVideoFile;
      var uploadFileName = fileName;
      var uploadSizeBytes = sizeBytes;
      var didApplyWatermark = false;
      final shouldApplyWatermark = await _shouldApplyAutoWatermark();
      unawaited(_analytics.logPublishStarted(
        platformCount: _selectedPlatforms.length,
        isScheduled: scheduledAt != null,
        watermarkEnabled: shouldApplyWatermark,
      ));

      if (shouldApplyWatermark) {
        if (!mounted) {
          return null;
        }

        setState(() {
          _successMessage = 'กำลังใส่ลายน้ำวิดีโอ...';
        });

        final watermarkedVideo = await _applyAutoWatermark(
          inputFile: localVideoFile,
          fileName: fileName,
        );

        watermarkedVideoForCleanup = watermarkedVideo;
        uploadVideoFileForRequest = watermarkedVideo.file;
        uploadFileName = watermarkedVideo.fileName;
        uploadSizeBytes = watermarkedVideo.sizeBytes;
        didApplyWatermark = true;
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      late final UploadResult upload;
      try {
        upload = await createAndUploadFileWithRetry(
          request: CreateUploadRequest(
            fileName: uploadFileName,
            contentType: 'video/mp4',
            sizeBytes: uploadSizeBytes,
            width: width,
            height: height,
          ),
          file: uploadVideoFileForRequest,
          createUpload: createUpload,
          uploadFile: uploadVideoFile,
          onRetry: () {
            if (mounted) {
              setState(() {
                _successMessage = 'ลิงก์อัปโหลดหมดอายุ กำลังลองใหม่...';
              });
            }
          },
        );
      } finally {
        await watermarkedVideoForCleanup?.cleanupTemporaryFiles();
        watermarkedVideoForCleanup = null;
      }
      String? coverImageS3Key;
      var selectedCover = _coverResult;
      final shouldUploadCoverImage = selectedCover != null &&
          _selectedPlatforms.any(
            (platform) =>
                platform == SocialPlatform.instagramReels ||
                platform == SocialPlatform.facebookReels,
          );
      if (shouldUploadCoverImage) {
        final cover = await _readCoverForUpload(
          videoFile: localVideoFile,
          fileName: fileName,
        );
        selectedCover = cover;
        if (mounted) {
          setState(() {
            _successMessage = 'กำลังอัปโหลดหน้าปก...';
          });
        }
        final coverFile = cover.imageFile;
        final coverLease = cover.retainTemporaryFiles();
        try {
          final coverUpload = await createAndUploadFileWithRetry(
            request: CreateUploadRequest(
              fileName: 'postdee-cover.jpg',
              contentType: 'image/jpeg',
              sizeBytes: coverFile.lengthSync(),
              width: 1080,
              height: 1920,
            ),
            file: coverFile,
            createUpload: createUpload,
            uploadFile: uploadVideoFile,
            onRetry: () {
              if (mounted) {
                setState(() {
                  _successMessage = 'ลิงก์อัปโหลดหน้าปกหมดอายุ กำลังลองใหม่...';
                });
              }
            },
          );
          coverImageS3Key = coverUpload.videoS3Key;
        } finally {
          await coverLease?.release();
        }
      }
      final createPost = widget.createPost ?? _apiClient.createPost;
      final post = await createPost(
        CreatePostRequest(
          caption: caption,
          youtubeTitle: youtubeTitle,
          videoS3Key: upload.videoS3Key,
          platforms:
              _selectedPlatforms.map((platform) => platform.apiValue).toList(),
          scheduledAt: scheduledAt,
          coverImageS3Key: coverImageS3Key,
          coverFrameTimeMs: selectedCover?.coverFrameTimeMs,
        ),
      );

      if (identical(_coverResult, selectedCover)) {
        if (mounted) {
          setState(() => _coverResult = null);
        } else {
          _coverResult = null;
        }
      }
      _cleanupCoverAfterFrame(selectedCover);

      unawaited(_analytics.logPublishSucceeded(
        platformCount: post.platforms.length,
        isScheduled: scheduledAt != null,
      ));

      if (!mounted) {
        return null;
      }

      if (scheduledAt != null) {
        widget.onScheduledPostCreated?.call(post);
      }

      setState(() {
        final watermarkText = didApplyWatermark ? 'ใส่ลายน้ำแล้ว · ' : '';
        _successMessage =
            '$watermarkTextจัดคิวโพสต์ ${post.platforms.length} แพลตฟอร์มแล้ว: ${post.id}';
      });
      return post;
    } on CoverImageException catch (error) {
      unawaited(_analytics.logPublishFailed(reason: 'cover'));
      if (!mounted) return null;
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
      _setUploadStatus(error.message);
      return null;
    } on WatermarkVideoException catch (error) {
      unawaited(_analytics.logPublishFailed(reason: 'watermark'));
      if (!mounted) {
        return null;
      }

      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
      _setUploadStatus(error.message);
      return null;
    } on ApiException catch (error) {
      unawaited(_analytics.logPublishFailed(reason: 'api'));
      if (!mounted) {
        return null;
      }

      setState(() {
        _errorMessage = null;
      });
      _setUploadStatus(error.message);
      return null;
    } on SocketException {
      unawaited(_analytics.logPublishFailed(reason: 'network'));
      if (!mounted) {
        return null;
      }

      setState(() {
        _errorMessage = null;
      });
      _setUploadStatus('เชื่อมต่อ PostDee API ไม่ได้');
      return null;
    } catch (error) {
      unawaited(_analytics.logPublishFailed(reason: 'unknown'));
      if (!mounted) {
        return null;
      }

      setState(() {
        _errorMessage = null;
      });
      _setUploadStatus('เกิดข้อผิดพลาดระหว่างสร้างโพสต์');
      return null;
    } finally {
      await watermarkedVideoForCleanup?.cleanupTemporaryFiles();
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _setUploadStatus(String message) {
    _pendingInlineError = message;
    _pendingStatusSheet = PostDeeStatusSheetData(
      icon: Icons.cloud_off_rounded,
      iconColor: const Color(0xFFEF4444),
      iconTint: const Color(0x1FEF4444),
      title: 'อัปโหลด/คิวโพสต์ขัดข้อง',
      body: message,
      primaryLabel: 'กลับไปตรวจสอบ',
      secondaryLabel: null,
    );
    _pickVideoAfterStatus = false;
  }

  Future<void> _showPendingStatus() async {
    final data = _pendingStatusSheet;
    final shouldPickVideo = _pickVideoAfterStatus;
    final inlineError = _pendingInlineError;
    _pendingStatusSheet = null;
    _pickVideoAfterStatus = false;
    _pendingInlineError = null;
    if (data == null || !mounted) return;

    final confirmed = await showPostDeeStatusSheet(context, data: data);
    if (mounted && inlineError != null) {
      setState(() => _errorMessage = inlineError);
    }
    if (confirmed == true && shouldPickVideo && mounted) {
      await _pickVideoFile();
    }
  }

  void _setPlatformSelected(SocialPlatform platform, bool isSelected) {
    setState(() {
      if (isSelected && _connectedPlatforms.contains(platform)) {
        _selectedPlatforms.add(platform);
      } else {
        _selectedPlatforms.remove(platform);
      }
    });
  }

  void _clearSchedule() {
    setState(() {
      _selectedScheduleDate = null;
      _selectedScheduleTime = null;
      _scheduledAtController.clear();
    });
  }

  void _useSuggestedSchedule() {
    setState(() {
      _selectedScheduleDate ??= _scheduleDateFromToday(1);
      _selectedScheduleTime ??= const TimeOfDay(hour: 18, minute: 30);
      _syncScheduledAt();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            key: const ValueKey('uploader-scroll'),
            padding: const EdgeInsets.fromLTRB(16, AppTheme.spaceMd, 16, 116),
            children: [
              const _UploadPageHeader(),
              const SizedBox(height: AppTheme.spaceLg),
              const _UploadStepHeader(
                key: ValueKey('uploader-step-video'),
                title: '1 · เลือกวิดีโอ',
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _VideoPreviewCard(
                videoName: _selectedVideoName,
                coverImagePath: _coverResult?.localImagePath,
                coverImageBytes: _coverResult?.imageBytes,
                isSubmitting: _isSubmitting,
                onPickVideo: _pickVideoFile,
              ),
              if (_selectedVideoName != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: OutlinedButton.icon(
                    key: const ValueKey('uploader-cover-edit-button'),
                    onPressed: _isSubmitting ? null : _openCoverEditor,
                    icon: Icon(
                      _coverResult == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.edit_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _coverResult == null ? 'แต่งหน้าปก' : 'แก้หน้าปก',
                    ),
                  ),
                ),
                if (_coverResult != null) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'เลือกเฟรมที่ ${formatReviewVideoClock(Duration(milliseconds: _coverResult!.coverFrameTimeMs))}',
                      key: const ValueKey('uploader-cover-time'),
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('uploader-cover-remove-button'),
                      onPressed: _isSubmitting ? null : _removeCover,
                      icon: const Icon(Icons.hide_image_outlined, size: 17),
                      label: const Text('ลบหน้าปก · ใช้ปกอัตโนมัติ'),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppTheme.spaceLg),
              _PlatformSelectorSection(
                selectedPlatforms: _selectedPlatforms,
                connectedPlatforms: _connectedPlatforms,
                isLoadingConnections: _isLoadingConnections,
                connectionsErrorMessage: _connectionsErrorMessage,
                onPlatformChanged: _setPlatformSelected,
                onOpenConnections: _openConnections,
                onRetryConnections: _loadConnections,
              ),
              const SizedBox(height: AppTheme.spaceXl),
              const _UploadStepHeader(
                key: ValueKey('uploader-step-caption'),
                title: '3 · แคปชั่น',
              ),
              const SizedBox(height: AppTheme.spaceSm),
              _buildCaptionCard(context),
              const SizedBox(height: AppTheme.spaceXl),
              const _UploadStepHeader(
                key: ValueKey('uploader-step-schedule'),
                title: '4 · เวลาโพสต์',
              ),
              const SizedBox(height: AppTheme.spaceSm),
              SizedBox(
                key: const ValueKey('uploader-schedule-panel'),
                width: double.infinity,
                child: PostDeeCard(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  glowColor: AppTheme.accent,
                  child: _SchedulePanel(
                    scheduledAtController: _scheduledAtController,
                    selectedDate: _selectedScheduleDate,
                    selectedTime: _selectedScheduleTime,
                    onPostNow: _clearSchedule,
                    onSchedule: _useSuggestedSchedule,
                    onQuickDaySelected: _setQuickScheduleDay,
                    onTimeSelected: _setQuickScheduleTime,
                    onPickCustomTime: _pickCustomScheduleTime,
                    onPickCustomDate: _pickCustomScheduleDate,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              _AdvancedUploadToolsSection(
                advancedModeEnabled: _isAdvancedModeEnabled,
                onAdvancedModeChanged: (value) {
                  setState(() {
                    _isAdvancedModeEnabled = value;
                  });
                },
              ),
              const SizedBox(height: AppTheme.spaceLg),
            ],
          ),
        ),
        _buildStickyActionBar(context),
      ],
    );
  }

  Widget _buildCaptionCard(BuildContext context) {
    return PostDeeCard(
      glowColor: AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AiCaptionPanel(
            guidanceController: _aiGuidanceController,
            selectedVideoName: _selectedVideoName,
            isGenerating: _isGeneratingCaption,
            errorMessage: _aiCaptionErrorMessage,
            onGenerate: _generateAiCaption,
            quota: _captionQuota,
            isLoadingQuota: _isLoadingCaptionQuota,
            quotaLoadFailed: _captionQuotaLoadFailed,
            onRetryQuota: _loadCaptionQuota,
          ),
          const SizedBox(height: AppTheme.spaceMd),
          TextField(
            key: const ValueKey('uploader-caption-field'),
            controller: _captionController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'แคปชั่น',
              hintText: 'เขียนแคปชั่นของคุณ...',
            ),
          ),
          if (_hasYoutube) ...[
            const SizedBox(height: AppTheme.spaceMd),
            _buildYoutubeTitleSection(context),
          ],
          const SizedBox(height: AppTheme.spaceMd),
          Row(
            children: [
              Expanded(
                child: Text(
                  'เทมเพลต',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              OutlinedButton(
                onPressed: _isLoadingTemplates ? null : _loadTemplates,
                child: Text(_isLoadingTemplates
                    ? 'กำลังโหลดเทมเพลต...'
                    : 'โหลดเทมเพลต'),
              ),
            ],
          ),
          if (_templateErrorMessage != null) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              _templateErrorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_templates.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spaceSm),
            ..._templates.map(
              (template) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.text_snippet_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(template.title),
                          const SizedBox(height: AppTheme.spaceXs),
                          Text(
                            template.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _insertTemplate(template),
                      child: const Text('ใส่แคปชั่น'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasYoutube =>
      _selectedPlatforms.contains(SocialPlatform.youtubeShorts);

  String get _effectiveYoutubeTitle =>
      _youtubeTitleOverride ?? deriveYoutubeTitle(_captionController.text);

  void _syncAutomaticYoutubeTitle() {
    if (_youtubeTitleOverride == null && _isEditingYoutubeTitle) {
      _youtubeTitleController.text = deriveYoutubeTitle(_captionController.text);
    }
  }

  String? _postTextValidationError({
    required String caption,
    required String? youtubeTitle,
  }) {
    if (caption.isEmpty && (!_hasYoutube || _selectedPlatforms.length > 1)) {
      return 'เพิ่มแคปชั่นก่อนโพสต์';
    }
    final captionError = validatePostCaption(
      caption,
      includesYoutube: _hasYoutube,
      includesOtherPlatforms: _selectedPlatforms
          .any((platform) => platform != SocialPlatform.youtubeShorts),
    );
    if (captionError != null) return captionError;
    if (_hasYoutube) {
      final title = youtubeTitle ?? deriveYoutubeTitle(caption);
      final error = validateYoutubeTitle(title);
      if (error != null) return error;
      if (title.isEmpty) {
        return 'เพิ่มแคปชันหรือชื่อคลิป YouTube ก่อนโพสต์';
      }
    }
    return null;
  }

  Widget _buildYoutubeTitleSection(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _captionController,
      builder: (context, _, __) {
        final title = _effectiveYoutubeTitle;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ชื่อที่จะปรากฏบน YouTube Shorts',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                title.isEmpty ? 'ชื่อจะเติมจากแคปชันอัตโนมัติ' : title,
                key: const ValueKey('uploader-youtube-title-preview'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'แคปชันฉบับเต็มและแฮชแท็กจะใช้เป็นคำอธิบาย',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!_isEditingYoutubeTitle)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('uploader-youtube-title-edit'),
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            _youtubeTitleController.text = title;
                            setState(() => _isEditingYoutubeTitle = true);
                          },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('ปรับชื่อเฉพาะ YouTube'),
                  ),
                ),
              if (_isEditingYoutubeTitle) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('uploader-youtube-title-field'),
                  controller: _youtubeTitleController,
                  enabled: !_isSubmitting,
                  minLines: 1,
                  maxLines: 2,
                  onChanged: (value) => setState(() {
                    _youtubeTitleOverride =
                        value.trim().isEmpty ? null : value.trim();
                  }),
                  decoration: InputDecoration(
                    labelText: 'ชื่อคลิป YouTube',
                    helperText: 'เว้นว่างเพื่อใช้ชื่อจากแคปชัน',
                    counterText:
                        '${_youtubeTitleController.text.trim().runes.length}/$youtubeTitleMaxLength',
                    errorText: validateYoutubeTitle(_youtubeTitleController.text),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('uploader-youtube-title-reset'),
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _youtubeTitleOverride = null;
                              _isEditingYoutubeTitle = false;
                              _youtubeTitleController.clear();
                            });
                          },
                    child: const Text('ใช้ชื่อจากแคปชัน'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // Solid card footer with a hairline top border, per the prototype's
  // publish bar (no dark gradient).
  Widget _buildStickyActionBar(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        key: const ValueKey('uploader-sticky-action-bar'),
        decoration: BoxDecoration(
          color: AppTheme.glass,
          border: Border(
            top: BorderSide(color: AppTheme.borderSoft),
          ),
        ),
        child: Padding(
          // extendBody lets the floating capsule nav overlap the body, so
          // lift the sticky actions above it via the ambient bottom inset.
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            10 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                PostDeeNotice(
                  message: _errorMessage!,
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.error_outline,
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
              if (_successMessage != null) ...[
                PostDeeNotice(
                  message: _successMessage!,
                  color: AppTheme.successInk,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
              _GradientActionButton(
                key: const ValueKey('uploader-sticky-post-button'),
                label: _isSubmitting ? 'กำลังโพสต์...' : 'โพสต์',
                icon: Icons.send_rounded,
                onPressed: _isSubmitting ? null : _reviewThenPost,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadPageHeader extends StatelessWidget {
  const _UploadPageHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'สร้างโพสต์ใหม่',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'อัปโหลดครั้งเดียว แล้วเตรียมโพสต์ไปทุกช่องทาง',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UploadStepHeader extends StatelessWidget {
  const _UploadStepHeader({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _AdvancedUploadToolsSection extends StatelessWidget {
  const _AdvancedUploadToolsSection({
    required this.advancedModeEnabled,
    required this.onAdvancedModeChanged,
  });

  final bool advancedModeEnabled;
  final ValueChanged<bool> onAdvancedModeChanged;

  static const _epTrimmerDetail = GrowthToolDetail(
    id: 'ep_trimmer',
    title: 'ตัดคลิปเป็น EP',
    description: 'ตรวจความยาวคลิปก่อนโพสต์ และเตรียมร่าง EP.1 / EP.2 ให้',
    status: 'เร็ว ๆ นี้',
    icon: Icons.content_cut,
    color: Color(0xFFFFD166),
    prototypeOnly: true,
    settings: [
      GrowthToolSettingOption(
        id: 'platform_duration_check',
        label: 'ดูความยาวคลิปและข้อจำกัดของแต่ละแพลตฟอร์ม',
      ),
      GrowthToolSettingOption(
        id: 'ep_title_draft',
        label: 'เตรียมชื่อ EP.1 / EP.2 / EP.3',
      ),
      GrowthToolSettingOption(
        id: 'next_ep_comment_draft',
        label: 'ร่างข้อความคอมเมนต์ลิงก์ EP ถัดไปเพื่อให้เจ้าของร้านอนุมัติ',
      ),
    ],
  );

  static const _watermarkDetail = GrowthToolDetail(
    id: 'auto_watermark',
    title: 'ใส่ลายน้ำอัตโนมัติ',
    description: 'ฝังโลโก้ PostDee ที่มุมขวาล่างของวิดีโอก่อนอัปโหลด',
    status: 'ใช้โลโก้ PostDee มุมขวาล่าง',
    icon: Icons.shield_outlined,
    color: AppTheme.success,
    settings: [
      GrowthToolSettingOption(
        id: 'shop_logo',
        label: 'ใช้โลโก้ PostDee มุมขวาล่างก่อนอัปโหลด',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('uploader-advanced-tools-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.tune_outlined,
              color: AppTheme.textSecondary,
              size: 18,
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                'เครื่องมือเสริม',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Text(
              'เลือกได้หลายอย่าง',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Row(
          children: const [
            Expanded(
              child: _CompactUploadToolButton(
                key: ValueKey('uploader-tool-ep-trimmer'),
                detail: _epTrimmerDetail,
              ),
            ),
            SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: _CompactUploadToolButton(
                key: ValueKey('uploader-tool-auto-watermark'),
                detail: _watermarkDetail,
              ),
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border:
                Border.all(color: AppTheme.borderSoft.withValues(alpha: 0.84)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'โหมดตั้งค่าขั้นสูง',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        advancedModeEnabled
                            ? 'ซับ/โทนสี/CTA · ให้ปรับใต้การ์ดทันที'
                            : 'ปิดไว้เพื่อใช้ค่าพื้นฐานของ PostDee',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: advancedModeEnabled,
                  activeThumbColor: AppTheme.accent,
                  activeTrackColor: AppTheme.accent.withValues(alpha: 0.24),
                  onChanged: onAdvancedModeChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactUploadToolButton extends StatelessWidget {
  const _CompactUploadToolButton({
    required this.detail,
    super.key,
  });

  final GrowthToolDetail detail;

  @override
  Widget build(BuildContext context) {
    final color = detail.color;

    return Semantics(
      button: true,
      label: detail.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => showGrowthToolDetailSheet(context, detail),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: AppTheme.borderSoft.withValues(alpha: 0.84),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                  ),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      detail.icon,
                      color: AppTheme.inkFor(color),
                      size: 19,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        detail.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppTheme.textMuted,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({
    required this.videoName,
    required this.coverImagePath,
    required this.coverImageBytes,
    required this.isSubmitting,
    required this.onPickVideo,
  });

  final String? videoName;
  final String? coverImagePath;
  final Uint8List? coverImageBytes;
  final bool isSubmitting;
  final VoidCallback onPickVideo;

  @override
  Widget build(BuildContext context) {
    final hasVideo = videoName != null;

    return Center(
      child: SizedBox(
        width: 150,
        height: 230,
        child: InkWell(
          key: const ValueKey('uploader-video-preview-picker'),
          borderRadius: BorderRadius.circular(18),
          onTap: isSubmitting ? null : onPickVideo,
          child: hasVideo ? _buildSelected(context) : _buildEmpty(context),
        ),
      ),
    );
  }

  // Dashed placeholder inviting a 9:16 pick, per the prototype.
  Widget _buildEmpty(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectBorderPainter(
        color: AppTheme.border,
        radius: 18,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                size: 28,
                color: AppTheme.accentCyanInk,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'เลือกวิดีโอ 9:16',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Reels · Shorts\nTikTok',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Selected clip: green gradient stand-in with the 9:16 check badge.
  Widget _buildSelected(BuildContext context) {
    final hasCoverBytes = coverImageBytes?.isNotEmpty == true;
    final hasCoverFile =
        coverImagePath != null && File(coverImagePath!).existsSync();
    final hasCoverImage = hasCoverBytes || hasCoverFile;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F3A2C), Color(0xFF0E9F6E)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.5),
            blurRadius: 26,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (hasCoverImage)
            Positioned.fill(
              child: hasCoverBytes
                  ? Image.memory(
                      coverImageBytes!,
                      key: const ValueKey('uploader-cover-preview-image'),
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      File(coverImagePath!),
                      key: const ValueKey('uploader-cover-preview-image'),
                      fit: BoxFit.cover,
                    ),
            ),
          Center(
            child: !hasCoverImage
                ? Icon(
                    Icons.play_circle_rounded,
                    size: 46,
                    color: Colors.white.withValues(alpha: 0.92),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Text(
              videoName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '9:16',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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

class _PlatformSelectorSection extends StatelessWidget {
  const _PlatformSelectorSection({
    required this.selectedPlatforms,
    required this.connectedPlatforms,
    required this.isLoadingConnections,
    required this.connectionsErrorMessage,
    required this.onPlatformChanged,
    required this.onOpenConnections,
    required this.onRetryConnections,
  });

  final Set<SocialPlatform> selectedPlatforms;
  final Set<SocialPlatform> connectedPlatforms;
  final bool isLoadingConnections;
  final String? connectionsErrorMessage;
  final void Function(SocialPlatform platform, bool isSelected)
      onPlatformChanged;
  final VoidCallback onOpenConnections;
  final VoidCallback onRetryConnections;

  // Short per-platform descriptions from the prototype's connection list.
  static const _subLabels = {
    SocialPlatform.tiktok: 'โพสต์คลิปสั้นไป TikTok อัตโนมัติ',
    SocialPlatform.youtubeShorts: 'อัปขึ้น YouTube Shorts จากคลิปเดียว',
    SocialPlatform.instagramReels: 'แชร์ Reels ไป Instagram',
    SocialPlatform.facebookReels: 'โพสต์ Reels ลงเพจ Facebook',
    SocialPlatform.shopeeVideo: 'โพสต์วิดีโอขึ้น Shopee Video',
    SocialPlatform.lazadaVideo: 'โพสต์วิดีโอขึ้น Lazada Video',
  };

  @override
  Widget build(BuildContext context) {
    final visiblePlatforms = isLoadingConnections
        ? const <SocialPlatform>[]
        : connectablePlatforms
            .where(connectedPlatforms.contains)
            .toList(growable: false);
    final hasConnectedPlatforms = visiblePlatforms.isNotEmpty;
    final statusColor = hasConnectedPlatforms
        ? AppTheme.accentCyanInk
        : const Color(0xFFB5740B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '2 · เลือกช่องทาง',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              isLoadingConnections
                  ? 'กำลังตรวจสอบ'
                  : 'เลือกแล้ว ${selectedPlatforms.length} ช่องทาง',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentCyanInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          enabled: !isLoadingConnections,
          label: isLoadingConnections
              ? 'กำลังตรวจสอบช่องทาง'
              : connectionsErrorMessage ??
                  (visiblePlatforms.isEmpty
                      ? 'ยังไม่ได้เชื่อมต่อช่องทาง'
                      : 'เชื่อมต่อแล้ว ${visiblePlatforms.length} ช่องทาง'),
          child: GestureDetector(
            onTap: isLoadingConnections
                ? null
                : connectionsErrorMessage != null
                    ? onRetryConnections
                    : onOpenConnections,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isLoadingConnections
                        ? Icons.sync_rounded
                        : visiblePlatforms.isEmpty
                            ? Icons.link_off_rounded
                            : Icons.check_circle_outline_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isLoadingConnections
                              ? 'กำลังตรวจสอบช่องทาง...'
                              : connectionsErrorMessage ??
                                  (visiblePlatforms.isEmpty
                                      ? 'ยังไม่ได้เชื่อมต่อช่องทาง'
                                      : 'เชื่อมต่อแล้ว ${visiblePlatforms.length} ช่องทาง'),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: hasConnectedPlatforms
                                ? AppTheme.accentCyanInk
                                : AppTheme.isLightMode
                                    ? const Color(0xFF8A5908)
                                    : const Color(0xFFF3C173),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          isLoadingConnections
                              ? 'รอสักครู่ ระบบกำลังโหลดสถานะล่าสุด'
                              : connectionsErrorMessage != null
                                  ? 'ลองใหม่ หรือไปจัดการช่องทางที่เชื่อมต่อ'
                                  : visiblePlatforms.isEmpty
                                      ? 'เชื่อมต่อบัญชีโซเชียลก่อนเริ่มโพสต์'
                                      : 'เลือกเฉพาะช่องทางที่ต้องการโพสต์รอบนี้',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasConnectedPlatforms
                                ? AppTheme.textSecondary
                                : AppTheme.isLightMode
                                    ? const Color(0xFFA06A12)
                                    : const Color(0xFFD9AC5E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isLoadingConnections)
                        Text(
                          connectionsErrorMessage != null
                              ? 'ลองใหม่'
                              : hasConnectedPlatforms
                                  ? 'จัดการ'
                                  : 'ไปเชื่อมช่องทาง',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        color: statusColor,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (connectionsErrorMessage != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('uploader-open-connections'),
              onPressed: onOpenConnections,
              icon: const Icon(Icons.link_rounded, size: 17),
              label: const Text('ไปหน้าการเชื่อมต่อ'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentCyanInk,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (visiblePlatforms.isNotEmpty)
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
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
                for (var index = 0;
                    index < visiblePlatforms.length;
                    index += 1) ...[
                  if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
                  _PlatformRow(
                    platform: visiblePlatforms[index],
                    subLabel: _subLabels[visiblePlatforms[index]] ?? '',
                    isSelected: selectedPlatforms.contains(
                      visiblePlatforms[index],
                    ),
                    onChanged: (next) => onPlatformChanged(
                      visiblePlatforms[index],
                      next,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.platform,
    required this.subLabel,
    required this.isSelected,
    required this.onChanged,
  });

  final SocialPlatform platform;
  final String subLabel;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: platform.label,
      button: true,
      enabled: true,
      selected: isSelected,
      child: InkWell(
        key: ValueKey('uploader-platform-${platform.apiValue}'),
        onTap: () => onChanged(!isSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SocialPlatformLogo(platform: platform, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platform.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ExcludeSemantics(
                child: _PrototypeSwitch(isOn: isSelected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 46x27 pill switch with a 21px white knob, per the design handoff.
class _PrototypeSwitch extends StatelessWidget {
  const _PrototypeSwitch({required this.isOn});

  final bool isOn;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isOn ? AppTheme.accent : AppTheme.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33122018),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SizedBox.square(dimension: 21),
        ),
      ),
    );
  }
}

class _AiCaptionPanel extends StatelessWidget {
  const _AiCaptionPanel({
    required this.guidanceController,
    required this.selectedVideoName,
    required this.isGenerating,
    required this.onGenerate,
    required this.quota,
    required this.isLoadingQuota,
    required this.quotaLoadFailed,
    required this.onRetryQuota,
    this.errorMessage,
  });

  final TextEditingController guidanceController;
  final String? selectedVideoName;
  final bool isGenerating;
  final String? errorMessage;
  final VoidCallback onGenerate;
  final CaptionQuotaResult? quota;
  final bool isLoadingQuota;
  final bool quotaLoadFailed;
  final VoidCallback onRetryQuota;

  @override
  Widget build(BuildContext context) {
    final clipName = selectedVideoName?.trim();
    final quotaExhausted =
        quota?.isPaid == true && quota!.quota.remainingThisMonth == 0;

    return DecoratedBox(
      key: const ValueKey('uploader-ai-caption-panel'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.borderSoft),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.16),
            AppTheme.glassDeep,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: AppTheme.accent,
                  size: 18,
                ),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(
                    'AI แคปชั่นจากคลิปจริง',
                    key: const ValueKey('uploader-ai-real-clip-title'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Text(
              clipName == null || clipName.isEmpty
                  ? 'เลือกคลิปก่อน แล้วให้ AI ฟังเสียงจริงในคลิปเพื่อทำ Hook, SEO และแฮชแท็ก'
                  : 'คลิปที่เลือก: $clipName',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('uploader-ai-guidance-field'),
              controller: guidanceController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'คำแนะนำเพิ่มเติม (ถ้ามี)',
                hintText:
                    'เช่น ขอขายจริงใจ / อยากได้แนวตลก / เน้นลูกค้าแม่และเด็ก',
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              PostDeeNotice(
                message: errorMessage!,
                color: Theme.of(context).colorScheme.error,
                icon: Icons.error_outline,
              ),
            ],
            const SizedBox(height: 10),
            if (isLoadingQuota) ...[
              Text(
                'กำลังโหลดโควตา...',
                key: const ValueKey('uploader-ai-quota-loading'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: AppTheme.spaceSm),
            ] else if (quotaLoadFailed) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'โหลดโควตาไม่สำเร็จ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('uploader-ai-quota-retry'),
                    tooltip: 'โหลดโควตาอีกครั้ง',
                    onPressed: isGenerating ? null : onRetryQuota,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
            ] else if (quota?.isPaid == true) ...[
              CaptionQuotaStrip(plan: quota!.plan, quota: quota!.quota),
              const SizedBox(height: AppTheme.spaceSm),
            ],
            PostDeeGradientButton(
              key: const ValueKey('uploader-ai-generate-button'),
              label: isGenerating
                  ? 'AI กำลังฟังคลิป...'
                  : quotaExhausted
                      ? 'โควตา AI เดือนนี้หมดแล้ว'
                      : 'ให้ AI ช่วยเขียน',
              icon: Icons.auto_awesome,
              onPressed: isGenerating || quotaExhausted ? null : onGenerate,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDayOption {
  const _ScheduleDayOption({
    required this.label,
    required this.daysFromToday,
    required this.keySuffix,
  });

  final String label;
  final int daysFromToday;
  final String keySuffix;
}

class _ScheduleTimeOption {
  const _ScheduleTimeOption({
    required this.label,
    required this.time,
    required this.keySuffix,
  });

  final String label;
  final TimeOfDay time;
  final String keySuffix;
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({
    required this.scheduledAtController,
    required this.selectedDate,
    required this.selectedTime,
    required this.onPostNow,
    required this.onSchedule,
    required this.onQuickDaySelected,
    required this.onTimeSelected,
    required this.onPickCustomTime,
    required this.onPickCustomDate,
  });

  static const _dayOptions = [
    _ScheduleDayOption(
      label: 'วันนี้',
      daysFromToday: 0,
      keySuffix: 'today',
    ),
    _ScheduleDayOption(
      label: 'พรุ่งนี้',
      daysFromToday: 1,
      keySuffix: 'tomorrow',
    ),
  ];

  static const _timeOptions = [
    _ScheduleTimeOption(
      label: '09:00',
      time: TimeOfDay(hour: 9, minute: 0),
      keySuffix: '0900',
    ),
    _ScheduleTimeOption(
      label: '12:00',
      time: TimeOfDay(hour: 12, minute: 0),
      keySuffix: '1200',
    ),
    _ScheduleTimeOption(
      label: '18:30',
      time: TimeOfDay(hour: 18, minute: 30),
      keySuffix: '1830',
    ),
  ];

  static const _thaiMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  final TextEditingController scheduledAtController;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final VoidCallback onPostNow;
  final VoidCallback onSchedule;
  final ValueChanged<int> onQuickDaySelected;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final VoidCallback onPickCustomTime;
  final VoidCallback onPickCustomDate;

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  bool _isSameTime(TimeOfDay left, TimeOfDay right) =>
      left.hour == right.hour && left.minute == right.minute;

  _ScheduleDayOption? _readQuickSelectedDay(DateTime date, DateTime today) {
    for (final option in _dayOptions) {
      final optionDate = today.add(Duration(days: option.daysFromToday));

      if (_isSameDate(date, optionDate)) {
        return option;
      }
    }

    return null;
  }

  bool _isQuickTime(TimeOfDay time) {
    for (final option in _timeOptions) {
      if (_isSameTime(time, option.time)) {
        return true;
      }
    }

    return false;
  }

  String _formatDate(DateTime date) {
    final today = _todayDate();

    if (_isSameDate(date, today)) {
      return 'วันนี้';
    }

    if (_isSameDate(date, today.add(const Duration(days: 1)))) {
      return 'พรุ่งนี้';
    }

    return '${date.day} ${_thaiMonths[date.month - 1]} ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final hasSchedule = scheduledAtController.text.trim().isNotEmpty &&
        selectedDate != null &&
        selectedTime != null;
    final today = _todayDate();
    final quickSelectedDay = selectedDate == null
        ? null
        : _readQuickSelectedDay(selectedDate!, today);
    final hasCustomTime = selectedTime != null && !_isQuickTime(selectedTime!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              ),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(
                  Icons.calendar_month,
                  color: AppTheme.accent,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Text(
              'ตั้งเวลาโพสต์',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ScheduleModeButton(
                label: 'โพสต์เลย',
                testKey: const ValueKey('uploader-schedule-now'),
                icon: Icons.flash_on_outlined,
                isSelected: !hasSchedule,
                onPressed: onPostNow,
              ),
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: _ScheduleModeButton(
                label: 'ตั้งเวลา',
                testKey: const ValueKey('uploader-schedule-later'),
                icon: Icons.schedule_outlined,
                isSelected: hasSchedule,
                onPressed: onSchedule,
              ),
            ),
          ],
        ),
        if (hasSchedule) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            key: const ValueKey('uploader-schedule-summary'),
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.tileRadius),
              border: Border.all(
                color: AppTheme.accentCyan.withValues(alpha: 0.34),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    color: AppTheme.accentCyanInk,
                    size: 17,
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Text(
                      'ลงโพสต์ ${_formatDate(selectedDate!)} เวลา ${_formatTime(selectedTime!)} น.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'เลือกวัน',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _dayOptions)
                _SchedulePickerChip(
                  key: ValueKey('uploader-schedule-day-${option.keySuffix}'),
                  label: option.label,
                  icon: option.daysFromToday == 0
                      ? Icons.today_outlined
                      : Icons.event_outlined,
                  isSelected: quickSelectedDay?.keySuffix == option.keySuffix,
                  onPressed: () => onQuickDaySelected(option.daysFromToday),
                ),
              _SchedulePickerChip(
                key: const ValueKey('uploader-schedule-day-custom'),
                label: selectedDate == null || quickSelectedDay != null
                    ? 'เลือกวัน'
                    : _formatDate(selectedDate!),
                icon: Icons.edit_calendar_outlined,
                isSelected: selectedDate != null && quickSelectedDay == null,
                onPressed: onPickCustomDate,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'เลือกเวลา',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _timeOptions)
                _SchedulePickerChip(
                  key: ValueKey('uploader-schedule-time-${option.keySuffix}'),
                  label: option.label,
                  icon: Icons.schedule_outlined,
                  isSelected: selectedTime != null &&
                      _isSameTime(selectedTime!, option.time),
                  onPressed: () => onTimeSelected(option.time),
                ),
              _SchedulePickerChip(
                key: const ValueKey('uploader-schedule-time-custom'),
                label: hasCustomTime ? _formatTime(selectedTime!) : 'กำหนดเอง',
                icon: Icons.edit_calendar_outlined,
                isSelected: hasCustomTime,
                onPressed: onPickCustomTime,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppTheme.spaceSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.public,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ตั้งเวลาได้ล่วงหน้าสูงสุด 30 วันในแพ็กเกจ Starter ขึ้นไป',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SchedulePickerChip extends StatelessWidget {
  const _SchedulePickerChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.18)
              : AppTheme.glassDeep,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color:
                    isSelected ? AppTheme.accentCyan : AppTheme.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleModeButton extends StatelessWidget {
  const _ScheduleModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    this.testKey,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;
  final Key? testKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: testKey,
      height: 34,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor:
              isSelected ? AppTheme.accent.withValues(alpha: 0.16) : null,
          side: BorderSide(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PostDeeGradientButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
    );
  }
}
