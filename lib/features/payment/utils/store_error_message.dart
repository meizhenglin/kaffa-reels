import '../../../l10n/app_localizations.dart';

/// 把商店购买失败的内部归因码（`ios-store-error`、`play-item-not-found` 之类）
/// 转成用户能看懂的文案，并把 StoreKit / Play 的原始错误细节附在第二行。
///
/// 【为什么要统一】充值页、解锁弹窗各自维护了一份映射，解锁弹窗那份
/// 只覆盖了 `not-found` / `unavailable`，遇到 `ios-store-error` 这类码
/// 就把内部码原样弹给用户（用户完全看不懂）。排障细节（SKError 原文）
/// 也只有充值页带上了。此函数是唯一出口，所有购买失败提示都走这里。
///
/// 返回值形如：
/// ```
/// Purchase failed. Please try again.
/// (SKError code=storekit_no_response, message=...)
/// ```
String friendlyStorePurchaseError(AppLocalizations l10n, String? rawError) {
  final err = (rawError ?? '').trim();

  String reason;
  if (err.contains('store-unavailable') || err.contains('service-unavailable')) {
    // ios-store-unavailable / play-store-unavailable / play-service-unavailable
    reason = l10n.membershipIosStoreUnavailable;
  } else if (err.contains('not-found') ||
      err.contains('item-unavailable') ||
      err.contains('unavailable')) {
    // ios-item-not-found / play-item-not-found / play-no-eligible-offer
    reason = l10n.productUnavailable;
  } else if (err.contains('network-error')) {
    // ios-network-error
    reason = l10n.purchaseFailedPleaseRetry;
  } else if (err.contains('store-error') || err.isEmpty) {
    // ios-store-error（其他 SKError，具体看第二行的原始信息）
    reason = l10n.purchaseFailedPleaseRetry;
  } else {
    // 保留原始错误消息：Play 的 itemAlreadyOwned 等真实消息上层
    // 要做关键字匹配（如解锁链路的已购恢复），提示里也不能丢。
    reason = err;
  }

  // 【不带调试详情】StoreKit / Play 的原始错误细节只进日志
  // （PaymentService 内部已 debugPrint），不再拼进用户可见的提示——
  // 提示里出现过中文排障文案，正式包不允许。
  return reason;
}
