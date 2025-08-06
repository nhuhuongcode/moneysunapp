import 'package:flutter/material.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/time_filter_widget.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  final DatabaseService _databaseService = DatabaseService();

  // FIX: Use TimeFilter from common widget
  TimeFilter _selectedFilter = TimeFilter.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _updateDateRange(TimeFilter.thisMonth);
  }

  void _updateDateRange(TimeFilter filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      switch (filter) {
        case TimeFilter.thisWeek:
          _startDate = now.subtract(Duration(days: now.weekday - 1));
          _endDate = _startDate.add(const Duration(days: 6));
          break;
        case TimeFilter.thisMonth:
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0);
          break;
        case TimeFilter.thisYear:
          _startDate = DateTime(now.year, 1, 1);
          _endDate = DateTime(now.year, 12, 31);
          break;
        case TimeFilter.custom:
          // Keep current dates
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử Giao dịch'), elevation: 0),
      body: Column(
        children: [
          // FIX: Use common TimeFilterWidget
          TimeFilterWidget(
            selectedFilter: _selectedFilter,
            startDate: _startDate,
            endDate: _endDate,
            onFilterChanged: (filter, start, end) {
              setState(() {
                _selectedFilter = filter;
                _startDate = start;
                _endDate = end;
              });
            },
          ),

          // FIX: Transactions list with daily grouping template
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
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 80,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Không có giao dịch nào',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Trong khoảng thời gian này',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final transactions = snapshot.data!;

                // FIX: Group by date using DailyTransactionsGroup template
                final groupedTransactions = groupBy(
                  transactions,
                  (TransactionModel t) =>
                      DateTime(t.date.year, t.date.month, t.date.day),
                );

                return RefreshIndicator(
                  onRefresh: () async {
                    // Trigger rebuild
                    setState(() {});
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: groupedTransactions.length,
                    itemBuilder: (context, index) {
                      final entry = groupedTransactions.entries.elementAt(
                        index,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: DailyTransactionsGroup(
                          date: entry.key,
                          transactions: entry.value,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
