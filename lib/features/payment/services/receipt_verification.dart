import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Service for verifying purchase receipts with the backend
/// 
/// IMPORTANT: Receipt verification MUST be done server-side for security.
/// The app sends the raw receipt data to your backend, which then:
/// 1. Validates the receipt signature
/// 2. Queries Google/Apple servers to verify authenticity
/// 3. Stores the verified subscription status in your database
/// 
/// Never trust client-side subscription status alone!
class ReceiptVerificationService {
  ReceiptVerificationService._();
  static final ReceiptVerificationService instance =
      ReceiptVerificationService._();

  late final Dio _dio;

  /// Base URL for your backend API
  /// TODO: Replace with your actual backend URL
  static const _baseUrl = 'https://api.your-domain.com';

  void initialize({String? baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors for logging and auth
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('Receipt API Request: ${options.method} ${options.path}');
        return handler.next(options);
      },
      onError: (error, handler) {
        debugPrint('Receipt API Error: ${error.message}');
        return handler.next(error);
      },
    ));
  }

  /// Verify a purchase receipt with the backend
  /// 
  /// [receiptData] - The raw receipt/purchase data from in-app purchase
  /// [platform] - 'google_play' or 'app_store'
  /// [userId] - The authenticated user's ID (if logged in)
  /// 
  /// Returns [ReceiptVerificationResult] with verification status
  Future<ReceiptVerificationResult> verifyReceipt({
    required Map<String, dynamic> receiptData,
    required String platform,
    String? userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/subscriptions/verify',
        data: {
          'receipt': receiptData,
          'platform': platform,
          if (userId != null) 'user_id': userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return ReceiptVerificationResult.fromJson(data);
      }

      return ReceiptVerificationResult.failure(
        message: 'Server returned status ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('Receipt verification failed: ${e.message}');
      
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return ReceiptVerificationResult.failure(
          message: 'Network error. Please check your connection.',
          isNetworkError: true,
        );
      }

      // Parse error response if available
      if (e.response?.data != null) {
        try {
          final errorData = e.response!.data as Map<String, dynamic>;
          return ReceiptVerificationResult.fromJson(errorData);
        } catch (_) {}
      }

      return ReceiptVerificationResult.failure(
        message: 'Verification failed: ${e.message}',
      );
    } catch (e) {
      debugPrint('Unexpected error in receipt verification: $e');
      return ReceiptVerificationResult.failure(
        message: 'An unexpected error occurred',
      );
    }
  }

  /// Check subscription status from backend
  /// 
  /// Used for:
  /// - Checking if user's subscription is still active
  /// - Syncing subscription state after app restart
  /// - Checking before granting premium features
  Future<SubscriptionStatus?> checkSubscriptionStatus({
    required String userId,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/subscriptions/status',
        queryParameters: {'user_id': userId},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return SubscriptionStatus.fromJson(data);
      }

      return null;
    } on DioException catch (e) {
      debugPrint('Failed to check subscription status: ${e.message}');
      return null;
    }
  }

  /// Cancel subscription (initiated by user through app)
  /// 
  /// Note: Actual cancellation must be done through:
  /// - Google Play Console > Subscriptions page
  /// - App Store Connect > Subscriptions page
  /// 
  /// This just notifies your backend to update records
  Future<bool> cancelSubscription({
    required String userId,
    required String platform,
    required String subscriptionId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/subscriptions/cancel',
        data: {
          'user_id': userId,
          'platform': platform,
          'subscription_id': subscriptionId,
        },
      );

      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('Failed to cancel subscription: ${e.message}');
      return false;
    }
  }

  /// Report subscription lifecycle events to backend
  /// 
  /// IMPORTANT: Your backend should also listen to Google/Apple
  /// Real-time developer notifications (RTDN) for:
  /// - Subscription renewed
  /// - Subscription canceled
  /// - Subscription expired
  /// - Payment failed
  /// - Billing retry
  Future<void> reportEvent({
    required String userId,
    required String event,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _dio.post(
        '/api/v1/subscriptions/events',
        data: {
          'user_id': userId,
          'event': event,
          'data': data,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      // Non-critical, don't throw
      debugPrint('Failed to report event: $e');
    }
  }
}

/// Result of receipt verification
class ReceiptVerificationResult {
  const ReceiptVerificationResult({
    required this.success,
    required this.isValid,
    this.message,
    this.expireDate,
    this.subscriptionType,
    this.isNetworkError = false,
  });

  factory ReceiptVerificationResult.fromJson(Map<String, dynamic> json) {
    return ReceiptVerificationResult(
      success: json['success'] ?? false,
      isValid: json['is_valid'] ?? false,
      message: json['message'],
      expireDate: json['expire_date'] != null
          ? DateTime.tryParse(json['expire_date'])
          : null,
      subscriptionType: json['subscription_type'],
    );
  }

  factory ReceiptVerificationResult.failure({
    required String message,
    bool isNetworkError = false,
  }) {
    return ReceiptVerificationResult(
      success: false,
      isValid: false,
      message: message,
      isNetworkError: isNetworkError,
    );
  }

  /// Whether the API call succeeded
  final bool success;

  /// Whether the receipt is valid
  final bool isValid;

  /// Human-readable message
  final String? message;

  /// Subscription expiration date (from verified receipt)
  final DateTime? expireDate;

  /// Type of subscription (monthly, quarterly, yearly)
  final String? subscriptionType;

  /// Whether the failure was due to network error
  final bool isNetworkError;
}

/// Subscription status from backend
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.isActive,
    this.expireDate,
    this.type,
    this.autoRenew,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      isActive: json['is_active'] ?? false,
      expireDate: json['expire_date'] != null
          ? DateTime.tryParse(json['expire_date'])
          : null,
      type: json['type'],
      autoRenew: json['auto_renew'],
    );
  }

  final bool isActive;
  final DateTime? expireDate;
  final String? type;
  final bool? autoRenew;
}
