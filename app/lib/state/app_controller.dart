import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notes_core/notes_core.dart';

import '../platform/audio_recorder.dart';
import '../platform/biometric_unlock_store.dart';
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
    BiometricUnlockStore? biometricUnlockStore,
    CryptoService? crypto,
    this.createKdfParams, // test seam: cheap params in tests, null = production
  }) : biometricUnlockStore =
           biometricUnlockStore ?? const DisabledBiometricUnlockStore(),
       store = FileVaultStore(vaultDir) {
    final c = crypto ?? CryptoService();
    vault = VaultService(store: store, crypto: c);
    repo = NotesRepository(vault: vault, store: store);
    exporter = ExportService(store: store);
  }

  final Directory vaultDir;
  final Directory audioTempDir;
  final Directory exportsDir;
  final SettingsStore settingsStore;
  /// On-device transcription engine, or `null` when this platform has no
  /// bundled engine (voice notes are then disabled rather than stubbed).
  final TranscriptionService? transcription;
  final AudioRecorderPort recorder;
  final BiometricUnlockStore biometricUnlockStore;
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
  String? _biometricUnlockError;
  BiometricUnlockAvailability _biometricUnlockAvailability =
      const BiometricUnlockAvailability.unavailable(
        'Checking biometric unlock support.',
      );
  bool _biometricUnlockReady = false;
  bool _busy = false;
  Timer? _autoLockTimer;

  AppPhase get phase => _phase;
  AppSettings get settings => _settings;
  String get search => _search;
  String? get selectedId => _selectedId;
  String? get unlockError => _unlockError;
  String? get biometricUnlockError => _biometricUnlockError;
  BiometricUnlockAvailability get biometricUnlockAvailability =>
      _biometricUnlockAvailability;
  String get biometricUnlockLabel => _biometricUnlockAvailability.label;
  bool get biometricUnlockAvailable => _biometricUnlockAvailability.isAvailable;
  bool get biometricUnlockReady => _biometricUnlockReady;
  bool get canUnlockWithBiometric =>
      _phase == AppPhase.locked && _biometricUnlockReady && !_busy;
  bool get busy => _busy;
  String get vaultLocation => store.description;

  List<Note> get visibleNotes => repo.search(_search);
  Note? get selectedNote =>
      _selectedId == null ? null : repo.getNote(_selectedId!);

  /// Loads settings and decides the initial phase: locked if a vault exists,
  /// otherwise the create-vault flow.
  Future<void> init() async {
    _settings = await settingsStore.load();
    final exists = await vault.vaultExists();
    _phase = exists ? AppPhase.locked : AppPhase.needsCreation;
    await _refreshBiometricUnlockState(vaultExists: exists, notify: false);
    notifyListeners();
  }

  // ---------------------------------------------------------------- vault ---

  Future<void> createVault(String passphrase) async {
    _setBusy(true);
    try {
      await vault.createVault(passphrase, kdfParams: createKdfParams);
      await repo.loadAll();
      await _disableBiometricUnlock(saveSettings: true);
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
    _biometricUnlockError = null;
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

  Future<void> changePassphrase(String current, String next) async {
    await vault.changePassphrase(current, next);
    await _refreshCachedDekAfterVaultHeaderChange();
  }

  Future<bool> enableBiometricUnlock() async {
    _setBusy(true);
    _biometricUnlockError = null;
    try {
      final availability = await biometricUnlockStore.checkAvailability();
      _biometricUnlockAvailability = availability;
      if (!availability.isAvailable) {
        _biometricUnlockError =
            availability.reason ?? 'Biometric unlock is not available.';
        notifyListeners();
        return false;
      }

      final binding = await _currentVaultBinding();
      if (binding == null || !vault.isUnlocked) {
        _biometricUnlockError =
            'Unlock with your passphrase before enabling biometric unlock.';
        notifyListeners();
        return false;
      }

      final dek = vault.exportDekForPlatformUnlockCache();
      try {
        await biometricUnlockStore.saveCachedDek(
          vaultBinding: binding,
          dek: dek,
        );
      } finally {
        _zero(dek);
      }

      _settings = _settings.copyWith(
        biometricUnlockEnabled: true,
        biometricUnlockVaultBinding: binding,
      );
      await settingsStore.save(_settings);
      _biometricUnlockReady = true;
      notifyListeners();
      return true;
    } catch (_) {
      _biometricUnlockError =
          'Biometric unlock could not be enabled on this device.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disableBiometricUnlock() =>
      _disableBiometricUnlock(saveSettings: true);

  Future<bool> unlockWithBiometric() async {
    _setBusy(true);
    _unlockError = null;
    _biometricUnlockError = null;
    try {
      final binding = await _currentVaultBinding();
      if (binding == null ||
          !_settings.biometricUnlockEnabled ||
          _settings.biometricUnlockVaultBinding != binding) {
        _unlockError = 'Biometric unlock needs to be set up again.';
        await _disableBiometricUnlock(saveSettings: true);
        notifyListeners();
        return false;
      }

      final cachedDek = await biometricUnlockStore.readCachedDek(
        vaultBinding: binding,
      );
      if (cachedDek == null) {
        _unlockError = 'Biometric unlock needs to be set up again.';
        await _disableBiometricUnlock(saveSettings: true);
        notifyListeners();
        return false;
      }

      try {
        await vault.unlockWithPlatformCachedDek(cachedDek);
        await repo.loadAll();
      } catch (_) {
        vault.lock();
        repo.clear();
        _unlockError =
            'Biometric unlock could not open this vault. Use your passphrase.';
        await _disableBiometricUnlock(saveSettings: true);
        notifyListeners();
        return false;
      } finally {
        _zero(cachedDek);
      }

      _enterUnlocked();
      return true;
    } catch (_) {
      _unlockError = 'Biometric unlock failed. Use your passphrase.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ---------------------------------------------------------------- notes ---

  Future<Note> newNote() async {
    final note = await repo.createNote();
    _selectedId = note.id;
    notifyListeners();
    return note;
  }

  /// Autosave entry point from the editor. No-op if nothing changed.
  Future<void> saveNote(
    String id, {
    required String title,
    required String body,
  }) async {
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

  /// Toggles the pinned state of a note, moving it into or out of the pinned
  /// section at the top of the list. No-op if the note no longer exists.
  Future<void> togglePinned(String id) async {
    final note = repo.getNote(id);
    if (note == null) return;
    await repo.setPinned(id, !note.pinned);
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

  Future<void> refreshBiometricUnlockState() => _refreshBiometricUnlockState();

  // --------------------------------------------------------------- export ---

  Future<File> exportEncryptedBackup() async {
    final target = File('${exportsDir.path}/notes-backup-${_stamp()}.notesbak');
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
    _autoLockTimer = Timer(Duration(minutes: _settings.autoLockMinutes), lock);
  }

  // ---------------------------------------------------------------- utils ---

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  Future<void> _refreshBiometricUnlockState({
    bool notify = true,
    bool? vaultExists,
  }) async {
    _biometricUnlockAvailability = await biometricUnlockStore
        .checkAvailability();
    final exists = vaultExists ?? await vault.vaultExists();
    final binding = exists ? await _currentVaultBinding() : null;
    _biometricUnlockReady =
        _settings.biometricUnlockEnabled &&
        _biometricUnlockAvailability.isAvailable &&
        binding != null &&
        _settings.biometricUnlockVaultBinding == binding;
    if (notify) notifyListeners();
  }

  Future<void> _disableBiometricUnlock({required bool saveSettings}) async {
    await biometricUnlockStore.clearCachedDek();
    _settings = _settings.copyWith(
      biometricUnlockEnabled: false,
      biometricUnlockVaultBinding: null,
    );
    _biometricUnlockReady = false;
    if (saveSettings) await settingsStore.save(_settings);
    notifyListeners();
  }

  Future<void> _refreshCachedDekAfterVaultHeaderChange() async {
    if (!_settings.biometricUnlockEnabled) {
      await _refreshBiometricUnlockState();
      return;
    }

    final binding = await _currentVaultBinding();
    if (binding == null || !vault.isUnlocked) {
      await _disableBiometricUnlock(saveSettings: true);
      return;
    }

    final dek = vault.exportDekForPlatformUnlockCache();
    try {
      await biometricUnlockStore.saveCachedDek(vaultBinding: binding, dek: dek);
      _settings = _settings.copyWith(biometricUnlockVaultBinding: binding);
      await settingsStore.save(_settings);
      await _refreshBiometricUnlockState();
    } catch (_) {
      _biometricUnlockError =
          'Biometric unlock was disabled after the passphrase change.';
      await _disableBiometricUnlock(saveSettings: true);
    } finally {
      _zero(dek);
    }
  }

  Future<String?> _currentVaultBinding() async {
    if (!await vault.vaultExists()) return null;
    final meta = await store.readMetadata();
    return _vaultBinding(meta);
  }

  String _vaultBinding(VaultMetadata meta) {
    final kdf = meta.kdfParams;
    return [
      VaultMetadata.formatId,
      meta.version,
      meta.createdAt.toUtc().toIso8601String(),
      meta.cipher.id,
      kdf.memoryKiB,
      kdf.iterations,
      kdf.parallelism,
      base64UrlEncode(kdf.salt),
      base64UrlEncode(meta.wrappedKey),
    ].join('|');
  }

  void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    final transcription = this.transcription;
    if (transcription is DisposableTranscriptionService) {
      (transcription as DisposableTranscriptionService).dispose();
    }
    super.dispose();
  }
}
