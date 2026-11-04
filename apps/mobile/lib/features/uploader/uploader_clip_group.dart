part of 'uploader_screen.dart';

class _ClipGroupRuntimeReview {
  _ClipGroupRuntimeReview({
    required this.form,
    required this.settings,
    required this.bindings,
    required this.tikTokBinding,
    required this.tikTokIntent,
    required this.tikTokOptions,
  });
  final String form;
  final PlatformPublishSettings settings;
  final Map<SocialPlatform, String> bindings;
  final String tikTokBinding;
  final String? tikTokIntent;
  final TikTokPublishingOptionsResult? tikTokOptions;
}

extension _UploaderClipGroups on _UploaderScreenState {
  void _guardClipGroup(AuthSessionBinding session, String owner) {
    if (!mounted || !session.isCurrent || session.userId != owner ||
        PostDeeAuthSessionStore.instance.session.stableUserId != owner ||
        !PostDeeAuthSessionStore.instance.session.isSignedIn) {
      throw const ClipGroupDraftException(
          'บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดชุดคลิปใหม่');
    }
  }

  Future<void> _openSavedClipGroup(String groupId) async {
    if (_isOpeningClipGroup || widget.clipGroupEditor) return;
    final session = PostDeeAuthSessionStore.instance.captureSession();
    final owner = session.userId;
    if (owner == null) return;
    final navigator = Navigator.of(context);
    final openingGeneration = ++_clipGroupRouteGeneration;
    _isOpeningClipGroup = true;
    try {
      final resolved = await _resolveDraftStore();
      _guardClipGroup(session, owner);
      if (resolved == null || resolved is! ClipGroupDraftStore) {
        throw const ClipGroupDraftException('เปิดพื้นที่เก็บชุดคลิปไม่ได้');
      }
      final PublishDraftStore store = resolved;
      final groupStore = resolved as ClipGroupDraftStore;
      var working = await groupStore.loadClipGroup(groupId);
      _guardClipGroup(session, owner);
      if (working == null || working.ownerUserId != owner) {
        throw const ClipGroupDraftException(
            'ไม่พบข้อมูลชุดคลิป กรุณาตรวจรายการฉบับร่าง');
      }
      final drafts = <String, PublishDraft>{};
      Future<ClipGroupDraft> reload() async {
        _guardClipGroup(session, owner);
        final current = await groupStore.loadClipGroup(groupId);
        _guardClipGroup(session, owner);
        if (current == null || current.ownerUserId != owner) {
          throw const ClipGroupDraftException('เปิดชุดคลิปนี้ไม่ได้');
        }
        final saved = await store.listDrafts();
        _guardClipGroup(session, owner);
        drafts
          ..clear()
          ..addEntries(saved.where((d) => d.ownerUserId == owner)
              .map((d) => MapEntry(d.id, d)));
        working = current;
        return current;
      }
      await reload();
      await _loadConnections();
      _guardClipGroup(session, owner);
      final reviewBindings = {
        for (final p in working!.items.expand((item) => item.platformApiValues)
            .map(_platformFromApiValue).whereType<SocialPlatform>())
          p: _connectionBinding(p),
      };
      Future<ClipGroupDraft> saveGroup(ClipGroupDraft proposed) async {
        final saved = await _persistClipGroupEdits(
            store, groupStore, proposed, session);
        working = saved;
        await reload();
        return working!;
      }
      Future<PublishDraft> saveCaption(PublishDraft draft, String caption) async {
        _guardClipGroup(session, owner);
        final current = working!;
        final item = current.items
            .where((item) => item.draftId == draft.id).firstOrNull;
        final actual = await store.loadDraft(draft.id);
        _guardClipGroup(session, owner);
        if (item == null || item.isAccepted || actual == null ||
            actual.uploadedMedia != null || actual.ownerUserId != owner) {
          throw const ClipGroupDraftException(
              'คลิปนี้เคยเริ่มส่งแล้ว กรุณาตรวจรายการเดิมก่อนแก้ไข');
        }
        working = await _persistClipGroupEdits(
            store, groupStore,
            current.copyWith(items: [
              for (final member in current.items)
                member.draftId == draft.id
                    ? member.copyWith(usesSharedCaption: false) : member,
            ]), session);
        _guardClipGroup(session, owner);
        final saved = await store.saveDraft(clipGroupMemberSaveRequest(actual,
            caption: caption, captionNeedsReview: false, now: widget.now()));
        _guardClipGroup(session, owner);
        drafts[saved.id] = saved;
        return saved;
      }
      Future<void> beforeMemberSave(String id, String caption) async {
        _guardClipGroup(session, owner);
        final current = await groupStore.loadClipGroup(groupId);
        _guardClipGroup(session, owner);
        if (current == null || current.revision != working!.revision) {
          throw const ClipGroupDraftConflictException();
        }
        final member = current.items.where((item) => item.draftId == id)
            .firstOrNull;
        if (member == null || member.isAccepted) {
          throw const ClipGroupDraftException('รายการคลิปเปลี่ยนแล้ว');
        }
        if (member.usesSharedCaption && caption != current.sharedCaption) {
          working = await groupStore.saveClipGroup(current.copyWith(
            updatedAt: widget.now().toUtc(),
            items: [
              for (final item in current.items)
                item.draftId == id
                    ? item.copyWith(usesSharedCaption: false) : item,
            ],
          ), expectedRevision: current.revision);
          _guardClipGroup(session, owner);
        }
      }
      await navigator.push<void>(MaterialPageRoute(
        builder: (_) => ClipGroupReviewScreen(
          initialGroup: working!,
          draftsById: drafts,
          ownerSession: session,
          now: widget.now,
          loadSubscription: _loadSubscription,
          loadPostQuota: widget.loadPostQuota ??
              PostDeeApiClient(
                  authHeaders: PostDeeApiAuthHeaders(sessionBinding: session))
                  .loadCurrentSubscription,
          onSaveGroup: saveGroup,
          onSaveCaption: saveCaption,
          onReloadGroup: reload,
          onEditClip: (draft, section) async {
            _guardClipGroup(session, owner);
            final member = working!.items
                .where((item) => item.draftId == draft.id).firstOrNull;
            final latest = await store.loadDraft(draft.id);
            _guardClipGroup(session, owner);
            if (member == null || member.isAccepted || latest == null ||
                latest.uploadedMedia != null) {
              throw const ClipGroupDraftException(
                  'คลิปนี้เคยเริ่มส่งแล้ว กรุณาตรวจรายการเดิมก่อนแก้ไข');
            }
            if (section == ClipGroupEditSection.cover) {
              await _restoreDraft(latest);
              await _openCoverEditor();
              _guardClipGroup(session, owner);
              final saved = await _persistCurrentDraft(showSavedMessage: false);
              if (saved == null) {
                throw const ClipGroupDraftException('บันทึกหน้าปกไม่สำเร็จ');
              }
            } else {
              await navigator.push<PublishDraft>(MaterialPageRoute(
                builder: (_) => _clipGroupMemberEditor(
                    latest, section, store, beforeMemberSave),
              ));
              _guardClipGroup(session, owner);
            }
            await reload();
            return drafts[draft.id];
          },
          onSubmit: (confirmed, onProgress) async {
            final prepared = await _persistClipGroupEdits(
                store, groupStore, confirmed, session, captionsReviewed: true);
            working = prepared;
            final result = await _submitSavedClipGroup(prepared, store,
                groupStore, session, reviewBindings, onProgress);
            working = result.group;
            if (session.isCurrent) await reload();
            return result;
          },
        ),
      ));
      if (mounted && session.isCurrent) {
        final cover = _clearActiveDraftFormState();
        if (cover != null) await cover.cleanupTemporaryFiles();
        _updateClipGroupState(() {
          _currentStep = 0;
          _successMessage = 'เก็บชุดคลิปไว้แล้ว เปิดทำต่อได้จากฉบับร่าง';
        });
        await _loadDrafts();
      }
    } catch (error) {
      if (mounted && session.isCurrent) {
        _updateClipGroupState(() => _errorMessage = apiErrorMessage(error,
            fallbackMessage: error is ClipGroupDraftException
                ? error.message : 'เปิดชุดคลิปไม่สำเร็จ กรุณาลองใหม่'));
      }
    } finally {
      if (openingGeneration == _clipGroupRouteGeneration) {
        _isOpeningClipGroup = false;
      }
    }
  }

