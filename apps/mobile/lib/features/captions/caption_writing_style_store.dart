import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/caption_writing_style.dart';

abstract interface class CaptionWritingStyleStore {
  Future<CaptionWritingStyleProfile> load(String ownerUserId);
  Future<void> save(String ownerUserId, CaptionWritingStyleProfile profile);
  Future<void> clear(String ownerUserId);
}

class SharedPreferencesCaptionWritingStyleStore
    implements CaptionWritingStyleStore {
  const SharedPreferencesCaptionWritingStyleStore({
    SharedPreferences? preferences,
    PostDeeAuthSessionStore? sessionStore,
    Future<SharedPreferences> Function()? loadPreferences,
  })  : _preferences = preferences,
        _sessionStore = sessionStore,
        _loadPreferences = loadPreferences;

  final SharedPreferences? _preferences;
  final PostDeeAuthSessionStore? _sessionStore;
  final Future<SharedPreferences> Function()? _loadPreferences;
  static int _deletionGeneration = 0;
  static final Map<String, Future<void>> _ownerMutationTails = {};

  AuthSession get _session =>
      (_sessionStore ?? PostDeeAuthSessionStore.instance).session;
  String _key(String owner) =>
      'postdee.caption_writing_style.v1.${Uri.encodeComponent(owner)}';
  Future<SharedPreferences> get _activePreferences async =>
      _preferences ??
      await (_loadPreferences ?? SharedPreferences.getInstance)();

  void _requireOwner(String owner, int deletionGeneration) {
    if (owner.isEmpty ||
        !_session.isSignedIn ||
        _session.stableUserId != owner ||
        deletionGeneration != _deletionGeneration) {
      throw const AuthSessionChangedException();
    }
  }

  Future<void> _serializeOwnerMutation(
    String owner,
    Future<void> Function() mutation,
  ) {
    final previous = _ownerMutationTails[owner] ?? Future<void>.value();
    final operation = previous.then((_) => mutation());
    // A failed write must not prevent a later clear from reaching storage.
    final tail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _ownerMutationTails[owner] = tail;
    return operation.whenComplete(() {
      if (identical(_ownerMutationTails[owner], tail)) {
        _ownerMutationTails.remove(owner);
      }
    });
  }

  @override
  Future<CaptionWritingStyleProfile> load(String ownerUserId) async {
    final generation = _deletionGeneration;
    _requireOwner(ownerUserId, generation);
    final preferences = await _activePreferences;
    _requireOwner(ownerUserId, generation);
    final value = preferences.getString(_key(ownerUserId));
    if (value == null) return const CaptionWritingStyleProfile();
    try {
      final json = jsonDecode(value);
      if (json is! Map) return const CaptionWritingStyleProfile();
      return CaptionWritingStyleProfile.fromJson(
          Map<String, Object?>.from(json));
    } on FormatException {
      return const CaptionWritingStyleProfile();
    } on TypeError {
      return const CaptionWritingStyleProfile();
    }
  }

  @override
  Future<void> save(
      String ownerUserId, CaptionWritingStyleProfile profile) async {
    final generation = _deletionGeneration;
    _requireOwner(ownerUserId, generation);
    final value = jsonEncode(profile.toJson());
    final preferences = await _activePreferences;
    _requireOwner(ownerUserId, generation);
    await _serializeOwnerMutation(ownerUserId, () async {
      _requireOwner(ownerUserId, generation);
      if (!await preferences.setString(_key(ownerUserId), value)) {
        throw StateError('Caption writing style could not be saved');
      }
      _requireOwner(ownerUserId, generation);
    });
  }

  @override
  Future<void> clear(String ownerUserId) async {
    _requireOwner(ownerUserId, _deletionGeneration);
    final generation = ++_deletionGeneration;
    final preferences = await _activePreferences;
    _requireOwner(ownerUserId, generation);
    await _serializeOwnerMutation(ownerUserId, () async {
      _requireOwner(ownerUserId, generation);
      if (!await preferences.remove(_key(ownerUserId))) {
        throw StateError('Caption writing style could not be cleared');
      }
      _requireOwner(ownerUserId, generation);
    });
  }

  /// Called only after account DELETE succeeds, with the owner captured before
  /// the request. The auth session may already have been revoked by that point.
  Future<void> clearForDeletedAccount(String capturedOwnerUserId) async {
    if (capturedOwnerUserId.trim().isEmpty) {
      throw ArgumentError.value(capturedOwnerUserId, 'capturedOwnerUserId');
    }
    _deletionGeneration++;
    final preferences = await _activePreferences;
    await _serializeOwnerMutation(capturedOwnerUserId, () async {
      if (!await preferences.remove(_key(capturedOwnerUserId))) {
        throw StateError(
            'Deleted account caption writing style could not be cleared');
      }
    });
  }
}
