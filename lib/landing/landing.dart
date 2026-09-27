import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web target = landing page. The browser itself needs a real webview, which
/// the web platform cannot host — so this page is deliberately not an app.
/// Dark, sea-toned, one animated line: a sine wave drawn by hand.
class WaveLandingApp extends StatelessWidget {
  const WaveLandingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wave — a quiet browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0B0E14),
          primary: Color(0xFF6DA8FF),
          onSurface: Color(0xFFE8ECF4),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 88,
            fontWeight: FontWeight.w600,
            letterSpacing: -3.5,
            height: 1.0,
            color: Color(0xFFE8ECF4),
          ),
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            color: Color(0xFFE8ECF4),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: Color(0xFF9AA4B8),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: Color(0xFF9AA4B8),
          ),
          labelSmall: TextStyle(
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5C6779),
          ),
        ),
      ),
      home: const LandingPage(),
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  static const releases =
      'https://gitlab.com/HttpAnimations/wave/-/releases';
  static const source = 'https://gitlab.com/HttpAnimations/wave';

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 860;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const _Nav(),
            SizedBox(
              height: wide ? 560 : 640,
              child: const Stack(
                children: [
                  Positioned.fill(child: _WaveField()),
                  Center(child: _Hero()),
                ],
              ),
            ),
            _SpecSheet(wide: wide),
            _EngineSection(wide: wide),
            _SyncSection(wide: wide),
            const _Footer(),
          ],
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
      child: Row(
        children: [
          const _WaveMark(size: 22),
          const SizedBox(width: 10),
          Text('wave',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                      fontWeight: FontWeight.w600, letterSpacing: -0.4)),
          const Spacer(),
          _NavLink(
              label: 'Download',
              onTap: () => launchUrl(Uri.parse(LandingPage.releases))),
          const SizedBox(width: 24),
          _NavLink(
              label: 'Source',
              onTap: () => launchUrl(Uri.parse(LandingPage.source))),
          const SizedBox(width: 24),
          _NavLink(
              label: 'AGPL-3.0',
              onTap: () => launchUrl(Uri.parse(
                  '${LandingPage.source}/-/blob/main/LICENSE'))),
        ],
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            fontSize: 13,
            color: _hover
                ? const Color(0xFFE8ECF4)
                : const Color(0xFF9AA4B8),
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

/// Three sine waves sliding at different rates — the only decoration.
class _WaveField extends StatefulWidget {
  const _WaveField();

  @override
  State<_WaveField> createState() => _WaveFieldState();
}

class _WaveFieldState extends State<_WaveField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) => CustomPaint(
        painter: _WavePainter(_ticker.value),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final specs = [
      (amp: 26.0, freq: 1.4, speed: 1.0, y: 0.62, alpha: 0.10),
      (amp: 18.0, freq: 2.1, speed: -0.7, y: 0.66, alpha: 0.14),
      (amp: 34.0, freq: 0.9, speed: 0.5, y: 0.70, alpha: 0.07),
    ];
    for (final s in specs) {
      final paint = Paint()
        ..color = const Color(0xFF6DA8FF).withValues(alpha: s.alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final path = Path();
      const steps = 120;
      for (var i = 0; i <= steps; i++) {
        final x = size.width * i / steps;
        final phase = t * 2 * math.pi * s.speed;
        final y = size.height * s.y +
            s.amp *
                math.sin(
                    (i / steps) * math.pi * 2 * s.freq + phase) *
                math.sin(i / steps * math.pi);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t;
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('A quiet browser.',
            textAlign: TextAlign.center, style: theme.displayLarge),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            'Wave keeps the chrome thin and the web thick: vertical tabs, '
            'workspaces that tint themselves, and Firefox Account sign-in '
            'so your things follow you.',
            textAlign: TextAlign.center,
            style: theme.bodyLarge,
          ),
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _DownloadButton(
                label: 'Linux', detail: 'deb · rpm · AppImage · tar'),
            _DownloadButton(
                label: 'Windows', detail: 'x86_64 · arm64 zip'),
            _DownloadButton(label: 'macOS', detail: 'dmg · arm64'),
            _DownloadButton(
                label: 'Android', detail: 'apk · aab'),
            _DownloadButton(
                label: 'iOS', detail: 'ipa via AltStore'),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'No telemetry. No account needed unless you want sync.',
          style: theme.labelSmall,
        ),
      ],
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(LandingPage.releases)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _hover
                ? const Color(0xFF6DA8FF).withValues(alpha: 0.12)
                : const Color(0xFF141925),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover
                  ? const Color(0xFF6DA8FF).withValues(alpha: 0.6)
                  : const Color(0xFF232B3A),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE8ECF4))),
              const SizedBox(height: 2),
              Text(widget.detail,
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF5C6779))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell(
      {required this.wide, required this.child, this.lede, this.title});

  final bool wide;
  final Widget child;
  final String? title;
  final String? lede;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: wide ? 120 : 28, vertical: 72),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(title!, style: theme.headlineMedium),
            if (lede != null) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(lede!, style: theme.bodyLarge),
              ),
            ],
            const SizedBox(height: 40),
            child,
          ],
        ),
      ),
    );
  }
}

/// Feature list styled as a spec sheet, not marketing cards.
class _SpecSheet extends StatelessWidget {
  const _SpecSheet({required this.wide});

