import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wave/storage.dart';

/// Exercises the real Hive-backed Storage.init path. This file must not
/// call setupTestEnv (memory backend) or the init early-returns.
void main() {
  test('hive-backed init persists via real boxes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('wave_hive_test');
    addTearDown(() => dir.delete(recursive: true));

    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel,
            (call) async => dir.path);

    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final secrets = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      switch (call.method) {
        case 'write':
          secrets[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'read':
          return secrets[call.arguments['key']];
        case 'delete':
          secrets.remove(call.arguments['key']);
          return null;
        default:
          return null;
      }
    });

    await Storage.init();
    Storage.write(Storage.settings, 'k', 'v');
    expect(Storage.read(Storage.settings, 'k'), 'v');

    await Storage.writeSecret('sk', 'sv');
    expect(await Storage.readSecret('sk'), 'sv');
    await Storage.deleteSecret('sk');
    expect(await Storage.readSecret('sk'), isNull);

    Storage.settings.put('toDelete', 'x');
    Storage.settings.delete('toDelete');
    expect(Storage.settings.get('toDelete'), isNull);
  });
}
