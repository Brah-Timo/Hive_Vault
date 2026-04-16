# Indexing Layer

> **Files**: `lib/src/indexing/`
>
> - `index_engine.dart` — In-memory inverted index
> - `tokenizer.dart` — Arabic/Latin text tokeniser
> - `indexing_config.dart` — Index configuration
> - `index_stats.dart` — (stats model lives in `core/vault_stats.dart`)

---

## 1. `index_engine.dart` — `InMemoryIndexEngine`

A dual-structure inverted index providing O(1) token lookup and AND/OR/prefix search.

### Data Structures

```
_invertedIndex : Map<token, Set<key>>
    "invoice" → {"INV-001", "INV-002", "INV-003"}
    "paid"    → {"INV-001"}
    "pending" → {"INV-002", "INV-003"}

_reverseIndex  : Map<key, Set<token>>
    "INV-001" → {"invoice", "paid", "client", "acme"}
    "INV-002" → {"invoice", "pending", "client", "beta"}
```

The two-way mapping enables:
- **Forward lookup**: which keys contain a token → O(1) via `_invertedIndex`
- **Atomic updates**: remove all old tokens for a key → O(t) via `_reverseIndex`

### Constructor

```dart
InMemoryIndexEngine(IndexingConfig config);
```

### Indexing Operations

```dart
// Add or replace an entry
engine.indexEntry('INV-001', 'Invoice ACME Corp paid 2024');

// Remove an entry completely
engine.removeEntry('INV-001');

// Clear everything
engine.clearIndex();

// Rebuild from scratch
engine.rebuildFrom({'INV-001': 'Invoice ACME Corp', 'INV-002': '...'});
```

`indexEntry` is **atomic**: it removes all old tokens for the key first, then inserts the new tokens.

### Search Operations

```dart
// AND search — all tokens must match
Set<String> keys = engine.searchAll('invoice pending');
// Returns keys that have BOTH "invoice" AND "pending" indexed

// OR search — any token matches
Set<String> keys = engine.searchAny('acme beta');
// Returns keys that have "acme" OR "beta"

// Prefix search
Set<String> keys = engine.searchPrefix('inv');
// Returns keys with any token starting with "inv"

// All indexed keys
Set<String> allKeys = engine.allKeys();

// Check if a key is indexed
bool indexed = engine.isIndexed('INV-001');
```

### Complexity

| Operation | Complexity | Notes |
|---|---|---|
| `indexEntry` | O(t) | t = token count |
| `removeEntry` | O(t) amortised | |
| `searchAll` | O(t · log m) | t = query tokens, m = match set size |
| `searchAny` | O(t · m) | |
| `searchPrefix` | O(k) | k = total unique keywords |
| `allKeys` | O(n) | n = indexed entries |

### Statistics

```dart
int count    = engine.indexedCount;   // Number of indexed keys
int keywords = engine.keywordCount;   // Unique tokens
bool empty   = engine.isEmpty;

IndexStats stats = engine.getStats();
// stats.totalEntries, totalKeywords, averageKeywordsPerEntry, memoryEstimateBytes
```

### Memory Estimation

```dart
int bytes = engine.getStats().memoryEstimateBytes;
```

Estimate is based on:
- Token strings: 2 bytes per character (UTF-16)
- Key references in `Set<String>`: ~32 bytes per reference (pointer + String header)
- Reverse index entries: ~20 bytes per token reference

### Debug Dump

```dart
print(engine.debugDump(maxEntries: 20));
// InMemoryIndex [
//   "invoice" → {INV-001, INV-002, INV-003}
//   "paid"    → {INV-001}
//   ...
// ]
```

---

## 2. `tokenizer.dart` — `Tokenizer`

Converts raw searchable text into a normalised, filtered set of tokens.

```dart
class Tokenizer {
  const Tokenizer(IndexingConfig config);
}
```

### Pipeline

```
Input text: "Invoice #INV-001 — ACME Corp. (Due: 2024-03-15)"

Step 1: Lowercase (Latin chars)
  "invoice #inv-001 — acme corp. (due: 2024-03-15)"

Step 2: Arabic diacritic removal (if Arabic text present)
  (no change for Latin input)

Step 3: Split on non-alphanumeric, non-Arabic characters
  ["invoice", "inv", "001", "acme", "corp", "due", "2024", "03", "15"]

Step 4: Filter tokens < minimumTokenLength (default 2)
  ["invoice", "inv", "001", "acme", "corp", "due", "2024", "03", "15"]

Step 5: Remove stop words {"the", "a", "an", "in", "on", "at", "to"}
  ["invoice", "inv", "001", "acme", "corp", "due", "2024", "03", "15"]

Step 6: Cap at maxTokensPerEntry (default 100)
  → Final token set
```

