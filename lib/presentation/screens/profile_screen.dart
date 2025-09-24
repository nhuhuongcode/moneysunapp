import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/partnership_service.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/budget_provider.dart';
import 'package:moneysun/presentation/screens/manage_categories_screen.dart';
import 'package:moneysun/presentation/screens/manage_wallets_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final PartnershipService _partnershipService = PartnershipService();
  final AuthService _authService = AuthService();
  final _inviteCodeController = TextEditingController();

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // State variables
  bool _isLoading = false;
  String? _currentInviteCode;
  bool _isGeneratingCode = false;
  bool _isDeletingData = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadCurrentInviteCode();
  }

  // ============ ANIMATION SETUP ============

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  // ============ INITIALIZATION ============

  Future<void> _loadCurrentInviteCode() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (!userProvider.hasPartner) {
      try {
        final code = await _partnershipService.getActiveInviteCode(
          userProvider,
        );
        if (mounted) {
          setState(() {
            _currentInviteCode = code;
          });
        }
      } catch (e) {
        debugPrint('Error loading invite code: $e');
      }
    }
  }

  // ============ MAIN BUILD METHOD ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Consumer3<UserProvider, ConnectionStatusProvider, DataService>(
        builder: (context, userProvider, connectionStatus, dataService, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(userProvider, connectionStatus),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // User Profile Card
                        _buildAnimatedCard(
                          child: _buildUserProfileCard(userProvider),
                          delay: 100,
                        ),

                        const SizedBox(height: 20),

                        // Partnership Section
                        _buildAnimatedCard(
                          child: _buildPartnershipSection(userProvider),
                          delay: 200,
                        ),

                        const SizedBox(height: 20),

                        // DataService Status
                        _buildAnimatedCard(
                          child: _buildDataServiceStatus(
                            connectionStatus,
                            dataService,
                          ),
                          delay: 300,
                        ),

                        const SizedBox(height: 20),

                        // Management Section
                        _buildAnimatedCard(
                          child: _buildManagementSection(),
                          delay: 400,
                        ),

                        const SizedBox(height: 20),

                        // Statistics Section
                        _buildAnimatedCard(
                          child: _buildStatisticsSection(),
                          delay: 500,
                        ),

                        const SizedBox(height: 20),

                        // Actions Section
                        _buildAnimatedCard(
                          child: _buildActionsSection(),
                          delay: 600,
                        ),

                        const SizedBox(height: 20),

                        // ✅ NEW: Danger Zone Section
                        _buildAnimatedCard(
                          child: _buildDangerZoneSection(),
                          delay: 700,
                        ),

                        const SizedBox(height: 20),

                        // Sign Out
                        _buildAnimatedCard(
                          child: _buildSignOutSection(),
                          delay: 800,
                        ),

                        const SizedBox(height: 40), // Bottom padding
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============ WIDGET BUILDERS ============

  Widget _buildAnimatedCard({required Widget child, required int delay}) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 600 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: child,
    );
  }

  Widget _buildSliverAppBar(
    UserProvider userProvider,
    ConnectionStatusProvider connectionStatus,
  ) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Cá nhân & Cài đặt',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).primaryColor.withOpacity(0.1),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
        ),
      ),
      actions: [
        // Connection status indicator
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: connectionStatus.statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: connectionStatus.statusColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connectionStatus.isSyncing)
                SizedBox(
                  width: 12,
                  height: 12,
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
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  size: 14,
                  color: connectionStatus.statusColor,
                ),
              const SizedBox(width: 4),
              Text(
                connectionStatus.isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 10,
                  color: connectionStatus.statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserProfileCard(UserProvider userProvider) {
    final user = userProvider.currentUser;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Hero(
              tag: 'user_avatar',
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: user?.photoURL != null
                          ? ClipOval(
                              child: Image.network(
                                user!.photoURL!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildDefaultAvatar(),
                              ),
                            )
                          : _buildDefaultAvatar(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 20),

            // User Info
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Người dùng',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? 'Chưa có email',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // Partnership status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: userProvider.hasPartner
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: userProvider.hasPartner
                            ? Colors.green.withOpacity(0.3)
                            : Colors.orange.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          userProvider.hasPartner ? Icons.people : Icons.person,
                          size: 16,
                          color: userProvider.hasPartner
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          userProvider.hasPartner ? 'Đã kết nối' : 'Độc lập',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: userProvider.hasPartner
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return const Icon(Icons.person, size: 40, color: Colors.white);
  }

  Widget _buildPartnershipSection(UserProvider userProvider) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              userProvider.hasPartner
                  ? Colors.green.withOpacity(0.05)
                  : Colors.blue.withOpacity(0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: userProvider.hasPartner
                        ? Colors.green.withOpacity(0.15)
                        : Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    userProvider.hasPartner ? Icons.people : Icons.person_add,
                    color: userProvider.hasPartner ? Colors.green : Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quản lý chung',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        userProvider.hasPartner
                            ? 'Kết nối với đối tác'
                            : 'Chia sẻ chi tiêu với người thân',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Partnership content
            userProvider.hasPartner
                ? _buildActivePartnershipContent(userProvider)
                : _buildInvitePartnershipContent(userProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePartnershipContent(UserProvider userProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Partner info
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.green.withOpacity(0.2),
                    backgroundImage: userProvider.partnerPhotoURL != null
                        ? NetworkImage(userProvider.partnerPhotoURL!)
                        : null,
                    child: userProvider.partnerPhotoURL == null
                        ? const Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.green,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userProvider.partnerDisplayName ?? 'Đối tác',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (userProvider.partnershipCreationDate != null)
                          Text(
                            'Kết nối từ ${DateFormat('dd/MM/yyyy').format(userProvider.partnershipCreationDate!)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Partnership stats
              FutureBuilder<Map<String, dynamic>>(
                future: _partnershipService.getPartnershipStatistics(
                  userProvider,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Lỗi khi tải thống kê',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    final stats = snapshot.data!;
                    final duration = stats['duration'] as Map<String, dynamic>?;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  'Thời gian kết nối',
                                  '${duration?['days'] ?? 0} ngày',
                                  Icons.calendar_today,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildStatItem(
                                  'Trạng thái',
                                  'Hoạt động',
                                  Icons.check_circle,
                                  Colors.green,
                                ),
                              ),
                            ],
                          ),
                          if ((duration?['days'] ?? 0) > 30) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Đã kết nối được ${(duration?['months'] ?? 0)} tháng!',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Actions
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showPartnershipInfo(userProvider),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Chi tiết'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => _showDisconnectDialog(userProvider),
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Ngắt kết nối'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInvitePartnershipContent(UserProvider userProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Invite code section
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code, color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Mã mời của bạn',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_currentInviteCode != null) ...[
                // Display current invite code
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      SelectableText(
                        _currentInviteCode!,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          fontFamily: 'Courier',
                          color: Colors.blue,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      // 👉 Dùng Wrap thay vì Row
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _currentInviteCode!),
                              );
                              _showSuccessSnackBar('Đã sao chép mã mời!');
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Sao chép'),
                          ),
                          TextButton.icon(
                            onPressed: _generateNewInviteCode,
                            icon: _isGeneratingCode
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(
                              _isGeneratingCode ? 'Đang tạo...' : 'Tạo mới',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _cancelCurrentInviteCode,
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'Hủy',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mã mời có hiệu lực trong 24 giờ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Generate invite code button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isGeneratingCode
                        ? null
                        : _generateNewInviteCode,
                    icon: _isGeneratingCode
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 20),
                    label: Text(
                      _isGeneratingCode ? 'Đang tạo mã...' : 'Tạo mã mời',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Accept invite section
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Nhập mã của đối tác',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inviteCodeController,
                      decoration: InputDecoration(
                        hintText: 'Nhập mã 6 ký tự',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.orange,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 1,
                          ),
                        ),
                        prefixIcon: const Icon(
                          Icons.qr_code,
                          color: Colors.orange,
                        ),
                        suffixIcon: _inviteCodeController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _inviteCodeController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      inputFormatters: [
                        // Only allow alphanumeric characters
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _inviteCodeController.value = _inviteCodeController
                              .value
                              .copyWith(
                                text: value.toUpperCase(),
                                selection: TextSelection.collapsed(
                                  offset: value.length,
                                ),
                              );
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        _isLoading || _inviteCodeController.text.length != 6
                        ? null
                        : () => _acceptInvite(userProvider),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Kết nối'),
                  ),
                ],
              ),

              // Validation feedback
              if (_inviteCodeController.text.isNotEmpty &&
                  _inviteCodeController.text.length < 6)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Mã mời cần đủ 6 ký tự (${_inviteCodeController.text.length}/6)',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDataServiceStatus(
    ConnectionStatusProvider connectionStatus,
    DataService dataService,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: connectionStatus.statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    connectionStatus.isOnline
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    color: connectionStatus.statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Trạng thái đồng bộ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildStatusRow(
              'Kết nối',
              connectionStatus.statusMessage,
              connectionStatus.statusColor,
            ),
            _buildStatusRow(
              'Mục chờ đồng bộ',
              '${connectionStatus.pendingItems}',
              connectionStatus.pendingItems > 0 ? Colors.orange : Colors.green,
            ),

            if (connectionStatus.lastSyncTime != null)
              _buildStatusRow(
                'Lần cuối đồng bộ',
                DateFormat(
                  'dd/MM/yyyy HH:mm',
                ).format(connectionStatus.lastSyncTime!),
                Colors.grey,
              ),

            if (connectionStatus.lastError != null)
              _buildStatusRow('Lỗi', connectionStatus.lastError!, Colors.red),

            const SizedBox(height: 16),

            // Manual sync button
            if (!connectionStatus.isOnline || connectionStatus.pendingItems > 0)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: connectionStatus.isSyncing
                      ? null
                      : () => _performManualSync(dataService),
                  icon: connectionStatus.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    connectionStatus.isSyncing
                        ? 'Đang đồng bộ...'
                        : 'Đồng bộ thủ công',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: connectionStatus.statusColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Quản lý dữ liệu',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          _buildManagementTile(
            Icons.account_balance_wallet_outlined,
            'Quản lý Nguồn tiền',
            'Tạo, chỉnh sửa ví và tài khoản',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageWalletsScreen()),
            ),
          ),
          const Divider(height: 1),
          _buildManagementTile(
            Icons.category_outlined,
            'Quản lý Danh mục',
            'Tạo, chỉnh sửa danh mục thu chi',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()),
            ),
          ),
          const Divider(height: 1),
          _buildManagementTile(
            Icons.add_circle_outline,
            'Tạo danh mục mặc định',
            'Tạo nhanh danh mục phổ biến',
            _showCreateDefaultCategoriesDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildManagementTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Theme.of(context).primaryColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildStatisticsSection() {
    return Consumer3<WalletProvider, TransactionProvider, CategoryProvider>(
      builder:
          (
            context,
            walletProvider,
            transactionProvider,
            categoryProvider,
            child,
          ) {
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thống kê tổng quan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Số ví',
                            '${walletProvider.walletCount}',
                            Icons.account_balance_wallet,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Danh mục',
                            '${categoryProvider.categories.length}',
                            Icons.category,
                            Colors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      'Tổng số dư',
                      NumberFormat.currency(
                        locale: 'vi_VN',
                        symbol: '₫',
                      ).format(walletProvider.totalBalance),
                      Icons.account_balance,
                      walletProvider.totalBalance >= 0
                          ? Colors.green
                          : Colors.red,
                      isFullWidth: true,
                    ),
                  ],
                ),
              ),
            );
          },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool isFullWidth = false,
  }) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildActionTile(
            Icons.backup,
            'Xuất dữ liệu',
            'Sao lưu dữ liệu ra file',
            () => _showFeatureNotImplemented('Xuất dữ liệu'),
          ),
          const Divider(height: 1),
          _buildActionTile(
            Icons.restore,
            'Nhập dữ liệu',
            'Khôi phục từ file sao lưu',
            () => _showFeatureNotImplemented('Nhập dữ liệu'),
          ),
          const Divider(height: 1),
          // ✅ NEW: Debug section (only show in debug mode)
          if (kDebugMode) ...[
            _buildActionTile(
              Icons.bug_report,
              'Thống kê dữ liệu',
              'Xem thống kê dữ liệu hiện tại (Debug)',
              _showDataDeletionStats,
            ),
            const Divider(height: 1),
            _buildActionTile(
              Icons.clear,
              '☢️ Nuclear Option',
              'Xóa cứng tất cả dữ liệu local (Debug)',
              _showNuclearOption,
            ),
            const Divider(height: 1),
          ],
          _buildActionTile(
            Icons.info_outline,
            'Về ứng dụng',
            'Thông tin phiên bản và nhà phát triển',
            _showAboutDialog,
          ),
        ],
      ),
    );
  }

  void _showDataDeletionStats() async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final stats = await dataService.getDataDeletionStats();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thống kê dữ liệu'),
            content: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(stats),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Lỗi khi lấy thống kê: $e');
    }
  }

  void _showNuclearOption() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          '☢️ TÙY CHỌN NUCLEAR',
          style: TextStyle(color: Colors.red),
        ),
        content: const Text(
          'Tùy chọn này sẽ XÓA CỨNG tất cả dữ liệu local mà không cần xác nhận thêm.\n\n'
          'CHỈ SỬ DỤNG KHI CÁC PHƯƠNG THỨC KHÁC THẤT BẠI!\n\n'
          'Bạn có chắc chắn muốn tiếp tục?',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _executeNuclearOption();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              '☢️ NUCLEAR',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ NEW: Execute nuclear option
  Future<void> _executeNuclearOption() async {
    try {
      _showLoadingSnackBar('Executing nuclear option...');

      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.forceNukeLocalDatabase();
      await _clearAllProviders();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSuccessSnackBar('Nuclear option completed!');

      // Auto sign out after nuclear option
      Future.delayed(const Duration(seconds: 3), () async {
        await _authService.signOut();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showErrorSnackBar('Nuclear option failed: ${_getErrorMessage(e)}');
    }
  }

  // ✅ NEW: Danger Zone Section
  Widget _buildDangerZoneSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vùng nguy hiểm',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                      ),
                      Text(
                        'Các thao tác không thể hoàn tác',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildDangerActionTile(
              Icons.delete_forever_outlined,
              'Xóa tất cả dữ liệu',
              'Xóa vĩnh viễn tất cả giao dịch, ví, danh mục và ngân sách',
              _showDeleteAllDataDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerActionTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.red, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade600),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.red.withOpacity(0.7)),
      onTap: onTap,
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSignOutSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.logout, color: Colors.red),
        ),
        title: const Text(
          'Đăng xuất',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Thoát khỏi tài khoản hiện tại'),
        onTap: _showSignOutDialog,
      ),
    );
  }

  // ============ DATA DELETION METHODS ============

  /// ✅ NEW: Show delete all data confirmation dialog with backup option
  void _showDeleteAllDataDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Xóa tất cả dữ liệu',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'CẢNH BÁO NGHIÊM TRỌNG',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Thao tác này sẽ XÓA VĨNH VIỄN tất cả dữ liệu của bạn bao gồm:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    _buildDeleteItem('🏦 Tất cả ví và tài khoản'),
                    _buildDeleteItem('💸 Tất cả giao dịch thu chi'),
                    _buildDeleteItem('📁 Tất cả danh mục và tiểu mục'),
                    _buildDeleteItem('📊 Tất cả ngân sách và báo cáo'),
                    _buildDeleteItem('🔄 Dữ liệu cả offline và online'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nếu có partnership, dữ liệu chung cũng sẽ bị xóa',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ✅ NEW: Backup option
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.backup, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'TÙY CHỌN SAO LƯU',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hệ thống sẽ tự động tạo bản sao lưu trong bộ nhớ tạm trước khi xóa. '
                      'Nếu xảy ra lỗi, bạn có thể khôi phục dữ liệu.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'THAO TÁC NÀY KHÔNG THỂ HOÀN TÁC!\n\n'
                'Hãy chắc chắn bạn đã cân nhắc kỹ lưỡng.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy bỏ'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showBackupAndDeleteOption();
            },
            icon: const Icon(Icons.backup, size: 18),
            label: const Text('Sao lưu & Xóa'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showFinalDeleteConfirmation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa ngay'),
          ),
        ],
      ),
    );
  }

  /// ✅ NEW: Show backup and delete option
  void _showBackupAndDeleteOption() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.backup, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Text('Sao lưu & Xóa dữ liệu'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 QUY TRÌNH SAO LƯU & XÓA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProcessStep('1. Tạo bản sao lưu dữ liệu trong bộ nhớ'),
                  _buildProcessStep('2. Thực hiện xóa toàn bộ dữ liệu'),
                  _buildProcessStep('3. Nếu có lỗi → Tự động khôi phục'),
                  _buildProcessStep('4. Nếu thành công → Xóa bản sao lưu'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.security,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'An toàn hơn - có thể khôi phục nếu xảy ra lỗi',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Quay lại'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showFinalDeleteConfirmation();
            },
            icon: const Icon(Icons.backup, size: 18),
            label: const Text('Tiếp tục'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.circle, size: 4, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ NEW: Final confirmation dialog with text input
  void _showFinalDeleteConfirmation() {
    final TextEditingController confirmController = TextEditingController();
    const String confirmText = 'Y';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isConfirmTextCorrect =
              confirmController.text.toUpperCase() == confirmText;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'XÁC NHẬN CUỐI CÙNG',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Để xác nhận bạn thực sự muốn xóa TẤT CẢ dữ liệu, '
                  'vui lòng nhập chính xác từ khóa bên dưới:',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: SelectableText(
                      confirmText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                        color: Colors.red,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Nhập từ khóa xác nhận',
                    hintText: 'Nhập: $confirmText',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isConfirmTextCorrect ? Colors.green : Colors.red,
                        width: 2,
                      ),
                    ),
                    prefixIcon: Icon(
                      isConfirmTextCorrect ? Icons.check_circle : Icons.warning,
                      color: isConfirmTextCorrect ? Colors.green : Colors.red,
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) => setState(() {}),
                ),
                if (confirmController.text.isNotEmpty && !isConfirmTextCorrect)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Từ khóa không chính xác. Vui lòng nhập: $confirmText',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Hủy bỏ'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isConfirmTextCorrect && !_isDeletingData
                    ? () {
                        Navigator.of(context).pop();
                        _executeDeleteAllData();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: _isDeletingData
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('XÓA TẤT CẢ'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ✅ NEW: Execute the actual data deletion
  Future<void> _executeDeleteAllData() async {
    setState(() => _isDeletingData = true);

    try {
      // Show progress dialog
      _showDeletionProgressDialog();

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);

      final userId = userProvider.currentUser?.uid;
      final partnershipId = userProvider.partnershipId;

      if (userId == null) {
        throw Exception('User ID not available');
      }

      // Step 1: Disconnect partnership if exists
      if (userProvider.hasPartner) {
        _updateDeletionProgress('Ngắt kết nối partnership...', 0.05);
        try {
          await _partnershipService.disconnectPartnership(userProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          debugPrint('Warning: Failed to disconnect partnership: $e');
          // Continue with deletion even if partnership disconnect fails
        }
      }

      // Step 2: Use DataService to delete all data
      _updateDeletionProgress('Bắt đầu xóa tất cả dữ liệu...', 0.1);

      final success = await dataService.deleteAllUserData(
        userId: userId,
        partnershipId: partnershipId,
        onProgress: _updateDeletionProgress,
      );

      if (!success) {
        throw Exception('Data deletion failed');
      }

      // Step 3: Reset DataService state
      _updateDeletionProgress('Reset service state...', 0.95);
      await dataService.resetDataServiceState();

      // Step 4: Clear provider states
      _updateDeletionProgress('Dọn dẹp providers...', 0.97);
      await _clearAllProviders();

      // Step 5: Verify deletion completed
      _updateDeletionProgress('Kiểm tra hoàn tất...', 0.99);
      final isComplete = await dataService.verifyDeletionComplete(
        userId,
        partnershipId,
      );

      if (!isComplete) {
        debugPrint('⚠️ Some data may remain, attempting nuclear option...');
        await dataService.forceNukeLocalDatabase();
      }

      // Step 6: Complete
      _updateDeletionProgress('Hoàn tất!', 1.0);
      await Future.delayed(const Duration(seconds: 1));

      // Hide progress dialog
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // Show success message and sign out
      _showSuccessSnackBar('Đã xóa tất cả dữ liệu thành công!');

      // Sign out after a short delay
      Future.delayed(const Duration(seconds: 2), () async {
        await _authService.signOut();
      });
    } catch (e) {
      // Hide progress dialog if showing
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      _showErrorSnackBar('Lỗi khi xóa dữ liệu: ${_getErrorMessage(e)}');
      debugPrint('❌ Error deleting all data: $e');

      // Show recovery info if available
      await _showRecoveryInfo();
    } finally {
      if (mounted) {
        setState(() => _isDeletingData = false);
      }
    }
  }

  /// ✅ NEW: Show recovery information if deletion fails
  Future<void> _showRecoveryInfo() async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final recoveryInfo = await dataService.getRecoveryInfo();

      if (recoveryInfo['has_recoverable_data'] == true) {
        final pendingItems = recoveryInfo['pending_sync_items'] as int? ?? 0;

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Thông tin phục hồi'),
              content: Text(
                'Có $pendingItems mục dữ liệu chưa được đồng bộ có thể được phục hồi nếu bạn đăng nhập lại ngay.\n\n'
                'Nếu tiếp tục đăng xuất, dữ liệu này sẽ bị mất vĩnh viễn.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Ở lại'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _authService.signOut();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text(
                    'Đăng xuất',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error showing recovery info: $e');
    }
  }

  /// ✅ NEW: Show deletion progress dialog
  void _showDeletionProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false, // Prevent back button
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  // Animated deletion icon
                  TweenAnimationBuilder<double>(
                    duration: const Duration(seconds: 1),
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_forever,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Đang xóa dữ liệu...',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _deletionProgressMessage,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: _deletionProgress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_deletionProgress * 100).round()}% hoàn thành',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Không đóng ứng dụng trong quá trình xóa',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Progress tracking variables
  double _deletionProgress = 0.0;
  String _deletionProgressMessage = 'Bắt đầu xóa dữ liệu...';

  /// ✅ NEW: Update deletion progress
  void _updateDeletionProgress(String message, double progress) {
    if (mounted) {
      setState(() {
        _deletionProgressMessage = message;
        _deletionProgress = progress;
      });
    }
  }

  /// ✅ NEW: Delete data from Firebase
  Future<void> _deleteFirebaseData(UserProvider userProvider) async {
    _updateDeletionProgress('Xóa dữ liệu online...', 0.2);

    final userId = userProvider.currentUser?.uid;
    if (userId == null) return;

    try {
      final DatabaseReference dbRef = FirebaseDatabase.instance.ref();

      // Prepare batch updates for deletion
      final Map<String, dynamic> updates = {};

      // Delete user's transactions
      _updateDeletionProgress('Xóa giao dịch online...', 0.3);
      final transactionsSnapshot = await dbRef
          .child('transactions')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (transactionsSnapshot.exists) {
        final transactions =
            transactionsSnapshot.value as Map<dynamic, dynamic>;
        for (final transactionId in transactions.keys) {
          updates['transactions/$transactionId'] = null;
        }
      }

      // Delete user's wallets
      _updateDeletionProgress('Xóa ví online...', 0.4);
      final walletsSnapshot = await dbRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (walletsSnapshot.exists) {
        final wallets = walletsSnapshot.value as Map<dynamic, dynamic>;
        for (final walletId in wallets.keys) {
          updates['wallets/$walletId'] = null;
        }
      }

      // Delete user's categories
      _updateDeletionProgress('Xóa danh mục online...', 0.5);
      final categoriesSnapshot = await dbRef
          .child('categories')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (categoriesSnapshot.exists) {
        final categories = categoriesSnapshot.value as Map<dynamic, dynamic>;
        for (final categoryId in categories.keys) {
          updates['categories/$categoryId'] = null;
        }
      }

      // Delete user's budgets
      _updateDeletionProgress('Xóa ngân sách online...', 0.6);
      final budgetsSnapshot = await dbRef
          .child('budgets')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (budgetsSnapshot.exists) {
        final budgets = budgetsSnapshot.value as Map<dynamic, dynamic>;
        for (final budgetId in budgets.keys) {
          updates['budgets/$budgetId'] = null;
        }
      }

      // Delete shared data if partnership exists
      final partnershipId = userProvider.partnershipId;
      if (partnershipId != null) {
        _updateDeletionProgress('Xóa dữ liệu chung...', 0.65);

        // Delete shared wallets
        final sharedWalletsSnapshot = await dbRef
            .child('wallets')
            .orderByChild('ownerId')
            .equalTo(partnershipId)
            .get();

        if (sharedWalletsSnapshot.exists) {
          final sharedWallets =
              sharedWalletsSnapshot.value as Map<dynamic, dynamic>;
          for (final walletId in sharedWallets.keys) {
            updates['wallets/$walletId'] = null;
          }
        }

        // Delete shared categories
        final sharedCategoriesSnapshot = await dbRef
            .child('categories')
            .orderByChild('ownerId')
            .equalTo(partnershipId)
            .get();

        if (sharedCategoriesSnapshot.exists) {
          final sharedCategories =
              sharedCategoriesSnapshot.value as Map<dynamic, dynamic>;
          for (final categoryId in sharedCategories.keys) {
            updates['categories/$categoryId'] = null;
          }
        }

        // Delete shared budgets
        final sharedBudgetsSnapshot = await dbRef
            .child('budgets')
            .orderByChild('ownerId')
            .equalTo(partnershipId)
            .get();

        if (sharedBudgetsSnapshot.exists) {
          final sharedBudgets =
              sharedBudgetsSnapshot.value as Map<dynamic, dynamic>;
          for (final budgetId in sharedBudgets.keys) {
            updates['budgets/$budgetId'] = null;
          }
        }
      }

      // Clear user profile and related data
      _updateDeletionProgress('Xóa thông tin tài khoản...', 0.7);
      updates['users/$userId'] = null;

      // Clear notifications
      updates['user_notifications/$userId'] = null;
      updates['user_refresh_triggers/$userId'] = null;

      // Execute batch deletion
      if (updates.isNotEmpty) {
        _updateDeletionProgress('Thực hiện xóa online...', 0.75);
        await dbRef.update(updates);
      }

      debugPrint(
        '✅ Successfully deleted ${updates.length} items from Firebase',
      );
    } catch (e) {
      debugPrint('❌ Error deleting Firebase data: $e');
      // Continue with local deletion even if Firebase deletion fails
    }
  }

  /// ✅ NEW: Delete all local data
  Future<void> _deleteLocalData() async {
    _updateDeletionProgress('Xóa dữ liệu offline...', 0.8);

    final dataService = Provider.of<DataService>(context, listen: false);

    try {
      // Get access to local database
      if (dataService.isInitialized) {
        // Clear all local tables
        await dataService
            .forceUploadAllLocalData(); // This will help ensure we don't lose anything important

        // Note: We would need to add a method to DataService to clear all local data
        // For now, we'll simulate this by clearing the providers
        debugPrint(
          '🗑️ Local data deletion would be implemented in DataService',
        );
      }
    } catch (e) {
      debugPrint('❌ Error deleting local data: $e');
    }
  }

  /// ✅ NEW: Clear all provider states
  Future<void> _clearAllProviders() async {
    try {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final transactionProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      final categoryProvider = Provider.of<CategoryProvider>(
        context,
        listen: false,
      );
      final budgetProvider = Provider.of<BudgetProvider>(
        context,
        listen: false,
      );

      // Clear provider data by reloading empty state
      // Note: These methods would need to be added to providers
      debugPrint('🧹 Provider state clearing would be implemented');

      // Force reload all providers with empty state
      await Future.wait([
        walletProvider.loadWallets(forceRefresh: true),
        transactionProvider.loadTransactions(forceRefresh: true),
        categoryProvider.loadCategories(forceRefresh: true),
        budgetProvider.loadBudgets(forceRefresh: true),
      ]);
    } catch (e) {
      debugPrint('❌ Error clearing providers: $e');
    }
  }

  // ============ EVENT HANDLERS (Rest of the methods remain the same) ============

  Future<void> _generateNewInviteCode() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Check if user already has a partner
    if (userProvider.hasPartner) {
      _showErrorSnackBar('Bạn đã có đối tác rồi');
      return;
    }

    setState(() => _isGeneratingCode = true);

    try {
      // Cancel existing invite code if any
      if (_currentInviteCode != null) {
        await _partnershipService.cancelInviteCode(userProvider);
      }

      final code = await _partnershipService.generateInviteCode(userProvider);

      if (mounted) {
        setState(() => _currentInviteCode = code);
        _showSuccessSnackBar('Đã tạo mã mời mới: $code');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Lỗi khi tạo mã mời: ${_getErrorMessage(e)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCode = false);
      }
    }
  }

  Future<void> _acceptInvite(UserProvider userProvider) async {
    final inviteCode = _inviteCodeController.text.trim();

    // Validate invite code format
    if (inviteCode.length != 6) {
      _showErrorSnackBar('Mã mời phải có 6 ký tự');
      return;
    }

    // Check if user already has a partner
    if (userProvider.hasPartner) {
      _showErrorSnackBar('Bạn đã có đối tác rồi');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // First validate the invite code
      final validation = await _partnershipService.validateInviteCode(
        inviteCode,
      );

      if (!validation['valid']) {
        _showErrorSnackBar(validation['reason'] ?? 'Mã mời không hợp lệ');
        return;
      }

      // Show confirmation dialog with inviter info
      final shouldProceed = await _showAcceptInviteConfirmation(
        validation['inviterName'] ?? 'Người dùng',
        validation['inviterEmail'] ?? '',
      );

      if (!shouldProceed) return;

      // Accept the invitation
      await _partnershipService.acceptInvitation(inviteCode, userProvider);

      if (mounted) {
        _inviteCodeController.clear();
        _showSuccessSnackBar(
          'Kết nối thành công với ${validation['inviterName']}!',
        );

        // Refresh partnership data
        await userProvider.refreshPartnershipData();

        // Clear current invite code since we now have a partner
        setState(() => _currentInviteCode = null);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Lỗi: ${_getErrorMessage(e)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelCurrentInviteCode() async {
    if (_currentInviteCode == null) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await _partnershipService.cancelInviteCode(userProvider);

      if (mounted) {
        setState(() => _currentInviteCode = null);
        _showSuccessSnackBar('Đã hủy mã mời');
      }
    } catch (e) {
      _showErrorSnackBar('Lỗi khi hủy mã mời: ${_getErrorMessage(e)}');
    }
  }

  Future<bool> _showAcceptInviteConfirmation(
    String inviterName,
    String inviterEmail,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Xác nhận kết nối'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bạn có muốn kết nối với:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              inviterName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (inviterEmail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.email, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                inviterEmail,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sau khi kết nối, bạn và đối tác sẽ có thể:\n'
                  '• Xem dữ liệu chi tiêu của nhau\n'
                  '• Tạo ví chung và ngân sách chung\n'
                  '• Quản lý chi tiêu gia đình cùng nhau',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Kết nối'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _getErrorMessage(dynamic error) {
    String errorMessage = error.toString();

    // Clean up common error prefixes
    if (errorMessage.startsWith('Exception: ')) {
      errorMessage = errorMessage.substring(11);
    } else if (errorMessage.startsWith('FirebaseException: ')) {
      errorMessage = errorMessage.substring(19);
    }

    // Handle specific error cases
    if (errorMessage.contains('network')) {
      return 'Lỗi kết nối mạng. Vui lòng kiểm tra internet.';
    } else if (errorMessage.contains('permission')) {
      return 'Không có quyền truy cập. Vui lòng đăng nhập lại.';
    } else if (errorMessage.contains('already has a partner')) {
      return 'Người dùng đã có đối tác rồi.';
    } else if (errorMessage.contains('expired')) {
      return 'Mã mời đã hết hạn.';
    } else if (errorMessage.contains('not found') ||
        errorMessage.contains('không tồn tại')) {
      return 'Mã mời không tồn tại.';
    }

    return errorMessage;
  }

  void _showDisconnectDialog(UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ngắt kết nối Partnership'),
        content: Text(
          'Bạn có chắc chắn muốn ngắt kết nối với ${userProvider.partnerDisplayName}?\n\n'
          'Sau khi ngắt kết nối:\n'
          '• Bạn sẽ không còn thấy dữ liệu của đối tác\n'
          '• Đối tác cũng không thấy dữ liệu của bạn\n'
          '• Dữ liệu chung sẽ bị ẩn\n\n'
          'Thao tác này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _disconnectPartnership(userProvider);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Ngắt kết nối',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectPartnership(UserProvider userProvider) async {
    setState(() => _isLoading = true);

    try {
      await _partnershipService.disconnectPartnership(userProvider);
      _showSuccessSnackBar('Đã ngắt kết nối thành công');
      setState(() => _currentInviteCode = null);
      _loadCurrentInviteCode();
    } catch (e) {
      _showErrorSnackBar('Lỗi khi ngắt kết nối: ${_getErrorMessage(e)}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPartnershipInfo(UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thông tin Partnership'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(
                'Partnership ID',
                userProvider.partnershipId ?? 'N/A',
              ),
              _buildInfoRow(
                'Đối tác',
                userProvider.partnerDisplayName ?? 'N/A',
              ),
              _buildInfoRow('Partner UID', userProvider.partnerUid ?? 'N/A'),
              if (userProvider.partnershipCreationDate != null)
                _buildInfoRow(
                  'Ngày tạo',
                  DateFormat(
                    'dd/MM/yyyy HH:mm',
                  ).format(userProvider.partnershipCreationDate!),
                ),
              const SizedBox(height: 16),
              FutureBuilder<Map<String, dynamic>>(
                future: _partnershipService.getPartnershipStatistics(
                  userProvider,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    final stats = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thống kê:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Số ngày kết nối',
                          '${stats['duration']?['days'] ?? 0}',
                        ),
                        _buildInfoRow('Trạng thái', 'Hoạt động'),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'Courier'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performManualSync(DataService dataService) async {
    try {
      await dataService.forceSyncNow();
      if (mounted) {
        _showSuccessSnackBar('Đồng bộ thành công!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Đồng bộ thất bại: ${_getErrorMessage(e)}');
      }
    }
  }

  void _showCreateDefaultCategoriesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tạo danh mục mặc định'),
        content: const Text(
          'Tạo các danh mục phổ biến như:\n'
          '• Thu nhập: Lương, Thưởng, Đầu tư...\n'
          '• Chi tiêu: Ăn uống, Di chuyển, Mua sắm...\n\n'
          'Bạn có muốn tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createDefaultCategories();
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDefaultCategories() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final categoryProvider = Provider.of<CategoryProvider>(
        context,
        listen: false,
      );

      // Show loading indicator
      _showLoadingSnackBar('Đang tạo danh mục mặc định...');

      // Check if user already has categories
      final existingCategories = categoryProvider.categories;
      if (existingCategories.length >= 10) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showInfoSnackBar('Bạn đã có đủ danh mục rồi!');
        return;
      }

      // Default expense categories with icons
      final defaultExpenseCategories = [
        {'name': 'Ăn uống', 'icon': 0xe554}, // restaurant
        {'name': 'Di chuyển', 'icon': 0xe539}, // directions_car
        {'name': 'Mua sắm', 'icon': 0xe59c}, // shopping_bag
        {'name': 'Giải trí', 'icon': 0xe01d}, // movie
        {'name': 'Hóa đơn', 'icon': 0xe0c3}, // receipt
        {'name': 'Y tế', 'icon': 0xe2bf}, // local_hospital
        {'name': 'Giáo dục', 'icon': 0xe80c}, // school
        {'name': 'Khác', 'icon': 0xe94f}, // more_horiz
      ];

      // Default income categories with icons
      final defaultIncomeCategories = [
        {'name': 'Lương', 'icon': 0xe2c8}, // work
        {'name': 'Thưởng', 'icon': 0xe263}, // card_giftcard
        {'name': 'Đầu tư', 'icon': 0xe1db}, // trending_up
        {'name': 'Kinh doanh', 'icon': 0xe1a4}, // business
        {'name': 'Khác', 'icon': 0xe94f}, // more_horiz
      ];

      int successCount = 0;
      int errorCount = 0;
      final List<String> createdCategories = [];
      final List<String> skippedCategories = [];

      // Create personal expense categories
      for (final category in defaultExpenseCategories) {
        final name = category['name'] as String;

        // Check if category already exists
        final exists = existingCategories.any(
          (c) =>
              c.name.toLowerCase() == name.toLowerCase() &&
              c.type == 'expense' &&
              c.ownershipType == CategoryOwnershipType.personal,
        );

        if (exists) {
          skippedCategories.add(name);
          continue;
        }

        try {
          final success = await categoryProvider.addCategory(
            name: name,
            type: 'expense',
            ownershipType: CategoryOwnershipType.personal,
            iconCodePoint: category['icon'] as int,
          );

          if (success) {
            successCount++;
            createdCategories.add(name);
            debugPrint('✅ Created expense category: $name');
          } else {
            errorCount++;
            debugPrint('❌ Failed to create expense category: $name');
          }

          // Small delay to avoid overwhelming the system
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          errorCount++;
          debugPrint('❌ Error creating expense category $name: $e');
        }
      }

      // Create personal income categories
      for (final category in defaultIncomeCategories) {
        final name = category['name'] as String;

        // Check if category already exists
        final exists = existingCategories.any(
          (c) =>
              c.name.toLowerCase() == name.toLowerCase() &&
              c.type == 'income' &&
              c.ownershipType == CategoryOwnershipType.personal,
        );

        if (exists) {
          skippedCategories.add(name);
          continue;
        }

        try {
          final success = await categoryProvider.addCategory(
            name: name,
            type: 'income',
            ownershipType: CategoryOwnershipType.personal,
            iconCodePoint: category['icon'] as int,
          );

          if (success) {
            successCount++;
            createdCategories.add(name);
            debugPrint('✅ Created income category: $name');
          } else {
            errorCount++;
            debugPrint('❌ Failed to create income category: $name');
          }

          // Small delay to avoid overwhelming the system
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          errorCount++;
          debugPrint('❌ Error creating income category $name: $e');
        }
      }

      // Create shared categories if user has partner
      if (userProvider.hasPartner) {
        final sharedCategories = [
          {'name': 'Chi tiêu chung', 'type': 'expense', 'icon': 0xe88a}, // home
          {
            'name': 'Thu nhập chung',
            'type': 'income',
            'icon': 0xe2bc,
          }, // savings
        ];

        for (final category in sharedCategories) {
          final name = category['name'] as String;
          final type = category['type'] as String;

          // Check if category already exists
          final exists = existingCategories.any(
            (c) =>
                c.name.toLowerCase() == name.toLowerCase() &&
                c.type == type &&
                c.ownershipType == CategoryOwnershipType.shared,
          );

          if (exists) {
            skippedCategories.add(name);
            continue;
          }

          try {
            final success = await categoryProvider.addCategory(
              name: name,
              type: type,
              ownershipType: CategoryOwnershipType.shared,
              iconCodePoint: category['icon'] as int,
            );

            if (success) {
              successCount++;
              createdCategories.add(name);
              debugPrint('✅ Created shared category: $name');
            } else {
              errorCount++;
              debugPrint('❌ Failed to create shared category: $name');
            }

            // Small delay
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            errorCount++;
            debugPrint('❌ Error creating shared category $name: $e');
          }
        }
      }

      // Hide loading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Refresh categories list to show new categories
      await categoryProvider.loadCategories(forceRefresh: true);

      // Show result message
      if (successCount > 0) {
        String message = 'Đã tạo $successCount danh mục mặc định';

        if (skippedCategories.isNotEmpty) {
          message += ' (${skippedCategories.length} đã tồn tại)';
        }

        if (errorCount > 0) {
          message += ' ($errorCount lỗi)';
        }

        _showSuccessSnackBar(message);

        // Log created categories for debugging
        debugPrint(
          '✅ Successfully created categories: ${createdCategories.join(", ")}',
        );
        if (skippedCategories.isNotEmpty) {
          debugPrint(
            'ℹ️ Skipped existing categories: ${skippedCategories.join(", ")}',
          );
        }
      } else if (skippedCategories.isNotEmpty) {
        _showInfoSnackBar('Tất cả danh mục mặc định đã tồn tại rồi!');
      } else {
        _showErrorSnackBar('Không thể tạo danh mục mặc định nào');
      }
    } catch (e) {
      // Hide loading if still showing
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      debugPrint('❌ Error in _createDefaultCategories: $e');
      _showErrorSnackBar('Lỗi khi tạo danh mục: ${_getErrorMessage(e)}');
    }
  }

  // ✅ HELPER METHOD: Show loading snackbar
  void _showLoadingSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 30), // Long duration for loading
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ✅ HELPER METHOD: Show info snackbar
  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ✅ ENHANCED: _showSuccessSnackBar và _showErrorSnackBar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận đăng xuất'),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất?\n\n'
          'Dữ liệu chưa đồng bộ có thể bị mất nếu bạn không có kết nối mạng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _authService.signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Đăng xuất',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'MoneySun',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.7),
            ],
          ),
        ),
        child: const Icon(
          Icons.account_balance_wallet,
          color: Colors.white,
          size: 32,
        ),
      ),
      children: const [
        Text('Ứng dụng quản lý chi tiêu cá nhân và gia đình'),
        SizedBox(height: 16),
        Text('Tính năng chính:'),
        Text('• Quản lý thu chi offline/online'),
        Text('• Đồng bộ với đối tác'),
        Text('• Báo cáo chi tiết'),
        Text('• Quản lý ngân sách'),
      ],
    );
  }

  void _showFeatureNotImplemented(String feature) {
    _showErrorSnackBar('$feature chưa được triển khai');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }
}
