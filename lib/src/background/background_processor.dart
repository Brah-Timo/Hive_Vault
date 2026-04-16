// lib/src/background/background_processor.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Background processing via Flutter compute / Dart isolates.
// ─────────────────────────────────────────────────────────────────────────────
//
// Encryption and compression are CPU-bound. For payloads larger than the
// configured threshold they are offloaded to a background isolate so the
// Flutter UI thread is not blocked.
//
// Note: Dart isolates cannot share objects — all data must be serialised
// (typically as Uint8List) before being sent and received via the isolate
// message port. The `compute` function from flutter/foundation.dart handles
// this transparently.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import '../compression/compression_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Message types for isolate communication
// ─────────────────────────────────────────────────────────────────────────────

class _CompressMessage {
  final Uint8List data;
  final CompressionProvider provider;
  const _CompressMessage(this.data, this.provider);
}

class _DecompressMessage {
  final Uint8List data;
  final CompressionProvider provider;
  const _DecompressMessage(this.data, this.provider);
}

// Top-level functions required by compute() — must not be closures.
Uint8List _compressInIsolate(_CompressMessage msg) =>
    msg.provider.compress(msg.data);

Uint8List _decompressInIsolate(_DecompressMessage msg) =>
    msg.provider.decompress(msg.data);

// ─────────────────────────────────────────────────────────────────────────────

/// Decides whether to run compression in the background based on data size.
///
/// For data smaller than [threshold] bytes the operation runs synchronously
/// on the calling isolate (no overhead). For larger data it is offloaded via
/// Flutter's [compute] function.
class BackgroundProcessor {
  /// Byte threshold above which work is offloaded to a background isolate.
  final int threshold;

  /// Whether background processing is globally enabled.
  final bool enabled;

  const BackgroundProcessor({
    this.threshold = 65536, // 64 KB
    this.enabled = true,
  });

  // ─── Compression ──────────────────────────────────────────────────────────

  /// Compresses [data] using [provider], offloading to a background isolate
  /// when data size exceeds [threshold] and [enabled] is `true`.
  Future<Uint8List> compress(
    Uint8List data,
    CompressionProvider provider,
  ) async {
    if (!enabled || data.length < threshold) {
      return provider.compress(data);
    }
    return compute(_compressInIsolate, _CompressMessage(data, provider));
  }

  /// Decompresses [data] using [provider], offloading when appropriate.
  Future<Uint8List> decompress(
    Uint8List data,
    CompressionProvider provider,
  ) async {
    if (!enabled || data.length < threshold) {
      return provider.decompress(data);
    }
    return compute(_decompressInIsolate, _DecompressMessage(data, provider));
  }

  // ─── Utility ──────────────────────────────────────────────────────────────

  /// Returns `true` if a payload of [sizeBytes] would be processed in the
  /// background.
  bool wouldUseBackground(int sizeBytes) => enabled && sizeBytes >= threshold;
}
