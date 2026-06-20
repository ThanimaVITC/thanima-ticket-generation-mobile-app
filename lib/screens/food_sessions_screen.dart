import 'package:flutter/material.dart';
import '../models/food_session.dart';
import '../services/api_service.dart';
import 'food_scan_screen.dart';

class FoodSessionsScreen extends StatefulWidget {
  final String eventId;

  const FoodSessionsScreen({super.key, required this.eventId});

  @override
  State<FoodSessionsScreen> createState() => _FoodSessionsScreenState();
}

class _FoodSessionsScreenState extends State<FoodSessionsScreen> {
  final ApiService _apiService = ApiService();
  List<FoodSession> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Seed from cache for an instant render, then refresh in the background.
    final cached = ApiService.peek('food:${widget.eventId}');
    if (cached is List) {
      _sessions = cached.map((s) => FoodSession.fromJson(Map<String, dynamic>.from(s as Map))).toList();
      _isLoading = false;
    }
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      if (_sessions.isEmpty) _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiService.getFoodSessions(
        widget.eventId,
        activeOnly: true,
      );
      if (!mounted) return;
      setState(() {
        _sessions = data.map((s) => FoodSession.fromJson(s)).toList();
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

  void _openScanner(FoodSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FoodScanScreen(
          eventId: widget.eventId,
          session: session,
        ),
      ),
    ).then((_) => _loadSessions());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Food Sessions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _buildBody(),
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
                onPressed: _loadSessions,
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

    if (_sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSessions,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.no_meals, color: Colors.grey, size: 56),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No food sessions available',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'An admin needs to add and show a session',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _sessions.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Select a session, then scan attendee QR codes to admit them. '
                'Each attendee can be admitted only once.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            );
          }
          return _buildSessionCard(_sessions[index - 1]);
        },
      ),
    );
  }

  Widget _buildSessionCard(FoodSession session) {
    final stats = session.stats;
    final isFull = stats?.full ?? (session.count >= session.maxLimit);
    final nearLimit = stats?.nearLimit ?? (session.count >= session.limit);
    final pct = session.maxLimit > 0
        ? (session.count / session.maxLimit).clamp(0.0, 1.0)
        : 0.0;

    final Color accent = isFull
        ? Colors.red
        : nearLimit
            ? Colors.orange
            : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isFull ? null : () => _openScanner(session),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.restaurant, color: accent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${session.count} / ${session.maxLimit} admitted',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isFull)
                      _badge('FULL', Colors.red)
                    else if (nearLimit)
                      _badge('NEAR LIMIT', Colors.orange)
                    else
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.grey,
                        size: 16,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Limit ${session.limit} • Max ${session.maxLimit}'
                  '${stats != null ? ' • ${stats.remainingToMax} spots left' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
