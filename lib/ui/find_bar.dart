import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';

/// Find-in-page bar. Slides under the toolbar; drives the webview's native
/// find API through evaluateJavaScript for a portable implementation.
class FindBar extends StatefulWidget {
  const FindBar({super.key});

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _find(AppState app, {bool backwards = false}) {
    final tab = app.activeTab;
    if (tab == null) return;
    final c = app.controllerOf(tab.id);
    // window.find is universal across WKWebView/WebView2/WebKitGTK.
    // jsonEncode gives us a fully-escaped JS string literal.
    c?.evaluateJavaScript(
        'window.find(${jsonEncode(_query.text)}, false, $backwards, true, false, false, false)');
  }

  void _close(AppState app) {
    app.setFindBar(false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.findBarVisible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        width: 320,
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Focus(
                onKeyEvent: (node, e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.escape) {
                    _close(app);
                    return KeyEventResult.handled;
                  }
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.enter) {
                    _find(app,
                        backwards: HardwareKeyboard.instance
                            .isShiftPressed);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _query,
                  focusNode: _focus,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: 'Find in page',
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (_) => _find(app),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              onPressed: () => _find(app, backwards: true),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon:
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              onPressed: () => _find(app),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => _close(app),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
