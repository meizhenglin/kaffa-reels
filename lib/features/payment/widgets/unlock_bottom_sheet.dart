import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show PurchaseDetails, PurchaseStatus;

import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/unlock_product.dart';
import '../models/payment_channel.dart';
import '../models/subscription_product.dart';
import '../providers/coin_record_provider.dart';
import '../providers/recharge_provider.dart';
import '../services/payment_service.dart';
import '../services/unified_payment_handler.dart';
import '../widgets/payment_channel_selector.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/widgets/app_snack_bar.dart';

/// 解锁剧集弹窗组件
/// 显示当前K币余额、解锁当前集需要的K币
/// 包含整剧解锁商品、VIP商品列表
/// 根据余额和商品类型执行不同的解锁/购买逻辑
class UnlockBottomSheet extends ConsumerStatefulWidget {
  const UnlockBottomSheet({
    super.key,
    required this.videoId,
    required this.episodeId,
    required this.episodesNum,
    required this.episodeIndex,
    required this.dramaTitle,
    this.coverUrl,
    required this.config,
    required this.onUnlockSuccess,
    this.onDismiss,
    this.onVipPurchaseSuccess,
  });

  final String videoId;
  final String episodeId;
  final int episodesNum;
  final int episodeIndex;
  final String dramaTitle;
  final String? coverUrl;
  final UnlockConfig config;
  final void Function(int episodeIndex) onUnlockSuccess;
  final VoidCallback? onDismiss;
  final VoidCallback? onVipPurchaseSuccess;

  static Future<UnlockResult?> show({
    required BuildContext context,
    required String videoId,
    required String episodeId,
    required int episodesNum,
    required int episodeIndex,
    required String dramaTitle,
    String? coverUrl,
    required UnlockConfig config,
    required void Function(int episodeIndex) onUnlockSuccess,
    VoidCallback? onDismiss,
    VoidCallback? onVipPurchaseSuccess,
  }) {
    return showModalBottomSheet<UnlockResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => UnlockBottomSheet(
        videoId: videoId,
        episodeId: episodeId,
        episodesNum: episodesNum,
        episodeIndex: episodeIndex,
        dramaTitle: dramaTitle,
        coverUrl: coverUrl,
        config: config,
        onUnlockSuccess: onUnlockSuccess,
        onDismiss: onDismiss,
        onVipPurchaseSuccess: onVipPurchaseSuccess,
      ),
    );
  }

  @override
  ConsumerState<UnlockBottomSheet> createState() => _UnlockBottomSheetState();
}

class _UnlockBottomSheetState extends ConsumerState<UnlockBottomSheet> {
  /// 正在处理的商品ID集合，支持同时处理多个商品
  final Set<int> _processingProductIds = {};
  /// 余额是否已懒加载过（避免重复请求）
  bool _balanceLazyLoaded = false;

  bool _isProcessingProduct(int goodsId) =>
      _processingProductIds.contains(goodsId);

  void _setProcessing(int goodsId, bool processing) {
    setState(() {
      if (processing) {
        _processingProductIds.add(goodsId);
      } else {
        _processingProductIds.remove(goodsId);
      }
    });
  }

  /// 懒加载余额：首次需要余额时（余额支付通道被点击）才发请求。
  Future<void> _ensureBalanceLoaded() async {
    if (_balanceLazyLoaded) return;
    _balanceLazyLoaded = true;
    await ref.read(coinBalanceInfoProvider.notifier).load();
  }

  @override
  void initState() {
    super.initState();
  }

