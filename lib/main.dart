import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bootstrap_stub.dart'
    if (dart.library.io) 'bootstrap_io.dart';
import 'landing/landing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // The web target is a landing page, not the browser itself — a webview
    // cannot render the web inside the web.
    runApp(const WaveLandingApp());
    return;
  }
  bootstrap();
}