  Future<ClipGroupDraft> _persistClipGroupEdits(
    PublishDraftStore store,
    ClipGroupDraftStore groupStore,
    ClipGroupDraft proposed,
    AuthSessionBinding session, {
    bool captionsReviewed = false,
  }) async {
    _guardClipGroup(session, proposed.ownerUserId);
    final current = await groupStore.loadClipGroup(proposed.id);
    _guardClipGroup(session, proposed.ownerUserId);
    if (current == null || current.revision != proposed.revision ||
        current.ownerUserId != proposed.ownerUserId) {
      throw const ClipGroupDraftConflictException();
    }
    final requests = <PublishDraftSaveRequest>[];
    for (final item in proposed.items.where((item) => !item.isAccepted)) {
      _guardClipGroup(session, proposed.ownerUserId);
      final draft = await store.loadDraft(item.draftId);
      _guardClipGroup(session, proposed.ownerUserId);
      if (draft == null || draft.clipGroupId != proposed.id ||
          draft.ownerUserId != proposed.ownerUserId || draft.isClipGroupSource) {
        throw const ClipGroupDraftException(
            'ไม่พบคลิปบางรายการ ร่างที่เหลือยังอยู่ กรุณาตรวจชุดคลิป');
      }
      final caption = item.usesSharedCaption
          ? proposed.sharedCaption : draft.caption;
      final schedule = proposed.deliveryMode == ClipGroupDeliveryMode.scheduled
          ? item.scheduledAt : null;
      final reviewed = captionsReviewed ? false : draft.captionNeedsReview;
      if (caption != draft.caption || schedule != draft.scheduledAt ||
          reviewed != draft.captionNeedsReview) {
        requests.add(clipGroupMemberSaveRequest(draft,
            caption: caption, captionNeedsReview: reviewed,
            scheduledAt: schedule, replaceSchedule: true, now: widget.now()));
      }
    }
    // Desired form values are durable before applying the per-member edits.
    // A failed local copy is reconciled on reopening, never sent half prepared.
    final saved = await groupStore.saveClipGroup(
        proposed.copyWith(updatedAt: widget.now().toUtc()),
        expectedRevision: current.revision);
    _guardClipGroup(session, proposed.ownerUserId);
    for (final request in requests) {
      _guardClipGroup(session, proposed.ownerUserId);
      await store.saveDraft(request);
      _guardClipGroup(session, proposed.ownerUserId);
    }
    return saved;
  }

