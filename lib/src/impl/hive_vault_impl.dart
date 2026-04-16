// lib/src/impl/hive_vault_impl.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Concrete implementation of SecureStorageInterface.
//
// This class wires all the individual components together:
//   CompressionProvider → BinaryProcessor → EncryptionProvider → Hive Box
//
// It also manages:
//   - In-memory index (InMemoryIndexEngine)
//   - LRU cache (LruCache)
//   - Audit logging (AuditLogger)
//   - Background processing (BackgroundProcessor)
//   - Runtime statistics (VaultStatsCounter)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/vault_config.dart';
import '../core/vault_interface.dart';
import '../core/vault_stats.dart';
import '../core/vault_exceptions.dart';
import '../core/sensitivity_level.dart';
import '../core/constants.dart';
import '../core/compression_config.dart';
import '../compression/compression_provider.dart';
import '../compression/auto_compression_provider.dart';
import '../encryption/encryption_provider.dart';
import '../indexing/index_engine.dart';
import '../indexing/tokenizer.dart';
import '../binary/binary_processor.dart';
import '../binary/payload_info.dart';
import '../cache/lru_cache.dart';
import '../audit/audit_logger.dart';
import '../audit/audit_entry.dart';
import '../background/background_processor.dart';
import 'vault_stats_counter.dart';

/// Full implementation of [SecureStorageInterface] backed by a Hive Box.
///
/// Do not instantiate directly — use [VaultFactory] or
/// `HiveVault.create(boxName: '…', config: VaultConfig.erp())`.
class HiveVaultImpl implements SecureStorageInterface {
  // ─── Dependencies ─────────────────────────────────────────────────────────
  final String boxName;
  final VaultConfig config;
  final CompressionProvider _compressor;
  final EncryptionProvider _encryptor;
  final InMemoryIndexEngine _index;
  final BinaryProcessor _binary;
  final VaultCache _cache;
  final AuditLogger _audit;
  final BackgroundProcessor _bg;
  final VaultStatsCounter _stats = VaultStatsCounter();

  // Hive box — opened during [initialize].
  late Box<Uint8List> _box;
  bool _initialised = false;

  HiveVaultImpl({
    required this.boxName,
    required this.config,
    required CompressionProvider compressor,
    required EncryptionProvider encryptor,
  })  : _compressor = compressor,
        _encryptor = encryptor,
        _index = InMemoryIndexEngine(config.indexing),
        _binary = BinaryProcessor(
          enableIntegrityChecks: config.enableIntegrityChecks,
        ),
        _cache = config.enableMemoryCache && config.memoryCacheSize > 0
            ? LruCache(capacity: config.memoryCacheSize)
            : LruCache(capacity: 1),
        _audit = AuditLogger(),
        _bg = BackgroundProcessor(
          threshold: config.backgroundProcessingThreshold,
          enabled: config.enableBackgroundProcessing,
        );

