import 'dart:convert';

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
  });

  /// Opaque random identifier (also the on-disk filename). Reveals nothing
  /// about the content.
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
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
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  /// UTF-8 JSON bytes — the exact plaintext that gets encrypted.
  List<int> toEncodedBytes() => utf8.encode(jsonEncode(toJson()));

  factory Note.fromEncodedBytes(List<int> bytes) =>
      Note.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
}
