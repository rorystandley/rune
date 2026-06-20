import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notes_core/notes_core.dart';

import '../platform/audio_recorder.dart';
import 'app_settings.dart';

enum AppPhase { loading, needsCreation, locked, unlocked }

/// The single source of truth for app state. Wraps the pure-Dart [VaultService]
/// / [NotesRepository] / [ExportService] and adds UI concerns: the lock/unlock
/// state machine, auto-lock timer, current selection and search.
///
/// No secrets are logged here. Decrypted notes live only inside [repo] while
/// unlocked and are dropped on [lock].
class AppController extends ChangeNotifier {
  AppController({
    required this.vaultDir,
    required this.audioTempDir,
    required this.exportsDir,
    required this.settingsStore,
    required this.transcription,
    required this.recorder,
    CryptoService? crypto,
    this.createKdfParams, // test seam: cheap params in tests, null = production
  }) : store = FileVaultStore(vaultDir) {
    final c = crypto ?? CryptoService();
    vault = VaultService(store: store, crypto: c);
    repo = NotesRepository(vault: vault, store: store);
    exporter = ExportService(store: store);
  }

  final Directory vaultDir;
  final Directory audioTempDir;
  final Directory exportsDir;
  final SettingsStore settingsStore;
  final TranscriptionService transcription;
  final AudioRecorderPort recorder;
  final KdfParams? createKdfParams;

  late final FileVaultStore store;
  late final VaultService vault;
  late final NotesRepository repo;
  late final ExportService exporter;

  AppPhase _phase = AppPhase.loading;
  AppSettings _settings = const AppSettings();
  String _search = '';
  String? _selectedId;
  String? _unlockError;
  bool _busy = false;
  Timer? _autoLockTimer;

  AppPhase get phase => _phase;
  AppSettings get settings => _settings;
  String get search => _search;
  String? get selectedId => _selectedId;
  String? get unlockError => _unlockError;
  bool get busy => _busy;
  String get vaultLocation => store.description;

  List<Note> get visibleNotes => repo.search(_search);
  Note? get selectedNote =>
      _selectedId == null ? null : repo.getNote(_selectedId!);

  /// Loads settings and decides the initial phase: locked if a vault exists,
  /// otherwise the create-vault flow.
  Future<void> init() async {
    _settings = await settingsStore.load();
    _phase =
        (await vault.vaultExists()) ? AppPhase.locked : AppPhase.needsCreation;
    notifyListeners();
  }

  // ---------------------------------------------------------------- vault ---

  Future<void> createVault(String passphrase) async {
    _setBusy(true);
    try {
      await vault.createVault(passphrase, kdfParams: createKdfParams);
      await repo.loadAll();
      _enterUnlocked();
    } finally {
      _setBusy(false);
    }
  }

  /// Returns true on success; sets [unlockError] and returns false on a wrong
  /// passphrase.
  Future<bool> unlock(String passphrase) async {
    _setBusy(true);
    _unlockError = null;
    try {
      await vault.unlock(passphrase);
      await repo.loadAll();
      _enterUnlocked();
      return true;
    } on WrongPassphraseException {
      _unlockError = 'Incorrect passphrase.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void lock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    repo.clear();
    vault.lock();
    _selectedId = null;
    _search = '';
    _unlockError = null;
    _phase = AppPhase.locked;
    notifyListeners();
  }

  void _enterUnlocked() {
    _selectedId = null; // show the list; user picks a note
    _search = '';
    _unlockError = null;
    _phase = AppPhase.unlocked;
    _resetAutoLock();
    notifyListeners();
  }

  Future<void> changePassphrase(String current, String next) =>
      vault.changePassphrase(current, next);

  // ---------------------------------------------------------------- notes ---

  Future<Note> newNote() async {
    final note = await repo.createNote();
    _selectedId = note.id;
    notifyListeners();
    return note;
  }

  /// Autosave entry point from the editor. No-op if nothing changed.
  Future<void> saveNote(String id,
      {required String title, required String body}) async {
    final existing = repo.getNote(id);
    if (existing == null) return;
    if (existing.title == title && existing.body == body) return;
    await repo.updateNote(id, title: title, body: body);
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    await repo.deleteNote(id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  void selectNote(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  void setSearch(String query) {
    _search = query;
    notifyListeners();
  }

  // ------------------------------------------------------------- settings ---

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    await settingsStore.save(next);
    _resetAutoLock();
    notifyListeners();
  }

  // --------------------------------------------------------------- export ---

  Future<File> exportEncryptedBackup() async {
    final target =
        File('${exportsDir.path}/notes-backup-${_stamp()}.notesbak');
    return exporter.exportEncryptedBackup(target);
  }

  Future<Directory> exportPlaintext({required bool confirmed}) async {
    final target = Directory('${exportsDir.path}/notes-plaintext-${_stamp()}');
    return exporter.exportPlaintext(target, repo, confirmed: confirmed);
  }

  // ------------------------------------------------------------ auto-lock ---

  void onUserActivity() {
    if (_phase == AppPhase.unlocked) _resetAutoLock();
  }

  void onSentToBackground() {
    if (_phase == AppPhase.unlocked && _settings.lockOnBackground) lock();
  }

  void _resetAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    if (_settings.autoLockMinutes <= 0 || _phase != AppPhase.unlocked) return;
    _autoLockTimer =
        Timer(Duration(minutes: _settings.autoLockMinutes), lock);
  }

  // ---------------------------------------------------------------- utils ---

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    super.dispose();
  }
}
