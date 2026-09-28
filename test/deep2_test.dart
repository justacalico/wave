import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wave/models.dart';
import 'package:wave/services/sync.dart';

import 'helpers.dart';

void main() {
  setUp(setupTestEnv);

  group('app_state sync paths', () {
    test('syncNow merges local + backend records into stores', () async {
      final app = await makeAppState();
      app.bookmarks.add(Bookmark(
          id: 'local-bm', url: 'https://a.dev', title: 'A'));
      app.recordVisit('https://h.dev', 'H');
      await app.vault.ensureKey();
      await app.vault.upsert(VaultEntry(
          id: 'v1', origin: 'https://s.dev', username: 'u', password: 'p'));
      final t = app.newTab(url: 'https://tab.dev');

      // remote-side records in the local backend
      await app.sync.local.upload('bookmarks', [
        SyncRecord(
            id: 'remote-bm',
            payload: jsonEncode(Bookmark(
                    id: 'remote-bm',
                    url: 'https://remote.dev',
                    title: 'R')
                .toJson()),
            modified: DateTime.now().millisecondsSinceEpoch / 1000),
      ]);

      await app.syncNow();
      expect(app.sync.status, SyncStatus.idle);
      expect(
          app.bookmarks.any((b) => b.id == 'remote-bm'), isTrue);
      expect(
          app.bookmarks.any((b) => b.id == 'local-bm'), isTrue);
      expect(app.sync.lastSyncAt, isNotNull);
      expect(t, isNotNull);
    });

    test('suspendInactiveTabs sleeps the oldest', () async {
      final app = await makeAppState();
      for (var i = 0; i < 9; i++) {
        app.newTab(url: 'https://t$i.dev', activate: i == 8);
      }
      app.suspendInactiveTabs(keepAlive: 6);
      expect(app.tabs.any((t) => t.suspended), isTrue);
      expect(app.tabs.last.suspended, isFalse);
    });

    test('submitOmnibox navigates + records history', () async {
      final app = await makeAppState();
      app.submitOmnibox('!g cats');
      expect(app.activeTab!.url,
          'https://www.google.com/search?q=cats');
      app.submitOmnibox('https://site.dev');
      expect(app.activeTab!.url, 'https://site.dev');
    });

    test('reloadTab + duplicateTab + openUrlInNewTab', () async {
      final app = await makeAppState();
      final t = app.newTab(url: 'https://a.dev');
      app.reloadTab(t.id);
      app.duplicateTab(t.id);
      expect(
          app.tabs.where((e) => e.url == 'https://a.dev').length, 2);
      app.openUrlInNewTab('https://new.dev');
      expect(app.activeTab!.url, 'https://new.dev');
    });

    test('credential save + lookup flow', () async {
      final app = await makeAppState();
      await app.vault.ensureKey();
      final t = app.newTab(url: 'https://login.dev');
      app.controllerFor(t).onCredentialRequest?.call(
          'login.dev', 'me', 'pw');
      await Future.delayed(Duration.zero);
      expect(app.pendingCredentialOrigin, 'login.dev');
      app.savePendingCredential();
      expect(
          app.vault.forOrigin('https://login.dev'), isNotEmpty);
    });
  });

  group('sync service edge paths', () {
    test('fxa backend without scope is not ready', () async {
      final app = await makeAppState();
      app.sync.setBackendChoice('fxa');
      expect(app.sync.backend.ready, isFalse);
      // syncCollections against a non-ready backend still merges local
      final merged = await app.sync.syncCollections(
          {'bookmarks': [SyncRecord(id: 'x', payload: '{}', modified: 0)]});
      expect(merged['bookmarks']!.single.id, 'x');
    });

    test('SyncException text', () {
      expect(SyncException('boom').toString(), contains('boom'));
    });

    test('syncCollections uploads local records for all collections',
        () async {
      final app = await makeAppState();
      app.bookmarks.add(Bookmark(
          id: 'b', url: 'https://x.dev', title: 'X'));
      app.recordVisit('https://y.dev', 'Y');
      await app.vault.ensureKey();
      await app.vault.upsert(VaultEntry(
          id: 'v', origin: 'https://z.dev', username: 'a', password: 'b'));
      app.newTab(url: 'https://t.dev');
      await app.syncNow();
      for (final col in
          ['bookmarks', 'history', 'passwords', 'tabs']) {
        final got = await app.sync.local.download(col);
        expect(got, isNotEmpty, reason: col);
      }
    });
  });
}
