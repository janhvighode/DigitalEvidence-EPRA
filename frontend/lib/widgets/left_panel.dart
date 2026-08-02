import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'cyber_logo.dart';

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key});

  Widget featureCard(
    IconData icon,
    String title, {
    required bool mobile,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: mobile ? 45 : 55,
          width: mobile ? 45 : 55,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: mobile ? 23 : 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: mobile ? 12 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool mobile = Responsive.isMobile(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 20 : 45,
        vertical: mobile ? 25 : 35,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CyberLogo(),

          SizedBox(height: mobile ? 18 : 25),

          Text(
            "Digital Evidence\nPrioritization\nSystem",
            style: TextStyle(
              color: Colors.white,
              fontSize: mobile ? 30 : 44,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),

          SizedBox(height: mobile ? 15 : 20),

          Text(
            "Secure Cyber Investigation &\nDigital Evidence Management",
            style: TextStyle(
              color: Colors.white70,
              fontSize: mobile ? 15 : 20,
              height: 1.5,
            ),
          ),

          SizedBox(height: mobile ? 25 : 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              featureCard(
                Icons.security_rounded,
                "Secure",
                mobile: mobile,
              ),
              featureCard(
                Icons.analytics_rounded,
                "Efficient",
                mobile: mobile,
              ),
              featureCard(
                Icons.gps_fixed_rounded,
                "Accurate",
                mobile: mobile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}