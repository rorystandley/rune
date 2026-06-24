import 'dart:io';
import 'dart:typed_data';

const int _riff = 0x46464952; // RIFF
const int _wave = 0x45564157; // WAVE
const int _fmt = 0x20746d66; // fmt[space]
const int _data = 0x61746164; // data
const int _pcmFormat = 1;

/// Decodes a 16 kHz mono PCM16 WAV file into normalized float samples.
Float32List decodePcm16MonoWavFile(String path) =>
    decodePcm16MonoWav(File(path).readAsBytesSync());

/// Decodes 16 kHz mono PCM16 WAV bytes into normalized samples in [-1, 1].
///
/// The recorder is configured to produce this exact format so whisper.cpp can
/// consume the samples without resampling.
Float32List decodePcm16MonoWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      data.getUint32(0, Endian.little) != _riff ||
      data.getUint32(8, Endian.little) != _wave) {
    throw const FormatException('Expected a RIFF/WAVE file.');
  }

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? byteRate;
  int? blockAlign;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = data.getUint32(offset, Endian.little);
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkDataOffset = offset + 8;
    final nextOffset = chunkDataOffset + chunkSize + chunkSize.remainder(2);
    if (chunkDataOffset + chunkSize > bytes.length) {
      throw const FormatException(
          'WAV chunk extends past the end of the file.');
    }

    if (chunkId == _fmt) {
      if (chunkSize < 16) {
        throw const FormatException('WAV fmt chunk is too short.');
      }
      audioFormat = data.getUint16(chunkDataOffset, Endian.little);
      channels = data.getUint16(chunkDataOffset + 2, Endian.little);
      sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
      byteRate = data.getUint32(chunkDataOffset + 8, Endian.little);
      blockAlign = data.getUint16(chunkDataOffset + 12, Endian.little);
      bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
    } else if (chunkId == _data) {
      dataOffset = chunkDataOffset;
      dataLength = chunkSize;
    }

    offset = nextOffset;
  }

  if (audioFormat != _pcmFormat) {
    throw FormatException('Expected PCM WAV format, got $audioFormat.');
  }
  if (channels != 1) {
    throw FormatException('Expected mono WAV audio, got $channels channels.');
  }
  if (sampleRate != 16000) {
    throw FormatException('Expected 16 kHz WAV audio, got $sampleRate Hz.');
  }
  if (bitsPerSample != 16) {
    throw FormatException('Expected PCM16 WAV audio, got $bitsPerSample bits.');
  }
  if (blockAlign != 2 || byteRate != 32000) {
    throw FormatException(
      'Expected mono PCM16 block alignment, got blockAlign=$blockAlign, '
      'byteRate=$byteRate.',
    );
  }
  if (dataOffset == null || dataLength == null) {
    throw const FormatException('WAV file is missing a data chunk.');
  }
  if (!dataLength.isEven) {
    throw const FormatException('PCM16 data chunk has an odd byte length.');
  }

  final sampleCount = dataLength ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    final sample = data.getInt16(dataOffset + i * 2, Endian.little);
    samples[i] = sample / 32768.0;
  }
  return samples;
}
