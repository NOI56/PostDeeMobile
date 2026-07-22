import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import 'subtitle_draft_store.dart';
import 'subtitle_preview_overlay.dart';
import 'subtitle_project.dart';
import 'subtitle_studio_controller.dart';

typedef SubtitleVideoPreviewBuilder = Widget Function(
  BuildContext context,
  File sourceFile,
);

class SubtitleStudioScreen extends StatefulWidget {
  const SubtitleStudioScreen({
    super.key,
    required this.sourceFile,
    required this.initialProject,
    required this.draftStore,
    this.videoPreviewBuilder,
  });

  final File sourceFile;
  final SubtitleProject initialProject;
  final SubtitleDraftStore draftStore;
  final SubtitleVideoPreviewBuilder? videoPreviewBuilder;

  @override
  State<SubtitleStudioScreen> createState() => _SubtitleStudioScreenState();
}

class _SubtitleStudioScreenState extends State<SubtitleStudioScreen> {
  late final SubtitleStudioController _controller;
  final TextEditingController _cueTextController = TextEditingController();
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  int _sourcePositionMs = 0;
  int _nextId = 1;
  String? _lastSelectedCueId;

  @override
  void initState() {
    super.initState();
    _controller = SubtitleStudioController(
      initialProject: widget.initialProject,
      draftStore: widget.draftStore,
      now: DateTime.now,
      idGenerator: () =>
          'cue-local-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
    )..addListener(_onStudioChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    if (!mounted) return;
    _syncTextController();
    if (widget.videoPreviewBuilder == null) {
      final video = VideoPlayerController.file(widget.sourceFile);
      _videoController = video;
      video.addListener(_onVideoChanged);
      try {
        await video.initialize();
        final selectedCue = _controller.selectedCue;
        if (selectedCue != null) {
          await video.seekTo(
            Duration(milliseconds: selectedCue.sourceStartMs),
          );
          _sourcePositionMs = selectedCue.sourceStartMs;
        }
        if (mounted) setState(() => _videoReady = true);
      } catch (_) {
        if (mounted) setState(() => _videoReady = false);
      }
    }
  }

  void _onStudioChanged() {
    if (!mounted) return;
    _syncTextController();
    setState(() {});
  }

  void _syncTextController() {
    final cue = _controller.selectedCue;
    final selectedId = cue?.cueId;
    final text = cue == null ? '' : _controller.displayTextFor(cue);
    if (_lastSelectedCueId != selectedId || _cueTextController.text != text) {
      _lastSelectedCueId = selectedId;
      _cueTextController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _onVideoChanged() {
    final video = _videoController;
    if (!mounted || video == null || !video.value.isInitialized) return;
    final nextPosition = video.value.position.inMilliseconds;
    if (nextPosition == _sourcePositionMs) return;
    final selected = _controller.selectedCue;
    if (selected != null &&
        video.value.isPlaying &&
        nextPosition >= selected.sourceEndMs) {
      unawaited(video.pause());
    }
    setState(() => _sourcePositionMs = nextPosition);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onStudioChanged)
      ..dispose();
    _cueTextController.dispose();
    final video = _videoController;
    if (video != null) {
      video.removeListener(_onVideoChanged);
      unawaited(video.dispose());
    }
    super.dispose();
  }

  Future<void> _selectCue(SubtitleCue cue) async {
    _controller.selectCue(cue.cueId);
    final video = _videoController;
    if (video != null && video.value.isInitialized) {
      await video.seekTo(Duration(milliseconds: cue.sourceStartMs));
    }
    if (mounted) setState(() => _sourcePositionMs = cue.sourceStartMs);
  }

  Future<void> _replaySelectedCue() async {
    final cue = _controller.selectedCue;
    final video = _videoController;
    if (cue == null || video == null || !video.value.isInitialized) return;
    await video.seekTo(Duration(milliseconds: cue.sourceStartMs));
    await video.play();
  }

  Future<void> _togglePlayback() async {
    final video = _videoController;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    try {
      final project = await _controller.finish();
      if (mounted) Navigator.of(context).pop(project);
    } on SubtitleProjectValidationException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _close() async {
    final valid = await _controller.flushPendingText();
    if (!valid) {
      _showMessage('กรุณาใส่ข้อความซับก่อนออกจากหน้านี้');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          key: const ValueKey('subtitle-studio-screen'),
          backgroundColor: AppTheme.pitchBlack,
          appBar: AppBar(
            backgroundColor: AppTheme.pitchBlack,
            foregroundColor: Colors.white,
            leading: IconButton(
              onPressed: _close,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'บันทึกฉบับร่างแล้วกลับ',
            ),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'แต่งซับ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  'แก้แล้วเห็นตัวอย่างทันที',
                  style: TextStyle(fontSize: 10, color: Color(0xFF9DB0A6)),
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('subtitle-undo'),
                onPressed: _controller.canUndo ? _controller.undo : null,
                icon: const Icon(Icons.undo_rounded),
                tooltip: 'ย้อนกลับ',
              ),
              IconButton(
                key: const ValueKey('subtitle-redo'),
                onPressed: _controller.canRedo ? _controller.redo : null,
                icon: const Icon(Icons.redo_rounded),
                tooltip: 'ทำซ้ำ',
              ),
            ],
          ),
          body: !_controller.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildPreview(),
                    if (_controller.validationMessage != null)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFF422006),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        child: Text(
                          _controller.validationMessage!,
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const TabBar(
                      indicatorColor: AppTheme.accent,
                      labelColor: AppTheme.accent,
                      unselectedLabelColor: Color(0xFF91A399),
                      tabs: [
                        Tab(
                          key: ValueKey('subtitle-text-tab'),
                          icon: Icon(Icons.subtitles_outlined, size: 19),
                          text: 'ข้อความและเวลา',
                        ),
                        Tab(
                          key: ValueKey('subtitle-style-tab'),
                          icon: Icon(Icons.palette_outlined, size: 19),
                          text: 'รูปแบบซับ',
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildTextEditor(),
                          _buildStyleEditor(),
                        ],
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: ElevatedButton.icon(
                key: const ValueKey('subtitle-finish'),
                onPressed: _finish,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: AppTheme.accent,
                  foregroundColor: const Color(0xFF03251A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  _controller.isSaving
                      ? 'กำลังบันทึก...'
                      : 'สร้างวิดีโอพร้อมซับ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final activeCue = _controller.cueAt(_sourcePositionMs);
    final previewCue = activeCue ?? _controller.selectedCue;
    final previewText =
        previewCue == null ? '' : _controller.displayTextFor(previewCue);
    final video = _videoController;
    final isPlaying = video?.value.isPlaying ?? false;

    return Container(
      color: const Color(0xFF08110E),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                height: 248,
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.videoPreviewBuilder case final builder?)
                          builder(context, widget.sourceFile)
                        else if (_videoReady && video != null)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: video.value.size.width,
                              height: video.value.size.height,
                              child: VideoPlayer(video),
                            ),
                          )
                        else
                          const ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: Color(0xFF6C7D74),
                              ),
                            ),
                          ),
                        SubtitlePreviewOverlay(
                          text: previewText,
                          style: _controller.project.defaultStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  key: const ValueKey('subtitle-playback'),
                  onPressed: video == null ? null : _togglePlayback,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatTime(_sourcePositionMs)} / '
                  '${_formatTime(_controller.project.sourceDurationMs)}',
                  style: const TextStyle(
                    color: Color(0xFFB8C6BF),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 7),
                OutlinedButton.icon(
                  onPressed: _replaySelectedCue,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label:
                      const Text('ฟังประโยค', style: TextStyle(fontSize: 10)),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_controller.project.cues.length} ประโยค',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextEditor() {
    final selected = _controller.selectedCue;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        TextField(
          key: const ValueKey('subtitle-cue-text-field'),
          controller: _cueTextController,
          enabled: selected != null,
          minLines: 2,
          maxLines: 3,
          onChanged: _controller.stageSelectedCueText,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          decoration: _inputDecoration('ข้อความซับที่เลือก'),
        ),
        const SizedBox(height: 10),
        if (selected != null) ...[
          Row(
            children: [
              Expanded(
                  child: _timingControl('เริ่ม', selected.sourceStartMs, true)),
              const SizedBox(width: 8),
              Expanded(
                  child: _timingControl('จบ', selected.sourceEndMs, false)),
            ],
          ),
          const SizedBox(height: 9),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _actionButton(
              key: 'subtitle-add-cue',
              icon: Icons.add_rounded,
              label: 'เพิ่ม',
              onTap: _controller.addCueAfterSelected,
            ),
            _actionButton(
              key: 'subtitle-split-cue',
              icon: Icons.call_split_rounded,
              label: 'แยก',
              onTap: _controller.splitSelectedCue,
            ),
            _actionButton(
              key: 'subtitle-merge-cue',
              icon: Icons.merge_rounded,
              label: 'รวมถัดไป',
              onTap: _controller.mergeSelectedWithNext,
            ),
            _actionButton(
              key: 'subtitle-delete-cue',
              icon: Icons.delete_outline_rounded,
              label: 'ลบ',
              onTap: _controller.deleteSelectedCue,
              destructive: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'ประโยคทั้งหมด',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        for (var index = 0; index < _controller.project.cues.length; index++)
          _cueCard(index, _controller.project.cues[index]),
      ],
    );
  }

  Widget _timingControl(String label, int valueMs, bool isStart) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF13211B),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF29443A)),
      ),
      child: Column(
        children: [
          Text('$label ${_formatTime(valueMs)}',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => isStart
                    ? _controller.adjustSelectedTiming(startDeltaMs: -100)
                    : _controller.adjustSelectedTiming(endDeltaMs: -100),
                icon: const Icon(Icons.remove, size: 16),
              ),
              const Text('0.1 วิ',
                  style: TextStyle(color: Color(0xFF91A399), fontSize: 9)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => isStart
                    ? _controller.adjustSelectedTiming(startDeltaMs: 100)
                    : _controller.adjustSelectedTiming(endDeltaMs: 100),
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String key,
    required IconData icon,
    required String label,
    required bool Function() onTap,
    bool destructive = false,
  }) {
    return OutlinedButton.icon(
      key: ValueKey(key),
      onPressed: () => onTap(),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            destructive ? const Color(0xFFFF8A80) : const Color(0xFFD7E4DD),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _cueCard(int index, SubtitleCue cue) {
    final selected = cue.cueId == _controller.selectedCueId;
    final removed = _controller.cueIsRemovedByCut(cue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? const Color(0xFF123B2E) : const Color(0xFF121B17),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _selectCue(cue),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor:
                      selected ? AppTheme.accent : const Color(0xFF26372F),
                  foregroundColor: selected
                      ? const Color(0xFF042419)
                      : const Color(0xFFB1C0B8),
                  child: Text('${index + 1}',
                      style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _controller.displayTextFor(cue),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              removed ? const Color(0xFF78877F) : Colors.white,
                          fontSize: 12,
                          decoration:
                              removed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatTime(cue.sourceStartMs)} – '
                        '${_formatTime(cue.sourceEndMs)}'
                        '${removed ? '  • ถูกตัดออกจากคลิป' : ''}',
                        style: TextStyle(
                          color: removed
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF81938A),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF6E8177), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleEditor() {
    final style = _controller.project.defaultStyle;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _styleHeading('ฟอนต์'),
        Row(
          children: [
            Expanded(
              child: _choiceButton(
                key: 'subtitle-font-prompt',
                label: 'Prompt',
                selected: style.fontId == 'Prompt',
                onTap: () => _setStyle(fontId: 'Prompt'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choiceButton(
                key: 'subtitle-font-anuphan',
                label: 'Anuphan',
                selected: style.fontId == 'Anuphan',
                onTap: () => _setStyle(fontId: 'Anuphan'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _slider(
          label: 'ขนาด ${style.fontSize.round()}',
          value: style.fontSize,
          min: 14,
          max: 42,
          divisions: 28,
          onChanged: (value) => _setStyle(fontSize: value),
        ),
        _styleHeading('สีตัวอักษร'),
        _colorRow(
          selected: style.textColor,
          values: const ['#FFFFFF', '#FFF45C', '#00E5A8', '#FF6B6B'],
          onChanged: (value) => _setStyle(textColor: value),
        ),
        const SizedBox(height: 14),
        _styleHeading('สีขอบ'),
        _colorRow(
          selected: style.outlineColor,
          values: const ['#000000', '#FFFFFF', '#052E21', '#7C2D12'],
          onChanged: (value) => _setStyle(outlineColor: value),
        ),
        _slider(
          label: 'ความหนาขอบ ${style.outlineWidth.toStringAsFixed(1)}',
          value: style.outlineWidth,
          min: 0,
          max: 5,
          divisions: 10,
          onChanged: (value) => _setStyle(outlineWidth: value),
        ),
        _slider(
          label: 'เงา ${style.shadowDepth.toStringAsFixed(1)}',
          value: style.shadowDepth,
          min: 0,
          max: 6,
          divisions: 12,
          onChanged: (value) => _setStyle(shadowDepth: value),
        ),
        _styleHeading('ตำแหน่ง'),
        Row(
          children: [
            for (final entry in const [
              (SubtitleAlignment.top, 'บน', 'subtitle-position-top'),
              (SubtitleAlignment.middle, 'กลาง', 'subtitle-position-middle'),
              (SubtitleAlignment.bottom, 'ล่าง', 'subtitle-position-bottom'),
            ]) ...[
              Expanded(
                child: _choiceButton(
                  key: entry.$3,
                  label: entry.$2,
                  selected: style.alignment == entry.$1,
                  onTap: () => _setStyle(alignment: entry.$1),
                ),
              ),
              if (entry.$1 != SubtitleAlignment.bottom)
                const SizedBox(width: 7),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _styleHeading('จำนวนบรรทัด'),
        Row(
          children: [
            Expanded(
              child: _choiceButton(
                key: 'subtitle-lines-one',
                label: '1 บรรทัด',
                selected: style.maxLines == 1,
                onTap: () => _setStyle(maxLines: 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choiceButton(
                key: 'subtitle-lines-two',
                label: '2 บรรทัด',
                selected: style.maxLines == 2,
                onTap: () => _setStyle(maxLines: 2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _styleHeading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFDCE7E1),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _choiceButton({
    required String key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? const Color(0xFF0F4D39) : const Color(0xFF13211B),
        foregroundColor: selected ? AppTheme.accent : const Color(0xFFC5D2CB),
        side: BorderSide(
          color: selected ? AppTheme.accent : const Color(0xFF30443A),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _colorRow({
    required String selected,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 10,
      children: [
        for (final value in values)
          InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: subtitleColor(value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == value
                      ? AppTheme.accent
                      : const Color(0xFF64766D),
                  width: selected == value ? 4 : 1,
                ),
              ),
              child: selected == value
                  ? Icon(
                      Icons.check_rounded,
                      color: value == '#000000'
                          ? Colors.white
                          : const Color(0xFF052E21),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFFC8D5CE), fontSize: 11)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _setStyle({
    String? fontId,
    double? fontSize,
    String? textColor,
    String? outlineColor,
    double? outlineWidth,
    double? shadowDepth,
    SubtitleAlignment? alignment,
    int? maxLines,
  }) {
    _controller.updateDefaultStyle(
      copySubtitleStyle(
        _controller.project.defaultStyle,
        fontId: fontId,
        fontSize: fontSize,
        textColor: textColor,
        outlineColor: outlineColor,
        outlineWidth: outlineWidth,
        shadowDepth: shadowDepth,
        alignment: alignment,
        maxLines: maxLines,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF91A399)),
        filled: true,
        fillColor: const Color(0xFF13211B),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30443A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
      );

  String _formatTime(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final tenths = (milliseconds % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }
}
