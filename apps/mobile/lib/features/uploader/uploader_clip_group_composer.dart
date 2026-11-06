part of 'uploader_screen.dart';

/// The existing uploader owns the caption page. The durable group journal still
/// owns its immutable media destinations, receipts and submission identities.
class _ClipCaptionComposer {
  _ClipCaptionComposer(
      {required this.group,
      required this.source,
      required this.drafts,
      required this.store,
      required this.groupStore,
      required this.session,
      required VoidCallback onChanged}) {
    for (final item in group.items) {
      final draft = drafts[item.draftId];
      if (draft == null) continue;
      captions[item.draftId] = TextEditingController(text: draft.caption)
        ..addListener(onChanged);
      settings[item.draftId] = draft.platformSettings;
      for (final platform in SocialPlatform.values
          .where((p) => item.platformApiValues.contains(p.apiValue))) {
        platformCaptions['${item.draftId}:${platform.apiValue}'] =
            TextEditingController(
                text: draft.platformSettings.platformCaptions[platform] ?? '')
              ..addListener(onChanged);
      }
      if (!item.usesSharedCaption) custom.add(item.draftId);
    }
  }
  ClipGroupDraft group;
  final PublishDraft source;
  final Map<String, PublishDraft> drafts;
  final PublishDraftStore store;
  final ClipGroupDraftStore groupStore;
  final AuthSessionBinding session;
  final captions = <String, TextEditingController>{};
  final platformCaptions = <String, TextEditingController>{};
  final settings = <String, PlatformPublishSettings>{};
  final custom = <String>{};
  String? selectedDraftId;
  SocialPlatform? selectedPlatform;
  bool get owned => session.isCurrent && session.userId == group.ownerUserId;
  bool get sharedLocked =>
      !owned ||
      group.items.any((item) =>
          item.isAccepted || drafts[item.draftId]?.uploadedMedia != null);
  bool editable(ClipGroupItem item) =>
      owned &&
      !item.isAccepted &&
      drafts[item.draftId] != null &&
      drafts[item.draftId]!.uploadedMedia == null;
  bool get separate => settings.values.any((s) => s.usePlatformCaptions);
  Set<SocialPlatform> targets([String? id]) => {
        for (final item
            in group.items.where((item) => id == null || item.draftId == id))
          for (final p in SocialPlatform.values)
            if (item.platformApiValues.contains(p.apiValue)) p,
      };
  String caption(String id, String shared) =>
      custom.contains(id) ? captions[id]?.text ?? '' : shared;
  String get snapshot => jsonEncode([
        group.id,
        group.revision,
        for (final item in group.items)
          [
            item.draftId,
            custom.contains(item.draftId),
            captions[item.draftId]?.text,
            settings[item.draftId]?.toDraftJson()
          ],
      ]);
  void dispose() {
    for (final c in [...captions.values, ...platformCaptions.values]) {
      c.dispose();
    }
  }
}

extension _UploaderClipCaptionComposer on _UploaderScreenState {
  void _composerInputChanged() {
    if (mounted) {
      _updateClipGroupState(() {
        _successMessage = null;
      });
    }
  }

