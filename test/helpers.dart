import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wave/app_state.dart';
import 'package:wave/storage.dart';

/// In-memory storage so service tests never touch the keychain.
final Map<String, String> fakeSecrets = {};

Directory? _tempDir;

/// The fake HttpOverrides the test binding installs. Loopback tests that
/// need real sockets set `HttpOverrides.global = null`; restore this after
/// them or later widget tests leak real NetworkImage fetches into FakeAsync.
HttpOverrides? _savedHttpOverrides;

/// Wires Hive + path_provider + secure storage to a temp dir so AppState
/// and services behave exactly like production, minus the OS.
/// Pass [clear]=false to simulate a restart on the same storage.
Future<void> setupTestEnv({bool clear = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _tempDir ??= await Directory.systemTemp.createTemp('wave_test');
  _savedHttpOverrides ??= HttpOverrides.current;
  HttpOverrides.global = _savedHttpOverrides;

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathChannel, (call) async {
    return _tempDir!.path;
  });

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureChannel, (call) async {
    switch (call.method) {
      case 'read':
        return fakeSecrets[call.arguments['key']];
      case 'write':
        fakeSecrets[call.arguments['key']] = call.arguments['value'];
        return null;
      case 'delete':
        fakeSecrets.remove(call.arguments['key']);
        return null;
      case 'deleteAll':
        fakeSecrets.clear();
        return null;
      case 'readAll':
        return fakeSecrets;
      default:
        return null;
    }
  });

  // window_manager plugin: caption buttons and the Linux companion dock
  // query the window state on build.
  const wmChannel = MethodChannel('window_manager');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(wmChannel, (call) async {
    switch (call.method) {
      case 'isMaximized':
      case 'isFullScreen':
      case 'isMinimized':
      case 'isPreventClose':
        return false;
      case 'isFocused':
      case 'isVisible':
        return true;
      case 'getBounds':
        return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 800.0};
      case 'getDevicePixelRatio':
        return 1.0;
      default:
        return null;
    }
  });

  await Storage.init(memory: true);
  if (clear) await clearAllStorage();
}

Future<void> clearAllStorage() async {
  fakeSecrets.clear();
  for (final box in [
    Storage.workspaces,
    Storage.tabs,
    Storage.bookmarks,
    Storage.history,
    Storage.downloads,
    Storage.settings,
    Storage.vault,
    Storage.sync,
  ]) {
    await box.clear();
  }
}

/// A fresh AppState with test storage.
Future<AppState> makeAppState({void Function()? preseed}) async {
  await setupTestEnv();
  preseed?.call();
  final app = AppState();
  await app.init();
  return app;
}

/// Re-inits AppState over the existing storage — a simulated restart.
Future<AppState> restartApp() async {
  await setupTestEnv(clear: false);
  final app = AppState();
  await app.init();
  return app;
}

/// Seeds a fake FxA profile so `fxa.signedIn` is true after restore.
void fakeProfileSeed() {
  Storage.write(
      Storage.settings,
      'fxa_profile',
      '{"uid":"u1","email":"cal@wave.dev"}');
}

/// Seeds a vault master key so `vault.locked` is false after restore.
void fakeVaultKey() {
  fakeSecrets['vault_master_key'] =
      base64Encode(List<int>.filled(32, 7));
}
