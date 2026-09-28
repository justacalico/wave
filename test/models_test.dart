import 'package:flutter_test/flutter_test.dart';
import 'package:wave/models.dart';

void main() {
  group('BrowserTab', () {
    test('json round trip', () {
      final tab = BrowserTab(
        id: 't1',
        workspaceId: 'w1',
        url: 'https://example.com',
        title: 'Example',
        kind: TabKind.pinned,
        isPrivate: true,
        readerMode: true,
      );
      final back = BrowserTab.fromJson(tab.toJson());
      expect(back.id, 't1');
      expect(back.workspaceId, 'w1');
      expect(back.url, 'https://example.com');
      expect(back.title, 'Example');
      expect(back.kind, TabKind.pinned);
      expect(back.isPrivate, isTrue);
      expect(back.readerMode, isTrue);
      expect(back.isPinned, isTrue);
      expect(back.host, 'example.com');
    });

    test('defaults', () {
      final tab = BrowserTab(id: 'x', workspaceId: 'w');
      expect(tab.url, '');
      expect(tab.title, 'New Tab');
      expect(tab.isPinned, isFalse);
      expect(tab.host, '');
    });
  });

  group('Workspace', () {
    test('json round trip', () {
      final ws =
          Workspace(id: 'w', name: 'Work', icon: 'briefcase', gradientIndex: 3);
      final back = Workspace.fromJson(ws.toJson());
      expect(back.name, 'Work');
      expect(back.icon, 'briefcase');
      expect(back.gradientIndex, 3);
    });
  });

  group('Bookmark', () {
    test('json round trip', () {
      final b = Bookmark(
          id: 'b1',
          url: 'https://a.dev',
          title: 'A',
          folder: 'dev');
      final back = Bookmark.fromJson(b.toJson());
      expect(back.url, 'https://a.dev');
      expect(back.folder, 'dev');
    });
  });

  group('HistoryEntry', () {
    test('json round trip', () {
      final h = HistoryEntry(
          url: 'https://a.dev', title: 'A', visitCount: 3);
      final back = HistoryEntry.fromJson(h.toJson());
      expect(back.visitCount, 3);
      expect(back.url, 'https://a.dev');
    });
  });

  group('DownloadItem', () {
    test('progress', () {
      final d = DownloadItem(
          id: 'd',
          url: 'u',
          filename: 'f.zip',
          totalBytes: 200,
          receivedBytes: 50);
      expect(d.progress, 0.25);
      final empty = DownloadItem(id: 'e', url: 'u', filename: 'f');
      expect(empty.progress, 0);
    });

    test('json round trip', () {
      final d = DownloadItem(
          id: 'd',
          url: 'u',
          filename: 'f.zip',
          path: '/tmp/f.zip',
          state: DownloadState.completed);
      final back = DownloadItem.fromJson(d.toJson());
      expect(back.state, DownloadState.completed);
      expect(back.path, '/tmp/f.zip');
    });
  });

  group('VaultEntry', () {
    test('json round trip + host', () {
      final e = VaultEntry(
          id: 'v1',
          origin: 'https://github.com',
          username: 'cal',
          password: 's3cret');
      final back = VaultEntry.fromJson(e.toJson());
      expect(back.host, 'github.com');
      expect(back.username, 'cal');
    });
  });

  group('SearchEngine', () {
    test('urlFor encodes query', () {
      final g = SearchEngine.defaults.first;
      expect(g.urlFor('hello world'),
          'https://www.google.com/search?q=hello%20world');
    });

    test('defaults all have bangs', () {
      for (final e in SearchEngine.defaults) {
        expect(e.bang.startsWith('!'), isTrue, reason: e.id);
        expect(e.template.contains('%s'), isTrue, reason: e.id);
      }
    });
  });

  group('FxAProfile', () {
    test('json round trip', () {
      const p = FxAProfile(
          uid: 'u1', email: 'a@b.c', displayName: 'Cal', avatarUrl: 'https://x/y.png');
      final back = FxAProfile.fromJson(p.toJson());
      expect(back.email, 'a@b.c');
      expect(back.displayName, 'Cal');
    });
  });

  group('json list helpers', () {
    test('decode empty', () {
      expect(decodeJsonList(null, Workspace.fromJson), isEmpty);
      expect(decodeJsonList('', Workspace.fromJson), isEmpty);
    });

    test('encode/decode', () {
      final items = [Workspace(id: 'a', name: 'A')];
      final raw = encodeJsonList(items, (w) => w.toJson());
      final back = decodeJsonList(raw, Workspace.fromJson);
      expect(back.single.name, 'A');
    });
  });
}
