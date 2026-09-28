import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../webview/companion_dock.dart';
import '../webview/controller.dart';
import 'account_panel.dart';
import 'content_area.dart';
import 'find_bar.dart';
import 'omnibox.dart';
import 'panels.dart';
import 'settings_panel.dart';
import 'sidebar.dart';
import 'vault_panel.dart';
import 'widgets.dart';

/// Adaptive root. Wide layout: Zen-style vertical sidebar + panel + content.
/// Compact: content with a bottom bar and a tab-grid switcher. Choosing
/// between them is pure layout — AppState is untouched, so nothing resets
/// on resize.
class BrowserShell extends StatefulWidget {
  const BrowserShell({super.key});

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver {
  final GlobalKey<OmniboxState> _omniboxKey = GlobalKey();
  late final CompanionDock? _dock;
  late AppState _app;

  @override
  void initState() {
    super.initState();
    _dock = CompanionDock.maybeCreate();
    unawaited(_dock?.init());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache once: during tree teardown a dirty rebuild can run while the
    // provider is already gone from this element's ancestors.
    _app = context.read<AppState>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dock?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // A size change here (window move/resize/drag) only affects layout;
    // companion windows re-dock through the dock listener below.
    _dock?.refresh();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final app = _app;
    return {
      const SingleActivator(LogicalKeyboardKey.keyT, control: true):
          () => app.newTab(),
      const SingleActivator(LogicalKeyboardKey.keyT,
          control: true, shift: true): _reopenClosed,
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
        final id = app.activeTabId;
        if (id != null) app.closeTab(id);
      },
      const SingleActivator(LogicalKeyboardKey.keyL, control: true):
          () => _omniboxKey.currentState?.focus(),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          () => _omniboxKey.currentState?.focus(),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
        final id = app.activeTabId;
        if (id != null) app.reloadTab(id);
      },
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          () => app.setFindBar(true),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          app.toggleSidebar,
      const SingleActivator(LogicalKeyboardKey.keyB,
          control: true, shift: true): app.toggleSidebarCollapsed,
      const SingleActivator(LogicalKeyboardKey.keyP,
          control: true, shift: true): () => app.newTab(isPrivate: true),
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          () => app.showPanel(ActivePanel.settings),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
        final t = app.activeTab;
        if (t != null && t.url.isNotEmpty) app.toggleBookmark(t);
      },
      const SingleActivator(LogicalKeyboardKey.keyH, control: true):
          () => app.showPanel(ActivePanel.history),
      const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
          () => app.showPanel(ActivePanel.downloads),
      const SingleActivator(LogicalKeyboardKey.tab, control: true):
          () => _cycleTab(1),
      const SingleActivator(LogicalKeyboardKey.tab,
          control: true, shift: true): () => _cycleTab(-1),
      const SingleActivator(LogicalKeyboardKey.digit1, control: true):
          () => _jumpToTab(0),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true):
          () => _jumpToTab(1),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true):
          () => _jumpToTab(2),
      const SingleActivator(LogicalKeyboardKey.digit4, control: true):
          () => _jumpToTab(3),
      const SingleActivator(LogicalKeyboardKey.digit5, control: true):
          () => _jumpToTab(4),
      const SingleActivator(LogicalKeyboardKey.digit6, control: true):
          () => _jumpToTab(5),
      const SingleActivator(LogicalKeyboardKey.digit7, control: true):
          () => _jumpToTab(6),
      const SingleActivator(LogicalKeyboardKey.digit8, control: true):
          () => _jumpToTab(7),
      const SingleActivator(LogicalKeyboardKey.digit9, control: true):
          () => _jumpToTab(8),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
        final c = _activeController(app);
        if (c != null) c.goBack();
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
        final c = _activeController(app);
        if (c != null) c.goForward();
      },
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
          () {
        if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
          return;
        }
        exit(0);
      },
    };
  }

  TabWebController? _activeController(AppState app) {
    final id = app.activeTabId;
    return id == null ? null : app.controllerOf(id);
  }

  void _reopenClosed() {
    // Session restore of closed tabs isn't tracked; reopening the most
    // recent history entry is the useful approximation.
    final app = context.read<AppState>();
    if (app.history.isNotEmpty) {
      app.openUrlInNewTab(app.history.first.url);
    }
  }

  void _cycleTab(int dir) {
    final app = context.read<AppState>();
    final list = app.workspaceTabs;
    if (list.isEmpty) return;
    final i = list.indexWhere((t) => t.id == app.activeTabId);
    final next = (i + dir) % list.length;
    app.activateTab(list[(next + list.length) % list.length].id);
  }

  void _jumpToTab(int index) {
    final app = context.read<AppState>();
    final list = app.workspaceTabs;
    if (index < list.length) app.activateTab(list[index].id);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              return wide
                  ? _DesktopLayout(
                      omniboxKey: _omniboxKey, dock: _dock)
                  : const _MobileLayout();
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop
// ---------------------------------------------------------------------------

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.omniboxKey, required this.dock});

  final GlobalKey<OmniboxState> omniboxKey;
  final CompanionDock? dock;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isDesktopOs =
        !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

    return Column(
      children: [
        if (isDesktopOs) const _WindowTitleBar(),
        Expanded(
          child: Row(
            children: [
              if (app.sidebarVisible)
                Sidebar(
                    onOpenAccount: () =>
                        app.showPanel(ActivePanel.account)),
              if (app.sidebarVisible) const SidePanel(),
              if (app.activePanel == ActivePanel.vault)
                const _PanelHost(
                    title: 'Passwords',
                    icon: Icons.lock_outline_rounded,
                    child: VaultPanel()),
              if (app.activePanel == ActivePanel.settings)
                const _PanelHost(
                    title: 'Settings',
                    icon: Icons.settings_outlined,
                    child: SettingsPanel()),
              if (app.activePanel == ActivePanel.account)
                const _PanelHost(
                    title: 'Firefox Account',
                    icon: Icons.account_circle_outlined,
                    child: AccountPanel()),
              Expanded(
                child: Column(
                  children: [
                    ContentToolbar(omniboxKey: omniboxKey),
                    _ActiveProgressLine(),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                              child: ContentArea(dock: dock)),
                          if (app.findBarVisible)
                            const Positioned(
                              top: 8,
                              right: 16,
                              child: FindBar(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelHost extends StatelessWidget {
  const _PanelHost(
      {required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Container(
      width: WaveTheme.panelWidth,
      decoration: BoxDecoration(
        color: WaveColors.of(context).sidebar,
        border: Border(
          right: BorderSide(
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                GhostButton(
                    icon: Icons.close_rounded,
                    onPressed: app.closePanel),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin window-drag strip + caption buttons for the frameless look.
class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      color: WaveColors.of(context).sidebar,
      child: Row(
        children: [
          const SizedBox(width: 12),
          // Traffic-light space on macOS handled by titleBarTopPadding.
          Expanded(
            child: DragToMoveArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'wave',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                ),
              ),
            ),
          ),
          if (!Platform.isMacOS)
            SizedBox(
              width: 138,
              height: 36,
              child: WindowCaption(
                brightness: Theme.of(context).brightness,
                backgroundColor: Colors.transparent,
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _ActiveProgressLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = app.activeTabId;
    final c = id == null ? null : app.controllerOf(id);
    if (c == null) {
      return const SizedBox(height: 2);
    }
    return ValueListenableBuilder<double>(
      valueListenable: c.progress,
      builder: (context, p, _) => ValueListenableBuilder<bool>(
        valueListenable: c.loading,
        builder: (context, loading, _) =>
            LoadingLine(progress: p, visible: loading),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile / narrow
// ---------------------------------------------------------------------------

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: ContentArea()),
          _MobileProgressLine(),
          _MobileBar(omniboxKey: null),
        ],
      ),
    );
  }
}

class _MobileProgressLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = app.activeTabId;
    final c = id == null ? null : app.controllerOf(id);
    if (c == null) return const SizedBox(height: 2);
    return ValueListenableBuilder<double>(
      valueListenable: c.progress,
      builder: (context, p, _) => ValueListenableBuilder<bool>(
        valueListenable: c.loading,
        builder: (context, loading, _) =>
            LoadingLine(progress: p, visible: loading),
      ),
    );
  }
}

class _MobileBar extends StatelessWidget {
  const _MobileBar({this.omniboxKey});

  final GlobalKey<OmniboxState>? omniboxKey;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = app.activeTab;
    final c = tab == null ? null : app.controllerOf(tab.id);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: WaveColors.of(context).sidebar,
        border: Border(
          top: BorderSide(
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Row(
        children: [
          GhostButton(
            icon: Icons.arrow_back_rounded,
            onPressed:
                c?.canGoBack == true ? () => c!.goBack() : null,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _openAddressSheet(context),
              child: Container(
                height: 38,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(19),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab?.isPrivate ?? false)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.privacy_tip_outlined,
                            size: 14, color: scheme.tertiary),
                      ),
                    Flexible(
                      child: Text(
                        tab == null || tab.url.isEmpty
                            ? 'Search or address'
                            : tab.host.isEmpty
                                ? tab.url
                                : tab.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: scheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _TabCountButton(),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                size: 20,
                color: scheme.onSurface.withValues(alpha: 0.75)),
            onSelected: (v) => _mobileMenu(context, v),
            itemBuilder: (context) => [
              _menuItem('bookmark', Icons.bookmark_outline_rounded,
                  'Bookmark'),
              _menuItem(
                  'history', Icons.history_rounded, 'History'),
              _menuItem('bookmarks', Icons.bookmarks_outlined,
                  'Bookmarks'),
              _menuItem('downloads',
                  Icons.download_rounded, 'Downloads'),
              _menuItem('passwords', Icons.lock_outline_rounded,
                  'Passwords'),
              _menuItem('private', Icons.visibility_off_outlined,
                  'New private tab'),
              _menuItem('desktop', Icons.refresh_rounded, 'Reload'),
              _menuItem('account', Icons.person_outline_rounded,
                  'Account & sync'),
              _menuItem('settings', Icons.settings_outlined,
                  'Settings'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  void _mobileMenu(BuildContext context, String v) {
    final app = context.read<AppState>();
    final tab = app.activeTab;
    switch (v) {
      case 'bookmark':
        if (tab != null && tab.url.isNotEmpty) {
          app.toggleBookmark(tab);
        }
        break;
      case 'history':
        _sheet(context, ActivePanel.history);
        break;
      case 'bookmarks':
        _sheet(context, ActivePanel.bookmarks);
        break;
      case 'downloads':
        _sheet(context, ActivePanel.downloads);
        break;
      case 'passwords':
        _sheet(context, ActivePanel.vault);
        break;
      case 'private':
        app.newTab(isPrivate: true);
        break;
      case 'desktop':
        if (tab != null) app.reloadTab(tab.id);
        break;
      case 'account':
        _sheet(context, ActivePanel.account);
        break;
      case 'settings':
        _sheet(context, ActivePanel.settings);
        break;
    }
  }

  void _sheet(BuildContext context, ActivePanel panel) {
    Widget body;
    switch (panel) {
      case ActivePanel.bookmarks:
        body = const BookmarksPanel();
        break;
      case ActivePanel.history:
        body = const HistoryPanel();
        break;
      case ActivePanel.downloads:
        body = const DownloadsPanel();
        break;
      case ActivePanel.vault:
        body = const VaultPanel();
        break;
      case ActivePanel.settings:
        body = const SettingsPanel();
        break;
      case ActivePanel.account:
        body = const AccountPanel();
        break;
      default:
        return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => SizedBox.expand(child: body),
      ),
    );
  }

  void _openAddressSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Omnibox(autofocus: true,
              onSubmitted: () => Navigator.pop(context)),
        ),
      ),
    );
  }
}

class _TabCountButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final count = app.workspaceTabs.length;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _tabSwitcher(context),
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.5),
              width: 1.4),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text('$count',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _tabSwitcher(BuildContext context) {
    final app = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ChangeNotifierProvider.value(
        value: app,
        child: const _TabSwitcherSheet(),
      ),
    );
  }
}

class _TabSwitcherSheet extends StatelessWidget {
  const _TabSwitcherSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tabs = app.workspaceTabs;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(app.activeWorkspace.name,
                    style:
                        Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    app.newTab();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New tab'),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.35,
              ),
              itemCount: tabs.length,
              itemBuilder: (context, i) {
                final t = tabs[i];
                final active = t.id == app.activeTabId;
                return _TabCard(tab: t, active: active);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard({required this.tab, required this.active});

  final BrowserTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
      onTap: () {
        app.activateTab(tab.id);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
          border: Border.all(
            color: active
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.4),
            width: active ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Favicon(tab: tab, size: 16),
                const Spacer(),
                InkWell(
                  onTap: () => app.closeTab(tab.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 14,
                        color: scheme.onSurface
                            .withValues(alpha: 0.55)),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              tab.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              tab.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
