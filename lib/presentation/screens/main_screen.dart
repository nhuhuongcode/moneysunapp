// lib/presentation/screens/_main_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/presentation/screens/budget_screen.dart';
import 'package:moneysun/presentation/screens/reporting_screen.dart';
import 'package:provider/provider.dart';

import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/screens/dashboard_screen.dart';
import 'package:moneysun/presentation/screens/profile_screen.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late PageController _pageController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Navigation items with  metadata
  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: Icons.dashboard_rounded,
      activeIcon: Icons.dashboard,
      label: 'Tổng quan',
      description: 'Dashboard & thống kê',
    ),
    NavigationItem(
      icon: Icons.pie_chart_outline_rounded,
      activeIcon: Icons.pie_chart_rounded,
      label: 'Báo cáo',
      description: 'Phân tích chi tiết',
    ),
    NavigationItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Ngân sách',
      description: 'Quản lý ngân sách',
    ),
    NavigationItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Cá nhân',
      description: 'Cài đặt & partnership',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<ConnectionStatusProvider, UserProvider, DataService>(
      builder: (context, connectionStatus, userProvider, dataService, child) {
        return Scaffold(
          body: Column(
            children: [
              //  status banner
              _buildStatusBanner(connectionStatus, userProvider),

              // Main content
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    children: [
                      const DashboardScreen(),
                      const ReportingScreen(),
                      const BudgetScreen(),
                      const ProfileScreen(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNavigation(userProvider),
        );
      },
    );
  }

  Widget _buildStatusBanner(
    ConnectionStatusProvider connectionStatus,
    UserProvider userProvider,
  ) {
    // Only show banner if there's something important to display
    if (!connectionStatus.shouldShowBanner && !userProvider.hasPartner) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // DataService status banner
          if (connectionStatus.shouldShowBanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: connectionStatus.statusColor.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: connectionStatus.statusColor.withOpacity(0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (connectionStatus.isSyncing)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          connectionStatus.statusColor,
                        ),
                      ),
                    )
                  else
                    Icon(
                      connectionStatus.isOnline
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      size: 16,
                      color: connectionStatus.statusColor,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DataService: ${connectionStatus.statusMessage}',
                      style: TextStyle(
                        color: connectionStatus.statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (connectionStatus.pendingItems > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: connectionStatus.statusColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${connectionStatus.pendingItems}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Partnership status banner
          // if (userProvider.hasPartner)
          //   PartnershipStatusWidget(userProvider: userProvider),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation(UserProvider userProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              elevation: 0,
              backgroundColor: Colors.transparent,
              selectedItemColor: Theme.of(context).primaryColor,
              unselectedItemColor: Colors.grey.shade400,
              selectedFontSize: 12,
              unselectedFontSize: 11,
              items: _navigationItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = _selectedIndex == index;

                return BottomNavigationBarItem(
                  icon: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(isSelected ? 8 : 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      size: isSelected ? 24 : 22,
                    ),
                  ),
                  label: item.label,
                  tooltip: item.description,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }
}

// Navigation Item Model
class NavigationItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String description;

  const NavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.description,
  });
}
