import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'routes/app_routes.dart';
import 'screens/auth/create_account_screen.dart';
import 'services/session_manager.dart';
import 'theme/theme_controller.dart';
import 'widgets/inactivity_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.initializeTheme();
  await SessionManager.instance.initializeSession();
  final String initialRoute = await _determineInitialRoute();
  runApp(DEPSApp(initialRoute: initialRoute));
}

Future<String> _determineInitialRoute() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("access_token");
    final roleId = prefs.getInt("role_id");

    if (token != null && token.isNotEmpty && token != 'null') {
      bool isExpired = true;
      try {
        isExpired = JwtDecoder.isExpired(token);
      } catch (_) {
        isExpired = true;
      }

      if (!isExpired && roleId != null) {
        if (roleId == 1) return AppRoutes.adminDashboard;
        if (roleId == 2) return AppRoutes.investigatorDashboard;
        if (roleId == 3) return AppRoutes.cyberExpertDashboard;
      } else {
        await SessionManager.instance.clearSessionData();
      }
    }
  } catch (_) {}

  // Fresh unauthenticated browser/app start -> Welcome/Register page
  return AppRoutes.welcome;
}

class DEPSApp extends StatelessWidget {
  final String? initialRoute;

  const DEPSApp({super.key, this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: SessionManager.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Digital Evidence Prioritization System',
          themeMode: ThemeController.instance.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: const Color(0xFF071B33),
            scaffoldBackgroundColor: const Color(0xFFF5F8FD),
            cardColor: Colors.white,
            canvasColor: const Color(0xFFF5F8FD),
            dialogBackgroundColor: Colors.white,
            dividerColor: const Color(0xFFE2E8F0),
            cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: Color(0xFF071B33),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              contentTextStyle: TextStyle(
                color: Color(0xFF334155),
                fontSize: 14,
              ),
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              textStyle: TextStyle(color: Color(0xFF071B33)),
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xFFE2E8F0),
              thickness: 1,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              labelStyle: const TextStyle(color: Color(0xFF071B33)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF0875F5), width: 1.5),
              ),
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0875F5),
              brightness: Brightness.light,
              surface: Colors.white,
              onSurface: const Color(0xFF071B33),
              surfaceContainer: const Color(0xFFF8FAFC),
              surfaceContainerHigh: const Color(0xFFF1F5F9),
              outline: const Color(0xFFE2E8F0),
              outlineVariant: const Color(0xFFCBD5E1),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF071B33),
            scaffoldBackgroundColor: const Color(0xFF0B132B),
            cardColor: const Color(0xFF16223F),
            canvasColor: const Color(0xFF0B132B),
            dialogBackgroundColor: const Color(0xFF16223F),
            dividerColor: const Color(0xFF253457),
            cardTheme: const CardThemeData(
              color: Color(0xFF16223F),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF16223F),
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              contentTextStyle: TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 14,
              ),
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Color(0xFF1E2D4A),
              surfaceTintColor: Colors.transparent,
              textStyle: TextStyle(color: Colors.white),
            ),
            dividerTheme: const DividerThemeData(
              color: Color(0xFF253457),
              thickness: 1,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E2D4A),
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              labelStyle: const TextStyle(color: Colors.white),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF253457)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF253457)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.5),
              ),
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0875F5),
              brightness: Brightness.dark,
              surface: const Color(0xFF16223F),
              onSurface: Colors.white,
              surfaceContainer: const Color(0xFF1E2D4A),
              surfaceContainerHigh: const Color(0xFF253457),
              outline: const Color(0xFF253457),
              outlineVariant: const Color(0xFF1E2D4A),
            ),
          ),
          builder: (context, child) {
            return InactivityDetector(child: child ?? const SizedBox());
          },
          initialRoute: initialRoute ?? AppRoutes.welcome,
          routes: AppRoutes.getRoutes(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        );
      },
    );
  }
}
