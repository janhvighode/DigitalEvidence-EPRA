import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF004687);
  static const Color leftPanel = Color(0xFF87CEEB);

  static const Color white = Colors.white;
  static const Color black = Color(0xFF1A1A1A);

  static const Color primary = Color(0xFF004687);
  static const Color primaryDark = Color(0xFF003366);

  static const Color grey = Color(0xFF6B7280);

  static const Color border = Color(0xFFE5E7EB);

  static const Color shadow = Color(0x22000000);

  // Forensic Brand Colors
  static const Color navy = Color(0xFF071B33);
  static const Color royalBlue = Color(0xFF0875F5);
  static const Color pageBg = Color(0xFFF5F8FD);
  static const Color cardBorder = Color(0xFFD8E2EF);
  static const Color cardBorderSubtle = Color(0xFFE2E8F0);
  static const Color mutedText = Color(0xFF64748B);
  static const Color subtleText = Color(0xFF94A3B8);

  // Pastel Card Tints & Accents
  // Blue: general, total evidence
  static const Color pastelBlueBg = Color(0xFFEFF6FF);
  static const Color pastelBlueBorder = Color(0xFFBFDBFE);
  static const Color pastelBlueText = Color(0xFF1D4ED8);
  static const Color pastelBlueIcon = Color(0xFF2563EB);

  // Green / Teal: analyzed, verified, success
  static const Color pastelGreenBg = Color(0xFFF0FDF4);
  static const Color pastelGreenBorder = Color(0xFFBBF7D0);
  static const Color pastelGreenText = Color(0xFF15803D);
  static const Color pastelGreenIcon = Color(0xFF16A34A);

  // Amber / Yellow: pending, medium priority, in-progress
  static const Color pastelAmberBg = Color(0xFFFFFBEB);
  static const Color pastelAmberBorder = Color(0xFFFDE68A);
  static const Color pastelAmberText = Color(0xFFB45309);
  static const Color pastelAmberIcon = Color(0xFFD97706);

  // Red / Coral: critical, high priority, integrity issues, alerts
  static const Color pastelRedBg = Color(0xFFFEF2F2);
  static const Color pastelRedBorder = Color(0xFFFECACA);
  static const Color pastelRedText = Color(0xFFB91C1C);
  static const Color pastelRedIcon = Color(0xFFDC2626);

  // Purple / Indigo: analysis, relationship, technical reports
  static const Color pastelPurpleBg = Color(0xFFFAF5FF);
  static const Color pastelPurpleBorder = Color(0xFFE9D5FF);
  static const Color pastelPurpleText = Color(0xFF7E22CE);
  static const Color pastelPurpleIcon = Color(0xFF9333EA);

  // Orange: custody, devices, interim reports
  static const Color pastelOrangeBg = Color(0xFFFFF7ED);
  static const Color pastelOrangeBorder = Color(0xFFFED7AA);
  static const Color pastelOrangeText = Color(0xFFC2410C);
  static const Color pastelOrangeIcon = Color(0xFFEA580C);

  // Soft Card Shadow
  static const List<BoxShadow> softCardShadow = [
    BoxShadow(color: Color(0x080F172A), blurRadius: 8, offset: Offset(0, 2)),
  ];

  // ============================================================
  // THEME-AWARE DYNAMIC HELPERS
  // ============================================================
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF0B132B) : const Color(0xFFF5F8FD);

  static Color cardBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF16223F) : Colors.white;

  static Color surfaceBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E2D4A) : const Color(0xFFF8FAFC);

  static Color textNavy(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF071B33);

  static Color textMuted(BuildContext context) =>
      isDark(context) ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  static Color textSubtle(BuildContext context) =>
      isDark(context) ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  static Color cardBorderColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF253457) : const Color(0xFFD8E2EF);

  static Color cardBorderSubtleColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF253457) : const Color(0xFFE2E8F0);

  static Color iconColor(BuildContext context) =>
      isDark(context) ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);

  static Color divider(BuildContext context) =>
      isDark(context) ? const Color(0xFF253457) : const Color(0xFFE2E8F0);

  // Dynamic Pastel Blue
  static Color dynamicPastelBlueBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF162A4A) : pastelBlueBg;
  static Color dynamicPastelBlueBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF1D4ED8) : pastelBlueBorder;
  static Color dynamicPastelBlueText(BuildContext context) =>
      isDark(context) ? const Color(0xFF93C5FD) : pastelBlueText;
  static Color dynamicPastelBlueIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFF60A5FA) : pastelBlueIcon;

  // Dynamic Pastel Green
  static Color dynamicPastelGreenBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF132F22) : pastelGreenBg;
  static Color dynamicPastelGreenBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF15803D) : pastelGreenBorder;
  static Color dynamicPastelGreenText(BuildContext context) =>
      isDark(context) ? const Color(0xFF86EFAC) : pastelGreenText;
  static Color dynamicPastelGreenIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFF4ADE80) : pastelGreenIcon;

  // Dynamic Pastel Amber
  static Color dynamicPastelAmberBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF332712) : pastelAmberBg;
  static Color dynamicPastelAmberBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFFB45309) : pastelAmberBorder;
  static Color dynamicPastelAmberText(BuildContext context) =>
      isDark(context) ? const Color(0xFFFDE047) : pastelAmberText;
  static Color dynamicPastelAmberIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFFFBBF24) : pastelAmberIcon;

  // Dynamic Pastel Red
  static Color dynamicPastelRedBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF331618) : pastelRedBg;
  static Color dynamicPastelRedBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFFB91C1C) : pastelRedBorder;
  static Color dynamicPastelRedText(BuildContext context) =>
      isDark(context) ? const Color(0xFFFCA5A5) : pastelRedText;
  static Color dynamicPastelRedIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFFF87171) : pastelRedIcon;

  // Dynamic Pastel Purple
  static Color dynamicPastelPurpleBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF271A3F) : pastelPurpleBg;
  static Color dynamicPastelPurpleBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF7E22CE) : pastelPurpleBorder;
  static Color dynamicPastelPurpleText(BuildContext context) =>
      isDark(context) ? const Color(0xFFD8B4FE) : pastelPurpleText;
  static Color dynamicPastelPurpleIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFFC084FC) : pastelPurpleIcon;

  // Dynamic Pastel Orange
  static Color dynamicPastelOrangeBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF331F14) : pastelOrangeBg;
  static Color dynamicPastelOrangeBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFFC2410C) : pastelOrangeBorder;
  static Color dynamicPastelOrangeText(BuildContext context) =>
      isDark(context) ? const Color(0xFFFDBA74) : pastelOrangeText;
  static Color dynamicPastelOrangeIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFFFB923C) : pastelOrangeIcon;
}

extension AppThemeExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get pageBg => AppColors.pageBackground(this);
  Color get cardBg => AppColors.cardBg(this);
  Color get surfaceBg => AppColors.surfaceBg(this);
  Color get textNavy => AppColors.textNavy(this);
  Color get textMuted => AppColors.textMuted(this);
  Color get textSubtle => AppColors.textSubtle(this);
  Color get cardBorder => AppColors.cardBorderColor(this);
  Color get cardBorderSubtle => AppColors.cardBorderSubtleColor(this);
  Color get dividerColor => AppColors.divider(this);
  Color get iconColor => AppColors.iconColor(this);
}
