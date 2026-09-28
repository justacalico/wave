import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../storage.dart';

/// Streams downloads to the platform Downloads folder (or app docs dir as a
/// fallback) and tracks them in Hive so the panel survives restarts.
class DownloadsService extends ChangeNotifier {
  DownloadsService();

  final List<DownloadItem> items = [];
  final Map<String, HttpClient> _clients = {};

  Future<void> restore() async {
    final raw = Storage.read(Storage.downloads, 'items');
    items
      ..clear()
      ..addAll(decodeJsonList(raw, DownloadItem.fromJson));
    // Anything left in-progress from a killed session is marked cancelled.
    for (final d in items) {
      if (d.state == DownloadState.inProgress) {
        d.state = DownloadState.cancelled;
      }
    }
  }

  Future<Directory> downloadDir() async {
    if (!kIsWeb) {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> start(String url, String filename) async {
    final dir = await downloadDir();
    var name = filename.isEmpty ? 'download' : filename;
    var target = File('${dir.path}/$name');
    var n = 1;
    while (await target.exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      name = '$stem-$n$ext';
      target = File('${dir.path}/$name');
      n++;
    }

    final item = DownloadItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      filename: name,
      path: target.path,
    );
    items.insert(0, item);
    _persist();
    notifyListeners();
    unawaited(_run(item, target));
  }

  Future<void> _run(DownloadItem item, File target) async {
    final client = HttpClient();
    _clients[item.id] = client;
    try {
      final req = await client.getUrl(Uri.parse(item.url));
      final res = await req.close();
      if (res.statusCode ~/ 100 != 2) {
        item.state = DownloadState.failed;
        await target.delete().catchError((_) => target);
        _finish(item);
        return;
      }
      item.totalBytes = res.contentLength;
      final sink = target.openWrite();
      try {
        await for (final chunk in res) {
          // A cancel while streaming owns the state from here on.
          if (item.state != DownloadState.inProgress) {
            _finish(item);
            return;
          }
          sink.add(chunk);
          item.receivedBytes += chunk.length;
          notifyListeners();
        }
        await sink.close();
        if (item.state == DownloadState.inProgress) {
          item.state = DownloadState.completed;
        }
      } catch (_) {
        await sink.close();
        await target.delete().catchError((_) => target);
        if (item.state == DownloadState.inProgress) {
          item.state = DownloadState.failed;
        }
      }
    } catch (_) {
      if (item.state == DownloadState.inProgress) {
        item.state = DownloadState.failed;
      }
    }
    _finish(item);
  }

  void _finish(DownloadItem item) {
    _clients.remove(item.id)?.close();
    _persist();
    notifyListeners();
  }

  void cancel(String id) {
    final item = items.firstWhere((d) => d.id == id);
    item.state = DownloadState.cancelled;
    _clients.remove(id)?.close(force: true);
    _persist();
    notifyListeners();
  }

  void clearFinished() {
    items.removeWhere((d) => d.state != DownloadState.inProgress);
    _persist();
    notifyListeners();
  }

  void _persist() {
    Storage.write(Storage.downloads, 'items',
        jsonEncode(items.take(200).map((d) => d.toJson()).toList()));
  }
}
