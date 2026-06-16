import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tonten/features/auth/screens/login_screen.dart';

class ApiClient {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final http.Client _client = _createClient();

  static http.Client _createClient() {
    if (kIsWeb) {
      var client = BrowserClient();
      client.withCredentials = true;
      return client;
    }
    return http.Client();
  }

  static const String baseUrl = 'http://localhost:6767';

  static Uri _buildUri(Uri url) {
    if (url.hasScheme) return url;
    return Uri.parse('$baseUrl${url.toString()}');
  }

  static void _handleUnauthorized() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesja wygasła. Zaloguj się ponownie.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final absoluteUrl = _buildUri(url);
    final response = await _client.get(absoluteUrl, headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _handleUnauthorized();
    }
    return response;
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body}) async {
    final absoluteUrl = _buildUri(url);
    final response = await _client.post(absoluteUrl, headers: headers, body: body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _handleUnauthorized();
    }
    return response;
  }
}