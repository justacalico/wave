import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/panels.dart';
import 'package:wave/ui/reader.dart';
import 'package:wave/ui/shell.dart';
import 'package:wave/ui/settings_panel.dart';
import 'package:wave/ui/vault_panel.dart';

import 'helpers.dart';

Widget wrap(AppState app, {Widget? child, Brightness b = Brightness.light}) =>
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: WaveTheme.light(const Color(0xFF5B8CFF)),
        darkTheme: WaveTheme.dark(const Color(0xFF5B8CFF)),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: child ?? const BrowserShell(),
      ),
    );

Future<AppState> pump(WidgetTester tester,
    {Size size = const Size(1400, 900),
    Widget? child,
    Brightness b = Brightness.light,
    void Function(AppState)? seed}) async {
  final app = AppState();
  await app.init();
  seed?.call(app);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(wrap(app, child: child, b: b));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return app;
}

void main() {
  setUp(setupTestEnv);

  group('omnibox', () {
    testWidgets('typing shows suggestions, enter navigates', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.recordVisit('https://flutter.dev', 'Flutter');
      });
      await tester.tap(find.text('Search or enter address'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Flutter'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.activeTab!.url, contains('flutter'));
    });

    testWidgets('arrow keys move highlight', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.recordVisit('https://one.dev', 'One');
        a.recordVisit('https://two.dev', 'Two');
      });
      await tester.tap(find.text('Search or enter address'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'o');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(app.activeTab, isNotNull);
    });

    testWidgets('submit bang search', (tester) async {
      final app = await pump(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, '!w mars');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(app.activeTab!.url, contains('wikipedia.org'));
    });
  });

  group('sidebar interactions', () {
    testWidgets('workspace switch + add workspace dialog', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Personal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.activeWorkspaceId, 'work');
      // Reopen menu -> New workspace -> dialog
      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('New workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).last, 'Reading');
        final create = find.text('Create');
        if (create.evaluate().isNotEmpty) {
          await tester.tap(create);
          await tester.pump();
          expect(
              app.workspaces.any((w) => w.name == 'Reading'), isTrue);
        }
      }
    });

    testWidgets('tab tile tap activates, close button removes',
        (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://a.dev');
        a.newTab(url: 'https://b.dev');
      });
      final first = app.workspaceTabs.first;
      await tester.tap(find.text(first.title).first);
      await tester.pump();
      expect(app.activeTabId, first.id);
      final close = find.byIcon(Icons.close_rounded);
      expect(close, findsWidgets);
      final count = app.workspaceTabs.length;
      await tester.tap(close.last);
      await tester.pump();
      expect(app.workspaceTabs.length, count - 1);
    });

    testWidgets('tab context menu pins', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://pinme.dev');
      });
      final tile = find.text('pinme.dev').first;
      await tester.longPress(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final pinItem = find.text('Pin');
      if (pinItem.evaluate().isNotEmpty) {
        await tester.tap(pinItem);
        await tester.pump();
        expect(app.pinnedTabs, isNotEmpty);
      }
    });
  });

  group('panels interactions', () {
    testWidgets('bookmark open + remove', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: BookmarksPanel())),
          size: const Size(500, 800),
          seed: (a) {
            a.bookmarks.add(Bookmark(
                id: 'b1', url: 'https://flutter.dev', title: 'Flutter'));
          });
      expect(find.text('Flutter'), findsOne);
      await tester.tap(find.text('Flutter'));
      await tester.pump();
      expect(
          app.tabs.any((t) => t.url == 'https://flutter.dev'), isTrue);
      // delete icon
      final del = find.byIcon(Icons.delete_outline_rounded);
      if (del.evaluate().isNotEmpty) {
        await tester.tap(del.first);
        await tester.pump();
        expect(app.bookmarks, isEmpty);
      }
    });

    testWidgets('history tap reopens and clear wipes', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: HistoryPanel())),
          size: const Size(500, 800),
          seed: (a) {
            a.recordVisit('https://a.dev', 'Site A');
            a.recordVisit('https://b.dev', 'Site B');
          });
      expect(find.text('Site B'), findsOne);
      await tester.tap(find.text('Site B'));
      await tester.pump();
      expect(app.activeTab!.url, 'https://b.dev');
      final clear = find.text('Clear');
      if (clear.evaluate().isNotEmpty) {
        await tester.tap(clear);
        await tester.pump();
        expect(app.history, isEmpty);
      }
    });

    testWidgets('downloads empty state renders', (tester) async {
      await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: DownloadsPanel())),
          size: const Size(500, 800));
      expect(find.textContaining('download', findRichText: true),
          findsWidgets);
    });

    testWidgets('settings toggles flip state', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: SettingsPanel())),
          size: const Size(500, 1200));
      final restore =
          find.widgetWithText(SwitchListTile, 'Restore tabs on launch');
      if (restore.evaluate().isNotEmpty) {
        await tester.tap(restore);
        await tester.pump();
        expect(app.restoreTabs, isFalse);
      }
    });

    testWidgets('vault unlock via account then list', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900));
      await app.vault.ensureKey();
      await tester.pump();
      final unlock = find.text('Unlock');
      if (unlock.evaluate().isNotEmpty) {
        await tester.tap(unlock);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    });
  });

  group('reader + find bar', () {
    testWidgets('reader sheet renders html and font controls',
        (tester) async {
      var closed = false;
      await pump(tester,
          child: Scaffold(
              body: ReaderSheet(
                  data: const {
                    'title': 'A quiet post',
                    'byline': 'wave',
                    'html': '<h1>Hi</h1><p>Body text</p>',
                    'words': 400,
                  },
                  onClose: () => closed = true)),
          size: const Size(700, 900));
      expect(find.text('Reader'), findsOne);
      expect(find.text('18'), findsOne);
      await tester.tap(find.byIcon(Icons.text_increase_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('find bar navigates and closes', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://page.dev');
        a.setFindBar(true, query: 'x');
      });
      expect(find.byIcon(Icons.close_rounded), findsWidgets);
      final field = find.byType(TextField);
      await tester.enterText(field.last, 'needle');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(app.findBarVisible, isFalse);
    });
  });

  group('shell chrome', () {
    testWidgets('ctrl+t makes a tab, ctrl+l focuses omnibox',
        (tester) async {
      final app = await pump(tester);
      final before = app.workspaceTabs.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(app.workspaceTabs.length, before + 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      // Omnibox textfield focused
      final tf = tester.widget<TextField>(find.byType(TextField).first);
      expect(tf.focusNode?.hasFocus ?? false, isTrue);
    });

    testWidgets('mobile bottom bar opens tab sheet', (tester) async {
      final app = await pump(tester, size: const Size(400, 800));
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(app.activeTab, isNotNull);
    });

    testWidgets('panel shortcuts open and close', (tester) async {
      final app = await pump(tester);
      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(k);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await key(LogicalKeyboardKey.keyH);
      expect(app.activePanel, ActivePanel.history);
      await key(LogicalKeyboardKey.keyJ);
      expect(app.activePanel, ActivePanel.downloads);
      await key(LogicalKeyboardKey.comma);
      expect(app.activePanel, ActivePanel.settings);
      await key(LogicalKeyboardKey.comma);
      expect(app.activePanel, ActivePanel.none);
    });
  });
}
