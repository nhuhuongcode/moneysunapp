import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({super.key});

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner> {
  late StreamSubscription<DatabaseEvent> _connectionSubscription;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    // Firebase cung cấp một đường dẫn đặc biệt là `.info/connected`
    // để lắng nghe trạng thái kết nối
    final connectedRef = FirebaseDatabase.instance.ref('.info/connected');
    _connectionSubscription = connectedRef.onValue.listen((event) {
      // Giá trị trả về là true nếu kết nối và false nếu ngắt kết nối
      final isConnected = event.snapshot.value as bool? ?? false;
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnected) {
      // Nếu đang kết nối, không hiển thị gì cả
      return const SizedBox.shrink();
    }

    // Nếu mất kết nối, hiển thị một banner
    return Container(
      width: double.infinity,
      color: Colors.orange.shade700,
      padding: const EdgeInsets.all(4.0),
      child: const Text(
        'Bạn đang offline. Mọi thay đổi sẽ được đồng bộ sau.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
