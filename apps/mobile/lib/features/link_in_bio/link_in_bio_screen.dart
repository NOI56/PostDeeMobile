import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/link_in_bio_appearance.dart';
import '../../core/network/api_error_message.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import 'link_in_bio_appearance_editor.dart';
import 'link_in_bio_draft_store.dart';
import 'link_in_bio_image_picker.dart';
import 'link_in_bio_preview.dart';
import 'link_in_bio_validation.dart';

typedef LinkInBioProfileLoader = Future<LinkInBioProfileResult?> Function();
typedef LinkInBioProfilePublisher = Future<LinkInBioProfileResult> Function({
  required String storeName,
  required String slug,
  required List<LinkInBioLinkResult> links,
  LinkInBioAppearance? appearance,
});
typedef LinkInBioProfileUnpublisher = Future<LinkInBioProfileResult> Function();
typedef LinkInBioLinkOpener = Future<bool> Function(Uri url);
typedef LinkInBioLinkCopier = Future<void> Function(String url);
typedef LinkInBioImagePicker = Future<Uint8List?> Function();
typedef LinkInBioImageUploader = Future<String> Function({
  required String slot,
  required Uint8List bytes,
});
typedef LinkInBioImageLoader = Future<Uint8List> Function(String key);

class LinkInBioScreen extends StatefulWidget {
  const LinkInBioScreen({
    super.key,
    this.draftStore,
    this.onBack,
    this.embeddedInTab = false,
    this.isActive = true,
    this.loadProfile,
    this.publishProfile,
    this.unpublishProfile,
    this.openLink,
    this.copyLink,
    this.pickImage,
    this.uploadImage,
    this.loadImage,
  });

  final LinkInBioDraftStore? draftStore;
  final VoidCallback? onBack;
  final bool embeddedInTab;
  final bool isActive;
  final LinkInBioProfileLoader? loadProfile;
  final LinkInBioProfilePublisher? publishProfile;
  final LinkInBioProfileUnpublisher? unpublishProfile;
  final LinkInBioLinkOpener? openLink;
  final LinkInBioLinkCopier? copyLink;
  final LinkInBioImagePicker? pickImage;
  final LinkInBioImageUploader? uploadImage;
  final LinkInBioImageLoader? loadImage;

  @override
  State<LinkInBioScreen> createState() => _LinkInBioScreenState();
}

class _LinkInBioScreenState extends State<LinkInBioScreen> {
  final _apiClient = PostDeeApiClient();
  final _scrollController = ScrollController();
  late final LinkInBioDraftStore _draftStore;
  late final String? _ownerUserId;
  late final TextEditingController _storeNameController;
  late final TextEditingController _slugController;
  late final TextEditingController _descriptionController;
  final _urlSettings = ExpansibleController();
  final _infoForm = GlobalKey<FormState>();
  int _step = 0;
  bool _editorOpen = false;
  Set<String> _enabledLinkIds = {};
  List<LinkInBioCustomLink> _customLinks = [];
  LinkInBioAppearance _appearance = const LinkInBioAppearance();
  final Map<String, Uint8List> _images = {};
  final _imageRevision = ValueNotifier<int>(0);
  final Set<String> _loadingImages = {};
  LinkInBioProfileResult? _profile;
  bool _hasLoadedDraft = false;
  bool _hasLocalDraft = false;
  bool _hasConfirmedProfile = false;
  bool _isLoading = false;
  bool _isBusy = false;
  bool _publicationUncertain = false;
  int _editVersion = 0;
  String? _errorMessage;
  String? _noticeMessage;
  Timer? _noticeTimer;

  bool get _ownerStillCurrent =>
      mounted &&
      PostDeeAuthSessionStore.instance.session.stableUserId == _ownerUserId;
  bool get _canEdit => !_isBusy;
  bool get _isEditing => _editorOpen || _profile == null;
  List<LinkInBioCustomLink> get _activeLinks =>
      _customLinks.where((link) => _enabledLinkIds.contains(link.id)).toList();
  LinkInBioDraft get _draft => LinkInBioDraft(
        storeName: _storeNameController.text.trim(),
        slug: _slugController.text.trim(),
        autoUpdateFromScheduledPosts: false,
        enabledLinkIds: {..._enabledLinkIds},
        customLinks: List.of(_customLinks),
        appearance: _appearance,
      );
  bool get _hasUnpublishedChanges {
    final profile = _profile;
    if (profile == null || !profile.isPublished) return false;
    return _storeNameController.text.trim() != profile.storeName ||
        _slugController.text.trim() != profile.slug ||
        jsonEncode(_activeLinks.map((link) => link.toJson()).toList()) !=
            jsonEncode(profile.links.map((link) => link.toJson()).toList()) ||
        jsonEncode(_appearance.toJson()) !=
            jsonEncode(profile.appearance.toJson());
  }

  @override
  void initState() {
    super.initState();
    _ownerUserId = PostDeeAuthSessionStore.instance.session.stableUserId;
    _draftStore = widget.draftStore ??
        SharedPreferencesLinkInBioDraftStore(ownerUserId: _ownerUserId);
    _storeNameController =
        TextEditingController(text: LinkInBioDraft.defaults().storeName);
    _slugController = TextEditingController();
    _descriptionController = TextEditingController();
    if (widget.isActive) _loadProfile();
  }

