import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../storage.dart';
import '../models.dart';
import '../services/fxa.dart';

/// Settings panel — theme, search, behavior, and sync plumbing.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Appearance'),
        _SettingTile(
          title: 'Theme',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded, size: 15)),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded, size: 15)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded, size: 15)),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeMode(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        _SettingTile(
          title: 'Compact sidebar',
          child: Switch(
            value: app.sidebarCollapsed,
            onChanged: (_) => app.toggleSidebarCollapsed(),
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Search'),
        RadioGroup<String>(
          groupValue: app.searchEngineId,
          onChanged: (v) => app.setSearchEngine(v!),
          child: Column(
            children: [
              for (final e in SearchEngine.defaults)
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.name),
                  subtitle: Text(e.bang),
                  value: e.id,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Browsing'),
        _SettingTile(
          title: 'Restore tabs on start',
          child: Switch(
            value: app.restoreTabs,
            onChanged: app.setRestoreTabs,
          ),
        ),
        _SettingTile(
          title: 'Record history',
          child: Switch(
            value: app.recordHistory,
            onChanged: app.setRecordHistory,
          ),
        ),
        _SettingTile(
          title: 'Reader font size',
          child: SizedBox(
            width: 120,
            child: Slider(
              value: app.readerFontSize,
              min: 12,
              max: 28,
              divisions: 16,
              label: '${app.readerFontSize.toInt()}',
              onChanged: app.setReaderFontSize,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Sync backend'),
        _BackendPicker(),
        const SizedBox(height: 20),
        _SectionTitle('Firefox Accounts'),
        _FxaConfig(),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Wave · AGPL-3.0 · system webview',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
          ),
        ),
      ],
    );
  }
}

class _BackendPicker extends StatefulWidget {
  @override
  State<_BackendPicker> createState() => _BackendPickerState();
}

class _BackendPickerState extends State<_BackendPicker> {
  late final TextEditingController _relayUrl;
  late final TextEditingController _relayToken;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _relayUrl = TextEditingController(text: app.sync.relayUrl ?? '');
    _relayToken = TextEditingController(
        text: Storage.read(Storage.settings, 'sync_relay_token') ?? '');
  }

  @override
  void dispose() {
    _relayUrl.dispose();
    _relayToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final choice = app.sync.backendChoice;
    final backend = app.sync.backend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<String>(
          groupValue: choice,
          onChanged: (v) => app.sync.setBackendChoice(v!),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Automatic'),
                subtitle: Text(
                    'Firefox Sync if permitted, relay if configured, else local'),
                value: 'auto',
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Firefox Sync'),
                subtitle: Text(app.fxa.hasSyncScope
                    ? 'Signed in with sync scope'
                    : 'Requires Mozilla to grant your client oldsync scope'),
                value: 'fxa',
              ),
              const RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Self-hosted relay'),
                subtitle: Text('Your own JSON sync server'),
                value: 'selfhosted',
              ),
              if (choice == 'selfhosted') ...[
                TextField(
                  controller: _relayUrl,
                  decoration: const InputDecoration(
                      hintText: 'https://relay.example.com'),
                  onChanged: (_) => _saveRelay(app),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _relayToken,
                  decoration: const InputDecoration(
                      hintText: 'Bearer token'),
                  obscureText: true,
                  onChanged: (_) => _saveRelay(app),
                ),
              ],
              const RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Local files'),
                subtitle: Text('Sync to the app data directory'),
                value: 'local',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.storage_rounded,
                size: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text('Active: ${backend.label}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  void _saveRelay(AppState app) {
    app.sync.configureRelay(
        _relayUrl.text.trim(), _relayToken.text.trim());
  }
}

class _FxaConfig extends StatefulWidget {
  @override
  State<_FxaConfig> createState() => _FxaConfigState();
}

class _FxaConfigState extends State<_FxaConfig> {
  late final TextEditingController _clientId;
  late final TextEditingController _contentUrl;
  late final TextEditingController _oauthUrl;
  late final TextEditingController _profileUrl;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _clientId = TextEditingController(text: app.fxa.clientId);
    _contentUrl =
        TextEditingController(text: app.fxa.endpoints.contentUrl);
    _oauthUrl = TextEditingController(text: app.fxa.endpoints.oauthUrl);
    _profileUrl =
        TextEditingController(text: app.fxa.endpoints.profileUrl);
  }

  @override
  void dispose() {
    _clientId.dispose();
    _contentUrl.dispose();
    _oauthUrl.dispose();
    _profileUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _clientId,
          decoration:
              const InputDecoration(hintText: 'OAuth client id'),
          style: Theme.of(context).textTheme.bodySmall,
          onChanged: (v) => app.fxa.clientId = v.trim(),
        ),
        const SizedBox(height: 8),
        Text(
          'Get a client id from the FxA ecosystem partner program, or '
          'point the endpoints below at a self-hosted accounts stack.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contentUrl,
          decoration: const InputDecoration(
              hintText: 'Content server URL',
              labelText: 'Accounts UI'),
          style: Theme.of(context).textTheme.bodySmall,
          onChanged: _apply,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _oauthUrl,
          decoration: const InputDecoration(
              hintText: 'OAuth server', labelText: 'OAuth API'),
          style: Theme.of(context).textTheme.bodySmall,
          onChanged: _apply,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _profileUrl,
          decoration: const InputDecoration(
              hintText: 'Profile server', labelText: 'Profile API'),
          style: Theme.of(context).textTheme.bodySmall,
          onChanged: _apply,
        ),
      ],
    );
  }

  void _apply(String _) {
    final app = context.read<AppState>();
    app.fxa.configureEndpoints(FxaEndpoints(
      contentUrl: _contentUrl.text.trim(),
      oauthUrl: _oauthUrl.text.trim(),
      profileUrl: _profileUrl.text.trim(),
      tokenServerUrl: app.fxa.endpoints.tokenServerUrl,
    ));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          child,
        ],
      ),
    );
  }
}
