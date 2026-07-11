import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/hai_pay_models.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/app_providers.dart';

/// HaiPay two-step flow:
///   1. POST /api/pay/getPayMethods
///   2a. POST /api/pay/userRechange -> merchantOrderNo
///   2b. POST /api/pay/initPay -> { payUrl, orderNo, merchantOrderNo }
///   3. Open H5 page in WebView
///   4. Poll status on resume
class HaiPayService {
  HaiPayService({
    required DioClient dioClient,
    required StorageService storage,
  })  : _dioClient = dioClient,
        _storage = storage;

  final DioClient _dioClient;
  final StorageService _storage;
  Dio get _dio => _dioClient.dio;

  static String _s(dynamic v) => v is String ? v : (v?.toString() ?? '');

  /// Backend envelope: `code: 0` or `code: 200`.
  static bool _ok(dynamic body) {
    if (body is! Map) return false;
    final code = body['code'];
    if (code is int) return code == 0 || code == 200;
    if (code is String) {
      return code == '0' ||
          code == '200' ||
          code.toLowerCase() == 'success' ||
          code.toLowerCase() == 'ok';
    }
    return false;
  }

  static Map<String, dynamic>? _data(dynamic body) {
    if (body is! Map) return null;
    final d = body['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) return null;
    return {'token': token};
  }

  /// POST /api/pay/getPayMethods
  Future<List<HaiPayMethod>> getPaymentMethods({
    required String currency,
    required String price,
    required String productName,
  }) async {
    try {
      final headers = (await _authHeaders()) ?? {};
      final response = await _dio.post(
        '/api/pay/getPayMethods',
        data: {
          'currency': currency,
          'price': price,
          'productName': productName,
        },
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (_ok(body)) {
          final data = _data(body);
          final list = data?['methods'] ?? body['data'];
          if (list is List) {
            final methods = list
                .whereType<Map>()
                .map((e) => HaiPayMethod.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            if (methods.isNotEmpty) return methods;
          }
        } else {
          debugPrint(
              '[HaiPayService] getPayMethods failed: ${response.statusCode} ${response.data}');
        }
      }
      return HaiPayMethodsResponse.fallbackMethods;
    } catch (e) {
      debugPrint('[HaiPayService] getPaymentMethods error: $e');
      return HaiPayMethodsResponse.fallbackMethods;
    }
  }

  /// POST /api/pay/userRechange
  /// Payload: { payType, payConfigId }
  ///
  /// [payType]     = the id returned by /api/pay/getPayMethods
  /// [payConfigId] = the goods/pay-config id that selects VIP / recharge / unlock
  ///
  /// Returns the merchant order number on success, null on failure.
  Future<String?> userRechange({
    required int payType,
    required int payConfigId,
  }) async {
    try {
      final headers = (await _authHeaders()) ?? {};
      final response = await _dio.post(
        '/api/pay/userRechange',
        data: {
          'payType': payType,
          'payConfigId': payConfigId,
        },
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (_ok(body)) {
          final data = _data(body);
          final orderNo = _s(data?['orderNo'] ?? body['orderNo']);
          final merchantOrderNo =
              _s(data?['merchantOrderNo'] ?? body['merchantOrderNo']);
          final n = merchantOrderNo.isNotEmpty ? merchantOrderNo : orderNo;
          if (n.isNotEmpty) return n;
        }
        debugPrint(
            '[HaiPayService] userRechange failed: ${response.statusCode} ${response.data}');
      }
      return null;
    } catch (e) {
      debugPrint('[HaiPayService] userRechange error: $e');
      return null;
    }
  }

  /// POST /api/pay/initPay
  /// Payload: { orderNo: <merchantOrderNo> }
  ///
  /// Response:
  /// { code: 200, message: 'success', payUrl, orderNo, merchantOrderNo }
  Future<HaiPayOrder?> initPay({required String merchantOrderNo}) async {
    try {
      final headers = (await _authHeaders()) ?? {};
      final response = await _dio.post(
        '/api/pay/initPay',
        data: {'orderNo': merchantOrderNo},
        options: Options(headers: headers),
      );

      // ignore: avoid_print
      print('[HaiPayService] initPay status=${response.statusCode} body=${response.data}');

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (_ok(body)) {
          // Backend wraps payload in body['data'] just like userRechange —
          // try to read from there first, fall back to the envelope itself.
          final data = _data(body);
          final payload = data ?? (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
          // ignore: avoid_print
          print('[HaiPayService] initPay payload=$payload');
          final order = HaiPayOrder.fromJson(payload);
          // ignore: avoid_print
          print('[HaiPayService] initPay parsed payInfo.len=${order.payInfo.length} orderNo=${order.orderNo}');
          if (order.payInfo.isEmpty) return null;
          return order;
        }
        debugPrint(
            '[HaiPayService] initPay failed (not ok): ${response.statusCode} ${response.data}');
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[HaiPayService] initPay error: $e');
      return null;
    }
  }

  /// Convenience: combine the two-step flow and return the openable order.
  Future<HaiPayOrder?> createAndInit({
    required int payType,
    required int payConfigId,
  }) async {
    final merchantOrderNo = await userRechange(
      payType: payType,
      payConfigId: payConfigId,
    );
    if (merchantOrderNo == null || merchantOrderNo.isEmpty) return null;
    return initPay(merchantOrderNo: merchantOrderNo);
  }

  /// Poll payment status.
  /// type: "1" = VIP, "2" = recharge, "3" = episode unlock
  Future<HaiPayStatus> pollPaymentStatus({
    required String type,
    required String orderNo,
  }) async {
    try {
      final headers = (await _authHeaders()) ?? {};
      final response = await _dio.post(
        '/pay/getOrderIsPay',
        data: {
          'type': type,
          'orderNo': orderNo,
        },
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final body = response.data;
        if (_ok(body)) {
          final data = _data(body);
          if (data != null) return HaiPayStatus.fromJson(data);
        }
      }
      return const HaiPayStatus(isPay: '1');
    } catch (e) {
      debugPrint('[HaiPayService] pollPaymentStatus error: $e');
      return const HaiPayStatus(isPay: '1');
    }
  }

  /// Start polling for payment status.
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