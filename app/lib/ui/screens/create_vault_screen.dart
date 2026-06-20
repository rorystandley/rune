import 'package:flutter/material.dart';

import '../../state/app_scope.dart';

/// First-launch screen: set a passphrase and create the encrypted local vault.
/// Makes the irreversibility of a forgotten passphrase impossible to miss.
class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _acknowledged = false;
  String? _error;

  static const int _minLength = 8;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pass = _pass.text;
    if (pass.length < _minLength) {
      setState(() => _error = 'Use at least $_minLength characters.');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = 'Passphrases do not match.');
      return;
    }
    if (!_acknowledged) {
      setState(() => _error = 'Please confirm you understand the warning.');
      return;
    }
    setState(() => _error = null);
    await AppScope.of(context).createVault(pass);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Create your vault',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Your notes are encrypted on this device with a passphrase '
                  'you choose. Nothing is sent anywhere.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('create-pass'),
                  controller: _pass,
                  obscureText: _obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('create-confirm'),
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration:
                      const InputDecoration(labelText: 'Confirm passphrase'),
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: 16),
                _WarningBox(
                  acknowledged: _acknowledged,
                  onChanged: (v) =>
                      setState(() => _acknowledged = v ?? false),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('create-button'),
                  onPressed: controller.busy ? null : _create,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: controller.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create vault'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Stored locally at:\n${controller.vaultLocation}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.acknowledged, required this.onChanged});

  final bool acknowledged;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('There is no password reset',
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'If you forget this passphrase, your notes cannot be recovered. '
            'There is no backdoor and no "forgot password". Write it down and '
            'keep it somewhere safe.',
            style: theme.textTheme.bodySmall,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!acknowledged),
            child: Row(
              children: [
                Checkbox(
                  key: const Key('create-ack'),
                  value: acknowledged,
                  onChanged: onChanged,
                ),
                const Expanded(
                  child:
                      Text('I understand my passphrase cannot be recovered'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
