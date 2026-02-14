import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';

class VerifyTicketScreen extends StatefulWidget {
  final String eventId;

  const VerifyTicketScreen({super.key, required this.eventId});

  @override
  State<VerifyTicketScreen> createState() => _VerifyTicketScreenState();
}

class _VerifyTicketScreenState extends State<VerifyTicketScreen> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  bool _isProcessing = false;
  bool _scanningEnabled = true;
  Map<String, dynamic>? _ticketData;
  bool _hasError = false;
  String _errorMessage = '';
  MobileScannerController cameraController = MobileScannerController();

  Future<void> _processBarcode(BarcodeCapture capture) async {
    if (_isProcessing || !_scanningEnabled) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue == null) continue;

      setState(() {
        _isProcessing = true;
        _scanningEnabled = false;
        _hasError = false;
        _errorMessage = '';
      });

      // Stop the camera immediately after detection
      await cameraController.stop();

      try {
        final qrPayload = barcode.rawValue!;
        final response = await _apiService.verifyTicket(
          qrPayload,
          widget.eventId,
        );

        if (!mounted) return;

        // Safely access ticket data
        final ticket = response['ticket'];
        if (ticket != null && ticket is Map<String, dynamic>) {
          setState(() {
            _ticketData = ticket;
          });

          _soundService.playSuccess();
        } else {
          throw Exception('Invalid ticket data received');
        }
      } catch (e) {
        _soundService.playError();
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
      break;
    }
  }

  void _resetScan() async {
    setState(() {
      _ticketData = null;
      _hasError = false;
      _errorMessage = '';
      _isProcessing = false;
      _scanningEnabled = true;
    });
    await cameraController.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Verify Ticket',
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
            child: _ticketData != null
                ? _buildTicketResultView()
                : _hasError
                ? _buildErrorView()
                : MobileScanner(
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
            child: _ticketData != null
                ? _buildTicketResultBottom()
                : _hasError
                ? _buildErrorBottom()
                : Column(
                    children: [
                      Text(
                        _isProcessing
                            ? 'Verifying...'
                            : 'Scan ticket to verify',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Position the QR code within the frame',
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

  Widget _buildTicketResultView() {
    final hasAttended = _ticketData?['hasAttended'] ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: hasAttended
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasAttended ? Icons.check_circle : Icons.confirmation_number,
              size: 60,
              color: hasAttended ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _ticketData?['name'] ?? 'Unknown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _ticketData?['regNo'] ?? '',
            style: const TextStyle(color: Colors.grey, fontSize: 18),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: hasAttended
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              hasAttended ? 'ATTENDANCE MARKED' : 'NOT ATTENDED',
              style: TextStyle(
                color: hasAttended ? Colors.green : Colors.orange,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_ticketData?['email'] != null)
            Text(
              _ticketData!['email'],
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          if (_ticketData?['phone'] != null)
            Text(
              _ticketData!['phone'],
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildTicketResultBottom() {
    final hasAttended = _ticketData?['hasAttended'] ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hasAttended
              ? 'Ticket verified - Attendance already marked'
              : 'Ticket verified - Attendance not yet marked',
          style: TextStyle(
            color: hasAttended ? Colors.green : Colors.orange,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _resetScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Another Ticket'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, size: 60, color: Colors.red),
          ),
          const SizedBox(height: 24),
          const Text(
            'Verification Failed',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBottom() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Unable to verify ticket',
          style: TextStyle(
            color: Colors.red,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _resetScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
