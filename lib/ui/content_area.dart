import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../webview/companion_adapter.dart';
import '../webview/companion_dock.dart';
import '../webview/controller.dart';
import '../webview/inapp_adapter.dart';
import 'new_tab.dart';
import 'omnibox.dart';
import '../theme.dart';
import 'reader.dart';
import 'widgets.dart';

/// Hosts the live webview for the active tab (and the split-view tab), or
/// the new-tab page when the tab is fresh. On Linux the webview is a docked
/// native window, so this widget only has to keep its rect reported.
class ContentArea extends StatelessWidget {
  const ContentArea({super.key, this.dock});

  final CompanionDock? dock;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final split = app.splitTab;
    final tabs = app.workspaceTabs;
    if (tabs.isEmpty) return const SizedBox.shrink();

    // The IndexedStack keeps every touched tab's webview alive — switching
    // tabs is instant and pages never reload. The stack sits in the same
    // slot whether or not split view is open, so webviews survive toggling.
    final stackTabs = split == null
        ? tabs
        : tabs.where((t) => t.id != split.id).toList();
    var index =
        stackTabs.indexWhere((t) => t.id == app.activeTabId);
    if (index < 0) index = 0;

    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: [
                    for (final t in stackTabs)
                      _TabSurface(key: ValueKey(t.id), tab: t, dock: dock),
                  ],
                ),
              ),
              if (split != null) ...[
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _TabSurface(
                      key: ValueKey('split-${split.id}'),
                      tab: split,
                      dock: dock),
                ),
              ],
            ],
          ),
        ),
        if (app.readerSheetOpen && app.readerData != null)
          Positioned.fill(
            child: ReaderSheet(
                data: app.readerData!,
                onClose: () => app.setReaderData(null)),
          ),
        if (app.pendingCredentialOrigin != null)
          const Positioned(
              top: 10, right: 12, child: _CredentialBanner()),
      ],
    );
  }
}

/// "Save password?" bubble under the toolbar, Zen/Firefox style.
class _CredentialBanner extends StatelessWidget {
  const _CredentialBanner();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final origin = app.pendingCredentialOrigin!;
    final user = app.pendingCredentialUser ?? '';
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
      color: scheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Save password for $origin?',
                  style: Theme.of(context).textTheme.titleSmall),
              if (user.isNotEmpty)
                Text(user,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: () => unawaited(
                        context.read<AppState>().savePendingCredential()),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        context.read<AppState>().clearPendingCredential(),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabSurface extends StatefulWidget {
  const _TabSurface({super.key, required this.tab, required this.dock});

  final BrowserTab tab;
  final CompanionDock? dock;

  @override
  State<_TabSurface> createState() => _TabSurfaceState();
}

class _TabSurfaceState extends State<_TabSurface> {
  /// Webviews are created lazily on first activation so restoring a session
  /// does not spawn a native view per tab.
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = widget.tab;
    if (tab.url.isEmpty) {
      return NewTabPage(tab: tab);
    }
    if (!_built &&
        (tab.id == app.activeTabId || tab.id == app.splitTabId)) {
      _built = true;
    }
    if (!_built) {
      return Container(
          color: Theme.of(context).scaffoldBackgroundColor);
    }
    final controller = app.controllerFor(tab);
    if (controller is CompanionTabController) {
      final dock = widget.dock;
      if (dock == null) {
        return const Center(child: Text('Web engine unavailable'));
      }
      return CompanionTabView(controller: controller, dock: dock);
    }
    if (controller is InAppTabController) {
      return InAppTabView(controller: controller);
    }
    return const Center(child: Text('Web engine unavailable'));
  }
}

/// The toolbar row above the content: nav buttons, omnibox, action icons.
class ContentToolbar extends StatelessWidget {
  const ContentToolbar({super.key, required this.omniboxKey});

  final GlobalKey<OmniboxState> omniboxKey;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = app.activeTab;
    final c = tab == null ? null : app.controllerOf(tab.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          GhostButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back (Alt+←)',
            onPressed:
                c?.canGoBack == true ? () => c!.goBack() : null,
          ),
          GhostButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Forward (Alt+→)',
            onPressed:
                c?.canGoForward == true ? () => c!.goForward() : null,
          ),
          GhostButton(
            icon: (c?.loading.value ?? false)
                ? Icons.close_rounded
                : Icons.refresh_rounded,
            tooltip: 'Reload (Ctrl+R)',
            onPressed: () {
              if (c == null) return;
              c.loading.value ? c.stop() : c.reload();
            },
          ),
          const SizedBox(width: 6),
          Expanded(child: Omnibox(key: omniboxKey)),
          const SizedBox(width: 6),
          if (tab != null && tab.url.isNotEmpty) ...[
            GhostButton(
              icon: Icons.chrome_reader_mode_outlined,
              tooltip: 'Reader mode',
              onPressed: () => _openReader(context),
            ),
            GhostButton(
              icon: Icons.vertical_split_rounded,
              tooltip: 'Split view',
              onPressed: () => _splitMenu(context),
            ),
          ],
          GhostButton(
            icon: Icons.more_vert_rounded,
            tooltip: 'Menu',
            onPressed: () => _mainMenu(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openReader(BuildContext context) async {
    final app = context.read<AppState>();
    final tab = app.activeTab;
    if (tab == null) return;
    final c = app.controllerOf(tab.id);
    final raw = await c?.evaluateJavaScript(kWaveReaderScript);
    if (raw == null || !context.mounted) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No article found on this page')));
        return;
      }
      app.setReaderData(data);
    } catch (_) {}
  }

  void _splitMenu(BuildContext context) {
    final app = context.read<AppState>();
    final active = app.activeTab;
    if (active == null) return;
    final others = app.workspaceTabs
        .where((t) => t.id != active.id && t.url.isNotEmpty)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Open another tab to split')));
      return;
    }
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
          MediaQuery.of(context).size.width - 40, 48, 0, 0),
      items: <PopupMenuEntry<void>>[
        for (final t in others.take(8))
          PopupMenuItem(
            child: Text(t.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => app.toggleSplitWith(t.id),
          ),
      ],
    );
  }

  void _mainMenu(BuildContext context) {
    final app = context.read<AppState>();
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
          MediaQuery.of(context).size.width - 40, 48, 0, 0),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem(
          child: const Text('New private tab'),
          onTap: () => app.newTab(isPrivate: true),
        ),
        PopupMenuItem(
          child: const Text('Bookmarks'),
          onTap: () => app.showPanel(ActivePanel.bookmarks),
        ),
        PopupMenuItem(
          child: const Text('History'),
          onTap: () => app.showPanel(ActivePanel.history),
        ),
        PopupMenuItem(
          child: const Text('Downloads'),
          onTap: () => app.showPanel(ActivePanel.downloads),
        ),
        PopupMenuItem(
          child: const Text('Passwords'),
          onTap: () => app.showPanel(ActivePanel.vault),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Text('Find in page'),
          onTap: () => app.setFindBar(true),
        ),
        PopupMenuItem(
          child: const Text('Synced tabs'),
          onTap: () => app.showPanel(ActivePanel.account),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Text('Settings'),
          onTap: () => app.showPanel(ActivePanel.settings),
        ),
      ],
    );
  }
}