  @override
  void didUpdateWidget(covariant LinkInBioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _loadProfile();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _urlSettings.dispose();
    _scrollController.dispose();
    _images.clear();
    _imageRevision.dispose();
    _loadingImages.clear();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _applyDraft(LinkInBioDraft draft) {
    _storeNameController.text = draft.storeName;
    _slugController.text = draft.slug;
    _customLinks = List.of(draft.customLinks);
    _enabledLinkIds = {...draft.enabledLinkIds};
    _appearance = draft.appearance;
    _descriptionController.text = _appearance.description;
    if (_editVersion == 0 && isValidLinkInBioSlug(draft.slug)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ownerStillCurrent &&
            _isEditing &&
            _step == 0 &&
            isValidLinkInBioSlug(_slugController.text.trim())) {
          _urlSettings.collapse();
        }
      });
    }
    unawaited(_loadDraftImages());
  }

  Future<void> _loadDraftImages() async {
    final keys = {
      _appearance.logoKey,
      _appearance.coverKey,
      _appearance.background.imageKey,
      _profile?.appearance.logoKey,
      _profile?.appearance.coverKey,
      _profile?.appearance.background.imageKey,
    }.whereType<String>().toSet();
    for (final key in keys) {
      if (_images.containsKey(key) || !_loadingImages.add(key)) continue;
      try {
        final bytes =
            await (widget.loadImage ?? _apiClient.loadLinkInBioImage)(key);
        if (!_ownerStillCurrent) return;
        setState(() {
          _images[key] = bytes;
          _imageRevision.value++;
        });
      } catch (_) {
        if (_ownerStillCurrent) {
          setState(() => _errorMessage =
              'โหลดรูปตัวอย่างไม่สำเร็จ กรุณาตรวจสถานะเว็บไซต์เพื่อลองใหม่');
        }
      } finally {
        _loadingImages.remove(key);
      }
    }
  }

  Future<String?> _uploadDraftImage(String slot) async {
    if (!_ownerStillCurrent || !_canEdit) return null;
    final bytes = await (widget.pickImage ?? pickLinkInBioImage)();
    if (!_ownerStillCurrent || bytes == null) return null;
    setState(() => _isBusy = true);
    try {
      final key = await (widget.uploadImage ?? _apiClient.uploadLinkInBioImage)(
          slot: slot, bytes: bytes);
      if (!_ownerStillCurrent) return null;
      _images[key] = bytes;
      _imageRevision.value++;
      return key;
    } finally {
      if (_ownerStillCurrent) setState(() => _isBusy = false);
    }
  }

  Future<void> _decorate() async {
    if (!_canEdit || _isLoading) return;
    final value = await showModalBottomSheet<LinkInBioAppearance>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => LinkInBioAppearanceEditor(
            showThemePicker: false,
            appearance: _appearance,
            storeName: _storeNameController.text,
            slug: _slugController.text,
            links: _activeLinks,
            images: _images,
            imageRevision: _imageRevision,
            uploadImage: _uploadDraftImage));
    if (!_ownerStillCurrent || value == null) return;
    setState(() {
      _appearance = value;
      _descriptionController.text = value.description;
      _editVersion++;
    });
  }

  Widget _draftPreview() => LinkInBioPreview(
      storeName: _storeNameController.text,
      slug: _slugController.text,
      links: _activeLinks,
      appearance: _appearance,
      images: _images);

  Future<void> _loadProfile() async {
    if (_isLoading || _isBusy) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final editVersion = _editVersion;
    final publicationWasUncertain = _publicationUncertain;
    try {
      if (!_hasLoadedDraft) {
        final draft = await _draftStore.loadDraft();
        if (!_ownerStillCurrent) return;
        _hasLoadedDraft = true;
        if (draft != null) {
          _hasLocalDraft = true;
          if (_editVersion == editVersion) setState(() => _applyDraft(draft));
        }
      }
      final profile =
          await (widget.loadProfile ?? _apiClient.loadLinkInBioProfile)();
      if (!_ownerStillCurrent) return;
      setState(() {
        _profile = profile;
        _hasConfirmedProfile = true;
        _publicationUncertain = false;
        if (publicationWasUncertain && profile?.isPublished == true) {
          _editorOpen = false;
        }
        if (!_hasLocalDraft &&
            _editVersion == 0 &&
            _editVersion == editVersion &&
            profile != null) {
          _applyDraft(LinkInBioDraft(
              storeName: profile.storeName,
              slug: profile.slug,
              autoUpdateFromScheduledPosts: false,
              enabledLinkIds: profile.links.map((link) => link.id).toSet(),
              customLinks: profile.links
                  .map((link) => LinkInBioCustomLink(
                      id: link.id,
                      title: link.title,
                      url: link.url,
                      category: link.category,
                      icon: link.icon,
                      font: link.font,
                      textColor: link.textColor,
                      buttonColor: link.buttonColor))
                  .toList(),
              appearance: profile.appearance));
        }
      });
      unawaited(_loadDraftImages());
    } catch (error) {
      if (_ownerStillCurrent) {
        setState(() => _errorMessage = apiErrorMessage(error,
            fallbackMessage: 'โหลดสถานะหน้าโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่'));
      }
    } finally {
      if (_ownerStillCurrent) setState(() => _isLoading = false);
    }
  }

  void _edited() => setState(() {
        _editorOpen = true;
        _editVersion++;
        _errorMessage = null;
      });

  void _message(String text) {
    if (!_ownerStillCurrent) return;
    _noticeTimer?.cancel();
    setState(() => _noticeMessage = text);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (_ownerStillCurrent) setState(() => _noticeMessage = null);
    });
  }

  void _showStatus() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Future<void> _saveDraft() async {
    if (!_canEdit) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await _draftStore.saveDraft(_draft);
      if (!_ownerStillCurrent) return;
      _hasLocalDraft = true;
      _message('บันทึกแบบร่างในเครื่องแล้ว ยังไม่ได้อัปเดตเว็บไซต์');
    } catch (_) {
      if (_ownerStillCurrent) {
        setState(() => _errorMessage = 'บันทึกแบบร่างไม่สำเร็จ กรุณาลองใหม่');
      }
    } finally {
      if (_ownerStillCurrent) setState(() => _isBusy = false);
    }
  }

  String? _publishValidation() {
    final draft = _draft;
    if (_descriptionController.text.length > 280) {
      return 'คำแนะนำร้านยาวเกิน 280 ตัวอักษร';
    }
    if (draft.storeName.isEmpty || draft.storeName.length > 80) {
      return 'กรอกชื่อร้าน 1–80 ตัวอักษร';
    }
    if (!isValidLinkInBioSlug(draft.slug)) {
      return 'ชื่อ URL ต้องเป็น a-z, 0-9 หรือขีดกลางภายในชื่อ ความยาว 3–40 ตัวอักษร';
    }
    if (_activeLinks.isEmpty) {
      return 'เพิ่มและเปิดใช้งานอย่างน้อย 1 ลิงก์ก่อนเผยแพร่';
    }
    if (_customLinks.length > 20) return 'เพิ่มได้สูงสุด 20 ลิงก์';
    if (_appearance.background.mode == 'image' &&
        _appearance.background.imageKey == null) {
      return 'เพิ่มภาพพื้นหลัง หรือเปลี่ยนพื้นหลังเป็นสีเดียวก่อนเผยแพร่';
    }
    final ids = <String>{};
    for (final link in _activeLinks) {
      if (link.id.trim().isEmpty || link.id.length > 80 || !ids.add(link.id)) {
        return 'ข้อมูลลิงก์ไม่ถูกต้อง กรุณาลบแล้วเพิ่มใหม่';
      }
      final error = linkInBioLinkError(link.title, link.url);
      if (error != null) return error;
    }
    return null;
  }

  Future<void> _publish() async {
    if (!_canEdit || _isLoading || _publicationUncertain) return;
    final validation = _publishValidation();
    if (validation != null) {
      setState(() => _errorMessage = validation);
      _showStatus();
      return;
    }
    final draft = _draft;
    final links = _activeLinks
        .map((link) => LinkInBioLinkResult(
            id: link.id,
            title: link.title,
            url: link.url,
            category: link.category,
            icon: link.icon,
            font: link.font,
            textColor: link.textColor,
            buttonColor: link.buttonColor))
        .toList();
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    var requested = false;
    try {
      await _draftStore.saveDraft(draft);
      if (!_ownerStillCurrent) return;
      _hasLocalDraft = true;
      requested = true;
      final profile =
          await (widget.publishProfile ?? _apiClient.publishLinkInBioProfile)(
              storeName: draft.storeName,
              slug: draft.slug,
              links: links,
              appearance: draft.appearance);
      if (!_ownerStillCurrent) return;
      if (!profile.isPublished || profile.publicUrl == null) {
        throw const ApiException('Publication was not confirmed');
      }
      setState(() {
        _profile = profile;
        _hasConfirmedProfile = true;
        _publicationUncertain = false;
        _storeNameController.text = profile.storeName;
        _slugController.text = profile.slug;
        _appearance = profile.appearance;
        _descriptionController.text = profile.appearance.description;
        _editorOpen = false;
        final publishedLinks = {
          for (final link in profile.links) link.id: link
        };
        _customLinks = _customLinks.map((link) {
          final published = publishedLinks[link.id];
          return published == null
              ? link
              : LinkInBioCustomLink(
                  id: published.id,
                  title: published.title,
                  url: published.url,
                  category: published.category,
                  icon: published.icon,
                  font: published.font,
                  textColor: published.textColor,
                  buttonColor: published.buttonColor);
        }).toList();
      });
      // Publication is already confirmed. A local disk failure must not turn
      // that server result into an unknown or failed publication.
      try {
        await _draftStore.saveDraft(_draft);
      } catch (_) {
        if (_ownerStillCurrent) {
          setState(() => _errorMessage =
              'เผยแพร่แล้ว แต่บันทึกแบบร่างในเครื่องไม่สำเร็จ กรุณาบันทึกแบบร่างอีกครั้ง');
        }
      }
      _message('เผยแพร่หน้าโปรไฟล์แล้ว คัดลอกลิงก์ส่งให้ลูกค้าได้');
    } catch (error) {
      if (!_ownerStillCurrent) return;
      final definitive = error is ApiException &&
          error.statusCode != null &&
          error.statusCode! >= 400 &&
          error.statusCode! < 500 &&
          error.statusCode != 408;
      setState(() {
        _publicationUncertain = requested && !definitive;
        _errorMessage =
            error is ApiException && error.code == 'LINK_IN_BIO_SLUG_TAKEN'
                ? 'ชื่อ URL นี้มีคนใช้แล้ว กรุณาเลือกชื่อใหม่'
                : _publicationUncertain
                    ? 'ยังไม่ทราบผลการเผยแพร่ กรุณาตรวจสถานะก่อนลองอีกครั้ง'
                    : apiErrorMessage(error,
                        fallbackMessage:
                            'เผยแพร่หน้าโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่');
      });
    } finally {
      if (_ownerStillCurrent) setState(() => _isBusy = false);
      if (_ownerStillCurrent) _showStatus();
    }
  }

  Future<void> _unpublish() async {
    if (!_canEdit || _isLoading || _publicationUncertain) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('หยุดเผยแพร่หน้าโปรไฟล์?'),
              content: const Text(
                  'ลูกค้าจะเปิดลิงก์หน้านี้ไม่ได้จนกว่าจะเผยแพร่อีกครั้ง แบบร่างของคุณยังอยู่'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('ยกเลิก')),
                FilledButton(
                    key: const ValueKey('link-in-bio-confirm-unpublish'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('หยุดเผยแพร่')),
              ],
            ));
    if (confirmed != true ||
        !_ownerStillCurrent ||
        !_canEdit ||
        _isLoading ||
        _publicationUncertain) {
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final profile = await (widget.unpublishProfile ??
          _apiClient.unpublishLinkInBioProfile)();
      if (!_ownerStillCurrent) return;
      if (profile.isPublished) {
        throw const ApiException('Unpublishing was not confirmed');
      }
      setState(() {
        _profile = profile;
        _hasConfirmedProfile = true;
      });
      _message('หยุดเผยแพร่แล้ว แบบร่างของคุณยังอยู่');
    } catch (error) {
      if (!_ownerStillCurrent) return;
      setState(() {
        _publicationUncertain = true;
        _errorMessage =
            'ยังไม่ทราบผลการหยุดเผยแพร่ กรุณาตรวจสถานะก่อนลองอีกครั้ง';
      });
    } finally {
      if (_ownerStillCurrent) setState(() => _isBusy = false);
      if (_ownerStillCurrent) _showStatus();
    }
  }

  Future<void> _copyPublicUrl() async {
    final url = _publicationUncertain ? null : _profile?.publicUrl;
    if (url == null) return;
    try {
      await (widget.copyLink ??
          (text) =>
              Clipboard.setData(ClipboardData(text: text)))(url.toString());
      _message('คัดลอกลิงก์แล้ว วางในแชตหรือหน้าโปรไฟล์ได้เลย');
    } catch (_) {
      _message('คัดลอกลิงก์ไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> _openPublicUrl() async {
    final url = _publicationUncertain ? null : _profile?.publicUrl;
    if (url == null) return;
    try {
      final opened = await (widget.openLink ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication))(url);
      if (!opened) {
        _message('เปิดเว็บไซต์ไม่สำเร็จ กรุณาคัดลอกลิงก์แล้วเปิดในเบราว์เซอร์');
      }
    } catch (_) {
      _message('เปิดเว็บไซต์ไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  void _preview() {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('ตัวอย่างก่อนเผยแพร่'),
              content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(child: _draftPreview())),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ปิดตัวอย่าง'))
              ],
            ));
  }

  Future<void> _showAddLinkSheet() async {
    if (!_canEdit) return;
    if (_customLinks.length >= 20) {
      _message('เพิ่มได้สูงสุด 20 ลิงก์');
      return;
    }
    final link = await _linkSheet();
    if (!_ownerStillCurrent || link == null) return;
    setState(() {
      _customLinks = [..._customLinks, link];
      _enabledLinkIds.add(link.id);
      _editVersion++;
    });
  }

  Future<LinkInBioCustomLink?> _linkSheet({LinkInBioCustomLink? initialLink}) =>
      showModalBottomSheet<LinkInBioCustomLink>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _AddLinkSheet(initialLink: initialLink));

  Future<void> _showEditLinkSheet(LinkInBioCustomLink existingLink) async {
    if (!_canEdit) return;
    final link = await _linkSheet(initialLink: existingLink);
    if (!_ownerStillCurrent || link == null) return;
    setState(() {
      _customLinks = [
        for (final item in _customLinks) item.id == link.id ? link : item
      ];
      _editVersion++;
    });
  }

  void _setLinkEnabled(String id, bool value) {
    if (!_canEdit) return;
    setState(() {
      value ? _enabledLinkIds.add(id) : _enabledLinkIds.remove(id);
      if (!value && _appearance.featuredLinkId == id) {
        _appearance = _appearance.copyWith(featuredLinkId: null);
      }
      _editVersion++;
    });
  }

  void _deleteCustomLink(String id) {
    if (!_canEdit) return;
    setState(() {
      _customLinks = _customLinks.where((link) => link.id != id).toList();
      _enabledLinkIds.remove(id);
      if (_appearance.featuredLinkId == id) {
        _appearance = _appearance.copyWith(featuredLinkId: null);
      }
      _editVersion++;
    });
  }

  void _moveLink(int from, int to) {
    if (!_canEdit || to < 0 || to >= _customLinks.length) return;
    setState(() {
      final items = List<LinkInBioCustomLink>.of(_customLinks);
      items.insert(to, items.removeAt(from));
      _customLinks = items;
      _editVersion++;
    });
  }

  void _featureLink(String id) {
    if (!_canEdit || !_enabledLinkIds.contains(id)) return;
    setState(() {
      _appearance = _appearance.copyWith(
          featuredLinkId: _appearance.featuredLinkId == id ? null : id);
      _editVersion++;
    });
  }

  void _setStep(int value) {
    if (!_canEdit || _isLoading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editorOpen = true;
      _step = value;
    });
    _showStatus();
  }

  void _next() {
    String? error;
    if (_step == 0) {
      if (!_infoForm.currentState!.validate()) return;
      if (_storeNameController.text.trim().isEmpty ||
          _storeNameController.text.trim().length > 80) {
        error = 'กรอกชื่อร้าน 1–80 ตัวอักษร';
      } else if (!isValidLinkInBioSlug(_slugController.text.trim())) {
        _urlSettings.expand();
        error =
            'ชื่อ URL ต้องเป็น a-z, 0-9 หรือขีดกลางภายในชื่อ ความยาว 3–40 ตัวอักษร';
      }
    } else if (_step == 1 && _activeLinks.isEmpty) {
      error = 'เพิ่มและเปิดใช้งานอย่างน้อย 1 ลิงก์ก่อนเผยแพร่';
    } else if (_step == 2 &&
        _appearance.background.mode == 'image' &&
        _appearance.background.imageKey == null) {
      error = 'เพิ่มภาพพื้นหลัง หรือเปลี่ยนพื้นหลังเป็นสีเดียวก่อนเผยแพร่';
    }
    if (error != null) {
      setState(() => _errorMessage = error);
      _showStatus();
      return;
    }
    setState(() => _errorMessage = null);
    _setStep(_step + 1);
  }

  Future<void> _chooseLogo() async {
    try {
      final key = await _uploadDraftImage('logo');
      if (!_ownerStillCurrent || key == null) return;
      setState(() {
        _appearance = _appearance.copyWith(logoKey: key);
        _editVersion++;
      });
    } catch (_) {
      if (_ownerStillCurrent) {
        setState(() => _errorMessage =
            'อัปโหลดโลโก้ไม่สำเร็จ กรุณาลองใหม่ รูปเดิมยังอยู่');
      }
    }
  }

  Widget _heading(String title) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(title,
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary)));

  Widget _steps() {
    const ids = ['info', 'links', 'theme', 'review'];
    const labels = ['ข้อมูลร้าน', 'ลิงก์', 'ธีม', 'ตรวจและเผยแพร่'];
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
                child: TextButton(
                    key: ValueKey('link-in-bio-step-${ids[index]}'),
                    onPressed:
                        _canEdit && !_isLoading ? () => _setStep(index) : null,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 2)),
                    child: Column(children: [
                      Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _step == index
                                  ? AppTheme.accentCyanInk
                                  : Colors.transparent,
                              border: Border.all(
                                  color: _step == index
                                      ? AppTheme.accentCyanInk
                                      : AppTheme.border)),
                          child: Text('${index + 1}',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: _step == index
                                      ? Colors.white
                                      : AppTheme.textSecondary))),
                      const SizedBox(height: 6),
                      Text(labels[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: _step == index
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: _step == index
                                  ? AppTheme.accentCyanInk
                                  : AppTheme.textSecondary)),
                    ]))),
        ]));
  }

  Widget _info() => Form(
      key: _infoForm,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('เริ่มจากข้อมูลร้าน'),
        TextField(
            key: const ValueKey('link-in-bio-store-name'),
            controller: _storeNameController,
            enabled: _canEdit,
            onChanged: (_) => _edited(),
            maxLength: 80,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'ชื่อร้าน', hintText: 'เช่น ร้านมินาขายดี')),
        const SizedBox(height: 12),
        TextFormField(
            key: const ValueKey('link-in-bio-description'),
            controller: _descriptionController,
            enabled: _canEdit,
            maxLength: 280,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'คำแนะนำร้าน', hintText: 'ร้านของคุณขายอะไร'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) => (value ?? '').length > 280
                ? 'คำแนะนำร้านยาวเกิน 280 ตัวอักษร'
                : null,
            onChanged: (value) {
              if (value.length <= 280) {
                setState(() {
                  _appearance = _appearance.copyWith(description: value);
                  _editVersion++;
                  _editorOpen = true;
                });
              }
            }),
        const SizedBox(height: 16),
        Row(children: [
          if (_images[_appearance.logoKey] != null) ...[
            SizedBox.square(
                dimension: 56,
                key: const ValueKey('link-in-bio-info-logo'),
                child: ClipOval(
                    child: Image.memory(_images[_appearance.logoKey]!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const Icon(Icons.image_not_supported_outlined)))),
            const SizedBox(width: 12),
          ],
          Expanded(
              child: OutlinedButton.icon(
                  key: const ValueKey('link-in-bio-image-logo'),
                  onPressed: _canEdit && !_isLoading ? _chooseLogo : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_appearance.logoKey == null
                      ? 'เพิ่มโลโก้'
                      : 'เปลี่ยนโลโก้'))),
          if (_appearance.logoKey != null)
            IconButton(
                tooltip: 'ลบโลโก้',
                onPressed: _canEdit
                    ? () => setState(() {
                          _appearance = _appearance.copyWith(logoKey: null);
                          _editVersion++;
                        })
                    : null,
                icon: const Icon(Icons.delete_outline)),
        ]),
        const SizedBox(height: 16),
        ExpansionTile(
            key: const ValueKey('link-in-bio-url-disclosure'),
            controller: _urlSettings,
            initiallyExpanded:
                !isValidLinkInBioSlug(_slugController.text.trim()),
            maintainState: true,
            tilePadding: EdgeInsets.zero,
            title: const Text('ที่อยู่เว็บไซต์ (URL)',
                key: ValueKey('link-in-bio-url-settings'),
                style: TextStyle(fontSize: 15)),
            subtitle: _slugController.text.trim().isEmpty
                ? null
                : Text(_slugController.text.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            children: [
              TextField(
                  key: const ValueKey('link-in-bio-slug'),
                  controller: _slugController,
                  enabled: _canEdit,
                  onChanged: (_) => _edited(),
                  maxLength: 40,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                      labelText: 'ชื่อ URL',
                      hintText: 'mina-shop',
                      helperText: 'a-z, 0-9 และขีดกลาง ความยาว 3–40 ตัวอักษร'))
            ]),
      ]));

  Widget _linkMenu(int index, LinkInBioCustomLink link) =>
      PopupMenuButton<String>(
          key: ValueKey('link-in-bio-link-menu-${link.id}'),
          tooltip: 'ตัวเลือกลิงก์',
          enabled: _canEdit,
          onSelected: (value) {
            switch (value) {
              case 'feature':
                _featureLink(link.id);
              case 'up':
                _moveLink(index, index - 1);
              case 'down':
                _moveLink(index, index + 1);
              case 'delete':
                _deleteCustomLink(link.id);
            }
          },
          itemBuilder: (_) => [
                PopupMenuItem(
                    key: ValueKey('link-in-bio-feature-${link.id}'),
                    value: 'feature',
                    enabled: _enabledLinkIds.contains(link.id),
                    child: Text(_appearance.featuredLinkId == link.id
                        ? 'ยกเลิกโปรโมชันเด่น'
                        : 'เลือกเป็นโปรโมชันเด่น')),
                PopupMenuItem(
                    key: ValueKey('link-in-bio-move-up-${link.id}'),
                    value: 'up',
                    enabled: index > 0,
                    child: const Text('เลื่อนขึ้น')),
                PopupMenuItem(
                    key: ValueKey('link-in-bio-move-down-${link.id}'),
                    value: 'down',
                    enabled: index < _customLinks.length - 1,
                    child: const Text('เลื่อนลง')),
                PopupMenuItem(
                    key: ValueKey('link-in-bio-delete-${link.id}'),
                    value: 'delete',
                    child: const Tooltip(
                        message: 'ลบลิงก์', child: Text('ลบลิงก์'))),
              ]);

  Widget _links() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('เพิ่มช่องทางของร้าน'),
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
                'ลิงก์สินค้าและช่องทางติดต่อ (${_customLinks.length}/20)',
                style: TextStyle(color: AppTheme.textSecondary))),
        if (_customLinks.isEmpty)
          const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                  'เพิ่มลิงก์จริง เช่น ร้าน Shopee, Lazada หรือ LINE ของคุณ')),
        for (final (index, link) in _customLinks.indexed)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BioLinkTile(
                  id: link.id,
                  icon: bioLinkIcon(link),
                  title: link.title,
                  subtitle: link.category.isEmpty
                      ? link.url
                      : '${link.category} • ${link.url}',
                  color: AppTheme.accentCyanInk,
                  enabled: _enabledLinkIds.contains(link.id),
                  featured: _appearance.featuredLinkId == link.id,
                  onChanged: _setLinkEnabled,
                  canEdit: _canEdit,
                  onEdit: () => _showEditLinkSheet(link),
                  menu: _linkMenu(index, link))),
        KeyedSubtree(
            key: const ValueKey('link-in-bio-add'),
            child: _AddLinkButton(onTap: _canEdit ? _showAddLinkSheet : null)),
      ]);

  Widget _themeStep() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('เลือกธีมที่ชอบ'),
        SizedBox(
            height: (MediaQuery.sizeOf(context).height * .17)
                .clamp(120.0, 150.0)
                .toDouble(),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SingleChildScrollView(child: _draftPreview()))),
        const SizedBox(height: 16),
        BioThemePicker(
            appearance: _appearance,
            enabled: _canEdit && !_isLoading,
            onChanged: (value) => setState(() {
                  _appearance = value;
                  _editVersion++;
                })),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            key: const ValueKey('link-in-bio-decorate'),
            onPressed: _canEdit && !_isLoading ? _decorate : null,
            icon: const Icon(Icons.tune),
            label: const Text('ตกแต่งเพิ่มเติม')),
      ]);

  Widget _overviewPreview() {
    final profile = _profile;
    if (profile == null || !profile.isPublished) return _draftPreview();
    return LinkInBioPreview(
        storeName: profile.storeName,
        slug: profile.slug,
        links: profile.links
            .map((link) => LinkInBioCustomLink(
                id: link.id,
                title: link.title,
                url: link.url,
                category: link.category,
                icon: link.icon,
                font: link.font,
                textColor: link.textColor,
                buttonColor: link.buttonColor))
            .toList(),
        appearance: profile.appearance,
        images: _images);
  }

  Widget _previewStep({required bool overview}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading(overview ? 'ตัวอย่างหน้าเว็บ' : 'ตรวจและเผยแพร่'),
        SizedBox(
            height:
                (MediaQuery.sizeOf(context).height * .4).clamp(220.0, 380.0),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SingleChildScrollView(
                    child: overview ? _overviewPreview() : _draftPreview()))),
        const SizedBox(height: 16),
        if (!overview) ...[
          const Text('ตรวจแบบร่างก่อนเผยแพร่ เมื่อพร้อมกดเผยแพร่ให้ลูกค้าเห็น'),
          TextButton(
              key: const ValueKey('link-in-bio-preview'),
              onPressed: _preview,
              child: const Text('ดูตัวอย่างเต็มหน้า')),
        ],
        if (overview &&
            !_publicationUncertain &&
            (_profile?.isPublished ?? false) &&
            _profile!.publicUrl != null)
          SelectableText(_profile!.publicUrl.toString(),
              key: const ValueKey('link-in-bio-public-url'),
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ]);

  Widget _more() => PopupMenuButton<String>(
      key: const ValueKey('link-in-bio-more'),
      tooltip: 'ตัวเลือกเพิ่มเติม',
      onSelected: (value) {
        switch (value) {
          case 'save':
            _saveDraft();
          case 'refresh':
            _loadProfile();
          case 'unpublish':
            _unpublish();
        }
      },
      itemBuilder: (_) => [
            PopupMenuItem(
                key: const ValueKey('link-in-bio-save-draft'),
                value: 'save',
                enabled: _canEdit,
                child: const Text('บันทึกแบบร่าง')),
            PopupMenuItem(
                key: const ValueKey('link-in-bio-refresh'),
                value: 'refresh',
                enabled: !_isLoading && !_isBusy,
                child: const Text('ตรวจสถานะเว็บไซต์')),
            if (_profile?.isPublished == true && !_publicationUncertain)
              PopupMenuItem(
                  key: const ValueKey('link-in-bio-unpublish'),
                  value: 'unpublish',
                  enabled: _canEdit && !_isLoading,
                  child: const Text('หยุดเผยแพร่')),
          ]);

  Widget _footer() {
    final ready = _canEdit && !_isLoading;
    final published = !_publicationUncertain &&
        (_profile?.isPublished ?? false) &&
        _profile!.publicUrl != null;
    return Padding(
        padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            widget.embeddedInTab && MediaQuery.viewInsetsOf(context).bottom == 0
                ? AppTheme.navOverlap
                : 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEditing) ...[
                SizedBox(
                    height: 52,
                    child: FilledButton(
                        key: const ValueKey('link-in-bio-edit-page'),
                        onPressed: ready ? () => _setStep(0) : null,
                        child: const Text('แก้ไขหน้าเว็บ'))),
                if (published) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            key: const ValueKey('link-in-bio-copy'),
                            onPressed: _canEdit ? _copyPublicUrl : null,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('คัดลอกลิงก์'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: OutlinedButton.icon(
                            key: const ValueKey('link-in-bio-open'),
                            onPressed: _canEdit ? _openPublicUrl : null,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('เปิดเว็บไซต์'))),
                  ]),
                ],
              ] else
                Row(children: [
                  if (_step > 0) ...[
                    Expanded(
                        child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                                key: const ValueKey('link-in-bio-previous'),
                                onPressed:
                                    ready ? () => _setStep(_step - 1) : null,
                                child: const Text('ย้อนกลับ')))),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                      flex: 2,
                      child: SizedBox(
                          height: 52,
                          child: _step == 3
                              ? FilledButton.icon(
                                  key: const ValueKey('link-in-bio-publish'),
                                  onPressed: ready && !_publicationUncertain
                                      ? _publish
                                      : null,
                                  icon: const Icon(Icons.public, size: 18),
                                  label: Text(_isBusy
                                      ? 'กำลังดำเนินการ...'
                                      : (_profile?.isPublished ?? false)
                                          ? 'อัปเดตหน้าเว็บไซต์'
                                          : 'เผยแพร่หน้าเว็บไซต์'))
                              : FilledButton(
                                  key: const ValueKey('link-in-bio-next'),
                                  onPressed: ready ? _next : null,
                                  child: const Text('ถัดไป')))),
                ]),
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final status = _publicationUncertain
        ? 'ยังไม่ทราบผล กรุณาตรวจสถานะ'
        : _isLoading
            ? 'กำลังตรวจสถานะ...'
            : (_profile?.isPublished ?? false)
                ? 'เผยแพร่แล้ว'
                : _hasConfirmedProfile
                    ? 'ยังไม่ได้เผยแพร่'
                    : 'ยังตรวจสถานะเว็บไซต์ไม่ได้';
    final body = DecoratedBox(
        decoration: AppTheme.screenBackground,
        child: SafeArea(
            top: !widget.embeddedInTab,
            bottom: !widget.embeddedInTab,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(children: [
                        IconButton(
                            key: ValueKey(_editorOpen && _profile != null
                                ? 'link-in-bio-close-editor'
                                : 'link-in-bio-back'),
                            tooltip: 'กลับ',
                            onPressed: !_canEdit
                                ? null
                                : () {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    if (_editorOpen && _profile != null) {
                                      setState(() => _editorOpen = false);
                                      _showStatus();
                                    } else if (_isEditing && _step > 0) {
                                      _setStep(_step - 1);
                                    } else {
                                      (widget.onBack ??
                                          () => Navigator.of(context)
                                              .maybePop())();
                                    }
                                  },
                            icon: const Icon(Icons.arrow_back)),
                        Expanded(
                            child: Text('ลิงก์หน้าโปรไฟล์',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary))),
                        _more(),
                      ])),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Text(status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary))),
                  if (_noticeMessage != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(_noticeMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.accentCyanInk)))),
                  Expanded(
                      child: SingleChildScrollView(
                          key: const ValueKey('link-in-bio-content'),
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_isEditing) _steps(),
                                if (_errorMessage != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Text(_errorMessage!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                if (_publicationUncertain ||
                                    (!_hasConfirmedProfile && !_isLoading))
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                          key: const ValueKey(
                                              'link-in-bio-retry'),
                                          onPressed: !_isLoading && !_isBusy
                                              ? _loadProfile
                                              : null,
                                          icon: const Icon(Icons.refresh),
                                          label:
                                              const Text('ตรวจสถานะอีกครั้ง'))),
                                if (_hasUnpublishedChanges)
                                  const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text(
                                          'มีการแก้ไขที่ยังไม่ได้เผยแพร่ เว็บไซต์ยังใช้ข้อมูลที่เผยแพร่ครั้งล่าสุด')),
                                if (_profile?.isPublished == true &&
                                    _slugController.text.trim() !=
                                        _profile!.slug)
                                  const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: Text(
                                          'เมื่อเผยแพร่ชื่อ URL ใหม่ ลิงก์เดิมจะเปิดไม่ได้ ต้องส่งลิงก์ใหม่ให้ลูกค้า')),
                                if (!_isEditing)
                                  _previewStep(overview: true)
                                else
                                  switch (_step) {
                                    0 => _info(),
                                    1 => _links(),
                                    2 => _themeStep(),
                                    _ => _previewStep(overview: false),
                                  },
                              ]))),
                  _footer(),
                ])));
    return widget.embeddedInTab
        ? Material(color: Colors.transparent, child: body)
        : Scaffold(backgroundColor: Colors.transparent, body: body);
  }
}

