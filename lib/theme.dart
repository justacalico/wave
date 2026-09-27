import 'package:flutter/material.dart';

/// Wave's design system: quiet neutral surfaces, a single workspace accent
/// that tints the chrome, and generous rounded corners. Apple-adjacent.
class WaveTheme {
  WaveTheme._();

  static const double sidebarWidth = 236;
  static const double sidebarCollapsedWidth = 52;
  static const double panelWidth = 340;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  /// Workspace accent palettes. Each pair is [seed, tint] where seed colors
  /// interactive elements and tint washes the sidebar background.
  static const List<WorkspaceGradient> workspaceGradients = [
    WorkspaceGradient('Tide', Color(0xFF5B8CFF), Color(0xFF8FB4FF)),
    WorkspaceGradient('Ember', Color(0xFFFF7A59), Color(0xFFFFB49A)),
    WorkspaceGradient('Moss', Color(0xFF4FA87E), Color(0xFF9AD8BB)),
    WorkspaceGradient('Dusk', Color(0xFF9B7BFF), Color(0xFFC9B8FF)),
    WorkspaceGradient('Sand', Color(0xFFD9A441), Color(0xFFF0CE8E)),
    WorkspaceGradient('Rose', Color(0xFFE56B94), Color(0xFFF7B3CB)),
    WorkspaceGradient('Slate', Color(0xFF64748B), Color(0xFFA8B6C7)),
    WorkspaceGradient('Mono', Color(0xFF52525B), Color(0xFF9CA3AF)),
  ];

  static ThemeData light(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: const Color(0xFFF5F5F7),
    );
    return _base(scheme, const Color(0xFFEBEBEE), const Color(0xFFF5F5F7));
  }

  static ThemeData dark(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF17171A),
    );
    return _base(scheme, const Color(0xFF1C1C20), const Color(0xFF17171A));
  }

  static ThemeData _base(ColorScheme scheme, Color sidebar, Color content) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: content,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
      extensions: [WaveColors(sidebar: sidebar, content: content)],
    );
  }
}

class WorkspaceGradient {
  const WorkspaceGradient(this.name, this.seed, this.tint);
  final String name;
  final Color seed;
  final Color tint;
}

/// Colors outside the Material scheme.
class WaveColors extends ThemeExtension<WaveColors> {
  const WaveColors({required this.sidebar, required this.content});
  final Color sidebar;
  final Color content;

  @override
  WaveColors copyWith({Color? sidebar, Color? content}) =>
      WaveColors(sidebar: sidebar ?? this.sidebar, content: content ?? this.content);

  @override
  WaveColors lerp(WaveColors? other, double t) => other == null
      ? this
      : WaveColors(
          sidebar: Color.lerp(sidebar, other.sidebar, t)!,
          content: Color.lerp(content, other.content, t)!,
        );

  static WaveColors of(BuildContext context) =>
      Theme.of(context).extension<WaveColors>()!;
}
