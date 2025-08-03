import 'package:flutter/material.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/transaction_list_item.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

enum TimeRangeFilter { thisWeek, thisMonth, custom }

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  late DateTime _startDate;
  late DateTime _endDate;
  TimeRangeFilter _selectedFilter = TimeRangeFilter.thisMonth;

  @override
  void initState() {
    super.initState();
    _updateDateRange(TimeRangeFilter.thisMonth);
  }

  void _updateDateRange(TimeRangeFilter filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      if (filter == TimeRangeFilter.thisWeek) {
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = _startDate.add(const Duration(days: 6));
      } else if (filter == TimeRangeFilter.thisMonth) {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
      }
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedFilter = TimeRangeFilter.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử Giao dịch')),
      body: Column(
        children: [
          // Bộ lọc thời gian
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8.0,
              children: [
                FilterChip(
                  label: const Text('Tháng này'),
                  selected: _selectedFilter == TimeRangeFilter.thisMonth,
                  onSelected: (_) =>
                      _updateDateRange(TimeRangeFilter.thisMonth),
                ),
                FilterChip(
                  label: const Text('Tuần này'),
                  selected: _selectedFilter == TimeRangeFilter.thisWeek,
                  onSelected: (_) => _updateDateRange(TimeRangeFilter.thisWeek),
                ),
                FilterChip(
                  label: const Text('Tùy chọn'),
                  selected: _selectedFilter == TimeRangeFilter.custom,
                  onSelected: (_) => _selectCustomDateRange(),
                ),
              ],
            ),
          ),
          // Danh sách giao dịch
          Expanded(
            child: StreamBuilder<List<TransactionModel>>(
              stream: _databaseService.getTransactionsStream(
                userProvider,
                _startDate,
                _endDate,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Không có giao dịch nào.'));
                }
                final transactions = snapshot.data!;
                return ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    return TransactionListItem(
                      transaction: transactions[index],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
