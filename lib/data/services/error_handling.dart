import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

// ============ ERROR CLASSIFICATION ============

enum ErrorType {
  network('Lỗi mạng'),
  firebase('Lỗi Firebase'),
  database('Lỗi cơ sở dữ liệu'),
  authentication('Lỗi xác thực'),
  validation('Lỗi dữ liệu'),
  permission('Lỗi quyền truy cập'),
  quota('Vượt giới hạn'),
  timeout('Hết thời gian chờ'),
  unknown('Lỗi không xác định');

  const ErrorType(this.displayName);
  final String displayName;
}

enum ErrorSeverity {
  low('Thấp'),
  medium('Trung bình'),
  high('Cao'),
  critical('Nghiêm trọng');

  const ErrorSeverity(this.displayName);
  final String displayName;

  Color get color {
    switch (this) {
      case ErrorSeverity.low:
        return Colors.green;
      case ErrorSeverity.medium:
        return Colors.orange;
      case ErrorSeverity.high:
        return Colors.red;
      case ErrorSeverity.critical:
        return Colors.red.shade800;
    }
  }
}

// ============ ERROR MODELS ============

class AppError {
  final String id;
  final ErrorType type;
  final ErrorSeverity severity;
  final String message;
  final String? technicalDetails;
  final DateTime timestamp;
  final String? operation;
  final Map<String, dynamic>? context;
  final String? stackTrace;
  final bool isRetryable;
  final int retryCount;

  const AppError({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    this.technicalDetails,
    required this.timestamp,
    this.operation,
    this.context,
    this.stackTrace,
    this.isRetryable = false,
    this.retryCount = 0,
  });

  factory AppError.fromException(
    dynamic exception, {
    String? operation,
    Map<String, dynamic>? context,
    int retryCount = 0,
  }) {
    final errorId = _generateErrorId();
    final timestamp = DateTime.now();

    if (exception is SocketException) {
      return AppError(
        id: errorId,
        type: ErrorType.network,
        severity: ErrorSeverity.high,
        message: 'Không thể kết nối mạng. Vui lòng kiểm tra kết nối internet.',
        technicalDetails: exception.message,
        timestamp: timestamp,
        operation: operation,
        context: context,
        stackTrace: exception.toString(),
        isRetryable: true,
        retryCount: retryCount,
      );
    }

    if (exception is TimeoutException) {
      return AppError(
        id: errorId,
        type: ErrorType.timeout,
        severity: ErrorSeverity.medium,
        message: 'Thao tác mất quá nhiều thời gian. Vui lòng thử lại.',
        technicalDetails: exception.message,
        timestamp: timestamp,
        operation: operation,
        context: context,
        stackTrace: exception.toString(),
        isRetryable: true,
        retryCount: retryCount,
      );
    }

    if (exception is FirebaseException) {
      return _handleFirebaseException(
        exception,
        errorId,
        timestamp,
        operation,
        context,
        retryCount,
      );
    }

    if (exception is DatabaseException) {
      return _handleDatabaseException(
        exception,
        errorId,
        timestamp,
        operation,
        context,
        retryCount,
      );
    }

    // Unknown error
    return AppError(
      id: errorId,
      type: ErrorType.unknown,
      severity: ErrorSeverity.medium,
      message: 'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại.',
      technicalDetails: exception.toString(),
      timestamp: timestamp,
      operation: operation,
      context: context,
      stackTrace: exception.toString(),
      isRetryable: false,
      retryCount: retryCount,
    );
  }

  static AppError _handleFirebaseException(
    FirebaseException exception,
    String errorId,
    DateTime timestamp,
    String? operation,
    Map<String, dynamic>? context,
    int retryCount,
  ) {
    ErrorType type;
    ErrorSeverity severity;
    String message;
    bool isRetryable;

    switch (exception.code) {
      case 'network-request-failed':
      case 'unavailable':
        type = ErrorType.network;
        severity = ErrorSeverity.high;
        message =
            'Kết nối mạng bị gián đoạn. Dữ liệu sẽ được đồng bộ khi có mạng.';
        isRetryable = true;
        break;

      case 'permission-denied':
        type = ErrorType.permission;
        severity = ErrorSeverity.critical;
        message = 'Không có quyền truy cập dữ liệu. Vui lòng đăng nhập lại.';
        isRetryable = false;
        break;

      case 'quota-exceeded':
        type = ErrorType.quota;
        severity = ErrorSeverity.high;
        message = 'Đã vượt giới hạn sử dụng. Vui lòng thử lại sau.';
        isRetryable = true;
        break;

      case 'unauthenticated':
        type = ErrorType.authentication;
        severity = ErrorSeverity.critical;
        message = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
        isRetryable = false;
        break;

      default:
        type = ErrorType.firebase;
        severity = ErrorSeverity.medium;
        message = 'Lỗi dịch vụ. Vui lòng thử lại sau.';
        isRetryable = true;
    }

    return AppError(
      id: errorId,
      type: type,
      severity: severity,
      message: message,
      technicalDetails: '${exception.code}: ${exception.message}',
      timestamp: timestamp,
      operation: operation,
      context: context,
      stackTrace: exception.stackTrace?.toString(),
      isRetryable: isRetryable,
      retryCount: retryCount,
    );
  }

