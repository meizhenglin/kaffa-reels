import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:qahwa_tv/features/payment/services/play_billing_probe.dart';

PlayBillingQueryResult result({
  required BillingResponse responseCode,
  List<String> unfetched = const [],
  List<String> found = const [],
  String? debugMessage,
  ProductType type = ProductType.subs,
}) {
  return PlayBillingQueryResult(
    productType: type,
    responseCode: responseCode,
    debugMessage: debugMessage,
    unfetchedIds: unfetched,
    foundIds: found,
  );
}

void main() {
  group('PlayBillingQueryResult.playCode', () {
    test('maps plugin enum to Play official numeric codes', () {
      expect(result(responseCode: BillingResponse.ok).playCode, 0);
      expect(result(responseCode: BillingResponse.serviceUnavailable).playCode, 2);
      expect(result(responseCode: BillingResponse.billingUnavailable).playCode, 3);
      expect(result(responseCode: BillingResponse.itemUnavailable).playCode, 4);
      expect(result(responseCode: BillingResponse.developerError).playCode, 5);
      expect(result(responseCode: BillingResponse.error).playCode, 6);
      expect(result(responseCode: BillingResponse.networkError).playCode, 9);
      expect(result(responseCode: BillingResponse.serviceDisconnected).playCode, -1);
    });
  });

  group('PlayBillingProbe.interpret', () {
    test('SERVICE_UNAVAILABLE is reported as a Play/account problem, not a product ID problem', () {
      final text = PlayBillingProbe.interpret(
        result(responseCode: BillingResponse.serviceUnavailable),
      );
      expect(text, contains('Play 服务不可用'));
      expect(text, contains('license tester'));
      // The whole point: it must state the product ID is irrelevant,
      // instead of implying the ID is wrong.
      expect(text, contains('商品 ID 是否正确无关'));
      expect(text, isNot(contains('这才是商品 ID')));
    });

    test('OK + unfetched IDs does NOT claim the product does not exist', () {
      final text = PlayBillingProbe.interpret(
        result(responseCode: BillingResponse.ok, unfetched: ['com.qahwa.vip1']),
      );
      expect(text, contains('com.qahwa.vip1'));
      // 「取不到详情」既可能是商品不存在，也可能是商品存在但当前账号/国家
      // 买不了（NO_ELIGIBLE_OFFER）。纯 Dart 探针分不出来，所以措辞不能
      // 断言「商品不存在」，必须指向原生探针的逐商品状态码。
      expect(text, isNot(contains('商品 ID 拼写')));
      expect(text, contains('NO_ELIGIBLE_OFFER'));
    });

    test('OK with nothing fetched at all is not blamed on the product ID', () {
      final text = PlayBillingProbe.interpret(result(responseCode: BillingResponse.ok));
      expect(text, contains('没有返回任何商品'));
      expect(text, isNot(contains('商品 ID')));
    });

    test('developerError points at the product type', () {
      final text = PlayBillingProbe.interpret(
        result(responseCode: BillingResponse.developerError),
      );
      expect(text, contains('商品类型'));
    });

    test('billingUnavailable points at the Play Store app', () {
      final text = PlayBillingProbe.interpret(
        result(responseCode: BillingResponse.billingUnavailable),
      );
      expect(text, contains('Play 商店'));
    });

    test('networkError points at the network', () {
      final text = PlayBillingProbe.interpret(
        result(responseCode: BillingResponse.networkError),
      );
      expect(text, contains('网络'));
    });
  });

  group('PlayBillingProbe.describe', () {
    test('renders both product types with their codes', () {
      final text = PlayBillingProbe.describe([
        result(
          responseCode: BillingResponse.serviceUnavailable,
          type: ProductType.subs,
          debugMessage: 'SERVICE_UNAVAILABLE',
        ),
        result(
          responseCode: BillingResponse.ok,
          type: ProductType.inapp,
          unfetched: ['com.qahwa.vip1'],
        ),
      ]);

      expect(text, contains('subs'));
      expect(text, contains('inapp'));
      expect(text, contains('code=2'));
      expect(text, contains('code=0'));
      expect(text, contains('debugMessage: SERVICE_UNAVAILABLE'));
      expect(text, contains('com.qahwa.vip1'));
    });

    test('handles an empty result set', () {
      expect(PlayBillingProbe.describe([]), contains('no Play billing result'));
    });
  });
}
