import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/monitoring/postdee_analytics.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/connections_screen.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/growth_tool_settings_store.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import '../shared/postdee_status_sheet.dart';
import 'clip_frame_extractor.dart';
import 'publish_flow_screen.dart';
import 'publish_review_screen.dart';
import 'video_picker_service.dart';
import 'watermark_video_processor.dart';

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
typedef UploaderScheduledPostCreated = void Function(QueuedPostResult post);
typedef UploaderConnectionsLoader = Future<List<SocialConnectionResult>>
    Function();

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
    this.loadSocialConnections,
    this.onScheduledPostCreated,
    this.onPublishFinished,
    this.onViewAnalytics,
    this.analytics,
    this.watermarkVideo,
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
  final UploaderConnectionsLoader? loadSocialConnections;
  final UploaderScheduledPostCreated? onScheduledPostCreated;
  final VoidCallback? onPublishFinished;
  final VoidCallback? onViewAnalytics;
  final PostDeeAnalytics? analytics;
  final UploaderWatermarkVideoProcessor? watermarkVideo;

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
  final Set<SocialPlatform> _connectedPlatforms = {};
  final List<TextTemplateResult> _templates = [];
  bool _isSubmitting = false;
  bool _isLoadingTemplates = false;
  bool _isGeneratingCaption = false;
  bool _isAdvancedModeEnabled = true;
  bool _isLoadingConnections = true;
  String? _connectionsErrorMessage;
  String? _successMessage;
  String? _errorMessage;
  String? _templateErrorMessage;
  String? _aiCaptionErrorMessage;
  String? _selectedVideoName;
  PostDeeStatusSheetData? _pendingStatusSheet;
  bool _pickVideoAfterStatus = false;
  String? _pendingInlineError;

  @override
  void initState() {
    super.initState();
    _prefillInitialVideo();
    unawaited(_loadConnections());
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
    final now = DateTime.now();
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
      lastDate: today.add(const Duration(days: 365)),
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

      if (video == null) {
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

      setState(() {
        _selectedVideoName = fileName;
        _localFilePathController.text = video.path;
        _fileNameController.text = fileName;
        _sizeBytesController.text = video.sizeBytes.toString();
        _widthController.text = video.width?.toString() ?? '';
        _heightController.text = video.height?.toString() ?? '';
        _aiCaptionErrorMessage = null;
        _errorMessage = null;
        _successMessage = null;
      });
      unawaited(_analytics.logVideoSelected(
        hasDimensions: video.width != null && video.height != null,
      ));
    } catch (error) {
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

    // The backend requires a caption, so catch it here instead of letting the
    // user confirm the review only to have the post bounce back.
    if (_captionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'เพิ่มแคปชั่นก่อนโพสต์';
        _successMessage = null;
      });
      return;
    }

    final watermarkEnabled = await _shouldApplyAutoWatermark();
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
    _pendingStatusSheet = null;
    _pickVideoAfterStatus = false;
    _pendingInlineError = null;
    final caption = _captionController.text.trim();
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

        uploadVideoFileForRequest = watermarkedVideo.file;
        uploadFileName = watermarkedVideo.fileName;
        uploadSizeBytes = watermarkedVideo.sizeBytes;
        didApplyWatermark = true;
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
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
      final createPost = widget.createPost ?? _apiClient.createPost;
      final post = await createPost(
        CreatePostRequest(
          caption: caption,
          videoS3Key: upload.videoS3Key,
          platforms:
              _selectedPlatforms.map((platform) => platform.apiValue).toList(),
          scheduledAt: scheduledAt,
        ),
      );

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
                isSubmitting: _isSubmitting,
                onPickVideo: _pickVideoFile,
              ),
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

  static const _manualEditorDetail = GrowthToolDetail(
    id: 'manual_editor',
    title: 'ตัดต่อเอง',
    description: 'วางแผนไทม์ไลน์ ซับ สติกเกอร์ และฟิลเตอร์ไว้ล่วงหน้า',
    status: 'เร็ว ๆ นี้',
    icon: Icons.video_settings_outlined,
    color: AppTheme.accentCyan,
    prototypeOnly: true,
    settings: [
      GrowthToolSettingOption(
        id: 'timeline_layers',
        label: 'จัดไทม์ไลน์และเลเยอร์ข้อความ',
      ),
      GrowthToolSettingOption(
        id: 'subtitle_sticker_filter',
        label: 'ซับ สติกเกอร์ และฟิลเตอร์ในคลิปเดียว',
      ),
      GrowthToolSettingOption(
        id: 'cta_card',
        label: 'ปรับ CTA ก่อนส่งไปโพสต์',
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
        const SizedBox(height: AppTheme.spaceSm),
        const _WideUploadToolButton(
          key: ValueKey('uploader-tool-manual-editor'),
          detail: _manualEditorDetail,
        ),
        const SizedBox(height: AppTheme.spaceSm),
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

class _WideUploadToolButton extends StatelessWidget {
  const _WideUploadToolButton({
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
            border:
                Border.all(color: AppTheme.borderSoft.withValues(alpha: 0.84)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.tileRadius),
                  ),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      detail.icon,
                      color: AppTheme.inkFor(color),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
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
    required this.isSubmitting,
    required this.onPickVideo,
  });

  final String? videoName;
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
          Center(
            child: Icon(
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
    final hasConnectedPlatforms = connectedPlatforms.isNotEmpty;
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
        const SizedBox(height: 10),
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
                  index < SocialPlatform.values.length;
                  index += 1) ...[
                if (index > 0) Divider(height: 1, color: AppTheme.borderSoft),
                _PlatformRow(
                  platform: SocialPlatform.values[index],
                  subLabel: connectedPlatforms.contains(
                    SocialPlatform.values[index],
                  )
                      ? _subLabels[SocialPlatform.values[index]] ?? ''
                      : connectablePlatforms.contains(
                          SocialPlatform.values[index],
                        )
                          ? 'ยังไม่ได้เชื่อมต่อ'
                          : 'ยังไม่รองรับการเชื่อมต่อ',
                  isConnected: connectedPlatforms.contains(
                    SocialPlatform.values[index],
                  ),
                  isConnectable: connectablePlatforms.contains(
                    SocialPlatform.values[index],
                  ),
                  isSelected: selectedPlatforms.contains(
                    SocialPlatform.values[index],
                  ),
                  onConnect: onOpenConnections,
                  onChanged: (next) => onPlatformChanged(
                    SocialPlatform.values[index],
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
    required this.isConnected,
    required this.isConnectable,
    required this.isSelected,
    required this.onConnect,
    required this.onChanged,
  });

  final SocialPlatform platform;
  final String subLabel;
  final bool isConnected;
  final bool isConnectable;
  final bool isSelected;
  final VoidCallback onConnect;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: platform.label,
      button: true,
      enabled: isConnected,
      selected: isSelected,
      child: InkWell(
        key: ValueKey('uploader-platform-${platform.apiValue}'),
        onTap: isConnected ? () => onChanged(!isSelected) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Opacity(
                opacity: isConnectable ? 1 : 0.5,
                child: SocialPlatformLogo(platform: platform, size: 36),
              ),
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
                        color: isConnectable
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
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
              if (!isConnectable)
                Container(
                  key: ValueKey('uploader-soon-${platform.apiValue}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.glassDeep,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'เร็ว ๆ นี้',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                )
              else if (!isConnected)
                TextButton(
                  key: ValueKey('uploader-connect-${platform.apiValue}'),
                  onPressed: onConnect,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentCyanInk,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'เชื่อมต่อ',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                )
              else
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
                    'ตั้งเวลาได้ในแพ็กเกจ Starter ขึ้นไป',
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
