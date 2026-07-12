// Temporary Mac App Store screenshot harness. Runs the seeded demo app and
// captures each store-worthy screen by rendering the root RepaintBoundary to
// a PNG from inside Flutter — no screen-recording or accessibility
// permissions involved. Launch the built binary directly and read the SHOT
// lines from stdout. Not part of CI; delete after use.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:notes_app/app.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/ui/screens/settings_screen.dart';

import 'demo_seed.dart';

final GlobalKey _shotKey = GlobalKey();
late final Directory _outDir;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _outDir = await Directory.systemTemp.createTemp('rune_mas_shots');
  final controller = await buildSeededController();
  runApp(RepaintBoundary(key: _shotKey, child: NotesApp(controller: controller)));
  unawaited(_drive(controller));
}

Future<void> _drive(AppController controller) async {
  await _settle(const Duration(seconds: 3)); // first frame + fonts

  // Shots 01-04 are light regardless of the machine's system theme.
  await controller
      .updateSettings(controller.settings.copyWith(themeMode: ThemeMode.light));
  await _settle(const Duration(milliseconds: 600));

  // 01: two-pane home, hero note open (seed selects it).
  await _capture('01-home-light');

  // 02: Markdown preview of the note with list markup.
  final q3 = controller.visibleNotes.firstWhere((n) => n.title == 'Q3 planning');
  controller.selectNote(q3.id);
  await _settle(const Duration(milliseconds: 800));
  await _tapKey('preview-toggle');
  await _settle(const Duration(milliseconds: 800));
  await _capture('02-markdown-preview');
  await _tapKey('preview-toggle'); // back to the editor
  await _settle(const Duration(milliseconds: 400));

  // 03: search with result count + highlighted matches.
  _searchField().text = 'time';
  controller.setSearch('time');
  await _settle(const Duration(milliseconds: 800));
  await _capture('03-search');
  _searchField().text = '';
  controller.setSearch('');
  await _settle(const Duration(milliseconds: 400));

  // 04: settings with the privacy posture card.
  final navigator = _findNavigator();
  unawaited(navigator.push(
    MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
  ));
  await _settle(const Duration(milliseconds: 900));
  await _capture('04-settings');

  // 05: dark mode, back on the two-pane home with the hero note.
  await controller
      .updateSettings(controller.settings.copyWith(themeMode: ThemeMode.dark));
  navigator.pop();
  final hero =
      controller.visibleNotes.firstWhere((n) => n.title == 'Welcome to Notes');
  controller.selectNote(hero.id);
  await _settle(const Duration(milliseconds: 900));
  await _capture('05-home-dark');

  stdout.writeln('ALL DONE ${_outDir.path}');
  await stdout.flush();
  exit(0);
}

Future<void> _settle(Duration d) async {
  await Future<void>.delayed(d);
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _capture(String name) async {
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${_outDir.path}/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  stdout.writeln('SHOT ${file.path} ${image.width}x${image.height}');
  await stdout.flush();
}

Element _findElement(bool Function(Element) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  if (found == null) throw StateError('element not found');
  return found!;
}

Future<void> _tapKey(String key) async {
  final element =
      _findElement((e) => e.widget.key == Key(key));
  final box = element.renderObject! as RenderBox;
  final pos = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 99, position: pos));
  await Future<void>.delayed(const Duration(milliseconds: 80));
  GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: 99, position: pos));
  await WidgetsBinding.instance.endOfFrame;
}

TextEditingController _searchField() {
  final element = _findElement(
      (e) => e.widget.key == const Key('search-field') && e.widget is TextField);
  return (element.widget as TextField).controller!;
}

NavigatorState _findNavigator() {
  final element = _findElement(
      (e) => e is StatefulElement && e.state is NavigatorState);
  return (element as StatefulElement).state as NavigatorState;
}
