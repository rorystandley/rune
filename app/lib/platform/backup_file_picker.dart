import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Opens the native file picker so the user can choose a Rune backup
/// (`.notesbak`) to import or restore. Returns the chosen file, or null if the
/// user cancelled. Local selection only — makes no network calls.
///
/// No type filter is applied: several desktop and mobile pickers hide files
/// behind a custom extension like `.notesbak`, and the import path validates the
/// file's contents anyway, so a wrong pick fails safely with a clear error.
Future<File?> pickBackupFile() async {
  final XFile? picked = await openFile();
  if (picked == null) return null;
  return File(picked.path);
}
