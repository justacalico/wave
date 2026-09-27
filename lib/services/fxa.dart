import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../storage.dart';

/// Server endpoints. Defaults are Mozilla production; every one can point at
/// a self-hosted FxA stack (mozilla/fxa monorepo) instead.
class FxaEndpoints {
  const FxaEndpoints({
    this.contentUrl = 'https://accounts.firefox.com',
    this.oauthUrl = 'https://oauth.accounts.firefox.com/v1',
    this.profileUrl = 'https://profile.accounts.firefox.com/v1',
    this.tokenServerUrl = 'https://token.services.mozilla.com',
  });

  final String contentUrl;
  final String oauthUrl;
  final String profileUrl;
  final String tokenServerUrl;

  Uri get authorization => Uri.parse('$contentUrl/authorization');
  Uri get token => Uri.parse('$oauthUrl/token');
  Uri get keys => Uri.parse('$oauthUrl/keys');
  Uri get destroy => Uri.parse('$oauthUrl/destroy');
  Uri get profile => Uri.parse('$profileUrl/profile');
  Uri get device => Uri.parse('$contentUrl/v1/account/device');

  Map<String, dynamic> toJson() => {
        'contentUrl': contentUrl,
        'oauthUrl': oauthUrl,
        'profileUrl': profileUrl,
        'tokenServerUrl': tokenServerUrl,
      };

  factory FxaEndpoints.fromJson(Map<String, dynamic> j) => FxaEndpoints(
        contentUrl: j['contentUrl'] as String? ??
            'https://accounts.firefox.com',
        oauthUrl: j['oauthUrl'] as String? ??
            'https://oauth.accounts.firefox.com/v1',
        profileUrl: j['profileUrl'] as String? ??
            'https://profile.accounts.firefox.com/v1',
        tokenServerUrl: j['tokenServerUrl'] as String? ??
            'https://token.services.mozilla.com',
      );
}

class FxaTokens {
  FxaTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    required this.expiresAt,
    this.scopedKey,
  });

  String accessToken;
  String? refreshToken;
  String? idToken;
  DateTime expiresAt;

  /// Decrypted oldsync bundle (kA/kB) when the scope was granted.
  Map<String, dynamic>? scopedKey;

  bool get expired => DateTime.now().isAfter(
      expiresAt.subtract(const Duration(seconds: 30)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'expiresAt': expiresAt.toIso8601String(),
        'scopedKey': scopedKey,
      };

  factory FxaTokens.fromJson(Map<String, dynamic> j) => FxaTokens(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String?,
        idToken: j['idToken'] as String?,
        expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? '') ??
            DateTime.now(),
        scopedKey:
            (j['scopedKey'] as Map?)?.cast<String, dynamic>(),
      );
}

/// Firefox Accounts sign-in over OAuth2 + PKCE, the same flow Firefox
/// browsers use. The OAuth client_id is injectable (`FXA_CLIENT_ID`
/// dart-define or the settings screen) because Mozilla hands ids out per
/// partner rather than self-service.
class FxaService extends ChangeNotifier {
  FxaService({FxaEndpoints? endpoints})
      : endpoints = endpoints ?? const FxaEndpoints();

  /// Override at build time: `--dart-define=FXA_CLIENT_ID=...`
  static const _definedClientId =
      String.fromEnvironment('FXA_CLIENT_ID', defaultValue: '');

  static const _tokenKey = 'fxa_tokens';
  static const _profileKey = 'fxa_profile';
  static const _endpointsKey = 'fxa_endpoints';
  static const _clientIdKey = 'fxa_client_id';

  FxaEndpoints endpoints;
  FxAProfile? profile;
  FxaTokens? _tokens;
  bool _signingIn = false;
  String? _lastError;
  HttpServer? _loopback;

  bool get signedIn => profile != null && _tokens != null;
  bool get signingIn => _signingIn;
  String? get lastError => _lastError;