### Arabic Support

The tokenizer handles Arabic-script text (Unicode U+0600–U+06FF and U+0750–U+07FF):
- **Diacritic stripping**: removes harakat (vowel marks) to improve recall
  - e.g., `مُحَمَّد` → `محمد` (removes U+064B–U+065F range)
- **Split pattern**: splits on any character that is not Arabic, Latin, or a digit

This allows searching Arabic ERP data (customer names, product descriptions) without requiring exact diacritic input.

### Methods

```dart
// Tokenize for indexing (with maxTokensPerEntry cap)
Set<String> tokens = tokenizer.tokenize('Invoice ACME Corp paid');

// Tokenize a query (no cap, slightly different pipeline)
Set<String> tokens = tokenizer.tokenizeQuery('acme invoice');

// Normalize a single string (lowercase + diacritics removed)
String norm = tokenizer.normaliseQuery('مُحَمَّد');   // 'محمد'
```

### Split Pattern

```dart
static final RegExp _splitPattern = RegExp(
  r'[^\u0600-\u06FF\u0750-\u07FF\u0041-\u005A\u0061-\u007A\u0030-\u0039]+',
);
// Splits on anything that is NOT: Arabic script, A-Z, a-z, 0-9
```

---

## 3. `indexing_config.dart` — `IndexingConfig`

Full reference:

```dart
class IndexingConfig {
  const IndexingConfig({
    this.enableIndexing = true,
    this.minimumTokenLength = 2,
    this.maxTokensPerEntry = 100,
    this.indexableFields = const {},
    this.stopWords = const {
      'the', 'a', 'an', 'in', 'on', 'at', 'to',
      'and', 'or', 'of', 'for', 'is', 'are', 'was',
    },
    this.caseSensitive = false,
    this.enableArabicNormalization = true,
  });
}
```

### Field Details

| Field | Default | Description |
|---|---|---|
| `enableIndexing` | `true` | Master on/off switch |
| `minimumTokenLength` | `2` | Tokens shorter than this are ignored |
| `maxTokensPerEntry` | `100` | Cap on tokens extracted per entry |
| `indexableFields` | `{}` | When non-empty, only index these JSON field names |
| `stopWords` | (common words) | Filtered out during tokenization |
| `caseSensitive` | `false` | Usually false for better recall |
| `enableArabicNormalization` | `true` | Strips harakat for Arabic text |

### `indexableFields` Example

```dart
IndexingConfig(
  indexableFields: {'name', 'description', 'sku', 'tags'},
)
// Only values of 'name', 'description', 'sku', 'tags' fields
// are indexed, even if the record has many other fields
```

### Disable Indexing

```dart
// VaultConfig.light() uses:
IndexingConfig(enableIndexing: false)
// → secureSearch returns [] immediately, no overhead
```

---

## Full-Text Search Examples

### Basic Search

```dart
// Save with searchable text
await vault.secureSave(
  'CLI-001',
  {'name': 'ACME Corporation', 'sector': 'manufacturing'},
  searchableText: 'ACME Corporation manufacturing client',
);

// AND search
final results = await vault.secureSearch<Map>('acme manufacturing');
// Returns CLI-001 (both tokens present)

// OR search
final results = await vault.secureSearchAny<Map>('acme beta');
// Returns CLI-001 (has 'acme') + any with 'beta'

// Prefix
final results = await vault.secureSearchPrefix<Map>('manuf');
// Returns CLI-001 (has 'manufacturing' starting with 'manuf')
```

### Keys Only

```dart
final keys = await vault.searchKeys('acme');
// Returns Set<String>: {'CLI-001', 'CLI-007'}
```

### Auto-Extracted Text

If `searchableText` is not provided, `HiveVaultImpl` auto-extracts text from Map/String values by recursively concatenating all string-typed values:

```dart
await vault.secureSave('CLI-001', {
  'name': 'ACME Corp',
  'email': 'info@acme.com',
  'active': true,
  'balance': 50000.0,
});
// Auto-indexed: "acme corp info@acme.com"
```

### Rebuild Index

```dart
// After importing data or if the index gets out of sync
await vault.rebuildIndex();
// Clears index, reads all keys, decrypts+deserializes, re-tokenizes
```
