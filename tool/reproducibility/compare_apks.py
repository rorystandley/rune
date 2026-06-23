#!/usr/bin/env python3
"""Compare two APKs for byte-identity *apart from the signature*.

This is the machine-checkable core of Rune's reproducibility test (ROADMAP #1).
F-Droid rebuilds the app from source and, using apksigcopier, grafts the
developer's signature onto its own rebuild; if the result is byte-identical to
the published, developer-signed APK it ships ours with a "reproducible" badge.
So the property we actually need is: *everything except the signing material is
bit-for-bit identical between two independent builds.*

What counts as "the signature" and is therefore ignored:
  * the v1 (JAR) signature files     META-INF/*.{RSA,DSA,EC,SF} and MANIFEST.MF
  * the v2/v3 APK Signing Block       — it is not a ZIP entry at all (it lives
    between the last entry and the central directory), so an entry-by-entry
    comparison never sees it.

Everything else is compared exactly: the ordered list of entry names, and for
each entry its compression method, CRC-32, compressed size, and the raw
compressed bytes. Comparing the *compressed* bytes (not just the decompressed
content) is deliberate — two builds that decompress to the same content but
deflate it differently are NOT byte-identical and would fail F-Droid's check.

Pure standard library: no third-party deps, deterministic, runs anywhere Python
3.8+ runs. Exit status 0 = identical apart from signature; 1 = a real
difference; 2 = usage / IO error.
"""

from __future__ import annotations

import fnmatch
import struct
import sys
import zipfile

# Entries that are part of the signature and must be ignored in the comparison.
SIGNATURE_GLOBS = (
    "META-INF/*.RSA",
    "META-INF/*.DSA",
    "META-INF/*.EC",
    "META-INF/*.SF",
    "META-INF/MANIFEST.MF",
)


def is_signature(name: str) -> bool:
    return any(fnmatch.fnmatch(name, g) for g in SIGNATURE_GLOBS)


def read_entries(path: str):
    """Return (ordered_names, {name: (method, crc, size, raw_compressed_bytes)}).

    Signature entries are dropped. Raw compressed bytes are read straight from
    the file using each entry's *local* header, which is the authoritative
    location of the data (the central-directory extra field can legitimately
    differ from the local one without affecting byte-identity).
    """
    order: list[str] = []
    entries: dict[str, tuple] = {}
    with open(path, "rb") as fh, zipfile.ZipFile(path) as zf:
        for zi in zf.infolist():
            if zi.is_dir() or is_signature(zi.filename):
                continue
            # Local file header: 30 fixed bytes, then name (len @26), extra (len @28).
            fh.seek(zi.header_offset + 26)
            name_len, extra_len = struct.unpack("<HH", fh.read(4))
            data_start = zi.header_offset + 30 + name_len + extra_len
            fh.seek(data_start)
            raw = fh.read(zi.compress_size)
            order.append(zi.filename)
            entries[zi.filename] = (zi.compress_type, zi.CRC, zi.compress_size, raw)
    return order, entries


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <a.apk> <b.apk>", file=sys.stderr)
        return 2

    a_path, b_path = argv[1], argv[2]
    try:
        a_order, a = read_entries(a_path)
        b_order, b = read_entries(b_path)
    except (OSError, zipfile.BadZipFile) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    diffs: list[str] = []

    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    for n in only_a:
        diffs.append(f"  only in {a_path}: {n}")
    for n in only_b:
        diffs.append(f"  only in {b_path}: {n}")

    for n in sorted(set(a) & set(b)):
        am, acrc, asz, araw = a[n]
        bm, bcrc, bsz, braw = b[n]
        if am != bm:
            diffs.append(f"  {n}: compression {am} != {bm}")
        if acrc != bcrc:
            diffs.append(f"  {n}: CRC {acrc:#010x} != {bcrc:#010x}")
        elif araw != braw:
            # Same CRC (decompresses identically) but different compressed bytes.
            diffs.append(
                f"  {n}: identical content but compressed bytes differ "
                f"({asz} vs {bsz} bytes) — non-reproducible deflate"
            )

    # Entry order matters for byte-identity even when every entry matches.
    if a_order != b_order and not (only_a or only_b):
        diffs.append("  entry order differs between the two APKs")

    if diffs:
        print("DIFFERENT — found differences outside the signature:")
        print("\n".join(diffs))
        print(f"\n{len(diffs)} difference(s). The two builds are NOT reproducible.")
        return 1

    print(
        f"IDENTICAL apart from signature: {len(a)} entries match "
        "(names, order, compression, CRC, and compressed bytes)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
