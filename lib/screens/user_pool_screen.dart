import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pool_entry.dart';
import '../services/api_service.dart';
import '../services/nfc_service.dart';
import '../services/sound_service.dart';
import 'user_pool_add_screen.dart';

class UserPoolScreen extends StatefulWidget {
  final String eventId;

  const UserPoolScreen({super.key, required this.eventId});

  @override
  State<UserPoolScreen> createState() => _UserPoolScreenState();
}

class _UserPoolScreenState extends State<UserPoolScreen> {
  final ApiService _apiService = ApiService();
  final NfcService _nfcService = NfcService();

  List<PoolEntry> _entries = [];
  bool _isLoading = true;
  String? _error;
  Timer? _ticker;

  // Null means NFC is usable. Anything else is the reason it isn't, and both
  // Add and Remove are disabled — the list itself stays fully readable.
  String? _nfcReason;

  @override
  void initState() {
    super.initState();
    // Seed from cache for an instant render, then refresh in the background.
    final cached = ApiService.peek('pool:${widget.eventId}:active');
    if (cached is List) {
      _entries = cached
          .map((e) => PoolEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _isLoading = false;
    }
    _load();
    // One ticker drives every "time in pool" cell — no re-fetching.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_entries.isEmpty) _isLoading = true;
      _error = null;
    });

    // Re-checked on every load so flipping NFC on in system settings and
    // pulling to refresh is enough to unlock the buttons.
    final reason = await _nfcService.unavailableReason();
    if (mounted) setState(() => _nfcReason = reason);

