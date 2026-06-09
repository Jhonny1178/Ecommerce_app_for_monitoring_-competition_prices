import 'package:flutter/material.dart';
import 'color_scheme.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const materialTheme = MaterialTheme(TextTheme());
    return materialTheme.light(); 
  }

  static ThemeData get darkTheme {
    const materialTheme = MaterialTheme(TextTheme());
    return materialTheme.dark(); 
  }
}