  Future<void> _adoptClipGroupComposer(String groupId) async {
    if (_isOpeningClipGroup || widget.clipGroupEditor) return;
    final session = PostDeeAuthSessionStore.instance.captureSession();
    final owner = session.userId;
    if (owner == null) return;
    final generation = ++_clipGroupRouteGeneration;
    _isOpeningClipGroup = true;
    try {
      final resolved = await _resolveDraftStore();
      _guardClipGroup(session, owner);
      if (resolved is! ClipGroupDraftStore) {
        throw const ClipGroupDraftException('เปิดพื้นที่เก็บชุดคลิปไม่ได้');
      }
      final store = resolved as PublishDraftStore;
      final groupStore = resolved as ClipGroupDraftStore;
      final group = await groupStore.loadClipGroup(groupId);
      _guardClipGroup(session, owner);
      if (group == null || group.ownerUserId != owner) {
        throw const ClipGroupDraftException(
            'ไม่พบข้อมูลชุดคลิป กรุณาตรวจรายการฉบับร่าง');
      }
      if (group.isComplete) {
        _isOpeningClipGroup = false;
        await _openSavedClipGroup(groupId, reviewOnly: true);
        return;
      }
      final records = await store.listDrafts();
      _guardClipGroup(session, owner);
      final drafts = {
        for (final d in records.where((d) => d.ownerUserId == owner)) d.id: d
      };
      final source = drafts[group.sourceDraftId];
      if (source == null ||
          source.uploadedMedia != null ||
          (source.clipGroupId != null && source.clipGroupId != group.id)) {
        throw const ClipGroupDraftException(
            'เปิดคลิปต้นฉบับไม่ได้ ข้อความเดิมยังอยู่ กรุณาเปิดชุดคลิปใหม่');
      }
      final sourceFile = File(source.videoPath);
      if (!sourceFile.existsSync() || sourceFile.lengthSync() <= 0) {
        throw const ClipGroupDraftException(
            'ไม่พบวิดีโอของฉบับร่างนี้ในเครื่อง');
      }
      _clipCaptionComposer?.dispose();
      _clipCaptionComposer = null;
      await _restoreDraft(source);
      _guardClipGroup(session, owner);
      if (_activeDraftId != source.id ||
          _localFilePathController.text != source.videoPath) {
        throw const ClipGroupDraftException(
            'เปิดคลิปต้นฉบับไม่ได้ ข้อความเดิมยังอยู่ กรุณาเปิดชุดคลิปใหม่');
      }
      final composer = _ClipCaptionComposer(
          group: group,
          source: source,
          drafts: drafts,
          store: store,
          groupStore: groupStore,
          session: session,
          onChanged: _composerInputChanged);
      _updateClipGroupState(() {
        _clipCaptionComposer = composer;
        _captionController.text = group.sharedCaption;
        _aiGuidanceController.text =
            group.captionContext?.aiGuidance ?? source.aiGuidance;
        _captionLanguage = readCaptionOutputLanguage(
            group.captionContext?.captionLanguage ?? source.captionLanguage);
        _platformSettings =
            _platformSettings.copyWith(usePlatformCaptions: false);
        _clipGroupRecords = {..._clipGroupRecords, group.id: group};
        _currentStep = 1;
        _errorMessage = null;
        _successMessage = null;
        _savedFormSnapshot = _formSnapshot;
      });
      if (_formScrollController.hasClients) _formScrollController.jumpTo(0);
    } catch (error) {
      if (mounted && session.isCurrent) {
        _updateClipGroupState(() {
          _errorMessage = clipGroupErrorText(context, error);
        });
      }
    } finally {
      if (generation == _clipGroupRouteGeneration) _isOpeningClipGroup = false;
    }
  }

  Future<bool> _validateComposerCaptionContext(
      bool Function() stillCurrent) async {
    final c = _clipCaptionComposer;
    if (c == null) return true;
    try {
      _guardClipGroup(c.session, c.group.ownerUserId);
      if (!stillCurrent() || c.sharedLocked) return false;
      final group = await c.groupStore.loadClipGroup(c.group.id);
      final source = await c.store.loadDraft(c.source.id);
      _guardClipGroup(c.session, c.group.ownerUserId);
      if (!identical(c, _clipCaptionComposer) ||
          !stillCurrent() ||
          group == null ||
          group.revision != c.group.revision ||
          source == null ||
          source.uploadedMedia != null ||
          source.videoPath != c.source.videoPath ||
          source.mediaContentFingerprint != c.source.mediaContentFingerprint ||
          source.submissionRequestId != c.source.submissionRequestId ||
          _activeDraftId != c.source.id ||
          _localFilePathController.text != c.source.videoPath ||
          !File(c.source.videoPath).existsSync()) {
        return false;
      }
      for (final item in group.items) {
        final draft = await c.store.loadDraft(item.draftId);
        _guardClipGroup(c.session, c.group.ownerUserId);
        if (item.isAccepted ||
            draft == null ||
            draft.uploadedMedia != null ||
            draft.clipGroupId != group.id ||
            draft.isClipGroupSource) {
          return false;
        }
      }
      return identical(c, _clipCaptionComposer) && stillCurrent();
    } catch (_) {
      return false;
    }
  }

