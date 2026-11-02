import 'package:flutter/material.dart';

/// Visual tokens — Evocative World (company) × Hoop (product).
/// See docs/10-diseno-visual.md.
abstract final class AppColors {
  static const bgApp = Color(0xFFF2F4F1);
  static const bgElevated = Color(0xFFFBFCF9);
  static const textPrimary = Color(0xFF1C1814);
  static const textSecondary = Color(0xFF5C574F);
  static const textInverse = Color(0xFFF7F4EF);
  /// Label / icon color on dark teal (accent) surfaces — light gold for contrast.
  static const textOnDark = Color(0xFFE8D4A0);
  static const accent = Color(0xFF0D4A5B);
  static const accentPressed = Color(0xFF0A3A47);
  static const accentSoft = Color(0x240D4A5B);
  static const gold = Color(0xFFB59344);
  static const moss = Color(0xFF5A6B3A);
  static const navy = Color(0xFF1A3D6D);
  static const bubbleOut = Color(0xFFD4E6E8);
  static const bubbleIn = Color(0xFFFBFCF9);
  static const hairline = Color(0x1F1C1814);
  static const coinPending = Color(0xFF9AA39B);
  static const coinInProgress = Color(0xFF8FB0B8);
  static const coinCompleted = Color(0xFF0D4A5B);
  static const danger = Color(0xFFB42318);
  /// Unread count badge on Hoops home list.
  static const unreadBadge = Color(0xFF6B3FA0);
  static const authGradientTop = Color(0xFF0D4A5B);
  static const authGradientMid = Color(0xFF1A3D6D);
  static const authGradientBottom = Color(0xFF12151A);
}
