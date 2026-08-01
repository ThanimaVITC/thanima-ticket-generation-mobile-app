import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../models/event.dart';
import '../models/registration.dart';

class ApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Simple in-memory SWR cache. Read methods write their last result here so
  // screens can render it instantly via ApiService.peek(key) while a fresh
  // request runs in the background.
  static final Map<String, dynamic> _cache = {};
  static dynamic peek(String key) => _cache[key];

  // Disk-backed copy of a cached list, so a screen renders instantly on the
  // first open after a cold start too — not just on revisits within a session.
  // Uses the secure storage already in the app rather than adding a package.
  Future<void> _persist(String key, Object value) async {
    try {
      await _storage.write(key: 'cache:$key', value: jsonEncode(value));
    } catch (_) {
      // A cache write is never worth failing a request over.
    }
  }

  Future<List<Map<String, dynamic>>?> readPersistedList(String key) async {
    try {
      final raw = await _storage.read(key: 'cache:$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // Production endpoint, used by default in normal/release runs.
  static const String onlineUrl = 'https://ticketing.thanimavitc.site/api';

  // Optional compile-time override for local development. Provide it with:
  //   flutter run --dart-define=BASE_URL=http://192.168.1.5:3000
  // When set, it takes precedence over any saved server URL so a local run
  // reliably hits the dev server even after a prior login stored a URL.
  static const String _envBaseUrl = String.fromEnvironment('BASE_URL');

  // Whether a compile-time BASE_URL override was supplied.
  static bool get hasEnvOverride => _envBaseUrl.trim().isNotEmpty;

  // The effective default URL: the compile-time override if given, else online.
  static String get defaultUrl =>
      hasEnvOverride ? _normalizeUrl(_envBaseUrl) : onlineUrl;

  // Normalize a base URL: trim, drop a trailing slash, ensure it ends with /api.
  // Accepts either "http://host:3000" or "http://host:3000/api".
  static String _normalizeUrl(String url) {
    final cleanUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    if (cleanUrl.endsWith('/api')) {
      return cleanUrl;
    }
    return '$cleanUrl/api';
  }

  Future<String> _getBaseUrl() async {
    // A compile-time override always wins (debug/local convenience).
    if (hasEnvOverride) {
      return _normalizeUrl(_envBaseUrl);
    }
    final url = await _storage.read(key: 'server_url');
    return _normalizeUrl(url ?? onlineUrl);
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
      final list = (data['events'] as List).map((e) => Event.fromJson(e)).toList();
      _cache['events'] = list;
      return list;
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _cache['event:$eventId'] = data;
      return data;
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
      final list = List<Map<String, dynamic>>.from(data['registrations']);
      _cache['regs:$eventId'] = list;
      return list;
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

  // Fetch food sessions for an event. Pass activeOnly to only get the
  // sessions an admin has made visible (what the scanner should show).
  Future<List<Map<String, dynamic>>> getFoodSessions(
    String eventId, {
    bool activeOnly = true,
  }) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final query = activeOnly ? '?activeOnly=1' : '';
    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId/food-sessions$query'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
      _cache['food:$eventId'] = list;
      return list;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to load food sessions');
    }
  }

  // Scan an attendee's ticket QR into a food session. Known outcomes
  // (admitted / already scanned / full / wrong event) come back as JSON with
  // different status codes, so we return both the status and the parsed body
  // and let the screen decide how to render rather than throwing.
  Future<Map<String, dynamic>> scanFoodSession(
    String eventId,
    String sessionId,
    String encryptedData,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/events/$eventId/food-sessions/$sessionId/scan'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'encryptedData': encryptedData}),
    );

    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (_) {
      body = {'error': 'Unexpected server response'};
    }

    return {'statusCode': response.statusCode, 'data': body};
  }

  // ---- User Pool ------------------------------------------------------
  // The add/lookup calls return {statusCode, data} rather than throwing,
  // because their 4xx bodies carry meaningful outcomes (alreadyInPool,
  // cardInUse, found:false) that the screens render differently — same shape
  // as scanFoodSession above.

  // A server that doesn't know a route answers with its HTML 404 page, not
  // JSON — jsonDecode then throws a FormatException full of markup, which is
  // what staff would see on screen. Decode defensively and say something
  // actionable instead.
  Map<String, dynamic> _decodeJson(http.Response response) {
    final body = response.body.trimLeft();
    final looksLikeJson = body.startsWith('{') || body.startsWith('[');

    if (!looksLikeJson) {
      if (response.statusCode == 404) {
        throw Exception(
          'This feature is not available on the server yet. '
          'The web app needs to be redeployed with the User Pool update.',
        );
      }
      throw Exception(
        'Server returned an unexpected response (HTTP ${response.statusCode}).',
      );
    }

    try {
      return Map<String, dynamic>.from(jsonDecode(body));
    } catch (_) {
      throw Exception(
        'Server returned malformed data (HTTP ${response.statusCode}).',
      );
    }
  }

  // activeOnly=true -> who is in the pool now; false -> full usage history.
  Future<List<Map<String, dynamic>>> getUserPool(
    String eventId, {
    bool activeOnly = true,
  }) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final status = activeOnly ? 'active' : 'all';
    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId/user-pool?status=$status'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      final list = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      _cache['pool:$eventId:$status'] = list;
      return list;
    }

    throw Exception(data['error'] ?? 'Failed to load the user pool');
  }

  Future<Map<String, dynamic>> addToUserPool(
    String eventId,
    String encryptedData,
    String nfcId,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/events/$eventId/user-pool/add'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'encryptedData': encryptedData, 'nfcId': nfcId}),
    );

    return _statusAndBody(response);
  }

  Future<Map<String, dynamic>> lookupPoolByNfc(
    String eventId,
    String nfcId,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse(
        '$baseUrl/events/$eventId/user-pool/lookup?nfcId=${Uri.encodeQueryComponent(nfcId)}',
      ),
      headers: {'Cookie': 'auth-token=$token'},
    );

    return _statusAndBody(response);
  }

  Future<Map<String, dynamic>> removeFromUserPool(
    String eventId,
    String entryId,
  ) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/events/$eventId/user-pool/remove'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'entryId': entryId}),
    );

    return _statusAndBody(response);
  }

  Map<String, dynamic> _statusAndBody(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = _decodeJson(response);
    } catch (e) {
      body = {'error': e.toString().replaceAll('Exception: ', '')};
    }
    return {'statusCode': response.statusCode, 'data': body};
  }

  // ---- Unpaid list ----------------------------------------------------

  Future<List<Map<String, dynamic>>> getUnpaid(String eventId) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId/unpaid'),
      headers: {'Cookie': 'auth-token=$token'},
    );

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      final list = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      _cache['unpaid:$eventId'] = list;
      unawaited(_persist('unpaid:$eventId', list));
      return list;
    }

    throw Exception(data['error'] ?? 'Failed to load the unpaid list');
  }

  // source is 'manual' when staff typed it, 'ocr' when it came off a card.
  Future<Map<String, dynamic>> addUnpaid(
    String eventId,
    String name,
    String regNo, {
    String source = 'manual',
  }) async {
    final token = await getToken();
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/events/$eventId/unpaid'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'auth-token=$token',
      },
      body: jsonEncode({'name': name, 'regNo': regNo, 'source': source}),
    );

    return _statusAndBody(response);
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