  Future<PublishDraft?> _persistCaptionComposer(
      {required bool showSavedMessage}) async {
    final c = _clipCaptionComposer;
    if (c == null || _isSavingDraft || _isGeneratingCaption || _isSubmitting) {
      return null;
    }
    _updateClipGroupState(() {
      _isSavingDraft = true;
      _errorMessage = null;
    });
    try {
      _guardClipGroup(c.session, c.group.ownerUserId);
      final proposed = c.group.copyWith(
          sharedCaption:
              c.sharedLocked ? c.group.sharedCaption : _captionController.text,
          captionContext: c.sharedLocked
              ? c.group.captionContext
              : ClipGroupCaptionContext(
                  aiGuidance: _aiGuidanceController.text,
                  captionLanguage: _captionLanguage),
          items: [
            for (final item in c.group.items)
              c.editable(item)
                  ? item.copyWith(
                      usesSharedCaption: !c.custom.contains(item.draftId))
                  : item
          ]);
      c.group = await _persistClipGroupEdits(
          c.store, c.groupStore, proposed, c.session);
      for (final item in c.group.items.where(c.editable)) {
        final draft = await c.store.loadDraft(item.draftId);
        _guardClipGroup(c.session, c.group.ownerUserId);
        if (draft == null || draft.uploadedMedia != null) {
          throw const ClipGroupDraftException(
              'คลิปนี้เคยเริ่มส่งแล้ว กรุณาตรวจรายการเดิมก่อนแก้ไข');
        }
        final caption = c.caption(item.draftId, c.group.sharedCaption);
        final settings = c.settings[item.draftId] ?? draft.platformSettings;
        if (caption == draft.caption &&
            jsonEncode(settings.toDraftJson()) ==
                jsonEncode(draft.platformSettings.toDraftJson())) {
          c.drafts[item.draftId] = draft;
          continue;
        }
        c.drafts[item.draftId] = await c.store.saveDraft(
            clipGroupMemberSaveRequest(draft,
                caption: caption,
                platformSettings: settings,
                now: widget.now()));
        _guardClipGroup(c.session, c.group.ownerUserId);
      }
      if (!mounted || !identical(c, _clipCaptionComposer)) return null;
      _updateClipGroupState(() {
        _clipGroupRecords = {..._clipGroupRecords, c.group.id: c.group};
        _savedFormSnapshot = _formSnapshot;
        _successMessage = showSavedMessage
            ? 'บันทึกร่างในเครื่องแล้ว · ยังไม่อัปโหลด ไม่โพสต์ และไม่ใช้โควตา'
            : null;
      });
      await _loadDrafts();
      if (!mounted || !c.owned || !identical(c, _clipCaptionComposer)) {
        return null;
      }
      return c.source;
    } catch (error) {
      if (mounted && c.owned && identical(c, _clipCaptionComposer)) {
        final saved = await c.groupStore.loadClipGroup(c.group.id);
        final drafts = await c.store.listDrafts();
        if (saved != null && c.owned && identical(c, _clipCaptionComposer)) {
          c.group = saved;
          c.drafts
            ..clear()
            ..addEntries(drafts
                .where((d) => d.ownerUserId == c.group.ownerUserId)
                .map((d) => MapEntry(d.id, d)));
        }
        if (mounted) {
          _updateClipGroupState(
              () => _errorMessage = clipGroupErrorText(context, error));
        }
      }
      return null;
    } finally {
      if (mounted) {
        _updateClipGroupState(() => _isSavingDraft = false);
      }
    }
  }

  Future<void> _composerNext() async {
    final c = _clipCaptionComposer;
    if (c == null || _formBusy || _isGeneratingCaption) return;
    if (await _persistCaptionComposer(showSavedMessage: false) == null ||
        !mounted ||
        !c.owned ||
        !identical(c, _clipCaptionComposer)) {
      return;
    }
    if (_currentStep == 1) {
      _updateClipGroupState(() {
        _currentStep = 2;
        _errorMessage = null;
      });
      if (_formScrollController.hasClients) _formScrollController.jumpTo(0);
    } else {
      await _openSavedClipGroup(c.group.id, reviewOnly: true);
    }
  }