    try {
      final data = await _apiService.getUserPool(widget.eventId, activeOnly: true);
      if (!mounted) return;
      setState(() {
        _entries = data.map((e) => PoolEntry.fromJson(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _openAdd() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserPoolAddScreen(eventId: widget.eventId),
      ),
    ).then((_) => _load());
  }

  // The whole remove flow lives inside one sheet that owns its own context and
  // pops itself — scan the card, show who it is, confirm or cancel.
  Future<void> _openRemove() async {
    final removedName = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => _RemoveSheet(eventId: widget.eventId),
    );

    if (!mounted) return;
    if (removedName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(removedName), backgroundColor: Colors.green),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('User Pool',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1E293B),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${_entries.length}',
            style: const TextStyle(
                color: Colors.purpleAccent,
                fontSize: 36,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 10),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('in the pool',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Icon(Icons.group_off, color: Colors.grey, size: 56),
            SizedBox(height: 16),
            Center(
              child: Text('Nobody is in the pool',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            SizedBox(height: 8),
            Center(
              child: Text('Use Add User to scan a ticket and an ID card',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
            columns: const [
              DataColumn(
                  label: Text('Name', style: TextStyle(color: Colors.grey))),
              DataColumn(
                  label: Text('Reg No', style: TextStyle(color: Colors.grey))),
              DataColumn(
                  label: Text('Number', style: TextStyle(color: Colors.grey))),
              DataColumn(
                  label: Text('Added', style: TextStyle(color: Colors.grey))),
              DataColumn(
                  label: Text('Time in', style: TextStyle(color: Colors.grey))),
            ],
            rows: _entries
                .map(
                  (e) => DataRow(
                    cells: [
                      DataCell(Text(e.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(e.regNo.isEmpty ? '—' : e.regNo,
                          style: const TextStyle(color: Colors.grey))),
                      DataCell(Text(e.phone.isEmpty ? '—' : e.phone,
                          style: const TextStyle(color: Colors.grey))),
                      DataCell(Text(DateFormat('h:mm a').format(e.enteredAt),
                          style: const TextStyle(color: Colors.grey))),
                      DataCell(Text(e.formattedTimeInPool,
                          style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold))),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    // Both actions need to read an ID card, so without NFC they are dead
    // weight. Disabling (rather than hiding) keeps it obvious *why* the door
    // flow is unavailable on this phone.
    final nfcOk = _nfcReason == null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!nfcOk) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.contactless_outlined,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nfcReason!,
                        style: const TextStyle(color: Colors.orange, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: nfcOk ? _openAdd : null,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: nfcOk ? _openRemove : null,
                    icon: const Icon(Icons.person_remove_alt_1),
                    label: const Text('Remove User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _RemoveStage { scanning, confirming, removing, failed }

/// Scan an ID card, show whose stay it is and how long it has run, then remove
/// or cancel. Pops with a success message string, or null if cancelled.
class _RemoveSheet extends StatefulWidget {
  final String eventId;

  const _RemoveSheet({required this.eventId});

  @override
  State<_RemoveSheet> createState() => _RemoveSheetState();
}

class _RemoveSheetState extends State<_RemoveSheet> {
  final ApiService _apiService = ApiService();
  final NfcService _nfcService = NfcService();
  final SoundService _soundService = SoundService();

  _RemoveStage _stage = _RemoveStage.scanning;
  PoolEntry? _entry;
  String _message = '';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nfcService.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _stage = _RemoveStage.scanning;
      _entry = null;
      _message = '';
    });

    String cardId;
    try {
      cardId = await _nfcService.readCardId();
    } on NfcFailure catch (e) {
      if (!mounted) return;
      _soundService.playError();
      setState(() {
        _stage = _RemoveStage.failed;
        _message = e.message;
      });
      return;
    }

    final result = await _apiService.lookupPoolByNfc(widget.eventId, cardId);
    if (!mounted) return;

    final data = Map<String, dynamic>.from(result['data'] ?? {});
    if (result['statusCode'] != 200 || data['found'] != true) {
      _soundService.playError();
      setState(() {
        _stage = _RemoveStage.failed;
        _message = data['error']?.toString() ?? 'This ID card is not in the pool';
      });
      return;
    }

    _soundService.playSuccess();
    setState(() {
      _entry = PoolEntry.fromJson(Map<String, dynamic>.from(data['entry']));
      _stage = _RemoveStage.confirming;
    });
    // Keep "time in pool" counting up while staff decide.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _remove() async {
    final entry = _entry;
    if (entry == null) return;

    setState(() => _stage = _RemoveStage.removing);

    final result = await _apiService.removeFromUserPool(widget.eventId, entry.id);
    if (!mounted) return;

    final data = Map<String, dynamic>.from(result['data'] ?? {});
    if (result['statusCode'] == 200 && data['ok'] == true) {
      _soundService.playSuccess();
      final ms = (data['durationMs'] as num?)?.toInt() ?? 0;
      Navigator.of(context).pop(
        '${entry.name} removed after ${PoolEntry.format(Duration(milliseconds: ms))}',
      );
      return;
    }

    _soundService.playError();
    setState(() {
      _stage = _RemoveStage.failed;
      _message = data['error']?.toString() ?? 'Could not remove this user';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: switch (_stage) {
        _RemoveStage.scanning => _buildScanning(),
        _RemoveStage.failed => _buildFailed(),
        _RemoveStage.confirming || _RemoveStage.removing => _buildConfirm(),
      },
    );
  }

  Widget _buildScanning() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.contactless, size: 56, color: Colors.purpleAccent),
        const SizedBox(height: 16),
        const Text(
          'Tap the ID card',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hold the card against the back of the phone',
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 56, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          _message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _scan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Scan again'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirm() {
    final entry = _entry!;
    final isRemoving = _stage == _RemoveStage.removing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.name,
          style: const TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _detailRow(Icons.badge, 'Reg No', entry.regNo.isEmpty ? '—' : entry.regNo),
        _detailRow(Icons.phone, 'Number', entry.phone.isEmpty ? '—' : entry.phone),
        _detailRow(Icons.login, 'Added at',
            DateFormat('MMM d, h:mm a').format(entry.enteredAt)),
        _detailRow(Icons.timer, 'Time in pool', entry.formattedTimeInPool,
            highlight: true),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isRemoving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isRemoving ? null : _remove,
                icon: isRemoving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.logout),
                label: Text(isRemoving ? 'Removing…' : 'Remove'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.purpleAccent : Colors.white,
              fontSize: 15,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
