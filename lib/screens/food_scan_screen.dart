import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/food_session.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';

enum _ScanResult { none, admitted, already, full, error }

class FoodScanScreen extends StatefulWidget {
  final String eventId;
  final FoodSession session;

  const FoodScanScreen({
    super.key,
    required this.eventId,
    required this.session,
  });

  @override
  State<FoodScanScreen> createState() => _FoodScanScreenState();
}

class _FoodScanScreenState extends State<FoodScanScreen> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  final MobileScannerController cameraController = MobileScannerController();

  bool _isProcessing = false;
  bool _scanningEnabled = true;

  _ScanResult _result = _ScanResult.none;
  Map<String, dynamic>? _attendee;
  String _message = '';
  String? _scannedSessionName;
  DateTime? _scannedAt;

  // Live session counters, seeded from the selected session and updated from
  // each scan response.
  late int _count = widget.session.count;
  late final int _limit = widget.session.limit;
  late final int _maxLimit = widget.session.maxLimit;
  bool _limitHit = false;

  Future<void> _processBarcode(BarcodeCapture capture) async {
    if (_isProcessing || !_scanningEnabled) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue == null) continue;

      setState(() {
        _isProcessing = true;
        _scanningEnabled = false;
      });

      await cameraController.stop();

      try {
        final result = await _apiService.scanFoodSession(
          widget.eventId,
          widget.session.id,
          barcode.rawValue!,
        );

        if (!mounted) return;

        final int status = result['statusCode'] ?? 0;
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(result['data'] ?? {});

        _applyResult(status, data);
      } catch (e) {
        _soundService.playError();
        if (!mounted) return;
        setState(() {
          _result = _ScanResult.error;
          _attendee = null;
          _message = e.toString().replaceAll('Exception: ', '');
        });
      } finally {
        // Show the outcome briefly.
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          if (_limitHit) {
            // Hard limit reached — close the scanner and keep it closed.
            await cameraController.stop();
            setState(() {
              _isProcessing = false;
              _scanningEnabled = false;
            });
          } else {
            setState(() {
              _result = _ScanResult.none;
              _attendee = null;
              _message = '';
              _scannedSessionName = null;
              _scannedAt = null;
              _isProcessing = false;
              _scanningEnabled = true;
            });
            await cameraController.start();
          }
        }
      }
      break;
    }
  }

  void _applyResult(int status, Map<String, dynamic> data) {
    if (status == 200 && data['ok'] == true) {
      final session = data['session'];
      final attendee = data['attendee'];
      setState(() {
        _result = _ScanResult.admitted;
        _attendee = attendee is Map ? Map<String, dynamic>.from(attendee) : null;
        _message = 'Admitted to ${widget.session.name}';
        if (session is Map && session['count'] != null) {
          _count = session['count'];
        }
        if (_count >= _maxLimit) {
          _limitHit = true;
        }
      });
      _soundService.playSuccess();
      return;
    }

    if (data['alreadyScanned'] == true) {
      final attendee = data['attendee'];
      setState(() {
        _result = _ScanResult.already;
        _attendee = attendee is Map ? Map<String, dynamic>.from(attendee) : null;
        _scannedSessionName = data['scannedSessionName'];
        _scannedAt = data['scannedAt'] != null
            ? DateTime.tryParse(data['scannedAt'].toString())
            : null;
        _message = 'Already scanned for food';
      });
      _soundService.playError();
      return;
    }

    if (data['full'] == true) {
      final stats = data['stats'];
      setState(() {
        _result = _ScanResult.full;
        _attendee = null;
        if (stats is Map && stats['admitted'] != null) {
          _count = stats['admitted'];
        }
        _message = 'Session is at full capacity';
        _limitHit = true;
      });
      _soundService.playError();
      return;
    }

    setState(() {
      _result = _ScanResult.error;
      _attendee = null;
      _message = data['error']?.toString() ?? 'Scan failed';
    });
    _soundService.playError();
  }

  Color get _accentColor {
    switch (_result) {
      case _ScanResult.admitted:
        return Colors.green;
      case _ScanResult.already:
        return Colors.orange;
      case _ScanResult.full:
      case _ScanResult.error:
        return Colors.red;
      case _ScanResult.none:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(
          widget.session.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  case TorchState.off:
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
          _buildStatsHeader(),
          Expanded(
            child: _limitHit
                ? _buildLimitHitView()
                : MobileScanner(
                    controller: cameraController,
                    onDetect: _processBarcode,
                  ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final pct = _maxLimit > 0 ? (_count / _maxLimit).clamp(0.0, 1.0) : 0.0;
    final remainingToMax = (_maxLimit - _count) < 0 ? 0 : (_maxLimit - _count);
    final remainingToLimit = (_limit - _count) < 0 ? 0 : (_limit - _count);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_count / $_maxLimit admitted',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$remainingToMax spots left',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                _count >= _maxLimit
                    ? Colors.red
                    : _count >= _limit
                        ? Colors.orange
                        : Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Limit $_limit • $remainingToLimit to limit',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Bottom status bar — mirrors the attendance scanner: camera stays live,
  // the result/status shows here at the bottom.
  Widget _buildStatusBar() {
    final softReached = _count >= _limit && _limit > 0;
    final leftToHard = (_maxLimit - _count) < 0 ? 0 : (_maxLimit - _count);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_result == _ScanResult.none) ...[
            Text(
              _isProcessing ? 'Processing…' : 'Align attendee QR in the frame',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            const Text(
              'Each attendee can be admitted only once per event',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon, color: _accentColor, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _attendee?['name']?.toString() ??
                            (_result == _ScanResult.full ? 'Session full' : 'Scan failed'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _attendee?['regNo'] != null ? '${_attendee!['regNo']} • $_message' : _message,
                        style: TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      if (_result == _ScanResult.already && _scannedSessionName != null)
                        Text(
                          'Previously at: $_scannedSessionName'
                          '${_scannedAt != null ? ' • ${DateFormat('MMM d, h:mm a').format(_scannedAt!.toLocal())}' : ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Soft-limit notice — shown on every scan once the soft limit is hit.
            if (_result == _ScanResult.admitted && softReached) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Soft limit reached • $leftToHard left to hard limit',
                        style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLimitHitView() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.block, size: 56, color: Colors.red),
          ),
          const SizedBox(height: 24),
          const Text(
            'Hard Limit Reached',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.session.name} is full ($_maxLimit / $_maxLimit). The scanner has been closed.',
            style: const TextStyle(color: Colors.grey, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Back to Sessions'),
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon {
    switch (_result) {
      case _ScanResult.admitted:
        return Icons.check_circle;
      case _ScanResult.already:
        return Icons.info;
      case _ScanResult.full:
        return Icons.block;
      case _ScanResult.error:
        return Icons.error_outline;
      case _ScanResult.none:
        return Icons.qr_code_scanner;
    }
  }
}