  final bool wide;

  static const rows = [
    ('tabs', 'vertical, per-workspace, reorderable, sleep when idle'),
    ('workspaces', 'named contexts with their own accent and tab set'),
    ('pins', 'pinned and essential tabs survive restarts'),
    ('split', 'two pages side by side in one window'),
    ('search', 'omnibox with bangs — !g !ddg !w !gh !yt !mdn'),
    ('reader', 'distilled article view with adjustable type'),
    ('vault', 'AES-256-GCM passwords, autofill, FxA unlock'),
    ('sync', 'bookmarks · history · passwords · tabs, end to end'),
    ('privacy', 'per-tab private mode, per-tab containers are next'),
    ('keys', 'ctrl-t w l r f b tab 1..9, alt-arrows — full keyboard'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return _SectionShell(
      wide: wide,
      title: 'Spec',
      lede:
          'What ships in v1. Everything runs against the webview your OS '
          'already has — nothing bundled, nothing phoning home.',
      child: Column(
        children: [
          for (final r in rows)
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom:
                      BorderSide(color: Color(0xFF1A2130), width: 1),
                ),
              ),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(
                            r.$1,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Color(0xFF6DA8FF),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(r.$2,
                              style: theme.bodyMedium),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$1,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Color(0xFF6DA8FF))),
                        const SizedBox(height: 4),
                        Text(r.$2, style: theme.bodyMedium),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _EngineSection extends StatelessWidget {
  const _EngineSection({required this.wide});

  final bool wide;

  static const engines = [
    ('Linux', 'WebKitGTK', 'the same engine Tauri and GNOME Web use'),
    ('Windows', 'WebView2', 'Microsoft Edge runtime, already installed'),
    ('macOS / iOS', 'WKWebView', 'WebKit, sandboxed by the OS'),
    ('Android', 'Android WebView', 'Chromium, updated by Play system'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return _SectionShell(
      wide: wide,
      title: 'Borrowed engines, on purpose',
      lede: 'Wave does not ship a browser engine. Each build asks the '
          'operating system for its webview — the Tauri approach — so the '
          'download stays small and engine security updates come from the OS.',
      child: GridView.count(
        crossAxisCount: wide ? 2 : 1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        mainAxisExtent: 144,
        children: [
          for (final e in engines)
            Container(
              padding: const EdgeInsets.all(22),
              color: const Color(0xFF11151F),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(e.$1,
                      style: theme.labelSmall),
                  const SizedBox(height: 6),
                  Text(e.$2,
                      style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text(e.$3, style: theme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return _SectionShell(
      wide: wide,
      title: 'Firefox Accounts inside',
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Sign in with the account you already trust with your '
                    'tabs. Wave runs the same OAuth2 + PKCE flow and the '
                    'sync-1.5 protocol: tokenserver handshake, Hawk-signed '
                    'writes, AES-encrypted records.\n\n'
                    'When Mozilla grants the client the oldsync scope, Wave '
                    'syncs with your real Firefox profile. Until then, point '
                    'it at your own relay — or a self-hosted FxA stack — '
                    'with one setting.',
                    style: theme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 60),
                Expanded(child: const _SyncDiagram()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sign in with the account you already trust with your '
                  'tabs. Same OAuth2 + PKCE flow, same sync-1.5 protocol. '
                  'Bring your own relay until Mozilla opens the scope.',
                  style: theme.bodyLarge,
                ),
                const SizedBox(height: 32),
                const _SyncDiagram(),
              ],
            ),
    );
  }
}

class _SyncDiagram extends StatelessWidget {
  const _SyncDiagram();

  static const nodes = [
    ('oauth', 'PKCE sign-in', true),
    ('profile', 'identity + avatar', true),
    ('devices', 'this browser, listed', true),
    ('keys', 'kB scoped bundle', false),
    ('storage', 'sync-1.5 collections', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11151F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2636)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            Row(
              children: [
                Icon(
                  nodes[i].$3
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 15,
                  color: nodes[i].$3
                      ? const Color(0xFF6DA8FF)
                      : const Color(0xFF3A4557),
                ),
                const SizedBox(width: 12),
                Text(
                  nodes[i].$1,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFE8ECF4),
                  ),
                ),
                const Spacer(),
                Text(nodes[i].$2,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (i < nodes.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 7),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 1,
                    height: 16,
                    color: const Color(0xFF1E2636),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: const BoxDecoration(
        border: Border(
            top: BorderSide(color: Color(0xFF1A2130), width: 1)),
      ),
      child: Row(
        children: [
          const _WaveMark(size: 16),
          const SizedBox(width: 8),
          Text('wave',
              style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            'AGPL-3.0 · Flutter · system webview',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _WaveMark extends StatelessWidget {
  const _WaveMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _MarkPainter());
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    const n = 40;
    for (var row = 0; row < 2; row++) {
      paint.color = row == 0
          ? const Color(0xFF6DA8FF)
          : const Color(0xFF4FA87E);
      final path = Path();
      final yBase = size.height * (0.35 + row * 0.3);
      for (var i = 0; i <= n; i++) {
        final x = size.width * i / n;
        final y = yBase +
            math.sin(i / n * math.pi * 2) * size.height * 0.14;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}
