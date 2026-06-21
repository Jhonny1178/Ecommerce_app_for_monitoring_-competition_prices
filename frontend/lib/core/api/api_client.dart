import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:tonten/features/auth/screens/login_screen.dart';

class ApiClient {
  static GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final http.Client _client = _createClient();

  static bool _isHandlingUnauthorized = false;

  static http.Client _createClient() {
    if (kIsWeb) {
      final client = BrowserClient();
      client.withCredentials = true;
      return client;
    }

    return http.Client();
  }

  static const String baseUrl = 'http://localhost:6767';

  static Uri _buildUri(Uri url) {
    if (url.hasScheme) {
      return url;
    }

    return Uri.parse('$baseUrl${url.toString()}');
  }

  static void _handleUnauthorized() {
    if (_isHandlingUnauthorized) {
      return;
    }

    _isHandlingUnauthorized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;

      if (context == null) {
        _isHandlingUnauthorized = false;
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sesja wygasła. Zaloguj się ponownie.',
          ),
          backgroundColor: Colors.red,
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );

      Future.delayed(
        const Duration(seconds: 2),
        () {
          _isHandlingUnauthorized = false;
        },
      );
    });
  }

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final absoluteUrl = _buildUri(url);

    final response = await _client.get(
      absoluteUrl,
      headers: headers,
    );

    if (response.statusCode == 401) {
      _handleUnauthorized();
    }

    return response;
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final absoluteUrl = _buildUri(url);

    final response = await _client.post(
      absoluteUrl,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 401) {
      _handleUnauthorized();
    }

    return response;
  }
}