class _BioLinkTile extends StatelessWidget {
  const _BioLinkTile(
      {required this.id,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.enabled,
      required this.onChanged,
      required this.menu,
      this.onEdit,
      this.canEdit = true,
      this.featured = false});
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final void Function(String id, bool value) onChanged;
  final Widget menu;
  final VoidCallback? onEdit;
  final bool canEdit;
  final bool featured;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: AppTheme.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border)),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
            child: Tooltip(
                message: 'แก้ไขลิงก์',
                child: InkWell(
                    key: ValueKey('link-in-bio-edit-$id'),
                    onTap: canEdit ? onEdit : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary))),
                                if (featured)
                                  Icon(Icons.star,
                                      size: 16, color: AppTheme.accentCyanInk),
                              ]),
                              const SizedBox(height: 4),
                              Text(subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary)),
                            ]))))),
        Switch.adaptive(
            key: ValueKey('link-in-bio-toggle-$id'),
            value: enabled,
            onChanged: canEdit ? (value) => onChanged(id, value) : null),
        menu,
      ]));
}

class _AddLinkButton extends StatelessWidget {
  const _AddLinkButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'เพิ่มลิงก์',
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: _DashedRRectBorderPainter(
            color: AppTheme.border,
            radius: 13,
          ),
          child: SizedBox(
            height: 46,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_link, size: 19, color: AppTheme.accentCyanInk),
                const SizedBox(width: 7),
                Text(
                  'เพิ่มลิงก์',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentCyanInk,
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

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.radius,
  })  : dash = 7,
        gap = 6,
        strokeWidth = 1;

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

