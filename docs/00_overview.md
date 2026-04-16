# HiveVault — Project Overview

> **Version**: 1.0.0 | **Dart SDK**: ≥3.0.0 | **Flutter**: ≥3.10.0

---

## What is HiveVault?

**HiveVault** is a production-grade, encrypted, compressed, indexed local-storage library for Flutter and Dart applications. It wraps [Hive](https://pub.dev/packages/hive) with a multi-layer security and performance stack:

```
┌──────────────────────────────────────────────────────────────────┐
│                        Your Application                          │
├──────────────────────────────────────────────────────────────────┤
│  VaultQuery DSL  │  ReactiveVault  │  MultiBoxVault  │  TTL     │
├──────────────────────────────────────────────────────────────────┤
│              HiveVaultImpl  (SecureStorageInterface)             │
├───────────────┬──────────────────┬───────────────────────────────┤
│  LRU Cache    │  InMemory Index  │  AuditLogger                  │
├───────────────┴──────────────────┴───────────────────────────────┤
│          BinaryProcessor  (framing + SHA-256 integrity)          │
├──────────────────────────┬───────────────────────────────────────┤
│  Encryption Layer        │  Compression Layer                    │
│  AES-256-GCM / CBC       │  GZip / Lz4 / Deflate / Auto         │
├──────────────────────────┴───────────────────────────────────────┤
│                    Hive (local NoSQL storage)                     │
└──────────────────────────────────────────────────────────────────┘
```

---

## Core Features

| Feature | Details |
|---|---|
| **Encryption** | AES-256-GCM (authenticated) or AES-256-CBC, PBKDF2 key derivation |
| **Compression** | GZip, Lz4, Deflate, Auto-select by payload size |
| **Search** | In-memory inverted index with AND/OR/prefix search |
| **Query DSL** | Fluent, type-safe predicate builder with sorting & pagination |
| **Transactions** | ACID-style write-ahead log with savepoints and rollback |
| **Reactive** | Stream-based change notifications for Flutter widgets |
| **TTL** | Per-key time-to-live with auto-purge timers |
| **Multi-box** | Module-isolated vaults for ERP domain separation |
| **Sharding** | Horizontal partitioning across multiple Hive boxes |
| **Sync** | Bidirectional sync with custom `RemoteDataSource` adapters |
| **Audit log** | Bounded in-memory ring buffer of every vault operation |
| **Health checks** | Automated cache, index, compression diagnostics |
| **Rate limiting** | Token-bucket and sliding-window rate limiters |
| **Migrations** | Versioned payload format migrations |
| **Background processing** | Flutter `compute` offload for large payloads |

---

## Quick Start

```dart
import 'package:hive_vault/hive_vault.dart';

void main() async {
  // 1. Initialize Hive
  await HiveVault.initHive();

  // 2. Open a vault with ERP preset
  final vault = await HiveVault.open(
    boxName: 'products',
    config: VaultConfig.erp(),
  );

  // 3. Save a record
  await vault.secureSave(
    'PROD-001',
    {'name': 'Widget A', 'price': 9.99, 'stock': 100},
    searchableText: 'Widget A widget product',
  );

  // 4. Retrieve a record
  final product = await vault.secureGet<Map>('PROD-001');

  // 5. Full-text search
  final results = await vault.secureSearch<Map>('widget');

  // 6. Close when done
  await vault.close();
}
```

---

## Source Tree

```
lib/
└── src/
    ├── audit/
    │   ├── audit_entry.dart          # AuditAction enum + AuditEntry model
    │   └── audit_logger.dart         # In-memory ring-buffer audit log
    ├── background/
    │   ├── background_processor.dart # Flutter compute offload for large payloads
    │   └── vault_counters.dart       # Mutable hit/miss/op counters
    ├── binary/
    │   ├── binary_processor.dart     # Payload framing (header + checksum)
    │   └── payload_info.dart         # Parsed payload header model
    ├── cache/
    │   ├── lru_cache.dart            # Generic LRU cache + VaultCache alias
    │   └── rate_limiter.dart         # Token-bucket / sliding-window limiters
    ├── compression/
    │   ├── _io_codec_native.dart     # dart:io GZip/ZLib codecs (non-web)
    │   ├── _io_codec_stub.dart       # Web stubs that throw UnsupportedError
    │   ├── auto_compression_provider.dart  # Auto-selects algorithm by size
    │   ├── auto_provider.dart        # Alternative auto provider (flag-aware)
    │   ├── compression_config.dart   # CompressionStrategy enum + config
    │   ├── compression_factory.dart  # Factory: config → CompressionProvider
    │   ├── compression_provider.dart # Abstract base interface
    │   ├── deflate_provider.dart     # ZLib/Deflate provider
    │   ├── gzip_provider.dart        # GZip provider (web: Lz4 fallback)
    │   ├── lz4_provider.dart         # Pure-Dart Lz4 block codec
    │   └── no_compression_provider.dart  # Pass-through (no-op)
    ├── core/
    │   ├── compression_config.dart   # (re-export / shared)
    │   ├── constants.dart            # All global constants + flag classes
    │   ├── encryption_config.dart    # EncryptionConfig
    │   ├── indexing_config.dart      # IndexingConfig
    │   ├── sensitivity_level.dart    # SensitivityLevel enum
    │   ├── vault_config.dart         # Master VaultConfig (presets)
    │   ├── vault_exceptions.dart     # Full exception hierarchy
    │   ├── vault_interface.dart      # SecureStorageInterface (public API)
    │   └── vault_stats.dart          # IndexStats + VaultStats value objects
    ├── encryption/
    │   ├── aes_cbc_provider.dart     # AES-256-CBC + buildEncryptionProvider()
    │   ├── aes_gcm_provider.dart     # AES-256-GCM (authenticated)
    │   ├── encryption_config.dart    # EncryptionConfig (full)
    │   ├── encryption_factory.dart   # Factory: config + key → provider
    │   ├── encryption_provider.dart  # Abstract base interface
    │   ├── key_manager.dart          # Key generation, derivation, secure storage
    │   ├── key_rotation_scheduler.dart # Automated key rotation with policies
    │   ├── no_encryption_provider.dart # Pass-through (no-op)
    │   └── sensitivity_level.dart    # (re-export)
    ├── impl/
    │   ├── hive_vault_impl.dart      # Core implementation of SecureStorageInterface
    │   ├── migration_manager.dart    # Versioned payload migrations
    │   ├── multi_box_vault.dart      # Multi-module vault collection
    │   ├── reactive_vault.dart       # Stream-emitting decorator
    │   ├── ttl_manager.dart          # Time-to-live management
    │   ├── vault_factory.dart        # HiveVault static factory (open/create/registry)
    │   ├── vault_health.dart         # Health checker + HealthReport
    │   └── vault_stats_counter.dart  # Mutable stats accumulator
    ├── indexing/
    │   ├── index_engine.dart         # In-memory inverted index
    │   ├── index_stats.dart          # (see core/vault_stats.dart)
    │   ├── indexing_config.dart      # IndexingConfig
    │   └── tokenizer.dart            # Arabic/Latin text tokeniser
    ├── observability/
    │   └── vault_metrics.dart        # VaultMetrics (Prometheus-style counters)
    ├── plugin/
    │   └── vault_plugin.dart         # VaultPlugin hook interface
    ├── query/
    │   └── query_dsl.dart            # VaultQuery fluent DSL
    ├── sharding/
    │   └── shard_manager.dart        # ShardManager + routing strategies
    ├── sync/
    │   ├── conflict_resolver.dart    # Conflict resolution strategies
    │   └── vault_synchronizer.dart   # Bidirectional sync engine
    └── transaction/
        └── vault_transaction.dart    # ACID transaction system
```

---

## VaultConfig Presets

| Preset | Compression | Encryption | Index | Audit | Cache |
|---|---|---|---|---|---|
| `VaultConfig()` | GZip-6 | AES-256-GCM | Full | Yes | 100 |
| `VaultConfig.erp()` | GZip-6 | AES-256-GCM+integrity | Full | Yes | 200 |
| `VaultConfig.light()` | Lz4 | AES-256-CBC | None | No | 30 |
| `VaultConfig.debug()` | None | None (plaintext) | Full | Yes | 50 |
| `VaultConfig.maxSecurity()` | GZip-9 | AES-256-GCM 200k PBKDF2 | Full | Yes | 50 |
| `VaultConfig.maxPerformance()` | Lz4 | None | Full | No | 500 |

---

## Binary Payload Format

Every value stored in Hive is wrapped in the HiveVault envelope:

```
Offset  Size    Field
──────  ──────  ─────────────────────────────────────
0       1 byte  Format version (currently 0x01)
1       1 byte  Compression flag (0=none, 1=gzip, 2=lz4, 3=deflate)
2       1 byte  Encryption flag  (0=none, 1=AES-CBC, 2=AES-GCM)
3..6    4 bytes Data length (uint32 big-endian)
7..N    N bytes Compressed + encrypted payload
N+1..   32 bytes SHA-256 checksum (when integrity checks enabled)
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `hive` | Underlying NoSQL storage |
| `hive_flutter` | Flutter adapter for Hive |
| `encrypt` | AES-256-CBC via `pointycastle` |
| `cryptography` | AES-256-GCM + PBKDF2 |
| `flutter_secure_storage` | Secure master-key persistence |
| `meta` | `@immutable` annotations |

---

## Documentation Index

| File | Topic |
|---|---|
| [01_core.md](01_core.md) | Core interfaces, config, constants, exceptions, stats |
| [02_encryption.md](02_encryption.md) | AES-GCM, AES-CBC, key manager, key rotation |
| [03_compression.md](03_compression.md) | GZip, Lz4, Deflate, Auto, providers |
| [04_indexing.md](04_indexing.md) | Inverted index engine, tokenizer, config |
| [05_impl.md](05_impl.md) | HiveVaultImpl, VaultFactory, migrations |
| [06_audit.md](06_audit.md) | AuditLogger, AuditEntry, audit actions |
| [07_cache.md](07_cache.md) | LRU cache, rate limiter, VaultRateLimiter |
| [08_binary.md](08_binary.md) | BinaryProcessor, PayloadInfo, payload format |
| [09_background.md](09_background.md) | BackgroundProcessor, VaultCounters |
| [10_query_dsl.md](10_query_dsl.md) | VaultQuery, predicates, sorting, pagination |
| [11_transactions.md](11_transactions.md) | VaultTransaction, savepoints, receipts |
| [12_observability.md](12_observability.md) | VaultMetrics, health checks, stats |
| [13_sync.md](13_sync.md) | VaultSynchronizer, RemoteDataSource, SyncResult |
| [14_sharding.md](14_sharding.md) | ShardManager, routing strategies |
| [15_plugin.md](15_plugin.md) | VaultPlugin hook system |
| [16_reactive.md](16_reactive.md) | ReactiveVault, VaultEvent streams |
| [17_vault_health.md](17_vault_health.md) | VaultHealthChecker, HealthReport, issues |
| [18_exception_reference.md](18_exception_reference.md) | Full exception hierarchy reference |
| [19_inventory_app.md](19_inventory_app.md) | Example: Inventory ERP app |
| [20_ttl.md](20_ttl.md) | TtlManager, auto-expiry, purge sweeps |
| [21_multi_box.md](21_multi_box.md) | MultiBoxVault, module isolation |
| [22_migration.md](22_migration.md) | MigrationManager, VaultMigration |
| [23_rate_limiter.md](23_rate_limiter.md) | Rate limiters in detail |
