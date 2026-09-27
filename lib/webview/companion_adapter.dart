import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

import 'companion_dock.dart';
import 'controller.dart';

/// Linux engine. WebKitGTK (the same webview Tauri uses on Linux) has no
/// embeddable Flutter widget, so each tab is a borderless native window that
/// the shell parks exactly over the content area — the technique used by
/// shipping apps built on desktop_webview_window.
class CompanionTabController extends TabWebController {
  CompanionTabController(super.tab);

  Webview? _webview;
  Rect _rect = Rect.zero;
  bool _engineVisible = false;
  bool _launched = false;
  bool _broken = false;
  bool _disposed = false;

  /// One-shot: the window is created lazily on first activation so opening
  /// the app with 20 restored tabs does not spawn 20 windows. Failure (no
  /// WebKitGTK runtime, headless test VM) leaves the tab inert rather than
  /// crashing the shell.
  Future<void> ensureCreated() async {
    if (_webview != null || _broken) return;
    try {
      _webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        windowWidth: _rect.width.toInt().clamp(200, 10000),
        windowHeight: _rect.height.toInt().clamp(200, 10000),
        windowPosX: _rect.left.toInt(),
        windowPosY: _rect.top.toInt(),
        title: 'wave-tab-${tab.id}',
        titleBarHeight: 0,
        useWindowPositionAndSize: true,
        userDataFolderWindows:
            tab.isPrivate ? 'wave_private_${tab.id}' : 'wave_default',
      ),
      );
    } catch (_) {
      _broken = true;
      return;
    }
    final w = _webview!;
    w.addScriptToExecuteOnDocumentCreated(kWavePageScript);
    w.registerJavaScriptMessageHandler('waveMeta', _onMeta);
    w.registerJavaScriptMessageHandler('waveCredentialSubmit',
        (name, body) {
      try {
        final m =
            jsonDecode(body as String) as Map<String, dynamic>;
        onCredentialRequest?.call(
            m['origin'] as String? ?? tab.host,
            m['username'] as String? ?? '',
            m['password'] as String? ?? '');
      } catch (_) {
        onCredentialRequest?.call(tab.host, '', '');
      }
    });
    w.setOnUrlRequestCallback((url) {
      onUrlChanged?.call(url);
      loading.value = true;
      return true;
    });
    w.setOnHistoryChangedCallback((canBack, canForward) {
      setNavState(canBack, canForward);
    });
    unawaited(w.onClose.then((_) => _webview = null));
  }

  void _onMeta(String name, dynamic body) {
    try {
      final meta = jsonDecode(body as String) as Map;
      final title = meta['title'] as String?;
      if (title != null && title.isNotEmpty) {
        onTitleChanged?.call(title);
      }
      final favicon = meta['favicon'] as String?;
      if (favicon != null && favicon.isNotEmpty) {
        tab.faviconUrl = favicon;
      }
      loading.value = false;
      progress.value = 1;
    } catch (_) {}
  }

  void _applyRect() {
    final w = _webview;
    if (w == null || _rect.isEmpty) return;
    unawaited(w.moveWebviewWindow(
      _rect.left.toInt(),
      _rect.top.toInt(),
      _rect.width.toInt(),
      _rect.height.toInt(),
    ));
  }

  @override
  Future<void> loadUrl(String url) async {
    if (_disposed) return;
    await ensureCreated();
    if (_disposed || _broken) return;
    _launched = true;
    _webview?.launch(url);
    loading.value = true;
  }

  @override
  Future<void> reload() async {
    if (_launched) await _webview?.reload();
  }

  @override
  Future<void> stop() => _webview?.stop() ?? Future.value();

  @override
  Future<void> goBack() => _webview?.back() ?? Future.value();

  @override
  Future<void> goForward() => _webview?.forward() ?? Future.value();

  @override
  Future<String?> evaluateJavaScript(String source) =>
      _webview?.evaluateJavaScript(source) ?? Future.value();

  @override
  Future<void> setMuted(bool muted) {
    return evaluateJavaScript(
        'document.querySelectorAll("video,audio").forEach(m=>m.muted=$muted);');
  }

  @override
  void setContentRect(Rect rect) {
    if (rect == _rect) return;
    _rect = rect;
    _applyRect();
  }

  @override
  void setEngineVisible(bool visible) {
    _engineVisible = visible;
    if (_disposed) return;
    if (visible && !_launched && tab.url.isNotEmpty) {
      unawaited(loadUrl(tab.url));
      return;
    }
    final w = _webview;
    if (w == null) return;
    unawaited(w.setWebviewWindowVisibility(visible && _launched));
    if (visible && _launched) {
      _applyRect();
      unawaited(w.bringToForeground());
    }
  }

  bool get isVisible => _engineVisible;

  /// Sync after the host window moves or resizes.
  void syncGeometry() => _applyRect();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _webview?.close();
    _webview = null;
    progress.dispose();
    loading.dispose();
  }
}

/// Placeholder widget for the companion engine. Reports its global rect so
/// the native webview window can be docked over it; renders an explanatory
/// surface underneath (visible during window drag/desync).
class CompanionTabView extends StatelessWidget {
  const CompanionTabView({
    super.key,
    required this.controller,
    required this.dock,
  });

  final CompanionTabController controller;
  final CompanionDock dock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dock,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _report(context));
          return Container(color: Theme.of(context).scaffoldBackgroundColor);
        },
      ),
    );
  }

  void _report(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final local = box.localToGlobal(Offset.zero) & box.size;
    controller.setContentRect(dock.toScreen(local));
  }
}
