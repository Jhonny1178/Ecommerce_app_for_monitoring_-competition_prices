import 'package:flutter/material.dart';
import 'core/theme/theme.dart';
import 'features/auth/screens/landing_page_screen.dart';
import 'core/api/api_client.dart';

final ValueNotifier<ThemeMode> globalThemeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: globalThemeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: ApiClient.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'e-ROCH App',
          
          themeMode: currentMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme, 
          
          home: const LandingPageScreen(),
        );
      },
    );
  }
}