  static AppError _handleDatabaseException(
    DatabaseException exception,
    String errorId,
    DateTime timestamp,
    String? operation,
    Map<String, dynamic>? context,
    int retryCount,
  ) {
    ErrorSeverity severity;
    String message;
    bool isRetryable;

    // Check for corruption error by inspecting the message
    if (exception.toString().toLowerCase().contains(
          'database disk image is malformed',
        ) ||
        exception.toString().toLowerCase().contains('file is not a database') ||
        exception.toString().toLowerCase().contains('malformed')) {
      severity = ErrorSeverity.critical;
      message = 'Cơ sở dữ liệu bị lỗi. Ứng dụng cần khởi tạo lại.';
      isRetryable = false;
    }
    // Check for closed database error
    else if (exception.toString().toLowerCase().contains(
      'database is closed',
    )) {
      severity = ErrorSeverity.medium;
      message = 'Kết nối cơ sở dữ liệu bị ngắt. Đang thử kết nối lại.';
      isRetryable = true;
    } else {
      severity = ErrorSeverity.medium;
      message = 'Lỗi lưu trữ dữ liệu. Vui lòng thử lại.';
      isRetryable = true;
    }

    return AppError(
      id: errorId,
      type: ErrorType.database,
      severity: severity,
      message: message,
      technicalDetails: exception.toString(),
      timestamp: timestamp,
      operation: operation,
      context: context,
      stackTrace: exception.toString(),
      isRetryable: isRetryable,
      retryCount: retryCount,
    );
  }

  static String _generateErrorId() {
    return 'ERR_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999).toString().padLeft(4, '0')}';
  }

  AppError withRetryCount(int newRetryCount) {
    return AppError(
      id: id,
      type: type,
      severity: severity,
      message: message,
      technicalDetails: technicalDetails,
      timestamp: timestamp,
      operation: operation,
      context: context,
      stackTrace: stackTrace,
      isRetryable: isRetryable,
      retryCount: newRetryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'severity': severity.name,
      'message': message,
      'technicalDetails': technicalDetails,
      'timestamp': timestamp.toIso8601String(),
      'operation': operation,
      'context': context,
      'stackTrace': stackTrace,
      'isRetryable': isRetryable,
      'retryCount': retryCount,
    };
  }
}

// ============ RETRY CONFIGURATION ============

class RetryConfig {
  final int maxRetries;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final bool useJitter;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.useJitter = true,
  });

  static const RetryConfig immediate = RetryConfig(
    maxRetries: 1,
    initialDelay: Duration.zero,
    maxDelay: Duration.zero,
    backoffMultiplier: 1.0,
    useJitter: false,
  );

  static const RetryConfig fast = RetryConfig(
    maxRetries: 3,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 5),
    backoffMultiplier: 1.5,
    useJitter: true,
  );

  static const RetryConfig standard = RetryConfig(
    maxRetries: 5,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
    useJitter: true,
  );

  static const RetryConfig aggressive = RetryConfig(
    maxRetries: 10,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(minutes: 2),
    backoffMultiplier: 2.0,
    useJitter: true,
  );

  Duration getDelay(int attemptNumber) {
    if (maxRetries <= 0) return Duration.zero;

    num delayMs =
        initialDelay.inMilliseconds * pow(backoffMultiplier, attemptNumber - 1);

    // Apply max delay limit
    delayMs = min(delayMs, maxDelay.inMilliseconds.toDouble());

    // Apply jitter to prevent thundering herd
    if (useJitter) {
      final jitter = Random().nextDouble() * 0.1; // ±10% jitter
      delayMs *= (1.0 + jitter - 0.05);
    }

    return Duration(milliseconds: delayMs.round());
  }
}

// ============ ENHANCED ERROR HANDLER ============

class EnhancedErrorHandler {
  static final EnhancedErrorHandler _instance =
      EnhancedErrorHandler._internal();
  factory EnhancedErrorHandler() => _instance;
  EnhancedErrorHandler._internal();

  final List<AppError> _errorHistory = [];
  final Map<String, Timer> _retryTimers = {};
  final StreamController<AppError> _errorStream = StreamController.broadcast();

