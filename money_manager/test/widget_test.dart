import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_manager/main.dart';
import 'package:money_manager/src/api.dart';
import 'package:money_manager/src/google_auth_provider.dart';
import 'package:money_manager/src/launcher.dart';

void main() {
  testWidgets('signed-out screen launches Google login', (tester) async {
    final launcher = RecordingLauncher();
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        return http.Response(
          '{"error":{"code":"unauthorized","message":"unauthenticated"}}',
          401,
        );
      }),
    );

    await tester.pumpWidget(
      MoneyManagerApp(
        api: api,
        googleAuthProvider: RedirectGoogleAuthProvider(launcher: launcher),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Money Manager'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();

    expect(
      launcher.openedUrls,
      contains('http://localhost:8080/api/auth/google/login'),
    );
  });

  testWidgets('signed-in shell loads ledger data and logs out', (tester) async {
    final requests = <String>[];
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return switch ('${request.method} ${request.url.path}') {
          'GET /api/auth/me' => http.Response(
            '{"user":{"email":"you@example.com","user_id":"123"}}',
            200,
          ),
          'GET /api/context/active-ledger' => http.Response(
            '{"ledger":{"id":1,"name":"Personal","type":"personal","owner_email":"you@example.com"}}',
            200,
          ),
          'GET /api/ledgers' => http.Response(
            '{"ledgers":[{"id":1,"name":"Personal","type":"personal","owner_email":"you@example.com"}]}',
            200,
          ),
          'GET /api/records' => http.Response('{"records":[]}', 200),
          'POST /api/auth/logout' => http.Response('', 204),
          _ => http.Response(
            '{"error":{"code":"not_found","message":"not found"}}',
            404,
          ),
        };
      }),
    );

    await tester.pumpWidget(
      MoneyManagerApp(api: api, googleAuthProvider: TestGoogleAuthProvider()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active ledger'), findsOneWidget);
    expect(find.text('Personal (personal)'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('you@example.com'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/auth/logout'));
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('native Google sign-in exchanges ID token and loads data', (
    tester,
  ) async {
    final authProvider = TestGoogleAuthProvider(idToken: 'native-id-token');
    final requests = <String>[];
    final authorizations = <String?>[];
    final api = MicroLedgerApi(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        authorizations.add(request.headers['Authorization']);
        return switch ('${request.method} ${request.url.path}') {
          'GET /api/auth/me' => http.Response(
            '{"error":{"code":"unauthorized","message":"unauthenticated"}}',
            401,
          ),
          'POST /api/auth/google/id-token' => http.Response(
            '{"session_token":"session-123","user":{"email":"native@example.com","user_id":"native-123"}}',
            200,
          ),
          'GET /api/context/active-ledger' => http.Response(
            '{"ledger":{"id":1,"name":"Personal","type":"personal","owner_email":"native@example.com"}}',
            200,
          ),
          'GET /api/ledgers' => http.Response(
            '{"ledgers":[{"id":1,"name":"Personal","type":"personal","owner_email":"native@example.com"}]}',
            200,
          ),
          'GET /api/records' => http.Response('{"records":[]}', 200),
          _ => http.Response(
            '{"error":{"code":"not_found","message":"not found"}}',
            404,
          ),
        };
      }),
    );

    await tester.pumpWidget(
      MoneyManagerApp(api: api, googleAuthProvider: authProvider),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(
      authProvider.loginUris.single.toString(),
      'http://localhost:8080/api/auth/google/login',
    );
    expect(requests, contains('POST /api/auth/google/id-token'));
    expect(find.text('Active ledger'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('native@example.com'), findsOneWidget);
    expect(authorizations, contains('Bearer session-123'));
  });
}

class RecordingLauncher implements UrlLauncher {
  final openedUrls = <String>[];

  @override
  void open(String url) {
    openedUrls.add(url);
  }
}

class TestGoogleAuthProvider implements GoogleAuthProvider {
  TestGoogleAuthProvider({this.idToken});

  final String? idToken;
  final loginUris = <Uri>[];
  var signedOut = false;

  @override
  bool get usesRedirect => false;

  @override
  Future<String?> signInIdToken(Uri loginUri) async {
    loginUris.add(loginUri);
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}
