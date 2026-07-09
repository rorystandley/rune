import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme.dart';
import 'ui/screens/create_vault_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/unlock_screen.dart';

/// Root widget. Owns the [AppController], observes app lifecycle for
/// lock-on-background, and routes to a screen based on the current [AppPhase].
class NotesApp extends StatefulWidget {
  const NotesApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.onSentToBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(controller: widget.controller, child: const _App());
  }
}

/// Builds the [MaterialApp] from the live [AppSettings] so the in-app
/// appearance controls (theme mode + reading text size) take effect
/// immediately. Kept below [AppScope] so a settings change rebuilds it.
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return MaterialApp(
      title: 'Rune',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      builder: (context, child) {
        // Compose the reading-size preference with the platform's own scaling
        // so OS accessibility text sizing still contributes rather than being
        // overridden. `scale(1)` reads back the platform's effective factor.
        final media = MediaQuery.of(context);
        final platformFactor = media.textScaler.scale(1);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(platformFactor * settings.textScale),
          ),
          child: child!,
        );
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return switch (controller.phase) {
      AppPhase.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AppPhase.needsCreation => const CreateVaultScreen(),
      AppPhase.locked => const UnlockScreen(),
      AppPhase.unlocked => const HomeScreen(),
    };
  }
}
