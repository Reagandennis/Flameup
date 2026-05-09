import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color muted = onSurface.withValues(alpha: 0.7);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final ThemeModeNotifier notifier = ref.read(themeModeProvider.notifier);
    final AuthService auth = AuthService();

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings',
            style:
                TextStyle(color: onSurface, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: <Widget>[
            _ProfileCard(
              displayName: auth.displayName,
              email: auth.email,
            ),
            const SizedBox(height: 18),
            Text('Appearance',
                style:
                    TextStyle(color: muted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _SettingsCard(
              children: <Widget>[
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('System'),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('Light'),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('Dark'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Account',
                style:
                    TextStyle(color: muted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _SettingsCard(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Update display name'),
                  onTap: () =>
                      _showUpdateNameDialog(context, auth),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete account'),
                  subtitle:
                      const Text('This action is permanent and cannot be undone.'),
                  onTap: () => _confirmDeleteAccount(context, auth),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';
    return _SettingsCard(
      children: <Widget>[
        ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Text(initials,
                style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text(displayName,
              style: TextStyle(
                  color: scheme.onSurface, fontWeight: FontWeight.w800)),
          subtitle: Text(email,
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7))),
        ),
      ],
    );
  }
}

Future<void> _showUpdateNameDialog(
    BuildContext context, AuthService auth) async {
  final TextEditingController ctrl =
      TextEditingController(text: auth.displayName);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Update display name'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(labelText: 'Display Name'),
        autofocus: true,
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save')),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  try {
    await auth.updateDisplayName(ctrl.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

Future<void> _confirmDeleteAccount(
    BuildContext context, AuthService auth) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
          'All your data will be permanently removed. This cannot be undone.'),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    // Delete the current session — full account deletion requires a server function.
    // Send an email request in the meantime.
    await auth.signOut();
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@flameup.app',
      queryParameters: <String, String>{
        'subject': 'Account deletion request',
        'body': 'Please delete my Flameup account.\n\nEmail: ${auth.email}',
      },
    );
    await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    if (context.mounted) context.go('/login');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