  // ═══════════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> initialize() async {
    if (_initialised) return;
    try {
      _box = await Hive.openBox<Uint8List>(boxName);
      _initialised = true;
      _stats.openedAt = DateTime.now();

      if (config.indexing.enableAutoIndexing) {
        if (config.indexing.buildIndexInBackground) {
          // Fire-and-forget; index is built asynchronously.
          _rebuildIndexInternal().ignore();
        } else {
          await _rebuildIndexInternal();
        }
      }
    } catch (e) {
      throw VaultInitException(
        'Failed to open Hive box "$boxName"',
        cause: e,
      );
    }
  }

  @override
  Future<void> close() async {
    _requireInitialised();
    _index.clearIndex();
    _cache.clear();
    await _encryptor.dispose();
    await _box.close();
    _initialised = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Core CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> secureSave<T>(
    String key,
    T value, {
    SensitivityLevel? sensitivity,
    String? searchableText,
  }) async {
    _requireInitialised();
    final sw = Stopwatch()..start();

    try {
      final effectiveSensitivity =
          sensitivity ?? config.encryption.defaultSensitivity;

      // 1 — Serialise to raw bytes.
      final rawBytes = BinaryProcessor.objectToBytes(value);
      final originalSize = rawBytes.length;

      // 2 — Determine compression.
      int compressionFlag;
      Uint8List processedBytes;

      if (rawBytes.length >= config.compression.minimumSizeForCompression &&
          _compressor.isWorthCompressing(rawBytes.length)) {
        // Use the actual provider's flag; for Auto, derive it per-size.
        if (_compressor is AutoCompressionProvider) {
          final auto = _compressor as AutoCompressionProvider;
          compressionFlag = auto.headerFlagFor(rawBytes.length);
        } else {
          compressionFlag = _compressor.headerFlag;
        }
        processedBytes = await _bg.compress(rawBytes, _compressor);
      } else {
        compressionFlag = CompressionFlag.none;
        processedBytes = rawBytes;
      }

      final compressedSize = processedBytes.length;

      // 3 — Encrypt.
      int encryptionFlag;
      if (effectiveSensitivity.requiresEncryption) {
        processedBytes = await _encryptor.encrypt(processedBytes);
        encryptionFlag = _encryptor.headerFlag;
      } else {
        encryptionFlag = EncryptionFlag.none;
      }

      final encryptedSize = processedBytes.length;

      // 4 — Frame into binary envelope.
      final payload = await _binary.createPayload(
        data: processedBytes,
        compressionFlag: compressionFlag,
        encryptionFlag: encryptionFlag,
      );

      // 5 — Persist to Hive.
      await _box.put(key, payload);

      // 6 — Update in-memory index.
      if (config.indexing.enableAutoIndexing) {
        final text = searchableText ?? _extractSearchableText(value);
        if (text.isNotEmpty) {
          _index.indexEntry(key, text);
        }
      }

      // 7 — Update cache.
      if (config.enableMemoryCache) {
        _cache.put(key, value);
      }

      // 8 — Update stats & audit.
      sw.stop();
      _stats.recordWrite(
        originalSize: originalSize,
        finalSize: payload.length,
      );
      if (config.enableAuditLog) {
        _audit.log(
          action: AuditAction.save,
          key: key,
          originalSize: originalSize,
          compressedSize: compressedSize,
          encryptedSize: encryptedSize,
          elapsed: sw.elapsed,
        );
      }
    } catch (e) {
      if (config.enableAuditLog) {
        _audit.log(
          action: AuditAction.error,
          key: key,
          details: 'secureSave failed: $e',
        );
      }
      rethrow;
    }
  }

  @override
  Future<T?> secureGet<T>(String key) async {
    _requireInitialised();
    final sw = Stopwatch()..start();

    // 1 — Check cache.
    if (config.enableMemoryCache) {
      final cached = _cache.get(key);
      if (cached != null) {
        sw.stop();
        _stats.recordRead();
        if (config.enableAuditLog) {
          _audit.log(
            action: AuditAction.get,
            key: key,
            fromCache: true,
            elapsed: sw.elapsed,
          );
        }
        return cached as T?;
      }
    }

    // 2 — Load from Hive.
    final payload = _box.get(key);
    if (payload == null) {
      _stats.recordRead();
      return null;
    }

    try {
      // 3 — Parse envelope.
      final info = await _binary.parsePayload(payload);

      // 4 — Decrypt.
      Uint8List bytes = info.data;
      if (info.isEncrypted) {
        bytes = await _encryptor.decrypt(bytes);
      }

      // 5 — Decompress.
      if (info.isCompressed) {
        bytes = await _bg.decompress(bytes, _resolveDecompressor(info));
      }

      // 6 — Deserialise.
      final value = BinaryProcessor.bytesToObject<T>(bytes);

      // 7 — Store in cache.
      if (config.enableMemoryCache) {
        _cache.put(key, value);
      }

      // 8 — Stats & audit.
      sw.stop();
      _stats.recordRead();
      if (config.enableAuditLog) {
        _audit.log(
          action: AuditAction.get,
          key: key,
          fromCache: false,
          elapsed: sw.elapsed,
        );
      }

      return value;
    } catch (e) {
      if (config.enableAuditLog) {
        _audit.log(
          action: AuditAction.error,
          key: key,
          details: 'secureGet failed: $e',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> secureDelete(String key) async {
    _requireInitialised();
    await _box.delete(key);
    _index.removeEntry(key);
    _cache.remove(key);
    if (config.enableAuditLog) {
      _audit.log(action: AuditAction.delete, key: key);
    }
  }

  @override
  Future<bool> secureContains(String key) async {
    _requireInitialised();
    return _box.containsKey(key);
  }

  @override
  Future<List<String>> getAllKeys() async {
    _requireInitialised();
    return _box.keys.cast<String>().toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Batch operations
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> secureSaveBatch(
    Map<String, dynamic> entries, {
    SensitivityLevel? sensitivity,
  }) async {
    _requireInitialised();
    final sw = Stopwatch()..start();

    for (final entry in entries.entries) {
      await secureSave(entry.key, entry.value, sensitivity: sensitivity);
    }

    sw.stop();
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.batchSave,
        key: '(${entries.length} keys)',
        elapsed: sw.elapsed,
        details: 'batch size: ${entries.length}',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> secureGetBatch(List<String> keys) async {
    _requireInitialised();
    final result = <String, dynamic>{};
    await Future.wait(
      keys.map((k) async {
        final v = await secureGet<dynamic>(k);
        if (v != null) result[k] = v;
      }),
    );
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.batchGet,
        key: '(${keys.length} keys)',
        details: 'found: ${result.length}/${keys.length}',
      );
    }
    return result;
  }

  @override
  Future<void> secureDeleteBatch(List<String> keys) async {
    _requireInitialised();
    for (final key in keys) {
      await secureDelete(key);
    }
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.batchDelete,
        key: '(${keys.length} keys)',
        details: 'deleted: ${keys.length}',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Search
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<List<T>> secureSearch<T>(String query) async {
    _requireInitialised();
    _stats.recordSearch();
    final keys = _index.searchAll(query);
    return _fetchByKeys<T>(keys, query, 'AND');
  }

  @override
  Future<List<T>> secureSearchAny<T>(String query) async {
    _requireInitialised();
    _stats.recordSearch();
    final keys = _index.searchAny(query);
    return _fetchByKeys<T>(keys, query, 'OR');
  }

  @override
  Future<List<T>> secureSearchPrefix<T>(String prefix) async {
    _requireInitialised();
    _stats.recordSearch();
    final keys = _index.searchPrefix(prefix);
    return _fetchByKeys<T>(keys, prefix, 'PREFIX');
  }

  @override
  Future<Set<String>> searchKeys(String query) async {
    _requireInitialised();
    return _index.searchAll(query);
  }

  Future<List<T>> _fetchByKeys<T>(
    Set<String> keys,
    String query,
    String mode,
  ) async {
    final results = <T>[];
    for (final key in keys) {
      final value = await secureGet<T>(key);
      if (value != null) results.add(value);
    }
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.search,
        key: query,
        details: '$mode search → ${results.length} results',
      );
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Maintenance
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> rebuildIndex() async {
    _requireInitialised();
    await _rebuildIndexInternal();
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.rebuildIndex,
        key: boxName,
        details: 'indexed ${_index.indexedCount} entries',
      );
    }
  }

  Future<void> _rebuildIndexInternal() async {
    _index.clearIndex();
    for (final rawKey in _box.keys) {
      final key = rawKey as String;
      try {
        final value = await secureGet<dynamic>(key);
        if (value != null) {
          final text = _extractSearchableText(value);
          if (text.isNotEmpty) {
            _index.indexEntry(key, text);
          }
        }
      } catch (_) {
        // Skip corrupt entries during index rebuild.
      }
    }
  }

  @override
  Future<void> compact() async {
    _requireInitialised();
    await _box.compact();
    if (config.enableAuditLog) {
      _audit.log(action: AuditAction.compact, key: boxName);
    }
  }

  @override
  void clearCache() {
    _cache.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Import / Export
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<Uint8List> exportEncrypted() async {
    _requireInitialised();
    final sw = Stopwatch()..start();

    final exportMap = <String, String>{};
    for (final rawKey in _box.keys) {
      final key = rawKey as String;
      final payload = _box.get(key);
      if (payload != null) {
        exportMap[key] = base64.encode(payload);
      }
    }

    final jsonBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(exportMap)),
    );

    // Re-encrypt the export with the same encryptor.
    final encrypted = await _encryptor.encrypt(jsonBytes);

    sw.stop();
    if (config.enableAuditLog) {
      _audit.log(
        action: AuditAction.exportData,
        key: boxName,
        originalSize: jsonBytes.length,
        encryptedSize: encrypted.length,
        elapsed: sw.elapsed,
        details: 'exported ${exportMap.length} entries',
      );
    }

    return encrypted;
  }

  @override
  Future<void> importEncrypted(Uint8List data) async {
    _requireInitialised();
    final sw = Stopwatch()..start();

    try {
      final jsonBytes = await _encryptor.decrypt(data);
      final jsonStr = utf8.decode(jsonBytes);
      final Map<String, dynamic> importMap = jsonDecode(jsonStr);

      for (final entry in importMap.entries) {
        final payload =
            Uint8List.fromList(base64.decode(entry.value as String));
        await _box.put(entry.key, payload);
      }

      // Rebuild index after import.
      await _rebuildIndexInternal();
      // Clear cache — imported data may differ from cached.
      _cache.clear();

      sw.stop();
      if (config.enableAuditLog) {
        _audit.log(
          action: AuditAction.importData,
          key: boxName,
          elapsed: sw.elapsed,
          details: 'imported ${importMap.length} entries',
        );
      }
    } catch (e) {
      throw VaultImportException(
        'Failed to import encrypted archive',
        cause: e,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<VaultStats> getStats() async {
    _requireInitialised();
    final indexStats = _index.getStats();
    return VaultStats(
      boxName: boxName,
      totalEntries: _box.length,
      cacheSize: _cache.length,
      cacheCapacity: config.memoryCacheSize,
      cacheHitRatio: _cache.hitRatio,
      compressionAlgorithm: _compressor.algorithmName,
      encryptionAlgorithm: _encryptor.algorithmName,
      indexStats: indexStats,
      totalBytesSaved: _stats.totalBytesSaved,
      totalBytesWritten: _stats.totalBytesWritten,
      totalWrites: _stats.totalWrites,
      totalReads: _stats.totalReads,
      totalSearches: _stats.totalSearches,
      openedAt: _stats.openedAt,
    );
  }

  @override
  List<AuditEntry> getAuditLog({int limit = 50}) =>
      _audit.getRecent(count: limit);

  /// Returns the full audit logger (for export or advanced queries).
  AuditLogger get auditLogger => _audit;

  // ═══════════════════════════════════════════════════════════════════════════
  //  Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  void _requireInitialised() {
    if (!_initialised) {
      throw VaultInitException(
        'HiveVault "$boxName" has not been initialised. '
        'Call initialize() before any other method.',
      );
    }
  }

  /// Resolves the correct decompression provider from the payload's flag.
  CompressionProvider _resolveDecompressor(PayloadInfo info) {
    // The AutoCompressionProvider detects algorithm from magic bytes internally.
    if (_compressor is AutoCompressionProvider) return _compressor;

    // For non-auto providers, the stored flag determines the decompressor.
    // We use the same provider if flags match, otherwise fall back to Auto.
    if (info.compressionFlag == _compressor.headerFlag) return _compressor;

    // Flag mismatch — use Auto which detects via magic bytes.
    return AutoCompressionProvider();
  }

  /// Extracts searchable text from any value type.
  String _extractSearchableText(dynamic value) {
    if (value is String) return value;
    if (value is Map<String, dynamic>) {
      return extractSearchableText(
        value,
        allowedFields: config.indexing.indexableFields,
      );
    }
    if (value is Map) {
      // Generic map — convert to string
      return value.values.whereType<String>().join(' ');
    }
    return '';
  }
}