  Future<ClipGroupSubmissionResult> _submitSavedClipGroup(
    ClipGroupDraft group,
    PublishDraftStore store,
    ClipGroupDraftStore groupStore,
    AuthSessionBinding session,
    Map<SocialPlatform, String> reviewedBindings,
    void Function(ClipGroupSubmissionProgress) onProgress,
  ) async {
    void guard() {
      _guardClipGroup(session, group.ownerUserId);
      for (final entry in reviewedBindings.entries) {
        if (_connectionBinding(entry.key) != entry.value) {
          throw const ClipGroupDraftException(
              'บัญชีปลายทางเปลี่ยนแล้ว กรุณาตรวจช่องทางของชุดคลิปใหม่');
        }
      }
    }
    final runtimeReviews = <String, _ClipGroupRuntimeReview>{};
    try {
      guard();
      await _loadConnections();
      guard();
      final subscription = await _loadSubscription();
      guard();
      final pending = group.items.where((item) => !item.isAccepted).toList();
      for (final item in pending) {
        final draft = await store.loadDraft(item.draftId);
        guard();
        if (draft == null) {
          throw const ClipGroupDraftException('ไม่พบคลิปบางรายการในชุด');
        }
        if (draft.uploadedMedia != null) continue;
        if (subscription.requiresPhoneVerification) {
          throw const ClipGroupDraftException('ยืนยันเบอร์โทรก่อนส่งชุดคลิป');
        }
        if (group.deliveryMode == ClipGroupDeliveryMode.scheduled) {
          if (!subscription.canSchedule ||
              item.scheduledAt == null ||
              !item.scheduledAt!.isAfter(widget.now()) ||
              !isPostScheduleWithinLimit(scheduledAt: item.scheduledAt!,
                  now: widget.now(), plan: subscription.plan)) {
            throw ClipGroupDraftException(
                postScheduleLimitMessage(subscription.plan));
          }
        }
        onProgress(ClipGroupSubmissionProgress(
            itemIndex: item.index,
            completed: group.items.where((item) => item.isAccepted).length,
            total: group.items.length, stage: ClipGroupSubmissionStage.checking,
            itemDraftId: item.draftId));
        await _restoreDraft(draft);
        await _readSelectedVideoDuration();
        guard();
        if (_draftUnavailablePlatforms.isNotEmpty ||
            _selectedPlatformWithoutIdentity != null ||
            _selectedPlatforms.length != item.platformApiValues.length) {
          throw const ClipGroupDraftException(
              'บางช่องทางในชุดคลิปยังไม่พร้อม กรุณาตรวจการเชื่อมต่อ');
        }
        for (final platform in _selectedPlatforms.toList()) {
          final needsFreshTikTok = platform == SocialPlatform.tiktok &&
              _platformSettings.tiktokPublishMode == TikTokPublishMode.directPost;
          if (needsFreshTikTok || !_resolvedPlatformSettings.canSubmit(platform)) {
            await _openPlatformSettings(platform);
            guard();
            if (!_resolvedPlatformSettings.canSubmit(platform) ||
                (needsFreshTikTok &&
                    _tikTokConsentedIntent != _tikTokConsentIntent)) {
              throw const ClipGroupDraftException(
                  'ยังไม่ได้ยืนยันการตั้งค่าบางคลิป ชุดคลิปยังอยู่ในฉบับร่าง');
            }
          }
        }
        final textError = _postTextValidationError();
        if (textError != null) throw ClipGroupDraftException(textError);
        if (_selectedDurationProblem case final problem?) {
          throw ClipGroupDraftException(problem.message);
        }
        final saved = await _persistCurrentDraft(showSavedMessage: false);
        guard();
        if (saved == null) {
          throw const ClipGroupDraftException('บันทึกการตรวจคลิปไม่สำเร็จ');
        }
        runtimeReviews[draft.id] = _ClipGroupRuntimeReview(
          form: _formSnapshot,
          settings: _platformSettings,
          bindings: Map.of(_savedPlatformSettingsBindings),
          tikTokBinding: _tikTokConnectionBinding(),
          tikTokIntent: _tikTokConsentedIntent,
          tikTokOptions: _tikTokPublishingOptions,
        );
      }
      guard();
      return await ClipGroupSubmission(
        groupStore: groupStore,
        draftStore: store,
        now: widget.now,
        submitOne: (draft, item, checkpoint) async {
          guard();
          if (draft.uploadedMedia != null) {
            final recovered = await _recoverClipGroupMember(draft);
            guard();
            if (recovered != null) {
              if (!const {'QUEUED','PUBLISHING','PUBLISHED','PARTIAL_PUBLISHED'}
                  .contains(recovered.status.toUpperCase())) {
                throw const ClipGroupDraftException(
                    'พบรายการเดิมที่ยังส่งไม่สำเร็จ กรุณาตรวจรายละเอียดโพสต์');
              }
              await checkpoint(recovered);
              guard();
              await _deleteDraftAndConfirmAbsent(store, draft.id);
              return recovered;
            }
            // Never invent a new intent after a response was lost.
            throw const ClipGroupDraftException(
                'ยังไม่พบผลรายการเดิม ร่างและข้อมูลอัปโหลดยังอยู่ กรุณาตรวจอีกครั้ง');
          }
          await _restoreDraft(draft);
          await _readSelectedVideoDuration();
          guard();
          final proof = runtimeReviews[draft.id];
          if (proof == null || proof.tikTokBinding != _tikTokConnectionBinding()) {
            throw const ClipGroupDraftException(
                'ข้อมูลการตรวจคลิปเปลี่ยนแล้ว กรุณาตรวจชุดคลิปอีกครั้ง');
          }
          _updateClipGroupState(() {
            _platformSettings = proof.settings;
            _savedPlatformSettingsBindings
              ..clear()..addAll(proof.bindings);
            _tikTokPublishingOptions = proof.tikTokOptions;
            _tikTokConsentedIntent = proof.tikTokIntent;
          });
          if (_formSnapshot != proof.form ||
              (proof.tikTokIntent != null &&
                  proof.tikTokIntent != _tikTokConsentIntent)) {
            throw const ClipGroupDraftException(
                'คลิปหรือเวลาส่งเปลี่ยนแล้ว กรุณาตรวจชุดคลิปอีกครั้ง');
          }
          _clipGroupAcceptedCheckpoint = checkpoint;
          try {
            final post = await _createPost();
            guard();
            if (post == null) {
              throw ClipGroupDraftException(_errorMessage ??
                  _pendingInlineError ?? _submissionInlineError ??
                  'ส่งคลิปนี้ไม่สำเร็จ รายการที่เหลือยังอยู่ในชุด');
            }
            return post;
          } finally {
            _clipGroupAcceptedCheckpoint = null;
          }
        },
      )(group, session: session, onProgress: onProgress);
    } catch (error) {
      final completed = group.items.where((item) => item.isAccepted).length;
      return ClipGroupSubmissionResult(group: group, completed: completed,
          remaining: group.items.length-completed, error: error,
          cancelled: !session.isCurrent);
    }
  }

