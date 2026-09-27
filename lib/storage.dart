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
    _workspaces = Kv._(await Hive.openBox('workspaces'));
    _tabs = Kv._(await Hive.openBox('tabs'));
    _bookmarks = Kv._(await Hive.openBox('bookmarks'));
    _history = Kv._(await Hive.openBox('history'));
    _downloads = Kv._(await Hive.openBox('downloads'));
    _settings = Kv._(await Hive.openBox('settings'));
    _vault = Kv._(await Hive.openBox('vault'));
    _sync = Kv._(await Hive.openBox('sync'));
    _ready = true;
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
