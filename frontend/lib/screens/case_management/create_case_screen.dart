import 'package:flutter/material.dart';

class CreateCaseScreen extends StatefulWidget {
  const CreateCaseScreen({super.key});

  @override
  State<CreateCaseScreen> createState() => _CreateCaseScreenState();
}

class _CreateCaseScreenState extends State<CreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController();

  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  String? selectedInvestigator;
  String? selectedPriority;

  bool isSubmitting = false;

  // Temporary investigators.
  // Later GET /investigators API se load honge.
  final List<String> investigators = [
    "Rahul Sharma",
    "Sneha Verma",
    "Amit Patil",
    "Priya Singh",
  ];

  final List<String> priorities = [
    "Low",
    "Medium",
    "High",
    "Critical",
  ];

  @override
  void initState() {
    super.initState();

    _titleFocus.addListener(_refreshFocus);
    _descriptionFocus.addListener(_refreshFocus);
  }

  void _refreshFocus() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();

    _titleFocus.removeListener(_refreshFocus);
    _descriptionFocus.removeListener(_refreshFocus);

    _titleFocus.dispose();
    _descriptionFocus.dispose();

    super.dispose();
  }

  // =========================================================
  // PRIORITY COLOR
  // =========================================================

  Color _priorityColor(String priority) {
    switch (priority) {
      case "Low":
        return const Color(0xFF10B981);

      case "Medium":
        return const Color(0xFFFF9800);

      case "High":
        return const Color(0xFFEF4444);

      case "Critical":
        return const Color(0xFF8B35E8);

      default:
        return const Color(0xFF0875F5);
    }
  }

  // =========================================================
  // CREATE CASE
  // =========================================================

  Future<void> _createCase() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (selectedInvestigator == null) {
      _showMessage("Please select an investigator.");
      return;
    }

    if (selectedPriority == null) {
      _showMessage("Please select case priority.");
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      // =====================================================
      // BACKEND API WILL BE CONNECTED HERE
      //
      // POST /cases
      //
      // {
      //   "title": _titleController.text.trim(),
      //   "description": _descriptionController.text.trim(),
      //   "investigator_id": investigatorId,
      //   "priority": selectedPriority
      // }
      // =====================================================

      await Future.delayed(
        const Duration(milliseconds: 700),
      );

      if (!mounted) return;

      _showSuccessDialog();
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =========================================================
  // SUCCESS DIALOG
  // =========================================================

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE8F3FF),
                child: Icon(
                  Icons.check_rounded,
                  color: Color(0xFF0875F5),
                ),
              ),
              SizedBox(width: 12),
              Text(
                "Case Created",
                style: TextStyle(
                  color: Color(0xFF071B33),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            "The new investigation case has been created successfully.",
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                _titleController.clear();
                _descriptionController.clear();

                setState(() {
                  selectedInvestigator = null;
                  selectedPriority = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0875F5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // MAIN SCREEN
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 700;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 28,
            vertical: isMobile ? 18 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1250,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // =================================================
                  // BREADCRUMB
                  // =================================================

                  _buildBreadcrumb(isMobile),

                  SizedBox(
                    height: isMobile ? 14 : 16,
                  ),

                  // =================================================
                  // NEW CASE HEADER
                  // =================================================

                  _buildHeader(isMobile),

                  SizedBox(
                    height: isMobile ? 18 : 20,
                  ),

                  // =================================================
                  // FORM CARD
                  // =================================================

                  _buildFormCard(isMobile),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // BREADCRUMB
  // =========================================================

  Widget _buildBreadcrumb(bool isMobile) {
    return Row(
      children: [
        const Text(
          "Dashboard",
          style: TextStyle(
            color: Color(0xFF0875F5),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(width: 8),

        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Color(0xFF9AA8BA),
        ),

        const SizedBox(width: 8),

        Text(
          "New Case",
          style: TextStyle(
            color: Colors.blueGrey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      height: isMobile ? 120 : 132,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFE6F1FF),
            Color(0xFFF3F8FF),
            Color(0xFFF8FBFF),
          ],
        ),
      ),
      child: Stack(
        children: [
          // =================================================
          // RIGHT CYBER / SHIELD DESIGN
          // =================================================

          Positioned(
            right: isMobile ? -80 : -10,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(
                  isMobile ? 220 : 390,
                  isMobile ? 120 : 132,
                ),
                painter: HeaderCyberPainter(),
              ),
            ),
          ),

          // =================================================
          // HEADER CONTENT
          // =================================================

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: 14,
            ),
            child: Row(
              children: [
                // =============================================
                // LARGE CASE + ICON
                // =============================================

                Container(
                  width: isMobile ? 68 : 78,
                  height: isMobile ? 68 : 78,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEBFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0875F5)
                            .withOpacity(0.14),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.business_center_rounded,
                        color: const Color(0xFF0866DF),
                        size: isMobile ? 34 : 39,
                      ),

                      Positioned(
                        right: isMobile ? 10 : 12,
                        bottom: isMobile ? 11 : 12,
                        child: Container(
                          width: isMobile ? 21 : 23,
                          height: isMobile ? 21 : 23,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0875F5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFDCEBFF),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  width: isMobile ? 14 : 18,
                ),

                // =============================================
                // BLUE VERTICAL ACCENT
                // =============================================

                Container(
                  width: 3,
                  height: isMobile ? 66 : 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0866DF),
                        Color(0xFF2C8BFF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                SizedBox(
                  width: isMobile ? 14 : 18,
                ),

                // =============================================
                // TITLE
                // =============================================

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "New Case",
                        style: TextStyle(
                          fontSize: isMobile ? 24 : 29,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF071B33),
                          letterSpacing: -0.3,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        "Create a new investigation case. Fill in the details below to get started.",
                        maxLines: isMobile ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 14,
                          height: 1.4,
                          color: const Color(0xFF63728A),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isMobile)
                  const SizedBox(width: 230),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // FORM CARD
  // =========================================================

  Widget _buildFormCard(bool isMobile) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6E7FF),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0875F5)
                .withOpacity(0.09),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // =================================================
          // TOP RIGHT FORM CYBER LINES
          // =================================================

          Positioned(
            right: -15,
            top: -8,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(
                  isMobile ? 180 : 310,
                  isMobile ? 105 : 135,
                ),
                painter: HeaderCyberPainter(),
              ),
            ),
          ),

          // =================================================
          // FORM
          // =================================================

          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 18 : 28,
              isMobile ? 22 : 26,
              isMobile ? 18 : 28,
              isMobile ? 24 : 30,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CASE TITLE

                  _fieldLabel("Case Title"),

                  const SizedBox(height: 9),

                  _buildTextField(
                    controller: _titleController,
                    focusNode: _titleFocus,
                    hint: "Enter case title",
                    icon: Icons.description_rounded,
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return "Case title is required";
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 23),

                  // DESCRIPTION

                  _fieldLabel(
                    "Case Description",
                  ),

                  const SizedBox(height: 9),

                  _buildTextField(
                    controller: _descriptionController,
                    focusNode: _descriptionFocus,
                    hint: "Enter case description...",
                    icon: Icons.article_rounded,
                    maxLines: isMobile ? 5 : 6,
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return "Case description is required";
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 23),

                  // =================================================
                  // INVESTIGATOR + PRIORITY
                  // =================================================

                  if (isMobile)
                    Column(
                      children: [
                        _buildInvestigatorField(),

                        const SizedBox(height: 20),

                        _buildPriorityField(),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child:
                              _buildInvestigatorField(),
                        ),

                        const SizedBox(width: 22),

                        Expanded(
                          child:
                              _buildPriorityField(),
                        ),
                      ],
                    ),

                  const SizedBox(height: 28),

                  // CREATE BUTTON

                  _buildCreateButton(isMobile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // FIELD LABEL
  // =========================================================

  Widget _fieldLabel(String text) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xFF071B33),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(
            text: "  *",
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TEXT FIELD
  // =========================================================

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final bool focused = focusNode.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF0875F5)
                      .withOpacity(0.13),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(
          color: Color(0xFF071B33),
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFF8492A6),
          ),
          filled: true,
          fillColor: const Color(0xFFFBFDFF),

          prefixIcon: Padding(
            padding: EdgeInsets.only(
              left: 10,
              right: 10,
              top: maxLines > 1 ? 10 : 8,
              bottom: maxLines > 1 ? 90 : 8,
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
  icon,
  color: const Color(0xFF064DB8),
  size: 23,
),
            ),
          ),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFFD7E1EE),
            ),
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFF0875F5),
              width: 1.7,
            ),
          ),

          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFFEF4444),
            ),
          ),

          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Color(0xFFEF4444),
              width: 1.5,
            ),
          ),

          contentPadding: EdgeInsets.symmetric(
            horizontal: 15,
            vertical: maxLines > 1 ? 18 : 14,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // INVESTIGATOR
  // =========================================================

  Widget _buildInvestigatorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel("Investigator"),

        const SizedBox(height: 9),

        DropdownButtonFormField<String>(
          value: selectedInvestigator,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF071B33),
          ),
          decoration: _dropdownDecoration(
            Icons.people_alt_rounded,
          ),
          hint: const Text(
            "Select investigator",
            style: TextStyle(
              color: Color(0xFF8492A6),
              fontSize: 14,
            ),
          ),
          items: investigators.map((investigator) {
            return DropdownMenuItem(
              value: investigator,
              child: Text(
                investigator,
                style: const TextStyle(
                  color: Color(0xFF071B33),
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedInvestigator = value;
            });
          },
          validator: (value) {
            if (value == null) {
              return "Please select investigator";
            }

            return null;
          },
        ),
      ],
    );
  }

  // =========================================================
  // PRIORITY
  // =========================================================

  Widget _buildPriorityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel("Priority"),

        const SizedBox(height: 9),

        DropdownButtonFormField<String>(
          value: selectedPriority,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF071B33),
          ),
          decoration: _dropdownDecoration(
            Icons.flag_rounded,
          ),
          hint: const Text(
            "Select priority",
            style: TextStyle(
              color: Color(0xFF8492A6),
              fontSize: 14,
            ),
          ),
          items: priorities.map((priority) {
            final color = _priorityColor(priority);

            return DropdownMenuItem(
              value: priority,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),

                  const SizedBox(width: 11),

                  Text(
                    priority,
                    style: const TextStyle(
                      color: Color(0xFF071B33),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedPriority = value;
            });
          },
          validator: (value) {
            if (value == null) {
              return "Please select priority";
            }

            return null;
          },
        ),
      ],
    );
  }

  // =========================================================
  // DROPDOWN DECORATION
  // =========================================================

  InputDecoration _dropdownDecoration(
    IconData icon,
  ) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFFBFDFF),

      prefixIcon: Padding(
        padding: const EdgeInsets.all(9),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF064DB8),
            size: 21,
          ),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFD7E1EE),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFF0875F5),
          width: 1.7,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
          width: 1.5,
        ),
      ),

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
    );
  }

  // =========================================================
  // CREATE BUTTON
  // =========================================================

  Widget _buildCreateButton(bool isMobile) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        width: isMobile ? double.infinity : 205,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFF064DB8),
              Color(0xFF0875F5),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0875F5)
                  .withOpacity(0.30),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isSubmitting ? null : _createCase,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_box_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                        SizedBox(width: 9),
                        Text(
                          "Create Case",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// HEADER CYBER / SHIELD PAINTER
// =============================================================
class HeaderCyberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()
      ..color = const Color(0xFF0875F5).withOpacity(0.10)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = const Color(0xFF0875F5).withOpacity(0.14)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // =====================================================
    // FOLDER
    // =====================================================

    final double folderX = size.width * 0.76;
    final double folderY = size.height * 0.28;
    final double folderW = size.width * 0.13;
    final double folderH = size.height * 0.38;

    final folder = Path();

    folder.moveTo(
      folderX,
      folderY + folderH * 0.18,
    );

    folder.lineTo(
      folderX + folderW * 0.32,
      folderY + folderH * 0.18,
    );

    folder.lineTo(
      folderX + folderW * 0.42,
      folderY,
    );

    folder.lineTo(
      folderX + folderW * 0.68,
      folderY,
    );

    folder.lineTo(
      folderX + folderW * 0.78,
      folderY + folderH * 0.18,
    );

    folder.lineTo(
      folderX + folderW,
      folderY + folderH * 0.18,
    );

    folder.lineTo(
      folderX + folderW,
      folderY + folderH,
    );

    folder.lineTo(
      folderX,
      folderY + folderH,
    );

    folder.close();

    canvas.drawPath(
      folder,
      lightPaint,
    );

    canvas.drawPath(
      folder,
      outlinePaint,
    );

    // =====================================================
    // MAGNIFYING GLASS
    // =====================================================

    final Offset searchCenter = Offset(
      size.width * 0.88,
      size.height * 0.58,
    );

    final double searchRadius =
        size.height * 0.14;

    canvas.drawCircle(
      searchCenter,
      searchRadius,
      outlinePaint,
    );

    canvas.drawLine(
      Offset(
        searchCenter.dx + searchRadius * 0.70,
        searchCenter.dy + searchRadius * 0.70,
      ),
      Offset(
        searchCenter.dx + searchRadius * 1.65,
        searchCenter.dy + searchRadius * 1.65,
      ),
      outlinePaint,
    );

    // =====================================================
    // SMALL DECORATIVE PLUS
    // =====================================================

    final plusPaint = Paint()
      ..color = const Color(0xFF0875F5).withOpacity(0.18)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final Offset plusCenter = Offset(
      size.width * 0.70,
      size.height * 0.30,
    );

    canvas.drawLine(
      Offset(
        plusCenter.dx - 6,
        plusCenter.dy,
      ),
      Offset(
        plusCenter.dx + 6,
        plusCenter.dy,
      ),
      plusPaint,
    );

    canvas.drawLine(
      Offset(
        plusCenter.dx,
        plusCenter.dy - 6,
      ),
      Offset(
        plusCenter.dx,
        plusCenter.dy + 6,
      ),
      plusPaint,
    );

    // =====================================================
    // SMALL DOTS
    // =====================================================

    final dotPaint = Paint()
      ..color = const Color(0xFF0875F5).withOpacity(0.18)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(
        size.width * 0.73,
        size.height * 0.68,
      ),
      3,
      dotPaint,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.94,
        size.height * 0.27,
      ),
      2.5,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}