import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// Reader mode sheet: extracted article HTML rendered as calm Flutter text,
/// with font-size controls. Overlays the content area.
class ReaderSheet extends StatelessWidget {
  const ReaderSheet({super.key, required this.data, required this.onClose});

  final Map<String, dynamic> data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final title = data['title'] as String? ?? '';
    final byline = data['byline'] as String? ?? '';
    final html = data['html'] as String? ?? '';
    final words = data['words'] as int? ?? 0;
    final minutes = (words / 200).ceil();

    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Icon(Icons.chrome_reader_mode_rounded,
                    size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Reader',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                _FontButton(
                  icon: Icons.text_decrease_rounded,
                  onTap: () => app.setReaderFontSize(
                      (app.readerFontSize - 1).clamp(12, 28)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('${app.readerFontSize.toInt()}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                _FontButton(
                  icon: Icons.text_increase_rounded,
                  onTap: () => app.setReaderFontSize(
                      (app.readerFontSize + 1).clamp(12, 28)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 32, 0, 80),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          [
                            if (byline.isNotEmpty) byline,
                            if (minutes > 0) '$minutes min read',
                          ].join('  ·  '),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.55),
                              ),
                        ),
                        const SizedBox(height: 24),
                        HtmlWidget(
                          html,
                          textStyle: TextStyle(
                            fontSize: app.readerFontSize,
                            height: 1.65,
                            color: scheme.onSurface
                                .withValues(alpha: 0.92),
                          ),
                          customStylesBuilder: (element) {
                            switch (element.localName) {
                              case 'h1':
                              case 'h2':
                                return {
                                  'font-size':
                                      '${app.readerFontSize * 1.5}px',
                                  'font-weight': '700',
                                  'margin': '20px 0 8px',
                                };
                              case 'h3':
                              case 'h4':
                                return {
                                  'font-size':
                                      '${app.readerFontSize * 1.2}px',
                                  'font-weight': '600',
                                  'margin': '16px 0 6px',
                                };
                              case 'a':
                                return {
                                  'color':
                                      '#${scheme.primary.toARGB32().toRadixString(16).substring(2)}',
                                  'text-decoration': 'none',
                                };
                              case 'blockquote':
                                return {
                                  'border-left':
                                      '3px solid #${scheme.outlineVariant.toARGB32().toRadixString(16).substring(2)}',
                                  'padding-left': '16px',
                                  'font-style': 'italic',
                                };
                              case 'code':
                              case 'pre':
                                return {
                                  'font-family': 'monospace',
                                  'font-size':
                                      '${app.readerFontSize * 0.85}px',
                                };
                              case 'img':
                                return {'display': 'block'};
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontButton extends StatelessWidget {
  const _FontButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16),
      ),
    );
  }
}
