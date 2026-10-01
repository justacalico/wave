import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../webview/controller.dart';
import 'omnibox.dart';
import 'widgets.dart';

/// The vertical tab rail: nav controls and omnibox on top, then workspace
/// switcher, essentials, pinned tabs and the reorderable tab list.
/// Collapses to a 52px icon rail.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, this.onOpenAccount, this.omniboxKey});

  final VoidCallback? onOpenAccount;
  final GlobalKey<OmniboxState>? omniboxKey;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final collapsed = app.sidebarCollapsed;
    final width =
        collapsed ? WaveTheme.sidebarCollapsedWidth : WaveTheme.sidebarWidth;
    final colors = WaveColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          right: BorderSide(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          _NavToolbar(collapsed: collapsed, omniboxKey: omniboxKey),
          _WorkspaceHeader(collapsed: collapsed),
          const SizedBox(height: 4),
          if (app.essentialTabs.isNotEmpty)
            _EssentialsRow(collapsed: collapsed),
          Expanded(
            child: collapsed
                ? const _CollapsedTabRail()
                : const _TabList(),
          ),
          const Divider(height: 1),
          _BottomBar(onOpenAccount: onOpenAccount, collapsed: collapsed),
        ],
      ),
    );
  }
}

/// Back/forward/reload, the omnibox and the main menu. What used to be
/// the content toolbar, docked at the top of the sidebar.
class _NavToolbar extends StatelessWidget {
  const _NavToolbar({required this.collapsed, this.omniboxKey});

  final bool collapsed;
  final GlobalKey<OmniboxState>? omniboxKey;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = app.activeTab;
    final c = tab == null ? null : app.controllerOf(tab.id);

