// example/inventory_app/lib/services/auth_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Simple PIN-based authentication service using shared_preferences-like
// approach via HiveVault (stored in the settings vault).
// In production, use flutter_secure_storage for the PIN hash.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';

/// Simple PIN authentication service.
/// Stores a salted SHA-256 hash of the PIN (simulated without dart:crypto).
/// For production, use flutter_secure_storage.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// In-memory store for demo (use flutter_secure_storage in production).
  String? _storedHash;
  String? _storedSalt;
  bool _pinEnabled = false;

  bool get isPinEnabled => _pinEnabled;

  /// Derive a simple hash string from pin + salt.
  String _hash(String pin, String salt) {
    // Simple deterministic hash for demo purposes
    // In production: use crypto package with SHA-256
    final combined = '$salt:$pin:inventory_vault_v1';
    var hash = 0;
    for (final char in combined.codeUnits) {
      hash = ((hash << 5) - hash + char) & 0xFFFFFFFF;
    }
    // Mix more
    final bytes = utf8.encode(combined);
    var h1 = 0x9747b28c;
    var h2 = hash;
    for (int i = 0; i < bytes.length; i++) {
      h1 = ((h1 ^ bytes[i]) * 0x5bd1e995 + i) & 0xFFFFFFFF;
      h2 = ((h2 ^ bytes[bytes.length - 1 - i]) + h1) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64.encode(bytes);
  }

  /// Set a new PIN.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    _storedSalt = salt;
    _storedHash = hash;
    _pinEnabled = true;
  }

  /// Verify the entered PIN against the stored hash.
  Future<bool> verifyPin(String pin) async {
    if (!_pinEnabled || _storedSalt == null || _storedHash == null) {
      return true; // No PIN set — allow through
    }
    return _hash(pin, _storedSalt!) == _storedHash;
  }

  /// Clear the PIN.
  Future<void> clearPin() async {
    _storedHash = null;
    _storedSalt = null;
    _pinEnabled = false;
  }

  /// Persist the PIN state to a map (for saving in vault settings).
  Map<String, dynamic> toMap() => {
        'pinEnabled': _pinEnabled,
        'pinHash': _storedHash,
        'pinSalt': _storedSalt,
      };

  /// Restore PIN state from a map (loaded from vault settings).
  void fromMap(Map<String, dynamic> map) {
    _pinEnabled = map['pinEnabled'] as bool? ?? false;
    _storedHash = map['pinHash'] as String?;
    _storedSalt = map['pinSalt'] as String?;
  }
}
