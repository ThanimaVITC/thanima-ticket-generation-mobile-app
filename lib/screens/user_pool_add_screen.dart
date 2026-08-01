import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/nfc_service.dart';
import '../services/sound_service.dart';

// Ticket -> confirm who it is -> ID card -> server.
enum _Step { scanTicket, verifying, confirmUser, tapCard, submitting, done }

enum _Outcome { added, alreadyInPool, cardInUse, error }

class UserPoolAddScreen extends StatefulWidget {
  final String eventId;

  const UserPoolAddScreen({super.key, required this.eventId});

  @override
  State<UserPoolAddScreen> createState() => _UserPoolAddScreenState();
}

class _UserPoolAddScreenState extends State<UserPoolAddScreen> {
  final ApiService _apiService = ApiService();
  final NfcService _nfcService = NfcService();
  final SoundService _soundService = SoundService();
  final MobileScannerController _cameraController = MobileScannerController();

  _Step _step = _Step.scanTicket;
  _Outcome? _outcome;

  String? _ticketPayload;
  Map<String, dynamic>? _ticket; // resolved from the QR, shown before the tap
  String _message = '';
  String _detail = '';
  Map<String, dynamic>? _entry;

  @override
  void dispose() {
    _cameraController.dispose();
    _nfcService.cancel();
    super.dispose();
  }

