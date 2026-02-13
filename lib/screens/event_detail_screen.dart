import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/api_service.dart';
import 'qr_scan_screen.dart';
import 'manual_attendance_screen.dart';
import 'attendees_list_screen.dart';
import 'assign_ticket_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final ApiService _apiService = ApiService();
  late Future<Map<String, dynamic>> _eventDetailsFuture;

  @override
  void initState() {
    super.initState();
    _refreshEventDetails();
  }

  void _refreshEventDetails() {
    setState(() {
      _eventDetailsFuture = _apiService.getEventDetails(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Event Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _eventDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No data found'));
          }

          final eventData = snapshot.data!['event'];
          final stats = snapshot.data!['stats'];
          final event = Event.fromJson(eventData);

          return RefreshIndicator(
            onRefresh: () async {
              _refreshEventDetails();
              await _eventDetailsFuture;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Info
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, y • h:mm a').format(event.date),
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Registrations',
                          stats['totalRegistrations'].toString(),
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          'Attendance',
                          stats['totalAttendance'].toString(),
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStatCard(
                    'Attendance Rate',
                    '${stats['attendanceRate']}%',
                    Colors.purple,
                  ),
                  
                  const SizedBox(height: 40),
                  const Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  _buildActionTile(
                    'Scan QR Code',
                    'Scan attendee QR code to mark attendance',
                    Icons.qr_code_scanner,
                    Colors.orange,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QrScanScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _refreshEventDetails()),
                  ),

                  const SizedBox(height: 16),
                  _buildActionTile(
                    'Assign Tickets',
                    'Assign QR tickets to registered users',
                    Icons.qr_code,
                    Colors.purple,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AssignTicketScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _refreshEventDetails()),
                  ),
                  
                  _buildActionTile(
                    'Manual Attendance',
                    'Mark attendance by searching name/reg no',
                    Icons.edit_note,
                    Colors.blue,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ManualAttendanceScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _refreshEventDetails()),
                  ),
                  
                  _buildActionTile(
                    'View Attendees',
                    'List all registrations and attendance status',
                    Icons.people,
                    Colors.teal,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AttendeesListScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _refreshEventDetails()),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }
}
