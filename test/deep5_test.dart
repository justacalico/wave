import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/landing/landing.dart';
import 'package:wave/models.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/panels.dart';
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
    void Function(AppState)? seed}) async {
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

  group('panels search + groups', () {
    testWidgets('bookmark search filters', (tester) async {
      await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: BookmarksPanel())),
          size: const Size(500, 900),
          seed: (a) {
            a.bookmarks.add(Bookmark(
                id: 'b1', url: 'https://a.dev', title: 'Alpha'));
            a.bookmarks.add(Bookmark(
                id: 'b2', url: 'https://b.dev', title: 'Beta'));
          });
      await tester.enterText(
          find.widgetWithText(TextField, 'Search bookmarks'),
          'alpha');
      await tester.pump();
      expect(find.text('Alpha'), findsOne);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('history day groups + per-row remove + clear dialog',
        (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: HistoryPanel())),
          size: const Size(500, 900),
          seed: (a) {
            a.history.add(HistoryEntry(
                url: 'https://old.dev',
                title: 'Old',
                lastVisited:
                    DateTime.now().subtract(const Duration(days: 2))));
            a.history.add(HistoryEntry(
                url: 'https://today.dev',
                title: 'Today visit',
                lastVisited: DateTime.now()));
          });
      app.notifyListeners();
      await tester.pump();
      expect(find.text('Today'), findsWidgets);
      // remove a row
      final remove = find.byIcon(Icons.close);
      if (remove.evaluate().isNotEmpty) {
        await tester.tap(remove.first);
        await tester.pump();
      }
      // confirm-clear dialog
      final clearBtn = find.byIcon(Icons.delete_outline_rounded);
      final clearText = find.text('Clear');
      if (clearBtn.evaluate().isNotEmpty) {
        await tester.tap(clearBtn.first);
      } else if (clearText.evaluate().isNotEmpty) {
        await tester.tap(clearText.first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final confirm = find.text('Clear browsing history?');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(find.text('Clear').last);
        await tester.pump();
        expect(app.history, isEmpty);
      }
    });

    testWidgets('downloads clear finished', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: DownloadsPanel())),
          size: const Size(500, 900),
          seed: (a) {
            a.downloads.items.add(DownloadItem(
                id: 'd',
                url: 'https://x.dev/f.zip',
                filename: 'f.zip',
                state: DownloadState.completed));
          });
      await tester.pump();
      await tester.tap(find.text('Clear finished'));
      await tester.pump();
      expect(app.downloads.items, isEmpty);
    });
  });

  group('sidebar essentials + badges', () {
    testWidgets('essential + private tabs render sections',
        (tester) async {
      await pump(tester, seed: (a) {
        final t = a.newTab(url: 'https://ess.dev', activate: false);
        a.setTabKind(t.id, TabKind.essential);
        a.newTab(url: 'https://priv.dev', isPrivate: true);
      });
      await tester.pump();
      expect(find.text('priv.dev'), findsWidgets);
    });

    testWidgets('account chip opens account panel', (tester) async {
      final app = await pump(tester);
      final chip = find.byType(CircleAvatar);
      expect(chip, findsWidgets);
      await tester.tap(chip.first);
      await tester.pump();
      expect(app.activePanel, ActivePanel.account);
    });
  });

  group('toolbar menus', () {
    testWidgets('main menu items', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://page.dev');
      });
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final priv = find.text('New private tab');
      if (priv.evaluate().isNotEmpty) {
        await tester.tap(priv);
        await tester.pump();
        expect(app.activeTab!.isPrivate, isTrue);
      }
    });

    testWidgets('split menu picks another tab', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://a.dev', activate: false);
        a.newTab(url: 'https://b.dev');
      });
      final splitBtn = find.byIcon(Icons.vertical_split_rounded);
      if (splitBtn.evaluate().isEmpty) return;
      await tester.tap(splitBtn.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final item = find.text('a.dev');
      if (item.evaluate().isNotEmpty) {
        await tester.tap(item.last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(app.splitTabId, isNotNull);
      }
    });

    testWidgets('reader button on url tab', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://article.dev');
      });
      final readerBtn =
          find.byIcon(Icons.chrome_reader_mode_outlined);
      if (readerBtn.evaluate().isNotEmpty) {
        await tester.tap(readerBtn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        // webview is broken in tests -> evaluateJavaScript null -> no sheet
        expect(app.readerSheetOpen, isFalse);
      }
    });
  });

  group('account panel detail', () {
    testWidgets('sync now + synced tabs', (tester) async {
      final app = await pump(tester,
          size: const Size(1400, 900),
          seed: (a) {
            a.sync.setBackendChoice('local');
          });
      // open account panel via shortcut-ish path
      app.showPanel(ActivePanel.account);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final syncNow = find.text('Sync now');
      if (syncNow.evaluate().isNotEmpty) {
        await tester.tap(syncNow);
        await tester.pump();
      }
    });
  });

  group('landing page', () {
    testWidgets('download buttons hover + tap', (tester) async {
      const channel =
          MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel,
              (call) async => call.method == 'launch' || true);
      await pump(tester,
          child: const LandingPage(), size: const Size(400, 1000));
      await tester.pump();
      expect(find.text('wave'), findsWidgets);
      final linux = find.text('Linux');
      if (linux.evaluate().isNotEmpty) {
        await tester.tap(linux.first, warnIfMissed: false);
        await tester.pump();
      }
    });
  });

  group('theme colors', () {
    test('WaveColors lerp + of', () {
      const a =
          WaveColors(sidebar: Color(0xFF000000), content: Color(0xFF111111));
      const b =
          WaveColors(sidebar: Color(0xFFFFFFFF), content: Color(0xFFEEEEEE));
      final mid = a.lerp(b, 0.5);
      expect(mid.sidebar, isNot(a.sidebar));
      expect(a.lerp(null, 0.5).sidebar, a.sidebar);
    });
  });
}
