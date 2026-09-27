import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'services/downloads.dart';
import 'services/fxa.dart';
import 'services/sync.dart';
import 'services/vault.dart';
import 'storage.dart';
import 'webview/companion_adapter.dart';
import 'webview/controller.dart';

enum ActivePanel { none, bookmarks, history, downloads, vault, settings, account }

/// Everything Wave knows, in one ChangeNotifier created once in main() above
/// MaterialApp. Window resizes swap layouts only — they never touch this.
class AppState extends ChangeNotifier {
  AppState();

  // ---- Services ----------------------------------------------------------

  final FxaService fxa = FxaService();
  late final SyncService sync = SyncService(fxa);
  final VaultService vault = VaultService();
  final DownloadsService downloads = DownloadsService();

  // ---- Browsing state ----------------------------------------------------

  final List<Workspace> workspaces = [];
  String activeWorkspaceId = '';

  /// All open tabs across workspaces, in creation order.
  final List<BrowserTab> tabs = [];
  String? activeTabId;

  /// Secondary tab shown side-by-side in split view.
  String? splitTabId;

  final Map<String, TabWebController> _controllers = {};

  final List<Bookmark> bookmarks = [];
  final List<HistoryEntry> history = [];

  // ---- Settings ----------------------------------------------------------

  ThemeMode themeMode = ThemeMode.system;
  String searchEngineId = 'google';
  bool sidebarCollapsed = false;
  bool sidebarVisible = true;
  bool restoreTabs = true;
  bool recordHistory = true;
  bool blockPopups = false;
  double readerFontSize = 18;

  // ---- Transient UI state ------------------------------------------------

  ActivePanel activePanel = ActivePanel.none;
  bool findBarVisible = false;
  String findQuery = '';
  bool readerSheetOpen = false;
  Map<String, dynamic>? readerData;

  bool get isCompact => sidebarCollapsed;

  // ------------------------------------------------------------------------
  // Init / persistence
  // ------------------------------------------------------------------------

  Future<void> init() async {
    await Storage.init();
    await fxa.restore();
    await vault.restore();
    await downloads.restore();
    sync.restore();
    _loadSettings();
    _loadWorkspacesAndTabs();
    _loadBookmarks();
    _loadHistory();
    notifyListeners();
  }

  void _loadSettings() {
    final s = Storage.settings;
    themeMode = ThemeMode.values[s.get('themeMode', defaultValue: 0) as int];
    searchEngineId = s.get('searchEngineId', defaultValue: 'google') as String;
    sidebarCollapsed = s.get('sidebarCollapsed', defaultValue: false) as bool;
    sidebarVisible = s.get('sidebarVisible', defaultValue: true) as bool;
    restoreTabs = s.get('restoreTabs', defaultValue: true) as bool;
    recordHistory = s.get('recordHistory', defaultValue: true) as bool;
    readerFontSize = s.get('readerFontSize', defaultValue: 18.0) as double;
  }

  void _saveSettings() {
    final s = Storage.settings;
    s.put('themeMode', themeMode.index);
    s.put('searchEngineId', searchEngineId);
    s.put('sidebarCollapsed', sidebarCollapsed);
    s.put('sidebarVisible', sidebarVisible);
    s.put('restoreTabs', restoreTabs);
    s.put('recordHistory', recordHistory);
    s.put('readerFontSize', readerFontSize);
  }

  void _loadWorkspacesAndTabs() {
    final wsRaw = Storage.read(Storage.workspaces, 'list');
    workspaces.addAll(decodeJsonList(wsRaw, Workspace.fromJson));
    if (workspaces.isEmpty) {
      workspaces.add(Workspace(
          id: 'personal', name: 'Personal', icon: 'wave', gradientIndex: 0));
      workspaces.add(Workspace(
          id: 'work', name: 'Work', icon: 'briefcase', gradientIndex: 3));
      _saveWorkspaces();
    }
    final savedWs = Storage.read(Storage.workspaces, 'active');
    activeWorkspaceId = savedWs != null &&
            savedWs.isNotEmpty &&
            workspaces.any((w) => w.id == savedWs)
        ? savedWs
        : workspaces.first.id;

    if (restoreTabs) {
      final tabsRaw = Storage.read(Storage.tabs, 'list');
      for (final t in decodeJsonList(tabsRaw, BrowserTab.fromJson)) {
        if (!t.isPrivate &&
            workspaces.any((w) => w.id == t.workspaceId)) {
          tabs.add(t);
          controllerFor(t);
        }
      }
      activeTabId = Storage.read(Storage.tabs, 'active');
      if (activeTabId == null ||
          !tabs.any((t) => t.id == activeTabId)) {
        activeTabId = tabs.isEmpty ? null : tabs.first.id;
      }
    }
    if (tabs.isEmpty) {
      final t = newTab(workspaceId: activeWorkspaceId, notify: false);
      activeTabId = t.id;
    }
  }