  int get _userBalance => ref.watch(coinBalanceInfoProvider).balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.padding.bottom + 16;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1232), Color(0xFF2D2440)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDragHandle(),
                _buildHeader(l10n),
                _buildPriceInfoRow(l10n),
                _buildProductsGrid(l10n),
                _buildAgreementText(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.lock_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.unlockToContinue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.episode} ${widget.episodeIndex + 1} · ${widget.dramaTitle}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              widget.onDismiss?.call();
              if (mounted) Navigator.of(context).pop();
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                color: Colors.white.withOpacity(0.7),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInfoRow(AppLocalizations l10n) {
    // UI 展示余额：优先用本地状态，没有则触发懒加载，
    // 但不阻塞 UI（避免选支付方式阶段就立刻请求 userPersonalCenter）。
    if (!_balanceLazyLoaded && _userBalance == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureBalanceLoaded();
      });
    }
    final balance = _userBalance;
    final episodePrice = widget.config.episodeUnlockPrice;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPriceInfoItem(
              icon: Icons.lock_open,
              label: l10n.episodePrice,
              value: '${episodePrice.toInt()} ${l10n.kCoin}',
              valueColor: const Color(0xFFFF6B6B),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: Colors.white.withOpacity(0.12),
          ),
          Expanded(
            child: _buildPriceInfoItem(
              icon: Icons.account_balance_wallet,
              label: l10n.accountBalance,
              value: '$balance ${l10n.kCoin}',
              valueColor: balance >= episodePrice
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFFFA940),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.5)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProductsGrid(AppLocalizations l10n) {
    final allProducts = widget.config.allProducts;

    if (allProducts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
          child: Text(
            l10n.noProductsAvailable,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    final crossAxisCount = allProducts.length == 1 ? 1 : 2;
    final childAspectRatio = crossAxisCount == 1 ? 3.0 : 1.85;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: allProducts.length,
        itemBuilder: (context, index) {
          final product = allProducts[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  Widget _buildProductCard(UnlockProduct product) {
    final l10n = AppLocalizations.of(context);
    final price = product.price;
    final originalPrice = product.originalPrice;
    final hasDiscount = originalPrice != null && originalPrice > price;
    final isProcessing = _isProcessingProduct(product.goodsId);

    String? tagLabel;
    Color tagColor;
    if (hasDiscount) {
      tagLabel = l10n.limitedOffer;
      tagColor = const Color(0xFFFF6B6B);
    } else if (product.isBestValue) {
      tagLabel = l10n.bestValue;
      tagColor = const Color(0xFF8B5CF6);
    } else if (product.isPopular) {
      tagLabel = l10n.hot;
      tagColor = const Color(0xFFFFA940);
    } else {
      tagLabel = null;
      tagColor = Colors.transparent;
    }

    return GestureDetector(
      onTap: isProcessing ? null : () => _handleProductTap(product),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isProcessing ? 0.55 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.12),
                Colors.white.withOpacity(0.06),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(tagLabel != null ? 0.3 : 0.15),
              width: tagLabel != null ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (product.goodsName.isNotEmpty) ...[
                      Text(
                        product.goodsName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            l10n.kCoin,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 4),
                      Text(
                        '\$${originalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    if (tagLabel != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tagColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: tagColor.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          tagLabel,
                          style: TextStyle(
                            color: tagColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isProcessing)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementText() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chargingAgreement,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.chargingRule1,
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 10,
              height: 1.6,
            ),
          ),
          Text(
            l10n.chargingRule2,
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 10,
              height: 1.6,
            ),
          ),
          Text(
            l10n.chargingRule3,
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 10,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleProductTap(UnlockProduct product) async {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      Navigator.of(context).pop(UnlockResult.loginRequired());
      return;
    }

    // 懒加载余额：只在需要判断余额是否足够时才请求（余额支付通道被点击）
    await _ensureBalanceLoaded();
    final balance = _userBalance;

    if (product.type == UnlockProductType.vip) {
      await _handleVipPurchase(product);
      return;
    }

    if (product.type == UnlockProductType.coinRecharge) {
      await _confirmCoinRecharge(product);
      return;
    }

    // Direct episode purchases use the cash price from the API and must not
    // be compared with the user's K-Coin balance.
    if (product.type == UnlockProductType.episode ||
        product.type == UnlockProductType.season) {
      final confirmed = await _confirmPurchase(product);
      if (confirmed != true) return;
      await _confirmAndUnlockByPurchase(
        product,
        showBalanceDialog: false,
      );
      return;
    }

    if (balance >= product.price) {
      await _confirmAndUnlockByBalance(product);
    } else {
      await _confirmAndUnlockByPurchase(product);
    }
  }

  /// 通用"确认购买"提示框：用于不依赖余额判断的商品（整剧解锁等）。
  Future<bool?> _confirmPurchase(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmPurchase),
        content: Text(product.goodsName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.purchase),
          ),
        ],
      ),
    );
  }

  /// Confirm and start payment for a K-coin recharge package.
  Future<void> _confirmCoinRecharge(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmPurchase),
        content: Text(product.goodsName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.purchase),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _setProcessing(product.goodsId, true);
    try {
      final rechargeProduct = product.toRechargeProduct();
      // iOS / Google 渠道包直接走商店内购，不弹 HaiPay 选择器。
      if (shouldUseStoreDirectly()) {
        final handler = ref.read(rechargePurchaseHandlerProvider);
        final success = await handler.purchase(rechargeProduct);
        if (!mounted) return;
        _setProcessing(product.goodsId, false);
        if (success) {
          await _unlockCurrentEpisodeAfterRecharge(product.goodsId);
        } else {
          // 【用户可读的错误提示】商品查不到时 handler 会带出内部错误码
          // （如 play-item-not-found / ios-item-not-found），直接弹出来
          // 用户完全看不懂。统一映射成「商品暂不可用」；
          // 其余错误码照原样显示（排障时仍能看到细节）。
          final err = handler.lastError ?? '';
          final friendly =
              err.contains('not-found') ||
                  err.contains('item-unavailable') ||
                  err.contains('unavailable')
              ? l10n.productUnavailable
              : (err.isNotEmpty ? err : l10n.purchaseFailed);
          AppSnackBar.show(context, message: friendly);
        }
        return;
      }

      final handler = ref.read(unifiedPaymentHandlerProvider);
      final price = product.price.toStringAsFixed(2);
      final haiPayMethods = await handler.fetchHaiPayMethods(
        price: price,
        productName: product.goodsName,
      );
      if (!mounted) return;

      final channel = await PaymentChannelSelector.show(
        context: context,
        price: price,
        productName: product.goodsName,
        haiPayMethods: haiPayMethods,
      );
      if (channel == null || !mounted) return;

      if (channel.isGooglePlay) {
        final rechargeHandler = ref.read(rechargePurchaseHandlerProvider);
        final success = await rechargeHandler.purchase(rechargeProduct);
        if (success) {
          await _unlockCurrentEpisodeAfterRecharge(product.goodsId);
        } else if (mounted) {
          AppSnackBar.show(
            context,
            message: rechargeHandler.lastError ?? l10n.purchaseFailed,
          );
        }
      } else {
        await handler.purchaseRecharge(
          product: rechargeProduct,
          price: price,
          context: context,
          channel: channel,
          onPaymentComplete: (paid) {
            if (paid) {
              _unlockCurrentEpisodeAfterRecharge(product.goodsId);
            }
          },
        );
      }
    } finally {
      if (mounted) {
        _setProcessing(product.goodsId, false);
      }
    }
  }

  /// After a recharge, immediately spend the new balance on the episode that
  /// opened this sheet.
  Future<void> _unlockCurrentEpisodeAfterRecharge(int rechargeGoodsId) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final balanceNotifier = ref.read(coinBalanceInfoProvider.notifier);
    final episodePrice = widget.config.episodeUnlockPrice;
    var balance = 0;
    var lastBalance = 0;
    var balanceArrived = false;
    // 海派支付/Google Play 充值到账通常是异步的,后端可能需要数秒。
    // 我们轮询余额,只要余额有增长就视为到账(避免误报"余额不足")。
    for (var attempt = 0; attempt < 10; attempt++) {
      await balanceNotifier.load();
      if (!mounted) return;
      balance = ref.read(coinBalanceInfoProvider).balance;
      if (balance > lastBalance) {
        lastBalance = balance;
        balanceArrived = true;
        if (balance >= episodePrice) break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    if (!mounted) return;
    if (balance < episodePrice) {
      _setProcessing(rechargeGoodsId, false);
      if (balanceArrived) {
        // 到账了但还不到解锁价——通常不该发生(单集价 < 单包金币价)
        AppSnackBar.show(context, message: l10n.insufficientBalance);
      } else {
        // 充值扣款成功,但后端异步到账可能延迟,告诉用户稍后重试
        AppSnackBar.show(context, message: l10n.rechargeProcessing);
      }
      return;
    }

    final apiService = ApiService(
      dioClient: ref.read(dioClientProvider),
      storage: ref.read(storageServiceProvider),
    );
    final response = await apiService.getUserPayEpisodes(
      videoId: widget.videoId,
      episodesId: widget.episodeId,
      episodesNum: widget.episodesNum,
    );
    if (!mounted) return;

    _setProcessing(rechargeGoodsId, false);
    if (response.isSuccess) {
      await balanceNotifier.load();
      if (!mounted) return;
      widget.onUnlockSuccess.call(widget.episodeIndex);
      AppSnackBar.show(context, message: l10n.unlockSuccess);
      Navigator.of(
        context,
      ).pop(UnlockResult.success(episodeIndex: widget.episodeIndex));
    } else {
      AppSnackBar.show(context, message: response.error ?? l10n.unlockFailed);
    }
  }

  /// 余额足够，直接扣余额解锁
  Future<void> _confirmAndUnlockByBalance(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmUnlock),
        content: Text(
          l10n.confirmUnlockMessage(product.price.toInt(), product.goodsName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.confirm,
              style: const TextStyle(color: Color(0xFF5D4391)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _performUnlockByBalance(product);
  }

  /// 余额不足时可先提示，再弹出支付渠道。
  Future<void> _confirmAndUnlockByPurchase(
    UnlockProduct product, {
    bool showBalanceDialog = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (showBalanceDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.insufficientBalance),
          content: Text(l10n.insufficientBalanceMessage(product.goodsName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                l10n.buy,
                style: const TextStyle(color: Color(0xFF5D4391)),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // iOS / Google 渠道包直接走商店内购（iOS 上是 StoreKit 链路），
    // 不弹渠道选择器 —— 虚拟商品绕开苹果支付有 3.1.1 拒审风险。
    if (shouldUseStoreDirectly()) {
      await _performUnlockByGooglePlay(product);
      return;
    }

    final handler = ref.read(unifiedPaymentHandlerProvider);
    final price = product.price.toStringAsFixed(2);
    final haiPayMethods = await handler.fetchHaiPayMethods(
      price: price,
      productName: product.goodsName,
    );

    final channel = await PaymentChannelSelector.show(
      context: context,
      price: price,
      productName: product.goodsName,
      haiPayMethods: haiPayMethods,
    );

    if (channel == null) return;

    if (channel.isGooglePlay) {
      await _performUnlockByGooglePlay(product);
    } else {
      await _performUnlockByHaiPay(product, channel);
    }
  }

  /// 扣余额解锁
  Future<void> _performUnlockByBalance(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );

      bool success = false;
      ApiResponse? resp;

      if (product.type == UnlockProductType.episode) {
        resp = await apiService.getUserPayEpisodes(
          videoId: widget.videoId,
          episodesId: widget.episodeId,
          episodesNum: widget.episodesNum,
          goodsId: product.goodsId,
        );
        success = resp.isSuccess;
      } else if (product.type == UnlockProductType.season) {
        resp = await apiService.userRechange(
          // 【按平台传 payType】5=Android(Google Play)，6=iOS(App Store)。
          // 之前写死 5，iOS 建出来的订单会被记成 Google 渠道。
          payType: defaultTargetPlatform == TargetPlatform.iOS ? 6 : 5,
          payConfigId: product.goodsId,
          videoId: widget.videoId,
        );
        success = resp.isSuccess;
      }

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (success) {
        final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
        coinNotifier.deductCoins(product.price.toInt());
        await coinNotifier.load();

        AppSnackBar.show(context, message: l10n.unlockSuccess);
        Navigator.of(context).pop(
          UnlockResult.success(
            episodeIndex: widget.episodeIndex,
            wholeDrama: product.type == UnlockProductType.season,
          ),
        );
      } else {
        AppSnackBar.show(context, message: resp?.error ?? l10n.unlockFailed);
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.unlockFailed}: $e');
      }
    }
  }

  /// 通过 Google Play 购买解锁
  ///
  /// 单集/整剧解锁是一次性权益，必须走 [PaymentService.purchaseConsumable]
  /// （buyConsumable + autoConsume）。之前用 `purchase()`（buyNonConsumable）
  /// 会让 Play 把该商品标记为 owned：第一次买完不 consume，之后每次再买
  /// 都报 itemAlreadyOwned（"已拥有此内容"），解锁接口永远不会被调用。
  Future<void> _performUnlockByGooglePlay(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final paymentService = PaymentService.instance;
      // 【按平台取商品 ID】iOS 取 iosProductId（后台没配则兜底 Google ID），
      // Android 取 googlePlayId。之前写死 Google ID，iOS 上永远查不到商品。
      final platformProductId = product.getProductId(defaultTargetPlatform);
      final products = await paymentService.getProducts(
        productIds: [platformProductId],
      );

      if (products.isEmpty) {
        if (mounted) {
          _setProcessing(product.goodsId, false);
          AppSnackBar.show(context, message: l10n.productUnavailable);
        }
        return;
      }

      debugPrint(
        '[Unlock] store purchase start: goodsId=${product.goodsId} '
        'productId=$platformProductId type=${product.type}',
      );

      // 【先建单】后端回调（iOS /notice/apple、Android /notice/google）
      // 需要 orderNo 来关联这笔支付。
      // 【必须带 videoId】解锁订单里如果没有 videoId，后端订单记录的
      // videoId 是 0，回调按 orderNo 反查订单时拿不到剧集信息，
      // 整剧解锁就不知道要解锁哪部剧。
      // createOrder 不支持 videoId，这里直接调 userRechange（它支持）。
      // 建单失败不阻塞支付，回调里会缺 orderNo。
      String? orderNo;
      try {
        final apiService = ApiService(
          dioClient: ref.read(dioClientProvider),
          storage: ref.read(storageServiceProvider),
        );
        final resp = await apiService.userRechange(
          // 5 = Android(Google Play)，6 = iOS(App Store)
          payType: defaultTargetPlatform == TargetPlatform.iOS ? 6 : 5,
          payConfigId: product.goodsId,
          videoId: widget.videoId,
        );
        if (resp.isSuccess && resp.data is Map) {
          final data = Map<String, dynamic>.from(resp.data as Map);
          final nested = data['data'] is Map
              ? Map<String, dynamic>.from(data['data'] as Map)
              : const <String, dynamic>{};
          final rawOrderNo =
              data['orderNo'] ?? nested['orderNo'] ?? data['orderId'] ?? nested['orderId'];
          orderNo = rawOrderNo?.toString();
        }
        debugPrint(
          '[Unlock] Unlock order created: ok=${resp.isSuccess} '
          'orderNo=$orderNo goodsId=${product.goodsId} videoId=${widget.videoId}',
        );
      } catch (e) {
        debugPrint('[Unlock] Create unlock order failed: $e');
      }

      // onComplete 在 purchaseStream 投递真实购买结果时被调用，
      // 用它把 PurchaseDetails（含 purchaseToken）带出来发后端回调。
      PurchaseDetails? completedPurchase;
      final paid = await paymentService.purchaseConsumable(
        product: products.first,
        applicationUserName:
            await ref.read(storageServiceProvider).getUserIdAsync(),
        onComplete: (purchase) => completedPurchase = purchase,
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (!paid) {
        final err = paymentService.lastError ?? '';
        debugPrint(
          '[Unlock] Google Play purchase failed: err=$err '
          'goodsId=${product.goodsId}',
        );
        // itemAlreadyOwned 说明用户之前已经为这个商品付过钱（旧版本把
        // 一次性商品买成了非消耗型，Play 账户里还留着）。消耗掉旧购买
        // 并直接补发解锁接口，让用户不用再付一次钱。
        if (err.contains('itemAlreadyOwned') || err.contains('ITEM_ALREADY_OWNED')) {
          debugPrint(
            '[Unlock] itemAlreadyOwned detected — recovering previous purchase '
            'and calling unlock API directly (goodsId=${product.goodsId})',
          );
          await _recoverAlreadyOwnedUnlock(product);
          return;
        }
        AppSnackBar.show(
          context,
          message: err.isNotEmpty ? err : l10n.purchaseFailed,
        );
        return;
      }

      debugPrint(
        '[Unlock] Google Play payment confirmed: goodsId=${product.goodsId} '
        '→ sending google callback then calling unlock API',
      );
      await _callUnlockApiAfterGooglePlayPayment(
        product,
        purchase: completedPurchase,
        orderNo: orderNo,
      );
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.purchaseFailed}: $e');
      }
    }
  }

  /// 用户此前已经付过钱（Play 里该商品是 owned 状态）：
  /// 查到旧购买后 consume 掉，然后直接补发解锁接口。
  Future<void> _recoverAlreadyOwnedUnlock(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final paymentService = PaymentService.instance;
      final past = await paymentService.queryExistingPurchases(forceRefresh: true);
      final playId = product.googlePlayId ?? '';
      PurchaseDetails? ownedPurchase;
      for (final p in past) {
        if (p.productID == playId &&
            (p.status == PurchaseStatus.purchased ||
                p.status == PurchaseStatus.restored)) {
          ownedPurchase = p;
          break;
        }
      }

      if (ownedPurchase != null) {
        debugPrint(
          '[Unlock] Consuming previously owned purchase: ${ownedPurchase.productID}',
        );
        await paymentService.consumePurchase(ownedPurchase);
        if (!mounted) return;
        _setProcessing(product.goodsId, false);
        await _callUnlockApiAfterGooglePlayPayment(
          product,
          purchase: ownedPurchase,
        );
        return;
      }

      debugPrint(
        '[Unlock] itemAlreadyOwned but no matching past purchase found '
        '(playId=$playId) — cannot auto-recover',
      );
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: l10n.purchaseFailed);
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.purchaseFailed}: $e');
      }
    }
  }

  /// Play 侧支付已确认（或旧购买已消耗）：先给后端发 /notice/google 回调，
  /// 再调用解锁接口完成解锁。
  ///
  /// 【为什么要发回调】之前单集解锁的 Google 流程从来没有给后端发过
  /// /notice/google，后端看不到这笔 Play 收入。参数结构和 K币 充值链路
  /// （recharge_provider._handlePurchaseSuccess）保持一致，
  /// payConfigType=3 表示单集/整剧解锁（对齐 HaiPay 的 productType '3'）。
  ///
  /// 解锁接口失败也不能当普通失败处理 —— 存入待重试队列，
  /// 下次启动/重试时补发，避免「钱付了集没解锁」。
  Future<void> _callUnlockApiAfterGooglePlayPayment(
    UnlockProduct product, {
    PurchaseDetails? purchase,
    String? orderNo,
  }) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      // 1. 发谷歌支付回调（先存后发 + 3 次指数退避，弱网不丢单）
      if (purchase != null) {
        await _sendGoogleUnlockCallback(
          product: product,
          purchase: purchase,
          orderNo: orderNo,
        );
      }

      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );

      ApiResponse? resp;
      if (product.type == UnlockProductType.episode) {
        resp = await apiService.getUserPayEpisodes(
          videoId: widget.videoId,
          episodesId: widget.episodeId,
          episodesNum: widget.episodesNum,
          goodsId: product.goodsId,
        );
      } else if (product.type == UnlockProductType.season) {
        resp = await apiService.userRechange(
          payType: 5,
          payConfigId: product.goodsId,
          videoId: widget.videoId,
        );
      }

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      final ok = resp?.isSuccess ?? false;
      debugPrint(
        '[Unlock] Unlock API result: ok=$ok '
        'code=${resp?.code} error=${resp?.error} goodsId=${product.goodsId}',
      );

      final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
      await coinNotifier.load();

      if (ok) {
        AppSnackBar.show(context, message: l10n.unlockSuccess);
        // 整剧解锁：带上 wholeDrama 标记，让调用方刷新整部剧的集数状态。
        Navigator.of(context).pop(
          UnlockResult.success(
            episodeIndex: widget.episodeIndex,
            wholeDrama: product.type == UnlockProductType.season,
          ),
        );
      } else {
        // 已付款但解锁接口失败 —— 存待重试，避免用户重复付钱。
        await ref.read(storageServiceProvider).savePendingPayment({
          'orderId': 'goods-${product.goodsId}',
          'type': 'unlockEpisode',
          'goodsId': product.goodsId,
          'videoId': widget.videoId,
          'episodesId': widget.episodeId,
          'episodesNum': widget.episodesNum,
        });
        AppSnackBar.show(
          context,
          message: resp?.error ?? l10n.unlockFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.unlockFailed}: $e');
      }
    }
  }

  /// 给后端补发谷歌支付回调（POST /notice/google）。
  ///
  /// 【先存后发】发送前先把回调参数落盘（同 orderId 去重），成功后再出队。
  /// App 在发送过程中被杀/断网，下次启动或进会员页时
  /// checkAndRetryPendingPayments 看到这条记录（含 purchaseToken）
  /// 会自动补发 /notice/google。
  Future<void> _sendGoogleUnlockCallback({
    required UnlockProduct product,
    required PurchaseDetails purchase,
    String? orderNo,
  }) async {
    final storage = ref.read(storageServiceProvider);
    final callbackOrderId =
        orderNo ?? 'google-${purchase.purchaseID ?? product.goodsId}';

    final callbackPayload = <String, dynamic>{
      // 后端订单字段名是 orderNo（/api/pay/userRechange 返回 orderNo），
      // 两个都带上，兼容后端两种读法。
      'orderNo': orderNo,
      'orderId': callbackOrderId,
      'productId': purchase.productID,
      'purchaseId': purchase.purchaseID,
      'transactionDate': purchase.transactionDate,
      'status': purchase.status.name,
      'payConfigType': 2, // 2 = 单集/整剧解锁（后端订单返回 payConfigType=2）
      'goodsId': product.goodsId,
      'videoId': widget.videoId,
      'episodesId': widget.episodeId,
      'episodesNum': widget.episodesNum,
      'purchaseToken': purchase.verificationData.serverVerificationData,
      'verificationData': {
        'localVerificationData':
            purchase.verificationData.localVerificationData,
        'serverVerificationData':
            purchase.verificationData.serverVerificationData,
        'source': purchase.verificationData.source,
      },
    };

    await storage.savePendingPayment(callbackPayload);
    debugPrint('[Unlock] Google callback payload: $callbackPayload');

    var confirmed = false;
    for (var retry = 0; retry < 3 && !confirmed; retry++) {
      if (retry > 0) {
        await Future<void>.delayed(Duration(seconds: 2 << (retry - 1)));
      }
      try {
        // 【按平台路由回调】iOS → /notice/apple，Android → /notice/google。
        confirmed = await payServiceProvider.confirmStorePurchase(
          params: callbackPayload,
        );
      } catch (e) {
        debugPrint(
          '[Unlock] store callback failed (attempt ${retry + 1}): $e',
        );
      }
    }

    if (confirmed) {
      await storage.removePendingPayment(callbackOrderId);
    }
    debugPrint(
      '[Unlock] Google callback confirmed=$confirmed '
      'product=${purchase.productID} orderNo=$orderNo goodsId=${product.goodsId}',
    );
  }

  /// 通过 HaiPay H5 购买解锁
  Future<void> _performUnlockByHaiPay(
    UnlockProduct product,
    PaymentChannel channel,
  ) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final handler = ref.read(unifiedPaymentHandlerProvider);
      final opened = await handler.unlockEpisode(
        product: product,
        price: product.price.toStringAsFixed(2),
        context: context,
        videoId: widget.videoId,
        episodeId: widget.episodeId,
        episodesNum: widget.episodesNum,
        channel: channel,
        onPaymentComplete: (paid) {
          if (paid) {
            widget.onUnlockSuccess.call(widget.episodeIndex);
            AppSnackBar.show(context, message: l10n.purchaseSuccessful);
            // Close the unlock sheet immediately so the caller can trigger
            // automatic playback now that the payment is confirmed.
            // 整剧解锁：带上 wholeDrama 标记，让调用方刷新整部剧的集数状态。
            Navigator.of(context).pop(
              UnlockResult.success(
                episodeIndex: widget.episodeIndex,
                wholeDrama: product.type == UnlockProductType.season,
              ),
            );
          }
        },
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      // pop 已在 onPaymentComplete 内触发；这里只负责错误提示。
      if (!opened) {
        AppSnackBar.show(
          context,
          message: handler.lastError ?? l10n.purchaseFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.purchaseFailed}: $e');
      }
    }
  }

  /// VIP商品 → 弹出渠道选择（Google Play 或 HaiPay）
  Future<void> _handleVipPurchase(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      // iOS / Google 渠道包直接走商店内购（iOS 上是 StoreKit 链路），
      // 不弹渠道选择器。
      if (shouldUseStoreDirectly()) {
        await _performVipByGooglePlay(product);
        return;
      }

      final handler = ref.read(unifiedPaymentHandlerProvider);
      final price = product.price.toStringAsFixed(2);
      final haiPayMethods = await handler.fetchHaiPayMethods(
        price: price,
        productName: product.goodsName,
      );

      final channel = await PaymentChannelSelector.show(
        context: context,
        price: price,
        productName: product.goodsName,
        haiPayMethods: haiPayMethods,
      );

      if (channel == null) {
        _setProcessing(product.goodsId, false);
        return;
      }

      if (channel.isGooglePlay) {
        await _performVipByGooglePlay(product);
      } else {
        await _performVipByHaiPay(product, channel);
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.vipSubscriptionFailed}: $e');
      }
    }
  }

  /// VIP 订阅购买 - Google Play
  Future<void> _performVipByGooglePlay(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);

    try {
      final paymentService = PaymentService.instance;

      // 先查商店商品（按平台取 ID），再建订单。
      // 商品根本不存在的时候没必要建订单，否则会留下一条永远不会被支付的订单。
      final products = await paymentService.getProducts(
        productIds: [product.getProductId(defaultTargetPlatform)],
        requireSubscriptionOnAndroid: true,
      );

      if (products.isEmpty) {
        debugPrint(
          '[Unlock] No store product for "${product.getProductId(defaultTargetPlatform)}" '
          '(goodsId=${product.goodsId}) — skipping order creation',
        );
        if (mounted) {
          _setProcessing(product.goodsId, false);
          AppSnackBar.show(context, message: l10n.vipProductUnavailable);
        }
        return;
      }

      final payService = payServiceProvider;
      final userId = await ref.read(storageServiceProvider).getUserIdAsync();

      // 与会员页一致的流程：匹配成功直接拉起支付，
      // 订单等支付确认后再建（POST /api/pay/userRechange），
      // 之后验证 / acknowledge / 开通会员全部由后端完成。
      // 【不要】在拉起支付之前建订单 —— 商品买不了会留下孤儿订单。
      final success = await paymentService.purchase(
        product: products.first,
        applicationUserName: userId,
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (success) {
        // 支付已确认 → 通知后端建单核销
        bool orderCreated = false;
        try {
          final order = await payService.createOrder(
            payConfigId: product.goodsId,
          );
          orderCreated = order != null;
        } catch (e) {
          debugPrint('[Unlock] Create VIP order after payment failed: $e');
        }

        if (!orderCreated) {
          // 钱已付，不能当失败处理；存入待重试队列，下次启动/进会员页补发
          await ref.read(storageServiceProvider).savePendingPayment({
            'orderId': 'goods-${product.goodsId}',
            'type': 'createOrder',
            'goodsId': product.goodsId,
          });
        }

        final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
        await coinNotifier.load();

        AppSnackBar.show(context, message: l10n.vipSubscriptionSuccess);
        Navigator.of(
          context,
        ).pop(UnlockResult.vip());
      } else {
        AppSnackBar.show(
          context,
          message: paymentService.lastError ?? l10n.vipSubscriptionFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.vipSubscriptionFailed}: $e');
      }
    }
  }

  /// VIP 订阅购买 - HaiPay
  Future<void> _performVipByHaiPay(
    UnlockProduct product,
    PaymentChannel channel,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      final handler = ref.read(unifiedPaymentHandlerProvider);
      final subProduct = SubscriptionProduct(
        id: 'vip_haipay_${product.goodsId}',
        type: SubscriptionPeriod.monthly,
        googlePlayId: '',
        appStoreId: '',
        price: product.price.toStringAsFixed(2),
        priceCn: product.price.toStringAsFixed(2),
        originalPrice: '',
        originalPriceCn: '',
        benefits: const [],
        displayName: product.goodsName,
        goodsId: product.goodsId,
      );
      // success=true here means the WebView already closed and the user
      // completed payment. By the time we reach this point the WebView is
      // no longer in the navigation stack, so it is safe to pop the
      // unlock sheet.
      final opened = await handler.purchaseVip(
        product: subProduct,
        price: product.price.toStringAsFixed(2),
        context: context,
        channel: channel,
        onPaymentComplete: (paid) {
          if (paid) {
            widget.onVipPurchaseSuccess?.call();
          }
        },
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (opened) {
        AppSnackBar.show(context, message: l10n.vipSubscriptionSuccess);
        Navigator.of(context).pop(UnlockResult.vip());
      } else {
        AppSnackBar.show(
          context,
          message: handler.lastError ?? l10n.vipSubscriptionFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.vipSubscriptionFailed}: $e');
      }
    }
  }
}
