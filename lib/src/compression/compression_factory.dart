// lib/src/compression/compression_factory.dart
//
// HiveVault — Factory that resolves a [CompressionProvider] from config.

import '../core/vault_exceptions.dart';
import 'compression_config.dart';
import 'compression_provider.dart';
import 'gzip_provider.dart';
import 'lz4_provider.dart';
import 'deflate_provider.dart';
import 'auto_provider.dart';
import 'no_compression_provider.dart';

/// Resolves the correct [CompressionProvider] from a [CompressionConfig].
class CompressionFactory {
  const CompressionFactory._();

  static CompressionProvider create(CompressionConfig config) {
    switch (config.strategy) {
      case CompressionStrategy.none:
        return const NoCompressionProvider();

      case CompressionStrategy.gzip:
        return GZipCompressionProvider(level: config.gzipLevel);

      case CompressionStrategy.lz4:
        return const Lz4CompressionProvider();

      case CompressionStrategy.deflate:
        return DeflateCompressionProvider(level: config.gzipLevel);

      case CompressionStrategy.auto:
        return AutoCompressionProvider(
          gzipLevel: config.gzipLevel,
          minSize: config.minimumSizeForCompression,
        );
    }
    // ignore: dead_code
    throw VaultConfigException(
      'Unknown CompressionStrategy: ${config.strategy}',
    );
  }
}
