import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Brand Colors - Deep Amber/Gold for restaurant
  static const Color primary = Color(0xFFD4A017);
  static const Color primaryLight = Color(0xFFE8C547);
  static const Color primaryDark = Color(0xFFA07C10);
  static const Color onPrimary = Color(0xFF1A1208);

  // Background Colors - Rich dark theme
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceVariant = Color(0xFF242424);
  static const Color card = Color(0xFF1E1E1E);

  // Text Colors
  static const Color textPrimary = Color(0xFFF5F0E8);
  static const Color textSecondary = Color(0xFF9A9080);
  static const Color textOnPrimary = Color(0xFF1A1208);
  static const Color textHint = Color(0xFF5A5248);

  // Status Colors
  static const Color success = Color(0xFF4CAF7A);
  static const Color error = Color(0xFFE85D5D);
  static const Color warning = Color(0xFFFFB347);
  static const Color info = Color(0xFF64B5F6);

  // Table Status Colors
  static const Color tableAvailable = Color(0xFF4CAF7A);
  static const Color tableOccupied = Color(0xFFE85D5D);
  static const Color tableReserved = Color(0xFFFFB347);
  static const Color tableCleaning = Color(0xFF64B5F6);

  // Divider / Border
  static const Color divider = Color(0xFF2A2A2A);
  static const Color border = Color(0xFF333333);

  // Gradient colors
  static const Color gradientStart = Color(0xFFD4A017);
  static const Color gradientEnd = Color(0xFF8B6914);

  // Role Colors
  static const Color roleManager = Color(0xFFD4A017);
  static const Color roleCashier = Color(0xFF64B5F6);
  static const Color roleWaiter = Color(0xFF4CAF7A);
  static const Color roleKitchen = Color(0xFFFF8A65);
  static const Color roleInventory = Color(0xFFBA68C8);
}
