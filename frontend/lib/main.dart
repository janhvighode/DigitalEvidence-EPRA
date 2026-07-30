import 'package:flutter/material.dart';
import 'screens/auth/create_account_screen.dart';

void main() {
  runApp(const DEPSApp());
}

class DEPSApp extends StatelessWidget {
  const DEPSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Digital Evidence Prioritization System',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home:  CreateAccountScreen(),
    );
  }
}