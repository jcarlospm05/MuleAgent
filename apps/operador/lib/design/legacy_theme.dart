import 'package:flutter/material.dart';

/// Temporary shared theme; Estilo Mule replaces this in stage 3.
ThemeData legacyCaptureTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFFFFDF8),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF21355E),
    primary: const Color(0xFF21355E),
    surface: const Color(0xFFFFFDF8),
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: Color(0xFF182237),
    ),
    bodyMedium: TextStyle(fontSize: 18),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: Color(0xFFCDD6E5), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 80),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
);
