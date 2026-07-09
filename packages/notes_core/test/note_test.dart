import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2024, 1, 1, 12);
  final updatedAt = DateTime.utc(2024, 1, 2, 9, 30);

  Note sample({bool pinned = false}) => Note(
        id: 'abc123',
        title: 'Title',
        body: 'Body',
        createdAt: createdAt,
        updatedAt: updatedAt,
        pinned: pinned,
      );

  test('defaults to unpinned', () {
    expect(sample().pinned, isFalse);
  });

  test('pinned survives a JSON round-trip', () {
    final restored = Note.fromJson(sample(pinned: true).toJson());
    expect(restored.pinned, isTrue);
    expect(restored.id, 'abc123');
    expect(restored.updatedAt, updatedAt);
  });

  test('pinned survives an encoded-bytes round-trip', () {
    final restored = Note.fromEncodedBytes(sample(pinned: true).toEncodedBytes());
    expect(restored.pinned, isTrue);
  });

  test('legacy JSON without a pinned field decodes as unpinned', () {
    final legacy = {
      'id': 'abc123',
      'title': 'Title',
      'body': 'Body',
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
    expect(Note.fromJson(legacy).pinned, isFalse);
  });

  test('copyWith toggles pinned without touching other fields', () {
    final pinned = sample().copyWith(pinned: true);
    expect(pinned.pinned, isTrue);
    expect(pinned.title, 'Title');
    expect(pinned.body, 'Body');
    expect(pinned.updatedAt, updatedAt);

    // Omitting pinned preserves the existing value.
    expect(pinned.copyWith(title: 'New').pinned, isTrue);
  });
}
