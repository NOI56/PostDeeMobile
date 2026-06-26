import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';
import '../platforms/social_platform_logo.dart';
import '../shared/growth_tool_detail_sheet.dart';
import '../shared/growth_tool_settings_store.dart';
import '../shared/postdee_card.dart';
import '../shared/postdee_notice.dart';
import 'clip_frame_extractor.dart';
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
    this.onScheduledPostCreated,
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
  final UploaderScheduledPostCreated? onScheduledPostCreated;
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
  final Set<SocialPlatform> _selectedPlatforms = {
    SocialPlatform.tiktok,
    SocialPlatform.youtubeShorts,
  };
  final List<TextTemplateResult> _templates = [];
  bool _isSubmitting = false;
  bool _isLoadingTemplates = false;
  bool _isGeneratingCaption = false;
  String? _successMessage;
  String? _errorMessage;
  String? _templateErrorMessage;
  String? _aiCaptionErrorMessage;
  String? _selectedVideoName;

  @override
  void initState() {
    super.initState();
    _prefillInitialVideo();
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
        _aiCaptionErrorMessage =
            'เลือกคลิปจริงจากเครื่องก่อนให้ AI คิดแคปชั่น';
      });
      return null;
    }

    if (!localVideoFile.existsSync()) {
      setState(() {
        _aiCaptionErrorMessage =
            'ไม่พบไฟล์วิดีโอในเครื่อง';
      });
      return null;
    }

    sizeBytes ??= localVideoFile.lengthSync();

    if (fileName.isEmpty || sizeBytes < 1) {
      setState(() {
        _aiCaptionErrorMessage =
            'ไฟล์วิดีโอที่เลือกมีข้อมูลไม่ครบ';
      });
      return null;
    }

    if (width != null &&
        height != null &&
        !_isVerticalNineBySixteen(width: width, height: height)) {
      setState(() {
        _aiCaptionErrorMessage =
            'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920';
      });
      return null;
    }

    final createUpload = widget.createUpload ?? _apiClient.createUpload;
    final upload = await createUpload(
      CreateUploadRequest(
        fileName: fileName,
        contentType: 'video/mp4',
        sizeBytes: sizeBytes,
        width: width,
        height: height,
      ),
    );
    final uploadVideoFile =
        widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
    await uploadVideoFile(upload, localVideoFile);

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

        final upload = await createUpload(
          CreateUploadRequest(
            fileName: 'frame_${index + 1}.jpg',
            contentType: 'image/jpeg',
            sizeBytes: sizeBytes,
          ),
        );
        await uploadVideoFile(upload, frame);
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
      final selectedFrameKeys =
          subscription.isPro ? await _uploadAiCaptionFrames() : const <String>[];

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
    } catch (error) {
      setState(() {
        _errorMessage = 'เลือกวิดีโอไม่ได้: $error';
        _successMessage = null;
      });
    }
  }

  Future<void> _createPost() async {
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
      return;
    }

    if (!localVideoFile.existsSync()) {
      setState(() {
        _errorMessage = 'ไม่พบไฟล์วิดีโอในเครื่อง';
        _successMessage = null;
      });
      return;
    }

    sizeBytes ??= localVideoFile.lengthSync();

    if (caption.isEmpty || fileName.isEmpty) {
      setState(() {
        _errorMessage = 'ต้องมีแคปชั่น ชื่อไฟล์ และขนาดไฟล์ที่ถูกต้อง';
        _successMessage = null;
      });
      return;
    }

    if (_scheduledAtController.text.trim().isNotEmpty && scheduledAt == null) {
      setState(() {
        _errorMessage = 'เวลาตั้งโพสต์ต้องเป็นรูปแบบ ISO ที่ถูกต้อง';
        _successMessage = null;
      });
      return;
    }

    if (scheduledAt != null && !scheduledAt.isAfter(widget.now())) {
      setState(() {
        _errorMessage = 'เวลาตั้งโพสต์ต้องเป็นเวลาในอนาคต';
        _successMessage = null;
      });
      return;
    }

    if (width != null &&
        height != null &&
        !_isVerticalNineBySixteen(width: width, height: height)) {
      setState(() {
        _errorMessage = 'ใช้วิดีโอแนวตั้ง 9:16 เช่น 1080x1920';
        _successMessage = null;
      });
      return;
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
            return;
          }

          setState(() {
            _errorMessage =
                'การตั้งเวลาโพสต์ต้องใช้แพ็กเกจ Starter 199 หรือ Pro 299';
          });
          return;
        }
      }

      if (subscription.requiresPhoneVerification) {
        if (!mounted) {
          return;
        }

        setState(() {
          _errorMessage = 'ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน';
        });
        return;
      }

      var uploadVideoFileForRequest = localVideoFile;
      var uploadFileName = fileName;
      var uploadSizeBytes = sizeBytes;
      var didApplyWatermark = false;
      final shouldApplyWatermark = await _shouldApplyAutoWatermark();

      if (shouldApplyWatermark) {
        if (!mounted) {
          return;
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
      final upload = await createUpload(
        CreateUploadRequest(
          fileName: uploadFileName,
          contentType: 'video/mp4',
          sizeBytes: uploadSizeBytes,
          width: width,
          height: height,
        ),
      );
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      await uploadVideoFile(upload, uploadVideoFileForRequest);
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

      if (!mounted) {
        return;
      }

      if (scheduledAt != null) {
        widget.onScheduledPostCreated?.call(post);
      }

      setState(() {
        final watermarkText = didApplyWatermark ? 'ใส่ลายน้ำแล้ว · ' : '';
        _successMessage =
            '$watermarkTextจัดคิวโพสต์ ${post.platforms.length} แพลตฟอร์มแล้ว: ${post.id}';
      });
    } on WatermarkVideoException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
        _successMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'เชื่อมต่อ PostDee API ไม่ได้';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดระหว่างสร้างโพสต์';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _setPlatformSelected(SocialPlatform platform, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedPlatforms.add(platform);
      } else {
        _selectedPlatforms.remove(platform);
      }
    });
  }

  void _selectEveryPlatform() {
    setState(() {
      _selectedPlatforms
        ..clear()
        ..addAll(SocialPlatform.values);
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
              const _UploadStepHeader(
                key: ValueKey('uploader-step-video'),
                title: 'เลือกคลิป',
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
                onPlatformChanged: _setPlatformSelected,
                onSelectAll: _selectEveryPlatform,
              ),
              const SizedBox(height: AppTheme.spaceXl),
              const _UploadStepHeader(
                key: ValueKey('uploader-step-schedule'),
                title: 'ตั้งเวลา',
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
              const _AdvancedUploadToolsSection(),
              const SizedBox(height: AppTheme.spaceXl),
              const _UploadStepHeader(
                key: ValueKey('uploader-step-caption'),
                title: 'แคปชั่น',
              ),
              const SizedBox(height: AppTheme.spaceSm),
              PostDeeCard(
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
                        hintText: 'เขียนแคปชั่นหรือใส่จากเทมเพลต',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'เทมเพลต',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed:
                              _isLoadingTemplates ? null : _loadTemplates,
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
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
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
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
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
              ),
              const SizedBox(height: AppTheme.spaceLg),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            key: const ValueKey('uploader-sticky-action-bar'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.pitchBlack.withValues(alpha: 0),
                  AppTheme.pitchBlack,
                  AppTheme.pitchBlack,
                ],
                stops: const [0, 0.46, 1],
              ),
              border: Border(
                top: BorderSide(color: AppTheme.navBorder, width: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
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
                    onPressed: _selectedPlatforms.isEmpty || _isSubmitting
                        ? null
                        : _createPost,
                  ),
                ],
              ),
            ),
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
    final textTheme = Theme.of(context).textTheme;

    return Text(
      title,
      style: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _AdvancedUploadToolsSection extends StatelessWidget {
  const _AdvancedUploadToolsSection();

  static const _epTrimmerDetail = GrowthToolDetail(
    id: 'ep_trimmer',
    title: 'ตัดคลิปเป็น EP',
    description: 'ตรวจความยาวคลิปก่อนโพสต์ และเตรียมร่าง EP.1 / EP.2 ให้',
    status: 'ขั้นโพสต์',
    icon: Icons.content_cut,
    color: Color(0xFFFFD166),
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
    description: 'ฝังโลโก้ร้านลงในวิดีโอก่อนโพสต์',
    status: 'แบรนด์',
    icon: Icons.shield_outlined,
    color: AppTheme.success,
    settings: [
      GrowthToolSettingOption(
        id: 'shop_logo',
        label: 'อัปโหลดโลโก้ร้าน',
      ),
      GrowthToolSettingOption(
        id: 'watermark_position_size',
        label: 'เลือกตำแหน่งและขนาดลายน้ำ',
      ),
      GrowthToolSettingOption(
        id: 'preview_before_post',
        label: 'พรีวิวก่อนโพสต์โดยยังไม่แก้ไฟล์จริงในรอบนี้',
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
              'เลือกใช้ได้',
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
                  child: Text(
                    detail.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 136),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: InkWell(
            key: const ValueKey('uploader-video-preview-picker'),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            onTap: isSubmitting ? null : onPickVideo,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: AppTheme.border),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF263755),
                    Color(0xFF11131B),
                    Color(0xFF050507),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentCyan.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PreviewGlowPainter(),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _SmallPill(
                      icon: Icons.crop_portrait,
                      label: '9:16',
                      color: AppTheme.accentCyan,
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceMd),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasVideo
                                ? Icons.play_circle_fill
                                : Icons.cloud_upload_outlined,
                            color: hasVideo
                                ? AppTheme.accentCyan
                                : AppTheme.onDarkSecondary,
                            size: 34,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            videoName ?? 'รอเลือกวิดีโอ 9:16',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppTheme.onDarkPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasVideo
                                ? 'พร้อมเลือกแพลตฟอร์มและตั้งเวลา'
                                : 'เหมาะกับ Reels, Shorts และ TikTok',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.onDarkSecondary,
                                    ),
                          ),
                          const SizedBox(height: 6),
                          FilledButton.tonalIcon(
                            onPressed: isSubmitting ? null : onPickVideo,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            icon: const Icon(Icons.video_library_outlined),
                            label: Text(
                              hasVideo ? 'เปลี่ยนวิดีโอ' : 'เลือกวิดีโอ',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasVideo)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: FilledButton.icon(
                        onPressed: isSubmitting ? null : onPickVideo,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        icon: const Icon(Icons.edit, size: 15),
                        label: const Text('แก้ไขภาพปก'),
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
}

class _PlatformSelectorSection extends StatelessWidget {
  const _PlatformSelectorSection({
    required this.selectedPlatforms,
    required this.onPlatformChanged,
    required this.onSelectAll,
  });

  final Set<SocialPlatform> selectedPlatforms;
  final void Function(SocialPlatform platform, bool isSelected)
      onPlatformChanged;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'เลือกแพลตฟอร์ม',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            TextButton(
              onPressed: onSelectAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('เลือกทั้งหมด'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var index = 0;
                index < SocialPlatform.values.length;
                index += 1) ...[
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: _PlatformTile(
                    platform: SocialPlatform.values[index],
                    isSelected: selectedPlatforms.contains(
                      SocialPlatform.values[index],
                    ),
                    onChanged: (next) => onPlatformChanged(
                      SocialPlatform.values[index],
                      next,
                    ),
                  ),
                ),
              ),
              if (index < SocialPlatform.values.length - 1)
                const SizedBox(width: AppTheme.spaceSm),
            ],
          ],
        ),
      ],
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.isSelected,
    required this.onChanged,
  });

  final SocialPlatform platform;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? platform.color : AppTheme.border;

    return Semantics(
      label: platform.label,
      button: true,
      selected: isSelected,
      child: InkWell(
        key: ValueKey('uploader-platform-${platform.apiValue}'),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => onChanged(!isSelected),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass.withValues(alpha: isSelected ? 0.86 : 0.72),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected
                  ? borderColor.withValues(alpha: 0.72)
                  : AppTheme.border.withValues(alpha: 0.72),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SocialPlatformLogo(
                  platform: platform,
                  size: 28,
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: _CompactPlatformSwitch(
                    isSelected: isSelected,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactPlatformSwitch extends StatelessWidget {
  const _CompactPlatformSwitch({
    required this.isSelected,
  });

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.navActive : AppTheme.textMuted,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: SizedBox(
        width: 28,
        height: 16,
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: isSelected ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : AppTheme.glassDeep,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 12),
            ),
          ),
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
              label:
                  isGenerating ? 'AI กำลังฟังคลิป...' : 'ให้ AI คิดจากคลิปนี้',
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
                    'เวลาไทย (GMT+7) · ตั้งเวลาได้ใน Starter/Pro',
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

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppTheme.spaceXs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.onDarkPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final topGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.accentCyan.withValues(alpha: 0.42),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.52, size.height * 0.28),
          radius: size.width * 0.65,
        ),
      );

    final bottomGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.accentPink.withValues(alpha: 0.34),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.42, size.height * 0.8),
          radius: size.width * 0.75,
        ),
      );

    canvas.drawRect(Offset.zero & size, topGlow);
    canvas.drawRect(Offset.zero & size, bottomGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
