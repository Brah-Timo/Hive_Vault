// example/inventory_app/lib/screens/auth/auth_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// PIN-based authentication screen for the InventoryVault app.
// Supports: set PIN, verify PIN, change PIN, biometric hint.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';

enum AuthMode { verify, setup, change }

class AuthScreen extends StatefulWidget {
  final AuthMode mode;
  final VoidCallback onSuccess;
  final VoidCallback? onCancel;

  const AuthScreen({
    super.key,
    this.mode = AuthMode.verify,
    required this.onSuccess,
    this.onCancel,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const _pinLength = 4;

  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _error = false;
  int _attempts = 0;
  bool _isLocked = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    if (widget.mode == AuthMode.setup) {
      _isConfirming = false;
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.mode == AuthMode.setup) {
      return _isConfirming ? 'Confirm PIN' : 'Create PIN';
    }
    if (widget.mode == AuthMode.change) {
      return _isConfirming ? 'Confirm New PIN' : 'Enter New PIN';
    }
    return 'Enter PIN';
  }

  String get _subtitle {
    if (widget.mode == AuthMode.setup) {
      return _isConfirming
          ? 'Re-enter your 4-digit PIN to confirm'
          : 'Create a 4-digit PIN to secure your inventory';
    }
    if (widget.mode == AuthMode.change) {
      return _isConfirming
          ? 'Re-enter your new PIN to confirm'
          : 'Enter a new 4-digit PIN';
    }
    return 'Enter your PIN to continue';
  }

  void _onDigit(String digit) {
    if (_isLocked) return;
    HapticFeedback.lightImpact();
    final currentPin = _isConfirming ? _confirmPin : _pin;
    if (currentPin.length >= _pinLength) return;

    setState(() {
      _error = false;
      if (_isConfirming) {
        _confirmPin += digit;
      } else {
        _pin += digit;
      }
    });

    // Auto-submit when PIN is complete
    final updated = _isConfirming ? _confirmPin : _pin;
    if (updated.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 100), _submit);
    }
  }

  void _onDelete() {
    if (_isLocked) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = false;
      if (_isConfirming && _confirmPin.isNotEmpty) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else if (!_isConfirming && _pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _submit() async {
    if (widget.mode == AuthMode.verify) {
      final isValid = await AuthService.instance.verifyPin(_pin);
      if (isValid) {
        HapticFeedback.heavyImpact();
        widget.onSuccess();
      } else {
        _attempts++;
        if (_attempts >= 5) {
          setState(() => _isLocked = true);
          await Future.delayed(const Duration(seconds: 30));
          if (mounted) setState(() { _isLocked = false; _attempts = 0; });
        }
        _triggerError();
      }
    } else if (widget.mode == AuthMode.setup || widget.mode == AuthMode.change) {
      if (!_isConfirming) {
        setState(() => _isConfirming = true);
      } else {
        if (_pin == _confirmPin) {
          await AuthService.instance.setPin(_pin);
          HapticFeedback.heavyImpact();
          widget.onSuccess();
        } else {
          _triggerError();
          setState(() {
            _confirmPin = '';
            _isConfirming = false;
            _pin = '';
          });
        }
      }
    }
  }

  void _triggerError() {
    HapticFeedback.vibrate();
    setState(() {
      _error = true;
      _pin = '';
      _confirmPin = '';
    });
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirming ? _confirmPin : _pin;

    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      appBar: widget.onCancel != null
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: widget.onCancel,
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.mode == AuthMode.verify
                          ? Icons.lock_outlined
                          : Icons.lock_open_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLocked ? 'Too many attempts. Wait 30 seconds.' : _subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isLocked ? Colors.red.shade200 : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // PIN dots
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_shakeAnimation.value * (_error ? 1 : 0), 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pinLength,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < currentPin.length
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                            border: Border.all(
                              color: _error
                                  ? Colors.red.shade300
                                  : Colors.white54,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_error) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.mode == AuthMode.verify
                          ? 'Incorrect PIN. Try again.'
                          : 'PINs do not match. Try again.',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            // Keypad
            Expanded(
              flex: 3,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildKeyRow(['1', '2', '3']),
                      _buildKeyRow(['4', '5', '6']),
                      _buildKeyRow(['7', '8', '9']),
                      _buildBottomRow(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _DigitKey(digit: d, onTap: _onDigit)).toList(),
    );
  }

  Widget _buildBottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Empty or fingerprint placeholder
        SizedBox(
          width: 72,
          height: 72,
          child: widget.mode == AuthMode.verify
              ? IconButton(
                  icon: const Icon(Icons.fingerprint, size: 32),
                  color: Colors.grey.shade400,
                  onPressed: null, // biometric not implemented
                )
              : null,
        ),
        _DigitKey(digit: '0', onTap: _onDigit),
        SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: Colors.red.withOpacity(0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _onDelete,
              child: const Center(
                child: Icon(Icons.backspace_outlined,
                    color: Colors.red, size: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DigitKey extends StatelessWidget {
  final String digit;
  final ValueChanged<String> onTap;

  const _DigitKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.grey.shade100,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onTap(digit),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
