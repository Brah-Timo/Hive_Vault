// example/inventory_app/lib/screens/scanner/scanner_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Barcode / QR scanner.
//   • Mobile / Desktop  → uses MobileScanner (camera-based).
//   • Web               → manual-entry only (no camera API required).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// mobile_scanner is only available on native platforms (not web)
// ignore: depend_on_referenced_packages
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) '../../utils/scanner_stub.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../products/product_detail_screen.dart';
import '../products/product_form_screen.dart';
import '../stock/stock_movement_form_screen.dart';
import '../../theme/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String? _lastScanned;
  String _scanMode = 'info'; // 'stockIn', 'stockOut', 'info'
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Scanner'),
        actions: [
          if (!kIsWeb) ...[
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: () {
                _controller?.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
              tooltip: 'Toggle torch',
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: () => _controller?.switchCamera(),
              tooltip: 'Switch camera',
            ),
          ],
        ],
      ),
      body: kIsWeb ? _buildWebFallback() : _buildNativeScanner(),
    );
  }

  // ── Native camera scanner ─────────────────────────────────────────────────

  Widget _buildNativeScanner() {
    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
        ),
        // Dark overlay with transparent rect
        _buildScanOverlay(),
        // Bottom controls panel
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomPanel(),
        ),
      ],
    );
  }

  Widget _buildScanOverlay() {
    return Stack(
      children: [
        // Semi-transparent mask
        Container(color: Colors.black45),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Transparent scan window
              Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor, width: 3),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.transparent,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Align barcode within the frame',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Web fallback (manual entry) ───────────────────────────────────────────

  Widget _buildWebFallback() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              size: 72,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Camera Scanner',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Camera scanning is not available in the web browser.\n'
            'Please enter the barcode manually below.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 32),
          _buildModeSelector(),
          const SizedBox(height: 24),
          _buildManualEntryCard(),
          if (_lastScanned != null) ...[
            const SizedBox(height: 20),
            _buildLastScannedChip(),
          ],
        ],
      ),
    );
  }

  Widget _buildManualEntryCard() {
    final ctrl = TextEditingController();
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Barcode / SKU',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'e.g. 1234567890123 or ELC-001',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    if (ctrl.text.trim().isNotEmpty) {
                      setState(() => _lastScanned = ctrl.text.trim());
                      _handleBarcode(ctrl.text.trim());
                    }
                  },
                ),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  setState(() => _lastScanned = v.trim());
                  _handleBarcode(v.trim());
                }
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    setState(() => _lastScanned = ctrl.text.trim());
                    _handleBarcode(ctrl.text.trim());
                  }
                },
                icon: const Icon(Icons.search),
                label: const Text('Search Product'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastScannedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'Last: $_lastScanned',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel (native only) ────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scan Mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _buildModeSelector(),
          if (_lastScanned != null) ...[
            const SizedBox(height: 12),
            _buildLastScannedChip(),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _showManualEntry,
            icon: const Icon(Icons.keyboard),
            label: const Text('Enter Barcode Manually'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _modeButton(
          label: 'Stock In',
          icon: Icons.add_circle_outline,
          color: Colors.green,
          mode: 'stockIn',
        ),
        _modeButton(
          label: 'Stock Out',
          icon: Icons.remove_circle_outline,
          color: Colors.red,
          mode: 'stockOut',
        ),
        _modeButton(
          label: 'Product Info',
          icon: Icons.info_outline,
          color: AppTheme.primaryColor,
          mode: 'info',
        ),
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required Color color,
    required String mode,
  }) {
    final isSelected = _scanMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _scanMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Detection handler ─────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue == _lastScanned) return;

    setState(() {
      _isProcessing = true;
      _lastScanned = rawValue;
    });

    await _handleBarcode(rawValue);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _handleBarcode(String barcode) async {
    if (!mounted) return;
    final prov = context.read<InventoryProvider>();
    final product = await prov.getProductByBarcode(barcode);
    if (!mounted) return;

    if (product == null) {
      _showProductNotFound(barcode);
      return;
    }

    if (_scanMode == 'info') {
      _showProductInfo(product);
    } else if (_scanMode == 'stockIn') {
      _showStockMovementSheet(product, preferIn: true);
    } else {
      _showStockMovementSheet(product, preferIn: false);
    }
  }

  void _showProductInfo(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _showStockMovementSheet(Product product, {required bool preferIn}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          StockMovementFormSheet(product: product, preferIn: preferIn),
    );
  }

  void _showProductNotFound(String barcode) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'Product Not Found',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'No product matched barcode:\n$barcode',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProductFormScreen()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Create New Product'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualEntry() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode / SKU',
            prefixIcon: Icon(Icons.qr_code),
          ),
          onSubmitted: (v) {
            Navigator.pop(context);
            if (v.trim().isNotEmpty) {
              setState(() => _lastScanned = v.trim());
              _handleBarcode(v.trim());
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _lastScanned = ctrl.text.trim());
                _handleBarcode(ctrl.text.trim());
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}
