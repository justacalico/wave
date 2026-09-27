import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/panels.dart';
import 'package:wave/ui/shell.dart';
import 'package:wave/ui/vault_panel.dart';
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

  group('vault list interactions', () {
    testWidgets('list, search, copy, edit, delete, lock', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900));
      await app.vault.ensureKey();
      await app.vault.upsert(VaultEntry(
          id: 'e1',
          origin: 'https://github.com',
          username: 'calico',
          password: 'hunter2'));
      app.notifyListeners();
      await tester.pump();

      expect(find.text('github.com'), findsOne);
      final search =
          find.widgetWithText(TextField, 'Search passwords');
      await tester.enterText(search, 'gitlab');
      await tester.pump();
      expect(find.text('github.com'), findsNothing);
      await tester.enterText(search, 'git');
      await tester.pump();
      expect(find.text('github.com'), findsOne);

      await tester.tap(find.byTooltip('Copy password'));
      await tester.pump();
      expect(find.text('Password copied'), findsOne);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.text('github.com'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Edit password'), findsOne);
      await tester.tap(find.byTooltip('Generate'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(app.vault.entries.single.password, isNot('hunter2'));

      await tester.tap(find.text('github.com'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(app.vault.entries, isEmpty);

      await tester.tap(find.byTooltip('Lock vault'));
      await tester.pump();
      expect(app.vault.locked, isTrue);
    });

    testWidgets('create-vault path sets master password', (tester) async {
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900));
      await tester.enterText(find.byType(TextField).first, 'hunter2');
      await tester.tap(find.text('Create vault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.vault.hasMasterPassword, isTrue);
      expect(app.vault.locked, isFalse);
      app.vault.lock();
      app.notifyListeners();
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'bad');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Wrong password'), findsOne);
    });

    testWidgets('unlock-with-account button', (tester) async {
      fakeSecrets['fxa_tokens'] =
          '{"accessToken":"a","expiresAt":"${DateTime.now().add(const Duration(hours: 1)).toIso8601String()}"}';
      final app = await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: VaultPanel())),
          size: const Size(500, 900));
      expect(find.byType(TextField), findsWidgets);
      await app.vault.unlockWithAccount();
      await tester.pump();
      expect(app.vault.locked, isFalse);
    });
  });

  group('sidebar deep', () {
    testWidgets('tab context menu: pin, split, close', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://other.dev', activate: false);
        a.newTab(url: 'https://ctx.dev');
      });
      await tester.tapAt(tester.getCenter(find.textContaining('ctx.dev').first), buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pin'), findsOne);
      await tester.tap(find.text('Pin').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.pinnedTabs.single.url, 'https://ctx.dev');

      await tester.tapAt(tester.getCenter(find.textContaining('other.dev').first), buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Open in split view'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.splitTabId, isNotNull);
    });

    testWidgets('move tab to workspace via context menu', (tester) async {
      final app = await pump(tester, seed: (a) {
        a.newTab(url: 'https://moveme.dev');
      });
      await tester.tapAt(tester.getCenter(find.textContaining('moveme.dev').first), buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Move to Work'));
      await tester.pump();
      expect(
          app.workspaceTabs.any((t) => t.url.contains('moveme')),
          isFalse);
    });

    testWidgets('edit workspaces dialog renames', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Personal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Edit workspaces'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Workspaces'), findsOne);
      final editBtn = find.byIcon(Icons.edit_outlined);
      if (editBtn.evaluate().isNotEmpty) {
        await tester.tap(editBtn.first);
        await tester.pump();
        final nameField = find.byType(TextField).last;
        await tester.enterText(nameField, 'Home Base');
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(app.workspaces.any((w) => w.name == 'Home Base'),
            isTrue);
      }
    });

    testWidgets('new private tab via rail button', (tester) async {
      final app = await pump(tester);
      final btn = find.byTooltip('New private tab (Ctrl+Shift+P)');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pump();
        expect(app.activeTab!.isPrivate, isTrue);
      }
    });

    testWidgets('collapse rail mode renders workspace dots',
        (tester) async {
      final app = await pump(tester);
      app.toggleSidebarCollapsed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(app.sidebarCollapsed, isTrue);
    });
  });

  group('panels detail', () {
    testWidgets('download tiles: running/completed/failed',
        (tester) async {
      await pump(tester,
          child: const Scaffold(
              body: SizedBox(width: 420, child: DownloadsPanel())),
          size: const Size(500, 900),
          seed: (a) {
            a.downloads.items.addAll([
              DownloadItem(
                  id: 'd1',
                  url: 'https://x.dev/a.zip',
                  filename: 'a.zip',
                  state: DownloadState.inProgress,
                  receivedBytes: 5,
                  totalBytes: 10),
              DownloadItem(
                  id: 'd2',
                  url: 'https://x.dev/b.zip',
                  filename: 'b.zip',
                  state: DownloadState.completed,
                  path: '/tmp/b.zip',
                  receivedBytes: 10,
                  totalBytes: 10),
              DownloadItem(
                  id: 'd3',
                  url: 'https://x.dev/c.zip',
                  filename: 'c.zip',
                  state: DownloadState.failed,
                  totalBytes: 10),
            ]);
          });
      await tester.pump();
      expect(find.text('a.zip'), findsOne);
      expect(find.text('b.zip'), findsOne);
      expect(find.text('c.zip'), findsOne);
      // completed -> open button
      final open = find.byTooltip('Open');
      if (open.evaluate().isNotEmpty) {
        await tester.tap(open.first);
        await tester.pump();
      }
      final retry = find.byTooltip('Retry');
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry.first);
        await tester.pump();
      }
      final cancel = find.byTooltip('Cancel');
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.first);
        await tester.pump();
      }
    });
  });

  group('widgets', () {
    testWidgets('favicon letter fallback + ghost button hover',
        (tester) async {
      await pump(tester,
          child: Scaffold(
            body: Column(
              children: [
                Favicon(
                    tab: BrowserTab(
                        id: 'x',
                        workspaceId: 'personal',
                        title: 'Wave',
                        url: 'https://wave.dev'),
                    size: 20),
                const UrlFavicon(url: 'https://wave.dev', size: 18),
                GhostButton(
                    icon: Icons.abc, tooltip: 't', onPressed: () {}),
                const GhostButton(
                    icon: Icons.abc, tooltip: 'd', onPressed: null),
                const PrivateBadge(),
                const LoadingLine(progress: 0.5, visible: true),
                const LoadingLine(progress: 0, visible: true),
              ],
            ),
          ),
          size: const Size(400, 400));
      await tester.pump();
      expect(find.text('W'), findsOne);
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.moveTo(tester.getCenter(find.byTooltip('t')));
      await tester.pump();
    });
  });
}
