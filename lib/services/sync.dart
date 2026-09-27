import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../storage.dart';
import 'fxa.dart';

/// One record in a sync collection. Last-writer-wins on [modified].
class SyncRecord {
  SyncRecord({required this.id, required this.payload, required this.modified});

  final String id;
  final String payload;
  final double modified;

  Map<String, dynamic> toJson() =>
      {'id': id, 'payload': payload, 'modified': modified};

  factory SyncRecord.fromJson(Map<String, dynamic> j) => SyncRecord(
        id: j['id'] as String,
        payload: j['payload'] as String? ?? '',
        modified: (j['modified'] as num?)?.toDouble() ?? 0,
      );
}

/// Where collections physically go. Three backends ship:
/// - [FxaSyncBackend]: real Firefox Sync storage (tokenserver + Hawk + BSO),
///   active when the OAuth client holds the oldsync scope.
/// - [SelfHostedSyncBackend]: a plain JSON blob relay you run yourself.
/// - [LocalSyncBackend]: JSONL files in the app data dir, default so sync
///   state is always exerciseable offline.
abstract class SyncBackend {
  String get id;
  String get label;
  bool get ready;

  /// Returns the server-timestamp cursor after write, or 0 on failure.
  Future<double> upload(String collection, List<SyncRecord> records);
  Future<List<SyncRecord>> download(String collection, {double since = 0});
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => 'SyncException: $message';
}

// ---------------------------------------------------------------------------
// Local backend
// ---------------------------------------------------------------------------

class LocalSyncBackend extends SyncBackend {
  @override
  String get id => 'local';
  @override
  String get label => 'Local files';
  @override
  bool get ready => true;