  Stream<AppError> get errorStream => _errorStream.stream;
  List<AppError> get recentErrors => List.unmodifiable(
    _errorHistory
        .where((e) => DateTime.now().difference(e.timestamp).inMinutes < 30)
        .toList(),
  );

  /// Execute operation with automatic retry logic
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    String? operationName,
    RetryConfig config = RetryConfig.standard,
    Map<String, dynamic>? context,
    bool Function(AppError)? shouldRetry,
  }) async {
    int attemptCount = 0;
    AppError? lastError;

    while (attemptCount <= config.maxRetries) {
      attemptCount++;

      try {
        debugPrint(
          '🔄 Executing ${operationName ?? 'operation'} (attempt $attemptCount/${config.maxRetries + 1})',
        );

        final result = await operation();

        if (attemptCount > 1) {
          debugPrint(
            '✅ ${operationName ?? 'Operation'} succeeded after $attemptCount attempts',
          );
        }

        return result;
      } catch (exception) {
        final error = AppError.fromException(
          exception,
          operation: operationName,
          context: context,
          retryCount: attemptCount - 1,
        );

        lastError = error;
        _recordError(error);

        // Check if we should retry
        final isLastAttempt = attemptCount > config.maxRetries;
        final canRetry = error.isRetryable && !isLastAttempt;
        final customShouldRetry = shouldRetry?.call(error) ?? true;

        if (!canRetry || !customShouldRetry) {
          debugPrint(
            '❌ ${operationName ?? 'Operation'} failed permanently: ${error.message}',
          );
          _errorStream.add(error);
          rethrow;
        }

        // Calculate delay for next attempt
        final delay = config.getDelay(attemptCount);

        debugPrint(
          '⏳ ${operationName ?? 'Operation'} failed (attempt $attemptCount), retrying in ${delay.inMilliseconds}ms: ${error.message}',
        );

        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      }
    }

    // This should never be reached, but just in case
    if (lastError != null) {
      _errorStream.add(lastError);
      throw Exception(lastError.message);
    }

    throw Exception('Operation failed without error information');
  }

  /// Execute operation with timeout
  Future<T> executeWithTimeout<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 30),
    String? operationName,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException {
      final error = AppError.fromException(
        TimeoutException(
          'Operation timed out after ${timeout.inSeconds}s',
          timeout,
        ),
        operation: operationName,
      );
      _recordError(error);
      _errorStream.add(error);
      rethrow;
    }
  }

  /// Execute operation with both retry and timeout
  Future<T> executeRobust<T>(
    Future<T> Function() operation, {
    String? operationName,
    RetryConfig retryConfig = RetryConfig.standard,
    Duration timeout = const Duration(seconds: 30),
    Map<String, dynamic>? context,
    bool Function(AppError)? shouldRetry,
  }) async {
    return executeWithRetry<T>(
      () => executeWithTimeout<T>(
        operation,
        timeout: timeout,
        operationName: operationName,
      ),
      operationName: operationName,
      config: retryConfig,
      context: context,
      shouldRetry: shouldRetry,
    );
  }

  /// Schedule a retry for later execution
  void scheduleRetry(
    String retryId,
    Future<void> Function() operation,
    Duration delay, {
    String? operationName,
  }) {
    // Cancel existing timer if any
    _retryTimers[retryId]?.cancel();

    _retryTimers[retryId] = Timer(delay, () async {
      try {
        debugPrint('🔄 Executing scheduled retry: $retryId');
        await operation();
        debugPrint('✅ Scheduled retry succeeded: $retryId');
      } catch (e) {
        debugPrint('❌ Scheduled retry failed: $retryId - $e');
        final error = AppError.fromException(e, operation: operationName);
        _recordError(error);
        _errorStream.add(error);
      } finally {
        _retryTimers.remove(retryId);
      }
    });
  }

  /// Cancel a scheduled retry
  void cancelRetry(String retryId) {
    _retryTimers[retryId]?.cancel();
    _retryTimers.remove(retryId);
  }

  /// Record error for analytics and debugging
  void _recordError(AppError error) {
    _errorHistory.add(error);

    // Keep only recent errors (last 1000 or last 24 hours)
    final cutoffTime = DateTime.now().subtract(const Duration(hours: 24));
    _errorHistory.removeWhere(
      (e) => e.timestamp.isBefore(cutoffTime) && _errorHistory.length > 1000,
    );

    // Log error for debugging
    debugPrint(
      '📝 Error recorded: ${error.id} - ${error.type.displayName} - ${error.message}',
    );
  }

  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final recentErrors = this.recentErrors;

    final stats = <String, dynamic>{
      'total': recentErrors.length,
      'byType': <String, int>{},
      'bySeverity': <String, int>{},
      'retryableErrors': recentErrors.where((e) => e.isRetryable).length,
      'averageRetryCount': 0.0,
    };

    if (recentErrors.isNotEmpty) {
      // Count by type
      for (final error in recentErrors) {
        stats['byType'][error.type.name] =
            (stats['byType'][error.type.name] ?? 0) + 1;
        stats['bySeverity'][error.severity.name] =
            (stats['bySeverity'][error.severity.name] ?? 0) + 1;
      }

      // Calculate average retry count
      final totalRetries = recentErrors.fold<int>(
        0,
        (sum, e) => sum + e.retryCount,
      );
      stats['averageRetryCount'] = totalRetries / recentErrors.length;
    }

    return stats;
  }

  /// Clear error history
  void clearErrorHistory() {
    _errorHistory.clear();
    debugPrint('🧹 Error history cleared');
  }

  /// Dispose resources
  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _errorStream.close();
  }
}

