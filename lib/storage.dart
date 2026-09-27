import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Thin persistence layer over Hive boxes. Everything in Wave that survives
/// a restart lives in one of these boxes; secrets live in secure storage.
class Storage {
  Storage._();

  static late Box _workspaces;
  static late Box _tabs;
  static late Box _bookmarks;
  static late Box _history;
  static late Box _downloads;
  static late Box _settings;
  static late Box _vault;
  static late Box _sync;

  static const secure = FlutterSecureStorage();

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    if (kIsWeb) {
      await Hive.initFlutter();
    } else {
      final dir = await getApplicationSupportDirectory();
      await Hive.initFlutter(dir.path);
    }
    _workspaces = await Hive.openBox('workspaces');
    _tabs = await Hive.openBox('tabs');
    _bookmarks = await Hive.openBox('bookmarks');
    _history = await Hive.openBox('history');
    _downloads = await Hive.openBox('downloads');
    _settings = await Hive.openBox('settings');
    _vault = await Hive.openBox('vault');
    _sync = await Hive.openBox('sync');
    _ready = true;
  }

  static Box get workspaces => _workspaces;
  static Box get tabs => _tabs;
  static Box get bookmarks => _bookmarks;
  static Box get history => _history;
  static Box get downloads => _downloads;
  static Box get settings => _settings;
  static Box get vault => _vault;
  static Box get sync => _sync;

  static String? read(Box box, String key) => box.get(key) as String?;
  static void write(Box box, String key, String value) => box.put(key, value);

  static Future<String?> readSecret(String key) => secure.read(key: key);
  static Future<void> writeSecret(String key, String value) =>
      secure.write(key: key, value: value);
  static Future<void> deleteSecret(String key) => secure.delete(key: key);
}