  Future<QueuedPostResult?> _recoverClipGroupMember(PublishDraft draft) async {
    final receipt = draft.uploadedMedia!;
    final platforms = draft.platformApiValues.map(_platformFromApiValue)
        .whereType<SocialPlatform>().toSet();
    var settings = draft.platformSettings;
    if (settings.youtubeMadeForKids != null &&
        settings.youtubeContainsSyntheticMedia != null &&
        settings.youtubeCommunityGuidelinesCertified) {
      settings = settings.resolvedForCaption(draft.caption);
    }
    if (platforms.contains(SocialPlatform.tiktok) &&
        settings.tiktokPublishMode == TikTokPublishMode.directPost) {
      settings = settings.copyWith(
          tiktokVideoDurationSeconds: receipt.videoDurationSeconds);
    }
    return (widget.recoverPostSubmission ?? _apiClient.recoverPostSubmission)(
        CreatePostRequest(
          clientRequestId: draft.submissionRequestId,
          caption: _requestCaption(draft.caption, settings, platforms),
          videoS3Key: receipt.videoS3Key,
          mediaContentFingerprint: receipt.mediaContentFingerprint,
          platforms: draft.platformApiValues.toList(),
          platformSettings: settings.toRecoveryApiJson(selectedPlatforms: platforms),
          scheduledAt: draft.scheduledAt,
          coverImageS3Key: receipt.coverImageS3Key,
          coverFrameTimeMs: draft.cover?.design.coverFrameTimeMs,
        ));
  }

