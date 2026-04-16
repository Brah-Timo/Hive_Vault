// lib/src/indexing/tokenizer.dart
// ─────────────────────────────────────────────────────────────────────────────
// HiveVault — Text tokeniser for the in-memory inverted index.
// Supports Arabic, Latin, and mixed scripts.
// ─────────────────────────────────────────────────────────────────────────────

import '../core/indexing_config.dart';

/// Splits text into normalised, filtered tokens suitable for indexing.
///
/// Handles:
/// - Arabic / Arabic-script text (Unicode range U+0600–U+06FF).
/// - Latin text (A–Z, a–z, digits).
/// - Mixed Arabic-Latin documents (ERP invoices, client names, etc.).
/// - Configurable stop-word filtering and minimum token length.
class Tokenizer {
  final IndexingConfig config;

  const Tokenizer(this.config);

  /// Tokenises [text] and returns a (possibly empty) [Set] of normalised tokens.
  ///
  /// Steps:
  /// 1. Lowercase (for Latin characters).
  /// 2. Remove diacritics (Arabic harakat) for better recall.
  /// 3. Split on whitespace and punctuation.
  /// 4. Filter tokens shorter than [IndexingConfig.minimumTokenLength].
  /// 5. Remove stop-words.
  /// 6. Cap at [IndexingConfig.maxTokensPerEntry] tokens.
  Set<String> tokenize(String text) {
    if (text.isEmpty) return const {};

    final normalised = _normalise(text);
    final parts = normalised.split(_splitPattern);

    final tokens = <String>{};
    for (final part in parts) {
      if (part.length < config.minimumTokenLength) continue;
      if (config.stopWords.contains(part)) continue;
      tokens.add(part);
      if (tokens.length >= config.maxTokensPerEntry) break;
    }

    return tokens;
  }

  /// Normalises a single query string (same pipeline as indexing, but no cap).
  String normaliseQuery(String query) => _normalise(query);

  /// Splits a query into tokens (no cap, no stop-word filter for queries).
  Set<String> tokenizeQuery(String query) {
    final normalised = _normalise(query);
    return normalised
        .split(_splitPattern)
        .where((t) => t.length >= config.minimumTokenLength)
        .toSet();
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  /// Matches any character that is NOT a letter, digit, or Arabic script char.
  static final RegExp _splitPattern = RegExp(
    r'[^\u0600-\u06FF\u0750-\u077F\w]+',
    unicode: true,
  );

  /// Arabic diacritics (harakat) — removing them improves recall.
  static final RegExp _arabicDiacritics = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4'
    r'\u06E7\u06E8\u06EA-\u06ED]',
  );

  /// Tatweel (stretching character) — decorative, not semantic.
  static final RegExp _tatweel = RegExp(r'\u0640');

  String _normalise(String text) {
    var s = text;
    // 1. Remove Arabic diacritics.
    s = s.replaceAll(_arabicDiacritics, '');
    // 2. Remove tatweel.
    s = s.replaceAll(_tatweel, '');
    // 3. Lowercase (no-op for Arabic but handles Latin).
    s = s.toLowerCase();
    // 4. Trim.
    return s.trim();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility: extracts a searchable string from a Map<String, dynamic>.
// ─────────────────────────────────────────────────────────────────────────────

/// Extracts all string-valued fields from [data] and concatenates them,
/// optionally restricted to [allowedFields].
///
/// Used by [HiveVaultImpl] to auto-build searchable text when no explicit
/// [searchableText] is provided by the caller.
String extractSearchableText(
  Map<String, dynamic> data, {
  List<String> allowedFields = const [],
}) {
  final buf = StringBuffer();

  void _visit(dynamic value) {
    if (value is String) {
      buf.write(value);
      buf.write(' ');
    } else if (value is Map<String, dynamic>) {
      for (final entry in value.entries) {
        if (allowedFields.isEmpty || allowedFields.contains(entry.key)) {
          _visit(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _visit(item);
      }
    } else if (value is num || value is bool) {
      buf.write(value.toString());
      buf.write(' ');
    }
  }

  if (allowedFields.isEmpty) {
    _visit(data);
  } else {
    for (final field in allowedFields) {
      _visit(data[field]);
    }
  }

  return buf.toString().trim();
}
