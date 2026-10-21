import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';

class AddonPendingDataException implements Exception {
  const AddonPendingDataException(
      [this.message =
          'ข้อมูลการซื้อที่รอยืนยันไม่พร้อมใช้งาน กรุณาติดต่อฝ่ายช่วยเหลือ']);
  final String message;
}

class AddonPendingConflictException extends AddonPendingDataException {
  const AddonPendingConflictException()
      : super(
            'มีรายการซื้อเดิมรอยืนยัน กรุณาตรวจสอบรายการเดิมก่อนซื้ออีกครั้ง');
}

class AddonPendingRecord {
  AddonPendingRecord(
      {required this.productId,
      required this.intentId,
      this.transactionId,
      this.transactionIdKind = 'STORE',
      List<String>? baselineTransactionIds})
      : baselineTransactionIds = baselineTransactionIds == null
            ? null
            : List<String>.unmodifiable(baselineTransactionIds) {
    if (!_validId(productId, 256) ||
        !_validId(intentId, 128) ||
        (transactionIdKind != 'STORE' && transactionIdKind != 'REVENUECAT') ||
        (transactionId == null && transactionIdKind != 'STORE') ||
        (transactionId != null && !_validId(transactionId!, 512)) ||
        (this.baselineTransactionIds != null &&
            (this.baselineTransactionIds!.length > 10000 ||
                this.baselineTransactionIds!.any((id) => !_validId(id, 512)) ||
                this.baselineTransactionIds!.toSet().length !=
                    this.baselineTransactionIds!.length))) {
      throw const AddonPendingDataException();
    }
  }

  final String productId;
  final String intentId;
  final String? transactionId;
  final String transactionIdKind;
  final List<String>? baselineTransactionIds;
  static bool _validId(String value, int length) =>
      value.isNotEmpty && value.length <= length && value.trim() == value;

  Map<String, Object?> toJson() => {
        'version': 1,
        'productId': productId,
        'intentId': intentId,
        if (transactionId != null) 'transactionId': transactionId,
        if (transactionId != null) 'transactionIdKind': transactionIdKind,
        if (baselineTransactionIds != null)
          'baselineTransactionIds': baselineTransactionIds,
      };

  factory AddonPendingRecord.fromJson(Map<String, Object?> json) {
    const allowed = {
      'version',
      'productId',
      'intentId',
      'transactionId',
      'transactionIdKind',
      'baselineTransactionIds'
    };
    final baseline = json['baselineTransactionIds'];
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json['version'] != 1 ||
        json['productId'] is! String ||
        json['intentId'] is! String ||
        (json.containsKey('transactionId') &&
            json['transactionId'] is! String) ||
        (json.containsKey('transactionIdKind') &&
            json['transactionIdKind'] is! String) ||
        (json.containsKey('baselineTransactionIds') &&
            (baseline is! List || baseline.any((value) => value is! String)))) {
      throw const AddonPendingDataException();
    }
    return AddonPendingRecord(
        productId: json['productId'] as String,
        intentId: json['intentId'] as String,
        transactionId: json['transactionId'] as String?,
        transactionIdKind: json['transactionIdKind'] as String? ?? 'STORE',
        baselineTransactionIds:
            baseline == null ? null : List<String>.from(baseline as List));
  }
}

abstract class AddonPendingStore {
  Future<AddonPendingRecord?> load();
  Future<void> save(AddonPendingRecord record);
  Future<void> clear({required String intentId});
}

void _assertSameIntent(AddonPendingRecord? current, AddonPendingRecord next) {
  if (current != null &&
      (current.intentId != next.intentId ||
          current.productId != next.productId ||
          (current.transactionId != null &&
              (current.transactionId != next.transactionId ||
                  current.transactionIdKind != next.transactionIdKind)))) {
    throw const AddonPendingConflictException();
  }
}

class InMemoryAddonPendingStore implements AddonPendingStore {
  InMemoryAddonPendingStore({AddonPendingRecord? initialRecord})
      : _record = initialRecord;
  AddonPendingRecord? _record;
  @override
  Future<AddonPendingRecord?> load() async => _record;
  @override
  Future<void> save(AddonPendingRecord record) async {
    _assertSameIntent(_record, record);
    _record = record;
  }

