import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/sync.dart';
import '../theme.dart';
import 'widgets.dart';

/// Firefox Account panel: sign-in card when logged out; profile, sync
/// status, synced tab list and backend info when logged in.
class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.fxa.signedIn) return const _SignInCard();
    return const _AccountView();
  }
}

class _SignInCard extends StatefulWidget {
  const _SignInCard();

  @override
  State<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<_SignInCard> {
  late final TextEditingController _clientId;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController(
        text: context.read<AppState>().fxa.clientId);
  }

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.8),
                    scheme.tertiary.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.local_fire_department_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 18),
            Text('Firefox Account',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Sign in to sync bookmarks, passwords, tabs and history '
              'across Wave — and Firefox when Mozilla opens the sync '
              'scope to your client.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _clientId,
              decoration: const InputDecoration(
                hintText: 'OAuth client id',
                helperText: 'Required — from the FxA partner program '
                    'or a self-hosted stack',
              ),
              onChanged: (v) => app.fxa.clientId = v.trim(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: app.fxa.signingIn
                    ? null
                    : () => _signIn(context),
                icon: app.fxa.signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : const Icon(Icons.login_rounded, size: 16),
                label: Text(app.fxa.signingIn
                    ? 'Waiting for sign-in…'
                    : 'Sign in'),
              ),
            ),
            if (app.fxa.lastError != null) ...[
              const SizedBox(height: 10),
              Text(
                app.fxa.lastError!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      await context.read<AppState>().fxa.signIn();
      if (context.mounted) {
        await context.read<AppState>().vault.unlockWithAccount();
      }
    } catch (_) {}
  }
}

class _AccountView extends StatelessWidget {
  const _AccountView();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.fxa.profile!;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: p.avatarUrl != null
                  ? NetworkImage(p.avatarUrl!)
                  : null,
              backgroundColor: scheme.primaryContainer,
              child: p.avatarUrl == null
                  ? const Icon(Icons.person_rounded, size: 22)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.displayName ?? p.email,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                  if (p.displayName != null)
                    Text(p.email,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: scheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 18),
              tooltip: 'Sign out',
              onPressed: () => _signOut(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SyncStatusCard(),
        const SizedBox(height: 16),
        const _SyncedTabsList(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
          ),
          child: Row(
            children: [
              Icon(
                app.fxa.hasSyncScope
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 15,
                color: app.fxa.hasSyncScope
                    ? Colors.green
                    : scheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  app.fxa.hasSyncScope
                      ? 'Firefox Sync scope granted — Wave syncs with '
                          'your other Firefoxes.'
                      : 'Sync scope not granted to this client — Wave '
                          'uses the ${app.sync.backend.label.toLowerCase()} '
                          'backend until Mozilla allows it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            scheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _signOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Firefox Account?'),
        content: const Text(
            'Syncing pauses on this device. Your data stays encrypted '
            'on the server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AppState>().fxa.signOut();
              Navigator.pop(context);
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = app.sync;
    final scheme = Theme.of(context).colorScheme;

    String statusText;
    IconData icon;
    Color? color;
    switch (sync.status) {
      case SyncStatus.idle:
        statusText = sync.lastSyncAt == null
            ? 'Never synced'
            : 'Last synced ${_ago(sync.lastSyncAt!)}';
        icon = Icons.sync_rounded;
        color = scheme.primary;
        break;
      case SyncStatus.syncing:
        statusText = 'Syncing…';
        icon = Icons.sync_rounded;
        color = scheme.primary;
        break;
      case SyncStatus.error:
        statusText = 'Sync error: ${sync.lastError}';
        icon = Icons.error_outline_rounded;
        color = scheme.error;
        break;
      case SyncStatus.disabled:
        statusText = 'No sync backend configured';
        icon = Icons.sync_disabled_rounded;
        color = scheme.onSurface.withValues(alpha: 0.4);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(WaveTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sync',
                    style:
                        Theme.of(context).textTheme.titleSmall),
                Text(statusText,
                    maxLines: 2,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.55),
                        )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: sync.status == SyncStatus.syncing
                ? null
                : () => app.syncNow(),
            child: const Text('Sync now'),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Tabs open on other synced devices, from the `tabs` collection.
class _SyncedTabsList extends StatefulWidget {
  const _SyncedTabsList();

  @override
  State<_SyncedTabsList> createState() => _SyncedTabsListState();
}

class _SyncedTabsListState extends State<_SyncedTabsList> {
  List<SyncRecord>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.sync.backend.ready) return;
    try {
      final recs =
          await app.sync.backend.download('tabs', since: 0);
      final localIds =
          app.tabs.map((t) => t.id).toSet();
      if (mounted) {
        setState(() {
          _remote = recs.where((r) => !localIds.contains(r.id)).toList();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remote = _remote;
    if (remote == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Synced tabs',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (remote.isEmpty)
          Text('Nothing from other devices yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ))
        else
          for (final r in remote.take(10))
            _RemoteTabTile(record: r),
      ],
    );
  }
}

class _RemoteTabTile extends StatelessWidget {
  const _RemoteTabTile({required this.record});

  final SyncRecord record;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(record.payload) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    final title = j['title'] as String? ?? '';
    final url = j['url'] as String? ?? '';
    if (url.isEmpty) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: UrlFavicon(url: url, size: 16),
      title: Text(title.isEmpty ? url : title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      onTap: () =>
          context.read<AppState>().openUrlInNewTab(url),
    );
  }
}
