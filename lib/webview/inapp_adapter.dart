import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'controller.dart';

/// Embedded engine backed by flutter_inappwebview. Covers Android, iOS,
/// Windows (WebView2) and macOS (WKWebView) — the same strategy Tauri uses:
/// the webview the OS already ships, embedded in the app window.
class InAppTabController extends TabWebController {
  InAppTabController(super.tab);

  InAppWebViewController? _inner;

  /// Called by [InAppTabView] once the platform view hands us a controller.
  void attach(InAppWebViewController controller) {
    _inner = controller;
    _wireJsHandlers(controller);
    if (tab.url.isNotEmpty) {
      unawaited(controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(tab.url))));
    }
  }

  void _wireJsHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'waveMeta',
      callback: (args) {
        if (args.isEmpty) return;
        try {
          final meta = jsonDecode(args.first as String) as Map;
          final title = meta['title'] as String?;
          if (title != null && title.isNotEmpty && title != tab.title) {
            onTitleChanged?.call(title);
          }
          final favicon = meta['favicon'] as String?;
          if (favicon != null && favicon.isNotEmpty) {
            tab.faviconUrl = favicon;
          }
        } catch (_) {}
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'waveCredentialSubmit',
      callback: (args) {
        if (args.isEmpty) return;
        onCredentialRequest?.call(tab.host);
      },
    );
  }

  @override
  Future<void> loadUrl(String url) =>
      _inner?.loadUrl(urlRequest: URLRequest(url: WebUri(url))) ??
      Future.value();

  @override
  Future<void> reload() => _inner?.reload() ?? Future.value();

  @override
  Future<void> stop() => _inner?.stopLoading() ?? Future.value();

  @override
  Future<void> goBack() async {
    if (await _inner?.canGoBack() ?? false) await _inner?.goBack();
  }

  @override
  Future<void> goForward() async {
    if (await _inner?.canGoForward() ?? false) await _inner?.goForward();
  }

  @override
  Future<String?> evaluateJavaScript(String source) async {
    final result = await _inner?.evaluateJavascript(source: source);
    if (result == null) return null;
    return result is String ? result : jsonEncode(result);
  }

  @override
  Future<void> setMuted(bool muted) => evaluateJavaScript(
      'document.querySelectorAll("video,audio").forEach(m=>m.muted=$muted);')
      .then((_) {});

  @override
  Future<void> dispose() async {
    _inner = null;
    progress.dispose();
    loading.dispose();
  }
}

/// Widget half of the in-app engine. One per open tab; kept alive in an
/// IndexedStack so switching tabs never reloads the page.
class InAppTabView extends StatefulWidget {
  const InAppTabView({super.key, required this.controller});

  final InAppTabController controller;

  @override
  State<InAppTabView> createState() => _InAppTabViewState();
}

class _InAppTabViewState extends State<InAppTabView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        incognito: widget.controller.tab.isPrivate,
        useOnDownloadStart: true,
        supportMultipleWindows: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsBackForwardNavigationGestures: true,
        useWideViewPort: true,
        builtInZoomControls: false,
        displayZoomControls: false,
        safeBrowsingEnabled: true,
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.controller;
    return InAppWebView(
      keepAlive: InAppWebViewKeepAlive(),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: kWavePageScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: c.attach,
      onLoadStart: (controller, url) {
        c.loading.value = true;
        if (url != null) c.onUrlChanged?.call(url.toString());
      },
      onLoadStop: (controller, url) async {
        c.loading.value = false;
        c.progress.value = 1;
        if (url != null) c.onUrlChanged?.call(url.toString());
        c.setNavState(
          await controller.canGoBack(),
          await controller.canGoForward(),
        );
      },
      onProgressChanged: (controller, p) {
        c.progress.value = p / 100;
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        if (url != null) c.onUrlChanged?.call(url.toString());
        c.setNavState(
          await controller.canGoBack(),
          await controller.canGoForward(),
        );
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.isNotEmpty) c.onTitleChanged?.call(title);
      },
      onCreateWindow: (controller, action) async {
        final url = action.request.url?.toString();
        if (url != null && url.isNotEmpty) c.onNewWindow?.call(url);
        return false;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url;
        if (url == null) return NavigationActionPolicy.ALLOW;
        final scheme = url.scheme;
        if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
          return NavigationActionPolicy.ALLOW;
        }
        // Custom schemes (mailto:, intent:, etc.) are left to the OS.
        return NavigationActionPolicy.CANCEL;
      },
      onDownloadStartRequest: (controller, request) {
        c.onDownloadStart?.call(
          request.url.toString(),
          request.suggestedFilename ?? request.url.pathSegments.lastOrNull ?? 'download',
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          c.loading.value = false;
        }
      },
    );
  }
}
