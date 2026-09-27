import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/vault.dart';
import '../theme.dart';
import 'widgets.dart';

/// Password vault panel. Locked: unlock via Firefox Account session or the
/// optional master password. Unlocked: searchable credential list.
class VaultPanel extends StatefulWidget {
  const VaultPanel({super.key});

  @override
  State<VaultPanel> createState() => _VaultPanelState();
}

class _VaultPanelState extends State<VaultPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final vault = app.vault;
    if (vault.locked) return const _VaultLocked();
    return _VaultList(
      query: _query,
      onQuery: (v) => setState(() => _query = v),
    );
  }
}

class _VaultLocked extends StatefulWidget {
  const _VaultLocked();

  @override
  State<_VaultLocked> createState() => _VaultLockedState();
}

class _VaultLockedState extends State<_VaultLocked> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock(AppState app, {String? password}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    bool ok;
    if (password != null) {
      ok = await app.vault.unlock(password);
    } else {
      ok = await app.vault.unlockWithAccount();
    }
    if (!ok && mounted) {
      setState(() => _error = 'Wrong password');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final vault = app.vault;
    final fxa = app.fxa;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded,
                  size: 26, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text('Vault locked',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Passwords stay encrypted on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
            ),
            const SizedBox(height: 20),
            if (fxa.signedIn && !vault.hasMasterPassword)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _tryUnlock(app),
                  icon: const Icon(Icons.verified_user_outlined,
                      size: 16),
                  label:
                      Text('Unlock as ${fxa.profile!.email}'),
                ),
              )
            else ...[
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: vault.hasMasterPassword
                      ? 'Master password'
                      : 'Set a master password',
                  errorText: _error,
                ),
                onSubmitted: (v) => _tryUnlock(app, password: v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (vault.hasMasterPassword) {
                            await _tryUnlock(app,
                                password: _password.text);
                          } else {
                            await _tryUnlock(app, password: null);
                            if (_password.text.isNotEmpty) {
                              await app.vault
                                  .setMasterPassword(_password.text);
                            }
                          }
                        },
                  child: Text(vault.hasMasterPassword
                      ? 'Unlock'
                      : 'Create vault'),
                ),
              ),
            ],
            if (!fxa.signedIn) ...[
              const SizedBox(height: 14),
              Text(
                'Sign in with Firefox Account to unlock without a '
                'password and sync credentials.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color:
                          scheme.onSurface.withValues(alpha: 0.45),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VaultList extends StatelessWidget {
  const _VaultList({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var items = app.vault.entries;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      items = items
          .where((e) =>
              e.origin.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q))
          .toList();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search passwords',
                    prefixIcon:
                        Icon(Icons.search_rounded, size: 16),
                  ),
                  onChanged: onQuery,
                ),
              ),
              const SizedBox(width: 6),
              GhostButton(
                icon: Icons.add_rounded,
                tooltip: 'Add password',
                onPressed: () => _editEntry(context, null),
              ),
              GhostButton(
                icon: Icons.lock_rounded,
                tooltip: 'Lock vault',
                onPressed: () => app.vault.lock(),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('Vault is empty',
                      style: TextStyle(fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _VaultTile(entry: items[i]),
                ),
        ),
      ],
    );
  }
}

class _VaultTile extends StatelessWidget {
  const _VaultTile({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(WaveTheme.radiusSm),
      onTap: () => _editEntry(context, entry),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            UrlFavicon(url: entry.origin, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(entry.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.5),
                          )),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 15),
              tooltip: 'Copy password',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: entry.password));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Password copied')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _editEntry(BuildContext context, VaultEntry? existing) {
  final app = context.read<AppState>();
  final origin =
      TextEditingController(text: existing?.origin ?? '');
  final username =
      TextEditingController(text: existing?.username ?? '');
  final password =
      TextEditingController(text: existing?.password ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  var obscure = true;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title:
            Text(existing == null ? 'New password' : 'Edit password'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: origin,
                decoration:
                    const InputDecoration(hintText: 'https://site.com'),
                autofocus: existing == null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: username,
                decoration:
                    const InputDecoration(hintText: 'Username'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: password,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                          hintText: 'Password'),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 16),
                    onPressed: () =>
                        setState(() => obscure = !obscure),
                  ),
                  IconButton(
                    icon: const Icon(Icons.casino_outlined, size: 16),
                    tooltip: 'Generate',
                    onPressed: () => setState(() =>
                        password.text =
                            VaultService.generatePassword()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(hintText: 'Note'),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                app.vault.remove(existing.id);
                Navigator.pop(context);
              },
              child: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final o = origin.text.trim();
              if (o.isEmpty) return;
              app.vault.upsert(VaultEntry(
                id: existing?.id ??
                    'v-${DateTime.now().microsecondsSinceEpoch}',
                origin: o.startsWith('http') ? o : 'https://$o',
                username: username.text.trim(),
                password: password.text,
                note: note.text.trim(),
                createdAt: existing?.createdAt,
              ));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
