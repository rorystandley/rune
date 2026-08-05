import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Opens the native file picker so the user can choose a Rune backup
/// (`.notesbak`) to import or restore. Returns the chosen file, or null if the
/// user cancelled. Local selection only — makes no network calls.
///
/// Uses [FileType.any] rather than an extension filter: several desktop pickers
/// hide files when given a custom extension list, and the import path validates
/// the file's contents anyway, so a wrong pick fails safely with a clear error.
Future<File?> pickBackupFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choose a Rune backup',
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.first.path;
  return path == null ? null : File(path);
}
