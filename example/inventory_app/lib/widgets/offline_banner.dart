// example/inventory_app/lib/widgets/offline_banner.dart
// ─────────────────────────────────────────────────────────────────────────────
// Offline-first banner — always shows on web that all data is stored locally.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A small banner shown at the top of selected screens to indicate that the
/// app is running in offline-first mode (all data stored locally + encrypted).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppTheme.successColor.withAlpha(31), // ~12%
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 14, color: AppTheme.successColor),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Offline-first mode — all data stored locally & encrypted',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.successColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(Icons.lock, size: 12, color: AppTheme.successColor),
        ],
      ),
    );
  }
}
