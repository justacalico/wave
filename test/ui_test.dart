import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/account_panel.dart';
import 'package:wave/ui/new_tab.dart';
import 'package:wave/ui/panels.dart';
import 'package:wave/ui/settings_panel.dart';
import 'package:wave/ui/shell.dart';
import 'package:wave/ui/vault_panel.dart';

import 'helpers.dart';


Widget wrapApp(AppState app,
    {Widget? child, Brightness brightness = Brightness.light}) {
  return ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(
      theme: WaveTheme.light(const Color(0xFF5B8CFF)),
      darkTheme: WaveTheme.dark(const Color(0xFF5B8CFF)),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: child ?? const BrowserShell(),
    ),
  );
}

Future<void> pumpApp(WidgetTester tester, AppState app,
    {Size size = const Size(1400, 900),
    Widget? child,
    Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
      wrapApp(app, child: child, brightness: brightness));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}
void main() {
  late AppState app;
  setUp(() async {
    app = await makeAppState();
  });

  group('shell', () {
    testWidgets('wide layout shows sidebar + new tab page', (tester) async {
      await pumpApp(tester, app);
      expect(find.text('Personal'), findsWidgets);
      expect(find.text('New tab'), findsOne);
      expect(find.byType(NewTabPage), findsOne);
      // Search field on the start surface.
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('compact layout shows mobile bar', (tester) async {
      await pumpApp(tester, app, size: const Size(400, 800));
      // No sidebar, but the bottom bar shows a tab count.
      expect(find.byIcon(Icons.more_vert_rounded), findsOne);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOne);
    });

    testWidgets('collapsed sidebar renders icon rail', (tester) async {
      app.toggleSidebarCollapsed();
      await pumpApp(tester, app, size: const Size(1200, 800));
      expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    });
  });

  group('panels', () {
    testWidgets('bookmarks panel lists entries', (tester) async {
      app.bookmarks.add(Bookmark(
          id: 'b1', url: 'https://flutter.dev', title: 'Flutter'));
      await pumpApp(tester, app,
          child: const Scaffold(
              body: SizedBox(width: 400, child: BookmarksPanel())),
          size: const Size(500, 800));
      expect(find.text('Flutter'), findsOne);
      expect(find.text('https://flutter.dev'), findsOne);
    });

    testWidgets('history panel groups by day', (tester) async {
      app.recordVisit('https://a.dev', 'Site A');
      await pumpApp(tester, app,
          child: const Scaffold(
              body: SizedBox(width: 400, child: HistoryPanel())),
          size: const Size(500, 800));
      expect(find.text('Site A'), findsOne);
      expect(find.text('Today'), findsOne);
    });

    testWidgets('settings panel renders sections', (tester) async {
      await pumpApp(tester, app,
          child: const Scaffold(
              body: SizedBox(width: 400, child: SettingsPanel())),
          size: const Size(500, 1000));
      expect(find.text('Appearance'), findsOne);
      expect(find.text('Search'), findsOne);
      expect(find.text('Sync backend'), findsOne);
      expect(find.text('Google'), findsOne);
    });

    testWidgets('vault panel shows lock screen', (tester) async {
      await pumpApp(tester, app,
          child: const Scaffold(
              body: SizedBox(width: 400, child: VaultPanel())),
          size: const Size(500, 800));
      expect(find.text('Vault locked'), findsOne);
    });

    testWidgets('account panel shows sign-in card when logged out',
        (tester) async {
      await pumpApp(tester, app,
          child: const Scaffold(
              body: SizedBox(width: 400, child: AccountPanel())),
          size: const Size(500, 800));
      expect(find.text('Firefox Account'), findsOne);
      expect(find.text('Sign in'), findsOne);
    });
  });

  group('sidebar interactions', () {
    testWidgets('new tab button creates a tab', (tester) async {
      await pumpApp(tester, app);
      final before = app.workspaceTabs.length;
      await tester.tap(find.text('New tab'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(app.workspaceTabs.length, before + 1);
    });
  });
}
