// Helpers to keep secrets out of any logs.
//
// The notes_core library performs NO logging of its own — it never prints
// passphrases, keys, or note content (verified by test). These helpers are for
// the UI layer, which may emit non-sensitive diagnostics, so that anything
// derived from secrets is masked before it can reach a log sink.

/// Masks all but a short prefix of an opaque id. Note ids are random and reveal
/// nothing about content, but we still avoid logging them in full.
String maskId(String id, {int keep = 4}) {
  if (id.length <= keep) return '*' * id.length;
  return '${id.substring(0, keep)}…';
}

/// Always returns a fixed mask. Use around any value that might be secret.
String redact(Object? _) => '«redacted»';
