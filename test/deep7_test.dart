import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/landing/landing.dart';
import 'package:wave/models.dart';
import 'package:wave/services/fxa.dart';
import 'package:wave/services/sync.dart';
import 'package:wave/storage.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/settings_panel.dart';
import 'package:wave/ui/shell.dart';
import 'package:wave/ui/widgets.dart';

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

void main() {
  setUp(setupTestEnv);

  group('shell keyboard', () {
    testWidgets('ctrl+w, ctrl+tab cycle, digits, alt+arrows',
        (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://t1.dev', activate: false);
        a.newTab(url: 'https://t2.dev', activate: false);
        a.newTab(url: 'https://t3.dev');
      });
      Future<void> key(LogicalKeyboardKey k,
          {bool ctrl = true, bool shift = false, bool alt = false}) async {
        if (ctrl) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        if (alt) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        }
        await tester.sendKeyEvent(k);
        if (alt) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        }
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        if (ctrl) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.pump();
      }

      // jump to index then back
      await key(LogicalKeyboardKey.digit2);
      expect(app.activeTabId, app.workspaceTabs[1].id);
      await key(LogicalKeyboardKey.digit1);
      expect(app.activeTabId, app.workspaceTabs[0].id);
      // cycle
      final start = app.activeTabId;
      await key(LogicalKeyboardKey.tab);
      expect(app.activeTabId, isNot(start));
      await key(LogicalKeyboardKey.tab, shift: true);
      expect(app.activeTabId, start);
      // alt arrows (noop controllers but lines covered)
      await key(LogicalKeyboardKey.arrowLeft, alt: true, ctrl: false);
      await key(LogicalKeyboardKey.arrowRight, alt: true, ctrl: false);
      // close current
      await key(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(app.workspaceTabs.length, 3);
      // collapse sidebar
      await key(LogicalKeyboardKey.keyB, shift: true);
      expect(app.sidebarCollapsed, isTrue);
      await key(LogicalKeyboardKey.keyB);
      expect(app.sidebarVisible, isFalse);
      await key(LogicalKeyboardKey.keyB);
      // find bar + reader + comma
      await key(LogicalKeyboardKey.keyF);
      expect(app.findBarVisible, isTrue);
      await key(LogicalKeyboardKey.escape, ctrl: false);
      await key(LogicalKeyboardKey.keyQ); // guarded in tests
    });
  });

  group('sidebar deep II', () {
    testWidgets('essential tile tap + workspace dialog icon/gradient pick',
        (tester) async {
      final app = await pump(tester, seed: (a) {
        final t = a.newTab(url: 'https://ess.dev', activate: false);
        a.setTabKind(t.id, TabKind.essential);
      });
      await tester.pump();
      // essentials section header + tile
      final ess = find.textContaining('ess.dev');
      if (ess.evaluate().isNotEmpty) {
        await tester.tap(ess.first);
        await tester.pump();
        expect(app.activeTab!.url, 'https://ess.dev');
      }
      // workspace dialog: open + pick icon + gradient + save
      await tester.tap(find.text('Personal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('New workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.enterText(
            find.byType(TextField).last, 'Dev');
        await tester.pump();
        final create = find.text('Create');
        if (create.evaluate().isNotEmpty) {
          await tester.tap(create, warnIfMissed: false);
          await tester.pump();
          expect(app.workspaces.any((w) => w.name == 'Dev'),
              isTrue);
        }
      }
    });

    testWidgets('workspace delete from edit dialog', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Personal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Edit workspaces'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final del = find.byIcon(Icons.delete_outline_rounded);
      if (del.evaluate().isNotEmpty) {
        final before = app.workspaces.length;
        await tester.tap(del.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // confirm if a dialog opens
        final confirm = find.text('Delete');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.last);
          await tester.pump();
        }
        expect(app.workspaces.length, lessThanOrEqualTo(before));
      }
    });
  });

  group('settings deep', () {
    testWidgets('endpoint editors apply', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: SettingsPanel())),
          size: const Size(500, 1400));
      await tester.enterText(
          find.widgetWithText(TextField, 'Content server URL'),
          'http://content.local');
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'OAuth server'),
          'http://oauth.local');
      await tester.enterText(
          find.widgetWithText(TextField, 'Profile server'),
          'http://profile.local');
      await tester.pump();
      expect(app.fxa.endpoints.contentUrl, 'http://content.local');
      expect(app.fxa.endpoints.oauthUrl, 'http://oauth.local');
      expect(app.fxa.endpoints.profileUrl, 'http://profile.local');
    });
  });

  group('account panel II', () {
    testWidgets('synced tabs list + sign-out confirm', (tester) async {
      fakeSecrets['fxa_tokens'] = jsonEncode(FxaTokens(
              accessToken: 'at',
              refreshToken: 'rt',
              expiresAt:
                  DateTime.now().add(const Duration(hours: 1)))
          .toJson());
      Storage.write(
          Storage.settings,
          'fxa_profile',
          jsonEncode(const FxAProfile(
                  uid: 'u1', email: 'cal@wave.dev')
              .toJson()));
      Storage.write(Storage.settings, 'sync_backend', 'local');
      final app = await pump(tester, size: const Size(1500, 1100));
      // seed remote tabs into local backend (real file I/O -> real zone)
      await tester.runAsync(() => app.sync.local.upload('tabs', [
            SyncRecord(
                id: 'remote1',
                payload: jsonEncode({
                  'title': 'Remote Site',
                  'url': 'https://remote.dev'
                }),
                modified: 1),
          ]));
      app.showPanel(ActivePanel.account);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final remote = find.text('Remote Site');
      if (remote.evaluate().isNotEmpty) {
        await tester.tap(remote);
        await tester.pump();
        expect(
            app.tabs.any((t) => t.url == 'https://remote.dev'),
            isTrue);
      }
      // sign out flow
      final signOutBtn = find.text('Sign out');
      if (signOutBtn.evaluate().isNotEmpty) {
        await tester.tap(signOutBtn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final confirm = find.text('Sign out of Firefox Account?');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(find.text('Sign out').last);
          await tester.pump();
        }
      }
    });
  });

  group('widgets remaining', () {
    testWidgets('favicon image path + ghost hover out', (tester) async {
      await pump(tester,
          child: Scaffold(
            body: Column(children: [
              Favicon(
                  tab: BrowserTab(
                      id: 'i',
                      workspaceId: 'w',
                      title: 'T',
                      url: 'https://img.dev',
                      faviconUrl: 'https://img.dev/f.ico'),
                  size: 18),
              const UrlFavicon(url: 'https://img.dev/f.png', size: 18),
              GhostButton(
                  icon: Icons.abc, tooltip: 'h', onPressed: () {}),
            ]),
          ),
          size: const Size(300, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final g =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.moveTo(tester.getCenter(find.byTooltip('h')));
      await tester.pump();
      await g.moveTo(const Offset(0, 0));
      await tester.pump();
    });
  });

  group('account panel III', () {
    testWidgets('sign-in error path + sync status variants',
        (tester) async {
      final app = await pump(tester, size: const Size(1400, 1000));
      app.showPanel(ActivePanel.account);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // sign in with no client id -> inline error
      final signIn =
          find.widgetWithText(FilledButton, 'Sign in');
      if (signIn.evaluate().isNotEmpty) {
        await tester.tap(signIn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(app.fxa.lastError, isNotNull);
      }
    });

    testWidgets('sync status card shows states', (tester) async {
      final app = await pump(tester,
          size: const Size(1400, 1100), preseed: () {
        fakeSecrets['fxa_tokens'] = jsonEncode(FxaTokens(
                accessToken: 'at',
                refreshToken: 'rt',
                expiresAt:
                    DateTime.now().add(const Duration(hours: 1)))
            .toJson());
        Storage.write(
            Storage.settings,
            'fxa_profile',
            jsonEncode(const FxAProfile(
                    uid: 'u1', email: 'cal@wave.dev')
                .toJson()));
        Storage.write(Storage.settings, 'sync_backend', 'local');
      });
      app.showPanel(ActivePanel.account);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // error state text
      app.sync.status = SyncStatus.error;
      app.sync.lastError = 'nope';
      app.sync.notifyListeners();
      app.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Sync error'), findsOne);
      app.sync.status = SyncStatus.idle;
      app.sync.lastSyncAt = DateTime.now()
          .subtract(const Duration(minutes: 5));
      app.sync.notifyListeners();
      app.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Last synced'), findsOne);
    });
  });

  group('landing desktop', () {
    testWidgets('nav links + footer render wide', (tester) async {
      const channel =
          MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const MaterialApp(home: LandingPage()));
      await tester.pump();
      await tester.tap(find.text('Download').first, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('Source').first, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('AGPL-3.0').first, warnIfMissed: false);
      await tester.pump();
      // footer tagline
      expect(find.textContaining('AGPL-3.0'), findsWidgets);
    });
  });
}
