import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_edit_sound_effects.dart';

typedef SoundEffectPreviewCallback = Future<void> Function(
  AiEditSoundEffectDefinition soundEffect,
);

class SoundEffectStudioScreen extends StatefulWidget {
  const SoundEffectStudioScreen({
    super.key,
    required this.durationSeconds,
    this.initialPlacements = const <AiEditSoundEffectPlacement>[],
    this.onPreview,
  }) : assert(
          durationSeconds > 0 && durationSeconds < double.infinity,
          'durationSeconds must be finite and greater than zero.',
        );

  final double durationSeconds;
  final List<AiEditSoundEffectPlacement> initialPlacements;
  final SoundEffectPreviewCallback? onPreview;

  @override
  State<SoundEffectStudioScreen> createState() =>
      _SoundEffectStudioScreenState();
}

class _SoundEffectStudioScreenState extends State<SoundEffectStudioScreen> {
  late final List<_EditableSoundEffectPlacement> _placements;
  var _nextPlacementId = 0;
  var _currentTimeSeconds = 0.0;
  String? _previewingSoundId;

  double get _maximumStartSeconds {
    final safetyGap = math.min(0.001, widget.durationSeconds / 2);
    return widget.durationSeconds - safetyGap;
  }

  bool get _isAtLimit => _placements.length >= maxAiEditSoundEffectsPerVideo;

  @override
  void initState() {
    super.initState();
    final initialPlacements = validateAiEditSoundEffectPlacements(
      widget.initialPlacements,
      outputDurationSeconds: widget.durationSeconds,
    );
    _placements = [
      for (final placement in initialPlacements)
        _EditableSoundEffectPlacement(
          id: _nextPlacementId++,
          placement: placement,
        ),
    ];
  }

  void _setCurrentTime(double value) {
    setState(() {
      _currentTimeSeconds = _normalizeTime(value);
    });
  }

  void _addSoundEffect(AiEditSoundEffectDefinition soundEffect) {
    if (_isAtLimit) {
      return;
    }
    setState(() {
      _placements.add(
        _EditableSoundEffectPlacement(
          id: _nextPlacementId++,
          placement: AiEditSoundEffectPlacement(
            soundId: soundEffect.id,
            startSeconds: _currentTimeSeconds,
          ),
        ),
      );
    });
  }

  void _updatePlacement(
    int id, {
    double? startSeconds,
    double? volume,
  }) {
    final index = _placements.indexWhere((placement) => placement.id == id);
    if (index < 0) {
      return;
    }
    final current = _placements[index];
    setState(() {
      _placements[index] = current.copyWith(
        startSeconds:
            startSeconds == null ? null : _normalizeTime(startSeconds),
        volume: volume == null ? null : math.max(0.01, volume.clamp(0, 1)),
      );
    });
  }

  void _removePlacement(int id) {
    setState(() {
      _placements.removeWhere((placement) => placement.id == id);
    });
  }

