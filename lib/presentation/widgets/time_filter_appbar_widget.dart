import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TimeFilter { thisWeek, thisMonth, thisYear, custom }

class TimeFilterAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final TimeFilter selectedFilter;
  final DateTime startDate;
  final DateTime endDate;
  final Function(TimeFilter, DateTime, DateTime) onFilterChanged;
  final List<Widget>? additionalActions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool showDateRange;

  const TimeFilterAppBar({
    super.key,
    required this.title,
    required this.selectedFilter,
    required this.startDate,
    required this.endDate,
    required this.onFilterChanged,
    this.additionalActions,
    this.leading,
    this.bottom,
    this.showDateRange = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 2,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
      title: showDateRange
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous button
                if (selectedFilter != TimeFilter.custom)
                  _buildNavigationButton(
                    context,
                    Icons.chevron_left_rounded,
                    () => _navigatePrevious(),
                  ),

                // Time display
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getTimeIcon(),
                        size: 16,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getFormattedTimeRange(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Next button
                if (selectedFilter != TimeFilter.custom)
                  _buildNavigationButton(
                    context,
                    Icons.chevron_right_rounded,
                    () => _navigateNext(),
                  ),
              ],
            )
          : Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
      leading: leading,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).primaryColor.withOpacity(0.2),
          ),
          child: PopupMenuButton<TimeFilter>(
            icon: Icon(
              Icons.tune_rounded,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
            tooltip: 'Lọc thời gian',
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            position: PopupMenuPosition.under,
            onSelected: (filter) => _handleFilterSelection(context, filter),
            itemBuilder: (context) => [
              _buildPopupMenuItem(
                context,
                TimeFilter.thisWeek,
                Icons.view_week_rounded,
                'Tuần này',
              ),
              _buildPopupMenuItem(
                context,
                TimeFilter.thisMonth,
                Icons.calendar_month_rounded,
                'Tháng này',
              ),
              _buildPopupMenuItem(
                context,
                TimeFilter.thisYear,
                Icons.calendar_today_rounded,
                'Năm này',
              ),
              const PopupMenuDivider(),
              _buildPopupMenuItem(
                context,
                TimeFilter.custom,
                Icons.date_range_rounded,
                'Tùy chọn...',
              ),
            ],
          ),
        ),
        if (additionalActions != null) ...additionalActions!,
      ],
      bottom: bottom,
    );
  }

  Widget _buildNavigationButton(
    BuildContext context,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
      ),
    );
  }

  IconData _getTimeIcon() {
    switch (selectedFilter) {
      case TimeFilter.thisWeek:
        return Icons.view_week_rounded;
      case TimeFilter.thisMonth:
        return Icons.calendar_month_rounded;
      case TimeFilter.thisYear:
        return Icons.calendar_today_rounded;
      case TimeFilter.custom:
        return Icons.date_range_rounded;
    }
  }

  String _getFormattedTimeRange() {
    switch (selectedFilter) {
      case TimeFilter.thisMonth:
        return 'T${startDate.month}.${startDate.year}';

      case TimeFilter.thisWeek:
        final weekStart = DateFormat('dd.MM.yy').format(startDate);
        final weekEnd = DateFormat('dd.MM').format(endDate);
        return '$weekStart ~ $weekEnd';

      case TimeFilter.thisYear:
        return 'Năm ${startDate.year}';

      case TimeFilter.custom:
        final formatter = DateFormat('dd/MM/yyyy');
        if (startDate.year == endDate.year &&
            startDate.month == endDate.month &&
            startDate.day == endDate.day) {
          return formatter.format(startDate);
        }
        return '${formatter.format(startDate)} - ${formatter.format(endDate)}';
    }
  }

  void _navigatePrevious() {
    DateTime newStartDate;
    DateTime newEndDate;

    switch (selectedFilter) {
      case TimeFilter.thisMonth:
        newStartDate = DateTime(startDate.year, startDate.month - 1, 1);
        newEndDate = DateTime(newStartDate.year, newStartDate.month + 1, 0);
        break;

      case TimeFilter.thisWeek:
        newStartDate = startDate.subtract(const Duration(days: 7));
        newEndDate = newStartDate.add(const Duration(days: 6));
        break;

      case TimeFilter.thisYear:
        newStartDate = DateTime(startDate.year - 1, 1, 1);
        newEndDate = DateTime(startDate.year - 1, 12, 31);
        break;

      case TimeFilter.custom:
        return;
    }

    onFilterChanged(selectedFilter, newStartDate, newEndDate);
  }

  void _navigateNext() {
    DateTime newStartDate;
    DateTime newEndDate;

    switch (selectedFilter) {
      case TimeFilter.thisMonth:
        newStartDate = DateTime(startDate.year, startDate.month + 1, 1);
        newEndDate = DateTime(newStartDate.year, newStartDate.month + 1, 0);
        break;

      case TimeFilter.thisWeek:
        newStartDate = startDate.add(const Duration(days: 7));
        newEndDate = newStartDate.add(const Duration(days: 6));
        break;

      case TimeFilter.thisYear:
        newStartDate = DateTime(startDate.year + 1, 1, 1);
        newEndDate = DateTime(startDate.year + 1, 12, 31);
        break;

      case TimeFilter.custom:
        return;
    }

    onFilterChanged(selectedFilter, newStartDate, newEndDate);
  }

  @override
  Size get preferredSize {
    double height = kToolbarHeight;
    if (bottom != null) height += bottom!.preferredSize.height;
    return Size.fromHeight(height);
  }

  PopupMenuItem<TimeFilter> _buildPopupMenuItem(
    BuildContext context,
    TimeFilter filter,
    IconData icon,
    String label,
  ) {
    final isSelected = selectedFilter == filter;
    final primaryColor = Theme.of(context).primaryColor;

    return PopupMenuItem(
      value: filter,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected
                    ? primaryColor
                    : Theme.of(context).iconTheme.color,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? primaryColor
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Icon(Icons.check_circle_rounded, size: 18, color: primaryColor),
            ],
          ],
        ),
      ),
    );
  }

  void _handleFilterSelection(BuildContext context, TimeFilter filter) {
    if (filter == TimeFilter.custom) {
      _showCustomDatePicker(context);
    } else {
      _updateDateRange(filter);
    }
  }

  void _updateDateRange(TimeFilter filter) {
    final now = DateTime.now();
    DateTime newStartDate;
    DateTime newEndDate;

    switch (filter) {
      case TimeFilter.thisWeek:
        newStartDate = now.subtract(Duration(days: now.weekday - 1));
        newEndDate = newStartDate.add(const Duration(days: 6));
        break;
      case TimeFilter.thisMonth:
        newStartDate = DateTime(now.year, now.month, 1);
        newEndDate = DateTime(now.year, now.month + 1, 0);
        break;
      case TimeFilter.thisYear:
        newStartDate = DateTime(now.year, 1, 1);
        newEndDate = DateTime(now.year, 12, 31);
        break;
      case TimeFilter.custom:
        newStartDate = startDate;
        newEndDate = endDate;
        break;
    }

    onFilterChanged(filter, newStartDate, newEndDate);
  }

  Future<void> _showCustomDatePicker(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      helpText: 'Chọn khoảng thời gian',
      cancelText: 'Hủy',
      confirmText: 'Xác nhận',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: Theme.of(context).primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onFilterChanged(TimeFilter.custom, picked.start, picked.end);
    }
  }
}

