import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// Shown when a vault exists but is locked (including at every app start).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with WidgetsBindingObserver {
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _automaticBiometricUnlockAttempted = false;
  bool _automaticBiometricUnlockScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleAutomaticBiometricUnlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAutomaticBiometricUnlock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pass.dispose();
    super.dispose();
  }

  void _scheduleAutomaticBiometricUnlock() {
    if (_automaticBiometricUnlockAttempted ||
        _automaticBiometricUnlockScheduled) {
      return;
    }
    _automaticBiometricUnlockScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _automaticBiometricUnlockScheduled = false;
      await _tryAutomaticBiometricUnlock();
    });
  }

  Future<void> _tryAutomaticBiometricUnlock() async {
    if (!mounted || _automaticBiometricUnlockAttempted) return;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final controller = AppScope.of(context);
    if (!controller.canUnlockWithBiometric) return;
    _automaticBiometricUnlockAttempted = true;
    await controller.unlockWithBiometric();
  }

  Future<void> _unlock() async {
    final ok = await AppScope.of(context).unlock(_pass.text);
    if (ok) return;
    if (mounted) _pass.clear();
  }

  Future<void> _unlockWithBiometric() async {
    await AppScope.of(context).unlockWithBiometric();
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
                Text(
                  'Rune is locked',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('unlock-pass'),
                  controller: _pass,
                  obscureText: _obscure,
                  autofocus: !controller.biometricUnlockReady,
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    errorText: controller.unlockError,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock'),
                  ),
                ),
                if (controller.biometricUnlockReady) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('biometric-unlock-button'),
                    icon: const Icon(Icons.fingerprint),
                    onPressed: controller.busy ? null : _unlockWithBiometric,
                    label: Text(_biometricButtonLabel(controller)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _biometricButtonLabel(AppController controller) {
    final label = controller.biometricUnlockLabel;
    if (label == 'Biometric unlock') return 'Unlock with biometrics';
    return 'Unlock with $label';
  }
}
