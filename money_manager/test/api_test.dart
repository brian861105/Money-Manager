import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_manager/src/api.dart';

void main() {
  test('OAuth mode does not send a fake IAP identity header', () async {
    late http.Request capturedRequest;
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      authMode: AuthMode.oauth,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          '{"user":{"email":"you@example.com","user_id":"123"}}',
          200,
        );
      }),
    );

    final session = await api.getCurrentSession();

    expect(session?.email, 'you@example.com');
    expect(
      capturedRequest.headers,
      isNot(contains('X-Goog-Authenticated-User-Email')),
    );
  });

  test(
    'IAP dev mode sends the configured development identity header',
    () async {
      late http.Request capturedRequest;
      final api = MicroLedgerApi(
        baseUrl: 'http://localhost:8080',
        authMode: AuthMode.iapDev,
        devEmail: 'dev@example.com',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            '{"user":{"email":"dev@example.com","user_id":"dev"}}',
            200,
          );
        }),
      );

      await api.getCurrentSession();

      expect(
        capturedRequest.headers['X-Goog-Authenticated-User-Email'],
        'accounts.google.com:dev@example.com',
      );
    },
  );

  test('current session returns null on unauthorized response', () async {
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        return http.Response(
          '{"error":{"code":"unauthorized","message":"unauthenticated"}}',
          401,
        );
      }),
    );

    await expectLater(api.getCurrentSession(), completion(isNull));
  });

  test(
    'non-json error response becomes ApiException instead of FormatException',
    () async {
      final api = MicroLedgerApi(
        baseUrl: 'http://localhost:8080',
        client: MockClient((request) async {
          return http.Response('404 page not found', 404);
        }),
      );

      await expectLater(
        api.getCurrentSession(),
        throwsA(
          isA<ApiException>()
              .having((err) => err.statusCode, 'statusCode', 404)
              .having((err) => err.code, 'code', 'invalid_response')
              .having((err) => err.message, 'message', '404 page not found'),
        ),
      );
    },
  );

  test('Google ID token login stores backend session token', () async {
    late http.Request capturedRequest;
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          '{"session_token":"session-123","user":{"email":"native@example.com","user_id":"native-123"}}',
          200,
        );
      }),
    );

    final session = await api.loginWithGoogleIdToken('id-token-123');

    expect(session.email, 'native@example.com');
    expect(api.sessionToken, 'session-123');
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.url.path, '/api/auth/google/id-token');
    expect(capturedRequest.body, '{"id_token":"id-token-123"}');
    expect(capturedRequest.headers, isNot(contains('Authorization')));
  });

  test(
    'session token is sent as a bearer token for authenticated APIs',
    () async {
      final authorizations = <String?>[];
      final api = MicroLedgerApi(
        baseUrl: 'http://localhost:8080',
        client: MockClient((request) async {
          authorizations.add(request.headers['Authorization']);
          return switch ('${request.method} ${request.url.path}') {
            'POST /api/auth/google/id-token' => http.Response(
              '{"session_token":"session-123","user":{"email":"native@example.com","user_id":"native-123"}}',
              200,
            ),
            'GET /api/auth/me' => http.Response(
              '{"user":{"email":"native@example.com","user_id":"native-123"}}',
              200,
            ),
            'POST /api/auth/logout' => http.Response('', 204),
            _ => http.Response(
              '{"error":{"code":"not_found","message":"not found"}}',
              404,
            ),
          };
        }),
      );

      await api.loginWithGoogleIdToken('id-token-123');
      await api.getCurrentSession();
      await api.logout();

      expect(authorizations, [
        isNull,
        'Bearer session-123',
        'Bearer session-123',
      ]);
      expect(api.sessionToken, isNull);
    },
  );
}
