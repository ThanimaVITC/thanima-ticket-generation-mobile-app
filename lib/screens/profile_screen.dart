import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const String _version = 'v2.0.1';
  static const String _githubUrl =
      'https://github.com/ThanimaVITC/thanima-ticket-generation-mobile-app';
  static const String _supportEmail = 'tech@thanimavitc.site';
  static const String _websiteUrl = 'https://thanimavitc.site';
  static const String _appPageUrl =
      'https://thanimavitc.github.io/thanima-ticket-generation-mobile-app/';

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('Thanima App — Feedback / Issue')}',
    );
    await launchUrl(uri);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _linkButton(IconData icon, String label, String url) {
    return Material(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _launchUrl(url),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFF6366F1),
                      child: Text(
                        user?.name.isNotEmpty == true
                            ? user!.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.name ?? 'Unknown User',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Spacer(),
              // Support card
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
                    child: const Row(
                      children: [
                        Icon(Icons.mail_outline, color: Colors.purpleAccent, size: 24),
                        SizedBox(width: 14),
                        Expanded(
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
                        Icon(Icons.open_in_new, color: Colors.grey, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Links: App Page (full width), then Website | GitHub
              _linkButton(Icons.open_in_browser, 'App Page', _appPageUrl),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _linkButton(Icons.public, 'Website', _websiteUrl)),
                  const SizedBox(width: 10),
                  Expanded(child: _linkButton(Icons.code, 'GitHub', _githubUrl)),
                ],
              ),
              const SizedBox(height: 12),
              // Sign out
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    ).logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _version,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
