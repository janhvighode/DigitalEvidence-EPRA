import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/settings_model.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color navy = Color(0xFF071B33);
  static const Color darkBlue = Color(0xFF064B9A);
  static const Color blue = Color(0xFF0875F5);
  static const Color pageBackground = Color(0xFFF4F8FE);

  // ============================================================
  // API
  // ============================================================

  final ApiService _apiService = ApiService();

  // ============================================================
  // SETTINGS
  // ============================================================

  String selectedTheme = ThemeController.instance.isDark ? "Dark" : "Light";

  bool emailNotifications = true;

  // This is connected to backend's browser_notifications
  bool browserNotifications = true;

  int? autoLogout = 30;

  bool isLoading = true;
  bool isSaving = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectivePageBg = isDark ? const Color(0xFF0B132B) : pageBackground;

    if (isLoading) {
      return Scaffold(
        backgroundColor: effectivePageBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Material(
      color: effectivePageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 700;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 28,
              vertical: isMobile ? 16 : 26,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1350),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeading(isMobile),

                    SizedBox(height: isMobile ? 18 : 26),

                    // THEME
                    _buildThemeCard(isMobile),

                    const SizedBox(height: 16),

                    // EMAIL NOTIFICATIONS
                    _buildNotificationCard(
                      isMobile: isMobile,
                      icon: Icons.mail_rounded,
                      title: "Email Notifications",
                      description:
                          "Receive email notifications for important updates",
                      value: emailNotifications,
                      accentColor: const Color(0xFF159447),
                      darkColor: const Color(0xFF08783A),
                      lightColor: const Color(0xFFF1FBF6),
                      onChanged: (value) {
                        setState(() {
                          emailNotifications = value;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // BROWSER / SYSTEM NOTIFICATIONS
                    _buildNotificationCard(
                      isMobile: isMobile,
                      icon: Icons.notifications_rounded,
                      title: "Browser Notifications",
                      description: "Receive system and browser notifications",
                      value: browserNotifications,
                      accentColor: const Color(0xFF6D28D9),
                      darkColor: const Color(0xFF5420A8),
                      lightColor: const Color(0xFFF7F3FF),
                      onChanged: (value) {
                        setState(() {
                          browserNotifications = value;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // AUTO LOGOUT
                    _buildAutoLogoutCard(isMobile),

                    const SizedBox(height: 16),

                    // CHANGE PASSWORD
                    _buildChangePasswordCard(isMobile),

                    SizedBox(height: isMobile ? 20 : 24),

                    // SAVE BUTTON
                    _buildSaveButton(isMobile),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // LOAD SETTINGS FROM BACKEND
  // ============================================================

  Future<void> _loadSettings() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await _apiService.getSettings();

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final settings = UserSettings.fromJson(
              decoded,
              fallbackTheme: ThemeController.instance.currentApiValue,
            );

            setState(() {
              if (decoded.containsKey('theme') && decoded['theme'] != null) {
                selectedTheme = settings.theme == "DARK" ? "Dark" : "Light";
              }
              emailNotifications = settings.emailNotifications;
              browserNotifications = settings.browserNotifications;
              if (decoded.containsKey('auto_logout') ||
                  decoded.containsKey('auto_logout_minutes')) {
                autoLogout = settings.autoLogoutMinutes;
              }
              isLoading = false;
            });

            // Apply theme globally only if returned by backend
            if (decoded.containsKey('theme') && decoded['theme'] != null) {
              await ThemeController.instance.setTheme(settings.theme);
            }

            // Configure global inactivity auto logout
            SessionManager.instance.configureAutoLogout(
              settings.autoLogoutMinutes,
            );
            return;
          }
        } catch (_) {}

        setState(() {
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          isLoading = false;
        });
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
      } else {
        setState(() {
          isLoading = false;
        });

        final errorMsg = _extractErrorMessage(
          response.body,
          fallback:
              "Failed to load settings from server (${response.statusCode}).",
        );
        _showError(errorMsg);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      final errorMsg = _extractErrorMessage(
        e,
        fallback: "Unable to load settings. Please try again.",
      );
      _showError("Unable to load settings: $errorMsg");
    }
  }

  // ============================================================
  // SAVE SETTINGS TO BACKEND
  // ============================================================

  Future<void> _saveSettings() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    final String themeApiValue = selectedTheme == "Dark" ? "DARK" : "LIGHT";

    final Map<String, dynamic> payload = {
      "theme": themeApiValue,
      "email_notifications": emailNotifications,
      "browser_notifications": browserNotifications,
      "auto_logout": autoLogout,
    };

    debugPrint(
      "[Settings] PUT /settings payload: theme=$themeApiValue, email_notifications=$emailNotifications, browser_notifications=$browserNotifications, auto_logout=$autoLogout",
    );

    try {
      final response = await _apiService.updateSettings(payload);

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = _decodeResponse(response.body);
        if (data.isNotEmpty) {
          try {
            final settings = UserSettings.fromJson(
              data,
              fallbackTheme: themeApiValue,
            );
            setState(() {
              if (data.containsKey('theme') && data['theme'] != null) {
                selectedTheme = settings.theme == "DARK" ? "Dark" : "Light";
              } else {
                selectedTheme = themeApiValue == "DARK" ? "Dark" : "Light";
              }
              emailNotifications = settings.emailNotifications;
              browserNotifications = settings.browserNotifications;
              if (data.containsKey('auto_logout') ||
                  data.containsKey('auto_logout_minutes')) {
                autoLogout = settings.autoLogoutMinutes;
              }
            });
          } catch (_) {
            setState(() {
              selectedTheme = themeApiValue == "DARK" ? "Dark" : "Light";
            });
          }
        } else {
          setState(() {
            selectedTheme = themeApiValue == "DARK" ? "Dark" : "Light";
          });
        }

        // Apply theme globally only after save succeeds
        await ThemeController.instance.setTheme(themeApiValue);

        // Update global inactivity auto logout timer
        SessionManager.instance.configureAutoLogout(autoLogout);

        _showSuccess("Settings saved successfully.");
      } else if (response.statusCode == 401) {
        await SessionManager.instance.logoutAndRedirectToLogin(
          reason: "Session expired. Please log in again.",
        );
      } else {
        final errorMsg = _extractErrorMessage(
          response.body,
          fallback: "Failed to save settings (${response.statusCode}).",
        );
        _showError(errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = _extractErrorMessage(
        e,
        fallback: "Unable to save settings. Please try again.",
      );
      _showError("Unable to save settings: $errorMsg");
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // PAGE HEADING
  // ============================================================

  Widget _buildPageHeading(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 17 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF16223F), const Color(0xFF1E2F52)]
              : [const Color(0xFFEAF3FF), const Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF253457) : const Color(0xFFCFE3FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.20)
                : blue.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 68 : 88,
            height: isMobile ? 68 : 88,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C2D4F) : const Color(0xFFDCEBFF),
              borderRadius: BorderRadius.circular(isMobile ? 17 : 21),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF2B3F68)
                    : const Color(0xFFC3DCFC),
              ),
            ),
            child: Icon(
              Icons.settings_rounded,
              color: isDark ? const Color(0xFF60A5FA) : darkBlue,
              size: isMobile ? 39 : 50,
            ),
          ),

          SizedBox(width: isMobile ? 14 : 27),

          Container(
            width: 4,
            height: isMobile ? 58 : 72,
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          SizedBox(width: isMobile ? 14 : 25),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Settings",
                  style: TextStyle(
                    color: isDark ? Colors.white : navy,
                    fontSize: isMobile ? 24 : 31,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Configure your account preferences, notifications and security",
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF52647C),
                    fontSize: isMobile ? 12 : 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (!isMobile)
            Icon(
              Icons.settings_rounded,
              size: 100,
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : blue.withOpacity(0.055),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // THEME CARD
  // ============================================================

  Widget _buildThemeCard(bool isMobile) {
    return _settingsCard(
      accentColor: blue,
      backgroundColor: const Color(0xFFF5F9FF),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: Icons.palette_rounded,
                  title: "Theme",
                  description: "Choose your preferred theme",
                  iconColor: darkBlue,
                  iconBackground: const Color(0xFFDCEBFF),
                  isMobile: true,
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _themeOption(
                        title: "Light",
                        icon: Icons.light_mode_rounded,
                        selected: selectedTheme == "Light",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _themeOption(
                        title: "Dark",
                        icon: Icons.dark_mode_rounded,
                        selected: selectedTheme == "Dark",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text(
                  "Theme preference is synchronized with your account.",
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF718096),
                    fontSize: 11,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _cardInformation(
                    icon: Icons.palette_rounded,
                    title: "Theme",
                    description: "Choose your preferred theme",
                    iconColor: darkBlue,
                    iconBackground: const Color(0xFFDCEBFF),
                    isMobile: false,
                  ),
                ),

                const SizedBox(width: 30),

                SizedBox(
                  width: 390,
                  child: Row(
                    children: [
                      Expanded(
                        child: _themeOption(
                          title: "Light",
                          icon: Icons.light_mode_rounded,
                          selected: selectedTheme == "Light",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _themeOption(
                          title: "Dark",
                          icon: Icons.dark_mode_rounded,
                          selected: selectedTheme == "Dark",
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // THEME OPTION
  // ============================================================

  Widget _themeOption({
    required String title,
    required IconData icon,
    required bool selected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color unselectedBg = isDark ? const Color(0xFF1E2D4A) : Colors.white;
    final Color selectedBg = isDark
        ? const Color(0xFF1E3A6E)
        : const Color(0xFFEAF3FF);
    final Color unselectedBorder = isDark
        ? const Color(0xFF2E4166)
        : const Color(0xFFD2DDEB);
    final Color unselectedTextColor = isDark ? Colors.white : navy;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          selectedTheme = title;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? blue : unselectedBorder,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: blue.withOpacity(0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? blue : unselectedTextColor, size: 21),

            const SizedBox(width: 8),

            Text(
              title,
              style: TextStyle(
                color: selected ? blue : unselectedTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(width: 8),

            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? blue
                  : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF8190A4)),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // NOTIFICATION CARD
  // ============================================================

  Widget _buildNotificationCard({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required Color accentColor,
    required Color darkColor,
    required Color lightColor,
    required ValueChanged<bool> onChanged,
  }) {
    return _settingsCard(
      accentColor: accentColor,
      backgroundColor: lightColor,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: icon,
                  title: title,
                  description: description,
                  iconColor: darkColor,
                  iconBackground: accentColor.withOpacity(0.10),
                  isMobile: true,
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _toggleOption(
                        title: "ON",
                        selected: value,
                        color: accentColor,
                        darkColor: darkColor,
                        onTap: () {
                          onChanged(true);
                        },
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: _toggleOption(
                        title: "OFF",
                        selected: !value,
                        color: accentColor,
                        darkColor: darkColor,
                        onTap: () {
                          onChanged(false);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _cardInformation(
                    icon: icon,
                    title: title,
                    description: description,
                    iconColor: darkColor,
                    iconBackground: accentColor.withOpacity(0.10),
                    isMobile: false,
                  ),
                ),

                const SizedBox(width: 30),

                SizedBox(
                  width: 350,
                  child: Row(
                    children: [
                      Expanded(
                        child: _toggleOption(
                          title: "ON",
                          selected: value,
                          color: accentColor,
                          darkColor: darkColor,
                          onTap: () {
                            onChanged(true);
                          },
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: _toggleOption(
                          title: "OFF",
                          selected: !value,
                          color: accentColor,
                          darkColor: darkColor,
                          onTap: () {
                            onChanged(false);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // AUTO LOGOUT CARD
  // ============================================================

  Widget _buildAutoLogoutCard(bool isMobile) {
    return _settingsCard(
      accentColor: const Color(0xFFE58A00),
      backgroundColor: const Color(0xFFFFF7E8),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: Icons.timer_rounded,
                  title: "Auto Logout",
                  description: "Automatically logout after inactivity",
                  iconColor: const Color(0xFFB96A00),
                  iconBackground: const Color(0xFFFFE8BE),
                  isMobile: true,
                ),

                const SizedBox(height: 18),

                _autoLogoutDropdown(),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _cardInformation(
                    icon: Icons.timer_rounded,
                    title: "Auto Logout",
                    description: "Automatically logout after inactivity",
                    iconColor: const Color(0xFFB96A00),
                    iconBackground: const Color(0xFFFFE8BE),
                    isMobile: false,
                  ),
                ),

                const SizedBox(width: 30),

                SizedBox(width: 350, child: _autoLogoutDropdown()),
              ],
            ),
    );
  }

  // ============================================================
  // AUTO LOGOUT DROPDOWN
  // ============================================================

  Widget _autoLogoutDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isDark ? const Color(0xFF1E2D4A) : Colors.white;
    final dropdownBorder = isDark
        ? const Color(0xFF2E4166)
        : const Color(0xFFE3D7BF);
    final dropdownText = isDark ? Colors.white : navy;

    final options = <Map<String, dynamic>>[
      {"value": null, "label": "Never"},
      {"value": 15, "label": "15 minutes"},
      {"value": 30, "label": "30 minutes"},
      {"value": 60, "label": "1 hour"},
      {"value": 120, "label": "2 hours"},
    ];

    final currentVal = options.any((opt) => opt["value"] == autoLogout)
        ? autoLogout
        : 30;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: dropdownBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dropdownBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: currentVal,
          dropdownColor: dropdownBg,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: dropdownText),
          items: options.map((opt) {
            return DropdownMenuItem<int?>(
              value: opt["value"] as int?,
              child: Text(
                opt["label"] as String,
                style: TextStyle(
                  color: dropdownText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              autoLogout = value;
            });
          },
        ),
      ),
    );
  }

  // ============================================================
  // CHANGE PASSWORD CARD
  // ============================================================

  Widget _buildChangePasswordCard(bool isMobile) {
    const Color accentColor = Color(0xFF0369A1);
    const Color darkColor = Color(0xFF075985);
    const Color lightColor = Color(0xFFF0F7FF);

    return _settingsCard(
      accentColor: accentColor,
      backgroundColor: lightColor,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: Icons.lock_reset_rounded,
                  title: "Change Password",
                  description:
                      "Update your password regularly to keep your account secure and protected.",
                  iconColor: darkColor,
                  iconBackground: accentColor.withValues(alpha: 0.12),
                  isMobile: true,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.lock_outline_rounded, size: 20),
                    label: const Text(
                      "Change Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _cardInformation(
                    icon: Icons.lock_reset_rounded,
                    title: "Change Password",
                    description:
                        "Update your password regularly to keep your account secure and protected.",
                    iconColor: darkColor,
                    iconBackground: accentColor.withValues(alpha: 0.12),
                    isMobile: false,
                  ),
                ),
                const SizedBox(width: 30),
                SizedBox(
                  width: 350,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.lock_outline_rounded, size: 20),
                    label: const Text(
                      "Change Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // CHANGE PASSWORD DIALOG
  // ============================================================

  void _showChangePasswordDialog() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool saving = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dialogBg = isDark ? const Color(0xFF16223F) : Colors.white;
            final titleColor = isDark ? Colors.white : navy;
            final subtitleColor = isDark
                ? const Color(0xFF94A3B8)
                : const Color(0xFF64748B);

            return Dialog(
              backgroundColor: dialogBg,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 500,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0369A1).withOpacity(0.25)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.lock_reset_rounded,
                              color: Color(0xFF38BDF8),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Change Password",
                                  style: TextStyle(
                                    color: titleColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Update your password to keep your account secure",
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF94A3B8),
                            ),
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _dialogPasswordField(
                        controller: currentController,
                        label: "Current Password",
                        hint: "Enter your current password",
                        obscure: obscureCurrent,
                        onToggle: () {
                          setDialogState(() {
                            obscureCurrent = !obscureCurrent;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _dialogPasswordField(
                        controller: newController,
                        label: "New Password",
                        hint: "Enter your new password (min. 8 characters)",
                        obscure: obscureNew,
                        onToggle: () {
                          setDialogState(() {
                            obscureNew = !obscureNew;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _dialogPasswordField(
                        controller: confirmController,
                        label: "Confirm New Password",
                        hint: "Confirm your new password",
                        obscure: obscureConfirm,
                        onToggle: () {
                          setDialogState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final current = currentController.text;
                                      final newPass = newController.text;
                                      final confirmPass =
                                          confirmController.text;

                                      if (current.isEmpty ||
                                          newPass.isEmpty ||
                                          confirmPass.isEmpty) {
                                        setDialogState(() {
                                          errorMessage =
                                              "Please fill all password fields.";
                                        });
                                        return;
                                      }

                                      if (newPass != confirmPass) {
                                        setDialogState(() {
                                          errorMessage =
                                              "New password and Confirm password do not match.";
                                        });
                                        return;
                                      }

                                      if (current == newPass) {
                                        setDialogState(() {
                                          errorMessage =
                                              "New password cannot be the same as the current password.";
                                        });
                                        return;
                                      }

                                      if (newPass.length < 8) {
                                        setDialogState(() {
                                          errorMessage =
                                              "New password must be at least 8 characters long.";
                                        });
                                        return;
                                      }

                                      setDialogState(() {
                                        saving = true;
                                        errorMessage = null;
                                      });

                                      try {
                                        final response = await _apiService
                                            .changePasswordViaSettings({
                                              "current_password": current,
                                              "new_password": newPass,
                                              "confirm_password": confirmPass,
                                            });

                                        final data = _decodeResponse(
                                          response.body,
                                        );

                                        if (response.statusCode >= 200 &&
                                            response.statusCode < 300) {
                                          if (!mounted ||
                                              !dialogContext.mounted) {
                                            return;
                                          }
                                          Navigator.pop(dialogContext);

                                          final bool requireRelogin =
                                              data["require_relogin"] == true ||
                                              data["require_relogin"] == null;
                                          final String msg =
                                              data["message"] ??
                                              "Password changed successfully. Please log in again with your new password.";

                                          if (requireRelogin) {
                                            await SessionManager.instance
                                                .logoutAndRedirectToLogin(
                                                  reason: msg,
                                                );
                                          } else {
                                            _showSuccess(msg);
                                          }
                                        } else if (response.statusCode == 401) {
                                          if (!mounted ||
                                              !dialogContext.mounted) {
                                            return;
                                          }
                                          Navigator.pop(dialogContext);
                                          await SessionManager.instance
                                              .logoutAndRedirectToLogin(
                                                reason:
                                                    "Session expired. Please log in again.",
                                              );
                                        } else {
                                          setDialogState(() {
                                            saving = false;
                                            errorMessage = _extractErrorMessage(
                                              response.body,
                                              fallback:
                                                  "Failed to change password (${response.statusCode}).",
                                            );
                                          });
                                        }
                                      } catch (e) {
                                        setDialogState(() {
                                          saving = false;
                                          errorMessage =
                                              "Unable to change password: ${_extractErrorMessage(e, fallback: 'Please try again.')}";
                                        });
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0369A1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "Update Password",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dialogPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? const Color(0xFFE2E8F0) : navy;
    final fieldFill = isDark
        ? const Color(0xFF1E2D4A)
        : const Color(0xFFF8FAFC);
    final fieldBorder = isDark
        ? const Color(0xFF2E4166)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : navy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(color: textColor, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontSize: 13,
            ),
            filled: true,
            fillColor: fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: blue, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: const Color(0xFF64748B),
                size: 20,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TOGGLE OPTION
  // ============================================================

  Widget _toggleOption({
    required String title,
    required bool selected,
    required Color color,
    required Color darkColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = isDark
        ? const Color(0xFF1E2D4A)
        : Colors.white.withOpacity(0.85);
    final unselectedBorder = isDark
        ? const Color(0xFF2E4166)
        : const Color(0xFFD3DDE9);
    final unselectedTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF65748A);
    final unselectedIconColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF8290A3);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? color.withOpacity(0.22) : color.withOpacity(0.09))
              : unselectedBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : unselectedBorder,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.08),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? (isDark ? Colors.white : darkColor)
                  : unselectedIconColor,
              size: 20,
            ),

            const SizedBox(width: 8),

            Text(
              title,
              style: TextStyle(
                color: selected
                    ? (isDark ? Colors.white : darkColor)
                    : unselectedTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COMMON SETTINGS CARD
  // ============================================================

  Widget _settingsCard({
    required Color accentColor,
    required Color backgroundColor,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveBg = isDark
        ? const Color(0xFF16223F)
        : backgroundColor;
    final Color effectiveBorder = isDark
        ? const Color(0xFF253457)
        : accentColor.withOpacity(0.27);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: effectiveBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.25)
                : accentColor.withOpacity(0.07),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -22,
            top: -20,
            bottom: -20,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(17),
                ),
              ),
            ),
          ),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // CARD INFORMATION
  // ============================================================

  Widget _cardInformation({
    required IconData icon,
    required String title,
    required String description,
    required Color iconColor,
    required Color iconBackground,
    required bool isMobile,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveIconBg = isDark
        ? iconColor.withOpacity(0.18)
        : iconBackground;
    final Color effectiveTitleColor = isDark ? Colors.white : navy;
    final Color effectiveDescColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF596B83);

    return Row(
      children: [
        Container(
          width: isMobile ? 52 : 58,
          height: isMobile ? 52 : 58,
          decoration: BoxDecoration(
            color: effectiveIconBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? iconColor.withOpacity(0.25)
                  : iconColor.withOpacity(0.14),
            ),
          ),
          child: Icon(icon, color: iconColor, size: isMobile ? 25 : 28),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: effectiveTitleColor,
                  fontSize: isMobile ? 15 : 17,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                description,
                style: TextStyle(
                  color: effectiveDescColor,
                  fontSize: isMobile ? 11 : 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SAVE BUTTON
  // ============================================================

  Widget _buildSaveButton(bool isMobile) {
    return Align(
      alignment: isMobile ? Alignment.center : Alignment.centerRight,
      child: SizedBox(
        width: isMobile ? double.infinity : 330,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0875F5), Color(0xFF173FE5)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: blue.withOpacity(0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : _saveSettings,
            icon: isSaving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, color: Colors.white, size: 21),
            label: Text(
              isSaving ? "Saving..." : "Save Changes",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // RESPONSE HELPER
  // ============================================================

  Map<String, dynamic> _decodeResponse(String body) {
    if (body.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  String _extractErrorMessage(
    dynamic raw, {
    String fallback = "An unexpected error occurred.",
  }) {
    return extractSettingsErrorMessage(raw, fallback: fallback);
  }

  // ============================================================
  // SUCCESS
  // ============================================================

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF08783A),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626),
        content: Text(message),
      ),
    );
  }
}
