// example/inventory_app/lib/utils/scanner_stub.dart
// ─────────────────────────────────────────────────────────────────────────────
// Web stub for mobile_scanner package.
// mobile_scanner is not available on Flutter Web — this stub satisfies
// the compiler without pulling in any native dependencies.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Stub BarcodeCapture used in web builds.
class BarcodeCapture {
  final List<Barcode> barcodes;
  const BarcodeCapture({this.barcodes = const []});
}

/// Stub Barcode.
class Barcode {
  final String? rawValue;
  const Barcode({this.rawValue});
}

/// Stub MobileScannerController.
class MobileScannerController {
  void dispose() {}
  void toggleTorch() {}
  void switchCamera() {}
}

/// Stub MobileScanner widget — renders a placeholder on web.
class MobileScanner extends StatelessWidget {
  final MobileScannerController? controller;
  final void Function(BarcodeCapture capture)? onDetect;

  const MobileScanner({super.key, this.controller, this.onDetect});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
            SizedBox(height: 8),
            Text(
              'Camera scanner not available on Web.\nUse the barcode input field below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