  void _saveWorkspaces() {
    Storage.write(Storage.workspaces, 'list',
        jsonEncode(workspaces.map((w) => w.toJson()).toList()));
    if (activeWorkspaceId.isNotEmpty) {
      Storage.write(Storage.workspaces, 'active', activeWorkspaceId);
    }
  }

  void _saveTabs() {
    final persistable =
        tabs.where((t) => !t.isPrivate && t.url.isNotEmpty).toList();
    Storage.write(Storage.tabs, 'list',
        jsonEncode(persistable.map((t) => t.toJson()).toList()));
    Storage.write(Storage.tabs, 'active', activeTabId ?? '');
  }

  void _loadBookmarks() {
    final raw = Storage.read(Storage.bookmarks, 'list');
    bookmarks.addAll(decodeJsonList(raw, Bookmark.fromJson));
  }

  void _saveBookmarks() {
    Storage.write(Storage.bookmarks, 'list',
        jsonEncode(bookmarks.map((b) => b.toJson()).toList()));
  }

  void _loadHistory() {
    final raw = Storage.read(Storage.history, 'list');
    history.addAll(decodeJsonList(raw, HistoryEntry.fromJson));
  }

  void _saveHistory() {
    Storage.write(Storage.history, 'list',
        jsonEncode(history.take(5000).map((h) => h.toJson()).toList()));
  }

  // ------------------------------------------------------------------------
  // Workspaces
  // ------------------------------------------------------------------------

  Workspace get activeWorkspace => workspaces.firstWhere(
      (w) => w.id == activeWorkspaceId,
      orElse: () => workspaces.first);

  void switchWorkspace(String id) {
    if (id == activeWorkspaceId) return;
    activeWorkspaceId = id;
    final wsTabs = tabsFor(id);
    if (wsTabs.isEmpty) {
      final t = newTab(workspaceId: id);
      activeTabId = t.id;
    } else {
      activeTabId = wsTabs.last.id;
      wsTabs.last.lastActiveAt = DateTime.now();
    }
    splitTabId = null;
    _saveWorkspaces();
    _saveTabs();
    notifyListeners();
  }

  void addWorkspace(String name, String icon, int gradientIndex) {
    final id = 'ws-${DateTime.now().microsecondsSinceEpoch}';
    workspaces.add(Workspace(
        id: id, name: name, icon: icon, gradientIndex: gradientIndex));
    _saveWorkspaces();
    notifyListeners();
    switchWorkspace(id);
  }

  void renameWorkspace(String id, String name, int? gradientIndex) {
    final w = workspaces.firstWhere((e) => e.id == id);
    w.name = name;
    if (gradientIndex != null) w.gradientIndex = gradientIndex;
    _saveWorkspaces();
    notifyListeners();
  }

