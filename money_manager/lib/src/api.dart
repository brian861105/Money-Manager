import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client.dart';

enum AuthMode {
  oauth('oauth'),
  iapDev('iap-dev');

  const AuthMode(this.label);

  final String label;

  static AuthMode parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'iap-dev' || 'iap_dev' || 'iapdev' => AuthMode.iapDev,
      _ => AuthMode.oauth,
    };
  }
}

class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const devEmail = String.fromEnvironment(
    'API_DEV_EMAIL',
    defaultValue: 'you@example.com',
  );
  static const authModeName = String.fromEnvironment(
    'API_AUTH_MODE',
    defaultValue: 'oauth',
  );
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
  static const googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static AuthMode get authMode => AuthMode.parse(authModeName);
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => '$statusCode $code: $message';
}

class AuthSession {
  const AuthSession({required this.email, required this.userId});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      email: json['email'] as String,
      userId: json['user_id'] as String? ?? '',
    );
  }

  final String email;
  final String userId;
}

class Ledger {
  const Ledger({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerEmail,
  });

  factory Ledger.fromJson(Map<String, dynamic> json) {
    return Ledger(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      ownerEmail: json['owner_email'] as String,
    );
  }

  final int id;
  final String name;
  final String type;
  final String ownerEmail;
}

class LedgerRecord {
  const LedgerRecord({
    required this.id,
    required this.ledgerId,
    required this.creatorEmail,
    required this.date,
    required this.category,
    required this.description,
    required this.amountCents,
  });

  factory LedgerRecord.fromJson(Map<String, dynamic> json) {
    return LedgerRecord(
      id: json['id'] as int,
      ledgerId: json['ledger_id'] as int,
      creatorEmail: json['creator_email'] as String,
      date: DateTime.parse(json['date'] as String),
      category: json['category'] as String,
      description: json['description'] as String? ?? '',
      amountCents: json['amount_cents'] as int,
    );
  }

  final int id;
  final int ledgerId;
  final String creatorEmail;
  final DateTime date;
  final String category;
  final String description;
  final int amountCents;
}

class MicroLedgerApi {
  MicroLedgerApi({
    http.Client? client,
    String baseUrl = ApiConfig.baseUrl,
    AuthMode? authMode,
    String devEmail = ApiConfig.devEmail,
  }) : _client = client ?? createHttpClient(),
       _baseUrl = baseUrl,
       _authMode = authMode ?? ApiConfig.authMode,
       _devEmail = devEmail;

  final http.Client _client;
  final String _baseUrl;
  final AuthMode _authMode;
  final String _devEmail;
  String? _sessionToken;

  Uri authLoginUri() => Uri.parse('$_baseUrl/api/auth/google/login');

  String? get sessionToken => _sessionToken;

  Future<AuthSession> loginWithGoogleIdToken(String idToken) async {
    final json = await _send(
      'POST',
      '/api/auth/google/id-token',
      body: {'id_token': idToken},
      includeAuth: false,
    );
    final sessionToken = json['session_token'] as String?;
    if (sessionToken == null || sessionToken.trim().isEmpty) {
      throw ApiException(
        200,
        'invalid_response',
        'authentication response did not include a session token',
      );
    }

    _sessionToken = sessionToken;
    return AuthSession.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<AuthSession?> getCurrentSession() async {
    try {
      final json = await _send('GET', '/api/auth/me');
      return AuthSession.fromJson(json['user'] as Map<String, dynamic>);
    } on ApiException catch (err) {
      if (err.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    await _send('POST', '/api/auth/logout');
    _sessionToken = null;
  }

  Future<Ledger> getActiveLedger() async {
    final json = await _send('GET', '/api/context/active-ledger');
    return Ledger.fromJson(json['ledger'] as Map<String, dynamic>);
  }

  Future<Ledger> setActiveLedger(int ledgerId) async {
    final json = await _send(
      'PUT',
      '/api/context/active-ledger',
      body: {'ledger_id': ledgerId},
    );
    return Ledger.fromJson(json['ledger'] as Map<String, dynamic>);
  }

  Future<List<Ledger>> listLedgers() async {
    final json = await _send('GET', '/api/ledgers');
    final items = json['ledgers'] as List<dynamic>;
    return items
        .map((item) => Ledger.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<LedgerRecord>> listRecords({required int ledgerId}) async {
    final json = await _send('GET', '/api/ledgers/$ledgerId/records?limit=100');
    final items = json['records'] as List<dynamic>;
    return items
        .map((item) => LedgerRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<LedgerRecord> createRecord({
    required int ledgerId,
    required String category,
    required String description,
    required int amountCents,
  }) async {
    final json = await _send(
      'POST',
      '/api/ledgers/$ledgerId/records',
      body: {
        'date': DateTime.now().toUtc().toIso8601String(),
        'category': category,
        'description': description,
        'amount_cents': amountCents,
      },
    );
    return LedgerRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });
    if (_authMode == AuthMode.iapDev) {
      request.headers['X-Goog-Authenticated-User-Email'] =
          'accounts.google.com:$_devEmail';
    }
    final sessionToken = _sessionToken?.trim();
    if (includeAuth && sessionToken != null && sessionToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $sessionToken';
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode == 204) {
      return <String, dynamic>{};
    }

    final decoded = _decodeResponseBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        response.statusCode,
        error?['code'] as String? ?? 'request_failed',
        error?['message'] as String? ?? 'request failed',
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decodeResponseBody(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      return <String, dynamic>{
        'error': <String, dynamic>{'code': 'invalid_response', 'message': body},
      };
    }
  }

  void close() {
    _client.close();
  }
}
