import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';

class AssignTicketScreen extends StatefulWidget {
  final String eventId;

  const AssignTicketScreen({super.key, required this.eventId});

  @override
  State<AssignTicketScreen> createState() => _AssignTicketScreenState();
}

class _AssignTicketScreenState extends State<AssignTicketScreen> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  List<Map<String, dynamic>> _registrations = [];
  List<Map<String, dynamic>> _filteredRegistrations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Map<String, dynamic>? _selectedRegistration;
  MobileScannerController? _cameraController;
  bool _isScanning = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
  }

  Future<void> _loadRegistrations({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final registrations = await _apiService.getRegistrations(widget.eventId);
      setState(() {
        _registrations = registrations;
        _filteredRegistrations = registrations.where((reg) {
          final name = (reg['name'] ?? '').toString().toLowerCase();
          final regNo = (reg['regNo'] ?? '').toString().toLowerCase();
          final email = (reg['email'] ?? '').toString().toLowerCase();
          final query = _searchQuery.toLowerCase();
          return name.contains(query) ||
              regNo.contains(query) ||
              email.contains(query);
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterRegistrations(String query) {
    setState(() {
      _searchQuery = query;
      _filteredRegistrations = _registrations.where((reg) {
        final name = (reg['name'] ?? '').toString().toLowerCase();
        final regNo = (reg['regNo'] ?? '').toString().toLowerCase();
        final email = (reg['email'] ?? '').toString().toLowerCase();
        final lowerQuery = query.toLowerCase();
        return name.contains(lowerQuery) ||
            regNo.contains(lowerQuery) ||
            email.contains(lowerQuery);
      }).toList();
    });
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _isProcessing = false;
      _cameraController = MobileScannerController();
    });
  }

  void _stopScanning() {
    _cameraController?.dispose();
    setState(() {
      _isScanning = false;
      _isProcessing = false;
      _cameraController = null;
    });
  }

  Future<void> _processQrCode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue == null || _selectedRegistration == null) continue;

      setState(() {
        _isProcessing = true;
      });

      // Stop camera immediately after detection
      await _cameraController?.stop();

      final qrPayload = barcode.rawValue!;

      try {
        final existingAssignment = await _apiService.checkQrPayloadExists(
          widget.eventId,
          qrPayload,
        );

        if (existingAssignment != null) {
          _soundService.playError();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'This ticket is already assigned to ${existingAssignment['name'] ?? 'someone else'}',
              ),
              backgroundColor: Colors.red,
            ),
          );
          // Restart camera to allow scanning another ticket
          setState(() {
            _isProcessing = false;
          });
          await _cameraController?.start();
          continue;
        }

        await _apiService.assignQrPayload(
          widget.eventId,
          _selectedRegistration?['_id'] ?? '',
          qrPayload,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ticket assigned to ${_selectedRegistration?['name'] ?? 'User'}',
              ),
              backgroundColor: Colors.green,
            ),
          );

          _soundService.playSuccess();

          _stopScanning();
          setState(() {
            _selectedRegistration = null;
          });

          await _loadRegistrations(showLoading: false);
        }
      } catch (e) {
        _soundService.playError();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
        // Restart camera on error
        setState(() {
          _isProcessing = false;
        });
        await _cameraController?.start();
      }
      break;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Assign Tickets',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadRegistrations(),
          ),
        ],
      ),
      body: _isScanning ? _buildScannerView() : _buildListView(),
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: _filterRegistrations,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by name, reg no, or email',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredRegistrations.isEmpty
              ? const Center(
                  child: Text(
                    'No registrations found',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredRegistrations.length,
                  itemBuilder: (context, index) {
                    final reg = _filteredRegistrations[index];
                    final hasQrPayload =
                        reg['qrPayload'] != null &&
                        reg['qrPayload'].toString().isNotEmpty;
                    final isSelected =
                        _selectedRegistration?['_id'] == reg['_id'];

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.purple
                              : hasQrPayload
                              ? Colors.green.withOpacity(0.3)
                              : Colors.white.withOpacity(0.05),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          reg['name'] ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reg['regNo'] ?? '',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              reg['email'] ?? '',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: hasQrPayload
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.qr_code,
                                  color: Colors.orange,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedRegistration = reg;
                                  });
                                  _startScanning();
                                },
                              ),
                        onTap: () {
                          setState(() {
                            _selectedRegistration = reg;
                          });
                          if (!hasQrPayload) {
                            _startScanning();
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        if (_selectedRegistration != null &&
            (_selectedRegistration!['qrPayload'] == null ||
                _selectedRegistration!['qrPayload'].toString().isEmpty))
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Selected',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        _selectedRegistration?['name'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _startScanning,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildScannerView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _cameraController,
                onDetect: _processQrCode,
              ),
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  onPressed: _stopScanning,
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedRegistration != null
                    ? 'Assigning to: ${_selectedRegistration?['name'] ?? 'Unknown'}'
                    : 'Select a user first',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_isProcessing)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                )
              else
                const Text(
                  'Scan the QR code from the user\'s ticket',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
