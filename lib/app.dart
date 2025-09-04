import 'package:flutter/material.dart' hide NotificationListener;
import 'package:moneysun/core/theme/app_theme.dart';
import 'package:moneysun/features/auth/presentation/screens/auth_gate.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart'; // NEW
import 'package:provider/provider.dart';
import 'package:moneysun/presentation/widgets/notification_listener.dart';

class MoneySunApp extends StatelessWidget {
  const MoneySunApp({super.key});

  @override
  Widget build(BuildContext context) {
    // UPDATED: Multiple providers với sync status provider
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(
          create: (context) => SyncStatusProvider(),
        ), // NEW
      ],
      child: MaterialApp(
        title: 'Money Sun',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const NotificationListener(child: AuthGate()),
      ),
    );
  }
}
