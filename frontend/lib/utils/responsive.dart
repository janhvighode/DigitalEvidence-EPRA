import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 768;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= 768 &&
        MediaQuery.of(context).size.width < 1100;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1100;
  }

  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    if (isDesktop(context)) {
      return const EdgeInsets.symmetric(horizontal: 60, vertical: 40);
    }

    if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 30, vertical: 25);
    }

    return const EdgeInsets.all(20);
  }

  static double cardWidth(BuildContext context) {
    if (isDesktop(context)) {
      return 1250;
    }

    if (isTablet(context)) {
      return 900;
    }

    return screenWidth(context);
  }
}