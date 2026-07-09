import 'dart:convert';

/// Private sentinel so [Note.copyWith] can distinguish "leave [deletedAt] as-is"
/// from "explicitly clear it back to null" (restoring a soft-deleted note).
/// The type is library-private, so callers can't construct — and therefore
/// can't accidentally collide with — this marker.
class _Unchanged {
  const _Unchanged();
}

const _unchanged = _Unchanged();

/// A single note.
///
/// This is *plaintext*. It only ever exists in memory while the vault is
/// unlocked. It is serialized to JSON, encrypted with the vault data key, and
/// only the resulting ciphertext is written to disk.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.deletedAt,
  });

  /// Opaque random identifier (also the on-disk filename). Reveals nothing
  /// about the content.
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When true, the note sorts above unpinned notes in the list. Purely an
  /// organizing hint; it has no effect on encryption or storage layout.
  final bool pinned;

  /// When set, the note is soft-deleted: it lives in "Recently Deleted" and is
  /// hidden from the main list until it is either restored (cleared back to
  /// null) or permanently purged after the retention window. Null for a live
  /// note. Like [pinned], this is metadata only — the note stays encrypted on
  /// disk exactly as before.
  final DateTime? deletedAt;

  /// True while the note sits in Recently Deleted awaiting restore or purge.
  bool get isDeleted => deletedAt != null;

  Note copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    bool? pinned,
    Object? deletedAt = _unchanged,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
        deletedAt: identical(deletedAt, _unchanged)
            ? this.deletedAt
            : deletedAt as DateTime?,
      );

  /// First non-empty line of the body, for list previews.
  String get preview {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  /// Title for display: explicit title, else first body line, else a default.
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final p = preview;
    return p.isNotEmpty ? p : 'New note';
  }

  /// True for a note that has never had content typed into it.
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'pinned': pinned,
        // Only written when soft-deleted, so live notes keep a clean payload.
        if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        pinned: (json['pinned'] as bool?) ?? false,
        deletedAt: (json['deletedAt'] as String?) != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );

  /// UTF-8 JSON bytes — the exact plaintext that gets encrypted.
  List<int> toEncodedBytes() => utf8.encode(jsonEncode(toJson()));

  factory Note.fromEncodedBytes(List<int> bytes) =>
      Note.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
}
