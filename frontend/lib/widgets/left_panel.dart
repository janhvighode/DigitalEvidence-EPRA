import 'package:flutter/material.dart';
import 'cyber_logo.dart';

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  Widget featureCard(IconData icon, String title) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 45,
          vertical: 35,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CyberLogo(),

              const SizedBox(height: 25),

              const Text(
                "Digital Evidence\nPrioritization\nSystem",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "Secure Cyber Investigation &\nDigital Evidence Management",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              const SizedBox(height: 30),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  featureCard(Icons.security_rounded, "Secure"),
                  featureCard(Icons.analytics_rounded, "Efficient"),
                  featureCard(Icons.gps_fixed_rounded, "Accurate"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}