import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import 'event_detail_screen.dart';
import 'profile_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late Future<List<Event>> _eventsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _refreshEvents();
  }

  void _refreshEvents() {
    setState(() {
      _eventsFuture = _apiService.getEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Events',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Event>>(
        future: _eventsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshEvents,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No events found',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _refreshEvents();
              await _eventsFuture;
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final event = snapshot.data![index];
                return _buildEventCard(event);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventCard(Event event) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF1E293B), // Slate 800
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventDetailScreen(eventId: event.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (event.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  event.description!,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Colors.purple,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM d, y • h:mm a').format(event.date),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              if (event.location != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.purple,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.location!,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