  void removeWorkspace(String id) {
    if (workspaces.length <= 1) return;
    for (final t in tabs.where((t) => t.workspaceId == id).toList()) {
      closeTab(t.id);
    }
    workspaces.removeWhere((w) => w.id == id);
    if (activeWorkspaceId == id) {
      activeWorkspaceId = workspaces.first.id;
      final wsTabs = tabsFor(activeWorkspaceId);
      activeTabId = wsTabs.isEmpty ? null : wsTabs.last.id;
      activeTabId ??= newTab(workspaceId: activeWorkspaceId).id;
    }
    _saveWorkspaces();
    _saveTabs();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Tabs
  // ------------------------------------------------------------------------

  List<BrowserTab> tabsFor(String workspaceId) =>
      tabs.where((t) => t.workspaceId == workspaceId).toList();

  List<BrowserTab> get workspaceTabs => tabsFor(activeWorkspaceId);

  List<BrowserTab> get pinnedTabs =>
      workspaceTabs.where((t) => t.kind == TabKind.pinned).toList();

  List<BrowserTab> get essentialTabs =>
      workspaceTabs.where((t) => t.kind == TabKind.essential).toList();

  List<BrowserTab> get normalTabs =>
      workspaceTabs.where((t) => t.kind == TabKind.normal).toList();

  BrowserTab? get activeTab {
    final id = activeTabId;
    if (id == null) return null;
    return tabs.where((t) => t.id == id).firstOrNull;
  }

  BrowserTab? get splitTab {
    final id = splitTabId;
    if (id == null) return null;
    return tabs.where((t) => t.id == id).firstOrNull;
  }

  TabWebController controllerFor(BrowserTab tab) =>
      _controllers.putIfAbsent(tab.id, () => _wireController(tab));

  TabWebController? controllerOf(String tabId) => _controllers[tabId];

  TabWebController _wireController(BrowserTab tab) {
    final c = WebEngine.create(tab);
    c.onUrlChanged = (url) => _onTabUrl(tab, url);
    c.onTitleChanged = (title) => _onTabTitle(tab, title);
    c.onNewWindow = (url) => openUrlInNewTab(url);
    c.onDownloadStart = (url, filename) =>
        unawaited(downloads.start(url, filename));
    c.onCredentialRequest =
        (origin, user, pass) => _onCredentialSubmit(tab, origin, user, pass);
    return c;
  }

  void _onTabUrl(BrowserTab tab, String url) {
    if (tab.url != url) {
      tab.url = url;
      if (!tab.isPrivate && recordHistory && url.isNotEmpty) {
        recordVisit(url, tab.title);
      }
      _saveTabs();
      notifyListeners();
    }
  }

  void _onTabTitle(BrowserTab tab, String title) {
    if (tab.title != title && title.isNotEmpty) {
      tab.title = title;
      if (!tab.isPrivate && recordHistory && tab.url.isNotEmpty) {
        final h = history.where((e) => e.url == tab.url).firstOrNull;
        if (h != null) {
          h.title = title;
          _saveHistory();
        }
      }
      _saveTabs();
      notifyListeners();
    }
  }

  void _onCredentialSubmit(
      BrowserTab tab, String origin, String user, String pass) {
    // Re-surfaced to the UI via a pending-prompt flag.
    pendingCredentialOrigin = origin;
    pendingCredentialTabId = tab.id;
    pendingCredentialUser = user;
    pendingCredentialPassword = pass;
    notifyListeners();
  }

  /// Set when a page submits a password form; the shell shows a save sheet.
  String? pendingCredentialOrigin;
  String? pendingCredentialTabId;
  String? pendingCredentialUser;
  String? pendingCredentialPassword;

  void clearPendingCredential() {
    pendingCredentialOrigin = null;
    pendingCredentialTabId = null;
    pendingCredentialUser = null;
    pendingCredentialPassword = null;
    notifyListeners();
  }

  /// Persist the pending credential into the vault under the page origin.
  Future<void> savePendingCredential() async {
    final origin = pendingCredentialOrigin;
    if (origin == null || origin.isEmpty) return;
    await vault.upsert(VaultEntry(
      id: 'cred-${DateTime.now().microsecondsSinceEpoch}',
      origin: 'https://$origin',
      username: pendingCredentialUser ?? '',
      password: pendingCredentialPassword ?? '',
    ));
    clearPendingCredential();
  }

  BrowserTab newTab({
    String? url,
    String? workspaceId,
    bool isPrivate = false,
    bool activate = true,
    bool notify = true,
  }) {
    final ws = workspaceId ?? activeWorkspaceId;
    final tab = BrowserTab(
      id: 'tab-${DateTime.now().microsecondsSinceEpoch}-'
          '${tabs.length}',
      workspaceId: ws,
      url: url ?? '',
      title: (url ?? '').isEmpty ? 'New Tab' : _titleFromUrl(url!),
      isPrivate: isPrivate,
      createdAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
    );
    tabs.add(tab);
    controllerFor(tab);
    if (activate) {
      activeTabId = tab.id;
      if (ws != activeWorkspaceId) activeWorkspaceId = ws;
    }
    _syncEngineVisibility();
    _saveTabs();
    _saveWorkspaces();
    if (notify) notifyListeners();
    return tab;
  }

  void openUrl(String url, {BrowserTab? tab}) {
    final t = tab ?? activeTab;
    if (t == null) {
      newTab(url: url);
      return;
    }
    t.url = url;
    t.readerMode = false;
    readerSheetOpen = false;
    unawaited(controllerFor(t).loadUrl(url));
    _saveTabs();
    notifyListeners();
  }

  void openUrlInNewTab(String url) {
    newTab(url: url, isPrivate: activeTab?.isPrivate ?? false);
  }

  void activateTab(String id) {
    if (activeTabId == id) return;
    activeTabId = id;
    final t = activeTab;
    if (t != null) {
      t.lastActiveAt = DateTime.now();
      t.suspended = false;
      if (splitTabId == id) splitTabId = null;
    }
    _syncEngineVisibility();
    _saveTabs();
    notifyListeners();
  }

  void closeTab(String id) {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final closing = tabs[index];
    tabs.removeAt(index);
    unawaited(_controllers.remove(id)?.dispose() ?? Future.value());
    if (splitTabId == id) splitTabId = null;
    if (activeTabId == id) {
      final wsTabs = tabsFor(closing.workspaceId);
      if (wsTabs.isNotEmpty) {
        // Prefer the tab that was active most recently in this workspace.
        wsTabs.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
        activeTabId = wsTabs.first.id;
      } else {
        activeTabId = null;
        if (closing.workspaceId == activeWorkspaceId) {
          activeTabId = newTab(workspaceId: closing.workspaceId).id;
        }
      }
    }
    _syncEngineVisibility();
    _saveTabs();
    notifyListeners();
  }

  /// [newIndex] is the destination index already adjusted by
  /// ReorderableListView's onReorderItem contract.
  void reorderTab(String workspaceId, int oldIndex, int newIndex) {
    final wsTabs = tabsFor(workspaceId);
    if (oldIndex < 0 || oldIndex >= wsTabs.length) return;
    if (newIndex > wsTabs.length) newIndex = wsTabs.length;
    final t = wsTabs.removeAt(oldIndex);
    wsTabs.insert(newIndex, t);
    // Rebuild global order: everything not in this workspace keeps position.
    tabs.removeWhere((e) => e.workspaceId == workspaceId);
    tabs.addAll(wsTabs);
    _saveTabs();
    notifyListeners();
  }

  void setTabKind(String id, TabKind kind) {
    final t = tabs.firstWhere((e) => e.id == id);
    t.kind = kind;
    _saveTabs();
    notifyListeners();
  }

  void moveTabToWorkspace(String tabId, String workspaceId) {
    final t = tabs.firstWhere((e) => e.id == tabId);
    if (t.workspaceId == workspaceId) return;
    t.workspaceId = workspaceId;
    if (activeTabId == tabId) {
      final remaining = tabsFor(activeWorkspaceId);
      activeTabId = remaining.isEmpty ? null : remaining.last.id;
      activeTabId ??= newTab(workspaceId: activeWorkspaceId).id;
    }
    _saveTabs();
    notifyListeners();
  }

  void reloadTab(String id) =>
      unawaited(_controllers[id]?.reload() ?? Future.value());

  /// Clone a tab — same url, same workspace, lands next to the original.
  BrowserTab? duplicateTab(String id) {
    final src = tabs.firstWhereOrNull((t) => t.id == id);
    if (src == null) return null;
    final t = newTab(
        url: src.url,
        workspaceId: src.workspaceId,
        isPrivate: src.isPrivate);
    return t;
  }

  void suspendInactiveTabs({int keepAlive = 6}) {
    final active = workspaceTabs
        .where((t) => !t.suspended && t.id != activeTabId)
        .toList()
      ..sort((a, b) => a.lastActiveAt.compareTo(b.lastActiveAt));
    for (var i = 0; i + keepAlive < active.length; i++) {
      active[i].suspended = true;
      final c = _controllers[active[i].id];
      if (c is CompanionTabController) {
        unawaited(c.dispose());
        _controllers.remove(active[i].id);
      }
    }
    notifyListeners();
  }

  /// Engine visibility for the companion-window platform.
  void _syncEngineVisibility() {
    if (!WebEngine.usesCompanion) return;
    for (final entry in _controllers.entries) {
      final c = entry.value;
      if (c is CompanionTabController) {
        c.setEngineVisible(
            entry.key == activeTabId || entry.key == splitTabId);
      }
    }
  }

  void activateCompanionIfNeeded() {
    final id = activeTabId;
    if (id == null) return;
    final c = _controllers[id];
    if (c is CompanionTabController && (activeTab?.url.isNotEmpty ?? false)) {
      unawaited(c.ensureCreated());
    }
    _syncEngineVisibility();
  }

  static String _titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.host;
  }