// ============ ERROR MONITORING WIDGET ============

class ErrorMonitoringWidget extends StatefulWidget {
  final Widget child;

  const ErrorMonitoringWidget({super.key, required this.child});

  @override
  State<ErrorMonitoringWidget> createState() => _ErrorMonitoringWidgetState();
}

class _ErrorMonitoringWidgetState extends State<ErrorMonitoringWidget> {
  late StreamSubscription<AppError> _errorSubscription;
  final List<AppError> _displayedErrors = [];

  @override
  void initState() {
    super.initState();
    _errorSubscription = EnhancedErrorHandler().errorStream.listen(
      _handleError,
    );
  }

  void _handleError(AppError error) {
    if (!mounted) return;

    // Only show certain types of errors to user
    if (_shouldDisplayToUser(error)) {
      setState(() {
        _displayedErrors.add(error);
      });

      // Auto-dismiss non-critical errors
      if (error.severity != ErrorSeverity.critical) {
        Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _displayedErrors.remove(error);
            });
          }
        });
      }

      // Show snackbar for immediate feedback
      _showErrorSnackbar(error);
    }
  }

  bool _shouldDisplayToUser(AppError error) {
    // Don't show low severity errors
    if (error.severity == ErrorSeverity.low) return false;

    // Don't show network errors if they're retryable (they'll be handled automatically)
    if (error.type == ErrorType.network && error.isRetryable) return false;

    // Show critical errors always
    if (error.severity == ErrorSeverity.critical) return true;

    // Show high severity errors
    if (error.severity == ErrorSeverity.high) return true;

    // Show medium severity errors that aren't retryable
    if (error.severity == ErrorSeverity.medium && !error.isRetryable)
      return true;

    return false;
  }

  void _showErrorSnackbar(AppError error) {
    if (!mounted) return;

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(_getErrorIcon(error.type), color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: error.severity.color,
      duration: Duration(
        seconds: error.severity == ErrorSeverity.critical ? 10 : 4,
      ),
      action: error.severity == ErrorSeverity.critical
          ? SnackBarAction(
              label: 'Chi tiết',
              textColor: Colors.white,
              onPressed: () => _showErrorDetails(error),
            )
          : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  IconData _getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.firebase:
        return Icons.cloud_off;
      case ErrorType.database:
        return Icons.storage;
      case ErrorType.authentication:
        return Icons.lock;
      case ErrorType.permission:
        return Icons.security;
      case ErrorType.timeout:
        return Icons.access_time;
      default:
        return Icons.error;
    }
  }

  void _showErrorDetails(AppError error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getErrorIcon(error.type), color: error.severity.color),
            const SizedBox(width: 8),
            Expanded(child: Text(error.type.displayName)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mô tả:', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(error.message),
              const SizedBox(height: 12),
              Text('Mã lỗi:', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(error.id, style: const TextStyle(fontFamily: 'monospace')),
              if (error.technicalDetails != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Chi tiết kỹ thuật:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  error.technicalDetails!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Thời gian: ${_formatTimestamp(error.timestamp)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          if (error.isRetryable)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Trigger retry if applicable
              },
              child: const Text('Thử Lại'),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_displayedErrors.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: _displayedErrors
                    .where((e) => e.severity == ErrorSeverity.critical)
                    .map(
                      (error) => _ErrorBanner(
                        error: error,
                        onDismiss: () {
                          setState(() {
                            _displayedErrors.remove(error);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _errorSubscription.cancel();
    super.dispose();
  }
}

class _ErrorBanner extends StatelessWidget {
  final AppError error;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.error, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: error.severity.color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: onDismiss,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
