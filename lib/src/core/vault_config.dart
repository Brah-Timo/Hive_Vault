// lib/src/core/vault_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Master configuration that aggregates all sub-configurations.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:meta/meta.dart';
import 'compression_config.dart';
import 'encryption_config.dart';
import 'indexing_config.dart';
import 'sensitivity_level.dart';
import '../core/constants.dart';

/// Top-level immutable configuration object for a [HiveVault] instance.
///
/// Aggregates [CompressionConfig], [EncryptionConfig], and [IndexingConfig]
/// alongside vault-level settings such as audit logging and memory cache.
///
/// Use one of the named constructors for common presets or provide a fully
/// custom configuration via the default constructor.
@immutable
class VaultConfig {
  // ─── Sub-configurations ──────────────────────────────────────────────────

  /// Compression settings.
  final CompressionConfig compression;

  /// Encryption settings.
  final EncryptionConfig encryption;

  /// In-memory index settings.
  final IndexingConfig indexing;

  // ─── Vault-level settings ────────────────────────────────────────────────

  /// When `true` every significant vault operation is recorded in the
  /// [AuditLogger], which can be retrieved via [HiveVault.getAuditLog].
  final bool enableAuditLog;

  /// When `true` the binary payload carries a SHA-256 checksum and the
  /// checksum is verified on every read. Adds ~0.1 ms per read.
  final bool enableIntegrityChecks;

  /// When `true` and data size > [backgroundProcessingThreshold], the
  /// compression + encryption pipeline is offloaded to a Dart isolate.
  final bool enableBackgroundProcessing;

  /// Size threshold (bytes) above which background isolate processing
  /// is triggered (when [enableBackgroundProcessing] is `true`).
  final int backgroundProcessingThreshold;

  /// Maximum number of decrypted entries held in the LRU memory cache.
  /// Set to 0 to disable caching.
  final int memoryCacheSize;

  /// Enables the LRU in-memory cache for recently accessed entries.
  final bool enableMemoryCache;

