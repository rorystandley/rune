import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

/// Where finished exports go, and how the user chooses.
///
/// The two platform families need opposite mechanics:
///
///  - **Desktop** (macOS, Windows, Linux) has a native "Save As" dialog, so the
///    user picks the exact folder and filename up front. On the sandboxed macOS
///    App Store build this is also what *grants* write access to the chosen
///    location, so it isn't just nicer, it's required.
///  - **Mobile** (iOS, Android) has no save/directory picker in `file_selector`
///    (iOS overrides only openFile; Android has no save-file dialog), and an
///    app's Documents directory isn't reachable from the Files app anyway. So
///    the export is staged privately and handed to the OS share sheet, whose
///    "Save to Files" (iOS) / file targets (Android) let the user place it
///    wherever they can later open it.
///
/// This keeps the OS as the single arbiter of the destination — the app never
/// writes to a location the user can't reach.
///
/// The entry points are mutable so widget tests can drive the flows without a
/// real native dialog or share sheet; production never reassigns them.

/// True when the user picks the destination via a native Save dialog before the
/// export is written (desktop). False when the export is staged and then shared
/// (mobile).
bool supportsSaveLocationPicker =
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Opens a native "Save As" dialog for a single export file. Returns the chosen
/// absolute path, or null if the user cancelled. Desktop only.
Future<String?> Function({required String suggestedName})
chooseExportFileLocation = _chooseExportFileLocation;

/// Opens a native directory picker for the plaintext export (a folder of
/// Markdown files). Returns the chosen directory path, or null if cancelled.
/// Desktop only.
Future<String?> Function() chooseExportDirectory = _chooseExportDirectory;

/// Hands finished export files to the OS share sheet so the user can save them
/// to Files, send them to another app, AirDrop, etc. Used on mobile, where
/// there is no save dialog. [origin] anchors the share popover on iPad/macOS.
Future<void> Function(List<String> paths, {Rect? origin}) shareExportedFiles =
    _shareExportedFiles;

Future<String?> _chooseExportFileLocation({
  required String suggestedName,
}) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  return location?.path;
}

Future<String?> _chooseExportDirectory() => getDirectoryPath();

Future<void> _shareExportedFiles(
  List<String> paths, {
  Rect? origin,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [for (final path in paths) XFile(path)],
      sharePositionOrigin: origin,
    ),
  );
}
