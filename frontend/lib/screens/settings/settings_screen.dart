import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';

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

  String selectedTheme = "Light";

  bool emailNotifications = true;

  // This is connected to backend's browser_notifications
  bool browserNotifications = true;

  int autoLogout = 30;

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
    if (isLoading) {
      return const Scaffold(
        backgroundColor: pageBackground,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Material(
      color: pageBackground,
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
                constraints: const BoxConstraints(
                  maxWidth: 1350,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeading(isMobile),

                    SizedBox(
                      height: isMobile ? 18 : 26,
                    ),

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
                      description:
                          "Receive system and browser notifications",
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

                    SizedBox(
                      height: isMobile ? 20 : 24,
                    ),

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          emailNotifications =
              data["email_notifications"] ?? true;

          browserNotifications =
              data["browser_notifications"] ?? true;

          autoLogout =
              data["auto_logout"] ?? 30;

          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });

        final data = _decodeResponse(response.body);

        _showError(
          data["detail"] ??
              data["message"] ??
              "Failed to load settings.",
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      _showError(
        "Unable to load settings: $e",
      );
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

    try {
      final response =
          await _apiService.updateSettings({
        "email_notifications": emailNotifications,
        "browser_notifications": browserNotifications,
        "auto_logout": autoLogout,
      });

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          emailNotifications =
              data["email_notifications"] ??
                  emailNotifications;

          browserNotifications =
              data["browser_notifications"] ??
                  browserNotifications;

          autoLogout =
              data["auto_logout"] ??
                  autoLogout;
        });

        _showSuccess(
          "Settings saved successfully.",
        );
      } else {
        final data = _decodeResponse(response.body);

        _showError(
          data["detail"] ??
              data["message"] ??
              "Failed to save settings.",
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        "Unable to save settings: $e",
      );
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
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 17 : 24,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF3FF),
            Color(0xFFF8FBFF),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFCFE3FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: blue.withOpacity(0.07),
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
              color: const Color(0xFFDCEBFF),
              borderRadius: BorderRadius.circular(
                isMobile ? 17 : 21,
              ),
              border: Border.all(
                color: const Color(0xFFC3DCFC),
              ),
            ),
            child: Icon(
              Icons.settings_rounded,
              color: darkBlue,
              size: isMobile ? 39 : 50,
            ),
          ),

          SizedBox(
            width: isMobile ? 14 : 27,
          ),

          Container(
            width: 4,
            height: isMobile ? 58 : 72,
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          SizedBox(
            width: isMobile ? 14 : 25,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  "Settings",
                  style: TextStyle(
                    color: navy,
                    fontSize: isMobile ? 24 : 31,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Configure system preferences and notifications",
                  style: TextStyle(
                    color: const Color(0xFF52647C),
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
              color: blue.withOpacity(0.055),
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
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: Icons.palette_rounded,
                  title: "Theme",
                  description:
                      "Choose your preferred theme",
                  iconColor: darkBlue,
                  iconBackground:
                      const Color(0xFFDCEBFF),
                  isMobile: true,
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _themeOption(
                        title: "Light",
                        icon:
                            Icons.light_mode_rounded,
                        selected:
                            selectedTheme == "Light",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _themeOption(
                        title: "Dark",
                        icon:
                            Icons.dark_mode_rounded,
                        selected:
                            selectedTheme == "Dark",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                const Text(
                  "Theme selection is currently a local UI preference.",
                  style: TextStyle(
                    color: Color(0xFF718096),
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
                    description:
                        "Choose your preferred theme",
                    iconColor: darkBlue,
                    iconBackground:
                        const Color(0xFFDCEBFF),
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
                          icon:
                              Icons.light_mode_rounded,
                          selected:
                              selectedTheme ==
                                  "Light",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _themeOption(
                          title: "Dark",
                          icon:
                              Icons.dark_mode_rounded,
                          selected:
                              selectedTheme ==
                                  "Dark",
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          selectedTheme = title;
        });
      },
      child: AnimatedContainer(
        duration:
            const Duration(milliseconds: 180),
        height: 64,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFEAF3FF)
              : Colors.white,
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? blue
                : const Color(0xFFD2DDEB),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color:
                        blue.withOpacity(0.10),
                    blurRadius: 10,
                    offset:
                        const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color:
                  selected ? blue : navy,
              size: 21,
            ),

            const SizedBox(width: 8),

            Text(
              title,
              style: TextStyle(
                color:
                    selected ? blue : navy,
                fontSize: 13,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(width: 8),

            Icon(
              selected
                  ? Icons
                      .radio_button_checked_rounded
                  : Icons
                      .radio_button_off_rounded,
              color: selected
                  ? blue
                  : const Color(0xFF8190A4),
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
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon: icon,
                  title: title,
                  description: description,
                  iconColor: darkColor,
                  iconBackground:
                      accentColor.withOpacity(0.10),
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
                    iconBackground:
                        accentColor.withOpacity(0.10),
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
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _cardInformation(
                  icon:
                      Icons.timer_rounded,
                  title: "Auto Logout",
                  description:
                      "Automatically logout after inactivity",
                  iconColor:
                      const Color(0xFFB96A00),
                  iconBackground:
                      const Color(0xFFFFE8BE),
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
                    icon:
                        Icons.timer_rounded,
                    title: "Auto Logout",
                    description:
                        "Automatically logout after inactivity",
                    iconColor:
                        const Color(0xFFB96A00),
                    iconBackground:
                        const Color(0xFFFFE8BE),
                    isMobile: false,
                  ),
                ),

                const SizedBox(width: 30),

                SizedBox(
                  width: 350,
                  child: _autoLogoutDropdown(),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // AUTO LOGOUT DROPDOWN
  // ============================================================

  Widget _autoLogoutDropdown() {
    const options = [
      5,
      10,
      15,
      30,
      60,
      120,
    ];

    return Container(
      height: 62,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color:
              const Color(0xFFE3D7BF),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: options.contains(autoLogout)
              ? autoLogout
              : 30,
          isExpanded: true,
          icon: const Icon(
            Icons
                .keyboard_arrow_down_rounded,
          ),
          items: options.map(
            (minutes) {
              return DropdownMenuItem<int>(
                value: minutes,
                child: Text(
                  "$minutes minutes",
                  style: const TextStyle(
                    color: navy,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              );
            },
          ).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              autoLogout = value;
            });
          },
        ),
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(12),
      child: AnimatedContainer(
        duration:
            const Duration(milliseconds: 180),
        height: 62,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.09)
              : Colors.white.withOpacity(0.85),
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color
                : const Color(0xFFD3DDE9),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color:
                        color.withOpacity(0.08),
                    blurRadius: 9,
                    offset:
                        const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons
                      .check_circle_rounded
                  : Icons
                      .radio_button_off_rounded,
              color: selected
                  ? darkColor
                  : const Color(0xFF8290A3),
              size: 20,
            ),

            const SizedBox(width: 8),

            Text(
              title,
              style: TextStyle(
                color: selected
                    ? darkColor
                    : const Color(0xFF65748A),
                fontSize: 13,
                fontWeight:
                    FontWeight.w900,
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
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color:
              accentColor.withOpacity(0.27),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                accentColor.withOpacity(0.07),
            blurRadius: 15,
            offset:
                const Offset(0, 5),
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
              decoration:
                  BoxDecoration(
                color: accentColor,
                borderRadius:
                    const BorderRadius
                        .horizontal(
                  left:
                      Radius.circular(17),
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
    return Row(
      children: [
        Container(
          width: isMobile ? 52 : 58,
          height: isMobile ? 52 : 58,
          decoration: BoxDecoration(
            color: iconBackground,
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  iconColor.withOpacity(0.14),
            ),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: isMobile ? 25 : 28,
          ),
        ),

        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: navy,
                  fontSize:
                      isMobile ? 15 : 17,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                description,
                style: TextStyle(
                  color:
                      const Color(0xFF596B83),
                  fontSize:
                      isMobile ? 11 : 13,
                  height: 1.35,
                  fontWeight:
                      FontWeight.w500,
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
      alignment: isMobile
          ? Alignment.center
          : Alignment.centerRight,
      child: SizedBox(
        width:
            isMobile ? double.infinity : 330,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(
              colors: [
                Color(0xFF0875F5),
                Color(0xFF173FE5),
              ],
            ),
            borderRadius:
                BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color:
                    blue.withOpacity(0.25),
                blurRadius: 14,
                offset:
                    const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed:
                isSaving ? null : _saveSettings,
            icon: isSaving
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.save_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
            label: Text(
              isSaving
                  ? "Saving..."
                  : "Save Changes",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
            style:
                ElevatedButton.styleFrom(
              backgroundColor:
                  Colors.transparent,
              disabledBackgroundColor:
                  Colors.transparent,
              shadowColor:
                  Colors.transparent,
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(13),
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

  Map<String, dynamic> _decodeResponse(
    String body,
  ) {
    if (body.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded
          is Map<String, dynamic>) {
        return decoded;
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  // SUCCESS
  // ============================================================

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        behavior:
            SnackBarBehavior.floating,
        backgroundColor:
            const Color(0xFF08783A),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        behavior:
            SnackBarBehavior.floating,
        backgroundColor:
            const Color(0xFFDC2626),
        content: Text(message),
      ),
    );
  }
}