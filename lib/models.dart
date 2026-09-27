import 'dart:convert';

enum TabKind { normal, pinned, essential }

enum DownloadState { inProgress, completed, failed, cancelled }

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.workspaceId,
    this.url = '',
    this.title = 'New Tab',
    this.faviconUrl,
    this.kind = TabKind.normal,
    this.isPrivate = false,
    this.isLoading = false,
    this.readerMode = false,
    this.suspended = false,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  final String id;
  String workspaceId;
  String url;
  String title;
  String? faviconUrl;
  TabKind kind;
  bool isPrivate;
  bool isLoading;
  bool readerMode;
  bool suspended;
  DateTime createdAt;
  DateTime lastActiveAt;

  bool get isPinned => kind != TabKind.normal;

  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host ?? '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'url': url,
        'title': title,
        'faviconUrl': faviconUrl,
        'kind': kind.index,
        'isPrivate': isPrivate,
        'readerMode': readerMode,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
      };

  factory BrowserTab.fromJson(Map<String, dynamic> j) => BrowserTab(
        id: j['id'] as String,
        workspaceId: j['workspaceId'] as String,
        url: j['url'] as String? ?? '',
        title: j['title'] as String? ?? 'New Tab',
        faviconUrl: j['faviconUrl'] as String?,
        kind: TabKind.values[j['kind'] as int? ?? 0],
        isPrivate: j['isPrivate'] as bool? ?? false,
        readerMode: j['readerMode'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        lastActiveAt:
            DateTime.tryParse(j['lastActiveAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

class Workspace {
  Workspace({
    required this.id,
    required this.name,
    this.icon = 'wave',
    this.gradientIndex = 0,
  });

  final String id;
  String name;
  String icon;
  int gradientIndex;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'icon': icon, 'gradientIndex': gradientIndex};

  factory Workspace.fromJson(Map<String, dynamic> j) => Workspace(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String? ?? 'wave',
        gradientIndex: j['gradientIndex'] as int? ?? 0,
      );
}

class Bookmark {
  Bookmark({
    required this.id,
    required this.url,
    required this.title,
    this.faviconUrl,
    this.folder = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String url;
  String title;
  String? faviconUrl;
  String folder;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'faviconUrl': faviconUrl,
        'folder': folder,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id'] as String,
        url: j['url'] as String,
        title: j['title'] as String,
        faviconUrl: j['faviconUrl'] as String?,
        folder: j['folder'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}

class HistoryEntry {
  HistoryEntry({
    required this.url,
    required this.title,
    this.visitCount = 1,
    DateTime? lastVisited,
  }) : lastVisited = lastVisited ?? DateTime.now();

  final String url;
  String title;
  int visitCount;
  DateTime lastVisited;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'visitCount': visitCount,
        'lastVisited': lastVisited.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        url: j['url'] as String,
        title: j['title'] as String? ?? '',
        visitCount: j['visitCount'] as int? ?? 1,
        lastVisited: DateTime.tryParse(j['lastVisited'] as String? ?? ''),
      );
}

class DownloadItem {
  DownloadItem({
    required this.id,
    required this.url,
    required this.filename,
    this.path = '',
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.state = DownloadState.inProgress,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String id;
  final String url;
  String filename;
  String path;
  int totalBytes;
  int receivedBytes;
  DownloadState state;
  DateTime startedAt;

  double get progress =>
      totalBytes > 0 ? receivedBytes / totalBytes : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'path': path,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'state': state.index,
        'startedAt': startedAt.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        id: j['id'] as String,
        url: j['url'] as String,
        filename: j['filename'] as String,
        path: j['path'] as String? ?? '',
        totalBytes: j['totalBytes'] as int? ?? 0,
        receivedBytes: j['receivedBytes'] as int? ?? 0,
        state: DownloadState.values[j['state'] as int? ?? 0],
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? ''),
      );
}

class VaultEntry {
  VaultEntry({
    required this.id,
    required this.origin,
    required this.username,
    required this.password,
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String origin;
  String username;
  String password;
  String note;
  DateTime createdAt;
  DateTime updatedAt;

  String get host => Uri.tryParse(origin)?.host ?? origin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin': origin,
        'username': username,
        'password': password,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> j) => VaultEntry(
        id: j['id'] as String,
        origin: j['origin'] as String,
        username: j['username'] as String,
        password: j['password'] as String,
        note: j['note'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
      );
}

class SearchEngine {
  const SearchEngine({
    required this.id,
    required this.name,
    required this.bang,
    required this.template,
    required this.faviconUrl,
  });

  final String id;
  final String name;

  /// Short trigger like `!g`, `!ddg`, `!w`.
  final String bang;

  /// Contains `%s` where the query goes.
  final String template;
  final String faviconUrl;

  String urlFor(String query) =>
      template.replaceAll('%s', Uri.encodeComponent(query));

  static const List<SearchEngine> defaults = [
    SearchEngine(
      id: 'google',
      name: 'Google',
      bang: '!g',
      template: 'https://www.google.com/search?q=%s',
      faviconUrl: 'https://www.google.com/favicon.ico',
    ),
    SearchEngine(
      id: 'duckduckgo',
      name: 'DuckDuckGo',
      bang: '!ddg',
      template: 'https://duckduckgo.com/?q=%s',
      faviconUrl: 'https://duckduckgo.com/favicon.ico',
    ),
    SearchEngine(
      id: 'brave',
      name: 'Brave',
      bang: '!br',
      template: 'https://search.brave.com/search?q=%s',
      faviconUrl: 'https://search.brave.com/favicon.ico',
    ),
    SearchEngine(
      id: 'bing',
      name: 'Bing',
      bang: '!b',
      template: 'https://www.bing.com/search?q=%s',
      faviconUrl: 'https://www.bing.com/favicon.ico',
    ),
    SearchEngine(
      id: 'wikipedia',
      name: 'Wikipedia',
      bang: '!w',
      template: 'https://en.wikipedia.org/wiki/Special:Search?search=%s',
      faviconUrl: 'https://en.wikipedia.org/favicon.ico',
    ),
    SearchEngine(
      id: 'github',
      name: 'GitHub',
      bang: '!gh',
      template: 'https://github.com/search?q=%s',
      faviconUrl: 'https://github.com/favicon.ico',
    ),
    SearchEngine(
      id: 'youtube',
      name: 'YouTube',
      bang: '!yt',
      template: 'https://www.youtube.com/results?search_query=%s',
      faviconUrl: 'https://www.youtube.com/favicon.ico',
    ),
    SearchEngine(
      id: 'mdn',
      name: 'MDN',
      bang: '!mdn',
      template: 'https://developer.mozilla.org/en-US/search?q=%s',
      faviconUrl: 'https://developer.mozilla.org/favicon.ico',
    ),
  ];
}

class FxAProfile {
  const FxAProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.locale,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String? locale;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'locale': locale,
      };

  factory FxAProfile.fromJson(Map<String, dynamic> j) => FxAProfile(
        uid: j['uid'] as String,
        email: j['email'] as String? ?? '',
        displayName: j['displayName'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        locale: j['locale'] as String?,
      );
}

/// Helpers shared by serializers.
String encodeJsonList<T>(Iterable<T> items, Map<String, dynamic> Function(T) f) =>
    jsonEncode(items.map(f).toList());

List<T> decodeJsonList<T>(
        String? raw, T Function(Map<String, dynamic>) f) =>
    raw == null || raw.isEmpty
        ? <T>[]
        : (jsonDecode(raw) as List)
            .map((e) => f(Map<String, dynamic>.from(e as Map)))
            .toList();
