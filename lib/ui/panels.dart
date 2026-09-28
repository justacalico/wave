import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Router for the side panel shown between the sidebar and the content.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: switch (app.activePanel) {
        ActivePanel.none => const SizedBox(width: 0),
        ActivePanel.bookmarks => const _PanelFrame(
            title: 'Bookmarks',
            icon: Icons.bookmark_rounded,
            child: BookmarksPanel()),
        ActivePanel.history => const _PanelFrame(
            title: 'History',
            icon: Icons.history_rounded,
            child: HistoryPanel()),
        ActivePanel.downloads => const _PanelFrame(
            title: 'Downloads',
            icon: Icons.download_rounded,
            child: DownloadsPanel()),
        _ => const SizedBox(width: 0),
      },
    );
  }
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame(
      {required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
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
                Icon(icon, size: 16, color: scheme.primary),
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

class BookmarksPanel extends StatefulWidget {
  const BookmarksPanel({super.key});

  @override
  State<BookmarksPanel> createState() => _BookmarksPanelState();
}

class _BookmarksPanelState extends State<BookmarksPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var items = app.bookmarks.reversed.toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      items = items
          .where((b) =>
              b.title.toLowerCase().contains(q) ||
              b.url.toLowerCase().contains(q))
          .toList();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search bookmarks',
              prefixIcon: Icon(Icons.search_rounded, size: 16),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const _EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  text: 'No bookmarks yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final b = items[i];
                    return _RowTile(
                      favicon: UrlFavicon(url: b.url, size: 16),
                      title: b.title.isEmpty ? b.url : b.title,
                      subtitle: b.url,
                      onTap: () {
                        context
                            .read<AppState>()
                            .openUrlInNewTab(b.url);
                      },
                      trailing: IconButton(
                        icon:
                            const Icon(Icons.delete_outline, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            context
                                .read<AppState>()
                                .removeBookmark(b.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var items = app.history;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      items = items
          .where((h) =>
              h.url.toLowerCase().contains(q) ||
              h.title.toLowerCase().contains(q))
          .toList();
    }
    // Group by day.
    final groups = <String, List<HistoryEntry>>{};
    for (final h in items) {
      final d = h.lastVisited;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(h);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search history',
                    prefixIcon:
                        Icon(Icons.search_rounded, size: 16),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 6),
              GhostButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear history',
                onPressed: () => _confirmClear(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const _EmptyState(
                  icon: Icons.history_rounded,
                  text: 'No history yet')
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final day in days) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            10, 10, 10, 4),
                        child: Text(_dayLabel(day),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                )),
                      ),
                      for (final h in groups[day]!)
                        _RowTile(
                          favicon:
                              UrlFavicon(url: h.url, size: 16),
                          title: h.title.isEmpty ? h.url : h.title,
                          subtitle: h.url,
                          onTap: () => context
                              .read<AppState>()
                              .openUrlInNewTab(h.url),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => context
                                .read<AppState>()
                                .removeHistoryEntry(h.url),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  String _dayLabel(String iso) {
    final d = DateTime.parse(iso);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return iso;
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear browsing history?'),
        content:
            const Text('This removes all recorded visits on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AppState>().clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class DownloadsPanel extends StatelessWidget {
  const DownloadsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.downloads.items;
    return Column(
      children: [
        if (items.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: app.downloads.clearFinished,
              child: const Text('Clear finished'),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const _EmptyState(
                  icon: Icons.download_rounded,
                  text: 'No downloads yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final d = items[i];
                    return _DownloadTile(item: d);
                  },
                ),
        ),
      ],
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final running = item.state == DownloadState.inProgress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (item.state) {
                    DownloadState.completed =>
                      Icons.check_circle_rounded,
                    DownloadState.failed =>
                      Icons.error_outline_rounded,
                    DownloadState.cancelled =>
                      Icons.cancel_outlined,
                    DownloadState.inProgress =>
                      Icons.downloading_rounded,
                  },
                  size: 16,
                  color: switch (item.state) {
                    DownloadState.completed => Colors.green,
                    DownloadState.failed => scheme.error,
                    DownloadState.cancelled =>
                      scheme.onSurface.withValues(alpha: 0.4),
                    DownloadState.inProgress => scheme.primary,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (running)
                  InkWell(
                    onTap: () => app.downloads.cancel(item.id),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, size: 14),
                    ),
                  )
                else if (item.state == DownloadState.completed)
                  InkWell(
                    onTap: () =>
                        launchUrl(Uri.file(item.path)),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.open_in_new_rounded,
                          size: 14,
                          color: scheme.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (running || item.totalBytes > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: LinearProgressIndicator(
                  value: item.totalBytes > 0 ? item.progress : null,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(
              running
                  ? '${_fmt(item.receivedBytes)}'
                      '${item.totalBytes > 0 ? ' / ${_fmt(item.totalBytes)}' : ''}'
                  : _fmt(item.totalBytes),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        scheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.favicon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final Widget favicon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            favicon,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.bodyMedium),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.45),
                          )),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 28,
              color: scheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          Text(text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  )),
        ],
      ),
    );
  }
}
