// lib/presentation/widgets/enhanced_connection_status_banner.dart
import 'package:flutter/material.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class EnhancedConnectionStatusBanner extends StatelessWidget {
  final bool showWhenOnline;
  final bool showDetailedInfo;
  final VoidCallback? onTap;

  const EnhancedConnectionStatusBanner({
    super.key,
    this.showWhenOnline = false,
    this.showDetailedInfo = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncStatusProvider>(
      builder: (context, syncProvider, child) {
        if (!syncProvider.isInitialized) {
          return const SizedBox.shrink();
        }

        final status = syncProvider.getConnectivityStatus();

        // Don't show banner when online unless explicitly requested
        if (status == ConnectivityStatus.online && !showWhenOnline) {
          return const SizedBox.shrink();
        }

        final bannerData = _getBannerData(context, status, syncProvider);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: GestureDetector(
            key: ValueKey(status),
            onTap: onTap ?? () => _showSyncDetailsDialog(context, syncProvider),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bannerData.backgroundColor,
                border: Border(
                  bottom: BorderSide(color: bannerData.borderColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Status icon
                  _buildStatusIcon(bannerData),
                  const SizedBox(width: 12),

                  // Status text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bannerData.title,
                          style: TextStyle(
                            color: bannerData.textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (showDetailedInfo && bannerData.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              bannerData.subtitle!,
                              style: TextStyle(
                                color: bannerData.textColor.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Action buttons
                  if (bannerData.showSyncButton)
                    _buildSyncButton(context, syncProvider, bannerData),

                  // Info button
                  Icon(
                    Icons.info_outline,
                    color: bannerData.textColor.withOpacity(0.7),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(_BannerData bannerData) {
    if (bannerData.isAnimated) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(bannerData.iconColor),
        ),
      );
    }

    return Icon(bannerData.icon, color: bannerData.iconColor, size: 20);
  }

  Widget _buildSyncButton(
    BuildContext context,
    SyncStatusProvider syncProvider,
    _BannerData bannerData,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: syncProvider.isSyncing
              ? null
              : () {
                  _performManualSync(context, syncProvider);
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bannerData.textColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: bannerData.textColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync, color: bannerData.textColor, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Đồng bộ',
                  style: TextStyle(
                    color: bannerData.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performManualSync(
    BuildContext context,
    SyncStatusProvider syncProvider,
  ) async {
    try {
      await syncProvider.forceSyncNow();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đồng bộ thành công!'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi đồng bộ: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSyncDetailsDialog(
    BuildContext context,
    SyncStatusProvider syncProvider,
  ) {
    final stats = syncProvider.getDetailedStats();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sync, color: Colors.blue),
            SizedBox(width: 8),
            Text('Chi tiết đồng bộ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow(
                'Trạng thái kết nối:',
                syncProvider.isConnectedToNetwork ? '🟢 Online' : '🔴 Offline',
              ),
              _buildStatRow(
                'Firebase:',
                syncProvider.isFirebaseConnected
                    ? '🟢 Kết nối'
                    : '🔴 Ngắt kết nối',
              ),
              _buildStatRow(
                'Trạng thái sync:',
                _getSyncStatusText(syncProvider.syncStatus),
              ),
              _buildStatRow(
                'Đồng bộ thành công:',
                '${syncProvider.successfulSyncs}',
              ),
              _buildStatRow('Đồng bộ thất bại:', '${syncProvider.failedSyncs}'),
              _buildStatRow(
                'Dữ liệu chờ sync:',
                '${syncProvider.pendingCount}',
              ),

              if (syncProvider.lastSyncTime != null)
                _buildStatRow(
                  'Lần sync cuối:',
                  _formatDateTime(syncProvider.lastSyncTime!),
                ),

              if (syncProvider.lastError != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Lỗi gần nhất:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    syncProvider.lastError!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (syncProvider.pendingCount > 0 && syncProvider.isOnline)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _performManualSync(context, syncProvider);
              },
              child: const Text('Đồng bộ ngay'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '⚪ Chờ';
      case SyncStatus.syncing:
        return '🔄 Đang đồng bộ';
      case SyncStatus.success:
        return '✅ Thành công';
      case SyncStatus.error:
        return '❌ Lỗi';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }

  _BannerData _getBannerData(
    BuildContext context,
    ConnectivityStatus status,
    SyncStatusProvider syncProvider,
  ) {
    switch (status) {
      case ConnectivityStatus.online:
        return _BannerData(
          title: 'Trực tuyến',
          subtitle: syncProvider.getStatusMessage(),
          icon: Icons.cloud_done,
          backgroundColor: Colors.green.shade50,
          borderColor: Colors.green.shade200,
          iconColor: Colors.green.shade600,
          textColor: Colors.green.shade800,
          showSyncButton: false,
          isAnimated: false,
        );

      case ConnectivityStatus.offline:
        return _BannerData(
          title: 'Chế độ ngoại tuyến',
          subtitle: syncProvider.pendingCount > 0
              ? '${syncProvider.pendingCount} thay đổi sẽ được đồng bộ khi có kết nối'
              : 'Mọi thay đổi sẽ được lưu và đồng bộ sau',
          icon: Icons.cloud_off,
          backgroundColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
          iconColor: Colors.orange.shade600,
          textColor: Colors.orange.shade800,
          showSyncButton: false,
          isAnimated: false,
        );

      case ConnectivityStatus.syncing:
        return _BannerData(
          title: 'Đang đồng bộ dữ liệu',
          subtitle: 'Vui lòng chờ trong giây lát...',
          icon: Icons.sync,
          backgroundColor: Colors.blue.shade50,
          borderColor: Colors.blue.shade200,
          iconColor: Colors.blue.shade600,
          textColor: Colors.blue.shade800,
          showSyncButton: false,
          isAnimated: true,
        );

      case ConnectivityStatus.syncError:
        return _BannerData(
          title: 'Lỗi đồng bộ',
          subtitle: syncProvider.lastError ?? 'Không thể đồng bộ dữ liệu',
          icon: Icons.sync_problem,
          backgroundColor: Colors.red.shade50,
          borderColor: Colors.red.shade200,
          iconColor: Colors.red.shade600,
          textColor: Colors.red.shade800,
          showSyncButton: syncProvider.isConnectedToNetwork,
          isAnimated: false,
        );

      case ConnectivityStatus.unknown:
        return _BannerData(
          title: 'Đang khởi tạo',
          subtitle: 'Kiểm tra kết nối và trạng thái đồng bộ...',
          icon: Icons.help_outline,
          backgroundColor: Colors.grey.shade100,
          borderColor: Colors.grey.shade300,
          iconColor: Colors.grey.shade600,
          textColor: Colors.grey.shade800,
          showSyncButton: false,
          isAnimated: true,
        );
    }
  }
}

class _BannerData {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final bool showSyncButton;
  final bool isAnimated;

  const _BannerData({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
    required this.showSyncButton,
    required this.isAnimated,
  });
}