  // ------------------------------------------------------------------------
  // Split view
  // ------------------------------------------------------------------------

  void toggleSplitWith(String tabId) {
    if (splitTabId == tabId) {
      splitTabId = null;
    } else if (tabId != activeTabId) {
      splitTabId = tabId;
    }
    _syncEngineVisibility();
    notifyListeners();
  }

  void closeSplit() {
    splitTabId = null;
    _syncEngineVisibility();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Navigation input (omnibox)
  // ------------------------------------------------------------------------

  SearchEngine get searchEngine => SearchEngine.defaults.firstWhere(
      (e) => e.id == searchEngineId,
      orElse: () => SearchEngine.defaults.first);

  /// Turns omnibox text into a URL: bangs, then URLs, then search.
  String resolveInput(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return '';

    // Search engine bangs: "!g recipe" or "recipe !g".
    for (final e in SearchEngine.defaults) {
      if (input.startsWith('${e.bang} ') || input.endsWith(' ${e.bang}')) {
        final q = input.replaceAll(e.bang, '').trim();
        return e.urlFor(q);
      }
    }

    if (_looksLikeUrl(input)) return _normalizeUrl(input);
    return searchEngine.urlFor(input);
  }

  bool _looksLikeUrl(String input) {
    if (input.contains(' ')) return false;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return true;
    }
    if (input.startsWith('about:') || input.startsWith('file:')) return true;
    final uri = Uri.tryParse('https://$input');
    if (uri == null || uri.host.isEmpty) return false;
    // localhost / IP literals with optional port are addresses, not searches.
    final bareHost = uri.host;
    if (bareHost == 'localhost' ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(bareHost) ||
        bareHost == '::1') {
      return true;
    }
    // One dotted label pair minimum and a plausible TLD.
    return bareHost.contains('.') &&
        !bareHost.contains('..') &&
        bareHost.split('.').last.length >= 2;
  }

