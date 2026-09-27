import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Tracks the host window's screen position and size and converts local
/// content rects into screen rects for companion webview windows. Only
/// active on Linux; a no-op elsewhere.
class CompanionDock extends ChangeNotifier with WindowListener {
  CompanionDock();

  Offset windowPos = Offset.zero;
  Size windowSize = Size.zero;
  bool active = false;

  static CompanionDock? maybeCreate() {
    if (kIsWeb || !Platform.isLinux) return null;
    return CompanionDock();
  }

  Future<void> init() async {
    active = true;
    windowManager.addListener(this);
    await refresh();
  }

  Future<void> refresh() async {
    if (!active) return;
    try {
      windowPos = await windowManager.getPosition();
      windowSize = await windowManager.getSize();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void onWindowMoved() => refresh();

  @override
  void onWindowResized() => refresh();

  @override
  void onWindowMinimize() => notifyListeners();

  @override
  void onWindowRestore() => refresh();

  /// Convert a rect in Flutter window coordinates into screen coordinates.
  Rect toScreen(Rect local) => local.shift(windowPos);

  @override
  void dispose() {
    if (active) windowManager.removeListener(this);
    super.dispose();
  }
}
