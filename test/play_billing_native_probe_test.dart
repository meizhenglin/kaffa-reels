import 'package:flutter_test/flutter_test.dart';
import 'package:qahwa_tv/features/payment/services/play_billing_native_probe.dart';

/// 构造一份原生探针的原始返回，模拟 `BillingProbe.java` 的输出结构。
Map<String, dynamic> rawResult({
  int setupCode = 0,
  String? countryCode = 'US',
  List<String> subs = const [],
  List<String> inapp = const [],
}) {
  return <String, dynamic>{
    'setupCode': setupCode,
    'setupDebugMessage': setupCode == 0 ? null : 'setup failed',
    'countryCode': countryCode,
    'queries': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'subs',
        'responseCode': 0,
        'debugMessage': null,
        'found': <Map<String, dynamic>>[
          for (final id in subs)
            <String, dynamic>{
              'productId': id,
              'title': id,
              'productType': 'subs',
            },
        ],
        'unfetched': <Map<String, dynamic>>[],
      },
      <String, dynamic>{
        'type': 'inapp',
        'responseCode': 0,
        'debugMessage': null,
        'found': <Map<String, dynamic>>[
          for (final id in inapp)
            <String, dynamic>{
              'productId': id,
              'title': id,
              'productType': 'inapp',
            },
        ],
        'unfetched': <Map<String, dynamic>>[],
      },
    ],
  };
}

/// 在指定查询里追加一个「取不到」的商品。
Map<String, dynamic> withUnfetched(
  Map<String, dynamic> raw, {
  required String queryType,
  required String productId,
  required int statusCode,
  String? productType,
}) {
  final queries = (raw['queries'] as List).cast<Map<String, dynamic>>();
  for (final q in queries) {
    if (q['type'] != queryType) continue;
    final unfetched = (q['unfetched'] as List).cast<Map<String, dynamic>>();
    unfetched.add(<String, dynamic>{
      'productId': productId,
      'productType': productType ?? queryType,
      'statusCode': statusCode,
    });
    q['unfetched'] = unfetched;
  }
  return raw;
}

void main() {
  group('PlayUnfetchedStatus', () {
    test('names the status codes Play returns', () {
      expect(PlayUnfetchedStatus.name(0), 'UNKNOWN');
      expect(PlayUnfetchedStatus.name(2), 'INVALID_PRODUCT_ID_FORMAT');
      expect(PlayUnfetchedStatus.name(3), 'PRODUCT_NOT_FOUND');
      expect(PlayUnfetchedStatus.name(4), 'NO_ELIGIBLE_OFFER');
      expect(PlayUnfetchedStatus.name(99), 'CODE_99');
    });

    test('separates "not found" from "no eligible offer"', () {
      expect(PlayUnfetchedStatus.isNotFound(3), isTrue);
      expect(PlayUnfetchedStatus.isNotFound(4), isFalse);
      expect(PlayUnfetchedStatus.isNoEligibleOffer(4), isTrue);
      expect(PlayUnfetchedStatus.isNoEligibleOffer(3), isFalse);
    });
  });

  group('PlayNativeProbeResult', () {
    test('parses setup code and country code', () {
      final parsed = PlayNativeBillingProbe.parseResult(rawResult());
      expect(parsed.isOk, isTrue);
      expect(parsed.setupCode, 0);
      expect(parsed.countryCode, 'US');
      expect(parsed.queries.length, 2);
      expect(parsed.queries.first.type, 'subs');
    });

    test('reports setup failure', () {
      final parsed = PlayNativeBillingProbe.parseResult(
        rawResult(setupCode: 2, countryCode: null),
      );
      expect(parsed.isOk, isFalse);
      expect(parsed.setupCode, 2);
      expect(parsed.setupDebugMessage, 'setup failed');
    });

    test('a product missing in both queries is classified as not found', () {
      var raw = withUnfetched(
        rawResult(),
        queryType: 'subs',
        productId: 'com.qahwa.vip2',
        statusCode: 3,
      );
      raw = withUnfetched(
        raw,
        queryType: 'inapp',
        productId: 'com.qahwa.vip2',
        statusCode: 3,
      );

      final parsed = PlayNativeBillingProbe.parseResult(raw);
      expect(parsed.notFoundIds, contains('com.qahwa.vip2'));
      expect(parsed.noEligibleOfferIds, isEmpty);
    });

    test('a product with no eligible offer is NOT reported as missing', () {
      var raw = withUnfetched(
        rawResult(),
        queryType: 'subs',
        productId: 'com.qahwa.vip2',
        statusCode: 4,
      );
      raw = withUnfetched(
        raw,
        queryType: 'inapp',
        productId: 'com.qahwa.vip2',
        statusCode: 3,
      );

      final parsed = PlayNativeBillingProbe.parseResult(raw);
      expect(parsed.notFoundIds, isEmpty);
      expect(parsed.noEligibleOfferIds, contains('com.qahwa.vip2'));
    });

    test(
      'a healthy subscription is not reported as missing even though the '
      'inapp query cannot fetch it',
      () {
        final raw = rawResult(subs: <String>['com.qahwa.vip1']);
        final withWrongType = withUnfetched(
          raw,
          queryType: 'inapp',
          productId: 'com.qahwa.vip1',
          statusCode: 3,
        );

        final parsed = PlayNativeBillingProbe.parseResult(withWrongType);
        expect(parsed.notFoundIds, isEmpty);
        expect(parsed.noEligibleOfferIds, isEmpty);
      },
    );

    test('unknown status codes are not silently treated as missing', () {
      var raw = withUnfetched(
        rawResult(),
        queryType: 'subs',
        productId: 'com.qahwa.vip3',
        statusCode: 0,
      );
      raw = withUnfetched(
        raw,
        queryType: 'inapp',
        productId: 'com.qahwa.vip3',
        statusCode: 0,
      );

      final parsed = PlayNativeBillingProbe.parseResult(raw);
      expect(parsed.notFoundIds, isEmpty);
      expect(parsed.noEligibleOfferIds, isEmpty);
      expect(parsed.unclassifiedIds, contains('com.qahwa.vip3'));
    });

    test('describe() mentions both kinds of failures', () {
      var raw = withUnfetched(
        rawResult(),
        queryType: 'subs',
        productId: 'com.qahwa.vip2',
        statusCode: 3,
      );
      raw = withUnfetched(
        raw,
        queryType: 'subs',
        productId: 'com.qahwa.vip3',
        statusCode: 4,
      );
      raw = withUnfetched(
        raw,
        queryType: 'inapp',
        productId: 'com.qahwa.vip2',
        statusCode: 3,
      );
      raw = withUnfetched(
        raw,
        queryType: 'inapp',
        productId: 'com.qahwa.vip3',
        statusCode: 3,
      );

      final text = PlayNativeBillingProbe.parseResult(raw).describe();
      expect(text, contains('US'));
      expect(text, contains('com.qahwa.vip2'));
      expect(text, contains('PRODUCT_NOT_FOUND'));
      expect(text, contains('NO_ELIGIBLE_OFFER'));
    });
  });
}