  String _normalizeUrl(String input) {
    if (input.startsWith('http://') ||
        input.startsWith('https://') ||
        input.startsWith('about:') ||
        input.startsWith('file:')) {
      return input;
    }
    return 'https://$input';
  }

  void submitOmnibox(String raw) {
    final url = resolveInput(raw);
    if (url.isEmpty) return;
    openUrl(url);
  }

  // ------------------------------------------------------------------------
  // Bookmarks / history
  // ------------------------------------------------------------------------

  bool isBookmarked(String url) => bookmarks.any((b) => b.url == url);

  void toggleBookmark(BrowserTab tab) {
    if (isBookmarked(tab.url)) {
      bookmarks.removeWhere((b) => b.url == tab.url);
    } else {
      bookmarks.add(Bookmark(
        id: 'bm-${DateTime.now().microsecondsSinceEpoch}',
        url: tab.url,
        title: tab.title,
        faviconUrl: tab.faviconUrl,
      ));
    }
    _saveBookmarks();
    notifyListeners();
  }

  void removeBookmark(String id) {
    bookmarks.removeWhere((b) => b.id == id);
    _saveBookmarks();
    notifyListeners();
  }

  void recordVisit(String url, String title) {
    final i = history.indexWhere((h) => h.url == url);
    if (i >= 0) {
      history[i].visitCount++;
      history[i].lastVisited = DateTime.now();
      if (title.isNotEmpty) history[i].title = title;
      final e = history.removeAt(i);
      history.insert(0, e);
    } else {
      history.insert(0, HistoryEntry(url: url, title: title));
    }
    if (history.length > 5000) history.removeRange(5000, history.length);
    _saveHistory();
  }

  void clearHistory() {
    history.clear();
    _saveHistory();
    notifyListeners();
  }

  void removeHistoryEntry(String url) {
    history.removeWhere((h) => h.url == url);
    _saveHistory();
    notifyListeners();
  }

  /// Omnibox suggestions: bookmarks + history matches, ranked.
  List<Object> suggestions(String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return [];
    final hits = <Object>[];
    final seen = <String>{};
    for (final b in bookmarks.reversed) {
      if (seen.contains(b.url)) continue;
      if (b.url.toLowerCase().contains(q) ||
          b.title.toLowerCase().contains(q)) {
        hits.add(b);
        seen.add(b.url);
      }
    }
    for (final h in history) {
      if (hits.length >= 8) break;
      if (seen.contains(h.url)) continue;
      if (h.url.toLowerCase().contains(q) ||
          h.title.toLowerCase().contains(q)) {
        hits.add(h);
        seen.add(h.url);
      }
    }
    return hits.take(8).toList();
  }

  // ------------------------------------------------------------------------
  // Panels, find bar, reader
  // ------------------------------------------------------------------------

