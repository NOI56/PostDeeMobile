import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/caption_language.dart';
import '../../core/theme/app_theme.dart';
import '../shared/postdee_notice.dart';
import 'caption_localizations.dart';

/// The interface locale and the requested caption language are independent.
class CaptionLanguagePicker extends StatefulWidget {
  const CaptionLanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.selectionScope,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  /// An owner/draft/clip identity invalidates a sheet opened for an older form.
  final Object? selectionScope;

  @override
  State<CaptionLanguagePicker> createState() => _CaptionLanguagePickerState();
}

class _CaptionLanguagePickerState extends State<CaptionLanguagePicker> {
  int _selectionVersion = 0;
  bool _isOpen = false;
  ModalRoute<dynamic>? _sheetRoute;

  @override
  void didUpdateWidget(CaptionLanguagePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionScope != widget.selectionScope ||
        oldWidget.value != widget.value ||
        (oldWidget.onChanged != null && widget.onChanged == null)) {
      _selectionVersion++;
      final route = _sheetRoute;
      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isCurrent) route.navigator?.pop();
        });
      }
    }
  }

  Future<void> _chooseLanguage() async {
    if (_isOpen || widget.onChanged == null) return;
    final version = _selectionVersion;
    final initialValue = readCaptionOutputLanguage(widget.value);
    final scope = widget.selectionScope;
    _isOpen = true;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.glass,
      showDragHandle: false,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) {
        _sheetRoute = ModalRoute.of(sheetContext);
        return _CaptionLanguageSheet(value: initialValue);
      },
    );
    _isOpen = false;
    _sheetRoute = null;
    if (!mounted ||
        version != _selectionVersion ||
        scope != widget.selectionScope ||
        widget.onChanged == null ||
        result == null ||
        result == readCaptionOutputLanguage(widget.value)) {
      return;
    }
    widget.onChanged!(result);
  }

  @override
  Widget build(BuildContext context) {
    final selected = captionOutputLanguageDetails(widget.value);
    final label = selected?.nativeName ??
        localizeCaptionMessage(context, 'อัตโนมัติ (ตามคลิป)');
    final enabled = widget.onChanged != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: localizeCaptionMessage(context, 'ภาษาแคปชั่น'),
      value: label,
      excludeSemantics: true,
      onTap: enabled ? _chooseLanguage : null,
      child: InkWell(
        onTap: enabled ? _chooseLanguage : null,
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            enabled: enabled,
            labelText: localizeCaptionMessage(context, 'ภาษาแคปชั่น'),
            helperText: localizeCaptionMessage(context,
                'เลือกภาษาที่ให้ AI เขียนได้ แม้เสียงในคลิปเป็นอีกภาษา'),
            helperMaxLines: 5,
          ),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: AppTheme.spaceSm),
              Icon(Icons.expand_more,
                  color: enabled ? AppTheme.textSecondary : AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptionLanguageSheet extends StatefulWidget {
  const _CaptionLanguageSheet({required this.value});

  final String value;

  @override
  State<_CaptionLanguageSheet> createState() => _CaptionLanguageSheetState();
}

class _CaptionLanguageSheetState extends State<_CaptionLanguageSheet> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _searchContainerKey = GlobalKey();

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final selected = captionOutputLanguageDetails(widget.value);
    final matches = searchCaptionOutputLanguages(_search.text);
    // Keep the current choice easy to find even when it falls far down the list.
    final languages = [
      if (selected != null && _search.text.trim().isEmpty) selected,
      ...matches.where((language) =>
          _search.text.trim().isNotEmpty || language.code != selected?.code),
    ];
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
      child: Row(
        children: [
          Expanded(
            child: CaptionText('เลือกภาษาแคปชั่น',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            key: const ValueKey('caption-language-close'),
            tooltip: localizeCaptionMessage(context, 'ปิด'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
    final searchField = KeyedSubtree(
      key: _searchContainerKey,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Row(
          children: [
            Expanded(
                child: TextField(
              key: const ValueKey('caption-language-search'),
              controller: _search,
              onChanged: (_) => _filter(),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: localizeCaptionMessage(
                    context, 'ค้นหาชื่อภาษาหรือรหัสภาษา'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('caption-language-clear-search'),
                        tooltip:
                            localizeCaptionMessage(context, 'ล้างการค้นหา'),
                        onPressed: () {
                          _search.clear();
                          _filter();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            )),
            if (keyboard > 0)
              IconButton(
                key: const ValueKey('caption-language-close'),
                tooltip: localizeCaptionMessage(context, 'ปิด'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
    final options = <Widget>[
      _languageRow(
        context,
        code: 'auto',
        nativeName: localizeCaptionMessage(context, 'อัตโนมัติ (ตามคลิป)'),
        description:
            localizeCaptionMessage(context, 'ใช้ภาษาตามเสียงหรือเนื้อหาในคลิป'),
      ),
      const Divider(height: AppTheme.spaceLg),
      if (languages.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
          child: PostDeeNotice(
            message: localizeCaptionMessage(
                context, 'ไม่พบภาษาที่ค้นหา ลองชื่อหรือรหัสภาษาอื่น'),
            icon: Icons.search_off,
            color: AppTheme.textSecondary,
          ),
        ),
      for (final language in languages)
        _languageRow(
          context,
          code: language.code,
          nativeName: language.nativeName,
          description:
              '${captionUsesThai(context) ? language.thaiName : language.englishName} · ${language.code}',
        ),
      Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: CaptionText(
          'รายการภาษาสำหรับเขียนแคปชั่นอ้างอิงเอกสาร Gemini ของ Google คุณภาพอาจต่างกันตามภาษาและเนื้อหา',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    ];
    Widget choices(List<Widget> children) => ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
          children: children,
        );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        key: const ValueKey('caption-language-sheet'),
        height: math.max(
            0,
            MediaQuery.sizeOf(context).height * (keyboard > 0 ? 1 : 0.9) -
                keyboard),
        child: LayoutBuilder(builder: (context, constraints) {
          final heading = [if (keyboard == 0) header, searchField];
          // A short window or tall keyboard must be able to scroll the header
          // too. Reparent the same search subtree to preserve focus and input.
          if (constraints.maxHeight < 320) {
            return choices([...heading, ...options]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...heading, Expanded(child: choices(options))],
          );
        }),
      ),
    );
  }

  Widget _languageRow(BuildContext context,
      {required String code,
      required String nativeName,
      required String description}) {
    final isSelected = code == widget.value;
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        key: ValueKey('caption-language-option-$code'),
        onTap: () => Navigator.of(context).pop(code),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceLg, vertical: AppTheme.spaceMd),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nativeName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(description,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: AppTheme.spaceMd),
                const Icon(Icons.check_circle, color: AppTheme.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
