import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wave/app_state.dart';
import 'package:wave/landing/landing.dart';
import 'package:wave/theme.dart';
import 'package:wave/ui/shell.dart';

import 'helpers.dart';


/// Golden tests are also the screenshot pipeline — these PNGs feed the
/// README and store listings. Regenerate with `flutter test --update-goldens`
/// on Linux (CI pins golden checks to ubuntu-latest for identical output).
void main() {
  late AppState app;
  setUp(() async {
    app = await makeAppState();
  });

  group('app goldens', () {
    testWidgets('desktop shell, light', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: WaveTheme.light(const Color(0xFF5B8CFF)),
          home: const BrowserShell(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await expectLater(find.byType(BrowserShell),
          matchesGoldenFile('goldens/shell_light.png'));
    });

    testWidgets('desktop shell, dark', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: WaveTheme.dark(const Color(0xFF9B7BFF)),
          home: const BrowserShell(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await expectLater(find.byType(BrowserShell),
          matchesGoldenFile('goldens/shell_dark.png'));
    });

    testWidgets('mobile shell', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: WaveTheme.dark(const Color(0xFF4FA87E)),
          home: const BrowserShell(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await expectLater(find.byType(BrowserShell),
          matchesGoldenFile('goldens/shell_mobile.png'));
    });
  });

  group('landing goldens', () {
    testWidgets('landing page desktop', (tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const WaveLandingApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await expectLater(find.byType(LandingPage),
          matchesGoldenFile('goldens/landing.png'));
    });
  });
}
