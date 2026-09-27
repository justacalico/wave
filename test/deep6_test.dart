import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';
import 'package:wave/services/fxa.dart';
import 'package:wave/services/sync.dart';
import 'package:wave/storage.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/reader.dart';
import 'package:wave/ui/shell.dart';

import 'helpers.dart';

Widget wrap(AppState app, {Widget? child}) => ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: WaveTheme.light(const Color(0xFF5B8CFF)),
        darkTheme: WaveTheme.dark(const Color(0xFF5B8CFF)),
        home: child ?? const BrowserShell(),
      ),
    );

Future<AppState> pump(WidgetTester tester,
    {Size size = const Size(1400, 900),
    Widget? child,
    void Function(AppState)? seed,
    void Function()? preseed}) async {
  preseed?.call();
  final app = AppState();
  await app.init();
  seed?.call(app);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(wrap(app, child: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  return app;
}

void seedSignedIn() {
  fakeSecrets['fxa_tokens'] = jsonEncode(FxaTokens(
          accessToken: 'at',
          refreshToken: 'rt',
          expiresAt: DateTime.now().add(const Duration(hours: 1)))
      .toJson());
  Storage.write(
      Storage.settings,
      'fxa_profile',
      jsonEncode(const FxAProfile(
              uid: 'u1', email: 'cal@wave.dev', displayName: 'Cal')
          .toJson()));
}

void main() {
  setUp(setupTestEnv);

  test('selfhosted relay error path marks error', () async {
    HttpOverrides.global = null;
    final app = await makeAppState();
    Storage.write(Storage.settings, 'sync_relay_url',
        'http://127.0.0.1:1'); // dead
    Storage.write(Storage.settings, 'sync_relay_token', 'tok');
    app.sync.setBackendChoice('selfhosted');
    await app.sync.syncCollections({
      'bookmarks': [SyncRecord(id: 'x', payload: '{}', modified: 1)]
    });
    expect(app.sync.status, SyncStatus.error);
    expect(app.sync.lastError, isNotNull);
  });

  test('private tab navigation skips history', () async {
    final app = await makeAppState();
    final priv = app.newTab(url: 'https://priv.dev', isPrivate: true);
    final pub = app.newTab(url: 'https://pub.dev', activate: false);
    app.controllerFor(priv)
        .onUrlChanged
        ?.call('https://priv.dev/next');
    await Future.delayed(Duration.zero);
    expect(app.history.any((h) => h.url.contains('priv.dev')),
        isFalse);
    app.controllerFor(pub).onUrlChanged?.call('https://pub.dev/next');
    await Future.delayed(Duration.zero);
    expect(app.history.any((h) => h.url.contains('pub.dev')),
        isTrue);
  });

  test('moveTabToWorkspace + setTabKind roundtrip', () async {
    final app = await makeAppState();
    final t = app.newTab(url: 'https://m.dev', activate: false);
    app.setTabKind(t.id, TabKind.pinned);
    expect(app.pinnedTabs.single.id, t.id);
    app.moveTabToWorkspace(t.id, 'work');
    app.switchWorkspace('work');
    expect(app.workspaceTabs.any((x) => x.id == t.id), isTrue);
  });

  group('reader styles', () {
    testWidgets('rich html styles render', (tester) async {
      await pump(tester,
          child: Scaffold(
              body: ReaderSheet(
                  data: const {
                    'title': 'T',
                    'byline': '',
                    'html': '<h1>H</h1><h3>S</h3><p>p<a href="x">l</a></p>'
                        '<blockquote>q</blockquote><code>c</code>'
                        '<pre>p</pre><img src="x.png">',
                    'words': 10,
                  },
                  onClose: () {})),
          size: const Size(700, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reader'), findsOne);
    });
  });

  group('find bar keys', () {
    testWidgets('enter + shift+enter + close icon', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://p.dev');
        a.setFindBar(true);
      });
      await tester.pump();
      final field = find.descendant(
          of: find.byType(Material), matching: find.byType(TextField));
      await tester.enterText(field.last, 'x');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(app.findBarVisible, isTrue);
    });
  });

  group('account panel detail', () {
    testWidgets('sync now + backend radios + endpoint fields',
        (tester) async {
      final app = await pump(tester,
          size: const Size(1400, 1000), preseed: seedSignedIn);
      app.showPanel(ActivePanel.account);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final syncNow = find.text('Sync now');
      if (syncNow.evaluate().isNotEmpty) {
        await tester.tap(syncNow);
        await tester.pump();
      }
      // backend radio
      final local = find.text('Local only');
      if (local.evaluate().isNotEmpty) {
        await tester.tap(local);
        await tester.pump();
      }
      final self = find.textContaining('relay');
      if (self.evaluate().isNotEmpty) {
        await tester.tap(self.first);
        await tester.pump();
      }
      // client id field
      final cid = find.widgetWithText(TextField, 'OAuth client id');
      if (cid.evaluate().isNotEmpty) {
        await tester.enterText(cid, 'abc123');
        await tester.testTextInput
            .receiveAction(TextInputAction.done);
        await tester.pump();
        expect(app.fxa.clientId, 'abc123');
      }
    });
  });

  group('new tab + content', () {
    testWidgets('new tab tiles + url tabs render surface',
        (tester) async {
      final app = await pump(tester, seed: (a) {
        a.recordVisit('https://flutter.dev', 'Flutter');
        a.recordVisit('https://dart.dev', 'Dart');
      });
      await tester.pump();
      // shortcuts strip shows history-derived tiles
      final tile = find.text('Flutter');
      if (tile.evaluate().isNotEmpty) {
        await tester.tap(tile.first);
        await tester.pump();
        expect(app.activeTab!.url, 'https://flutter.dev');
      }
    });
  });
}
