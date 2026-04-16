// lib/hive_vault.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Public API barrel file.
// Import this single file to use the entire HiveVault library.
// ─────────────────────────────────────────────────────────────────────────────
library hive_vault;

// ── Core ─────────────────────────────────────────────────────────────────────
export 'src/core/constants.dart';
export 'src/core/sensitivity_level.dart';
export 'src/core/compression_config.dart';
export 'src/core/encryption_config.dart';
export 'src/core/indexing_config.dart';
export 'src/core/vault_config.dart';
export 'src/core/vault_interface.dart';
export 'src/core/vault_exceptions.dart';
export 'src/core/vault_stats.dart';

// ── Compression ───────────────────────────────────────────────────────────────
export 'src/compression/compression_provider.dart';
export 'src/compression/gzip_provider.dart';
export 'src/compression/lz4_provider.dart';
export 'src/compression/deflate_provider.dart';
export 'src/compression/no_compression_provider.dart';
export 'src/compression/auto_compression_provider.dart';

// ── Encryption ────────────────────────────────────────────────────────────────
export 'src/encryption/encryption_provider.dart';
export 'src/encryption/aes_gcm_provider.dart';
export 'src/encryption/aes_cbc_provider.dart';
export 'src/encryption/no_encryption_provider.dart';
export 'src/encryption/key_manager.dart';
export 'src/encryption/key_rotation_scheduler.dart';

// ── Indexing ──────────────────────────────────────────────────────────────────
export 'src/indexing/tokenizer.dart';
export 'src/indexing/index_engine.dart';

// ── Binary ────────────────────────────────────────────────────────────────────
export 'src/binary/binary_processor.dart';
export 'src/binary/payload_info.dart';

// ── Cache & Rate Limiting ─────────────────────────────────────────────────────
export 'src/cache/lru_cache.dart';
export 'src/cache/rate_limiter.dart';

// ── Audit ─────────────────────────────────────────────────────────────────────
export 'src/audit/audit_entry.dart';
export 'src/audit/audit_logger.dart';

// ── Background ────────────────────────────────────────────────────────────────
export 'src/background/background_processor.dart';

// ── Implementation ────────────────────────────────────────────────────────────
export 'src/impl/hive_vault_impl.dart';
export 'src/impl/vault_factory.dart';
export 'src/impl/migration_manager.dart';
export 'src/impl/ttl_manager.dart';
export 'src/impl/reactive_vault.dart';
export 'src/impl/multi_box_vault.dart';
export 'src/impl/vault_health.dart';
export 'src/impl/vault_stats_counter.dart';

// ── Query DSL ─────────────────────────────────────────────────────────────────
export 'src/query/query_dsl.dart';

// ── Transactions ──────────────────────────────────────────────────────────────
export 'src/transaction/vault_transaction.dart';

// ── Plugin System ─────────────────────────────────────────────────────────────
export 'src/plugin/vault_plugin.dart';

// ── Observability ─────────────────────────────────────────────────────────────
export 'src/observability/vault_metrics.dart';

// ── Sharding ──────────────────────────────────────────────────────────────────
export 'src/sharding/shard_manager.dart';

// ── Sync & Conflict Resolution ────────────────────────────────────────────────
export 'src/sync/conflict_resolver.dart';
export 'src/sync/vault_synchronizer.dart';