  void showPanel(ActivePanel panel) {
    activePanel = activePanel == panel ? ActivePanel.none : panel;
    notifyListeners();
  }

  void closePanel() {
    activePanel = ActivePanel.none;
    notifyListeners();
  }

  void setFindBar(bool visible, {String query = ''}) {
    findBarVisible = visible;
    findQuery = query;
    notifyListeners();
  }

  void setReaderData(Map<String, dynamic>? data) {
    readerData = data;
    readerSheetOpen = data != null;
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Settings mutators
  // ------------------------------------------------------------------------

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _saveSettings();
    notifyListeners();
  }

  void setSearchEngine(String id) {
    searchEngineId = id;
    _saveSettings();
    notifyListeners();
  }

  void toggleSidebarCollapsed() {
    sidebarCollapsed = !sidebarCollapsed;
    _saveSettings();
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarVisible = !sidebarVisible;
    _saveSettings();
    notifyListeners();
  }

  void setRestoreTabs(bool v) {
    restoreTabs = v;
    _saveSettings();
    notifyListeners();
  }

  void setRecordHistory(bool v) {
    recordHistory = v;
    _saveSettings();
    notifyListeners();
  }

  void setReaderFontSize(double v) {
    readerFontSize = v;
    _saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Sync
  // ------------------------------------------------------------------------

  Map<String, List<SyncRecord>> _localRecords() {
    double ts(Map<String, dynamic> j, String key) =>
        DateTime.tryParse(j[key] as String? ?? '')
                ?.millisecondsSinceEpoch
                .toDouble() ??
            0;
    return {
      'bookmarks': bookmarks
          .map((b) => SyncRecord(
              id: b.id,
              payload: jsonEncode(b.toJson()),
              modified: ts(b.toJson(), 'createdAt') / 1000))
          .toList(),
      'history': history
          .take(1000)
          .map((h) => SyncRecord(
              id: base64Url.encode(utf8.encode(h.url)),
              payload: jsonEncode(h.toJson()),
              modified: ts(h.toJson(), 'lastVisited') / 1000))
          .toList(),
      'passwords': vault.locked
          ? []
          : vault.entries
              .map((e) => SyncRecord(
                  id: e.id,
                  payload: jsonEncode(e.toJson()),
                  modified: ts(e.toJson(), 'updatedAt') / 1000))
              .toList(),
      'tabs': tabs
          .where((t) => !t.isPrivate && t.url.isNotEmpty)
          .map((t) => SyncRecord(
              id: t.id,
              payload: jsonEncode(t.toJson()),
              modified: t.lastActiveAt.millisecondsSinceEpoch / 1000))
          .toList(),
    };
  }

  void _applyMerged(String collection, List<SyncRecord> records) {
    switch (collection) {
      case 'bookmarks':
        final incoming = records
            .map((r) =>
                Bookmark.fromJson(jsonDecode(r.payload) as Map<String, dynamic>))
            .toList();
        final byId = {for (final b in bookmarks) b.id: b};
        for (final b in incoming) {
          byId[b.id] = b;
        }
        bookmarks
          ..clear()
          ..addAll(byId.values);
        _saveBookmarks();
        break;
      case 'history':
        final incoming = records
            .map((r) => HistoryEntry.fromJson(
                jsonDecode(r.payload) as Map<String, dynamic>))
            .toList();
        final byUrl = {for (final h in history) h.url: h};
        for (final h in incoming) {
          final cur = byUrl[h.url];
          if (cur == null || h.lastVisited.isAfter(cur.lastVisited)) {
            byUrl[h.url] = h;
          }
        }
        history
          ..clear()
          ..addAll(byUrl.values
              .toList()
            ..sort((a, b) => b.lastVisited.compareTo(a.lastVisited)));
        _saveHistory();
        break;
      case 'passwords':
        if (!vault.locked) {
          for (final r in records) {
            try {
              final e = VaultEntry.fromJson(
                  jsonDecode(r.payload) as Map<String, dynamic>);
              unawaited(vault.upsert(e));
            } catch (_) {}
          }
        }
        break;
      case 'tabs':
        // Remote tab list is surfaced read-only in the synced-tabs UI; no
        // mutation of local open tabs.
        break;
    }
  }

  Future<void> syncNow() async {
    final merged = await sync.syncCollections(_localRecords());
    for (final entry in merged.entries) {
      _applyMerged(entry.key, entry.value);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------------

  @override
  void dispose() {
    for (final c in _controllers.values) {
      unawaited(c.dispose());
    }
    super.dispose();
  }
}