  @override
  Future<void> clear({required String intentId}) async {
    if (_record?.intentId == intentId) _record = null;
  }
}

/// Retains a payment intent and receipt across process restarts. Each exact
/// API/account scope has one serialized claim; no auth credentials are stored.
class SharedPreferencesAddonPendingStore implements AddonPendingStore {
  SharedPreferencesAddonPendingStore(
      {PostDeeAuthSessionStore? sessionStore,
      String? apiBaseUrl,
      SharedPreferences? preferences,
      Future<SharedPreferences> Function()? loadPreferences})
      : _sessions = sessionStore ?? PostDeeAuthSessionStore.instance,
        _binding =
            (sessionStore ?? PostDeeAuthSessionStore.instance).captureSession(),
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl,
        _preferences = preferences,
        _loadPreferences = loadPreferences;

  final PostDeeAuthSessionStore _sessions;
  final AuthSessionBinding _binding;
  final String _apiBaseUrl;
  final SharedPreferences? _preferences;
  final Future<SharedPreferences> Function()? _loadPreferences;
  static final Map<String, Future<void>> _tails = {};

  void _requireCurrent() {
    _binding.ensureCurrent();
    final owner = _binding.userId;
    if (owner == null ||
        owner.isEmpty ||
        owner.trim() != owner ||
        !_sessions.session.isSignedIn ||
        _sessions.session.stableUserId != owner) {
      throw const AuthSessionChangedException();
    }
    if (_apiBaseUrl.isEmpty || _apiBaseUrl.trim() != _apiBaseUrl) {
      throw const AddonPendingDataException();
    }
  }

  String get _key {
    _requireCurrent();
    return 'postdee.addon_pending.v1.${base64Url.encode(utf8.encode(jsonEncode([
              _apiBaseUrl,
              _binding.userId
            ]))).replaceAll('=', '')}';
  }

  Future<T> _serialize<T>(
      FutureOr<T> Function(SharedPreferences) action) async {
    final key = _key;
    final previous = _tails[key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      _requireCurrent();
      final preferences = _preferences ??
          await (_loadPreferences ?? SharedPreferences.getInstance)();
      _requireCurrent();
      await preferences.reload();
      _requireCurrent();
      final result = await action(preferences);
      _requireCurrent();
      return result;
    });
    final tail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    try {
      return await operation;
    } finally {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }
  }

  AddonPendingRecord? _read(SharedPreferences preferences) {
    try {
      final raw = preferences.getString(_key);
      if (raw == null) return null;
      if (raw.length > 6 * 1024 * 1024) throw const AddonPendingDataException();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const AddonPendingDataException();
      }
      return AddonPendingRecord.fromJson(decoded);
    } on FormatException {
      throw const AddonPendingDataException();
    } on TypeError {
      throw const AddonPendingDataException();
    }
  }

  @override
  Future<AddonPendingRecord?> load() => _serialize(_read);

  @override
  Future<void> save(AddonPendingRecord record) =>
      _serialize((preferences) async {
        _assertSameIntent(_read(preferences), record);
        _requireCurrent();
        if (!await preferences.setString(_key, jsonEncode(record.toJson()))) {
          throw const AddonPendingDataException();
        }
        _requireCurrent();
      });

  @override
  Future<void> clear({required String intentId}) =>
      _serialize((preferences) async {
        if (_read(preferences)?.intentId != intentId) return;
        _requireCurrent();
        if (!await preferences.remove(_key)) {
          throw const AddonPendingDataException();
        }
        _requireCurrent();
      });

  /// Called only after the server has confirmed deletion of this account.
  /// Ordinary purchase recovery cannot discard a corrupt pending marker.
  Future<void> clearForDeletedAccount() => _serialize((preferences) async {
        _requireCurrent();
        if (!await preferences.remove(_key)) {
          throw const AddonPendingDataException();
        }
        _requireCurrent();
      });
}
