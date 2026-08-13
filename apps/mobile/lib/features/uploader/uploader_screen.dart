import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/monitoring/postdee_analytics.dart';
import '../../core/theme/app_theme.dart';
import '../ai_editing/review_video_timeline.dart';
import '../platforms/connections_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/growth_tool_settings_store.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_status_sheet.dart';
import '../shared/post_schedule_policy.dart';
import '../shared/publishing_availability.dart';
import 'clip_frame_extractor.dart';
import 'cover_editor_screen.dart';
import 'cover_image_processor.dart';
import 'platform_publish_settings.dart';
import 'publish_draft.dart';
import 'publish_draft_store.dart';
import 'publish_draft_store_factory.dart';
import 'publish_flow_screen.dart';
import 'publish_review_screen.dart';
import 'video_picker_service.dart';
import 'watermark_video_processor.dart';

export '../shared/post_schedule_policy.dart';

typedef UploaderTemplateLoader = Future<List<TextTemplateResult>> Function();
typedef UploaderSubscriptionLoader = Future<SubscriptionStatusResult>
    Function();
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
typedef UploaderPublishingReadinessChecker = Future<void> Function();
typedef UploaderScheduledPostCreated = void Function(QueuedPostResult post);
typedef UploaderConnectionsLoader = Future<List<SocialConnectionResult>>
    Function();

class _PublishOwnerChangedException implements Exception {
  const _PublishOwnerChangedException();
}

