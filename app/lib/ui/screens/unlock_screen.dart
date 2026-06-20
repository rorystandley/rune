import 'package:flutter/material.dart';

import '../../state/app_scope.dart';

/// Shown when a vault exists but is locked (including at every app start).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final ok = await AppScope.of(context).unlock(_pass.text);
    if (ok) return;
    if (mounted) _pass.clear();
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
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock, size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Notes is locked',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('unlock-pass'),
                  controller: _pass,
                  obscureText: _obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    errorText: controller.unlockError,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _unlock(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('unlock-button'),
                  onPressed: controller.busy ? null : _unlock,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: controller.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
