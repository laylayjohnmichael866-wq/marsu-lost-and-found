import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/qr_verification_models.dart';
import '../../providers/app_state.dart';
import '../../services/qr_service.dart';
import 'qr_verification_result_screen.dart';

enum QrScannerMode { auto, itemOnly, claimVerification }

class QrScannerScreen extends StatefulWidget {
  final QrScannerMode mode;

  const QrScannerScreen({
    super.key,
    this.mode = QrScannerMode.auto,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _isProcessing = false;
  bool _torchEnabled = false;
  String? _lastScannedPayload;
  DateTime? _lastScannedAt;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isDuplicateScan(String payload) {
    return QrService.shouldIgnoreScan(
      isProcessing: _isProcessing,
      candidatePayload: payload,
      lastPayload: _lastScannedPayload,
      lastScannedAt: _lastScannedAt,
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawValue = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) return;

    await _handlePayload(rawValue);
  }

  Future<void> _handlePayload(String rawValue) async {
    final normalized = rawValue.trim();
    if (_isDuplicateScan(normalized)) return;

    setState(() {
      _isProcessing = true;
      _lastScannedPayload = normalized;
      _lastScannedAt = DateTime.now();
      _statusMessage = 'Verifying QR code with MarSU backend...';
    });

    try {
      await _controller.stop();
    } catch (_) {}

    try {
      final parsed = QrService.parsePayload(normalized);
      if (!parsed.isSupported) {
        _showScanError(
          'Unrecognized QR code. Please scan an official MarSU Lost & Found item or claim QR.',
        );
        return;
      }

      if (!mounted) return;
      final appState = context.read<AppState>();

      if (widget.mode == QrScannerMode.itemOnly ||
          parsed.kind == QrPayloadKind.item) {
        if (parsed.kind == QrPayloadKind.claim) {
          _showScanError(
            'This is a Claim Release QR voucher. Open the general or Admin scanner to verify claim vouchers.',
          );
          return;
        }
        final itemResult = await appState.verifyScannedItemQr(normalized);
        if (!mounted) return;
        await _openResultScreen(
          rawPayload: normalized,
          itemResult: itemResult,
        );
        return;
      }

      if (widget.mode == QrScannerMode.claimVerification ||
          parsed.kind == QrPayloadKind.claim) {
        if (parsed.kind == QrPayloadKind.item) {
          _showScanError(
            'This is an Item Identification QR tag, not a Claim Release voucher.',
          );
          return;
        }
        final claimResult = await appState.verifyScannedClaimQr(normalized);
        if (!mounted) return;
        await _openResultScreen(
          rawPayload: normalized,
          claimResult: claimResult,
        );
        return;
      }

      // Auto mode with raw token: try item QR first, then claim QR
      final itemResult = await appState.verifyScannedItemQr(normalized);
      if (!mounted) return;
      if (itemResult.status != ItemQrVerificationStatus.invalid) {
        await _openResultScreen(
          rawPayload: normalized,
          itemResult: itemResult,
        );
        return;
      }

      final claimResult = await appState.verifyScannedClaimQr(normalized);
      if (!mounted) return;
      await _openResultScreen(
        rawPayload: normalized,
        claimResult: claimResult,
      );
    } catch (e) {
      if (!mounted) return;
      _showScanError(
        'Verification failed: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> _openResultScreen({
    required String rawPayload,
    ItemQrVerificationResult? itemResult,
    ClaimQrVerificationResult? claimResult,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrVerificationResultScreen(
          rawPayload: rawPayload,
          itemResult: itemResult,
          claimResult: claimResult,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _statusMessage = null;
      _lastScannedAt = DateTime.now();
    });
    try {
      await _controller.start();
    } catch (_) {}
  }

  void _showScanError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
    setState(() {
      _isProcessing = false;
      _statusMessage = null;
      _lastScannedAt = DateTime.now();
    });
    _controller.start().catchError((_) {});
  }

  Future<void> _showManualEntryDialog() async {
    final textController = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter QR Payload or Token'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: 'QR Code Payload / Token',
            hintText: 'marsu://item/... or marsu://claim/...',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (value != null && value.isNotEmpty && mounted) {
      await _handlePayload(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isStaff = appState.isModerator;

    final titleText = switch (widget.mode) {
      QrScannerMode.itemOnly => 'Scan Item QR Tag',
      QrScannerMode.claimVerification => 'Verify Claim QR',
      QrScannerMode.auto => 'QR Code Scanner',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
                if (mounted) {
                  setState(() => _torchEnabled = !_torchEnabled);
                }
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () async {
              try {
                await _controller.switchCamera();
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: 'Enter QR payload manually',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: _isProcessing ? null : _showManualEntryDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            onDetectError: (error, _) {
              if (!mounted) return;
              setState(() {
                _statusMessage = 'Scanner frame error. Hold steady and try again.';
              });
            },
            placeholderBuilder: (_) => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Initializing camera...'),
                ],
              ),
            ),
            errorBuilder: (context, error) {
              return _ScannerErrorView(
                error: error,
                onRetry: () async {
                  try {
                    await _controller.start();
                  } catch (_) {}
                },
                onManualEntry: _showManualEntryDialog,
              );
            },
          ),
          // Scanner overlay frame
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isProcessing
                        ? AppColors.warning
                        : Colors.white.withValues(alpha: 0.9),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          // Role & guidance banner at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isStaff
                        ? 'Administrator Verification Mode'
                        : 'Student QR Verification Mode',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.mode == QrScannerMode.claimVerification
                        ? 'Point camera at the claimant’s temporary Claim Release QR voucher.'
                        : 'Point camera at a MarSU Item Tag or Claim Handover QR code.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage ?? 'Verifying QR code...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;

  const _ScannerErrorView({
    required this.error,
    required this.onRetry,
    required this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    final isPermissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final isUnsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final title = isPermissionDenied
        ? 'Camera Permission Required'
        : isUnsupported
            ? 'Camera Unavailable On This Device'
            : 'Camera Scanner Error';

    final description = isPermissionDenied
        ? 'MarSU Lost & Found needs camera access to scan item tags and claim release QR codes. Please allow camera permission in your device settings and try again.'
        : error.errorDetails?.message ?? error.errorCode.message;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPermissionDenied
                      ? Icons.no_photography_outlined
                      : Icons.error_outline,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onManualEntry,
                        icon: const Icon(Icons.keyboard_outlined),
                        label: const Text('Manual Input'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryMaroon,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Camera'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
