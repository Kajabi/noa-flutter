import 'dart:typed_data';
import 'package:noa/util/bytes_to_wav.dart';

/// Accumulates raw PCM bytes from BLE audio stream.
/// When buffer reaches threshold (5 seconds at 8kHz/8-bit = 40000 bytes),
/// converts to WAV and fires callback.
class AudioBuffer {
  int _chunkThreshold;
  final int _sampleRate;
  final int _bitDepth;
  final void Function(Uint8List wavData) onChunkReady;
  final List<int> _buffer = [];

  AudioBuffer({
    int chunkDurationSeconds = 5,
    int sampleRate = 8000,
    int bitDepth = 8,
    required this.onChunkReady,
  })  : _sampleRate = sampleRate,
        _bitDepth = bitDepth,
        _chunkThreshold = chunkDurationSeconds * sampleRate * (bitDepth ~/ 8);

  void updateChunkDuration(int seconds) {
    _chunkThreshold = seconds * _sampleRate * (_bitDepth ~/ 8);
  }

  void addData(Uint8List data) {
    _buffer.addAll(data);
    if (_buffer.length >= _chunkThreshold) {
      _flush();
    }
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    final pcmBytes = Uint8List.fromList(_buffer);
    _buffer.clear();
    final wavData = bytesToWav(pcmBytes, 8, 8000);
    onChunkReady(wavData);
  }

  /// Force flush any remaining audio data.
  void flush() {
    if (_buffer.isNotEmpty) {
      _flush();
    }
  }

  void clear() {
    _buffer.clear();
  }
}
