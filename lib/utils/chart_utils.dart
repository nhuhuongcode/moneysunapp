import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ChartUtils {
  // Safe interval calculation for X-axis (time-based)
  static double calculateTimeInterval(List<FlSpot> spots) {
    if (spots.length <= 1) {
      return 86400000; // 1 day in milliseconds
    }

    final totalRange = spots.last.x - spots.first.x;
    if (totalRange <= 0) {
      return 86400000; // Fallback to 1 day
    }

    // Calculate interval for approximately 4-5 labels
    double interval = totalRange / 4;

    // Ensure minimum interval of 1 hour (3600000 ms)
    if (interval < 3600000) {
      interval = 3600000;
    }

    // Ensure maximum interval of 30 days (2592000000 ms)
    if (interval > 2592000000) {
      interval = 2592000000;
    }

    return interval;
  }

  // Safe interval calculation for Y-axis (value-based)
  static double calculateValueInterval(List<FlSpot> spots) {
    if (spots.isEmpty) {
      return 100000; // Default fallback
    }

    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);

    final yRange = maxY - minY;

    // If all values are the same or range is too small
    if (yRange <= 0) {
      return maxY > 0 ? maxY / 4 : 100000;
    }

    // Calculate interval for approximately 4-5 horizontal grid lines
    double interval = yRange / 4;

    // Ensure minimum interval
    if (interval < 1) {
      interval = 1;
    }

    return interval;
  }

  // Get safe min/max Y values with padding
  static (double minY, double maxY) getSafeYRange(List<FlSpot> spots) {
    if (spots.isEmpty) {
      return (0, 100);
    }

    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);

    // Add 10% padding
    final yRange = maxY - minY;
    final padding = yRange * 0.1;

    return (
      (minY - padding).clamp(
        0,
        double.infinity,
      ), // Don't go below 0 for money values
      maxY + padding,
    );
  }

  // Format currency for chart labels
  static String formatCurrency(double value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B₫';
    } else if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M₫';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K₫';
    } else {
      return '${value.toStringAsFixed(0)}₫';
    }
  }

  // Generate colors for pie chart categories
  static List<Color> generateCategoryColors(int count) {
    const baseColors = [
      Color(0xFF2196F3), // Blue
      Color(0xFF4CAF50), // Green
      Color(0xFFFF9800), // Orange
      Color(0xFF9C27B0), // Purple
      Color(0xFFF44336), // Red
      Color(0xFF009688), // Teal
      Color(0xFFFFEB3B), // Amber
      Color(0xFF3F51B5), // Indigo
      Color(0xFFE91E63), // Pink
      Color(0xFF795548), // Brown
    ];

    List<Color> colors = [];
    for (int i = 0; i < count; i++) {
      colors.add(baseColors[i % baseColors.length]);
    }

    return colors;
  }

  // Create safe line chart data
  static LineChartData createSafeLineChartData({
    required List<FlSpot> spots,
    required Color lineColor,
    bool showDots = true,
    bool showGrid = true,
    bool showTitles = true,
  }) {
    final (minY, maxY) = getSafeYRange(spots);

    return LineChartData(
      gridData: FlGridData(
        show: showGrid,
        drawVerticalLine: false,
        horizontalInterval: calculateValueInterval(spots),
        getDrawingHorizontalLine: (value) {
          return const FlLine(color: Color(0xFFE0E0E0), strokeWidth: 0.5);
        },
      ),
      titlesData: FlTitlesData(
        show: showTitles,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showTitles,
            reservedSize: 35,
            interval: calculateTimeInterval(spots),
            getTitlesWidget: (value, meta) {
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${date.day}/${date.month}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              );
            },
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: lineColor,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: showDots,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 3,
                color: lineColor,
                strokeWidth: 2,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: lineColor.withOpacity(0.15),
          ),
        ),
      ],
    );
  }
}