  Future<File> _file(String collection) async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/sync/$collection.jsonl');
    await f.parent.create(recursive: true);
    return f;
  }

  @override
  Future<double> upload(String collection, List<SyncRecord> records) async {
    final f = await _file(collection);
    final existing = await download(collection);
    final map = {for (final r in existing) r.id: r};
    for (final r in records) {
      final cur = map[r.id];
      if (cur == null || r.modified >= cur.modified) map[r.id] = r;
    }
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    await f.writeAsString(
        '${map.values.map((r) => jsonEncode(r.toJson())).join('\n')}\n');
    return now;
  }

  @override
  Future<List<SyncRecord>> download(String collection,
      {double since = 0}) async {
    final f = await _file(collection);
    if (!await f.exists()) return [];
    final out = <SyncRecord>[];
    for (final line in await f.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final r = SyncRecord.fromJson(jsonDecode(line));
        if (r.modified > since) out.add(r);
      } catch (_) {}
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Self-hosted backend: trivial JSON relay.
// PUT  {base}/v1/{collection}  {records:[...]}  -> {modified: ts}
// GET  {base}/v1/{collection}?since=ts          -> {records:[...]}
// Compatible with any relay implementing those two endpoints.
// ---------------------------------------------------------------------------

class SelfHostedSyncBackend extends SyncBackend {
  SelfHostedSyncBackend({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  @override
  String get id => 'selfhosted';
  @override
  String get label => 'Self-hosted relay';
  @override
  bool get ready => baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  @override
  Future<double> upload(String collection, List<SyncRecord> records) async {
    final res = await http.put(
      Uri.parse('$baseUrl/v1/$collection'),
      headers: _headers,
      body: jsonEncode({
        'records': records.map((r) => r.toJson()).toList(),
      }),
    );
    if (res.statusCode ~/ 100 != 2) {
      throw SyncException('relay upload failed (${res.statusCode})');
    }
    return (jsonDecode(res.body)['modified'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<List<SyncRecord>> download(String collection,
      {double since = 0}) async {
    final res = await http.get(
      Uri.parse('$baseUrl/v1/$collection?since=$since'),
      headers: _headers,
    );
    if (res.statusCode ~/ 100 != 2) {
      throw SyncException('relay download failed (${res.statusCode})');
    }
    final list = (jsonDecode(res.body)['records'] as List?) ?? [];
    return list
        .map((e) => SyncRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// FxA backend: the real Firefox Sync storage protocol (sync-1.5).
// tokenserver -> Hawk-signed BSO reads/writes -> AES-256-CBC+HMAC payloads.
// ---------------------------------------------------------------------------

class FxaSyncBackend extends SyncBackend {
  FxaSyncBackend(this.fxa);

  final FxaService fxa;
  String? _apiEndpoint;
  String? _hawkId;
  String? _hawkKey;
  double _nodeExpiry = 0;

  @override
  String get id => 'fxa';
  @override
  String get label => 'Firefox Sync';
  @override
  bool get ready => fxa.hasSyncScope;

  Future<void> _ensureNode() async {
    if (_apiEndpoint != null &&
        DateTime.now().millisecondsSinceEpoch / 1000 < _nodeExpiry - 60) {
      return;
    }
    final token = await fxa.accessToken();
    final kid = fxa.scopedKey?['kid'];
    final res = await http.get(
      Uri.parse('${fxa.endpoints.tokenServerUrl}/1.0/sync/1.5'),
      headers: {
        'Authorization': 'Bearer $token',
        if (kid != null) 'X-KeyID': kid.toString(),
      },
    );
    if (res.statusCode != 200) {
      throw SyncException('tokenserver rejected (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _apiEndpoint = j['api_endpoint'] as String;
    _hawkId = j['id'] as String;
    _hawkKey = j['key'] as String;
    _nodeExpiry = DateTime.now().millisecondsSinceEpoch / 1000 +
        (j['duration'] as num? ?? 3600);
  }

  /// Hawk request-signing per the sync-1.5 storage spec.
  String _hawkHeader(String method, Uri uri, {String? body}) {
    final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final nonce = _nonce();
    var payloadHash = '';
    if (body != null) {
      final h = sha256.convert(utf8.encode(
          'hawk.1.payload\napplication/json\n$body\n'));
      payloadHash = base64.encode(h.bytes);
    }
    final normalized = 'hawk.1.header\n'
        '$ts\n$nonce\n$method\n'
        '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}\n'
        '${uri.host}\n${uri.port == 443 || uri.port == 80 ? 443 : uri.port}\n'
        '$payloadHash\n\n';
    final mac = Hmac(sha256, utf8.encode(_hawkKey!))
        .convert(utf8.encode(normalized));
    return 'Hawk id="$_hawkId", ts="$ts", nonce="$nonce", '
        'mac="${base64.encode(mac.bytes)}"'
        '${payloadHash.isNotEmpty ? ', hash="$payloadHash"' : ''}';
  }

  static String _nonce() {
    const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(8, (_) => c[r.nextInt(c.length)]).join();
  }

  /// Derives the sync-1.5 crypto bundle (enc + hmac) from kB via HKDF.
  Future<List<int>> _syncKeyBundle(List<int> info) async {
    final kb = fxa.scopedKey?['kB'] as String?;
    if (kb == null) throw SyncException('no kB in scoped key');
    final raw = _hexDecode(kb);
    final hkdf = cg.Hkdf(hmac: cg.Hmac.sha256(), outputLength: 64);
    final out = await hkdf.deriveKey(
        secretKey: cg.SecretKey(raw),
        nonce: const [],
        info: info);
    return (await out.extract()).bytes;
  }

  static List<int> _hexDecode(String s) => [
        for (var i = 0; i + 1 < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ];

  /// Encrypts a plaintext payload into a sync-1.5 BSO payload object.
  Future<String> _encryptPayload(String plaintext) async {
    final bundle = await _syncKeyBundle(utf8.encode(''));
    final encKey = bundle.sublist(0, 32);
    final hmacKey = bundle.sublist(32, 64);
    final aes = cg.AesCbc.with256bits(
        macAlgorithm: cg.MacAlgorithm.empty);
    final nonce = cg.SecretKeyData.random(length: 16);
    final box = await aes.encrypt(utf8.encode(plaintext),
        secretKey: cg.SecretKey(encKey), nonce: nonce.bytes);
    final mac = Hmac(sha256, hmacKey).convert(box.cipherText);
    return jsonEncode({
      'ciphertext': base64.encode(box.cipherText),
      'IV': base64.encode(nonce.bytes),
      'hmac': _hexEncode(mac.bytes),
    });
  }

  Future<String?> _decryptPayload(String bsoPayload) async {
    try {
      final j = jsonDecode(bsoPayload) as Map<String, dynamic>;
      final bundle = await _syncKeyBundle(utf8.encode(''));
      final encKey = bundle.sublist(0, 32);
      final hmacKey = bundle.sublist(32, 64);
      final ct = base64.decode(j['ciphertext'] as String);
      final expected = _hexEncode(Hmac(sha256, hmacKey).convert(ct).bytes);
      if (expected != j['hmac']) return null;
      final aes = cg.AesCbc.with256bits(
          macAlgorithm: cg.MacAlgorithm.empty);
      final clear = await aes.decrypt(
        cg.SecretBox(ct,
            nonce: base64.decode(j['IV'] as String), mac: cg.Mac.empty),
        secretKey: cg.SecretKey(encKey),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  static String _hexEncode(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<double> upload(String collection, List<SyncRecord> records) async {
    await _ensureNode();
    final uri = Uri.parse('$_apiEndpoint/storage/$collection');
    final encoded = <Map<String, dynamic>>[];
    for (final r in records) {
      encoded.add({
        'id': r.id,
        'payload': await _encryptPayload(r.payload),
        'ttl': null,
      });
    }
    final body = jsonEncode(encoded);
    final res = await http.post(uri,
        headers: {
          'Authorization': _hawkHeader('POST', uri, body: body),
          'Content-Type': 'application/json',
        },
        body: body);
    if (res.statusCode ~/ 100 != 2) {
      throw SyncException('fxa upload failed (${res.statusCode})');
    }
    return (jsonDecode(res.body)['modified'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<List<SyncRecord>> download(String collection,
      {double since = 0}) async {
    await _ensureNode();
    final uri = Uri.parse(
        '$_apiEndpoint/storage/$collection?newer=$since&full=1');
    final res = await http.get(uri,
        headers: {'Authorization': _hawkHeader('GET', uri)});
    if (res.statusCode != 200) {
      throw SyncException('fxa download failed (${res.statusCode})');
    }
    final out = <SyncRecord>[];
    for (final line in res.body.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final bso = jsonDecode(line) as Map<String, dynamic>;
        final payload = await _decryptPayload(bso['payload'] as String);
        if (payload != null) {
          out.add(SyncRecord(
            id: bso['id'] as String,
            payload: payload,
            modified: (bso['modified'] as num?)?.toDouble() ?? 0,
          ));
        }
      } catch (_) {}
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Engine: serializes app collections, merges, pushes/pulls, tracks cursors.
// ---------------------------------------------------------------------------

enum SyncStatus { idle, syncing, error, disabled }

class SyncService extends ChangeNotifier {
  SyncService(this.fxa);

  final FxaService fxa;
  final LocalSyncBackend local = LocalSyncBackend();

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSyncAt;

  static const collections = ['bookmarks', 'history', 'passwords', 'tabs'];

  static const _backendKey = 'sync_backend';
  static const _relayUrlKey = 'sync_relay_url';
  static const _relayTokenKey = 'sync_relay_token';
  static const _cursorKey = 'sync_cursor_';
  static const _lastKey = 'sync_last';

  SyncBackend get backend {
    final choice = Storage.read(Storage.settings, _backendKey) ?? 'auto';
    switch (choice) {
      case 'selfhosted':
        return SelfHostedSyncBackend(
          baseUrl: Storage.read(Storage.settings, _relayUrlKey) ?? '',
          token: Storage.read(Storage.settings, _relayTokenKey) ?? '',
        );
      case 'local':
        return local;
      case 'fxa':
        return FxaSyncBackend(fxa);
      case 'auto':
      default:
        if (fxa.hasSyncScope) return FxaSyncBackend(fxa);
        final relay = Storage.read(Storage.settings, _relayUrlKey);
        if (relay != null && relay.isNotEmpty) {
          return SelfHostedSyncBackend(
            baseUrl: relay,
            token: Storage.read(Storage.settings, _relayTokenKey) ?? '',
          );
        }
        return local;
    }
  }

  String get backendChoice =>
      Storage.read(Storage.settings, _backendKey) ?? 'auto';

  void setBackendChoice(String v) {
    Storage.write(Storage.settings, _backendKey, v);
    notifyListeners();
  }

  void configureRelay(String url, String token) {
    Storage.write(Storage.settings, _relayUrlKey, url);
    Storage.write(Storage.settings, _relayTokenKey, token);
    notifyListeners();
  }

  String? get relayUrl => Storage.read(Storage.settings, _relayUrlKey);

  void restore() {
    final raw = Storage.read(Storage.settings, _lastKey);
    if (raw != null) lastSyncAt = DateTime.tryParse(raw);
  }

  /// Full sync pass: pull remote changes, merge, push local. The caller
  /// supplies the current local records per collection and receives the
  /// merged set back to apply.
  Future<Map<String, List<SyncRecord>>> syncCollections(
      Map<String, List<SyncRecord>> localCollections) async {
    final b = backend;
    if (!b.ready) {
      status = SyncStatus.disabled;
      lastError = 'no backend ready';
      notifyListeners();
      return localCollections;
    }
    status = SyncStatus.syncing;
    lastError = null;
    notifyListeners();
    final merged = <String, List<SyncRecord>>{};
    try {
      for (final collection in collections) {
        final local = localCollections[collection] ?? [];
        final cursorRaw =
            Storage.read(Storage.sync, '$_cursorKey$collection');
        final since = double.tryParse(cursorRaw ?? '0') ?? 0;
        final remote = await b.download(collection, since: since);

        final byId = {for (final r in local) r.id: r};
        for (final r in remote) {
          final cur = byId[r.id];
          if (cur == null || r.modified >= cur.modified) {
            byId[r.id] = r;
          }
        }
        final combined = byId.values.toList()
          ..sort((a, c) => a.modified.compareTo(c.modified));
        merged[collection] = combined;
        final ts = await b.upload(collection, combined);
        Storage.write(Storage.sync, '$_cursorKey$collection', '$ts');
      }
      lastSyncAt = DateTime.now();
      Storage.write(
          Storage.settings, _lastKey, lastSyncAt!.toIso8601String());
      status = SyncStatus.idle;
    } on SyncException catch (e) {
      status = SyncStatus.error;
      lastError = e.message;
    } catch (e) {
      status = SyncStatus.error;
      lastError = e.toString();
    }
    notifyListeners();
    return merged;
  }
}