class _AddLinkSheet extends StatefulWidget {
  const _AddLinkSheet({
    this.initialLink,
  });

  final LinkInBioCustomLink? initialLink;

  @override
  State<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<_AddLinkSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _categoryController;
  late String _icon;
  String? _font;
  String? _textColor;
  String? _buttonColor;
  String? _errorMessage;
  final _linkAdvanced = ExpansibleController();
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialLink?.title);
    _urlController = TextEditingController(text: widget.initialLink?.url);
    _categoryController =
        TextEditingController(text: widget.initialLink?.category);
    _icon = widget.initialLink?.icon ?? 'auto';
    _font = widget.initialLink?.font;
    _textColor = widget.initialLink?.textColor;
    _buttonColor = widget.initialLink?.buttonColor;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _categoryController.dispose();
    _linkAdvanced.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) {
      _linkAdvanced.expand();
      return;
    }
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();
    final error = linkInBioLinkError(title, url);
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    Navigator.of(context).pop(LinkInBioCustomLink(
      id: widget.initialLink?.id ??
          'custom_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      url: url,
      category: _categoryController.text.trim(),
      icon: _icon,
      font: _font,
      textColor: _textColor,
      buttonColor: _buttonColor,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
            child: SizedBox(
                key: const ValueKey('link-in-bio-link-sheet'),
                height: (MediaQuery.sizeOf(context).height - bottomInset)
                    .clamp(
                        0.0,
                        _advancedOpen
                            ? MediaQuery.sizeOf(context).height * .86
                            : 430.0)
                    .toDouble(),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(children: [
                        Row(children: [
                          const Icon(Icons.add_link_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  widget.initialLink == null
                                      ? 'เพิ่มลิงก์ใหม่'
                                      : 'แก้ไขลิงก์',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700))),
                          IconButton(
                              tooltip: 'ปิด',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ]),
                        Expanded(
                            child: Form(
                                key: _form,
                                child: SingleChildScrollView(
                                    child: Column(children: [
                                  TextField(
                                      key: const ValueKey(
                                          'link-in-bio-link-title'),
                                      controller: _titleController,
                                      maxLength: 80,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                          labelText: 'ชื่อปุ่ม',
                                          hintText: 'เช่น คูปอง Shopee')),
                                  TextField(
                                      key: const ValueKey(
                                          'link-in-bio-link-url'),
                                      controller: _urlController,
                                      maxLength: 2048,
                                      keyboardType: TextInputType.url,
                                      decoration: const InputDecoration(
                                          labelText: 'URL ปลายทาง',
                                          hintText: 'https://...')),
                                  ExpansionTile(
                                    key: const ValueKey(
                                        'link-in-bio-link-advanced-disclosure'),
                                    controller: _linkAdvanced,
                                    maintainState: true,
                                    onExpansionChanged: (value) =>
                                        setState(() => _advancedOpen = value),
                                    tilePadding: EdgeInsets.zero,
                                    title: const Text('ตัวเลือกเพิ่มเติม',
                                        key: ValueKey(
                                            'link-in-bio-link-advanced')),
                                    children: [
                                      TextFormField(
                                          key: const ValueKey(
                                              'link-in-bio-link-category'),
                                          controller: _categoryController,
                                          maxLength: 60,
                                          validator: (value) => (value ?? '')
                                                      .trim()
                                                      .length >
                                                  60
                                              ? 'หมวดหมู่ยาวเกิน 60 ตัวอักษร'
                                              : null,
                                          decoration: const InputDecoration(
                                              labelText: 'หมวดหมู่',
                                              hintText:
                                                  'เช่น ช้อปสินค้า หรือ ติดต่อ')),
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<String>(
                                          key: const ValueKey(
                                              'link-in-bio-link-icon'),
                                          initialValue: _icon,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                              labelText: 'ไอคอน'),
                                          items: [
                                            for (final entry in const {
                                              'auto': 'เลือกจากลิงก์อัตโนมัติ',
                                              'link': 'ลิงก์',
                                              'shopee': 'Shopee',
                                              'lazada': 'Lazada',
                                              'line': 'LINE',
                                              'tiktok': 'TikTok',
                                              'youtube': 'YouTube',
                                              'instagram': 'Instagram',
                                              'facebook': 'Facebook'
                                            }.entries)
                                              DropdownMenuItem(
                                                  value: entry.key,
                                                  child: Text(entry.value))
                                          ],
                                          onChanged: (value) =>
                                              setState(() => _icon = value!)),
                                      const SizedBox(height: 16),
                                      const Text(
                                          'ปรับปุ่มนี้แยกจากธีมได้ หรือเว้นว่างเพื่อใช้ค่าของธีม'),
                                      const SizedBox(height: 10),
                                      BioFontField(
                                          key: const ValueKey(
                                              'link-in-bio-link-font'),
                                          label: 'ฟอนต์ปุ่มนี้',
                                          value: _font,
                                          allowDefault: true,
                                          onChanged: (value) =>
                                              setState(() => _font = value)),
                                      const SizedBox(height: 10),
                                      BioColorField(
                                          key: const ValueKey(
                                              'link-in-bio-link-text-color'),
                                          label: 'สีข้อความปุ่มนี้',
                                          value: _textColor,
                                          allowEmpty: true,
                                          onChanged: (value) => setState(
                                              () => _textColor = value)),
                                      const SizedBox(height: 10),
                                      BioColorField(
                                          key: const ValueKey(
                                              'link-in-bio-link-button-color'),
                                          label: 'สีพื้นปุ่มนี้',
                                          value: _buttonColor,
                                          allowEmpty: true,
                                          onChanged: (value) => setState(
                                              () => _buttonColor = value)),
                                    ],
                                  ),
                                ])))),
                        if (_errorMessage != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_errorMessage!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        const SizedBox(height: 10),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                                key: const ValueKey('link-in-bio-link-save'),
                                onPressed: _submit,
                                icon: const Icon(Icons.check),
                                label: const Text('บันทึกลิงก์'))),
                      ])),
                ))));
  }
}
