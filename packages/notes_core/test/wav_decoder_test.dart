import 'dart:convert';
import 'dart:typed_data';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  test('decodes 16 kHz mono PCM16 samples to normalized floats', () {
    final decoded = decodePcm16MonoWav(_wav([
      -32768,
      -16384,
      0,
      16384,
      32767,
    ]));

    expect(decoded, hasLength(5));
    expect(decoded[0], -1.0);
    expect(decoded[1], -0.5);
    expect(decoded[2], 0.0);
    expect(decoded[3], 0.5);
    expect(decoded[4], closeTo(32767 / 32768, 0.000001));
  });

  test('skips unknown chunks including RIFF padding bytes', () {
    final decoded = decodePcm16MonoWav(_wav([1024], includeOddJunk: true));

    expect(decoded, hasLength(1));
    expect(decoded.single, closeTo(1024 / 32768, 0.000001));
  });

  test('decodes WAVE_FORMAT_EXTENSIBLE recordings (macOS record output)', () {
    final decoded = decodePcm16MonoWav(_wav([0, 16384], extensible: true));

    expect(decoded, hasLength(2));
    expect(decoded[0], 0.0);
    expect(decoded[1], 0.5);
  });

  test('rejects audio that does not match the recorder format', () {
    expect(
      () => decodePcm16MonoWav(_wav([0], sampleRate: 8000)),
      throwsFormatException,
    );
  });
}

Uint8List _wav(
  List<int> samples, {
  int sampleRate = 16000,
  bool includeOddJunk = false,
  bool extensible = false,
}) {
  final bytes = BytesBuilder();

  void addAscii(String value) => bytes.add(ascii.encode(value));

  void addUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void addUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void addInt16(int value) {
    final data = ByteData(2)..setInt16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  final junkSize = includeOddJunk ? 2 + 8 : 0;
  final fmtBodySize = extensible ? 40 : 16;
  final dataSize = samples.length * 2;
  final riffSize = 4 + junkSize + (8 + fmtBodySize) + 8 + dataSize;

  addAscii('RIFF');
  addUint32(riffSize);
  addAscii('WAVE');

  if (includeOddJunk) {
    addAscii('JUNK');
    addUint32(1);
    bytes.addByte(0x7f);
    bytes.addByte(0);
  }

  addAscii('fmt ');
  addUint32(fmtBodySize);
  addUint16(extensible ? 0xFFFE : 1); // WAVE_FORMAT_EXTENSIBLE or PCM
  addUint16(1); // mono
  addUint32(sampleRate);
  addUint32(sampleRate * 2);
  addUint16(2);
  addUint16(16);
  if (extensible) {
    addUint16(22); // cbSize
    addUint16(16); // wValidBitsPerSample
    addUint32(0); // dwChannelMask
    // KSDATAFORMAT_SUBTYPE_PCM: {00000001-0000-0010-8000-00AA00389B71}
    bytes.add(Uint8List.fromList(const [
      0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, //
      0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
    ]));
  }

  addAscii('data');
  addUint32(dataSize);
  for (final sample in samples) {
    addInt16(sample);
  }

  return bytes.takeBytes();
}
