import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../storage.dart';

/// Encrypted password vault. Entries are AES-256-GCM blobs in Hive; the
/// 256-bit master key lives in secure storage. If a master password is set,
/// the key is wrapped with an HKDF-derived key so the vault is unreadable
/// without it — FxA sign-in is required to unlock, matching the Firefox
/// Lockwise model.
class VaultService extends ChangeNotifier {
  VaultService();

  static const _keySecret = 'vault_master_key';
  static const _wrappedKeySecret = 'vault_wrapped_key';
  static const _saltKey = 'vault_salt';
  static const _entriesKey = 'entries';

  List<VaultEntry> _entries = [];
  SecretKey? _key;
  bool _locked = true;
  bool _hasMasterPassword = false;

  bool get locked => _locked;
  bool get hasMasterPassword => _hasMasterPassword;
  List<VaultEntry> get entries => List.unmodifiable(_entries);

  Future<void> restore() async {
    _hasMasterPassword = await Storage.readSecret(_wrappedKeySecret) != null;
    final hasPlain = await Storage.readSecret(_keySecret) != null;
    if (!_hasMasterPassword && hasPlain) {
      _key = SecretKey(_b64(await Storage.readSecret(_keySecret)));
      _locked = false;
      await _loadEntries();
    }
    notifyListeners();
  }

  /// First-run: generates a master key. Call after FxA sign-in or when the
  /// user enables the vault without a password.
  Future<void> ensureKey() async {
    if (_key != null) return;
    final existing = await Storage.readSecret(_keySecret);
    if (existing != null) {
      _key = SecretKey(_b64(existing));
    } else {
      final key = SecretKeyData.random(length: 32).bytes;
      await Storage.writeSecret(_keySecret, _b64e(key));
      _key = SecretKey(key);
    }
    _locked = false;
    await _loadEntries();
    notifyListeners();
  }

  /// Wraps the master key with a key derived from [password].
  Future<void> setMasterPassword(String password) async {
    await ensureKey();
    final salt = SecretKeyData.random(length: 16).bytes;
    final wrap = await _deriveWrapKey(password, salt);
    final raw = await _key!.extract();
    final sealed = await _seal(utf8.encode(_b64e(raw.bytes)), wrap);
    await Storage.writeSecret(_wrappedKeySecret, sealed);
    await Storage.writeSecret(_saltKey, _b64e(salt));
    await Storage.deleteSecret(_keySecret);
    _hasMasterPassword = true;
    notifyListeners();
  }

  Future<bool> unlock(String password) async {
    final wrapped = await Storage.readSecret(_wrappedKeySecret);
    final saltRaw = await Storage.readSecret(_saltKey);
    if (wrapped == null || saltRaw == null) {
      await ensureKey();
      return true;
    }
    try {
      final wrap = await _deriveWrapKey(password, _b64(saltRaw));
      final plain = await _open(wrapped, wrap);
      _key = SecretKey(_b64(utf8.decode(plain)));
      _locked = false;
      await _loadEntries();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// FxA unlock path: the signed-in account is the auth factor, so the key
  /// only needs secure storage.
  Future<bool> unlockWithAccount() async {
    if (_hasMasterPassword) return false;
    await ensureKey();
    return true;
  }

  void lock() {
    _locked = true;
    _entries = [];
    if (_hasMasterPassword) _key = null;
    notifyListeners();
  }

  Future<void> upsert(VaultEntry entry) async {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      _entries[i] = entry;
    } else {
      _entries.add(entry);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  List<VaultEntry> forOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host ?? origin;
    return _entries
        .where((e) => e.host == host || e.host.endsWith('.$host'))
        .toList();
  }

  Future<void> _persist() async {
    final key = _key;
    if (key == null) return;
    final plain =
        jsonEncode(_entries.map((e) => e.toJson()).toList());
    Storage.write(Storage.vault, _entriesKey, await _seal(utf8.encode(plain), key));
  }

  Future<void> _loadEntries() async {
    final key = _key;
    if (key == null) return;
    final sealed = Storage.read(Storage.vault, _entriesKey);
    if (sealed == null) {
      _entries = [];
      return;
    }
    try {
      final plain = await _open(sealed, key);
      final list = jsonDecode(utf8.decode(plain)) as List;
      _entries = list
          .map((e) => VaultEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      _entries = [];
    }
  }

  /// Encrypted payload for sync (round-trips through SyncRecord.payload).
  Future<String?> exportEncrypted() async {
    return Storage.read(Storage.vault, _entriesKey);
  }

  static Future<SecretKey> _deriveWrapKey(
      String password, List<int> salt) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    // Stretch the password before HKDF extract.
    final stretched = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    return hkdf.deriveKey(
        secretKey: stretched, nonce: salt, info: utf8.encode('wave-vault'));
  }

  static Future<String> _seal(List<int> plain, SecretKey key) async {
    final aes = AesGcm.with256bits();
    final box =
        await aes.encrypt(plain, secretKey: key, aad: utf8.encode('wave'));
    return _b64e(box.concatenation());
  }

  static Future<List<int>> _open(String sealed, SecretKey key) async {
    final aes = AesGcm.with256bits();
    final box =
        SecretBox.fromConcatenation(_b64(sealed), nonceLength: 12, macLength: 16);
    return aes.decrypt(box, secretKey: key, aad: utf8.encode('wave'));
  }

  static String generatePassword({int length = 18}) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#%^&*()-_=+';
    const all = upper + lower + digits + symbols;
    final r = Random.secure();
    String pick(String set) => set[r.nextInt(set.length)];
    final chars = <String>[
      pick(upper), pick(lower), pick(digits), pick(symbols),
      for (var i = 4; i < length; i++) pick(all),
    ]..shuffle(r);
    return chars.join();
  }

  static List<int> _b64(String? s) =>
      s == null ? [] : base64.decode(s);
  static String _b64e(List<int> b) => base64.encode(b);
}
