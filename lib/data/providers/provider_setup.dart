// ============================================================================
// lib/presentation/providers/provider_setup_updated.dart
// SỬ DỤNG TRONG app.dart updated

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';

/// UPDATED Provider Setup for app.dart
class ProviderSetup {
  static List<ChangeNotifierProvider> getProviders() {
    return [
      // 1. Primary UserProvider
      ChangeNotifierProvider(create: (context) => UserProvider()),

      // 2. DataService - Single source of truth
      ChangeNotifierProxyProvider<UserProvider, DataService>(
        create: (context) => DataService(),
        update: (context, userProvider, dataService) {
          final service = dataService ?? DataService();

          // Initialize when user changes
          if (userProvider.currentUser != null && !service.isInitialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              service.initialize(userProvider).catchError((error) {
                debugPrint('❌ Failed to initialize DataService: $error');
              });
            });
          }

          return service;
        },
      ),

      // 3. TransactionProvider - depends on DataService
      ChangeNotifierProxyProvider2<
        DataService,
        UserProvider,
        TransactionProvider
      >(
        create: (context) => TransactionProvider(
          Provider.of<DataService>(context, listen: false),
          Provider.of<UserProvider>(context, listen: false),
        ),
        update: (context, dataService, userProvider, transactionProvider) {
          return transactionProvider ??
              TransactionProvider(dataService, userProvider);
        },
      ),

      // 4. WalletProvider - depends on DataService
      ChangeNotifierProxyProvider2<DataService, UserProvider, WalletProvider>(
        create: (context) => WalletProvider(
          Provider.of<DataService>(context, listen: false),
          Provider.of<UserProvider>(context, listen: false),
        ),
        update: (context, dataService, userProvider, walletProvider) {
          return walletProvider ?? WalletProvider(dataService, userProvider);
        },
      ),

      // 5. CategoryProvider - depends on DataService
      ChangeNotifierProxyProvider2<DataService, UserProvider, CategoryProvider>(
        create: (context) => CategoryProvider(
          Provider.of<DataService>(context, listen: false),
          Provider.of<UserProvider>(context, listen: false),
        ),
        update: (context, dataService, userProvider, categoryProvider) {
          return categoryProvider ??
              CategoryProvider(dataService, userProvider);
        },
      ),

      // 6. Connection Status Provider
      ChangeNotifierProxyProvider<DataService, ConnectionStatusProvider>(
        create: (context) => ConnectionStatusProvider(),
        update: (context, dataService, connectionProvider) {
          final provider = connectionProvider ?? ConnectionStatusProvider();
          if (dataService != null) {
            provider.updateFromDataService(dataService);
          }
          return provider;
        },
      ),
    ];
  }
}