  String get clientId {
    final stored = Storage.read(Storage.settings, _clientIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    return _definedClientId;
  }

  set clientId(String v) {
    Storage.write(Storage.settings, _clientIdKey, v);
    notifyListeners();
  }

  /// Scopes requested at sign-in. `profile` is universal;
  /// `tokens/session` lets us attach a device record; `oldsync` unlocks the
  /// real Firefox Sync collections when the client is allowed to hold it.
  static const requestedScopes = [
    'profile',
    'https://identity.mozilla.com/tokens/session',
    'https://identity.mozilla.com/apps/oldsync',
  ];

  Future<void> restore() async {
    try {
      final raw = await Storage.readSecret(_tokenKey);
      final profileRaw = Storage.read(Storage.settings, _profileKey);
      final epRaw = Storage.read(Storage.settings, _endpointsKey);
      if (epRaw != null) {
        endpoints = FxaEndpoints.fromJson(jsonDecode(epRaw));
      }
      if (raw != null) _tokens = FxaTokens.fromJson(jsonDecode(raw));
      if (profileRaw != null) {
        profile = FxAProfile.fromJson(jsonDecode(profileRaw));
      }
      if (_tokens != null && _tokens!.expired) await _refresh();
      notifyListeners();
    } catch (_) {}
  }

  void configureEndpoints(FxaEndpoints ep) {
    endpoints = ep;
    Storage.write(Storage.settings, _endpointsKey, jsonEncode(ep.toJson()));
    notifyListeners();
  }

  Future<String> signIn() async {
    if (clientId.isEmpty) {
      _lastError =
          'No OAuth client id. Set FXA_CLIENT_ID or paste one in Settings.';
      notifyListeners();
      throw StateError(_lastError!);
    }
    _signingIn = true;
    _lastError = null;
    notifyListeners();
    try {
      final verifier = _randomString(64);
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      final state = _randomString(24);
      final keysJwk = await _generateKeysJwk();

      _loopback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _loopback!.port;
      final redirect = 'http://127.0.0.1:$port/oauth';

      final authUri = endpoints.authorization.replace(queryParameters: {
        'client_id': clientId,
        'state': state,
        'scope': requestedScopes.join(' '),
        'response_type': 'code',
        'access_type': 'offline',
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'keys_jwk': keysJwk,
        'action': 'signin',
      });

      await launchUrl(authUri, mode: LaunchMode.externalApplication);
      final code = await _waitForCode(state);
      await _exchange(code, verifier, redirect);
      await _fetchProfile();
      await _attachDevice();
      _signingIn = false;
      notifyListeners();
      return profile?.email ?? '';
    } catch (e) {
      _signingIn = false;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      await _loopback?.close(force: true);
      _loopback = null;
    }
  }

  Future<String> _waitForCode(String expectedState) {
    final c = Completer<String>();
    final server = _loopback;
    if (server == null) {
      c.completeError(StateError('loopback server closed'));
      return c.future;
    }
    server.listen((req) async {
      final params = req.uri.queryParameters;
      const ok = '<html><body style="font-family:sans-serif;text-align:center;'
          'padding:64px"><h2>Wave is signed in</h2>'
          '<p>You can close this tab and return to the browser.</p>'
          '</body></html>';
      const bad = '<html><body><h2>Sign-in failed</h2></body></html>';
      if (params['state'] == expectedState && params['code'] != null) {
        req.response
          ..headers.contentType = ContentType.html
          ..write(ok);
        await req.response.close();
        if (!c.isCompleted) c.complete(params['code']);
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write(bad);
        await req.response.close();
        if (!c.isCompleted) {
          c.completeError(StateError(params['error'] ?? 'state mismatch'));
        }
      }
    });
    return c.future.timeout(const Duration(minutes: 3));
  }

  Future<void> _exchange(String code, String verifier, String redirect) async {
    final res = await http.post(endpoints.token, body: {
      'client_id': clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirect,
      'code_verifier': verifier,
    });
    if (res.statusCode != 200) {
      throw StateError('token exchange failed: ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _tokens = FxaTokens(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String?,
      idToken: j['id_token'] as String?,
      expiresAt: DateTime.now()
          .add(Duration(seconds: j['expires_in'] as int? ?? 3600)),
    );
    await _persistTokens();
    await _fetchScopedKey();
  }

  Future<void> _refresh() async {
    final t = _tokens;
    final refresh = t?.refreshToken;
    if (t == null || refresh == null) return;
    final res = await http.post(endpoints.token, body: {
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    });
    if (res.statusCode != 200) {
      _tokens = null;
      return;
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    t.accessToken = j['access_token'] as String;
    t.expiresAt = DateTime.now()
        .add(Duration(seconds: j['expires_in'] as int? ?? 3600));
    if (j['refresh_token'] != null) {
      t.refreshToken = j['refresh_token'] as String;
    }
    await _persistTokens();
  }

  Future<String> accessToken() async {
    if (_tokens != null && _tokens!.expired) await _refresh();
    return _tokens?.accessToken ?? '';
  }

  /// Pulls the oldsync key bundle when the granted scope allows it. Without
  /// the scope this returns null and sync falls back to a pluggable backend.
  Future<Map<String, dynamic>?> _fetchScopedKey() async {
    try {
      final res = await http.get(
        endpoints.keys.replace(queryParameters: {
          'scope': 'https://identity.mozilla.com/apps/oldsync',
        }),
        headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
      );
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final bundle =
            j['https://identity.mozilla.com/apps/oldsync'] as Map?;
        if (bundle != null) {
          _tokens!.scopedKey = bundle.cast<String, dynamic>();
          await _persistTokens();
          return _tokens!.scopedKey;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? get scopedKey => _tokens?.scopedKey;
  bool get hasSyncScope => _tokens?.scopedKey != null;

  Future<void> _fetchProfile() async {
    final token = await accessToken();
    final res = await http.get(endpoints.profile,
        headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      profile = FxAProfile(
        uid: j['uid'] as String? ?? '',
        email: j['email'] as String? ?? '',
        displayName: j['displayName'] as String?,
        avatarUrl: (j['avatar'] as String?)?.isNotEmpty == true
            ? j['avatar'] as String
            : null,
        locale: j['locale'] as String?,
      );
      Storage.write(
          Storage.settings, _profileKey, jsonEncode(profile!.toJson()));
    }
  }

  /// Registers Wave under the account's device list so the user sees it
  /// alongside their Firefoxes. Needs the tokens/session scope; silently
  /// skips when the client doesn't hold it.
  Future<void> _attachDevice() async {
    try {
      final token = await accessToken();
      await http.post(endpoints.device,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': 'Wave on ${Platform.operatingSystem}',
            'type': 'desktop',
          }));
    } catch (_) {}
  }

  Future<void> signOut() async {
    try {
      final token = await accessToken();
      if (token.isNotEmpty) {
        await http.post(endpoints.destroy,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'access_token': token}));
      }
    } catch (_) {}
    _tokens = null;
    profile = null;
    await Storage.deleteSecret(_tokenKey);
    Storage.settings.delete(_profileKey);
    notifyListeners();
  }

  Future<void> _persistTokens() async {
    if (_tokens == null) return;
    await Storage.writeSecret(_tokenKey, jsonEncode(_tokens!.toJson()));
  }

  static String _randomString(int len) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Ephemeral P-256 JWK required by the key-bearing OAuth scopes.
  static Future<String> _generateKeysJwk() async {
    try {
      final pair = await Ecdh.p256(length: 32).newKeyPair();
      final data = await pair.extract();
      final pub = data.publicKey;
      final x = base64Url.encode(pub.x).replaceAll('=', '');
      final y = base64Url.encode(pub.y).replaceAll('=', '');
      return jsonEncode({'kty': 'EC', 'crv': 'P-256', 'x': x, 'y': y});
    } catch (_) {}
    return '';
  }
}
