import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Minimal key/value surface over a Hive box, or a plain map when running
/// under flutter_test (file-backed boxes stall the fake-async zone).
class Kv {
  Kv._(this._box);

  Kv.memory() : _box = null;

  final Box? _box;
  final Map<String, dynamic> _map = {};

  dynamic get(String key, {dynamic defaultValue}) =>
      _box?.get(key, defaultValue: defaultValue) ??
      _map[key] ??
      defaultValue;

  void put(String key, dynamic value) {
    if (_box != null) {
      _box.put(key, value);
    } else {
      _map[key] = value;
    }
  }

  Future<void> delete(String key) async {
    if (_box != null) {
      await _box.delete(key);
    } else {
      _map.remove(key);
    }
  }

  Future<void> clear() async {
    if (_box != null) {
      await _box.clear();
    } else {
      _map.clear();
    }
  }
}

/// Thin persistence layer over Hive boxes. Everything in Wave that survives
/// a restart lives in one of these boxes; secrets live in secure storage.
class Storage {
  Storage._();

  static late Kv _workspaces;
  static late Kv _tabs;
  static late Kv _bookmarks;
  static late Kv _history;
  static late Kv _downloads;
  static late Kv _settings;
  static late Kv _vault;
  static late Kv _sync;

  static const secure = FlutterSecureStorage();

  static bool _ready = false;

  /// Pass [memory]=true in tests so boxes never touch the filesystem.
  static Future<void> init({bool memory = false}) async {
    if (_ready) return;
    if (memory) {
      _workspaces = Kv.memory();
      _tabs = Kv.memory();
      _bookmarks = Kv.memory();
      _history = Kv.memory();
      _downloads = Kv.memory();
      _settings = Kv.memory();
      _vault = Kv.memory();
      _sync = Kv.memory();
      _ready = true;
      return;
    }
    if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      final dir = await getApplicationSupportDirectory();
      await Hive.initFlutter(dir.path);
    }
    // A leftover process or a filesystem without flock support can make
    // openBox throw FileSystemException('lock failed'). Retry briefly —
    // a dying instance releases the lock quickly — then degrade to an
    // in-memory box so the app still runs (state just won't persist).
    _workspaces = await _openBox('workspaces');
    _tabs = await _openBox('tabs');
    _bookmarks = await _openBox('bookmarks');
    _history = await _openBox('history');
    _downloads = await _openBox('downloads');
    _settings = await _openBox('settings');
    _vault = await _openBox('vault');
    _sync = await _openBox('sync');
    _ready = true;
  }

  static Future<Kv> _openBox(String name) async {
    for (var i = 0; i < 40; i++) {
      try {
        return Kv._(await Hive.openBox(name));
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return Kv.memory();
  }

  static Kv get workspaces => _workspaces;
  static Kv get tabs => _tabs;
  static Kv get bookmarks => _bookmarks;
  static Kv get history => _history;
  static Kv get downloads => _downloads;
  static Kv get settings => _settings;
  static Kv get vault => _vault;
  static Kv get sync => _sync;

  static String? read(Kv box, String key) => box.get(key) as String?;
  static void write(Kv box, String key, String value) => box.put(key, value);

  static Future<String?> readSecret(String key) => secure.read(key: key);
  static Future<void> writeSecret(String key, String value) =>
      secure.write(key: key, value: value);
  static Future<void> deleteSecret(String key) => secure.delete(key: key);
}
