import 'package:flutter/material.dart';
import '../models/registration.dart';
import '../services/api_service.dart';

class ManualAttendanceScreen extends StatefulWidget {
  final String eventId;

  const ManualAttendanceScreen({super.key, required this.eventId});

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<Registration> _registrations = [];
  List<Registration> _filteredRegistrations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
    _searchController.addListener(_filterRegistrations);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRegistrations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await _apiService.getEventDetails(widget.eventId);
      final List<dynamic> regsData = details['registrations'];
      
      setState(() {
        _registrations = regsData.map((r) => Registration.fromJson(r)).toList();
        _filterRegistrations();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterRegistrations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredRegistrations = List.from(_registrations);
      } else {
        _filteredRegistrations = _registrations.where((reg) {
          return reg.name.toLowerCase().contains(query) ||
                 reg.regNo.toLowerCase().contains(query) ||
                 reg.email.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _markAttendance(Registration reg) async {
    try {
      await _apiService.markAttendance(widget.eventId, reg.email);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked attendance for ${reg.name}'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Update local state instead of reloading everything
      final index = _registrations.indexWhere((r) => r.id == reg.id);
      if (index != -1) {
        // Create new registration object with attended = true
        // Since fields are final, we can't just set attended = true
        // In a real app we might reload or use more complex state management
        // For now, let's reload to be safe and simple
        _loadRegistrations();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Manual Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E293B),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by Name, Reg No, or Email',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
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
                    : _filteredRegistrations.isEmpty
                        ? const Center(
                            child: Text(
                              'No attendees found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredRegistrations.length,
                            itemBuilder: (context, index) {
                              final reg = _filteredRegistrations[index];
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
                                    ],
                                  ),
                                  trailing: reg.attended
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.green.withOpacity(0.5)),
                                          ),
                                          child: const Text(
                                            'Attended',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: () => _markAttendance(reg),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.purple,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                          ),
                                          child: const Text('Mark'),
                                        ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