class UploaderScreen extends StatefulWidget {
  const UploaderScreen({
    super.key,
    this.loadTemplates,
    this.loadSubscription,
    this.generateCaption,
    this.generateRealClipCaption,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.createPost,
    this.checkPublishingReadiness,
    this.loadSocialConnections,
    this.onScheduledPostCreated,
    this.onPublishFinished,
    this.onViewAnalytics,
    this.analytics,
    this.watermarkVideo,
    this.openCoverEditor,
    this.coverImageProcessor,
    this.draftStore,
    this.now = DateTime.now,
    this.extractFrames,
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
  final UploaderCaptionGenerator? generateCaption;
  final UploaderRealClipCaptionGenerator? generateRealClipCaption;
  final UploaderVideoPicker? pickVideo;
  final UploaderUploadCreator? createUpload;
  final UploaderVideoUploader? uploadVideoFile;
  final UploaderPostCreator? createPost;
  final UploaderPublishingReadinessChecker? checkPublishingReadiness;
  final UploaderConnectionsLoader? loadSocialConnections;
  final UploaderScheduledPostCreated? onScheduledPostCreated;
  final VoidCallback? onPublishFinished;
  final VoidCallback? onViewAnalytics;
  final PostDeeAnalytics? analytics;
  final UploaderWatermarkVideoProcessor? watermarkVideo;
  final UploaderCoverEditorLauncher? openCoverEditor;
  final CoverImageProcessor? coverImageProcessor;
  final PublishDraftStore? draftStore;

  // Wall clock used to reject schedules in the past. Injectable so tests can
  // pin "now" instead of depending on the real time of day.
  final DateTime Function() now;

  // Extracts still frames from the clip for Pro AI captioning (Gemini "sees"
  // them). Injectable so tests don't touch the native FFmpeg plugin.
  final UploaderClipFrameExtractor? extractFrames;
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

class _UploaderScreenState extends State<UploaderScreen> {
  final _apiClient = PostDeeApiClient();
  PostDeeAnalytics get _analytics =>
      widget.analytics ?? PostDeeAnalytics.instance;
  final _captionController = TextEditingController();
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
  final Set<SocialPlatform> _draftUnavailablePlatforms = {};
  final Set<SocialPlatform> _connectedPlatforms = {};
  final Map<SocialPlatform, SocialConnectionResult> _connectionDetails = {};
  PlatformPublishSettings _platformSettings = const PlatformPublishSettings();
  final List<TextTemplateResult> _templates = [];
  bool _isSubmitting = false;
  bool _isPreparingReview = false;
  bool _isPreparingSubmission = false;
  bool _isLoadingTemplates = false;
  bool _isGeneratingCaption = false;
  bool _isLoadingConnections = true;
  bool _isLoadingDrafts = true;
  bool _draftStoreAvailable = false;
  bool _isSavingDraft = false;
  final Set<String> _blockedSubmissionDraftIds = {};
  String? _connectionsErrorMessage;
  String? _successMessage;
  String? _errorMessage;
  String? _templateErrorMessage;
  String? _aiCaptionErrorMessage;
  String? _selectedVideoName;
  CoverEditorResult? _coverResult;
  List<PublishDraft> _drafts = const [];
  String? _activeDraftId;
  DateTime? _activeDraftCreatedAt;
  bool? _activeDraftWatermarkEnabled;
  String? _resolvedDraftOwnerUserId;
  Future<PublishDraftStore?>? _draftStoreFuture;
  BuildContext? _draftSheetContext;
  int _draftLoadGeneration = 0;
  PostDeeStatusSheetData? _pendingStatusSheet;
  bool _pickVideoAfterStatus = false;
  String? _pendingInlineError;

  bool get _requiresNewSubmissionAttempt {
    final activeDraftId = _activeDraftId;
    return activeDraftId != null &&
        _blockedSubmissionDraftIds.contains(activeDraftId);
  }

  @override
  void initState() {
    super.initState();
    _prefillInitialVideo();
    if (widget.draftStore == null) {
      PostDeeAuthSessionStore.instance.addListener(_handleDraftOwnerChanged);
    }
    unawaited(_loadConnections());
    unawaited(_loadDrafts());
  }

  void _handleDraftOwnerChanged() {
    final nextOwnerUserId =
        PostDeeAuthSessionStore.instance.session.stableUserId;
    if (nextOwnerUserId != null &&
        nextOwnerUserId == _resolvedDraftOwnerUserId &&
        _draftStoreFuture != null) {
      return;
    }
    _draftLoadGeneration += 1;
    final draftSheetContext = _draftSheetContext;
    _draftSheetContext = null;
    if (draftSheetContext != null && draftSheetContext.mounted) {
      Navigator.of(draftSheetContext).pop();
    }
    _resolvedDraftOwnerUserId = null;
    _draftStoreFuture = null;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    final previousCover = _coverResult;
    setState(() {
      _drafts = const [];
      _draftStoreAvailable = false;
      _isLoadingDrafts = true;
      _activeDraftId = null;
      _activeDraftCreatedAt = null;
      _activeDraftWatermarkEnabled = null;
      _selectedVideoName = null;
      _coverResult = null;
      _captionController.clear();
      _aiGuidanceController.clear();
      _fileNameController.clear();
      _localFilePathController.clear();
      _sizeBytesController.clear();
      _widthController.clear();
      _heightController.clear();
      _scheduledAtController.clear();
      _selectedScheduleDate = null;
      _selectedScheduleTime = null;
      _selectedPlatforms.clear();
      _draftUnavailablePlatforms.clear();
      _connectedPlatforms.clear();
      _connectionDetails.clear();
      _platformSettings = const PlatformPublishSettings();
      _blockedSubmissionDraftIds.clear();
    });
    if (previousCover != null) {
      unawaited(previousCover.cleanupTemporaryFiles());
    }
    unawaited(_loadDrafts());
    unawaited(_loadConnections());
  }

  Future<void> _loadDrafts() async {
    final generation = ++_draftLoadGeneration;
    try {
      final store = await _resolveDraftStore();
      if (generation != _draftLoadGeneration) return;
      if (store == null) {
        if (mounted) {
          setState(() {
            _isLoadingDrafts = false;
            _draftStoreAvailable = false;
          });
        }
        return;
      }
      final drafts = await store.listDrafts();
      if (!mounted || generation != _draftLoadGeneration) return;
      setState(() {
        _drafts = drafts;
        _isLoadingDrafts = false;
        _draftStoreAvailable = true;
      });
    } catch (_) {
      if (!mounted || generation != _draftLoadGeneration) return;
      setState(() {
        _isLoadingDrafts = false;
        _draftStoreAvailable = false;
        _errorMessage = 'โหลดฉบับร่างในเครื่องไม่สำเร็จ';
      });
    }
  }

  Future<PublishDraftStore?> _resolveDraftStore() async {
    final injectedStore = widget.draftStore;
    if (injectedStore != null) return injectedStore;

    final ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    if (ownerUserId == null) {
      _resolvedDraftOwnerUserId = null;
      _draftStoreFuture = null;
      return null;
    }
    if (_resolvedDraftOwnerUserId != ownerUserId || _draftStoreFuture == null) {
      _resolvedDraftOwnerUserId = ownerUserId;
      _draftStoreFuture = createPublishDraftStoreForSession();
    }
    try {
      final store = await _draftStoreFuture;
      if (PostDeeAuthSessionStore.instance.session.stableUserId !=
          ownerUserId) {
        return null;
      }
      return store;
    } catch (_) {
      if (_resolvedDraftOwnerUserId == ownerUserId) {
        _draftStoreFuture = null;
      }
      rethrow;
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
          .toSet();
      final connectionDetails = <SocialPlatform, SocialConnectionResult>{};
      for (final result in results.where((result) => result.connected)) {
        final platform = _platformFromApiValue(result.platform);
        if (platform != null) connectionDetails[platform] = result;
      }

      setState(() {
        final desiredPlatforms = {
          ..._selectedPlatforms,
          ..._draftUnavailablePlatforms,
        };
        _connectedPlatforms
          ..clear()
          ..addAll(connected);
        _connectionDetails
          ..clear()
          ..addAll(connectionDetails);
        _selectedPlatforms
          ..clear()
          ..addAll(desiredPlatforms.where(_connectedPlatforms.contains));
        _draftUnavailablePlatforms
          ..clear()
          ..addAll(
            desiredPlatforms.where(
              (platform) => !_connectedPlatforms.contains(platform),
            ),
          );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draftUnavailablePlatforms.addAll(_selectedPlatforms);
        _connectedPlatforms.clear();
        _connectionDetails.clear();
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

  String? _socialConnectionIdentity(SocialConnectionResult connection) {
    final displayName = connection.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final externalAccountId = connection.externalAccountId?.trim() ?? '';
    return externalAccountId.isEmpty ? null : externalAccountId;
  }

  SocialPlatform? get _selectedPlatformWithoutIdentity => _selectedPlatforms
      .where(
        (platform) =>
            _connectionDetails[platform] == null ||
            _socialConnectionIdentity(_connectionDetails[platform]!) == null,
      )
      .firstOrNull;

  void _showMissingConnectionIdentityError() {
    setState(() {
      _errorMessage =
          'ยังยืนยันบัญชีหรือเพจปลายทางไม่ได้ กรุณารีเฟรชช่องทางหรือเชื่อมต่อใหม่';
      _successMessage = null;
    });
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
    if (widget.draftStore == null) {
      PostDeeAuthSessionStore.instance.removeListener(_handleDraftOwnerChanged);
    }
    final cover = _coverResult;
    _coverResult = null;
    if (cover != null) {
      unawaited(cover.cleanupTemporaryFiles());
    }
    _captionController.dispose();
    _fileNameController.dispose();
    _localFilePathController.dispose();
    _sizeBytesController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _scheduledAtController.dispose();
    _aiGuidanceController.dispose();
    super.dispose();
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
    if (previousCover != null && !identical(previousCover, result)) {
      unawaited(previousCover.cleanupTemporaryFiles());
    }
  }

  Future<CoverEditorResult> _readCoverForUpload({
    required File videoFile,
    required String fileName,
  }) async {
    final cover = _coverResult;
    if (cover == null) {
      throw const CoverImageException('ยังไม่ได้เลือกหน้าปก');
    }
    if (cover.imageFile.existsSync() && cover.imageFile.lengthSync() > 0) {
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
      unawaited(cover.cleanupTemporaryFiles());
    }
    return regenerated;
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
  }) {
    if (height <= width) {
      return false;
    }

    final expectedHeight = width * 16 / 9;
    final tolerance = expectedHeight * 0.02;

    return (height - expectedHeight).abs() <= tolerance;
  }

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

  Future<String?> _uploadSelectedClipForAiCaption() async {
    final localFilePath = _localFilePathController.text.trim();
    final localVideoFile = localFilePath.isEmpty ? null : File(localFilePath);
    final fileName = _fileNameController.text.trim().isNotEmpty
        ? _fileNameController.text.trim()
        : localVideoFile == null
            ? (_selectedVideoName ?? '').trim()
            : _readFileNameFromPath(localFilePath);
    var sizeBytes = _readPositiveInt(_sizeBytesController);
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

    sizeBytes ??= localVideoFile.lengthSync();

    if (fileName.isEmpty || sizeBytes < 1) {
      setState(() {
        _aiCaptionErrorMessage = 'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ';
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

    final createUpload = widget.createUpload ?? _apiClient.createUpload;
    final uploadVideoFile =
        widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
    final upload = await createAndUploadFileWithRetry(
      request: CreateUploadRequest(
        fileName: fileName,
        contentType: 'video/mp4',
        sizeBytes: sizeBytes,
        width: width,
        height: height,
      ),
      file: localVideoFile,
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

    return upload.videoS3Key;
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
    final selectedVideoName = (_selectedVideoName ?? '').trim();

    if (selectedVideoName.isEmpty) {
      setState(() {
        _aiCaptionErrorMessage =
            'เลือกคลิปก่อน แล้ว AI จะคิดแคปชั่นจากเสียงในคลิปนั้น';
      });
      return;
    }

    setState(() {
      _isGeneratingCaption = true;
      _aiCaptionErrorMessage = null;
    });

    try {
      final subscription = await _loadSubscription();

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

      final videoS3Key = await _uploadSelectedClipForAiCaption();

      if (videoS3Key == null) {
        return;
      }

      // Pro lets Gemini also "see" the clip: extract a few frames and upload
      // them so the backend can pass them to the model. Starter is audio-only.
      final selectedFrameKeys = subscription.isPro
          ? await _uploadAiCaptionFrames()
          : const <String>[];

      final guidance = _aiGuidanceController.text.trim();
      final generator =
          widget.generateRealClipCaption ?? _apiClient.generateCaptionFromClip;
      final caption = await generator(
        GenerateRealClipCaptionRequest(
          videoS3Key: videoS3Key,
          guidance: guidance.isEmpty ? null : guidance,
          selectedFrameKeys: selectedFrameKeys,
          deleteAfterUse: true,
        ),
      );
      final nextCaption = _formatRealClipCaption(caption);

      if (!mounted) {
        return;
      }

      setState(() {
        _captionController.value = TextEditingValue(
          text: nextCaption,
          selection: TextSelection.collapsed(offset: nextCaption.length),
        );
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = error.message;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _aiCaptionErrorMessage = 'เชื่อมต่อ PostDee API ไม่ได้';
      });
    } catch (_) {
      if (!mounted) {
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

  Future<bool> _watermarkEnabledForCurrentSelection() async {
    final requested =
        _activeDraftWatermarkEnabled ?? await _shouldApplyAutoWatermark();
    return shouldApplyPostDeeWatermark(
      requested: requested,
      selectedPlatforms: {
        ..._selectedPlatforms,
        ..._draftUnavailablePlatforms,
      },
    );
  }

  String _platformSettingsError(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.tiktok:
        return 'ยังโพสต์ตรงไป TikTok ไม่ได้ เลือกส่งเป็นร่างก่อน';
      case SocialPlatform.youtubeShorts:
        return _platformSettings.youtubeValidationMessage ??
            'ตั้งค่า YouTube ให้ครบก่อนโพสต์';
      case SocialPlatform.facebookReels:
        return 'เลือกว่าจะเผยแพร่หรือเก็บเป็นร่างบนเพจก่อน';
      case SocialPlatform.instagramReels:
        return 'ตั้งค่า Instagram ให้ครบก่อนโพสต์';
      case SocialPlatform.shopeeVideo:
      case SocialPlatform.lazadaVideo:
        return 'ช่องทางนี้ยังไม่พร้อมให้โพสต์';
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
      if (previousCover != null) {
        unawaited(previousCover.cleanupTemporaryFiles());
      }
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

  Future<void> _saveDraft() async {
    await _persistCurrentDraft(showSavedMessage: true);
  }

  Future<void> _startNewSubmissionAttempt() async {
    if (!_requiresNewSubmissionAttempt ||
        _isSavingDraft ||
        _isSubmitting ||
        _isGeneratingCaption) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เริ่มรายการโพสต์ใหม่?'),
        content: const Text(
          'กรุณาตรวจหน้ารายการโพสต์และแพลตฟอร์มปลายทางก่อน '
          'เพราะรายการเดิมอาจถูกส่งไปแล้ว การเริ่มรายการใหม่อาจโพสต์ซ้ำได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            key: const ValueKey('publish-new-attempt-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ตรวจแล้ว เริ่มรายการใหม่'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousDraftId = _activeDraftId;
    final previousCreatedAt = _activeDraftCreatedAt;
    setState(() {
      _activeDraftId = null;
      _activeDraftCreatedAt = null;
    });
    final saved = await _persistCurrentDraft(showSavedMessage: false);
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _activeDraftId = previousDraftId;
        _activeDraftCreatedAt = previousCreatedAt;
      });
      return;
    }
    setState(() {
      _successMessage =
          'สร้างร่างสำหรับรายการโพสต์ใหม่แล้ว กรุณาตรวจทานก่อนโพสต์';
    });
  }

  Future<PublishDraft?> _persistCurrentDraft({
    required bool showSavedMessage,
  }) async {
    if (_isSavingDraft || _isSubmitting || _isGeneratingCaption) return null;
    _isSavingDraft = true;
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
    }
    try {
      return await _persistCurrentDraftWhileLocked(
        showSavedMessage: showSavedMessage,
      );
    } on FileSystemException {
      if (!mounted) return null;
      setState(() {
        _errorMessage = 'บันทึกร่างไม่สำเร็จ ตรวจสอบพื้นที่ว่างในเครื่อง';
      });
      return null;
    } on PublishDraftValidationException catch (error) {
      if (!mounted) return null;
      setState(() => _errorMessage = error.message);
      return null;
    } catch (_) {
      if (!mounted) return null;
      setState(() => _errorMessage = 'บันทึกร่างในเครื่องไม่สำเร็จ');
      return null;
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  Future<PublishDraft?> _persistCurrentDraftWhileLocked({
    required bool showSavedMessage,
  }) async {
    final ownerUserIdAtStart = widget.draftStore == null
        ? PostDeeAuthSessionStore.instance.session.stableUserId
        : null;
    final draftGenerationAtStart = _draftLoadGeneration;
    final store = await _resolveDraftStore();
    if (!_draftOperationStillOwned(
      ownerUserId: ownerUserIdAtStart,
      generation: draftGenerationAtStart,
    )) {
      return null;
    }
    if (store == null) {
      setState(() {
        _errorMessage = 'ยังเปิดพื้นที่เก็บฉบับร่างในเครื่องไม่ได้';
        _successMessage = null;
      });
      return null;
    }

    final localPath = _localFilePathController.text.trim();
    final videoFile = localPath.isEmpty ? null : File(localPath);
    if (videoFile == null ||
        !videoFile.existsSync() ||
        videoFile.lengthSync() <= 0) {
      setState(() {
        _errorMessage = 'เลือกวิดีโอจากเครื่องก่อนบันทึกร่าง';
        _successMessage = null;
      });
      return null;
    }

    final rawSchedule = _scheduledAtController.text.trim();
    final scheduledAt = _readScheduledAt();
    if (rawSchedule.isNotEmpty && scheduledAt == null) {
      setState(() {
        _errorMessage = 'เวลาโพสต์ไม่ถูกต้อง กรุณาเลือกใหม่';
        _successMessage = null;
      });
      return null;
    }

    final now = widget.now().toUtc();
    final draftId = _activeDraftId ?? 'draft-${now.microsecondsSinceEpoch}';
    final createdAt = _activeDraftCreatedAt ?? now;
    final cover = _coverResult;
    final coverLease = cover?.retainTemporaryFiles();

    try {
      final watermarkEnabled = await _watermarkEnabledForCurrentSelection();
      final desiredPlatforms = {
        ..._selectedPlatforms,
        ..._draftUnavailablePlatforms,
      };
      final saved = await store.saveDraft(
        PublishDraftSaveRequest(
          id: draftId,
          createdAt: createdAt,
          updatedAt: now.isBefore(createdAt) ? createdAt : now,
          videoFile: videoFile,
          videoName: (_selectedVideoName ?? '').trim().isNotEmpty
              ? _selectedVideoName!.trim()
              : _readFileNameFromPath(localPath),
          videoSizeBytes:
              _readPositiveInt(_sizeBytesController) ?? videoFile.lengthSync(),
          videoWidth: _readPositiveInt(_widthController),
          videoHeight: _readPositiveInt(_heightController),
          caption: _captionController.text,
          aiGuidance: _aiGuidanceController.text,
          watermarkEnabled: watermarkEnabled,
          platformApiValues:
              desiredPlatforms.map((platform) => platform.apiValue).toSet(),
          platformSettings: _platformSettings,
          scheduledAt: scheduledAt,
          coverImageFile: cover?.imageFile,
          coverDesign: cover?.design,
          coverDurationMs: cover?.durationMs,
          coverSourceKind: cover?.sourceKind ?? CoverSourceKind.videoFrame,
          coverSourceImageFile: cover?.sourceImageFile,
          coverSourceImageName: cover?.sourceImageName,
        ),
      );
      if (!_draftOperationStillOwned(
        ownerUserId: ownerUserIdAtStart,
        generation: draftGenerationAtStart,
      )) {
        return null;
      }
      final drafts = await store.listDrafts();
      if (!_draftOperationStillOwned(
        ownerUserId: ownerUserIdAtStart,
        generation: draftGenerationAtStart,
      )) {
        return null;
      }
      if (!mounted) return null;
      final persistedCover = saved.cover?.toEditorResult();
      setState(() {
        _activeDraftId = saved.id;
        _activeDraftCreatedAt = saved.createdAt;
        _activeDraftWatermarkEnabled = saved.watermarkEnabled;
        _platformSettings = saved.platformSettings;
        _selectedVideoName = saved.videoName;
        _localFilePathController.text = saved.videoPath;
        _fileNameController.text = saved.videoName;
        _sizeBytesController.text = saved.videoSizeBytes.toString();
        _widthController.text = saved.videoWidth?.toString() ?? '';
        _heightController.text = saved.videoHeight?.toString() ?? '';
        _coverResult = persistedCover;
        _drafts = drafts;
        _successMessage = showSavedMessage
            ? 'บันทึกร่างในเครื่องแล้ว · ยังไม่อัปโหลด ไม่โพสต์ และไม่ใช้โควตา'
            : null;
      });
      if (cover != null && !identical(cover, persistedCover)) {
        unawaited(cover.cleanupTemporaryFiles());
      }
      return saved;
    } finally {
      await coverLease?.release();
    }
  }

  bool _draftBelongsToCurrentSession(PublishDraft draft) {
    if (widget.draftStore != null) return true;
    final ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    return ownerUserId != null &&
        ownerUserId == draft.ownerUserId &&
        ownerUserId == _resolvedDraftOwnerUserId;
  }

  bool _draftOperationStillOwned({
    required String? ownerUserId,
    required int generation,
  }) {
    if (widget.draftStore != null) return true;
    return ownerUserId != null &&
        generation == _draftLoadGeneration &&
        PostDeeAuthSessionStore.instance.session.stableUserId == ownerUserId &&
        _resolvedDraftOwnerUserId == ownerUserId;
  }

  void _showDraftOwnerChangedError() {
    if (!mounted) return;
    setState(() {
      _errorMessage = 'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดรายการฉบับร่างใหม่';
      _successMessage = null;
    });
  }

  CoverEditorResult? _clearActiveDraftFormState() {
    final previousCover = _coverResult;
    final activeDraftId = _activeDraftId;
    if (activeDraftId != null) {
      _blockedSubmissionDraftIds.remove(activeDraftId);
    }
    _activeDraftId = null;
    _activeDraftCreatedAt = null;
    _activeDraftWatermarkEnabled = null;
    _selectedVideoName = null;
    _coverResult = null;
    _captionController.clear();
    _aiGuidanceController.clear();
    _fileNameController.clear();
    _localFilePathController.clear();
    _sizeBytesController.clear();
    _widthController.clear();
    _heightController.clear();
    _scheduledAtController.clear();
    _selectedScheduleDate = null;
    _selectedScheduleTime = null;
    _selectedPlatforms.clear();
    _draftUnavailablePlatforms.clear();
    _platformSettings = const PlatformPublishSettings();
    return previousCover;
  }

  Future<void> _restoreDraft(PublishDraft draft) async {
    if (!_draftBelongsToCurrentSession(draft)) {
      _showDraftOwnerChangedError();
      return;
    }
    final video = File(draft.videoPath);
    if (!video.existsSync() || video.lengthSync() <= 0) {
      setState(() {
        _errorMessage = 'ไม่พบวิดีโอของฉบับร่างนี้ในเครื่อง';
        _successMessage = null;
      });
      return;
    }

    final previousCover = _coverResult;
    final desiredPlatforms = draft.platformApiValues
        .map(_platformFromApiValue)
        .whereType<SocialPlatform>()
        .toSet();
    final localSchedule = draft.scheduledAt?.toLocal();
    final scheduleExpired = draft.scheduledAt != null &&
        !draft.scheduledAt!.isAfter(widget.now().toUtc());

    setState(() {
      _activeDraftId = draft.id;
      _activeDraftCreatedAt = draft.createdAt;
      _activeDraftWatermarkEnabled = draft.watermarkEnabled;
      _selectedVideoName = draft.videoName;
      _localFilePathController.text = draft.videoPath;
      _fileNameController.text = draft.videoName;
      _sizeBytesController.text = draft.videoSizeBytes.toString();
      _widthController.text = draft.videoWidth?.toString() ?? '';
      _heightController.text = draft.videoHeight?.toString() ?? '';
      _captionController.text = draft.caption;
      _aiGuidanceController.text = draft.aiGuidance;
      _selectedPlatforms
        ..clear()
        ..addAll(desiredPlatforms.where(_connectedPlatforms.contains));
      _draftUnavailablePlatforms
        ..clear()
        ..addAll(
          desiredPlatforms.where(
            (platform) => !_connectedPlatforms.contains(platform),
          ),
        );
      _platformSettings = draft.platformSettings.copyWith(
        youtubeCommunityGuidelinesCertified: false,
      );
      _coverResult = draft.cover?.toEditorResult();
      _scheduledAtController.text =
          draft.scheduledAt?.toUtc().toIso8601String() ?? '';
      _selectedScheduleDate = localSchedule == null
          ? null
          : DateTime(
              localSchedule.year, localSchedule.month, localSchedule.day);
      _selectedScheduleTime = localSchedule == null
          ? null
          : TimeOfDay(hour: localSchedule.hour, minute: localSchedule.minute);
      _successMessage = 'เปิดฉบับร่างแล้ว';
      _errorMessage = scheduleExpired
          ? 'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลยก่อนยืนยัน'
          : _draftUnavailablePlatforms.isEmpty
              ? null
              : 'บางช่องทางในร่างยังไม่ได้เชื่อมต่อ กรุณาเชื่อมใหม่ก่อนโพสต์';
    });
    if (previousCover != null && !identical(previousCover, _coverResult)) {
      unawaited(previousCover.cleanupTemporaryFiles());
    }
  }

  Future<void> _deleteDraft(PublishDraft draft) async {
    final ownerUserIdAtStart = widget.draftStore == null
        ? PostDeeAuthSessionStore.instance.session.stableUserId
        : null;
    final draftGenerationAtStart = _draftLoadGeneration;
    if (!_draftBelongsToCurrentSession(draft)) {
      _showDraftOwnerChangedError();
      return;
    }
    final store = await _resolveDraftStore();
    if (!_draftOperationStillOwned(
      ownerUserId: ownerUserIdAtStart,
      generation: draftGenerationAtStart,
    )) {
      _showDraftOwnerChangedError();
      return;
    }
    if (store == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบฉบับร่างนี้?'),
        content: const Text(
          'วิดีโอและหน้าปกที่เก็บไว้กับฉบับร่างนี้จะถูกลบจากพื้นที่ของแอป',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            key: const ValueKey('publish-draft-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบร่าง'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_draftOperationStillOwned(
      ownerUserId: ownerUserIdAtStart,
      generation: draftGenerationAtStart,
    )) {
      _showDraftOwnerChangedError();
      return;
    }
    final deleted = await _deleteDraftAndConfirmAbsent(store, draft.id);
    if (!deleted) {
      if (!mounted) return;
      setState(() => _errorMessage = 'ลบฉบับร่างไม่สำเร็จ');
      return;
    }
    if (!_draftOperationStillOwned(
      ownerUserId: ownerUserIdAtStart,
      generation: draftGenerationAtStart,
    )) {
      return;
    }
    if (!mounted) return;
    CoverEditorResult? deletedDraftCover;
    setState(() {
      _drafts = _drafts.where((candidate) => candidate.id != draft.id).toList();
      if (_activeDraftId == draft.id) {
        deletedDraftCover = _clearActiveDraftFormState();
      }
      _errorMessage = null;
      _successMessage = 'ลบฉบับร่างแล้ว';
    });
    if (deletedDraftCover != null) {
      unawaited(deletedDraftCover!.cleanupTemporaryFiles());
    }

    try {
      final drafts = await store.listDrafts();
      if (mounted &&
          _draftOperationStillOwned(
            ownerUserId: ownerUserIdAtStart,
            generation: draftGenerationAtStart,
          )) {
        setState(() => _drafts = drafts);
      }
    } catch (_) {
      // The requested draft is already gone and the local list was updated.
      // A later screen refresh can retry loading the remaining drafts.
    }
  }

  Future<bool> _deleteDraftAndConfirmAbsent(
    PublishDraftStore store,
    String draftId,
  ) async {
    try {
      await store.deleteDraft(draftId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openDrafts() async {
    if (_isLoadingDrafts) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          _draftSheetContext = sheetContext;
          return StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ฉบับร่างในเครื่อง',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ยังไม่อัปโหลด ไม่ส่งไปแพลตฟอร์ม และไม่ใช้โควตา',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'แอปคัดลอกวิดีโอและหน้าปกไว้ในพื้นที่แอปของเครื่องนี้ '
                      'ร่างไม่ซิงก์ข้ามอุปกรณ์ และอาจรวมอยู่ในข้อมูลสำรองของระบบ',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    const SizedBox(height: 16),
                    if (_drafts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: Text('ยังไม่มีฉบับร่างในเครื่อง')),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _drafts.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final draft = _drafts[index];
                            return ListTile(
                              key: ValueKey('publish-draft-${draft.id}'),
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.video_file_outlined),
                              title: Text(
                                draft.caption.trim().isEmpty
                                    ? draft.videoName
                                    : draft.caption.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${draft.platformApiValues.length} ช่องทาง · เก็บในเครื่อง',
                              ),
                              trailing: IconButton(
                                key: ValueKey(
                                  'publish-draft-delete-${draft.id}',
                                ),
                                tooltip: 'ลบฉบับร่าง',
                                onPressed: () async {
                                  await _deleteDraft(draft);
                                  if (mounted) setSheetState(() {});
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await _restoreDraft(draft);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _draftSheetContext = null;
    }
  }

  /// Design screen #7: show the review summary before actually posting. When
  /// no clip is selected yet, skip straight to [_createPost] so its validation
  /// message shows instead of reviewing an empty post.
  Future<void> _reviewThenPost() async {
    if (_isPreparingReview ||
        _isSubmitting ||
        _isSavingDraft ||
        _isGeneratingCaption ||
        _requiresNewSubmissionAttempt) {
      return;
    }
    _isPreparingReview = true;
    if (mounted) setState(() {});
    try {
      await _reviewThenPostWhileLocked();
    } finally {
      _isPreparingReview = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _reviewThenPostWhileLocked() async {
    if (_isLoadingConnections) {
      setState(() {
        _errorMessage = 'กำลังตรวจสอบช่องทางที่เชื่อมต่อ กรุณารอสักครู่';
        _successMessage = null;
      });
      return;
    }

    if (_draftUnavailablePlatforms.isNotEmpty) {
      setState(() {
        _errorMessage = 'เชื่อมช่องทางที่เก็บไว้ในร่างให้ครบก่อนโพสต์: '
            '${_draftUnavailablePlatforms.map((platform) => platform.label).join(', ')}';
        _successMessage = null;
      });
      return;
    }

    if (_selectedPlatforms.isEmpty) {
      final hasConnectionError = _connectionsErrorMessage != null;
      final hasConnectedPlatforms = _connectedPlatforms.isNotEmpty;
      final shouldContinue = await showPostDeeStatusSheet(
        context,
        data: PostDeeStatusSheetData(
          icon: hasConnectionError
              ? Icons.cloud_off_rounded
              : hasConnectedPlatforms
                  ? Icons.touch_app_outlined
                  : Icons.link_off_rounded,
          iconColor: const Color(0xFFF59E0B),
          iconTint: const Color(0x24F59E0B),
          title: hasConnectionError
              ? 'ตรวจสอบช่องทางไม่ได้'
              : hasConnectedPlatforms
                  ? 'ยังไม่ได้เลือกช่องทาง'
                  : 'ยังไม่ได้เชื่อมช่องทาง',
          body: _connectionsErrorMessage ??
              (hasConnectedPlatforms
                  ? 'เลือกอย่างน้อย 1 ช่องทางก่อนเริ่มโพสต์'
                  : 'ต้องเชื่อมอย่างน้อย 1 ช่องทางก่อนจึงจะเริ่มโพสต์ได้'),
          primaryLabel: hasConnectionError
              ? 'ลองใหม่'
              : hasConnectedPlatforms
                  ? 'เลือกทั้งหมด'
                  : 'ไปเชื่อมช่องทาง',
          secondaryLabel: 'ไว้ก่อน',
        ),
      );

      if (shouldContinue == true && mounted) {
        if (hasConnectionError) {
          await _loadConnections();
        } else if (hasConnectedPlatforms) {
          _selectAllConnectedPlatforms();
        } else {
          await _openConnections();
        }
      }
      return;
    }

    if (_selectedPlatformWithoutIdentity != null) {
      _showMissingConnectionIdentityError();
      return;
    }

    final selectedVideoName = (_selectedVideoName ?? '').trim();

    if (selectedVideoName.isEmpty) {
      await _createPost();
      return;
    }

    // The backend requires a caption, so catch it here instead of letting the
    // user confirm the review only to have the post bounce back.
    if (_captionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'เพิ่มแคปชั่นก่อนโพสต์';
        _successMessage = null;
      });
      return;
    }

    final scheduledAt = _readScheduledAt();
    if (_scheduledAtController.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() {
        _errorMessage = 'เวลาตั้งโพสต์ไม่ถูกต้อง กรุณาเลือกใหม่';
        _successMessage = null;
      });
      return;
    }
    final now = widget.now();
    if (scheduledAt != null && !scheduledAt.isAfter(now)) {
      setState(() {
        _errorMessage = 'เวลาเดิมผ่านไปแล้ว เลือกเวลาใหม่หรือเลือกโพสต์เลย';
        _successMessage = null;
      });
      return;
    }
    if (scheduledAt != null &&
        !isPostScheduleWithinLimit(scheduledAt: scheduledAt, now: now)) {
      setState(() {
        _errorMessage = 'ตั้งเวลาโพสต์ล่วงหน้าได้สูงสุด 30 วัน';
        _successMessage = null;
      });
      return;
    }

    final watermarkEnabled = await _watermarkEnabledForCurrentSelection();
    if (!mounted) return;

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => PublishReviewScreen(
          videoName: selectedVideoName,
          caption: _captionController.text,
          platforms:
              SocialPlatform.values.where(_selectedPlatforms.contains).toList(),
          scheduledAt: _readScheduledAt(),
          watermarkEnabled: watermarkEnabled,
          platformSettings: _platformSettings,
          connectionDisplayNames: {
            for (final entry in _connectionDetails.entries)
              if (_socialConnectionIdentity(entry.value) case final name?)
                entry.key: name,
          },
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
          publish: _createPost,
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
      case PublishFlowAction.analytics:
        widget.onViewAnalytics?.call();
      case null:
        break;
    }
  }

  Future<QueuedPostResult?> _createPost() async {
    if (_isPreparingSubmission ||
        _isSubmitting ||
        _isGeneratingCaption ||
        _requiresNewSubmissionAttempt) {
      return null;
    }
    _isPreparingSubmission = true;
    if (mounted) setState(() {});
    try {
      return await _createPostWhileLocked();
    } finally {
      _isPreparingSubmission = false;
      if (mounted) setState(() {});
    }
  }

  Future<QueuedPostResult?> _createPostWhileLocked() async {
    _pendingStatusSheet = null;
    _pickVideoAfterStatus = false;
    _pendingInlineError = null;
    final caption = _captionController.text.trim();
    var localFilePath = _localFilePathController.text.trim();
    var localVideoFile = localFilePath.isEmpty ? null : File(localFilePath);
    var fileName = _fileNameController.text.trim().isNotEmpty
        ? _fileNameController.text.trim()
        : localVideoFile == null
            ? ''
            : _readFileNameFromPath(localFilePath);
    var sizeBytes = _readPositiveInt(_sizeBytesController);
    var width = _readPositiveInt(_widthController);
    var height = _readPositiveInt(_heightController);
    final scheduledAt = _readScheduledAt();

    final invalidPlatform = _selectedPlatforms
        .where((platform) => !_platformSettings.canSubmit(platform))
        .firstOrNull;
    if (invalidPlatform != null) {
      setState(() {
        _errorMessage = _platformSettingsError(invalidPlatform);
        _successMessage = null;
      });
      return null;
    }

    if (_selectedPlatformWithoutIdentity != null) {
      _showMissingConnectionIdentityError();
      return null;
    }

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

    if (caption.isEmpty) {
      setState(() {
        _errorMessage = 'เพิ่มแคปชั่นก่อนโพสต์';
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

    // Persist the complete submission locally before the first remote side
    // effect. If the app is killed after the server commits but before the
    // response arrives, reopening this draft reuses the same request ID and
    // cannot create a second post/quota charge.
    final submittedDraft = await _persistCurrentDraft(showSavedMessage: false);
    if (submittedDraft == null) return null;
    final submittedDraftId = submittedDraft.id;
    final submittedDraftOwnerUserId = widget.draftStore == null
        ? PostDeeAuthSessionStore.instance.session.stableUserId
        : null;
    final submittedDraftGeneration = _draftLoadGeneration;
    final submittedDraftStore = await _resolveDraftStore();
    if (submittedDraftStore == null ||
        _activeDraftId != submittedDraftId ||
        !_draftOperationStillOwned(
          ownerUserId: submittedDraftOwnerUserId,
          generation: submittedDraftGeneration,
        )) {
      _showDraftOwnerChangedError();
      return null;
    }
    bool submissionStillOwned() =>
        _activeDraftId == submittedDraftId &&
        _draftOperationStillOwned(
          ownerUserId: submittedDraftOwnerUserId,
          generation: submittedDraftGeneration,
        );

    void ensureSubmissionStillOwned() {
      if (!submissionStillOwned()) {
        throw const _PublishOwnerChangedException();
      }
    }

    localFilePath = submittedDraft.videoPath;
    localVideoFile = File(localFilePath);
    fileName = submittedDraft.videoName;
    sizeBytes = submittedDraft.videoSizeBytes;
    width = submittedDraft.videoWidth;
    height = submittedDraft.videoHeight;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    var didUploadVideo = false;
    WatermarkedVideoResult? generatedWatermarkedVideo;

    try {
      final checkPublishingReadiness = widget.checkPublishingReadiness ??
          _apiClient.checkPublishingReadiness;
      ensureSubmissionStillOwned();
      await checkPublishingReadiness();
      ensureSubmissionStillOwned();

      final subscription = await _loadSubscription();
      ensureSubmissionStillOwned();

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
      final shouldApplyWatermark = await _watermarkEnabledForCurrentSelection();
      ensureSubmissionStillOwned();
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
        generatedWatermarkedVideo = watermarkedVideo;
        ensureSubmissionStillOwned();

        uploadVideoFileForRequest = watermarkedVideo.file;
        uploadFileName = watermarkedVideo.fileName;
        uploadSizeBytes = watermarkedVideo.sizeBytes;
        didApplyWatermark = true;
      }

      final rawCreateUpload = widget.createUpload ?? _apiClient.createUpload;
      final rawUploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      Future<UploadResult> createUpload(CreateUploadRequest request) async {
        ensureSubmissionStillOwned();
        final result = await rawCreateUpload(request);
        ensureSubmissionStillOwned();
        return result;
      }

      Future<void> uploadVideoFile(UploadResult upload, File file) async {
        ensureSubmissionStillOwned();
        await rawUploadVideoFile(upload, file);
        ensureSubmissionStillOwned();
      }

      final upload = await createAndUploadFileWithRetry(
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
      ensureSubmissionStillOwned();
      didUploadVideo = true;
      final uploadedWatermarkedVideo = generatedWatermarkedVideo;
      if (uploadedWatermarkedVideo != null) {
        try {
          await uploadedWatermarkedVideo.cleanupTemporaryFiles();
          generatedWatermarkedVideo = null;
        } catch (_) {
          // The final cleanup block retries. Upload has already completed, so
          // a local cleanup problem must not create an accidental repost.
        }
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
        ensureSubmissionStillOwned();
        selectedCover = cover;
        if (mounted) {
          setState(() {
            _successMessage = 'กำลังอัปโหลดหน้าปก...';
          });
        }
        final coverLease = cover.retainTemporaryFiles();
        try {
          final coverUpload = await createAndUploadFileWithRetry(
            request: CreateUploadRequest(
              fileName: 'postdee-cover.jpg',
              contentType: 'image/jpeg',
              sizeBytes: cover.imageFile.lengthSync(),
              width: 1080,
              height: 1920,
            ),
            file: cover.imageFile,
            createUpload: createUpload,
            uploadFile: uploadVideoFile,
          );
          coverImageS3Key = coverUpload.videoS3Key;
        } finally {
          await coverLease?.release();
        }
      }
      final createPost = widget.createPost ?? _apiClient.createPost;
      ensureSubmissionStillOwned();
      final post = await createPost(
        CreatePostRequest(
          clientRequestId: submittedDraft.submissionRequestId,
          caption: caption,
          videoS3Key: upload.videoS3Key,
          platforms:
              _selectedPlatforms.map((platform) => platform.apiValue).toList(),
          platformSettings: submittedDraft.platformSettings.toApiJson(
            selectedPlatforms: Set<SocialPlatform>.from(_selectedPlatforms),
          ),
          scheduledAt: scheduledAt,
          coverImageS3Key: coverImageS3Key,
          coverFrameTimeMs: selectedCover?.coverFrameTimeMs,
        ),
      );
      ensureSubmissionStillOwned();
      final postStatus = post.status.toUpperCase();
      const acceptedPostStatuses = {
        'QUEUED',
        'PUBLISHING',
        'PUBLISHED',
        'PARTIAL_PUBLISHED',
      };
      if (!acceptedPostStatuses.contains(postStatus)) {
        _setUploadStatus(
          'ระบบตอบสถานะโพสต์ที่ยังยืนยันไม่ได้ กรุณาตรวจรายการโพสต์ก่อนลองใหม่',
        );
        return null;
      }
      _blockedSubmissionDraftIds.remove(submittedDraftId);

      var draftCleanupWarning = '';
      if (_activeDraftId == submittedDraftId &&
          _draftOperationStillOwned(
            ownerUserId: submittedDraftOwnerUserId,
            generation: submittedDraftGeneration,
          )) {
        final deleted = await _deleteDraftAndConfirmAbsent(
          submittedDraftStore,
          submittedDraftId,
        );
        if (deleted) {
          if (_activeDraftId == submittedDraftId &&
              _draftOperationStillOwned(
                ownerUserId: submittedDraftOwnerUserId,
                generation: submittedDraftGeneration,
              ) &&
              mounted) {
            setState(() {
              _drafts = _drafts
                  .where((candidate) => candidate.id != submittedDraftId)
                  .toList();
              _clearActiveDraftFormState();
            });
          }
          try {
            final drafts = await submittedDraftStore.listDrafts();
            if (mounted &&
                _draftOperationStillOwned(
                  ownerUserId: submittedDraftOwnerUserId,
                  generation: submittedDraftGeneration,
                )) {
              setState(() => _drafts = drafts);
            }
          } catch (_) {
            draftCleanupWarning = ' · ลบร่างแล้ว แต่รีเฟรชรายการร่างไม่สำเร็จ';
          }
        } else {
          draftCleanupWarning =
              ' · โพสต์เข้าคิวแล้ว แต่ลบร่างในเครื่องไม่สำเร็จ';
        }
      }

      if (identical(_coverResult, selectedCover)) {
        if (mounted) {
          setState(() => _coverResult = null);
        } else {
          _coverResult = null;
        }
      }
      if (selectedCover != null) {
        unawaited(selectedCover.cleanupTemporaryFiles());
      }

      unawaited(_analytics.logPublishSucceeded(
        platformCount: post.platforms.length,
        isScheduled: scheduledAt != null,
      ));

      if (!mounted) {
        return null;
      }

      if (scheduledAt != null && postStatus == 'QUEUED') {
        widget.onScheduledPostCreated?.call(post);
      }

      setState(() {
        final watermarkText = didApplyWatermark ? 'ใส่ลายน้ำแล้ว · ' : '';
        final replayText = post.idempotentReplay ? 'พบรายการเดิม · ' : '';
        final statusText = switch (postStatus) {
          'PUBLISHING' => 'กำลังส่ง',
          'PUBLISHED' => 'ส่งสำเร็จ',
          'PARTIAL_PUBLISHED' => 'ส่งสำเร็จเพียงบางช่องทาง',
          _ => 'รับรายการ ${post.platforms.length} ช่องทางแล้ว กำลังส่ง',
        };
        _successMessage =
            '$watermarkText$replayText$statusText: ${post.id}$draftCleanupWarning';
      });
      return post;
    } on _PublishOwnerChangedException {
      _showDraftOwnerChangedError();
      return null;
    } on CoverImageException catch (error) {
      unawaited(_analytics.logPublishFailed(reason: 'cover'));
      if (!mounted) {
        return null;
      }
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
        _successMessage = null;
      });
      if (isPublishingUnavailable(error)) {
        _setPublishingUnavailableStatus(videoWasUploaded: didUploadVideo);
      } else if (error.code == 'IDEMPOTENT_POST_FAILED' ||
          error.code == 'IDEMPOTENCY_KEY_REUSED') {
        setState(() => _blockedSubmissionDraftIds.add(submittedDraftId));
        _setUploadStatus(
          error.code == 'IDEMPOTENT_POST_FAILED'
              ? 'รายการโพสต์เดิมจบด้วยสถานะล้มเหลว ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่'
              : 'ข้อมูลในร่างเปลี่ยนจากคำขอเดิม ร่างยังอยู่ในเครื่อง กรุณาตรวจปลายทางก่อนเริ่มรายการโพสต์ใหม่',
        );
      } else {
        _setUploadStatus(error.message);
      }
      return null;
    } on SocketException {
      unawaited(_analytics.logPublishFailed(reason: 'network'));
      if (!mounted) {
        return null;
      }

      setState(() {
        _errorMessage = null;
        _successMessage = null;
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
        _successMessage = null;
      });
      _setUploadStatus('เกิดข้อผิดพลาดระหว่างสร้างโพสต์');
      return null;
    } finally {
      final watermarkedVideo = generatedWatermarkedVideo;
      if (watermarkedVideo != null) {
        try {
          await watermarkedVideo.cleanupTemporaryFiles();
        } catch (_) {
          if (mounted) {
            setState(() {
              _errorMessage ??=
                  'ล้างไฟล์วิดีโอชั่วคราวไม่สำเร็จ กรุณาตรวจพื้นที่ว่างในเครื่อง';
            });
          }
        }
      }
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _setPublishingUnavailableStatus({required bool videoWasUploaded}) {
    final body = videoWasUploaded
        ? publishingUnavailableAfterUploadMessage
        : publishingUnavailableBeforeUploadMessage;
    _pendingInlineError = '$publishingUnavailableTitle $body';
    _pendingStatusSheet = PostDeeStatusSheetData(
      icon: Icons.cloud_off_rounded,
      iconColor: const Color(0xFFF59E0B),
      iconTint: const Color(0x24F59E0B),
      title: publishingUnavailableTitle,
      body: body,
      primaryLabel: 'รับทราบ',
      secondaryLabel: null,
    );
    _pickVideoAfterStatus = false;
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
        _draftUnavailablePlatforms.remove(platform);
      } else {
        _selectedPlatforms.remove(platform);
        _draftUnavailablePlatforms.remove(platform);
      }
    });
  }

  Future<void> _openPlatformSettings(SocialPlatform platform) async {
    final next = await showModalBottomSheet<PlatformPublishSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PlatformSettingsSheet(
        platform: platform,
        initialSettings: _platformSettings,
        connection: _connectionDetails[platform],
      ),
    );
    if (!mounted || next == null) return;
    setState(() => _platformSettings = next);
  }

  void _selectAllConnectedPlatforms() {
    setState(() {
      _selectedPlatforms
        ..clear()
        ..addAll(_connectedPlatforms);
    });
  }

  void _clearSelectedPlatforms() {
    setState(() {
      _selectedPlatforms.clear();
      _draftUnavailablePlatforms.clear();
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
    final isFormBusy = _isSavingDraft ||
        _isSubmitting ||
        _isPreparingReview ||
        _isPreparingSubmission;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: isFormBusy,
            child: ListView(
              key: const ValueKey('uploader-scroll'),
              padding: const EdgeInsets.fromLTRB(16, AppTheme.spaceMd, 16, 116),
              children: [
                const _UploadPageHeader(),
                const SizedBox(height: AppTheme.spaceSm),
                _DraftSummaryCard(
                  draftCount: _drafts.length,
                  isLoading: _isLoadingDrafts,
                  isAvailable: _draftStoreAvailable,
                  onOpen: _openDrafts,
                ),
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
                  if (_coverResult != null)
                    Center(
                      child: Text(
                        'เลือกเฟรมที่ '
                        '${formatReviewVideoClock(Duration(milliseconds: _coverResult!.coverFrameTimeMs))}',
                        key: const ValueKey('uploader-cover-time'),
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: AppTheme.spaceLg),
                _PlatformSelectorSection(
                  selectedPlatforms: {
                    ..._selectedPlatforms,
                    ..._draftUnavailablePlatforms,
                  },
                  connectedPlatforms: _connectedPlatforms,
                  unavailableDraftPlatforms: _draftUnavailablePlatforms,
                  isLoadingConnections: _isLoadingConnections,
                  connectionsErrorMessage: _connectionsErrorMessage,
                  platformSettings: _platformSettings,
                  onPlatformChanged: _setPlatformSelected,
                  onOpenPlatformSettings: _openPlatformSettings,
                  onSelectAll: _selectAllConnectedPlatforms,
                  onClearAll: _clearSelectedPlatforms,
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
                const _UploadEpToolSection(),
                const SizedBox(height: AppTheme.spaceLg),
              ],
            ),
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
              if (_requiresNewSubmissionAttempt) ...[
                OutlinedButton.icon(
                  key: const ValueKey('uploader-start-new-publish-attempt'),
                  onPressed: _isSavingDraft || _isSubmitting
                      ? null
                      : _startNewSubmissionAttempt,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('เริ่มรายการโพสต์ใหม่'),
                ),
                const SizedBox(height: AppTheme.spaceSm),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('uploader-save-draft-button'),
                      onPressed: _isSavingDraft ||
                              _isSubmitting ||
                              _isGeneratingCaption ||
                              _isPreparingReview ||
                              _isPreparingSubmission ||
                              !_draftStoreAvailable
                          ? null
                          : _saveDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        _isSavingDraft ? 'กำลังบันทึก...' : 'บันทึกร่าง',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _GradientActionButton(
                      key: const ValueKey('uploader-sticky-post-button'),
                      label: _isSubmitting || _isPreparingSubmission
                          ? 'กำลังส่ง...'
                          : _isPreparingReview
                              ? 'กำลังเตรียม...'
                              : 'โพสต์',
                      icon: Icons.send_rounded,
                      onPressed: _isSubmitting ||
                              _isSavingDraft ||
                              _isGeneratingCaption ||
                              _isPreparingReview ||
                              _isPreparingSubmission ||
                              _requiresNewSubmissionAttempt
                          ? null
                          : _reviewThenPost,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftSummaryCard extends StatelessWidget {
  const _DraftSummaryCard({
    required this.draftCount,
    required this.isLoading,
    required this.isAvailable,
    required this.onOpen,
  });

  final int draftCount;
  final bool isLoading;
  final bool isAvailable;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: isAvailable && !isLoading,
      label: 'ฉบับร่างในเครื่อง $draftCount รายการ',
      child: InkWell(
        key: const ValueKey('uploader-open-drafts'),
        onTap: isAvailable && !isLoading ? onOpen : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderSoft),
          ),
          child: Row(
            children: [
              const Icon(Icons.drafts_outlined, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading
                          ? 'กำลังโหลดฉบับร่าง...'
                          : 'ฉบับร่างในเครื่อง ($draftCount)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      'ยังไม่อัปโหลด ไม่โพสต์ และไม่ใช้โควตา',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
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
                'อัปโหลดครั้งเดียว แล้วเลือกช่องทางที่ต้องการ',
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

class _UploadEpToolSection extends StatelessWidget {
  const _UploadEpToolSection();

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

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('uploader-ep-tool-section'),
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
          ],
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
            child: hasCoverImage
                ? const SizedBox.shrink()
                : Icon(
                    Icons.play_circle_rounded,
                    size: 46,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
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
    required this.unavailableDraftPlatforms,
    required this.isLoadingConnections,
    required this.connectionsErrorMessage,
    required this.platformSettings,
    required this.onPlatformChanged,
    required this.onOpenPlatformSettings,
    required this.onSelectAll,
    required this.onClearAll,
    required this.onOpenConnections,
    required this.onRetryConnections,
  });

  final Set<SocialPlatform> selectedPlatforms;
  final Set<SocialPlatform> connectedPlatforms;
  final Set<SocialPlatform> unavailableDraftPlatforms;
  final bool isLoadingConnections;
  final String? connectionsErrorMessage;
  final PlatformPublishSettings platformSettings;
  final void Function(SocialPlatform platform, bool isSelected)
      onPlatformChanged;
  final ValueChanged<SocialPlatform> onOpenPlatformSettings;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final VoidCallback onOpenConnections;
  final VoidCallback onRetryConnections;

  // Short per-platform descriptions from the prototype's connection list.
  static const _subLabels = {
    SocialPlatform.tiktok: 'ส่งคลิปไปแก้ต่อใน TikTok',
    SocialPlatform.youtubeShorts: 'อัปขึ้น YouTube Shorts จากคลิปเดียว',
    SocialPlatform.instagramReels: 'เผยแพร่ Reels ตามบัญชีที่เชื่อม',
    SocialPlatform.facebookReels: 'เลือกเผยแพร่หรือร่างบนเพจ',
    SocialPlatform.shopeeVideo: 'โพสต์วิดีโอขึ้น Shopee Video',
    SocialPlatform.lazadaVideo: 'โพสต์วิดีโอขึ้น Lazada Video',
  };

  @override
  Widget build(BuildContext context) {
    final hasConnectedPlatforms = connectedPlatforms.isNotEmpty;
    final visiblePlatforms = SocialPlatform.values
        .where(connectedPlatforms.contains)
        .toList(growable: false);
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
              'เลือกแล้ว ${selectedPlatforms.length} ช่องทาง',
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
          label: isLoadingConnections
              ? 'กำลังตรวจสอบช่องทาง'
              : connectedPlatforms.isEmpty
                  ? 'ยังไม่ได้เชื่อมต่อช่องทาง'
                  : 'เชื่อมต่อแล้ว ${connectedPlatforms.length} ช่องทาง',
          child: GestureDetector(
            onTap: connectionsErrorMessage != null
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
                        : connectedPlatforms.isEmpty
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
                                  (connectedPlatforms.isEmpty
                                      ? 'ยังไม่ได้เชื่อมต่อช่องทาง'
                                      : 'เชื่อมต่อแล้ว ${connectedPlatforms.length} ช่องทาง'),
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
                          connectedPlatforms.isEmpty
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
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFB5740B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (unavailableDraftPlatforms.isNotEmpty) ...[
          const SizedBox(height: 8),
          PostDeeNotice(
            message: 'ฉบับร่างเลือกไว้แต่ยังไม่ได้เชื่อม: '
                '${unavailableDraftPlatforms.map((platform) => platform.label).join(', ')}',
            color: const Color(0xFFB5740B),
            icon: Icons.link_off_rounded,
          ),
        ],
        if (visiblePlatforms.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('uploader-select-all-platforms'),
                onPressed: selectedPlatforms.length == visiblePlatforms.length
                    ? null
                    : onSelectAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                ),
                child: const Text('เลือกทั้งหมด'),
              ),
              TextButton(
                key: const ValueKey('uploader-clear-all-platforms'),
                onPressed: selectedPlatforms.isEmpty ? null : onClearAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                ),
                child: const Text('ล้างทั้งหมด'),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
                    settingsSummary: _settingsSummary(
                      visiblePlatforms[index],
                      platformSettings,
                    ),
                    onOpenSettings: () =>
                        onOpenPlatformSettings(visiblePlatforms[index]),
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
      ],
    );
  }

  String _settingsSummary(
    SocialPlatform platform,
    PlatformPublishSettings settings,
  ) {
    switch (platform) {
      case SocialPlatform.tiktok:
        return settings.tiktokPublishMode == TikTokPublishMode.inboxDraft
            ? 'ร่างใน TikTok'
            : 'ยังไม่พร้อมโพสต์ตรง';
      case SocialPlatform.youtubeShorts:
        if (!settings.canSubmit(platform)) return 'ต้องตั้งค่า';
        return switch (settings.youtubeVisibility) {
          YouTubeVisibility.private => 'ส่วนตัว · พร้อม',
          YouTubeVisibility.unlisted => 'ไม่เป็นสาธารณะ · พร้อม',
          YouTubeVisibility.public => 'สาธารณะ · พร้อม',
        };
      case SocialPlatform.instagramReels:
        return settings.instagramShareToFeed ? 'แชร์ในฟีด' : 'ไม่แชร์ในฟีด';
      case SocialPlatform.facebookReels:
        return switch (settings.facebookPublishMode) {
          FacebookPublishMode.publish => 'เผยแพร่บนเพจ',
          FacebookPublishMode.pageDraft => 'ร่างบนเพจ',
          null => 'ต้องตั้งค่า',
        };
      case SocialPlatform.shopeeVideo:
      case SocialPlatform.lazadaVideo:
        return 'ยังไม่รองรับ';
    }
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.platform,
    required this.subLabel,
    required this.isSelected,
    required this.settingsSummary,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final SocialPlatform platform;
  final String subLabel;
  final bool isSelected;
  final String settingsSummary;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: platform.label,
      button: true,
      enabled: true,
      selected: isSelected,
      child: Column(
        children: [
          InkWell(
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
          if (isSelected)
            Padding(
              padding: const EdgeInsets.fromLTRB(62, 0, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: ValueKey(
                    'uploader-platform-settings-${platform.apiValue}',
                  ),
                  onPressed: onOpenSettings,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          settingsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.tune_rounded, size: 17),
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

class _PlatformSettingsSheet extends StatefulWidget {
  const _PlatformSettingsSheet({
    required this.platform,
    required this.initialSettings,
    this.connection,
  });

  final SocialPlatform platform;
  final PlatformPublishSettings initialSettings;
  final SocialConnectionResult? connection;

  @override
  State<_PlatformSettingsSheet> createState() => _PlatformSettingsSheetState();
}

class _PlatformSettingsSheetState extends State<_PlatformSettingsSheet> {
  late PlatformPublishSettings _settings;
  late final TextEditingController _youtubeTitleController;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _youtubeTitleController = TextEditingController(
      text: widget.initialSettings.youtubeTitle,
    );
  }

  @override
  void dispose() {
    _youtubeTitleController.dispose();
    super.dispose();
  }

  PlatformPublishSettings get _currentSettings => _settings.copyWith(
        youtubeTitle: _youtubeTitleController.text,
      );

  @override
  Widget build(BuildContext context) {
    final current = _currentSettings;
    final displayName = widget.connection == null
        ? ''
        : (widget.connection!.displayName?.trim().isNotEmpty == true
            ? widget.connection!.displayName!.trim()
            : widget.connection!.externalAccountId?.trim() ?? '');
    final canSave = current.canSubmit(widget.platform);

    return Padding(
      key: const ValueKey('uploader-platform-settings-sheet'),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  SocialPlatformLogo(platform: widget.platform, size: 34),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          publishReviewPlatformLabel(widget.platform),
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (displayName.isNotEmpty)
                          Text(
                            displayName,
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.borderSoft),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: _buildSettings(current),
              ),
            ),
            Divider(height: 1, color: AppTheme.borderSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('uploader-platform-settings-save'),
                      onPressed: canSave
                          ? () => Navigator.of(context).pop(current)
                          : null,
                      child: const Text('บันทึกการตั้งค่า'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings(PlatformPublishSettings current) {
    switch (widget.platform) {
      case SocialPlatform.tiktok:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_rounded),
              title: Text('ส่งเป็นร่างเข้า TikTok'),
              subtitle: Text(
                'ส่งออกจริงและใช้โควตาโพสต์ · ต้องเปิด TikTok เพื่อตั้งค่าต่อ',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('uploader-tiktok-direct-disabled'),
              onPressed: null,
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('โพสต์ตรง · ยังไม่พร้อม'),
            ),
            const SizedBox(height: 8),
            Text(
              'โพสต์ตรงจะเปิดเมื่อ PostDee โหลดตัวเลือกความเป็นส่วนตัวและความยินยอมล่าสุดจาก TikTok ได้',
              style: TextStyle(color: AppTheme.textMuted, height: 1.45),
            ),
          ],
        );
      case SocialPlatform.youtubeShorts:
        final validationMessage = current.youtubeValidationMessage;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('uploader-youtube-title'),
              controller: _youtubeTitleController,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'ชื่อวิดีโอ YouTube',
                helperText: 'แคปชั่นหลักจะใช้เป็นคำอธิบาย',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<YouTubeVisibility>(
              key: const ValueKey('uploader-youtube-visibility'),
              initialValue: current.youtubeVisibility,
              decoration: const InputDecoration(labelText: 'การมองเห็น'),
              items: const [
                DropdownMenuItem(
                  value: YouTubeVisibility.private,
                  child: Text('ส่วนตัว (Private)'),
                ),
                DropdownMenuItem(
                  value: YouTubeVisibility.unlisted,
                  child: Text('ไม่เป็นสาธารณะ (Unlisted)'),
                ),
                DropdownMenuItem(
                  value: YouTubeVisibility.public,
                  child: Text('สาธารณะ (Public)'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _settings = current.copyWith(
                      youtubeVisibility: value,
                    ));
              },
            ),
            if (current.youtubeVisibility != YouTubeVisibility.private) ...[
              const SizedBox(height: 8),
              Text(
                'YouTube อาจยังคงวิดีโอเป็น Private จนกว่าจะผ่านการตรวจ API',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            _BinarySettingRow(
              title: 'วิดีโอนี้ทำมาเพื่อเด็กหรือไม่?',
              value: current.youtubeMadeForKids,
              yesKey: const ValueKey('uploader-youtube-made-for-kids-yes'),
              noKey: const ValueKey('uploader-youtube-made-for-kids-no'),
              onChanged: (value) => setState(
                () => _settings = current.copyWith(youtubeMadeForKids: value),
              ),
            ),
            const SizedBox(height: 16),
            _BinarySettingRow(
              title: 'มีสื่อสังเคราะห์ที่ดูเหมือนจริงหรือไม่?',
              value: current.youtubeContainsSyntheticMedia,
              yesKey: const ValueKey('uploader-youtube-synthetic-yes'),
              noKey: const ValueKey('uploader-youtube-synthetic-no'),
              onChanged: (value) => setState(
                () => _settings = current.copyWith(
                  youtubeContainsSyntheticMedia: value,
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const ValueKey(
                'uploader-youtube-guidelines-certified',
              ),
              contentPadding: EdgeInsets.zero,
              value: current.youtubeCommunityGuidelinesCertified,
              onChanged: (value) => setState(
                () => _settings = current.copyWith(
                  youtubeCommunityGuidelinesCertified: value ?? false,
                ),
              ),
              title: const Text(
                'ฉันยืนยันว่าวิดีโอเป็นไปตามกฎชุมชน YouTube',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (validationMessage != null)
              Text(
                validationMessage,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        );
      case SocialPlatform.instagramReels:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PostDeeNotice(
              message:
                  'Instagram ไม่มี Private รายโพสต์ วิดีโอจะเผยแพร่ตามบัญชีที่เชื่อม',
              color: Color(0xFFB5740B),
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('uploader-instagram-share-to-feed'),
              contentPadding: EdgeInsets.zero,
              value: current.instagramShareToFeed,
              onChanged: (value) => setState(
                () => _settings = current.copyWith(
                  instagramShareToFeed: value,
                ),
              ),
              title: const Text('แชร์ Reels ไปยังฟีด'),
            ),
          ],
        );
      case SocialPlatform.facebookReels:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsChoiceButton(
              key: const ValueKey('uploader-facebook-publish'),
              label: 'เผยแพร่บนเพจ',
              isSelected:
                  current.facebookPublishMode == FacebookPublishMode.publish,
              onPressed: () => setState(
                () => _settings = current.copyWith(
                  facebookPublishMode: FacebookPublishMode.publish,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsChoiceButton(
              key: const ValueKey('uploader-facebook-page-draft'),
              label: 'เก็บเป็นร่างบนเพจ',
              subtitle: 'ส่งออกจริงและใช้โควตาโพสต์',
              isSelected:
                  current.facebookPublishMode == FacebookPublishMode.pageDraft,
              onPressed: () => setState(
                () => _settings = current.copyWith(
                  facebookPublishMode: FacebookPublishMode.pageDraft,
                ),
              ),
            ),
          ],
        );
      case SocialPlatform.shopeeVideo:
      case SocialPlatform.lazadaVideo:
        return const Text('ช่องทางนี้ยังไม่รองรับการโพสต์');
    }
  }
}

class _BinarySettingRow extends StatelessWidget {
  const _BinarySettingRow({
    required this.title,
    required this.value,
    required this.yesKey,
    required this.noKey,
    required this.onChanged,
  });

  final String title;
  final bool? value;
  final Key yesKey;
  final Key noKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SettingsChoiceButton(
                key: yesKey,
                label: 'ใช่',
                isSelected: value == true,
                onPressed: () => onChanged(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SettingsChoiceButton(
                key: noKey,
                label: 'ไม่ใช่',
                isSelected: value == false,
                onPressed: () => onChanged(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsChoiceButton extends StatelessWidget {
  const _SettingsChoiceButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor:
            isSelected ? AppTheme.accent.withValues(alpha: 0.10) : null,
        side: BorderSide(
          color: isSelected ? AppTheme.accent : AppTheme.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        children: [
          Icon(
            isSelected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
    this.errorMessage,
  });

  final TextEditingController guidanceController;
  final String? selectedVideoName;
  final bool isGenerating;
  final String? errorMessage;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final clipName = selectedVideoName?.trim();

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
                Text(
                  'Starter/Pro',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.accentCyanInk,
                        fontWeight: FontWeight.w800,
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
            PostDeeGradientButton(
              key: const ValueKey('uploader-ai-generate-button'),
              label: isGenerating ? 'AI กำลังฟังคลิป...' : 'ให้ AI ช่วยเขียน',
              icon: Icons.auto_awesome,
              onPressed: isGenerating ? null : onGenerate,
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
