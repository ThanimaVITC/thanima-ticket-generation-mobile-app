import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/api_service.dart';
import 'qr_scan_screen.dart';
import 'manual_attendance_screen.dart';
import 'attendees_list_screen.dart';
import 'assign_ticket_screen.dart';
import 'verify_ticket_screen.dart';
import 'food_sessions_screen.dart';
import 'user_pool_screen.dart';
import 'user_pool_history_screen.dart';
import '../services/nfc_service.dart';
import 'info_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final ApiService _apiService = ApiService();
  final NfcService _nfcService = NfcService();
  late Future<Map<String, dynamic>> _eventDetailsFuture;

  // Null = NFC usable. The User Pool tile dims when this is set, since adding
  // and removing both need a card reader — the list stays viewable.
  String? _nfcReason;

  @override
  void initState() {
    super.initState();
    _refreshEventDetails();
    _checkNfc();
  }

  Future<void> _checkNfc() async {
    final reason = await _nfcService.unavailableReason();
    if (mounted) setState(() => _nfcReason = reason);
  }

  void _refreshEventDetails() {
    setState(() {
      _eventDetailsFuture = _apiService.getEventDetails(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Render the last cached payload instantly while a fresh one loads.
    final cached = ApiService.peek('event:${widget.eventId}') as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Event Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How it works',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InfoScreen()),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _eventDetailsFuture,
        initialData: cached,
        builder: (context, snapshot) {
          // Spinner only when there is nothing (no cache) to show yet.
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No data found'));
          }

          final eventData = snapshot.data!['event'];
          final stats = snapshot.data!['stats'] as Map<String, dynamic>;
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
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.purpleAccent),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, y • h:mm a').format(event.date),
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Stats
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Registrations', stats['totalRegistrations'].toString(), Colors.blue)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard('Attendance', stats['totalAttendance'].toString(), Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (event.foodSessionsEnabled)
                    Row(
                      children: [
                        Expanded(child: _buildStatCard('Attendance Rate', '${stats['attendanceRate']}%', Colors.purple)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard('Food Scanned', '${stats['foodScanRate'] ?? 0}%', Colors.pink)),
                      ],
                    )
                  else
                    _buildStatCard('Attendance Rate', '${stats['attendanceRate']}%', Colors.purple),

                  if (event.userPoolEnabled) ...[
                    const SizedBox(height: 16),
                    _buildStatCard('In Pool Now', '${stats['userPoolCount'] ?? 0}', Colors.cyanAccent),
                  ],

                  const SizedBox(height: 28),
                  const Text(
                    'ACTIONS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 12),

                  // Action grid (no per-item heavy card; clean tiles)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.2,
                    children: [
                      _actionTile('Scan QR', Icons.qr_code_scanner, Colors.orangeAccent,
                          () => _go(QrScanScreen(eventId: widget.eventId))),
                      _actionTile('Verify Ticket', Icons.verified_user, Colors.indigoAccent,
                          () => _go(VerifyTicketScreen(eventId: widget.eventId))),
                      _actionTile('Manual', Icons.how_to_reg, Colors.blueAccent,
                          () => _go(ManualAttendanceScreen(eventId: widget.eventId))),
                      _actionTile('Attendees', Icons.groups, Colors.tealAccent,
                          () => _go(AttendeesListScreen(eventId: widget.eventId))),
                      _actionTile('Assign Tickets', Icons.qr_code_2, Colors.purpleAccent,
                          () => _go(AssignTicketScreen(eventId: widget.eventId))),
                      if (event.foodSessionsEnabled)
                        _actionTile('Food Sessions', Icons.restaurant, Colors.pinkAccent,
                            () => _go(FoodSessionsScreen(eventId: widget.eventId))),
                      if (event.userPoolEnabled)
                        _actionTile('User Pool', Icons.group_add, Colors.cyanAccent,
                            () => _go(UserPoolScreen(eventId: widget.eventId)),
                            dimmed: _nfcReason != null),
                      if (event.userPoolEnabled)
                        _actionTile('Pool History', Icons.history, Colors.amberAccent,
                            () => _go(UserPoolHistoryScreen(eventId: widget.eventId))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => _refreshEventDetails());
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
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// [dimmed] marks a tile whose main actions are unavailable on this device.
  /// It stays tappable — the destination still has read-only value — but reads
  /// as inactive and carries a small "No NFC" marker.
  Widget _actionTile(String title, IconData icon, Color color, VoidCallback onTap,
      {bool dimmed = false}) {
    return Material(
      color: dimmed ? const Color(0xFF17212F) : const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: dimmed ? 0.03 : 0.06)),
          ),
          child: Row(
            children: [
              Icon(icon, color: dimmed ? Colors.white24 : color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          color: dimmed ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dimmed)
                      const Text(
                        'No NFC · view only',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
