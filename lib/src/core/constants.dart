// lib/src/core/constants.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Global constants used across all layers.
// ─────────────────────────────────────────────────────────────────────────────

/// Current binary payload format version.
/// Increment when the payload layout changes to support migration.
const int kPayloadVersion = 1;

/// Header size in bytes: version(1) + compression(1) + encryption(1) + dataLen(4)
const int kHeaderSize = 7;

/// Minimum data size (bytes) before attempting compression.
/// Data smaller than this is stored as-is to avoid compression overhead.
const int kDefaultMinCompressionSize = 64;

/// GZip magic bytes for format detection.
const int kGZipByte0 = 0x1f;
const int kGZipByte1 = 0x8b;

/// Lz4 magic number (little-endian) for format detection.
const int kLz4MagicByte0 = 0x04;
const int kLz4MagicByte1 = 0x22;
const int kLz4MagicByte2 = 0x4d;
const int kLz4MagicByte3 = 0x18;

/// AES-GCM nonce size (bytes).
const int kGcmNonceSize = 12;

/// AES-CBC IV size (bytes).
const int kCbcIvSize = 16;

/// PBKDF2 salt size (bytes).
const int kSaltSize = 16;

/// AES key size: 256 bits = 32 bytes.
const int kAesKeySize = 32;

/// GCM authentication tag size (bytes) appended by `cryptography` package.
const int kGcmTagSize = 16;

/// Default PBKDF2 iteration count for key derivation.
const int kDefaultPbkdf2Iterations = 100000;

/// Threshold (bytes) above which processing is offloaded to a background isolate.
const int kDefaultIsolateThreshold = 65536; // 64 KB

/// Default LRU cache size (number of entries).
const int kDefaultCacheSize = 100;

/// Secure storage key used to persist the vault master key.
const String kMasterKeyStorageId = 'hive_vault_master_key_v1';

/// Compression flag values embedded in binary payload header.
class CompressionFlag {
  const CompressionFlag._();
  static const int none = 0;
  static const int gzip = 1;
  static const int lz4 = 2;
  static const int deflate = 3;
}

/// Encryption flag values embedded in binary payload header.
class EncryptionFlag {
  const EncryptionFlag._();
  static const int none = 0;
  static const int aesCbc = 1;
  static const int aesGcm = 2;
}
