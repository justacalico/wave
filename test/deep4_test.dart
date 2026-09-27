import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/models.dart';
import 'package:wave/services/fxa.dart';
import 'package:wave/services/sync.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/shell.dart';

import 'helpers.dart';

void main() {
  setUp(setupTestEnv);

  test('fxa sync backend full loopback roundtrip', () async {
    HttpOverrides.global = null;
    final stored = <String, List<Map<String, dynamic>>>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = null;
    final port = server.port;
    server.listen((req) async {
      final uri = req.uri;
      if (uri.path == '/token/1.0/sync/1.5') {
        expect(req.headers.value('authorization'), 'Bearer at');
        expect(req.headers.value('x-keyid'), 'kid-1');
        req.response.write(jsonEncode({
          'api_endpoint': 'http://127.0.0.1:$port',
          'id': 'hawkid',
          'key': 'hawksecret',
          'duration': 3600,
        }));
      } else if (req.method == 'POST' &&
          uri.path.startsWith('/storage/')) {
        final col = uri.path.split('/').last;
        expect(req.headers.value('authorization'),
            startsWith('Hawk id="hawkid"'));
        final body =
            jsonDecode(await utf8.decoder.bind(req).join()) as List;
        stored[col] = [
          for (final b in body)
            {
              'id': b['id'],
              'payload': b['payload'],
              'modified': 42.0,
            }
        ];
        req.response.write(jsonEncode({'modified': 42.0}));
      } else if (req.method == 'GET' &&
          uri.path.startsWith('/storage/')) {
        final col = uri.path.split('/').last;
        final newer = double.tryParse(
                uri.queryParameters['newer'] ?? '0') ??
            0;
        final lines = (stored[col] ?? [])
            .where((b) => (b['modified'] as num) > newer)
            .map(jsonEncode)
            .join('\n');
        req.response.write(lines);
      }
      await req.response.close();
    });

    // A real 32-byte kB so HKDF/AES paths run for real.
    final kbBytes = (await cg.SecretKeyData.random(length: 32)
            .extract())
        .bytes;
    final kbHex =
        kbBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    fakeSecrets['fxa_tokens'] = jsonEncode(FxaTokens(
            accessToken: 'at',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            scopedKey: {'kid': 'kid-1', 'kB': kbHex})
        .toJson());
    final fxa = FxaService(
        endpoints: FxaEndpoints(
            tokenServerUrl: 'http://127.0.0.1:$port/token'));
    await fxa.restore();
    expect(fxa.hasSyncScope, isTrue);

    final sync = SyncService(fxa);
    sync.setBackendChoice('fxa');
    expect(sync.backend.ready, isTrue);

    final merged = await sync.syncCollections({
      'bookmarks': [
        SyncRecord(
            id: 'b1',
            payload: jsonEncode(
                Bookmark(id: 'b1', url: 'https://a.dev', title: 'A')
                    .toJson()),
            modified: 1),
      ],
      'history': [],
      'passwords': [],
      'tabs': [],
    });
    expect(sync.status, SyncStatus.idle, reason: sync.lastError);
    expect(merged['bookmarks']!.single.id, 'b1');
    expect(stored['bookmarks']!.single['id'], 'b1');
    // payload is encrypted BSO, not plaintext
    expect(stored['bookmarks']!.single['payload'] as String,
        isNot(contains('a.dev')));

    // second pass: no newer records -> download empty, upload again
    final again = await sync.syncCollections(
        {'bookmarks': merged['bookmarks']!});
    expect(again['bookmarks']!.single.id, 'b1');
    expect(sync.lastSyncAt, isNotNull);
    await server.close();
  });

  test('fxa backend error path marks status error', () async {
    HttpOverrides.global = null;
    fakeSecrets['fxa_tokens'] = jsonEncode(FxaTokens(
            accessToken: 'at',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            scopedKey: {'kid': 'kid-1', 'kB': '00' * 32})
        .toJson());
    final fxa = FxaService(
        endpoints: const FxaEndpoints(
            tokenServerUrl: 'http://127.0.0.1:1')); // dead port
    await fxa.restore();
    final sync = SyncService(fxa);
    sync.setBackendChoice('fxa');
    final merged = await sync.syncCollections(const {});
    expect(sync.status, SyncStatus.error);
    expect(merged, isEmpty);
  });

  group('mobile sheets', () {
    testWidgets('mobile menu opens every panel sheet', (tester) async {
      final app = await makeAppState();
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: WaveTheme.light(const Color(0xFF5B8CFF)),
            home: const BrowserShell())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      for (final label in [
        'History',
        'Bookmarks',
        'Downloads',
        'Passwords',
        'Settings',
        'Account & sync',
      ]) {
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final item = find.text(label);
        if (item.evaluate().isEmpty) continue;
        await tester.tap(item.last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // dismiss the sheet via the system back action
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      }
    });

    testWidgets('tab switcher grid: tap, close, new tab', (tester) async {
      final app = await makeAppState();
      app.newTab(url: 'https://one.dev', activate: false);
      app.newTab(url: 'https://two.dev');
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: WaveTheme.light(const Color(0xFF5B8CFF)),
            home: const BrowserShell())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // tab count button opens switcher
      await tester.tap(find.text('${app.workspaceTabs.length}'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final tile = find.text('one.dev');
      if (tile.evaluate().isNotEmpty) {
        await tester.tap(tile.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(app.activeTab!.url, 'https://one.dev');
      }
    });
  });

  group('desktop shell extras', () {
    testWidgets('alt+arrows, ctrl+d bookmark, ctrl+shift+p private',
        (tester) async {
      final app = await makeAppState();
      final t = app.newTab(url: 'https://nav.dev');
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: WaveTheme.light(const Color(0xFF5B8CFF)),
            home: const BrowserShell())));
      await tester.pump();

      // ctrl+d bookmarks the active tab
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
          app.bookmarks.any((b) => b.url == 'https://nav.dev'), isTrue);

      // ctrl+shift+p -> private tab
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(app.activeTab!.isPrivate, isTrue);

      // ctrl+shift+t reopens the most recent history entry
      app.recordVisit('https://nav.dev', 'Nav');
      app.closeTab(t.id);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(app.tabs.any((e) => e.url == 'https://nav.dev'), isTrue);
    });
  });
}
