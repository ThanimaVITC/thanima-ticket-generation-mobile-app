import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pool_entry.dart';
import '../services/api_service.dart';

/// Everyone who has used the User Pool for this event — current members
/// included, marked as still inside.
class UserPoolHistoryScreen extends StatefulWidget {
  final String eventId;

  const UserPoolHistoryScreen({super.key, required this.eventId});

  @override
  State<UserPoolHistoryScreen> createState() => _UserPoolHistoryScreenState();
}

class _UserPoolHistoryScreenState extends State<UserPoolHistoryScreen> {
  final ApiService _apiService = ApiService();

  List<PoolEntry> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cached = ApiService.peek('pool:${widget.eventId}:all');
    if (cached is List) {
      _entries = cached
          .map((e) => PoolEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _isLoading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_entries.isEmpty) _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiService.getUserPool(widget.eventId, activeOnly: false);
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

  @override
  Widget build(BuildContext context) {
    final uniqueUsers = _entries.map((e) => e.email).toSet().length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Pool History',
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
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF1E293B),
            child: Text(
              '$uniqueUsers people  ·  ${_entries.length} visits',
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ),
          Expanded(child: _buildBody()),
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
            Icon(Icons.history_toggle_off, color: Colors.grey, size: 56),
            SizedBox(height: 16),
            Center(
              child: Text('Nobody has used the pool yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
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
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildRow(_entries[index]),
      ),
    );
  }

  Widget _buildRow(PoolEntry entry) {
    final inPool = entry.isInPool;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (inPool ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  inPool ? 'IN POOL' : entry.formattedTimeInPool,
                  style: TextStyle(
                    color: inPool ? Colors.green : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.regNo.isEmpty ? entry.email : entry.regNo,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '${DateFormat('MMM d, h:mm a').format(entry.enteredAt)}'
            '${entry.exitedAt != null ? '  →  ${DateFormat('h:mm a').format(entry.exitedAt!)}' : '  →  still inside'}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
