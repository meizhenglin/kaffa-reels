import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/hai_pay_models.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/app_providers.dart';

/// Service for HaiPay H5 payment integration
/// Mirrors the Android project's payment flow:
/// 1. Get payment methods from backend
/// 2. Create order → get H5 payment URL
/// 3. Open H5 page (WebView or external browser)
/// 4. Poll for payment status on resume
class HaiPayService {
  HaiPayService({
    required DioClient dioClient,
    required StorageService storage,
  })  : _dioClient = dioClient,
        _storage = storage;

  final DioClient _dioClient;
  final StorageService _storage;
  Dio get _dio => _dioClient.dio;

  /// Get available payment methods from backend
  /// Equivalent to Android's: viewModel.payMethod(currency, price, productName)
  Future<List<HaiPayMethod>> getPaymentMethods({
    required String currency,
    required String price,
    required String productName,
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        '/pay/payMethod',
        data: {
          'currency': currency,
          'price': price,
          'productName': productName,
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        List<HaiPayMethod> methods = [];

        if (body['data'] is List) {
          methods = (body['data'] as List)
              .map((e) => HaiPayMethod.fromJson(e as Map<String, dynamic>))
              .toList();
        }

        return methods.isNotEmpty ? methods : HaiPayMethodsResponse.fallbackMethods;
      }

      return HaiPayMethodsResponse.fallbackMethods;
    } catch (e) {
      debugPrint('[HaiPayService] getPaymentMethods error: $e');
      return HaiPayMethodsResponse.fallbackMethods;
    }
  }

  /// Create VIP subscription order
  /// Equivalent to Android's: viewModel.payVip(map)
  Future<HaiPayOrder?> createVipOrder({
    required int payMethodId,
    required String vipId,
    required String money,
    required String currency,
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        '/pay/payVip',
        data: {
          'payMethodId': payMethodId.toString(),
          'vipId': vipId,
          'money': money,
          'currency': currency,
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (body['data'] != null) {
          return HaiPayOrder.fromJson(body['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[HaiPayService] createVipOrder error: $e');
      return null;
    }
  }

  /// Create coin recharge order
  /// Equivalent to Android's: viewModel.payRecharge(map)
  Future<HaiPayOrder?> createRechargeOrder({
    required int payMethodId,
    required int goodsId,
    required String amount,
    required String currency,
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        '/pay/payRecharge',
        data: {
          'payMethodId': payMethodId.toString(),
          'goodsId': goodsId.toString(),
          'amount': amount,
          'currency': currency,
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (body['data'] != null) {
          return HaiPayOrder.fromJson(body['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[HaiPayService] createRechargeOrder error: $e');
      return null;
    }
  }

  /// Create episode unlock order
  /// Equivalent to Android's: viewModel.payEpisode(map)
  Future<HaiPayOrder?> createEpisodeUnlockOrder({
    required int payMethodId,
    required String videoId,
    required String episodeId,
    required int episodesNum,
    required int goodsId,
    required String amount,
    required String currency,
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        '/pay/payEpisode',
        data: {
          'payMethodId': payMethodId.toString(),
          'videoId': videoId,
          'episodeId': episodeId,
          'episodesNum': episodesNum.toString(),
          'goodsId': goodsId.toString(),
          'amount': amount,
          'currency': currency,
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (body['data'] != null) {
          return HaiPayOrder.fromJson(body['data'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[HaiPayService] createEpisodeUnlockOrder error: $e');
      return null;
    }
  }

  /// Poll payment status
  /// type: "1" = VIP, "2" = recharge, "3" = episode unlock
  /// Equivalent to Android's: viewModel.getOrderIsPay(type, orderNo)
  Future<HaiPayStatus> pollPaymentStatus({
    required String type,
    required String orderNo,
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        '/pay/getOrderIsPay',
        data: {
          'type': type,
          'orderNo': orderNo,
        },
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (body['data'] != null) {
          return HaiPayStatus.fromJson(body['data'] as Map<String, dynamic>);
        }
      }
      return const HaiPayStatus(isPay: '1');
    } catch (e) {
      debugPrint('[HaiPayService] pollPaymentStatus error: $e');
      return const HaiPayStatus(isPay: '1');
    }
  }

  /// Start polling for payment status
  /// Stops when payment is confirmed or timeout is reached
  Stream<HaiPayStatus> startPolling({
    required String type,
    required String orderNo,
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 10),
  }) async* {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      final status = await pollPaymentStatus(type: type, orderNo: orderNo);
      yield status;

      if (status.isPaid) break;

      await Future.delayed(interval);
    }
  }

  /// One-shot payment status check
  Future<bool> checkPaymentStatus({
    required String type,
    required String orderNo,
  }) async {
    final status = await pollPaymentStatus(type: type, orderNo: orderNo);
    return status.isPaid;
  }
}

/// Provider for HaiPayService
final haiPayServiceProvider = Provider<HaiPayService>((ref) {
  return HaiPayService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
});
