import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class BackgroundDesign extends StatelessWidget {
  const BackgroundDesign({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [

        // Main Background
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.background,
                Color(0xFF0A5AA8),
                AppColors.background,
              ],
            ),
          ),
        ),

        // Top Left Circle
        Positioned(
          top: -180,
          left: -180,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(.06),
            ),
          ),
        ),

        // Bottom Right Circle
        Positioned(
          bottom: -220,
          right: -180,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(.05),
            ),
          ),
        ),

        // Center Glow
        Center(
          child: Container(
            width: 700,
            height: 700,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(.03),
            ),
          ),
        ),

        // Decorative Small Circle
        Positioned(
          top: 120,
          right: 220,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white70,
                width: 2,
              ),
            ),
          ),
        ),

        // Decorative Plus
        const Positioned(
          top: 180,
          left: 220,
          child: Icon(
            Icons.add,
            color: Colors.white70,
            size: 34,
          ),
        ),

        // Bottom Left Decorative Circle
        Positioned(
          bottom: 140,
          left: 160,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white54,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}