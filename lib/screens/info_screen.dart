import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  static const String _supportEmail = 'tech@thanimavitc.site';

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('Thanima App — Feedback / Issue')}',
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('How it works', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'A quick guide to everything on an event page.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),

          _section('Actions'),
          _item(
            Icons.qr_code_scanner,
            Colors.orangeAccent,
            'Scan QR',
            "Open the camera and scan an attendee's ticket QR to mark them present.",
          ),
          _item(
            Icons.verified_user,
            Colors.indigoAccent,
            'Verify Ticket',
            'Scan a ticket to check it is valid and see the holder’s details — without marking attendance.',
          ),
          _item(
            Icons.how_to_reg,
            Colors.blueAccent,
            'Manual',
            'Search by name or registration number and mark attendance by hand (when a QR can’t be scanned).',
          ),
          _item(
            Icons.groups,
            Colors.tealAccent,
            'Attendees',
            'Browse every registration with its attendance status, and search the list.',
          ),
          _item(
            Icons.qr_code_2,
            Colors.purpleAccent,
            'Assign Tickets',
            'Generate and assign QR ticket codes to registered users.',
          ),
          _item(
            Icons.restaurant,
            Colors.pinkAccent,
            'Food Sessions',
            'Scan attendees into food-hall sessions so each person gets food only once. Appears only when food sessions are enabled for the event.',
          ),

          const SizedBox(height: 16),
          _section('Stats'),
          _item(
            Icons.people,
            Colors.blue,
            'Registrations',
            'Total number of people registered for this event.',
          ),
          _item(
            Icons.event_available,
            Colors.green,
            'Attendance',
            'How many registrants have been marked present so far.',
          ),
          _item(
            Icons.percent,
            Colors.purple,
            'Attendance Rate',
            'Percentage of registered users who have attended.',
          ),
          _item(
            Icons.restaurant_menu,
            Colors.pink,
            'Food Scanned',
            'Percentage of users who have been scanned into a food session — i.e., how many have eaten.',
          ),

          const SizedBox(height: 16),
          _section('Support'),
          Material(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _contactSupport,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, color: Colors.purpleAccent, size: 24),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Need help?',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'For any issues, updates or feature requests about the app, contact $_supportEmail',
                            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new, color: Colors.grey, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
      ),
    );
  }

  Widget _item(IconData icon, Color color, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
