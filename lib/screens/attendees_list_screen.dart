import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/registration.dart';
import '../services/api_service.dart';

class AttendeesListScreen extends StatefulWidget {
  final String eventId;

  const AttendeesListScreen({super.key, required this.eventId});

  @override
  State<AttendeesListScreen> createState() => _AttendeesListScreenState();
}

class _AttendeesListScreenState extends State<AttendeesListScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  List<Registration> _allRegistrations = [];
  List<Registration> _attendedRegistrations = [];
  List<Registration> _pendingRegistrations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Seed from cache for an instant render, then refresh in the background.
    final cached = ApiService.peek('event:${widget.eventId}');
    if (cached is Map<String, dynamic>) {
      _applyDetails(cached);
      _isLoading = false;
    }
    _loadRegistrations();
  }

  void _applyDetails(Map<String, dynamic> details) {
    final List<dynamic> regsData = details['registrations'] ?? [];
    final all = regsData.map((r) => Registration.fromJson(r)).toList();
    _allRegistrations = all;
    _attendedRegistrations = all.where((r) => r.attended).toList();
    _pendingRegistrations = all.where((r) => !r.attended).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRegistrations() async {
    setState(() {
      if (_allRegistrations.isEmpty) _isLoading = true;
      _error = null;
    });

    try {
      final details = await _apiService.getEventDetails(widget.eventId);
      if (!mounted) return;
      setState(() {
        _applyDetails(details);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Attendees', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purple,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: 'All (${_allRegistrations.length})'),
            Tab(text: 'Attended (${_attendedRegistrations.length})'),
            Tab(text: 'Pending (${_pendingRegistrations.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRegistrations,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_allRegistrations),
                    _buildList(_attendedRegistrations),
                    _buildList(_pendingRegistrations),
                  ],
                ),
    );
  }

  Widget _buildList(List<Registration> registrations) {
    if (registrations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRegistrations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 200),
            Center(
              child: Text(
                'No attendees found',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRegistrations,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: registrations.length,
      itemBuilder: (context, index) {
        final reg = registrations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              reg.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  reg.regNo,
                  style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
                ),
                Text(
                  reg.email,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                if (reg.attended && reg.markedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Marked: ${DateFormat('h:mm a').format(reg.markedAt!)}',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
              ],
            ),
            trailing: reg.attended
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.circle_outlined, color: Colors.grey),
          ),
        );
      },
    ),
  );
}
}
