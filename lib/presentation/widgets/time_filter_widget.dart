import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TimeFilter { thisWeek, thisMonth, thisYear, custom }

class TimeFilterWidget extends StatelessWidget {
  final TimeFilter selectedFilter;
  final DateTime startDate;
  final DateTime endDate;
  final Function(TimeFilter, DateTime, DateTime) onFilterChanged;
  final bool showDateRange;

  const TimeFilterWidget({
    super.key,
    required this.selectedFilter,
    required this.startDate,
    required this.endDate,
    required this.onFilterChanged,
    this.showDateRange = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter chips
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                FilterChip(
                  label: const Text('Tuần này'),
                  selected: selectedFilter == TimeFilter.thisWeek,
                  onSelected: (_) =>
                      _updateFilter(TimeFilter.thisWeek, context),
                  selectedColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                ),
                FilterChip(
                  label: const Text('Tháng này'),
                  selected: selectedFilter == TimeFilter.thisMonth,
                  onSelected: (_) =>
                      _updateFilter(TimeFilter.thisMonth, context),
                  selectedColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                ),
                FilterChip(
                  label: const Text('Năm này'),
                  selected: selectedFilter == TimeFilter.thisYear,
                  onSelected: (_) =>
                      _updateFilter(TimeFilter.thisYear, context),
                  selectedColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                ),
                FilterChip(
                  label: const Text('Tùy chọn'),
                  selected: selectedFilter == TimeFilter.custom,
                  onSelected: (_) => _selectCustomDateRange(context),
                  selectedColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                ),
              ],
            ),

            // Show current date range
            if (showDateRange) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _getDateRangeText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _updateFilter(TimeFilter filter, BuildContext context) {
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
        // Keep current dates for custom
        newStartDate = startDate;
        newEndDate = endDate;
        break;
    }

    onFilterChanged(filter, newStartDate, newEndDate);
  }

  Future<void> _selectCustomDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      helpText: 'Chọn khoảng thời gian',
      cancelText: 'Hủy',
      confirmText: 'Xác nhận',
    );

    if (picked != null) {
      onFilterChanged(TimeFilter.custom, picked.start, picked.end);
    }
  }

  String _getDateRangeText() {
    final formatter = DateFormat('dd/MM/yyyy');
    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return formatter.format(startDate);
    }
    return '${formatter.format(startDate)} - ${formatter.format(endDate)}';
  }
}
