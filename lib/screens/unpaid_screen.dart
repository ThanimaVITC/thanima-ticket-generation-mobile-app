import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/unpaid_entry.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';
import 'unpaid_scan_screen.dart';

class UnpaidScreen extends StatefulWidget {
  final String eventId;

  const UnpaidScreen({super.key, required this.eventId});

  @override
  State<UnpaidScreen> createState() => _UnpaidScreenState();
}

class _UnpaidScreenState extends State<UnpaidScreen> {
  final ApiService _apiService = ApiService();

  final _searchController = TextEditingController();

  List<UnpaidEntry> _entries = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Show whatever we already have immediately, then refresh behind it.
    // In-memory first (same session), disk second (after a cold start).
    final cached = ApiService.peek('unpaid:${widget.eventId}');
    if (cached is List) {
      _entries = cached
          .map((e) => UnpaidEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _isLoading = false;
    } else {
      _seedFromDisk();
    }
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _seedFromDisk() async {
    final stored = await _apiService.readPersistedList('unpaid:${widget.eventId}');
    // The network may already have won the race — don't clobber fresher data.
    if (!mounted || stored == null || _entries.isNotEmpty) return;
    setState(() {
      _entries = stored.map((e) => UnpaidEntry.fromJson(e)).toList();
      _isLoading = false;
    });
  }

  List<UnpaidEntry> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.regNo.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      if (_entries.isEmpty) _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiService.getUnpaid(widget.eventId);
      if (!mounted) return;
      setState(() {
        _entries = data.map((e) => UnpaidEntry.fromJson(e)).toList();
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

  void _openScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UnpaidScanScreen(eventId: widget.eventId),
      ),
    ).then((_) => _load());
  }

  Future<void> _openManualAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      builder: (_) => _ManualAddSheet(eventId: widget.eventId),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Unpaid',
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Text(
                  '${_visible.length}',
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 30,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                const Text('unpaid',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Name or reg no',
                        hintStyle:
                            const TextStyle(color: Colors.white38, fontSize: 14),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white38, size: 18),
                        prefixIconConstraints: const BoxConstraints(
                            minWidth: 34, minHeight: 34),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white38, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.amberAccent),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
          _buildActions(),
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

    final visible = _visible;

    if (visible.isEmpty) {
      final searching = _query.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Icon(searching ? Icons.search_off : Icons.playlist_add_check,
                color: Colors.grey, size: 56),
            const SizedBox(height: 16),
            Center(
              child: Text(
                searching ? 'No match for "${_query.trim()}"' : 'Nobody on the unpaid list',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                searching
                    ? 'Search matches name and registration number'
                    : 'Scan an ID card or add someone manually',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildRow(visible[index]),
      ),
    );
  }

  Widget _buildRow(UnpaidEntry entry) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  entry.regNo,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 14,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                entry.source == 'ocr' ? Icons.badge : Icons.edit_note,
                color: Colors.white24,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, h:mm a').format(entry.createdAt),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openManualAdd,
                icon: const Icon(Icons.edit_note),
                label: const Text('Add Manually'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openScan,
                icon: const Icon(Icons.document_scanner),
                label: const Text('Scan ID Card'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Type a name and reg no by hand. Pops true when something was added.
class _ManualAddSheet extends StatefulWidget {
  final String eventId;

  const _ManualAddSheet({required this.eventId});

  @override
  State<_ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<_ManualAddSheet> {
  final ApiService _apiService = ApiService();
  final SoundService _soundService = SoundService();
  final _nameController = TextEditingController();
  final _regNoController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _regNoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await _apiService.addUnpaid(
      widget.eventId,
      _nameController.text,
      _regNoController.text,
      source: 'manual',
    );
    if (!mounted) return;

    final data = Map<String, dynamic>.from(result['data'] ?? {});
    final status = result['statusCode'] as int? ?? 0;

    if (status == 201 || data['ok'] == true) {
      _soundService.playSuccess();
      Navigator.of(context).pop(true);
      return;
    }

    _soundService.playError();
    setState(() {
      _saving = false;
      _error = data['error']?.toString() ?? 'Could not add this person';
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add to unpaid list',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Name', 'Arjun Menon'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regNoController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: _fieldDecoration('Registration Number', '23BCE1042'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_saving ? 'Adding…' : 'Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.grey),
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.amberAccent),
      ),
    );
  }
}
