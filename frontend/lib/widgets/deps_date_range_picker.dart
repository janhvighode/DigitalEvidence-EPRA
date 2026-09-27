import 'package:flutter/material.dart';

/// Reusable DEPS Date Range Picker that strictly conforms to the
/// two-column desktop/tablet layout and responsive mobile design.
///
/// Features:
/// - Left: Presets (Today, Yesterday, Last 7 Days, Last 14 Days, Last 30 Days, Last 90 Days)
/// - Right: Month + Year header with < / > navigation, weekday header (Su Mo Tu We Th Fr Sa),
///   calendar grid with selected range highlighting.
/// - Bottom: Cancel & Apply buttons.
/// - Temporary state: No API calls or outer state changes until [Apply] is clicked.
/// - Cancel: Discards selection and returns null.
/// - Dark/Light Theme: Respects app brightness and DEPS theme tokens.
Future<DateTimeRange?> showDepsDateRangePicker({
  required BuildContext context,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTimeRange?>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => DepsDateRangePickerDialog(
      initialStartDate: initialStartDate,
      initialEndDate: initialEndDate,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
    ),
  );
}

class DepsDateRangePickerDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const DepsDateRangePickerDialog({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<DepsDateRangePickerDialog> createState() =>
      _DepsDateRangePickerDialogState();
}

class _DepsDateRangePickerDialogState extends State<DepsDateRangePickerDialog> {
  DateTime? _tempStart;
  DateTime? _tempEnd;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    if (widget.initialStartDate != null) {
      _tempStart = DateTime(
        widget.initialStartDate!.year,
        widget.initialStartDate!.month,
        widget.initialStartDate!.day,
      );
    }
    if (widget.initialEndDate != null) {
      _tempEnd = DateTime(
        widget.initialEndDate!.year,
        widget.initialEndDate!.month,
        widget.initialEndDate!.day,
      );
    }

    final initialTarget = _tempEnd ?? _tempStart ?? DateTime.now();
    _displayedMonth = DateTime(initialTarget.year, initialTarget.month, 1);
  }

  // Presets definition
  static const List<String> _presets = [
    "Today",
    "Yesterday",
    "Last 7 days",
    "Last 14 days",
    "Last 30 days",
    "Last 90 days",
  ];

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTimeRange _getPresetRange(String preset) {
    final today = _today();
    switch (preset) {
      case "Today":
        return DateTimeRange(start: today, end: today);
      case "Yesterday":
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: yesterday, end: yesterday);
      case "Last 7 days":
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case "Last 14 days":
        return DateTimeRange(
          start: today.subtract(const Duration(days: 13)),
          end: today,
        );
      case "Last 30 days":
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case "Last 90 days":
        return DateTimeRange(
          start: today.subtract(const Duration(days: 89)),
          end: today,
        );
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  bool _isPresetActive(String preset) {
    if (_tempStart == null || _tempEnd == null) return false;
    final range = _getPresetRange(preset);
    return _isSameDay(_tempStart!, range.start) &&
        _isSameDay(_tempEnd!, range.end);
  }

  void _applyPreset(String preset) {
    final range = _getPresetRange(preset);
    setState(() {
      _tempStart = range.start;
      _tempEnd = range.end;
      _displayedMonth = DateTime(range.end.year, range.end.month, 1);
    });
  }

  void _onDaySelected(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);

    setState(() {
      if (_tempStart == null || (_tempStart != null && _tempEnd != null)) {
        _tempStart = normalized;
        _tempEnd = null;
      } else {
        if (normalized.isBefore(_tempStart!)) {
          _tempEnd = _tempStart;
          _tempStart = normalized;
        } else {
          _tempEnd = normalized;
        }
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isInRange(DateTime day) {
    if (_tempStart == null || _tempEnd == null) return false;
    return day.isAfter(_tempStart!) && day.isBefore(_tempEnd!);
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
        1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      );
    });
  }

  String _getMonthName(int month) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme palette
    final dialogBg = isDark ? const Color(0xFF0F1B2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF233554) : const Color(0xFFE2E8F0);
    final primaryBlue = const Color(0xFF0875F5);
    final textPrimary = isDark ? Colors.white : const Color(0xFF071B33);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final rangeHighlightBg = isDark ? const Color(0xFF1E3A6B) : const Color(0xFFE8F1FC);
    final headerDivider = isDark ? const Color(0xFF1E2D4A) : const Color(0xFFF1F5F9);

    final mediaWidth = MediaQuery.of(context).size.width;
    final isCompact = mediaWidth < 540;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Container(
          width: isCompact ? 340 : 520,
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(
            color: dialogBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      color: primaryBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Pick a date range",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: textMuted),
                      splashRadius: 18,
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: headerDivider),

              // Content Body (Two-column or compact stacked)
              Flexible(
                child: SingleChildScrollView(
                  child: isCompact
                      ? Column(
                          children: [
                            _buildPresetList(isDark, textPrimary, textMuted, primaryBlue, isCompact: true),
                            Divider(height: 1, thickness: 1, color: headerDivider),
                            _buildCalendar(isDark, textPrimary, textMuted, primaryBlue, rangeHighlightBg),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 170,
                              child: _buildPresetList(isDark, textPrimary, textMuted, primaryBlue),
                            ),
                            Container(
                              width: 1,
                              height: 330,
                              color: headerDivider,
                            ),
                            Expanded(
                              child: _buildCalendar(isDark, textPrimary, textMuted, primaryBlue, rangeHighlightBg),
                            ),
                          ],
                        ),
                ),
              ),

              Divider(height: 1, thickness: 1, color: headerDivider),

              // Footer Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: textMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (_tempStart != null) {
                          final finalEnd = _tempEnd ?? _tempStart!;
                          Navigator.of(context).pop(
                            DateTimeRange(start: _tempStart!, end: finalEnd),
                          );
                        } else {
                          Navigator.of(context).pop(null);
                        }
                      },
                      child: const Text(
                        "Apply",
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetList(
    bool isDark,
    Color textPrimary,
    Color textMuted,
    Color primaryBlue, {
    bool isCompact = false,
  }) {
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _presets.map((preset) {
            final active = _isPresetActive(preset);
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _applyPreset(preset),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark ? const Color(0xFF1E3A6B) : const Color(0xFFE8F1FC))
                      : (isDark ? const Color(0xFF16253D) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: active ? primaryBlue : (isDark ? const Color(0xFF233554) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Text(
                  preset,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? primaryBlue : textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _presets.map((preset) {
          final active = _isPresetActive(preset);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _applyPreset(preset),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark ? const Color(0xFF162A4A) : const Color(0xFFEAF3FF))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  preset,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? primaryBlue : textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendar(
    bool isDark,
    Color textPrimary,
    Color textMuted,
    Color primaryBlue,
    Color rangeHighlightBg,
  ) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final monthName = _getMonthName(month);

    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);

    // Weekday of 1st day (0 = Sunday in our header Su Mo Tu We Th Fr Sa)
    // Dart: DateTime.weekday: Monday is 1, Sunday is 7.
    // Sunday should be index 0:
    final int startOffset = firstDayOfMonth.weekday % 7;

    // Previous month filler days
    final prevMonthDate = DateTime(year, month - 1, 1);
    final daysInPrevMonth = DateUtils.getDaysInMonth(prevMonthDate.year, prevMonthDate.month);

    final List<Widget> dayWidgets = [];

    // Weekday labels
    const weekDays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];
    for (final dayLabel in weekDays) {
      dayWidgets.add(
        Center(
          child: Text(
            dayLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
        ),
      );
    }

    // Leading days from previous month
    for (int i = startOffset - 1; i >= 0; i--) {
      final dayNumber = daysInPrevMonth - i;
      dayWidgets.add(
        Center(
          child: Text(
            "$dayNumber",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      );
    }

    // Days of current month
    for (int day = 1; day <= daysInMonth; day++) {
      final current = DateTime(year, month, day);
      final isStart = _tempStart != null && _isSameDay(current, _tempStart!);
      final isEnd = _tempEnd != null && _isSameDay(current, _tempEnd!);
      final inRange = _isInRange(current);

      dayWidgets.add(
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _onDaySelected(current),
          child: Container(
            decoration: BoxDecoration(
              color: (isStart || isEnd)
                  ? primaryBlue
                  : (inRange ? rangeHighlightBg : Colors.transparent),
              shape: (isStart || isEnd) ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: (isStart || isEnd)
                  ? null
                  : (inRange ? BorderRadius.circular(4) : null),
            ),
            child: Center(
              child: Text(
                "$day",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: (isStart || isEnd)
                      ? FontWeight.w700
                      : (inRange ? FontWeight.w600 : FontWeight.w500),
                  color: (isStart || isEnd)
                      ? Colors.white
                      : (inRange
                          ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))
                          : textPrimary),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Trailing days from next month to complete the row
    final totalCells = startOffset + daysInMonth;
    final trailingDays = (7 - (totalCells % 7)) % 7;
    for (int day = 1; day <= trailingDays; day++) {
      dayWidgets.add(
        Center(
          child: Text(
            "$day",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Month navigation header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                color: textPrimary,
                splashRadius: 18,
                onPressed: _previousMonth,
              ),
              Text(
                "$monthName $year",
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                color: textPrimary,
                splashRadius: 18,
                onPressed: _nextMonth,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Calendar Grid
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 2,
            childAspectRatio: 1.1,
            children: dayWidgets,
          ),
        ],
      ),
    );
  }
}

/// Helper extension or utility class to format date query params as YYYY-MM-DD
/// and clean human-readable ranges.
class DepsDateFormat {
  static String toQueryDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  static String toDisplayRange(DateTime start, DateTime end) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    final startStr = "${start.day} ${months[start.month - 1]} ${start.year}";
    final endStr = "${end.day} ${months[end.month - 1]} ${end.year}";
    if (startStr == endStr) {
      return startStr;
    }
    return "$startStr – $endStr";
  }
}
