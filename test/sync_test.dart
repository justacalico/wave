import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wave/services/sync.dart';

import 'helpers.dart';

void main() {
  setUp(setupTestEnv);

  group('SyncRecord', () {
    test('json round trip', () {
      final r = SyncRecord(id: 'a', payload: '{"x":1}', modified: 42.5);
      final back = SyncRecord.fromJson(r.toJson());
      expect(back.id, 'a');
      expect(back.modified, 42.5);
    });
  });

  group('LocalSyncBackend', () {
    test('upload + download round trips and merges by modified', () async {
      final b = LocalSyncBackend();
      final t = DateTime.now().millisecondsSinceEpoch / 1000;
      await b.upload('bookmarks', [
        SyncRecord(id: 'a', payload: 'v1', modified: t - 100),
        SyncRecord(id: 'b', payload: 'v1', modified: t - 50),
      ]);
      var got = await b.download('bookmarks');
      expect(got.length, 2);

      // Older payload loses, newer wins.
      await b.upload('bookmarks', [
        SyncRecord(id: 'a', payload: 'old', modified: t - 300),
        SyncRecord(id: 'b', payload: 'v2', modified: t),
      ]);
      got = await b.download('bookmarks');
      expect(got.firstWhere((r) => r.id == 'a').payload, 'v1');
      expect(got.firstWhere((r) => r.id == 'b').payload, 'v2');

      // Incremental fetch.
      final fresh = await b.download('bookmarks', since: t - 1);
      expect(fresh.single.id, 'b');
    });
  });

  group('SelfHostedSyncBackend', () {
    test('round trip against a loopback relay', () async {
      // flutter_test installs a fake HttpClient globally; removing the
      // override restores the real client so we can hit the loopback relay.
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = null);
      final store = <String, List<Map<String, dynamic>>>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        final parts = req.uri.pathSegments; // v1/<collection>
        final col = parts.length > 1 ? parts[1] : 'x';
        if (req.method == 'PUT') {
          final body =
              jsonDecode(await utf8.decoder.bind(req).join());
          store.putIfAbsent(col, () => []);
          for (final r in (body['records'] as List)) {
            final m = Map<String, dynamic>.from(r);
            final i = store[col]!.indexWhere((e) => e['id'] == m['id']);
            if (i >= 0) {
              store[col]![i] = m;
            } else {
              store[col]!.add(m);
            }
          }
          req.response.write(jsonEncode({
            'modified':
                DateTime.now().millisecondsSinceEpoch / 1000.0
          }));
        } else {
          final since =
              double.tryParse(req.uri.queryParameters['since'] ?? '0') ??
                  0;
          final recs = (store[col] ?? [])
              .where((r) => (r['modified'] as num) > since)
              .toList();
          req.response.write(jsonEncode({'records': recs}));
        }
        await req.response.close();
      });

      final relay = SelfHostedSyncBackend(
          baseUrl: 'http://127.0.0.1:${server.port}', token: 't');
      expect(relay.ready, isTrue);
      await relay.upload('bookmarks',
          [SyncRecord(id: 'a', payload: 'p', modified: 5)]);
      final got = await relay.download('bookmarks');
      expect(got.single.id, 'a');
      expect(got.single.payload, 'p');
    });
  });

  group('SyncService', () {
    test('backend selection honors settings', () async {
      final app = await makeAppState();
      expect(app.sync.backend.id, 'local');
      app.sync.configureRelay('http://x.dev', 'tok');
      // auto picks relay when configured
      expect(app.sync.backend.id, 'selfhosted');
      app.sync.setBackendChoice('fxa');
      expect(app.sync.backend.id, 'fxa');
      expect(app.sync.backend.ready, isFalse); // no sync scope
      app.sync.setBackendChoice('local');
      expect(app.sync.backend.id, 'local');
    });

    test('syncCollections merges local + remote last-write-wins', () async {
      final app = await makeAppState();
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      // Seed the "remote" local backend with a record.
      await app.sync.local.upload('bookmarks',
          [SyncRecord(id: 'remote-1', payload: '{}', modified: now)]);

      final merged = await app.sync.syncCollections({
        'bookmarks': [
          SyncRecord(id: 'local-1', payload: '{}', modified: now - 10),
        ],
      });
      expect(app.sync.status, SyncStatus.idle);
      final ids = merged['bookmarks']!.map((r) => r.id).toSet();
      expect(ids, containsAll(['local-1', 'remote-1']));
      expect(app.sync.lastSyncAt, isNotNull);
    });
  });
}