  Future<void> _onBarcode(BarcodeCapture capture) async {
    if (_step != _Step.scanTicket) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      await _cameraController.stop();
      if (!mounted) return;
      setState(() {
        _ticketPayload = raw;
        _step = _Step.verifying;
      });
      _verifyTicket();
      return;
    }
  }

  // Resolve the QR to a person so staff can eyeball the name before asking for
  // the card. Failing here (wrong event, unknown ticket) is much cheaper to
  // recover from than failing after the tap.
  Future<void> _verifyTicket() async {
    try {
      final result = await _apiService.verifyTicket(
        _ticketPayload!,
        widget.eventId,
      );
      if (!mounted) return;
      _soundService.playSuccess();
      setState(() {
        _ticket = Map<String, dynamic>.from(result['ticket'] ?? {});
        _step = _Step.confirmUser;
      });
    } catch (e) {
      if (!mounted) return;
      _soundService.playError();
      _finish(_Outcome.error, e.toString().replaceAll('Exception: ', ''), '');
    }
  }

  Future<void> _readCard() async {
    setState(() => _step = _Step.tapCard);

    String cardId;
    try {
      cardId = await _nfcService.readCardId();
    } on NfcFailure catch (e) {
      if (!mounted) return;
      _soundService.playError();
      _finish(_Outcome.error, e.message, '');
      return;
    }

    if (!mounted) return;
    setState(() => _step = _Step.submitting);

    final result = await _apiService.addToUserPool(
      widget.eventId,
      _ticketPayload!,
      cardId,
    );
    if (!mounted) return;

    final data = Map<String, dynamic>.from(result['data'] ?? {});

    if (result['statusCode'] == 200 && data['ok'] == true) {
      _soundService.playSuccess();
      final entry = Map<String, dynamic>.from(data['entry'] ?? {});
      setState(() => _entry = entry);
      _finish(
        _Outcome.added,
        '${entry['name'] ?? 'User'} added to the pool',
        '${entry['regNo'] ?? ''}  ·  ${data['currentCount'] ?? '?'} now inside',
      );
      return;
    }

    _soundService.playError();

    if (data['alreadyInPool'] == true) {
      final entry = Map<String, dynamic>.from(data['entry'] ?? {});
      setState(() => _entry = entry);
      _finish(
        _Outcome.alreadyInPool,
        '${entry['name'] ?? 'This user'} is already in the pool',
        'Remove them first if they left without scanning out.',
      );
      return;
    }

    if (data['cardInUse'] == true) {
      final holder = data['holder'] is Map
          ? Map<String, dynamic>.from(data['holder'])
          : null;
      _finish(
        _Outcome.cardInUse,
        'This ID card is already in the pool',
        holder != null
            ? 'Held by ${holder['name']} (${holder['regNo'] ?? '—'})'
            : 'It belongs to another active member.',
      );
      return;
    }

    _finish(
      _Outcome.error,
      data['error']?.toString() ?? 'Could not add this user',
      data['wrongEvent'] == true ? 'That ticket belongs to a different event.' : '',
    );
  }

  void _finish(_Outcome outcome, String message, String detail) {
    setState(() {
      _step = _Step.done;
      _outcome = outcome;
      _message = message;
      _detail = detail;
    });
  }

  Future<void> _reset() async {
    setState(() {
      _step = _Step.scanTicket;
      _outcome = null;
      _ticketPayload = null;
      _ticket = null;
      _message = '';
      _detail = '';
      _entry = null;
    });
    await _cameraController.start();
  }

  Color get _outcomeColor {
    switch (_outcome) {
      case _Outcome.added:
        return Colors.green;
      case _Outcome.alreadyInPool:
        return Colors.orange;
      case _Outcome.cardInUse:
      case _Outcome.error:
      case null:
        return Colors.red;
    }
  }

  IconData get _outcomeIcon {
    switch (_outcome) {
      case _Outcome.added:
        return Icons.check_circle;
      case _Outcome.alreadyInPool:
        return Icons.info;
      case _Outcome.cardInUse:
        return Icons.credit_card_off;
      case _Outcome.error:
      case null:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Add to Pool',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: _step == _Step.scanTicket
            ? [
                IconButton(
                  color: Colors.white,
                  icon: ValueListenableBuilder(
                    valueListenable: _cameraController,
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
                  onPressed: () => _cameraController.toggleTorch(),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(child: _buildStage()),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    final ticketDone = _step != _Step.scanTicket && _step != _Step.verifying;
    final cardActive = _step == _Step.tapCard || _step == _Step.submitting;
    final cardDone = _step == _Step.done && _outcome == _Outcome.added;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          _stepChip('1  Ticket', ticketDone, !ticketDone),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          ),
          const SizedBox(width: 8),
          _stepChip('2  ID card', cardDone, cardActive),
        ],
      ),
    );
  }

  Widget _stepChip(String label, bool complete, bool active) {
    final color = complete
        ? Colors.green
        : active
            ? Colors.purpleAccent
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStage() {
    switch (_step) {
      case _Step.scanTicket:
        return Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _cameraController,
                onDetect: _onBarcode,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Scan the attendee\'s ticket QR first',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        );

      case _Step.verifying:
        return _centered(
          icon: Icons.qr_code_scanner,
          iconColor: Colors.purpleAccent,
          title: 'Checking the ticket…',
          subtitle: '',
          child: const Padding(
            padding: EdgeInsets.only(top: 24),
            child: CircularProgressIndicator(),
          ),
        );

      case _Step.confirmUser:
        return _buildConfirmUser();

      case _Step.tapCard:
        return _centered(
          icon: Icons.contactless,
          iconColor: Colors.purpleAccent,
          title: 'Tap the ID card',
          subtitle: _ticket?['name'] != null
              ? 'Hold ${_ticket!['name']}\'s card against the back of the phone'
              : 'Hold the card against the back of the phone',
          child: const Padding(
            padding: EdgeInsets.only(top: 24),
            child: CircularProgressIndicator(),
          ),
          action: TextButton(
            onPressed: _reset,
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        );

      case _Step.submitting:
        return _centered(
          icon: Icons.cloud_upload,
          iconColor: Colors.purpleAccent,
          title: 'Adding to the pool…',
          subtitle: '',
          child: const Padding(
            padding: EdgeInsets.only(top: 24),
            child: CircularProgressIndicator(),
          ),
        );

      case _Step.done:
        return _centered(
          icon: _outcomeIcon,
          iconColor: _outcomeColor,
          title: _message,
          subtitle: _detail,
          child: _entry != null && _outcome == _Outcome.alreadyInPool
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'In the pool since ${_entry!['enteredAt'] != null ? DateTime.parse(_entry!['enteredAt'].toString()).toLocal().toString().substring(11, 16) : '—'}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : null,
          action: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: const Text('Done'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Add another'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        );
    }
  }

  // Step 2 of 3: who the ticket belongs to, confirmed before the card is asked for.
  Widget _buildConfirmUser() {
    final t = _ticket ?? {};
    final attended = t['hasAttended'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 44, color: Colors.green),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t['name']?.toString() ?? 'Unknown',
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _detailRow(Icons.badge, 'Reg No', t['regNo']?.toString() ?? '—'),
                _detailRow(Icons.phone, 'Number', t['phone']?.toString() ?? '—'),
                _detailRow(Icons.mail_outline, 'Email', t['email']?.toString() ?? '—'),
                _detailRow(
                  attended ? Icons.check_circle : Icons.remove_circle_outline,
                  'Attendance',
                  attended ? 'Marked' : 'Not marked',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _readCard,
            icon: const Icon(Icons.contactless),
            label: const Text('Scan ID Card'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _centered({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? child,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
          ?child,
          if (action != null) ...[
            const SizedBox(height: 28),
            action,
          ],
        ],
      ),
    );
  }
}
