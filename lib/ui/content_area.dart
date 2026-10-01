import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../webview/companion_adapter.dart';
import '../webview/companion_dock.dart';
import '../webview/inapp_adapter.dart';
import 'new_tab.dart';
import '../theme.dart';
import 'reader.dart';

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