  UploaderScreen _clipGroupMemberEditor(
      PublishDraft draft, ClipGroupEditSection section, PublishDraftStore store,
      Future<void> Function(String, String) beforeSave) => UploaderScreen(
    fullScreen: true, initialDraftId: draft.id, draftStore: store,
    clipGroupEditor: true,
    clipGroupEditorStep: section == ClipGroupEditSection.channels ? 2 : 1,
    beforeClipGroupMemberSave: beforeSave,
    now: widget.now, loadTemplates: widget.loadTemplates,
    loadSubscription: widget.loadSubscription, loadCaptionQuota: widget.loadCaptionQuota,
    loadPostQuota: widget.loadPostQuota, generateCaption: widget.generateCaption,
    generateRealClipCaption: widget.generateRealClipCaption,
    enableRevenueCatBilling: widget.enableRevenueCatBilling,
    captionWritingStyleStore: widget.captionWritingStyleStore,
    platformPublishDefaultsStore: widget.platformPublishDefaultsStore,
    growthToolSettingsStore: widget.growthToolSettingsStore,
    loadSocialConnections: widget.loadSocialConnections,
    loadSocialPublishingReadiness: widget.loadSocialPublishingReadiness,
    probePublishMedia: widget.probePublishMedia,
    readVideoMetadata: widget.readVideoMetadata,
    loadTikTokPublishingOptions: widget.loadTikTokPublishingOptions,
    loadTikTokDurationOptions: widget.loadTikTokDurationOptions,
    openCoverEditor: widget.openCoverEditor,
    coverImageProcessor: widget.coverImageProcessor,
    extractFrames: widget.extractFrames,
    extractCaptionAudio: widget.extractCaptionAudio,
    extractCaptionVisualProxy: widget.extractCaptionVisualProxy,
    analytics: widget.analytics,
  );

  Future<void> _saveClipGroupMemberAndClose() async {
    if (_formBusy || _isGeneratingCaption || !widget.clipGroupEditor) return;
    final saved = await _persistCurrentDraft(showSavedMessage: false);
    if (saved != null && mounted) {
      _allowExit = true;
      Navigator.of(context).pop(saved);
    }
  }

  Widget _buildClipGroupEditorToolbar(BuildContext context) => Padding(
    padding: AppTheme.screenPadding,
    child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(uploaderText(context, 'แก้คลิปในชุด', 'Edit clip in group'),
              style: Theme.of(context).textTheme.titleLarge),
          if (_selectedVideoName != null)
            Text(_selectedVideoName!, maxLines: 1,
                overflow: TextOverflow.ellipsis),
          Text(uploaderText(context, 'ช่องทางตามแผนแบ่งคลิป',
              'Destinations follow the split plan'),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      )),
      IconButton(onPressed: _formBusy ? null : _requestExit,
          icon: const Icon(Icons.close),
          tooltip: uploaderText(context, 'กลับไปที่ชุดคลิป', 'Back to group')),
    ]),
  );

  Widget _buildClipGroupEditorActionBar(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(
          key: const ValueKey('clip-group-member-save'),
          onPressed: _formBusy || _isGeneratingCaption
              ? null : _saveClipGroupMemberAndClose,
          child: Text(uploaderText(context, 'บันทึกกลับเข้าชุด',
              'Save and return to group')),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(uploaderText(context, 'บันทึกการแก้ไข ยังไม่ส่งโพสต์',
            'Save changes without submitting')),
      ]),
    ),
  );
}