  Widget _buildComposerCaption(BuildContext context) {
    final c = _clipCaptionComposer!;
    if (!c.owned) {
      return PostDeeNotice(
          message: uploaderText(
              context,
              'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่',
              'Your account changed. Reopen this clip set.'));
    }
    final selected = c.selectedDraftId;
    final item = c.group.items.where((i) => i.draftId == selected).firstOrNull;
    final editable = item == null ? !c.sharedLocked : c.editable(item);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.video_library_outlined,
            color: AppTheme.accent, size: 32),
        const SizedBox(width: AppTheme.spaceMd),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              selected == null
                  ? c.group.title
                  : c.drafts[selected]?.videoName ?? c.group.title,
              style: Theme.of(context).textTheme.titleSmall),
          if (selected == null) _buildVideoMetadata(),
          TextButton.icon(
              onPressed: _formBusy
                  ? null
                  : () async {
                      final d =
                          selected == null ? c.source : c.drafts[selected];
                      if (d == null) return;
                      await Navigator.of(context).push<void>(MaterialPageRoute(
                          builder: (_) => PostVideoPreviewScreen(
                              videoFile: File(d.videoPath),
                              videoName: d.videoName)));
                    },
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const CaptionText('ดูคลิป')),
        ])),
      ]),
      const SizedBox(height: AppTheme.spaceMd),
      ClipGroupCaptionSelector(
          group: c.group,
          draftsById: c.drafts,
          sourceDurationSeconds: _videoDurationSeconds,
          selectedDraftId: selected,
          enabled: !_formBusy && !_isGeneratingCaption && !_isChoosingCaption,
          onSelected: (id) {
            FocusManager.instance.primaryFocus?.unfocus();
            _updateClipGroupState(() => c.selectedDraftId = id);
          }),
      const SizedBox(height: AppTheme.spaceMd),
      if (selected == null)
        AbsorbPointer(absorbing: !editable, child: _buildCaptionCard(context))
      else ...[
        _composerCaptionHeading(
          context,
          title: Text(
              uploaderText(context, 'แคปชันคลิปนี้', 'Caption for this clip'),
              style: Theme.of(context).textTheme.titleSmall),
          action: TextButton(
              key: ValueKey('clip-group-caption-custom-$selected'),
              onPressed: !editable || _formBusy
                  ? null
                  : () {
                      _updateClipGroupState(() {
                        if (c.custom.contains(selected)) {
                          c.custom.remove(selected);
                        } else {
                          c.captions[selected]!.text = _captionController.text;
                          c.custom.add(selected);
                        }
                      });
                    },
              child: Text(c.custom.contains(selected)
                  ? uploaderText(context, 'ใช้แคปชันหลัก', 'Use shared caption')
                  : uploaderText(
                      context, 'แก้เฉพาะคลิปนี้', 'Edit this clip'))),
        ),
        Text(
            uploaderText(
                context,
                c.custom.contains(selected)
                    ? 'ใช้เฉพาะคลิปนี้'
                    : 'คลิปนี้ใช้แคปชันหลักอยู่',
                c.custom.contains(selected)
                    ? 'Only used for this clip'
                    : 'This clip follows the shared caption'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppTheme.spaceSm),
        TextField(
            key: const ValueKey('uploader-caption-field'),
            controller: c.custom.contains(selected)
                ? c.captions[selected]
                : _captionController,
            readOnly: !editable || !c.custom.contains(selected) || _formBusy,
            minLines: 5,
            maxLines: 8,
            decoration: InputDecoration(
                labelText: localizeCaptionMessage(context, 'แคปชั่น'))),
        const SizedBox(height: AppTheme.spaceMd),
        _buildComposerPlatformCaptions(context),
        TextButton.icon(
            onPressed: _formBusy
                ? null
                : () => _updateClipGroupState(() => c.selectedDraftId = null),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(uploaderText(
                context, 'กลับไปแคปชันหลัก / AI', 'Shared caption / AI'))),
      ],
    ]);
  }

  Widget _buildComposerPlatformCaptions(BuildContext context) {
    final c = _clipCaptionComposer!;
    final targets = c.targets(c.selectedDraftId).toList();
    if (targets.isEmpty) return const SizedBox.shrink();
    if (!targets.contains(c.selectedPlatform)) {
      c.selectedPlatform = targets.first;
    }
    final platform = c.selectedPlatform!;
    final scopeItems = c.group.items
        .where(
            (i) => c.selectedDraftId == null || i.draftId == c.selectedDraftId)
        .toList();
    final separate = scopeItems
        .any((i) => c.settings[i.draftId]?.usePlatformCaptions == true);
    final hasDrafts = scopeItems
        .any((i) => c.settings[i.draftId]?.platformCaptions.isNotEmpty == true);
    if (targets.length == 1 && !separate && !hasDrafts) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PostDeeCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile.adaptive(
              key: const ValueKey('clip-group-platform-captions-toggle'),
              title: const CaptionText('ใช้แคปชั่นแยกตามช่องทาง'),
              subtitle: Text(uploaderText(
                  context,
                  separate
                      ? 'แก้เฉพาะคลิปและช่องทางที่ต้องการ'
                      : 'ตอนนี้ใช้แคปชันร่วมกัน',
                  separate
                      ? 'Edit only the clips and channels you choose'
                      : 'Using shared captions')),
              value: separate,
              onChanged: _formBusy || scopeItems.any((i) => !c.editable(i))
                  ? null
                  : (value) => _updateClipGroupState(() {
                        for (final item in scopeItems.where(c.editable)) {
                          c.settings[item.draftId] = c.settings[item.draftId]!
                              .copyWith(usePlatformCaptions: value);
                        }
                      }))),
      if (separate) ...[
        const SizedBox(height: AppTheme.spaceSm),
        if (targets.length > 1)
          DropdownButtonFormField<SocialPlatform>(
              isExpanded: true,
              key: const ValueKey('clip-group-caption-platform'),
              initialValue: platform,
              decoration: InputDecoration(
                  labelText: uploaderText(context, 'ช่องทาง', 'Channel')),
              items: [
                for (final p in targets)
                  DropdownMenuItem(value: p, child: Text(p.label))
              ],
              onChanged: _formBusy
                  ? null
                  : (p) {
                      if (p != null) {
                        _updateClipGroupState(() => c.selectedPlatform = p);
                      }
                    }),
        for (final item in c.group.items.where((i) =>
            (c.selectedDraftId == null || i.draftId == c.selectedDraftId) &&
            i.platformApiValues.contains(platform.apiValue)))
          _buildComposerPlatformField(context, c, item, platform),
      ],
      const SizedBox(height: AppTheme.spaceMd),
    ]);
  }

  Widget _buildComposerPlatformField(BuildContext context,
      _ClipCaptionComposer c, ClipGroupItem item, SocialPlatform platform) {
    final settings = c.settings[item.draftId];
    if (settings == null) return const SizedBox.shrink();
    final custom = settings.platformCaptions.containsKey(platform);
    final controller =
        c.platformCaptions['${item.draftId}:${platform.apiValue}']!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: AppTheme.spaceSm),
      _composerCaptionHeading(
        context,
        title: Text(
            '${clipGroupPartLabel(context, c.group, item)} · ${platform.label}',
            style: Theme.of(context).textTheme.titleSmall),
        action: TextButton(
            key: ValueKey(
                'clip-group-platform-custom-${item.draftId}-${platform.apiValue}'),
            onPressed: !c.editable(item) || _formBusy
                ? null
                : () => _updateClipGroupState(() {
                      final values = Map<SocialPlatform, String>.of(
                          settings.platformCaptions);
                      if (custom) {
                        values.remove(platform);
                      } else {
                        controller.text =
                            c.caption(item.draftId, _captionController.text);
                        values[platform] = controller.text;
                      }
                      c.settings[item.draftId] = settings.copyWith(
                          usePlatformCaptions: true, platformCaptions: values);
                    }),
            child: Text(custom
                ? uploaderText(context, 'ใช้แคปชันร่วม', 'Use shared caption')
                : uploaderText(context, 'แก้ช่องทางนี้', 'Edit this channel'))),
      ),
      TextField(
          key: ValueKey(
              'clip-group-platform-caption-${item.draftId}-${platform.apiValue}'),
          controller: custom
              ? controller
              : c.custom.contains(item.draftId)
                  ? c.captions[item.draftId]
                  : _captionController,
          readOnly: !custom || !c.editable(item) || _formBusy,
          minLines: 2,
          maxLines: 5,
          onChanged: custom
              ? (value) {
                  _updateClipGroupState(() {
                    c.settings[item.draftId] = c.settings[item.draftId]!
                        .copyWith(platformCaptions: {
                      ...c.settings[item.draftId]!.platformCaptions,
                      platform: value
                    });
                  });
                }
              : null,
          decoration: InputDecoration(
              labelText:
                  '${localizeCaptionMessage(context, 'แคปชั่น')} · ${platform.label}')),
    ]);
  }

  Widget _buildComposerChannels(BuildContext context) {
    final c = _clipCaptionComposer!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PostDeeNotice(
          message: uploaderText(
              context,
              'ใช้ช่องทางตามแผนแบ่งคลิปที่เลือกไว้ ตรวจบัญชีและการตั้งค่าของแต่ละคลิปได้ในขั้นตรวจทาน',
              'Channels follow your split plan. Check each clip’s accounts and settings during review.')),
      const SizedBox(height: AppTheme.spaceMd),
      for (final p in c.targets())
        ListTile(
            leading: SocialPlatformLogo(platform: p),
            title: Text(p.label),
            subtitle: Text(c.group.items
                .where((i) => i.platformApiValues.contains(p.apiValue))
                .map((i) => clipGroupPartLabel(context, c.group, i))
                .join(' · ')),
            trailing:
                const Icon(Icons.check_circle_outline, color: AppTheme.accent)),
    ]);
  }

  Widget _composerCaptionHeading(BuildContext context,
          {required Widget title, required Widget action}) =>
      LayoutBuilder(builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                Align(alignment: Alignment.centerRight, child: action),
              ]);
        }
        return Row(children: [Expanded(child: title), action]);
      });
}
