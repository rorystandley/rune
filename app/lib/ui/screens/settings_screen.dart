import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../app_version.g.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../state/app_settings.dart';
import '../widgets/dialogs.dart';
import '../widgets/passphrase_strength_meter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<int> _autoLockOptions = [0, 1, 5, 15, 30];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _PrivacyPostureCard(),
          _section(context, 'Appearance'),
          const _AppearanceControls(),
          _section(context, 'Security'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock'),
            subtitle: const Text('Lock after a period of inactivity'),
            trailing: DropdownButton<int>(
              value: _autoLockOptions.contains(settings.autoLockMinutes)
                  ? settings.autoLockMinutes
                  : 5,
              onChanged: (v) => controller.updateSettings(
                settings.copyWith(autoLockMinutes: v),
              ),
              items: _autoLockOptions
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m == 0 ? 'Off' : '$m min'),
                    ),
                  )
                  .toList(),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.exit_to_app),
            title: const Text('Lock when sent to background'),
            value: settings.lockOnBackground,
            onChanged: (v) => controller.updateSettings(
              settings.copyWith(lockOnBackground: v),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(controller.biometricUnlockLabel),
            subtitle: Text(_biometricSubtitle(controller)),
            value: controller.biometricUnlockReady,
            onChanged: controller.busy || !controller.biometricUnlockAvailable
                ? null
                : (v) => _setBiometricUnlock(context, controller, v),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change passphrase'),
            onTap: () => _changePassphrase(context, controller),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: () {
              controller.lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          _section(context, 'Voice notes'),
          SwitchListTile(
            secondary: const Icon(Icons.save_outlined),
            title: const Text('Keep audio by default'),
            subtitle: const Text(
              'Off = delete the recording after transcription',
            ),
            value: settings.keepAudioByDefault,
            onChanged: (v) => controller.updateSettings(
              settings.copyWith(keepAudioByDefault: v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Transcription engine'),
            subtitle: Text(
              controller.transcription == null
                  ? 'Not available on this platform'
                  : '${controller.transcription!.engineName}'
                        '${controller.transcription!.isLocal ? ' · on-device' : ''}',
            ),
          ),
          _section(context, 'Backup & export'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Export encrypted backup'),
            subtitle: const Text(
              'Safe: stays encrypted, needs your passphrase',
            ),
            onTap: () => _exportEncrypted(context, controller),
          ),
          ListTile(
            leading: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Export plaintext (unencrypted)'),
            subtitle: const Text(
              'Dangerous: writes readable, unprotected files',
            ),
            onTap: () => _exportPlaintext(context, controller),
          ),
          _section(context, 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text(kAppVersionDisplay),
          ),
          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Cryptography'),
            subtitle: Text(
              'Argon2id key derivation · XChaCha20-Poly1305 AEAD\n'
              'via the audited `cryptography` Dart package',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).hintColor,
        letterSpacing: 0.8,
      ),
    ),
  );

  Future<void> _exportEncrypted(
    BuildContext context,
    AppController controller,
  ) async {
    try {
      final file = await controller.exportEncryptedBackup();
      if (context.mounted) {
        await _showPath(context, 'Encrypted backup saved', file.path);
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Export failed.');
    }
  }

  Future<void> _exportPlaintext(
    BuildContext context,
    AppController controller,
  ) async {
    final ok = await confirmDestructive(
      context,
      title: 'Export unencrypted notes?',
      message:
          'This writes ALL of your notes as plain, readable files with no '
          'encryption. Anyone with access to those files can read them. Only do '
          'this if you understand the risk and will store the files safely.',
      confirmLabel: 'Export plaintext',
    );
    if (!ok) return;
    try {
      final dir = await controller.exportPlaintext(confirmed: true);
      if (context.mounted) {
        await _showPath(
          context,
          'Plaintext export (UNENCRYPTED) saved',
          dir.path,
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Export failed.');
    }
  }

  Future<void> _changePassphrase(
    BuildContext context,
    AppController controller,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ChangePassphraseDialog(controller: controller),
    );
  }

  String _biometricSubtitle(AppController controller) {
    if (!controller.biometricUnlockAvailable) {
      return controller.biometricUnlockAvailability.reason ??
          'Not available on this device';
    }
    if (controller.biometricUnlockReady) {
      return 'On - prompts automatically when locked';
    }
    if (controller.settings.biometricUnlockEnabled) {
      return 'Set up again for this vault';
    }
    return 'Off';
  }

  Future<void> _setBiometricUnlock(
    BuildContext context,
    AppController controller,
    bool enabled,
  ) async {
    if (!enabled) {
      await controller.disableBiometricUnlock();
      if (context.mounted) _snack(context, 'Biometric unlock disabled.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enable ${controller.biometricUnlockLabel}?'),
        content: const Text(
          'Rune will store this vault key in this device\'s secure credential '
          'store and prompt automatically when the vault is locked. Your '
          'passphrase still works and is still required anywhere you do not '
          'enable this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final enabledNow = await controller.enableBiometricUnlock();
    if (!context.mounted) return;
    _snack(
      context,
      enabledNow
          ? 'Biometric unlock enabled.'
          : controller.biometricUnlockError ?? 'Biometric unlock unavailable.',
    );
  }

  Future<void> _showPath(BuildContext context, String title, String path) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saved to:'),
            const SizedBox(height: 8),
            SelectableText(path, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

/// Light / Dark / System theme picker and a reading text-size slider with a
/// live preview. The slider commits (persists) on release to avoid writing the
/// settings file on every drag tick.
class _AppearanceControls extends StatefulWidget {
  const _AppearanceControls();

  @override
  State<_AppearanceControls> createState() => _AppearanceControlsState();
}

class _AppearanceControlsState extends State<_AppearanceControls> {
  double? _dragScale;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final settings = controller.settings;
    final theme = Theme.of(context);
    final scale = _dragScale ?? settings.textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.brightness_6_outlined),
              const SizedBox(width: 16),
              const Expanded(child: Text('Theme')),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    tooltip: 'Follow the system setting',
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    tooltip: 'Light',
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    tooltip: 'Dark',
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) => controller.updateSettings(
                  settings.copyWith(themeMode: s.first),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.format_size),
              const SizedBox(width: 16),
              const Expanded(child: Text('Text size')),
              Text(
                '${(scale * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: scale,
          min: AppSettings.minTextScale,
          max: AppSettings.maxTextScale,
          // 0.05 steps across the ~0.85–1.40 range.
          divisions:
              ((AppSettings.maxTextScale - AppSettings.minTextScale) / 0.05)
                  .round(),
          label: '${(scale * 100).round()}%',
          onChanged: (v) => setState(() => _dragScale = v),
          onChangeEnd: (v) {
            setState(() => _dragScale = null);
            controller.updateSettings(settings.copyWith(textScale: v));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'The quick brown fox jumps over the lazy dog.',
            // Preview the chosen size directly, independent of the value the
            // rest of the app is currently rendering at.
            textScaler: TextScaler.linear(scale),
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
          ),
        ),
      ],
    );
  }
}

class _PrivacyPostureCard extends StatelessWidget {
  const _PrivacyPostureCard();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final theme = Theme.of(context);
    const items = [
      'No telemetry, analytics, or tracking',
      'No network calls, works fully offline',
      'Notes encrypted at rest (XChaCha20-Poly1305)',
      'Key derived from your passphrase (Argon2id)',
      'No account, no cloud, no third parties',
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Privacy posture', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            const Divider(height: 24),
            Text('Vault location', style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            SelectableText(
              controller.vaultLocation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePassphraseDialog extends StatefulWidget {
  const _ChangePassphraseDialog({required this.controller});
  final AppController controller;

  @override
  State<_ChangePassphraseDialog> createState() =>
      _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends State<_ChangePassphraseDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 8) {
      setState(() => _error = 'New passphrase must be at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passphrases do not match.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await widget.controller.changePassphrase(_current.text, _next.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Passphrase changed.')));
      }
    } on WrongPassphraseException {
      setState(() {
        _error = 'Current passphrase is incorrect.';
        _busy = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not change passphrase.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current passphrase'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _next,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'New passphrase'),
          ),
          PassphraseStrengthMeter(passphrase: _next.text),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new passphrase',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change'),
        ),
      ],
    );
  }
}