    final back = GhostButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back (Alt+←)',
      onPressed:
          c?.canGoBack == true ? () => c!.goBack() : null,
    );
    final forward = GhostButton(
      icon: Icons.arrow_forward_rounded,
      tooltip: 'Forward (Alt+→)',
      onPressed:
          c?.canGoForward == true ? () => c!.goForward() : null,
    );
    final reload = GhostButton(
      icon: (c?.loading.value ?? false)
          ? Icons.close_rounded
          : Icons.refresh_rounded,
      tooltip: 'Reload (Ctrl+R)',
      onPressed: () {
        if (c == null) return;
        c.loading.value ? c.stop() : c.reload();
      },
    );
    final menu = Builder(
      builder: (context) => GhostButton(
        icon: Icons.more_vert_rounded,
        tooltip: 'Menu',
        onPressed: () => _mainMenu(context),
      ),
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            back,
            forward,
            reload,
            GhostButton(
              icon: Icons.search_rounded,
              tooltip: 'Search or address',
              onPressed: () {
                app.toggleSidebarCollapsed();
                WidgetsBinding.instance
                    .addPostFrameCallback((_) {
                  omniboxKey?.currentState?.focus();
                });
              },
            ),
            menu,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Column(
        children: [
          Row(
            children: [
              back,
              forward,
              reload,
              const Spacer(),
              menu,
            ],
          ),
          const SizedBox(height: 6),
          Omnibox(key: omniboxKey),
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

  RelativeRect _menuAnchor(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    return RelativeRect.fromLTRB(
        pos.dx, pos.dy + box.size.height + 4, pos.dx + box.size.width, 0);
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
      position: _menuAnchor(context),
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
    final hasPage = app.activeTab?.url.isNotEmpty ?? false;
    showMenu<void>(
      context: context,
      position: _menuAnchor(context),
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
        if (hasPage)
          PopupMenuItem(
            child: const Text('Reader mode'),
            onTap: () => _openReader(context),
          ),
        if (hasPage)
          PopupMenuItem(
            child: const Text('Split view'),
            onTap: () => _splitMenu(context),
          ),
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

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ws = app.activeWorkspace;
    final scheme = Theme.of(context).colorScheme;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: _WorkspaceDot(
          workspace: ws,
          selected: true,
          onTap: () => _showWorkspaceMenu(context),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
              onTap: () => _showWorkspaceMenu(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(workspaceIcon(ws.icon),
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ws.name,
                        style:
                            Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more_rounded,
                        size: 16,
                        color:
                            scheme.onSurface.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            ),
          ),
          GhostButton(
            icon: app.sidebarCollapsed
                ? Icons.keyboard_double_arrow_right_rounded
                : Icons.keyboard_double_arrow_left_rounded,
            tooltip: 'Compact mode (Ctrl+B)',
            onPressed: app.toggleSidebarCollapsed,
          ),
        ],
      ),
    );
  }

  void _showWorkspaceMenu(BuildContext context) {
    final app = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ws in app.workspaces)
              ListTile(
                leading: Icon(workspaceIcon(ws.icon)),
                title: Text(ws.name),
                trailing: ws.id == app.activeWorkspaceId
                    ? const Icon(Icons.check_rounded, size: 18)
                    : null,
                onTap: () {
                  app.switchWorkspace(ws.id);
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New workspace'),
              onTap: () {
                Navigator.pop(context);
                _showWorkspaceDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Edit workspaces'),
              onTap: () {
                Navigator.pop(context);
                _showWorkspaceDialog(context, editing: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _showWorkspaceDialog(BuildContext context,
      {bool editing = false}) {
    showDialog(
      context: context,
      builder: (context) => _WorkspaceDialog(editing: editing),
    );
  }
}

class _WorkspaceDot extends StatelessWidget {
  const _WorkspaceDot({
    required this.workspace,
    required this.selected,
    required this.onTap,
  });

  final Workspace workspace;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = WaveTheme.workspaceGradients[
        workspace.gradientIndex % WaveTheme.workspaceGradients.length];
    return Tooltip(
      message: workspace.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [g.tint.withValues(alpha: 0.35), g.seed.withValues(alpha: 0.2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? g.seed : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(workspaceIcon(workspace.icon),
              size: 16,
              color: selected ? g.seed : scheme.onSurface.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _EssentialsRow extends StatelessWidget {
  const _EssentialsRow({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tabs = app.essentialTabs;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 8 : 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tabs)
              _EssentialTile(tab: t, collapsed: collapsed),
          ],
        ),
      ),
    );
  }
}

class _EssentialTile extends StatelessWidget {
  const _EssentialTile({required this.tab, required this.collapsed});

  final BrowserTab tab;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.activeTabId == tab.id;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tab.title,
      preferBelow: false,
      child: InkWell(
        onTap: () => app.activateTab(tab.id),
        onSecondaryTap: () => _menu(context),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: collapsed ? 36 : 32,
          height: collapsed ? 36 : 32,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Favicon(tab: tab, size: collapsed ? 20 : 18),
        ),
      ),
    );
  }

  void _menu(BuildContext context) {
    final app = context.read<AppState>();
    _tabMenu(context, tab, app, position: null);
  }
}

class _CollapsedTabRail extends StatelessWidget {
  const _CollapsedTabRail();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tabs = app.workspaceTabs
        .where((t) => t.kind == TabKind.normal)
        .toList();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final t in tabs) _CollapsedTabIcon(tab: t),
        const SizedBox(height: 6),
        GhostButton(
          icon: Icons.add_rounded,
          tooltip: 'New tab (Ctrl+T)',
          onPressed: () => context.read<AppState>().newTab(),
        ),
      ],
    );
  }
}

class _CollapsedTabIcon extends StatelessWidget {
  const _CollapsedTabIcon({required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.activeTabId == tab.id;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tab.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => app.activateTab(tab.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 36,
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Favicon(tab: tab, size: 18),
          ),
        ),
      ),
    );
  }
}