// Extension widget for screens that need both TimeFilter and TabBar
class TimeFilterAppBarWithTabs extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final TimeFilter selectedFilter;
  final DateTime startDate;
  final DateTime endDate;
  final Function(TimeFilter, DateTime, DateTime) onFilterChanged;
  final List<Widget>? additionalActions;
  final TabController tabController;
  final List<Tab> tabs;
  final bool showDateRange;

  const TimeFilterAppBarWithTabs({
    super.key,
    required this.title,
    required this.selectedFilter,
    required this.startDate,
    required this.endDate,
    required this.onFilterChanged,
    required this.tabController,
    required this.tabs,
    this.additionalActions,
    this.showDateRange = true,
  });

  @override
  Widget build(BuildContext context) {
    return TimeFilterAppBar(
      title: title,
      selectedFilter: selectedFilter,
      startDate: startDate,
      endDate: endDate,
      onFilterChanged: onFilterChanged,
      additionalActions: additionalActions,
      showDateRange: showDateRange,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: TabBar(
              controller: tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(
                context,
              ).primaryColor.withOpacity(0.7),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.all(6),
              tabs: tabs
                  .map(
                    (tab) => SizedBox(
                      height: 48,
                      child: Center(child: tab.child ?? Text(tab.text ?? '')),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    double height = kToolbarHeight;
    height += 60; // TabBar section
    return Size.fromHeight(height);
  }
}
