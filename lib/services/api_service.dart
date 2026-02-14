import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../models/event.dart';
import '../models/registration.dart';

class ApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Default fallback if nothing is saved
  static const String defaultUrl = 'http://172.20.80.212:3000/api';

  Future<String> _getBaseUrl() async {
    final url = await _storage.read(key: 'server_url');
    // Ensure no trailing slash
    final cleanUrl = (url ?? defaultUrl).replaceAll(RegExp(r'/$'), '');
    // Ensure it ends with /api if not present?
    // The user input should be "http://ip:port", we append "/api"
    // Or we expect user to enter full api path?
    // Let's assume user enters "http://192.168.1.5:3000". We append "/api".

    if (cleanUrl.endsWith('/api')) {
      return cleanUrl;
    }
    return '$cleanUrl/api';
  }

  Future<String?> getServerUrl() async {
    return await _storage.read(key: 'server_url');
  }

  Future<void> setServerUrl(String url) async {
    // Basic cleanup
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    await _storage.write(key: 'server_url', value: clean);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<void> setToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  Future<void> removeToken() async {
    await _storage.delete(key: 'auth_token');
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final baseUrl = await _getBaseUrl();
    final fullUrl = Uri.parse('$baseUrl/auth/login');
    print('Attempting login to: $fullUrl');
    print('Email: $email');

    try {
      final response = await http.post(
        fullUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      print('Login Response Status: ${response.statusCode}');
      print('Login Response Body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Try to parse error, if fails execute generic error
        try {
          throw Exception(jsonDecode(response.body)['error'] ?? 'Login failed');
        } catch (e) {
          if (e is Exception) rethrow; // If it was the specific error above
          throw Exception(
            'Login failed: ${response.statusCode}. Check server URL.',
          );
        }
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused')) {
        throw Exception('Could not connect to server. Check URL and internet.');
      }
      rethrow;
    }
  }

  Future<User?> getMe() async {
    final token = await getToken();
    if (token == null) return null;
    final baseUrl = await _getBaseUrl();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {'Cookie': 'auth-token=$token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return User.fromJson(data['user']);
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  Future<List<Event>> getEvents() async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse('$baseUrl/events'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['events'] as List).map((e) => Event.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load events');
    }
  }

  Future<Map<String, dynamic>> getEventDetails(String eventId) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load event details');
    }
  }

  Future<Map<String, dynamic>> markAttendance(
    String eventId,
    String email,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/attendance/mark'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({
        'eventId': eventId,
        'email': email,
        'source': 'mobile',
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to mark attendance');
    }

    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> verifyQrAttendance(
    String encryptedData,
    String eventId,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/attendance/verify-qr'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'encryptedData': encryptedData, 'eventId': eventId}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to verify QR code');
    }

    return jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> getRegistrations(String eventId) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse('$baseUrl/registrations/$eventId'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['registrations']);
    } else {
      throw Exception('Failed to load registrations');
    }
  }

  Future<Map<String, dynamic>> assignQrPayload(
    String eventId,
    String registrationId,
    String qrPayload,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.put(
      Uri.parse('$baseUrl/registrations/$eventId/assign-qr'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({
        'registrationId': registrationId,
        'qrPayload': qrPayload,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to assign QR payload');
    }

    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>?> checkQrPayloadExists(
    String eventId,
    String qrPayload,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse(
        '$baseUrl/registrations/$eventId/check-qr?qrPayload=$qrPayload',
      ),
      headers: {'Cookie': 'auth-token=$token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['exists'] == true) {
        return data;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> verifyTicket(
    String qrPayload,
    String eventId,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/tickets/verify'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'qrPayload': qrPayload, 'eventId': eventId}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to verify ticket');
    }

    return jsonDecode(response.body);
  }
}