class _TabList extends StatelessWidget {
  const _TabList();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pinned = app.pinnedTabs;
    final normal = app.normalTabs;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        if (pinned.isNotEmpty) ...[
          _SectionLabel('Pinned'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in pinned) _PinnedTile(tab: t),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _SectionLabel('Tabs'),
        _NewTabTile(),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (o, n) => context
              .read<AppState>()
              .reorderTab(app.activeWorkspaceId, o, n),
          children: [
            for (var i = 0; i < normal.length; i++)
              _TabRow(key: ValueKey(normal[i].id), tab: normal[i], index: i),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
            ),
      ),
    );
  }
}

class _NewTabTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
      onTap: () => context.read<AppState>().newTab(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.add_rounded,
                size: 18,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55)),
            const SizedBox(width: 10),
            Text(
              'New tab',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabRow extends StatefulWidget {
  const _TabRow({super.key, required this.tab, required this.index});

  final BrowserTab tab;
  final int index;

  @override
  State<_TabRow> createState() => _TabRowState();
}

class _TabRowState extends State<_TabRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = widget.tab;
    final active = app.activeTabId == tab.id;
    final inSplit = app.splitTabId == tab.id;
    final scheme = Theme.of(context).colorScheme;
    final ws = app.activeWorkspace;
    final accent = WaveTheme.workspaceGradients[
            ws.gradientIndex % WaveTheme.workspaceGradients.length]
        .seed;

    return ReorderableDragStartListener(
      index: widget.index,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapUp: (d) =>
              _tabMenu(context, tab, app, position: d.globalPosition),
          onTap: () => app.activateTab(tab.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.16)
                  : _hover
                      ? scheme.onSurface.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
              border: active
                  ? Border.all(color: accent.withValues(alpha: 0.35))
                  : inSplit
                      ? Border.all(
                          color: scheme.tertiary.withValues(alpha: 0.5))
                      : null,
            ),
            child: Row(
              children: [
                if (active)
                  Container(
                    width: 2.5,
                    height: 16,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(width: 8.5),
                Favicon(tab: tab),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                      ),
                      if (tab.suspended)
                        Text(
                          'asleep',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                        ),
                    ],
                  ),
                ),
                if (tab.isPrivate) const PrivateBadge(),
                const SizedBox(width: 4),
                Opacity(
                  opacity: _hover || active ? 1 : 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => app.closeTab(tab.id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded,
                          size: 14,
                          color: scheme.onSurface
                              .withValues(alpha: 0.55)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.activeTabId == tab.id;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tab.title,
      preferBelow: false,
      child: InkWell(
        onTap: () => app.activateTab(tab.id),
        onSecondaryTapUp: (d) =>
            _tabMenu(context, tab, app, position: d.globalPosition),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Favicon(tab: tab, size: 18),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({this.onOpenAccount, required this.collapsed});

  final VoidCallback? onOpenAccount;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            GhostButton(
              icon: Icons.add_rounded,
              tooltip: 'New tab (Ctrl+T)',
              onPressed: () => app.newTab(),
            ),
            const SizedBox(height: 4),
            _AccountChip(collapsed: true, onTap: onOpenAccount),
            const SizedBox(height: 4),
            GhostButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onPressed: () =>
                  app.showPanel(ActivePanel.settings),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      child: Row(
        children: [
          _AccountChip(collapsed: false, onTap: onOpenAccount),
          const Spacer(),
          GhostButton(
            icon: Icons.private_connectivity_rounded,
            tooltip: 'New private tab (Ctrl+Shift+P)',
            onPressed: () => app.newTab(isPrivate: true),
          ),
          GhostButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings (Ctrl+,)',
            onPressed: () => app.showPanel(ActivePanel.settings),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  static void _noop() {}
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.collapsed, this.onTap});

  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profile = app.fxa.profile;
    final scheme = Theme.of(context).colorScheme;

    final avatar = profile?.avatarUrl != null
        ? CircleAvatar(
            radius: 13,
            backgroundImage: NetworkImage(profile!.avatarUrl!),
          )
        : CircleAvatar(
            radius: 13,
            backgroundColor: scheme.primaryContainer,
            child: Icon(
              profile == null
                  ? Icons.person_outline_rounded
                  : Icons.person_rounded,
              size: 15,
              color: scheme.onPrimaryContainer,
            ),
          );

    if (collapsed) {
      return Tooltip(
        message: profile?.email ?? 'Firefox Account',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.all(4), child: avatar),
        ),
      );
    }

    return Flexible(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  profile?.displayName ?? profile?.email ?? 'Sign in',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: profile == null
                            ? scheme.onSurface.withValues(alpha: 0.55)
                            : null,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _tabMenu(BuildContext context, BrowserTab tab, AppState app,
    {Offset? position}) {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final pos = position ?? overlay.size.center(Offset.zero);
  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
        pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
    items: <PopupMenuEntry<void>>[
      PopupMenuItem(
        child: const Text('Reload'),
        onTap: () => app.reloadTab(tab.id),
      ),
      PopupMenuItem(
        child: Text(tab.kind == TabKind.pinned ? 'Unpin' : 'Pin'),
        onTap: () => app.setTabKind(
            tab.id,
            tab.kind == TabKind.pinned
                ? TabKind.normal
                : TabKind.pinned),
      ),
      PopupMenuItem(
        child: Text(tab.kind == TabKind.essential
            ? 'Remove from essentials'
            : 'Add to essentials'),
        onTap: () => app.setTabKind(
            tab.id,
            tab.kind == TabKind.essential
                ? TabKind.normal
                : TabKind.essential),
      ),
      PopupMenuItem(
        child: const Text('Open in split view'),
        onTap: () {
          app.activateTab(app.activeTabId ?? tab.id);
          app.toggleSplitWith(tab.id);
        },
      ),
      const PopupMenuDivider(),
      for (final ws in app.workspaces)
        if (ws.id != tab.workspaceId)
          PopupMenuItem(
            child: Text('Move to ${ws.name}'),
            onTap: () => app.moveTabToWorkspace(tab.id, ws.id),
          ),
      const PopupMenuDivider(),
      PopupMenuItem(
        child: const Text('Close tab'),
        onTap: () => app.closeTab(tab.id),
      ),
    ],
  );
}

class _WorkspaceDialog extends StatefulWidget {
  const _WorkspaceDialog({required this.editing});

  final bool editing;

  @override
  State<_WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<_WorkspaceDialog> {
  late final TextEditingController _name;
  String _icon = 'wave';
  int _gradient = 0;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AlertDialog(
      title: Text(widget.editing ? 'Workspaces' : 'New workspace'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.editing)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ws in app.workspaces)
                      ListTile(
                        dense: true,
                        leading: Icon(workspaceIcon(ws.icon), size: 18),
                        title: Text(ws.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 16),
                              onPressed: () => setState(() {
                                _editingId = ws.id;
                                _name.text = ws.name;
                                _icon = ws.icon;
                                _gradient = ws.gradientIndex;
                              }),
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16),
                              onPressed: app.workspaces.length > 1
                                  ? () =>
                                      app.removeWorkspace(ws.id)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: _editingId == null
                    ? 'Workspace name'
                    : 'Rename workspace',
              ),
              autofocus: !widget.editing,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Icon',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in workspaceIconKeys)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _icon = k),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _icon == k
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Icon(workspaceIcon(k), size: 16),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Accent',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0;
                    i < WaveTheme.workspaceGradients.length;
                    i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _gradient = i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [
                            WaveTheme.workspaceGradients[i].tint,
                            WaveTheme.workspaceGradients[i].seed,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          width: 2,
                          color: _gradient == i
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            if (_editingId != null) {
              app.renameWorkspace(_editingId!, name, _gradient);
            } else {
              app.addWorkspace(name, _icon, _gradient);
            }
            Navigator.pop(context);
          },
          child: Text(_editingId == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
