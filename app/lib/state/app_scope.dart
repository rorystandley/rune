import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Exposes the single [AppController] to the widget tree. Widgets read it with
/// `AppScope.of(context)` and rebuild when it notifies.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found in the widget tree');
    return scope!.notifier!;
  }
}
