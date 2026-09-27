import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'companion_adapter.dart';
import 'inapp_adapter.dart';

/// What the browser shell needs from a rendering engine. Two engines exist:
/// [InAppTabController] (flutter_inappwebview — WebView/WKWebView/WebView2,
/// embedded as a widget) and [CompanionTabController] (desktop_webview_window —
/// WebKitGTK, a native window docked over the content rect). Same contract.
abstract class TabWebController {
  TabWebController(this.tab);

  final BrowserTab tab;

  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  bool _canGoBack = false;
  bool _canGoForward = false;

  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;

  /// Fired when the document URL changes.
  void Function(String url)? onUrlChanged;

  /// Fired when the document title changes.
  void Function(String title)? onTitleChanged;

  /// Fired when navigation capability changes.
  void Function(bool canGoBack, bool canGoForward)? onNavStateChanged;

  /// Fired when the page asks to open a new window (target=_blank, popups).
  void Function(String url)? onNewWindow;

  /// Fired when a download starts. Args: url, suggested filename.
  void Function(String url, String filename)? onDownloadStart;

  /// Fired when the webview wants the password vault. Resolves via [Completer].
  void Function(String origin)? onCredentialRequest;

  void setNavState(bool back, bool forward) {
    if (back != _canGoBack || forward != _canGoForward) {
      _canGoBack = back;
      _canGoForward = forward;
      onNavStateChanged?.call(back, forward);
    }
  }

  Future<void> loadUrl(String url);
  Future<void> reload();
  Future<void> stop();
  Future<void> goBack();
  Future<void> goForward();
  Future<String?> evaluateJavaScript(String source);
  Future<void> setMuted(bool muted);

  /// Companion-engine only: where on screen the webview window should sit.
  void setContentRect(Rect rect) {}

  /// Whether the engine's content should currently be on screen.
  void setEngineVisible(bool visible) {}

  Future<void> dispose();
}

/// Creates controllers for the current platform.
abstract class WebEngine {
  WebEngine._();

  static bool get usesCompanion =>
      !kIsWeb && Platform.isLinux;

  static TabWebController create(BrowserTab tab) =>
      usesCompanion ? CompanionTabController(tab) : InAppTabController(tab);
}

/// Injects Wave's JS helpers into a page: title/favicon reporting,
/// password-field detection for the vault, and reader-mode extraction.
const kWavePageScript = r'''
(function () {
  if (window.__waveInjected) return;
  window.__waveInjected = true;

  function post(name, body) {
    try {
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers[name]) {
        window.webkit.messageHandlers[name].postMessage(body);
      } else if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage({ name: name, body: body });
      } else if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler(name, body);
      }
    } catch (e) {}
  }

  function reportMeta() {
    var icon = '';
    var el = document.querySelector('link[rel~="icon"], link[rel="apple-touch-icon"]');
    if (el && el.href) icon = el.href;
    if (!icon) icon = location.origin + '/favicon.ico';
    post('waveMeta', JSON.stringify({ title: document.title, favicon: icon }));
  }

  new MutationObserver(function () { reportMeta(); })
    .observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener('DOMContentLoaded', reportMeta);
  window.addEventListener('load', reportMeta);
  setTimeout(reportMeta, 1200);

  // Password field detection for the vault.
  document.addEventListener('submit', function (e) {
    var form = e.target;
    if (!form || !form.querySelector) return;
    var pw = form.querySelector('input[type="password"]');
    if (!pw || !pw.value) return;
    var user = form.querySelector(
      'input[type="email"], input[type="text"], input[autocomplete="username"]');
    post('waveCredentialSubmit', JSON.stringify({
      origin: location.origin,
      username: user ? user.value : '',
      password: pw.value
    }));
  }, true);

  window.__waveFillCredential = function (u, p) {
    var pw = document.querySelector('input[type="password"]');
    if (!pw) return false;
    var form = pw.closest('form') || document;
    var user = form.querySelector(
      'input[type="email"], input[type="text"], input[autocomplete="username"]');
    if (user) {
      user.value = u;
      user.dispatchEvent(new Event('input', { bubbles: true }));
      user.dispatchEvent(new Event('change', { bubbles: true }));
    }
    pw.value = p;
    pw.dispatchEvent(new Event('input', { bubbles: true }));
    pw.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };
})();
''';

/// Compact readability pass: finds the densest text container and returns
/// title, byline and cleaned HTML for the reader view.
const kWaveReaderScript = r'''
(function () {
  var title = document.title;
  var og = document.querySelector('meta[property="og:title"]');
  if (og && og.content) title = og.content;
  var byline = '';
  var author = document.querySelector(
    'meta[name="author"], [rel="author"], .byline, [class*="author"]');
  if (author) byline = (author.content || author.textContent || '').trim();

  var best = null, bestScore = 0;
  var candidates = document.querySelectorAll(
    'article, main, [role="main"], .post, .content, .article, section, div');
  for (var i = 0; i < candidates.length; i++) {
    var el = candidates[i];
    var text = el.innerText || '';
    if (text.length < 200) continue;
    var p = el.querySelectorAll('p').length;
    var linkText = 0;
    var links = el.querySelectorAll('a');
    for (var j = 0; j < links.length; j++)
      linkText += (links[j].innerText || '').length;
    var score = p * 50 + text.length - linkText * 3;
    if (score > bestScore) { bestScore = score; best = el; }
  }
  if (!best) return JSON.stringify({ error: 'no content' });

  var clone = best.cloneNode(true);
  var junk = clone.querySelectorAll(
    'script, style, noscript, iframe, nav, aside, form, button, ' +
    '[class*="comment"], [class*="sidebar"], [class*="related"], ' +
    '[class*="share"], [class*="ad-"], [id*="ad-"]');
  for (var k = junk.length - 1; k >= 0; k--) junk[k].remove();
  var imgs = clone.querySelectorAll('img');
  for (var m = 0; m < imgs.length; m++) {
    var img = imgs[m];
    if (!img.src || img.width < 100 || img.naturalWidth < 100) img.remove();
  }

  var paras = clone.querySelectorAll('p');
  var total = 0;
  for (var n = 0; n < paras.length; n++) total += (paras[n].innerText || '').length;
  if (total < 300) return JSON.stringify({ error: 'not an article' });

  return JSON.stringify({
    title: title,
    byline: byline,
    html: clone.innerHTML,
    url: location.href,
    words: Math.round(total / 5.5)
  });
})();
''';