  const VaultConfig({
    this.compression = const CompressionConfig(),
    this.encryption = const EncryptionConfig(),
    this.indexing = const IndexingConfig(),
    this.enableAuditLog = true,
    this.enableIntegrityChecks = true,
    this.enableBackgroundProcessing = true,
    this.backgroundProcessingThreshold = kDefaultIsolateThreshold,
    this.memoryCacheSize = kDefaultCacheSize,
    this.enableMemoryCache = true,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  Named preset constructors
  // ═══════════════════════════════════════════════════════════════════════════

  /// Preset for full-featured ERP / commercial management applications.
  ///
  /// - GZip level-6 compression
  /// - AES-256-GCM with integrity check
  /// - Full indexing with prefix search
  /// - Audit log enabled
  factory VaultConfig.erp() {
    return const VaultConfig(
      compression: CompressionConfig(
        strategy: CompressionStrategy.gzip,
        gzipLevel: 6,
        minimumSizeForCompression: 128,
      ),
      encryption: EncryptionConfig(
        defaultSensitivity: SensitivityLevel.high,
        pbkdf2Iterations: 100000,
        enableIntegrityCheck: true,
      ),
      indexing: IndexingConfig(
        enableAutoIndexing: true,
        minimumTokenLength: 2,
        enablePrefixSearch: true,
        buildIndexInBackground: true,
      ),
      enableAuditLog: true,
      enableIntegrityChecks: true,
      memoryCacheSize: 200,
    );
  }

  /// Preset optimised for resource-constrained devices.
  ///
  /// - Lz4 compression (faster, smaller memory footprint)
  /// - AES-256-CBC (no GCM overhead)
  /// - Indexing disabled (saves RAM)
  /// - Audit log disabled
  factory VaultConfig.light() {
    return const VaultConfig(
      compression: CompressionConfig(
        strategy: CompressionStrategy.lz4,
        minimumSizeForCompression: 256,
      ),
      encryption: EncryptionConfig(
        defaultSensitivity: SensitivityLevel.standard,
        pbkdf2Iterations: 50000,
        enableIntegrityCheck: false,
      ),
      indexing: IndexingConfig.disabled(),
      enableAuditLog: false,
      enableIntegrityChecks: false,
      enableBackgroundProcessing: false,
      memoryCacheSize: 30,
    );
  }

  /// Preset for development and testing — no encryption, no compression.
  ///
  /// ⚠️  Never use this in production. Data is stored in plaintext.
  factory VaultConfig.debug() {
    return const VaultConfig(
      compression: CompressionConfig.disabled(),
      encryption: EncryptionConfig.disabled(),
      indexing: IndexingConfig.full(),
      enableAuditLog: true,
      enableIntegrityChecks: false,
      memoryCacheSize: 50,
    );
  }

  /// Maximum security preset.
  ///
  /// - GZip level-9
  /// - AES-256-GCM with 200k PBKDF2 iterations
  /// - Integrity check + key rotation enabled
  factory VaultConfig.maxSecurity() {
    return const VaultConfig(
      compression: CompressionConfig(
        strategy: CompressionStrategy.gzip,
        gzipLevel: 9,
        minimumSizeForCompression: 32,
      ),
      encryption: EncryptionConfig.maxSecurity(),
      indexing: IndexingConfig.full(),
      enableAuditLog: true,
      enableIntegrityChecks: true,
      memoryCacheSize: 50,
    );
  }

  /// Maximum performance preset — Lz4, no encryption, full index, large cache.
  factory VaultConfig.maxPerformance() {
    return const VaultConfig(
      compression: CompressionConfig.bestSpeed(),
      encryption: EncryptionConfig.disabled(),
      indexing: IndexingConfig.full(),
      enableAuditLog: false,
      enableIntegrityChecks: false,
      memoryCacheSize: 500,
    );
  }

  // ─── Equality & copy ─────────────────────────────────────────────────────

  VaultConfig copyWith({
    CompressionConfig? compression,
    EncryptionConfig? encryption,
    IndexingConfig? indexing,
    bool? enableAuditLog,
    bool? enableIntegrityChecks,
    bool? enableBackgroundProcessing,
    int? backgroundProcessingThreshold,
    int? memoryCacheSize,
    bool? enableMemoryCache,
  }) {
    return VaultConfig(
      compression: compression ?? this.compression,
      encryption: encryption ?? this.encryption,
      indexing: indexing ?? this.indexing,
      enableAuditLog: enableAuditLog ?? this.enableAuditLog,
      enableIntegrityChecks:
          enableIntegrityChecks ?? this.enableIntegrityChecks,
      enableBackgroundProcessing:
          enableBackgroundProcessing ?? this.enableBackgroundProcessing,
      backgroundProcessingThreshold:
          backgroundProcessingThreshold ?? this.backgroundProcessingThreshold,
      memoryCacheSize: memoryCacheSize ?? this.memoryCacheSize,
      enableMemoryCache: enableMemoryCache ?? this.enableMemoryCache,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultConfig &&
          compression == other.compression &&
          encryption == other.encryption &&
          indexing == other.indexing &&
          enableAuditLog == other.enableAuditLog &&
          enableIntegrityChecks == other.enableIntegrityChecks &&
          enableBackgroundProcessing == other.enableBackgroundProcessing &&
          memoryCacheSize == other.memoryCacheSize &&
          enableMemoryCache == other.enableMemoryCache;

  @override
  int get hashCode => Object.hash(
        compression,
        encryption,
        indexing,
        enableAuditLog,
        enableIntegrityChecks,
        enableBackgroundProcessing,
        memoryCacheSize,
        enableMemoryCache,
      );

  @override
  String toString() => 'VaultConfig(\n'
      '  compression: $compression\n'
      '  encryption:  $encryption\n'
      '  indexing:    $indexing\n'
      '  auditLog:    $enableAuditLog\n'
      '  integrity:   $enableIntegrityChecks\n'
      '  cache:       ${enableMemoryCache ? memoryCacheSize : "disabled"}\n'
      ')';
}
