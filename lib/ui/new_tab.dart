import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The start surface: quiet, a clock, a search field wired to the omnibox
/// resolver, and a shortcuts row built from most-visited history plus
/// bookmarks. Workspace accent washes the top edge.
class NewTabPage extends StatefulWidget {
  const NewTabPage({super.key, required this.tab});

  final BrowserTab tab;

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final ws = app.workspaces.firstWhere(
        (w) => w.id == widget.tab.workspaceId,
        orElse: () => app.activeWorkspace);
    final g = WaveTheme
        .workspaceGradients[ws.gradientIndex % WaveTheme.workspaceGradients.length];

    final shortcuts = _shortcuts(app);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            g.tint.withValues(alpha: 0.14),
            scheme.surface,
          ],
          stops: const [0.0, 0.45],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Clock(),
                const SizedBox(height: 8),
                Text(
                  'Good ${_daypart()}, ${app.fxa.profile?.displayName?.split(' ').first ?? 'traveller'}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _search,
                  focusNode: _focus,
                  decoration: InputDecoration(
                    hintText: 'Search with ${app.searchEngine.name} or type a URL',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.65),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(WaveTheme.radiusLg),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (v) {
                    final url = app.resolveInput(v);
                    if (url.isNotEmpty) app.openUrl(url, tab: widget.tab);
                  },
                ),
                const SizedBox(height: 32),
                if (shortcuts.isNotEmpty)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final s in shortcuts)
                        _ShortcutTile(
                            title: s.$1, url: s.$2, tab: widget.tab),
                    ],
                  ),
                if (widget.tab.isPrivate) ...[
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.privacy_tip_outlined,
                          size: 14,
                          color: scheme.tertiary),
                      const SizedBox(width: 6),
                      Text(
                        'Private tab — history is not recorded',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.tertiary,
                                ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<(String, String)> _shortcuts(AppState app) {
    final out = <(String, String)>[];
    final seen = <String>{};
    for (final b in app.bookmarks.reversed) {
      final host = Uri.tryParse(b.url)?.host ?? '';
      if (seen.add(host) && b.url.isNotEmpty) {
        out.add((b.title.isEmpty ? host : b.title, b.url));
      }
      if (out.length >= 6) break;
    }
    for (final h in app.history) {
      if (out.length >= 8) break;
      if (h.visitCount < 2) continue;
      final host = Uri.tryParse(h.url)?.host ?? '';
      if (host.isEmpty || !seen.add(host)) continue;
      out.add((h.title.isEmpty ? host : h.title, h.url));
    }
    return out;
  }

  String _daypart() {
    final h = DateTime.now().hour;
    if (h < 5) return 'evening';
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _Clock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 30)),
      builder: (context, _) {
        final t = DateTime.now();
        return Text(
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w200,
            letterSpacing: -2,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.85),
          ),
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile(
      {required this.title, required this.url, required this.tab});

  final String title;
  final String url;
  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
      onTap: () => context.read<AppState>().openUrl(url, tab: tab),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UrlFavicon(url: url, size: 22),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
