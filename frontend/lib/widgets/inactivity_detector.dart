import 'package:flutter/material.dart';
import '../services/session_manager.dart';

/// Wraps the application to record user interactions across all screens.
class InactivityDetector extends StatelessWidget {
  final Widget child;

  const InactivityDetector({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        SessionManager.instance.recordUserActivity();
        return false;
      },
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: true,
        onKeyEvent: (node, event) {
          SessionManager.instance.recordUserActivity();
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => SessionManager.instance.recordUserActivity(),
          onPointerUp: (_) => SessionManager.instance.recordUserActivity(),
          onPointerMove: (_) => SessionManager.instance.recordUserActivity(),
          onPointerHover: (_) => SessionManager.instance.recordUserActivity(),
          child: child,
        ),
      ),
    );
  }
}
