import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';

class QrScanScreen extends StatefulWidget {
  final String eventId;

  const QrScanScreen({super.key, required this.eventId});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  bool _isProcessing = false;
  Map<String, dynamic>? _lastScannedAttendee;
  MobileScannerController cameraController = MobileScannerController();

  Future<void> _processBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue == null) continue;

      setState(() {
        _isProcessing = true;
      });

      try {
        // Send encrypted QR data directly to server for validation
        final encryptedData = barcode.rawValue!;
        final response = await _apiService.verifyQrAttendance(
          encryptedData,
          widget.eventId,
        );

        if (!mounted) return;

        // Server already validates eventId, so we just process success

        setState(() {
          _lastScannedAttendee = response['attendance'];
        });

        _soundService.playSuccess();

        // Wait a bit to show the success message
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        _soundService.playError();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _lastScannedAttendee = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Scan QR Code',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: cameraController,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  case TorchState.unavailable:
                  case TorchState.auto:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            iconSize: 32.0,
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: cameraController,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                  case CameraFacing.external:
                  case CameraFacing.unknown:
                    return const Icon(Icons.camera);
                }
              },
            ),
            iconSize: 32.0,
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: cameraController,
              onDetect: _processBarcode,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: _lastScannedAttendee != null
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 40,
                    ),
                    title: Text(
                      _lastScannedAttendee!['name'] ?? 'Attendee',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _lastScannedAttendee!['email'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : Column(
                    children: [
                      Text(
                        _isProcessing
                            ? 'Processing...'
                            : 'Align QR code in the frame',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The app will automatically scan and mark attendance',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
