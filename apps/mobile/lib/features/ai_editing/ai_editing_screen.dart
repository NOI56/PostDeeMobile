import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_card.dart';
import '../uploader/uploader_screen.dart';
import '../uploader/video_picker_service.dart';
import 'capcut_editor_screen.dart';
import 'edit_styles.dart';
import 'subtitle_burn_video_processor.dart';

typedef EditorVideoPicker = Future<PickedVideoFile?> Function();
typedef EditorUploadCreator = Future<UploadResult> Function(
    CreateUploadRequest request);
typedef EditorVideoUploader = Future<void> Function(
  UploadResult upload,
  File videoFile,
);

/// Editing tab entry. Picks a real clip then opens the unified editor, which
/// mixes manual tools (trim/split/speed/volume/text/sticker/filter/adjust) with
/// AI helpers (auto caption + silence cut) — the user chooses per tool.
class AiEditingScreen extends StatefulWidget {
  const AiEditingScreen({
    super.key,
    this.pickVideo,
    this.createUpload,
    this.uploadVideoFile,
    this.transcribeClip,
  });

  final EditorVideoPicker? pickVideo;
  final EditorUploadCreator? createUpload;
  final EditorVideoUploader? uploadVideoFile;
  final CapCutTranscriptLoader? transcribeClip;

  @override
  State<AiEditingScreen> createState() => _AiEditingScreenState();
}

class _AiEditingScreenState extends State<AiEditingScreen> {
  final _apiClient = PostDeeApiClient();

  String _readFileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    final fileName = parts.isEmpty ? path : parts.last;

    return fileName.trim();
  }

  Future<void> _pickAndOpen({EditStyleSelection? style}) async {
    final picker = widget.pickVideo ?? GalleryVideoPicker().pickVideo;

    PickedVideoFile? picked;
    try {
      picked = await picker();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลือกวิดีโอไม่สำเร็จ')),
        );
      }
      return;
    }

    if (picked == null || !mounted) {
      return;
    }

    final file = File(picked.path);
    final fileName = picked.name.trim().isNotEmpty
        ? picked.name.trim()
        : _readFileNameFromPath(picked.path);

    try {
      if (!file.existsSync()) {
        throw const ApiException('ไม่พบไฟล์วิดีโอในเครื่อง');
      }

      final createUpload = widget.createUpload ?? _apiClient.createUpload;
      final upload = await createUpload(
        CreateUploadRequest(
          fileName: fileName,
          contentType: 'video/mp4',
          sizeBytes:
              picked.sizeBytes > 0 ? picked.sizeBytes : file.lengthSync(),
          width: picked.width,
          height: picked.height,
        ),
      );
      final uploadVideoFile =
          widget.uploadVideoFile ?? _apiClient.uploadVideoFile;
      await uploadVideoFile(upload, file);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CapCutEditorScreen(
            videoName: fileName,
            videoS3Key: upload.videoS3Key,
            videoFile: file,
            transcribeClip: widget.transcribeClip,
            requestEditPlan: _apiClient.requestAiEditPlan,
            initialStyle: style,
            onExported: _openPostFlow,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดวิดีโอก่อนตัดต่อไม่สำเร็จ')),
        );
      }
    }
  }

  /// Opens the posting flow pre-filled with the editor's rendered clip so the
  /// edited video reaches TikTok/Shorts/Reels without re-picking from gallery.
  Future<void> _openPostFlow(BurnedSubtitleResult result) async {
    if (!mounted) {
      return;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: AppTheme.screenPadding,
      children: [
        PostDeeCard(
          glowColor: AppTheme.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.movie_creation_outlined,
                  color: AppTheme.accent, size: 40),
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                'ตัดต่อคลิป',
                textAlign: TextAlign.center,
                style:
                    textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppTheme.spaceXs),
              Text(
                'ตัด/แบ่ง ความเร็ว เสียง ข้อความ ฟิลเตอร์ ทำเองได้ '
                'หรือให้ AI ใส่ซับ + ตัดช่วงเงียบให้ในที่เดียว',
                textAlign: TextAlign.center,
                style:
                    textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              PostDeeGradientButton(
                label: 'เลือกคลิปเริ่มตัดต่อ',
                icon: Icons.video_library_outlined,
                onPressed: _pickAndOpen,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.accent, size: 18),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                'หรือเริ่มจากสไตล์สำเร็จรูป',
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          'เลือกสไตล์ แล้วเลือกคลิป เดี๋ยวเราตั้งค่าตัดต่อให้อัตโนมัติ',
          style: textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        for (final style in editStyles)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
            child: _StyleExampleCard(
              style: style,
              onTap: () =>
                  _pickAndOpen(style: EditStyleSelection(style: style)),
            ),
          ),
      ],
    );
  }
}

class _StyleExampleCard extends StatelessWidget {
  const _StyleExampleCard({required this.style, required this.onTap});

  final EditStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.glass,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppTheme.borderSoft),
          ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(style.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            style.name,
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (style.plan.comingSoon)
                          const _MiniBadge(label: 'เร็วๆ นี้')
                        else if (style.plan.requiresAi)
                          const _MiniBadge(label: 'ใช้ AI'),
                        if (style.plan.isCustomPrompt)
                          const _MiniBadge(label: 'Pro'),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(
                      style.editingNote,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppTheme.spaceSm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
