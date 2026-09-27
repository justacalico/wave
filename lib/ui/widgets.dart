import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Favicon with a letter-tile fallback — never a broken-image icon.
class Favicon extends StatelessWidget {
  const Favicon({super.key, required this.tab, this.size = 18});

  final BrowserTab tab;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = tab.faviconUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _tile(context),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _tile(context),
        ),
      );
    }
    return _tile(context);
  }

  Widget _tile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = tab.host.isNotEmpty
        ? tab.host.replaceFirst('www.', '')[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.58,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Plain favicon for a bare url string (history/bookmarks lists).
class UrlFavicon extends StatelessWidget {
  const UrlFavicon({super.key, required this.url, this.size = 18});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return Icon(Icons.public, size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}/favicon.ico',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(Icons.public, size: size),
      ),
    );
  }
}

/// Icon mapping for workspace glyphs.
IconData workspaceIcon(String key) => switch (key) {
      'wave' => Icons.water_rounded,
      'briefcase' => Icons.work_outline_rounded,
      'book' => Icons.menu_book_outlined,
      'cart' => Icons.shopping_bag_outlined,
      'music' => Icons.music_note_rounded,
      'code' => Icons.code_rounded,
      'home' => Icons.home_outlined,
      'star' => Icons.star_outline_rounded,
      'game' => Icons.sports_esports_outlined,
      'chat' => Icons.forum_outlined,
      'news' => Icons.newspaper_rounded,
      'tools' => Icons.build_outlined,
      _ => Icons.water_rounded,
    };

const workspaceIconKeys = [
  'wave', 'briefcase', 'book', 'cart', 'music', 'code',
  'home', 'star', 'game', 'chat', 'news', 'tools',
];

/// Compact ghost icon button used in toolbars.
class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 18,
    this.toggled = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool toggled;
  final bool danger;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.toggled;
    final enabled = widget.onPressed != null;
    final color = widget.danger
        ? scheme.error
        : active
            ? scheme.primary
            : enabled
                ? scheme.onSurface.withValues(alpha: 0.75)
                : scheme.onSurface.withValues(alpha: 0.3);
    final child = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover && enabled
                ? scheme.onSurface.withValues(alpha: 0.08)
                : active
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: widget.size, color: color),
        ),
      ),
    );
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: child)
        : child;
  }
}

/// Thin linear progress for under the omnibox.
class LoadingLine extends StatelessWidget {
  const LoadingLine({super.key, required this.progress, required this.visible});

  final double progress;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: SizedBox(
        height: 2,
        child: LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          minHeight: 2,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Private-tab badge.
class PrivateBadge extends StatelessWidget {
  const PrivateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'P',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: scheme.tertiary,
        ),
      ),
    );
  }
}
