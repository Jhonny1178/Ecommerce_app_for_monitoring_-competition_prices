import 'package:flutter/material.dart';
import 'core/theme/theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'core/api/api_client.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ApiClient.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'e-ROCH App',
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    );
  }
}