  Future<void> _preview(AiEditSoundEffectDefinition soundEffect) async {
    final callback = widget.onPreview;
    if (callback == null || _previewingSoundId != null) {
      return;
    }
    setState(() {
      _previewingSoundId = soundEffect.id;
    });
    try {
      await callback(soundEffect);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('ฟังเสียง ${soundEffect.titleTh} ไม่สำเร็จ กรุณาลองใหม่'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _previewingSoundId = null;
        });
      }
    }
  }

  void _finish() {
    try {
      final result = validateAiEditSoundEffectPlacements(
        _placements.map((editable) => editable.placement),
        outputDurationSeconds: widget.durationSeconds,
      );
      Navigator.of(context).pop<List<AiEditSoundEffectPlacement>>(result);
    } on AiEditSoundEffectValidationException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  void _cancel() {
    Navigator.of(context).pop<List<AiEditSoundEffectPlacement>>();
  }

  double _normalizeTime(double value) {
    final clamped = value.clamp(0, _maximumStartSeconds);
    final rounded = (clamped * 10).roundToDouble() / 10;
    return math.min(rounded, _maximumStartSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      key: const ValueKey('sound-effect-studio-screen'),
      appBar: AppBar(
        title: const Text('ใส่เอฟเฟกต์เสียง'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'เลือกจังหวะบนคลิป แล้วเพิ่มเสียงที่เหมาะกับภาพ',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _buildCurrentTimeCard(context),
            if (_isAtLimit) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('sound-effect-limit-warning'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ใส่เอฟเฟกต์เสียงได้ไม่เกิน 8 จุดต่อคลิป',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'คลังเสียง PostDee',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'เสียงชุดนี้สร้างโดย PostDee สำหรับใช้กับคลิปของคุณ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final soundEffect in postDeeSoundEffectCatalog) ...[
              _buildCatalogCard(context, soundEffect),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            Text(
              'เสียงที่ใส่แล้ว (${_placements.length}/$maxAiEditSoundEffectsPerVideo)',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (_placements.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  'ยังไม่ได้ใส่เอฟเฟกต์เสียง',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final placement in _placements) ...[
                _buildPlacementCard(context, placement),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                key: const ValueKey('sound-effect-cancel'),
                button: true,
                label: 'ยกเลิกการแก้เอฟเฟกต์เสียง',
                onTap: _cancel,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _cancel,
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                key: const ValueKey('sound-effect-finish'),
                button: true,
                label: 'บันทึกเอฟเฟกต์เสียง',
                onTap: _finish,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _finish,
                      child: const Text('เสร็จ'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTimeCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final valueLabel = 'เริ่มที่ ${_formatSeconds(_currentTimeSeconds)} วินาที';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'จังหวะที่จะเพิ่ม',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              valueLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Semantics(
              key: const ValueKey('sound-effect-current-time'),
              label: 'ตำแหน่งสำหรับเพิ่มเอฟเฟกต์',
              value: valueLabel,
              increasedValue: _currentTimeSeconds < _maximumStartSeconds
                  ? 'เริ่มที่ ${_formatSeconds(_normalizeTime(_currentTimeSeconds + 0.1))} วินาที'
                  : null,
              decreasedValue: _currentTimeSeconds > 0
                  ? 'เริ่มที่ ${_formatSeconds(_normalizeTime(_currentTimeSeconds - 0.1))} วินาที'
                  : null,
              onIncrease: _currentTimeSeconds < _maximumStartSeconds
                  ? () => _setCurrentTime(_currentTimeSeconds + 0.1)
                  : null,
              onDecrease: _currentTimeSeconds > 0
                  ? () => _setCurrentTime(_currentTimeSeconds - 0.1)
                  : null,
              child: ExcludeSemantics(
                child: Slider(
                  value: _currentTimeSeconds,
                  min: 0,
                  max: _sliderMaximum,
                  divisions: _sliderDivisions,
                  onChanged: _maximumStartSeconds > 0 ? _setCurrentTime : null,
                  semanticFormatterCallback: (value) =>
                      'เริ่มที่ ${_formatSeconds(_normalizeTime(value))} วินาที',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogCard(
    BuildContext context,
    AiEditSoundEffectDefinition soundEffect,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canPreview = widget.onPreview != null && _previewingSoundId == null;
    final isPreviewing = _previewingSoundId == soundEffect.id;
    final addLabel =
        'เพิ่มเสียง ${soundEffect.titleTh} ที่ ${_formatSeconds(_currentTimeSeconds)} วินาที';

    return Card(
      key: ValueKey('sound-effect-catalog-${soundEffect.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _categoryIcon(soundEffect.category),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        soundEffect.titleTh,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_categoryLabel(soundEffect.category)} · '
                        '${soundEffect.durationSeconds.toStringAsFixed(1)} วินาที',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  key: ValueKey('sound-effect-preview-${soundEffect.id}'),
                  button: true,
                  enabled: canPreview,
                  label: isPreviewing
                      ? 'กำลังฟังเสียง ${soundEffect.titleTh}'
                      : 'ฟังเสียง ${soundEffect.titleTh}',
                  onTap: canPreview ? () => _preview(soundEffect) : null,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        tooltip: 'ฟังเสียง ${soundEffect.titleTh}',
                        onPressed:
                            canPreview ? () => _preview(soundEffect) : null,
                        icon: isPreviewing
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  key: ValueKey('sound-effect-add-${soundEffect.id}'),
                  button: true,
                  enabled: !_isAtLimit,
                  label: addLabel,
                  onTap: _isAtLimit ? null : () => _addSoundEffect(soundEffect),
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.tonalIcon(
                        onPressed: _isAtLimit
                            ? null
                            : () => _addSoundEffect(soundEffect),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('เพิ่ม'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacementCard(
    BuildContext context,
    _EditableSoundEffectPlacement editable,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final placement = editable.placement;
    final soundEffect = findPostDeeSoundEffect(placement.soundId)!;
    final timeLabel =
        'เริ่มที่ ${_formatSeconds(placement.startSeconds)} วินาที';
    final volumePercent = (placement.volume * 100).round();

    return Semantics(
      key: ValueKey('sound-effect-placement-${editable.id}'),
      container: true,
      label: 'เอฟเฟกต์เสียง ${soundEffect.titleTh}',
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      soundEffect.titleTh,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    key: ValueKey('sound-effect-remove-${editable.id}'),
                    button: true,
                    label: 'ลบเสียง ${soundEffect.titleTh}',
                    onTap: () => _removePlacement(editable.id),
                    child: ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          tooltip: 'ลบเสียง ${soundEffect.titleTh}',
                          onPressed: () => _removePlacement(editable.id),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _TimeStepButton(
                    key: ValueKey(
                      'sound-effect-time-decrement-${editable.id}',
                    ),
                    semanticsLabel:
                        'ลดเวลาเริ่มเสียง ${soundEffect.titleTh} 0.1 วินาที',
                    icon: Icons.remove_rounded,
                    onPressed: placement.startSeconds > 0
                        ? () => _updatePlacement(
                              editable.id,
                              startSeconds: placement.startSeconds - 0.1,
                            )
                        : null,
                  ),
                  Expanded(
                    child: Semantics(
                      key: ValueKey('sound-effect-time-${editable.id}'),
                      label: 'เวลาเริ่มเสียง ${soundEffect.titleTh}',
                      value: timeLabel,
                      increasedValue: placement.startSeconds <
                              _maximumStartSeconds
                          ? 'เริ่มที่ ${_formatSeconds(_normalizeTime(placement.startSeconds + 0.1))} วินาที'
                          : null,
                      decreasedValue: placement.startSeconds > 0
                          ? 'เริ่มที่ ${_formatSeconds(_normalizeTime(placement.startSeconds - 0.1))} วินาที'
                          : null,
                      onIncrease: placement.startSeconds < _maximumStartSeconds
                          ? () => _updatePlacement(
                                editable.id,
                                startSeconds: placement.startSeconds + 0.1,
                              )
                          : null,
                      onDecrease: placement.startSeconds > 0
                          ? () => _updatePlacement(
                                editable.id,
                                startSeconds: placement.startSeconds - 0.1,
                              )
                          : null,
                      child: ExcludeSemantics(
                        child: Slider(
                          value: placement.startSeconds,
                          min: 0,
                          max: _sliderMaximum,
                          divisions: _sliderDivisions,
                          onChanged: _maximumStartSeconds > 0
                              ? (value) => _updatePlacement(
                                    editable.id,
                                    startSeconds: value,
                                  )
                              : null,
                          semanticFormatterCallback: (value) =>
                              'เริ่มที่ ${_formatSeconds(_normalizeTime(value))} วินาที',
                        ),
                      ),
                    ),
                  ),
                  _TimeStepButton(
                    key: ValueKey(
                      'sound-effect-time-increment-${editable.id}',
                    ),
                    semanticsLabel:
                        'เพิ่มเวลาเริ่มเสียง ${soundEffect.titleTh} 0.1 วินาที',
                    icon: Icons.add_rounded,
                    onPressed: placement.startSeconds < _maximumStartSeconds
                        ? () => _updatePlacement(
                              editable.id,
                              startSeconds: placement.startSeconds + 0.1,
                            )
                        : null,
                  ),
                ],
              ),
              Center(
                child: Text(
                  timeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      key: ValueKey('sound-effect-volume-${editable.id}'),
                      label: 'ระดับเสียง ${soundEffect.titleTh}',
                      value: '$volumePercent เปอร์เซ็นต์',
                      increasedValue: placement.volume < 1
                          ? '${math.min(100, volumePercent + 5)} เปอร์เซ็นต์'
                          : null,
                      decreasedValue: placement.volume > 0.01
                          ? '${math.max(1, volumePercent - 5)} เปอร์เซ็นต์'
                          : null,
                      onIncrease: placement.volume < 1
                          ? () => _updatePlacement(
                                editable.id,
                                volume: placement.volume + 0.05,
                              )
                          : null,
                      onDecrease: placement.volume > 0.01
                          ? () => _updatePlacement(
                                editable.id,
                                volume: placement.volume - 0.05,
                              )
                          : null,
                      child: ExcludeSemantics(
                        child: Slider(
                          value: placement.volume,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          onChanged: (value) => _updatePlacement(
                            editable.id,
                            volume: value,
                          ),
                          semanticFormatterCallback: (value) =>
                              '${(value * 100).round()} เปอร์เซ็นต์',
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '$volumePercent%',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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

  double get _sliderMaximum => widget.durationSeconds;

  int get _sliderDivisions => math.max(1, (widget.durationSeconds * 10).ceil());
}

class _EditableSoundEffectPlacement {
  const _EditableSoundEffectPlacement({
    required this.id,
    required this.placement,
  });

  final int id;
  final AiEditSoundEffectPlacement placement;

  _EditableSoundEffectPlacement copyWith({
    double? startSeconds,
    double? volume,
  }) {
    return _EditableSoundEffectPlacement(
      id: id,
      placement: AiEditSoundEffectPlacement(
        soundId: placement.soundId,
        startSeconds: startSeconds ?? placement.startSeconds,
        volume: volume ?? placement.volume,
      ),
    );
  }
}

class _TimeStepButton extends StatelessWidget {
  const _TimeStepButton({
    super.key,
    required this.semanticsLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticsLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 48,
          child: IconButton(
            tooltip: semanticsLabel,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

String _formatSeconds(double seconds) => seconds.toStringAsFixed(1);

IconData _categoryIcon(AiEditSoundEffectCategory category) {
  return switch (category) {
    AiEditSoundEffectCategory.accent => Icons.auto_awesome_rounded,
    AiEditSoundEffectCategory.transition => Icons.air_rounded,
    AiEditSoundEffectCategory.success => Icons.check_circle_outline_rounded,
    AiEditSoundEffectCategory.attention => Icons.notifications_none_rounded,
  };
}

String _categoryLabel(AiEditSoundEffectCategory category) {
  return switch (category) {
    AiEditSoundEffectCategory.accent => 'เน้นจังหวะ',
    AiEditSoundEffectCategory.transition => 'เปลี่ยนฉาก',
    AiEditSoundEffectCategory.success => 'สำเร็จ',
    AiEditSoundEffectCategory.attention => 'เรียกความสนใจ',
  };
}
