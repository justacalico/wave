import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> bootstrap() async {
  await Storage.init();
  final app = AppState();
  await app.init();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(760, 480),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Wave',
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
      app.activateCompanionIfNeeded();
    }));
  }

  runApp(
    ChangeNotifierProvider.value(
      value: app,
      child: const WaveApp(),
    ),
  );
}

class WaveApp extends StatelessWidget {
  const WaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Theme derives from the active workspace accent — a Consumer here
    // rebuilds only the MaterialApp, never the AppState above it.
    return Consumer<AppState>(
      builder: (context, app, _) {
        final ws = app.activeWorkspace;
        final g = WaveTheme.workspaceGradients[
            ws.gradientIndex % WaveTheme.workspaceGradients.length];
        return MaterialApp(
          title: 'Wave',
          debugShowCheckedModeBanner: false,
          theme: WaveTheme.light(g.seed),
          darkTheme: WaveTheme.dark(g.seed),
          themeMode: app.themeMode,
          home: const BrowserShell(),
        );
      },
    );
  }
}
