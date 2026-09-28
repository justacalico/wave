import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wave/app_state.dart';
import 'package:wave/models.dart';

import 'helpers.dart';

void main() {
  group('AppState workspaces', () {
    test('seeds two workspaces when empty', () async {
      final app = await makeAppState();
      expect(app.workspaces.length, greaterThanOrEqualTo(2));
      expect(app.workspaces.map((w) => w.id), contains('personal'));
    });

    test('switch workspace creates a tab when empty', () async {
      final app = await makeAppState();
      app.addWorkspace('Reading', 'book', 2);
      final ws = app.workspaces.firstWhere((w) => w.name == 'Reading');
      expect(app.activeWorkspaceId, ws.id);
      expect(app.workspaceTabs, isNotEmpty);
    });

    test('rename and remove workspace', () async {
      final app = await makeAppState();
      app.renameWorkspace('work', 'Job', 5);
      expect(app.workspaces.firstWhere((w) => w.id == 'work').name, 'Job');
      expect(app.workspaces.firstWhere((w) => w.id == 'work').gradientIndex, 5);
      app.removeWorkspace('work');
      expect(app.workspaces.any((w) => w.id == 'work'), isFalse);
    });

    test('cannot remove the last workspace', () async {
      final app = await makeAppState();
      while (app.workspaces.length > 1) {
        app.removeWorkspace(app.workspaces.last.id);
      }
      expect(app.workspaces.length, 1);
    });
  });

  group('AppState tabs', () {
    test('new tab activates and lands in active workspace', () async {
      final app = await makeAppState();
      final before = app.workspaceTabs.length;
      final t = app.newTab(url: 'https://example.com');
      expect(app.activeTabId, t.id);
      expect(app.workspaceTabs.length, before + 1);
      expect(t.workspaceId, app.activeWorkspaceId);
    });

    test('openUrl updates active tab', () async {
      final app = await makeAppState();
      app.openUrl('https://flutter.dev');
      expect(app.activeTab!.url, 'https://flutter.dev');
    });

    test('close tab picks another tab in the workspace', () async {
      final app = await makeAppState();
      app.newTab(url: "https://a.dev");
      app.newTab(url: 'https://b.dev');
      app.closeTab(app.activeTabId!);
      expect(app.activeTabId, isNotNull);
      expect(app.tabs.any((t) => t.id == app.activeTabId), isTrue);
    });

    test('closing the last tab opens a fresh one', () async {
      final app = await makeAppState();
      for (final t in app.tabs.toList()) {
        app.closeTab(t.id);
      }
      expect(app.workspaceTabs, isNotEmpty);
      expect(app.activeTabId, isNotNull);
    });

    test('pin and essential kinds', () async {
      final app = await makeAppState();
      final t = app.newTab(url: 'https://pin.dev');
      app.setTabKind(t.id, TabKind.pinned);
      expect(app.pinnedTabs.single.id, t.id);
      app.setTabKind(t.id, TabKind.essential);
      expect(app.essentialTabs.single.id, t.id);
      app.setTabKind(t.id, TabKind.normal);
      expect(app.pinnedTabs, isEmpty);
      expect(app.essentialTabs, isEmpty);
    });

    test('reorderTab moves entries', () async {
      final app = await makeAppState();
      app.newTab(url: 'https://1.dev');
      app.newTab(url: 'https://2.dev');
      app.newTab(url: 'https://3.dev');
      final ids = app.normalTabs.map((t) => t.url).toList();
      app.reorderTab(app.activeWorkspaceId, 0, 2);
      final after = app.normalTabs.map((t) => t.url).toList();
      expect(after[0], ids[1]);
      expect(after[2], ids[0]);
    });

    test('moveTabToWorkspace relocates', () async {
      final app = await makeAppState();
      final t = app.newTab(url: 'https://move.dev');
      app.moveTabToWorkspace(t.id, 'work');
      expect(app.tabs.firstWhere((e) => e.id == t.id).workspaceId, 'work');
      expect(app.workspaceTabs.any((e) => e.id == t.id), isFalse);
      app.switchWorkspace('work');
      expect(app.workspaceTabs.any((e) => e.id == t.id), isTrue);
    });

    test('split view toggles', () async {
      final app = await makeAppState();
      final other = app.newTab(url: 'https://x.dev', activate: false);
      app.toggleSplitWith(other.id);
      expect(app.splitTabId, other.id);
      app.toggleSplitWith(other.id);
      expect(app.splitTabId, isNull);
      app.toggleSplitWith(other.id);
      app.closeSplit();
      expect(app.splitTabId, isNull);
    });

    test('tabs persist across restart', () async {
      final app = await makeAppState();
      app.newTab(url: 'https://persist.dev');
      app.newTab(url: 'https://private.dev', isPrivate: true);
      final app2 = await restartApp();
      expect(app2.tabs.any((t) => t.url == 'https://persist.dev'), isTrue);
      expect(app2.tabs.any((t) => t.url == 'https://private.dev'), isFalse);
    });
  });

  group('omnibox resolution', () {
    test('bangs route to engines', () async {
      final app = await makeAppState();
      expect(app.resolveInput('!g cats'),
          'https://www.google.com/search?q=cats');
      expect(app.resolveInput('cats !ddg'),
          'https://duckduckgo.com/?q=cats');
      expect(app.resolveInput('!w flutter'),
          contains('wikipedia.org'));
    });

    test('urls pass through', () async {
      final app = await makeAppState();
      expect(app.resolveInput('https://a.dev/x'), 'https://a.dev/x');
      expect(app.resolveInput('example.com'), 'https://example.com');
      expect(app.resolveInput('localhost:8080'), 'https://localhost:8080');
    });

    test('bare words become searches', () async {
      final app = await makeAppState();
      app.setSearchEngine('duckduckgo');
      expect(app.resolveInput('hello world'),
          'https://duckduckgo.com/?q=hello%20world');
      expect(app.resolveInput('singleword'),
          'https://duckduckgo.com/?q=singleword');
    });

    test('empty input', () async {
      final app = await makeAppState();
      expect(app.resolveInput('   '), '');
    });
  });

  group('bookmarks + history', () {
    test('toggle bookmark', () async {
      final app = await makeAppState();
      final t = app.newTab(url: 'https://bm.dev');
      expect(app.isBookmarked('https://bm.dev'), isFalse);
      app.toggleBookmark(t);
      expect(app.isBookmarked('https://bm.dev'), isTrue);
      app.toggleBookmark(t);
      expect(app.isBookmarked('https://bm.dev'), isFalse);
    });

    test('history records visits and bumps count', () async {
      final app = await makeAppState();
      app.recordVisit('https://h.dev', 'H');
      app.recordVisit('https://h.dev', 'H');
      app.recordVisit('https://other.dev', 'O');
      expect(app.history.first.url, 'https://other.dev');
      expect(app.history[1].visitCount, 2);
      app.removeHistoryEntry('https://h.dev');
      expect(app.history.any((h) => h.url == 'https://h.dev'), isFalse);
      app.clearHistory();
      expect(app.history, isEmpty);
    });

    test('private tabs skip history', () async {
      final app = await makeAppState();
      final t = app.newTab(isPrivate: true);
      app.controllerFor(t).onUrlChanged?.call('https://secret.dev');
      expect(app.history.any((h) => h.url == 'https://secret.dev'), isFalse);
    });

    test('suggestions rank bookmarks over history', () async {
      final app = await makeAppState();
      app.recordVisit('https://news.dev', 'Daily News');
      app.toggleBookmark(BrowserTab(id: 'b', workspaceId: 'w', url: 'https://news.dev', title: 'Daily News'));
      final hits = app.suggestions('news');
      expect(hits, isNotEmpty);
      expect(hits.first, isA<Bookmark>());
    });
  });

  group('panels + settings', () {
    test('panel toggles', () async {
      final app = await makeAppState();
      app.showPanel(ActivePanel.history);
      expect(app.activePanel, ActivePanel.history);
      app.showPanel(ActivePanel.history);
      expect(app.activePanel, ActivePanel.none);
      app.showPanel(ActivePanel.settings);
      app.closePanel();
      expect(app.activePanel, ActivePanel.none);
    });

    test('settings round trip through restart', () async {
      final app = await makeAppState();
      app.setThemeMode(ThemeMode.dark);
      app.setSearchEngine('brave');
      app.setRestoreTabs(false);
      final app2 = await restartApp();
      expect(app2.themeMode, ThemeMode.dark);
      expect(app2.searchEngineId, 'brave');
      expect(app2.restoreTabs, isFalse);
    });

    test('find bar state', () async {
      final app = await makeAppState();
      app.setFindBar(true, query: 'needle');
      expect(app.findBarVisible, isTrue);
      expect(app.findQuery, 'needle');
      app.setFindBar(false);
      expect(app.findBarVisible, isFalse);
    });

    test('sidebar collapse persists', () async {
      final app = await makeAppState();
      app.toggleSidebarCollapsed();
      expect(app.sidebarCollapsed, isTrue);
      final app2 = await restartApp();
      expect(app2.sidebarCollapsed, isTrue);
      app2.toggleSidebar();
      expect(app2.sidebarVisible, isFalse);
    });
  });

  group('credentials', () {
    test('credential prompt surfaces origin', () async {
      final app = await makeAppState(preseed: fakeVaultKey);
      final t = app.newTab(url: 'https://login.dev');
      app.controllerFor(t).onCredentialRequest?.call('login.dev', 'me', 'pw');
      expect(app.pendingCredentialOrigin, 'login.dev');
      expect(app.pendingCredentialTabId, t.id);
      app.clearPendingCredential();
      expect(app.pendingCredentialOrigin, isNull);
    });
  });
}
