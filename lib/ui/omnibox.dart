import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// The floating address bar. Focused: expands and shows bookmark/history
/// matches and the search engine. Esc returns to the current URL.
class Omnibox extends StatefulWidget {
  const Omnibox({super.key, this.autofocus = false, this.onSubmitted});

  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  State<Omnibox> createState() => OmniboxState();
}

class OmniboxState extends State<Omnibox> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  List<Object> _suggestions = [];
  int _highlight = -1;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length);
        _update();
      } else {
        _removeOverlay();
      }
      setState(() {});
    });
    _controller.addListener(_update);
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void focus() {
    _focus.requestFocus();
  }

  void _syncWithTab(AppState app) {
    final tab = app.activeTab;
    final text = tab?.url ?? '';
    if (!_focus.hasFocus && _controller.text != text) {
      _controller.text = text;
    }
  }

  void _update() {
    final app = context.read<AppState>();
    final q = _controller.text.trim();
    _suggestions = q.isEmpty ? [] : app.suggestions(q);
    _highlight = -1;
    if (_focus.hasFocus) {
      _showOverlay();
    }
    setState(() {});
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay() {
    _overlay?.remove();
    _overlay = OverlayEntry(builder: _buildSuggestions);
    Overlay.of(context).insert(_overlay!);
  }

  Widget _buildSuggestions(BuildContext context) {
    final app = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final q = _controller.text.trim();
    final items = <Widget>[];

    if (q.isNotEmpty) {
      items.add(_suggestionTile(
        icon: Icons.search_rounded,
        title: q,
        subtitle: '${app.searchEngine.name} search',
        onTap: () => _submit(q),
      ));
    }
    for (final s in _suggestions) {
      if (s is Bookmark) {
        items.add(_suggestionTile(
          icon: Icons.bookmark_rounded,
          title: s.title,
          subtitle: s.url,
          onTap: () => _submit(s.url),
        ));
      } else if (s is HistoryEntry) {
        items.add(_suggestionTile(
          icon: Icons.history_rounded,
          title: s.title.isEmpty ? s.url : s.title,
          subtitle: s.url,
          onTap: () => _submit(s.url),
        ));
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focus.unfocus(),
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 46),
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {},
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
                color: scheme.surfaceContainerHigh,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: items,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 16,
          color: scheme.onSurface.withValues(alpha: 0.55)),
      title: Text(title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5))),
      onTap: onTap,
    );
  }

  void _submit(String raw) {
    context.read<AppState>().submitOmnibox(raw);
    _focus.unfocus();
    _removeOverlay();
    widget.onSubmitted?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _syncWithTab(context.read<AppState>());
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
        e.logicalKey == LogicalKeyboardKey.arrowUp) {
      final count = _suggestions.length + 1;
      if (count > 0) {
        setState(() {
          _highlight += e.logicalKey == LogicalKeyboardKey.arrowDown
              ? 1
              : -1;
          if (_highlight >= count) _highlight = 0;
          if (_highlight < 0) _highlight = count - 1;
        });
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      if (_highlight > 0 && _highlight <= _suggestions.length) {
        final s = _suggestions[_highlight - 1];
        if (s is Bookmark) _submit(s.url);
        if (s is HistoryEntry) _submit(s.url);
      } else {
        _submit(_controller.text);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    _syncWithTab(app);
    final tab = app.activeTab;
    final secure = tab?.url.startsWith('https://') ?? false;
    final isPrivate = tab?.isPrivate ?? false;

    return CompositedTransformTarget(
      link: _link,
      child: Focus(
        onKeyEvent: _onKey,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 38,
          decoration: BoxDecoration(
            color: _focus.hasFocus
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: _focus.hasFocus
                  ? scheme.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                isPrivate
                    ? Icons.privacy_tip_outlined
                    : secure
                        ? Icons.lock_rounded
                        : Icons.search_rounded,
                size: 15,
                color: isPrivate
                    ? scheme.tertiary
                    : scheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Search or enter address',
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _submit,
                ),
              ),
              if (tab != null && tab.url.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => app.toggleBookmark(tab),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        app.isBookmarked(tab.url)
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 15,
                        color: app.isBookmarked(tab.url)
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.5),
                      ),
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
