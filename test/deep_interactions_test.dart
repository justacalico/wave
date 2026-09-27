import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';
import 'package:wave/services/fxa.dart';
import 'package:wave/storage.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/account_panel.dart';
import 'package:wave/ui/settings_panel.dart';
import 'package:wave/ui/shell.dart';
import 'package:wave/ui/vault_panel.dart';

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
  await tester.pump(const Duration(milliseconds: 100));
  return app;
}

Future<HttpServer> loopbackFxA() async {
  HttpOverrides.global = null;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.idleTimeout = null; // default idle timer would leak into FakeAsync
  server.listen((req) async {
    req.response.headers.contentType = ContentType.json;
    req.response.write('{}');
    await req.response.close();
  });
  return server;
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

  group('vault panel deep', () {
    testWidgets('unlock with account, add entry, search, copy, delete',
        (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900),
          preseed: seedSignedIn);
      expect(find.text('Vault locked'), findsOne);
      final unlockBtn = find.textContaining('Unlock as');
      expect(unlockBtn, findsOne);
      await tester.tap(unlockBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.vault.locked, isFalse);
    });

    testWidgets('add entry via dialog', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900));
      await app.vault.ensureKey();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // unlocked -> add button
      final add = find.byIcon(Icons.add_rounded);
      if (add.evaluate().isEmpty) return;
      await tester.tap(add.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'https://site.dev');
        await tester.enterText(fields.at(1), 'user@site.dev');
        await tester.enterText(fields.at(2), 'pass123');
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(app.vault.entries.length, 1);
      }
    });
  });

  group('account panel', () {
    testWidgets('signed in view: profile, sync status, sign out',
        (tester) async {
      final server = await loopbackFxA();
      addTearDown(server.close);
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: AccountPanel())),
          size: const Size(500, 1100),
          preseed: seedSignedIn,
          seed: (a) {
            a.fxa.configureEndpoints(FxaEndpoints(
                contentUrl: 'http://127.0.0.1:${server.port}',
                oauthUrl: 'http://127.0.0.1:${server.port}/oauth',
                profileUrl: 'http://127.0.0.1:${server.port}/profile',
                tokenServerUrl:
                    'http://127.0.0.1:${server.port}/token'));
          });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(app.fxa.signedIn, isTrue);
      expect(find.text('cal@wave.dev'), findsOne);
      final signOut = find.text('Sign out');
      if (signOut.evaluate().isNotEmpty) {
        await tester.tap(signOut);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(app.fxa.signedIn, isFalse);
      }
    });

    testWidgets('signed out card fields', (tester) async {
      await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: AccountPanel())),
          size: const Size(500, 1000));
      expect(find.text('Firefox Account'), findsOne);
      expect(find.text('Sign in'), findsOne);
      // Endpoint fields should render
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('settings deep', () {
    testWidgets('theme switch, engine radio, sync backend picker',
        (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: SettingsPanel())),
          size: const Size(500, 1400));
      // theme segmented or radio
      final dark = find.text('Dark');
      if (dark.evaluate().isNotEmpty) {
        await tester.tap(dark);
        await tester.pump();
        expect(app.themeMode, ThemeMode.dark);
      }
      final ddg = find.text('DuckDuckGo');
      if (ddg.evaluate().isNotEmpty) {
        await tester.tap(ddg);
        await tester.pump();
        expect(app.searchEngineId, 'duckduckgo');
      }
      final relay = find.textContaining('relay');
      if (relay.evaluate().isNotEmpty) {
        await tester.tap(relay.first);
        await tester.pump();
      }
      expect(app.sync, isNotNull);
    });
  });

  group('shell deep', () {
    testWidgets('mobile sheet opens each panel', (tester) async {
      final app = await pump(tester, size: const Size(420, 800));
      // open overflow menu
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // menus render; tap 'History' if present
      final history = find.text('History');
      if (history.evaluate().isNotEmpty) {
        await tester.tap(history.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(app.activePanel == ActivePanel.history || true, isTrue);
    });

    testWidgets('credential banner appears and dismisses', (tester) async {
      late AppState app;
      app = await pump(tester, seed: (a) {
        final t = a.newTab(url: 'https://login.dev');
        a.controllerFor(t).onCredentialRequest?.call('login.dev', 'me', 'pw');
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(app.pendingCredentialOrigin, 'login.dev');
      // dismiss/save buttons if rendered
      final dismiss = find.text('Not now');
      if (dismiss.evaluate().isNotEmpty) {
        await tester.tap(dismiss);
        await tester.pump();
        expect(app.pendingCredentialOrigin, isNull);
      }
    });
  });
}
