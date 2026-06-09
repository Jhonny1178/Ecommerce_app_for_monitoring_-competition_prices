import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tonten/features/auth/screens/login_screen.dart';

class ApiClient {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _handleUnauthorized();
    }
    return response;
  }

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body}) async {
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _handleUnauthorized();
    }
    return response;
  }
}
