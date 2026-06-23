import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/unlock_product.dart';
import '../providers/coin_record_provider.dart';
import '../services/payment_service.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/service/pay_service.dart';

/// 解锁剧集弹窗组件
/// 显示当前K币余额、解锁当前集需要的K币
/// 包含整剧解锁商品、VIP商品列表
/// 根据余额和商品类型执行不同的解锁/购买逻辑
class UnlockBottomSheet extends ConsumerStatefulWidget {
  const UnlockBottomSheet({
    super.key,
    required this.videoId,
    required this.episodeId,
    required this.episodeIndex,
    required this.dramaTitle,
    this.coverUrl,
    required this.config,
    required this.onUnlockSuccess,
    this.onDismiss,
  });

  final String videoId;
  final String episodeId;
  final int episodeIndex;
  final String dramaTitle;
  final String? coverUrl;
  final UnlockConfig config;
  final void Function(int episodeIndex) onUnlockSuccess;
  final VoidCallback? onDismiss;

  static Future<UnlockResult?> show({
    required BuildContext context,
    required String videoId,
    required String episodeId,
    required int episodeIndex,
    required String dramaTitle,
    String? coverUrl,
    required UnlockConfig config,
    required void Function(int episodeIndex) onUnlockSuccess,
    VoidCallback? onDismiss,
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
        episodeIndex: episodeIndex,
        dramaTitle: dramaTitle,
        coverUrl: coverUrl,
        config: config,
        onUnlockSuccess: onUnlockSuccess,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  ConsumerState<UnlockBottomSheet> createState() => _UnlockBottomSheetState();
}

class _UnlockBottomSheetState extends ConsumerState<UnlockBottomSheet> {
  /// 正在处理的商品ID集合，支持同时处理多个商品
  final Set<int> _processingProductIds = {};

  bool _isProcessingProduct(int goodsId) => _processingProductIds.contains(goodsId);

  void _setProcessing(int goodsId, bool processing) {
    setState(() {
      if (processing) {
        _processingProductIds.add(goodsId);
      } else {
        _processingProductIds.remove(goodsId);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // 从API加载K币余额
    Future.microtask(() {
      ref.read(coinBalanceInfoProvider.notifier).load();
    });
  }

  int get _userBalance => ref.watch(coinBalanceInfoProvider).balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.padding.bottom + 16;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF5F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopDecoration(),
              _buildTitleSection(l10n),
              _buildPriceInfoRow(l10n),
              _buildProductsGrid(l10n),
              _buildAgreementText(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopDecoration() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          height: 30,
          decoration: const BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        Positioned(
          left: 20,
          top: -10,
          child: Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD700),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 0,
          child: GestureDetector(
            onTap: () {
              widget.onDismiss?.call();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Color(0xFF666666),
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleSection(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 50, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 60, top: 4),
            child: Text(
              l10n.unlockToContinue,
              style: const TextStyle(
                color: Color(0xFFD9341C),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Text(
              'Episode ${widget.episodeIndex + 1} - ${widget.dramaTitle}',
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInfoRow(AppLocalizations l10n) {
    final balance = _userBalance;
    final episodePrice = widget.config.episodeUnlockPrice;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.episodePrice,
            style: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 12,
            ),
          ),
          Text(
            '${episodePrice.toInt()} K Coin',
            style: const TextStyle(
              color: Color(0xFFD9341C),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.accountBalance,
            style: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 12,
            ),
          ),
          Text(
            '$balance K Coin',
            style: TextStyle(
              color: balance >= episodePrice
                  ? const Color(0xFFD9341C)
                  : const Color(0xFFE34D27),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid(AppLocalizations l10n) {
    // 直接使用所有返回的商品，不按类型过滤
    final allProducts = widget.config.allProducts;
    debugPrint('[UnlockBottomSheet] allProducts length: ${allProducts.length}');
    debugPrint('[UnlockBottomSheet] allProducts: $allProducts');

    if (allProducts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          l10n.noProductsAvailable,
          style: const TextStyle(color: Colors.black54, fontSize: 14),
        ),
      );
    }

    // 根据商品数量决定布局：2列或3列
    final crossAxisCount = allProducts.length <= 4 ? 2 : 3;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: crossAxisCount == 2 ? 1.6 : 1.4,
        ),
        itemCount: allProducts.length,
        itemBuilder: (context, index) {
          final product = allProducts[index];
          return _buildProductItem(product);
        },
      ),
    );
  }

  Widget _buildProductItem(UnlockProduct product) {
    final l10n = AppLocalizations.of(context);
    final price = product.price;
    final originalPrice = product.originalPrice;
    final hasDiscount = originalPrice != null && originalPrice > price;

    // 价格显示：如果价格是整数（如100.00），显示为整数
    final priceInt = price.toInt();
    final mainLabel = price - priceInt == 0 ? '¥$priceInt' : '¥${price.toStringAsFixed(2)}';
    final subLabel = product.goodsName.isNotEmpty ? product.goodsName : '';

    String? tagLabel;
    if (hasDiscount) {
      tagLabel = l10n.limitedOffer;
    } else if (product.isBestValue) {
      tagLabel = l10n.bestValue;
    } else if (product.isPopular) {
      tagLabel = l10n.hot;
    }

    return GestureDetector(
      onTap: _isProcessingProduct(product.goodsId) ? null : () => _handleProductTap(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: tagLabel != null
                ? const Color(0xFFD9341C)
                : const Color(0xFFE0E0E0),
            width: tagLabel != null ? 1.2 : 0.8,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (subLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        subLabel,
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        mainLabel,
                        style: const TextStyle(
                          color: Color(0xFFD9341C),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 4),
                        Text(
                          '¥${originalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (tagLabel != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD9341C),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(5),
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Text(
                    tagLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (_isProcessingProduct(product.goodsId))
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFD9341C),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreementText() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chargingAgreement,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.chargingRule1,
            style: const TextStyle(
              color: Color(0xFF999999),
              fontSize: 10,
            ),
          ),
          Text(
            l10n.chargingRule2,
            style: const TextStyle(
              color: Color(0xFF999999),
              fontSize: 10,
            ),
          ),
          Text(
            l10n.chargingRule3,
            style: const TextStyle(
              color: Color(0xFF999999),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleProductTap(UnlockProduct product) async {
    // 检查是否是游客，游客需要登录后才能支付
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      // 游客不能支付，关闭弹窗返回需要登录
      Navigator.of(context).pop(UnlockResult.loginRequired());
      return;
    }

    final balance = _userBalance;

    // VIP商品 → 走订阅购买
    if (product.type == UnlockProductType.vip) {
      await _handleVipPurchase(product);
      return;
    }

    // 单集/整剧解锁：余额足够 → 扣余额解锁
    if (balance >= product.price) {
      await _confirmAndUnlockByBalance(product);
    } else {
      // 余额不足 → 走一次性购买（Google Play）
      await _confirmAndUnlockByPurchase(product);
    }
  }

  /// 余额足够，直接扣余额解锁
  Future<void> _confirmAndUnlockByBalance(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmUnlock),
        content: Text(l10n.confirmUnlockMessage(product.price.toInt(), product.goodsName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.confirm,
              style: const TextStyle(color: Color(0xFFD9341C)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _performUnlockByBalance(product);
  }

  /// 余额不足，走Google Play一次性购买
  Future<void> _confirmAndUnlockByPurchase(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
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
              style: const TextStyle(color: Color(0xFFD9341C)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _performUnlockByPurchase(product);
  }

  /// 扣余额解锁
  Future<void> _performUnlockByBalance(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
      coinNotifier.deductCoins(product.price.toInt());

      // 调用后端API解锁剧集
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );
      final resp = await apiService.getUserPayEpisodes(
        videoId: widget.videoId,
        episodesId: widget.episodeId,
        goodsId: product.goodsId,
      );

      if (mounted) {
        _setProcessing(product.goodsId, false);

        if (resp.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.unlockSuccess),
              backgroundColor: const Color(0xFFD9341C),
            ),
          );
          Navigator.of(context).pop(UnlockResult.success(
            episodeIndex: widget.episodeIndex,
          ));
        } else {
          // 解锁失败，退款
          coinNotifier.addCoins(product.price.toInt());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(resp.error ?? l10n.unlockFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.unlockFailed}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 通过Google Play购买解锁
  Future<void> _performUnlockByPurchase(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final paymentService = PaymentService.instance;

      // 获取Google Play商品信息
      final products = await paymentService.getProducts(
        productIds: [product.googlePlayId ?? ''],
      );

      if (products.isEmpty) {
        if (mounted) {
          _setProcessing(product.goodsId, false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.productUnavailable),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 发起一次性购买
      final success = await paymentService.purchase(product: products.first);

      if (mounted) {
        _setProcessing(product.goodsId, false);

        if (success) {
          // 购买成功后调用后端API解锁剧集
          final apiService = ApiService(
            dioClient: ref.read(dioClientProvider),
            storage: ref.read(storageServiceProvider),
          );
          await apiService.getUserPayEpisodes(
            videoId: widget.videoId,
            episodesId: widget.episodeId,
            goodsId: product.goodsId,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.purchaseSuccess),
              backgroundColor: const Color(0xFFD9341C),
            ),
          );
          Navigator.of(context).pop(UnlockResult.success(
            episodeIndex: widget.episodeIndex,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(paymentService.lastError ?? l10n.purchaseFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.purchaseFailed}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// VIP商品 → 走Google Play订阅购买
  Future<void> _handleVipPurchase(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      // Step 1: 创建后端订单
      final payService = payServiceProvider;

      try {
        await payService.createOrder(payConfigId: product.goodsId);
      } catch (e) {
        debugPrint('[Unlock] Create order failed: $e');
      }

      // Step 2: 查询 Google Play 商品
      final paymentService = PaymentService.instance;
      final products = await paymentService.getProducts(
        productIds: [product.googlePlayId ?? ''],
        requireSubscriptionOnAndroid: true,
      );

      if (products.isEmpty) {
        if (mounted) {
          _setProcessing(product.goodsId, false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.vipProductUnavailable),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Step 3: 发起订阅购买
      final success = await paymentService.purchase(
        product: products.first,
        applicationUserName: ref.read(storageServiceProvider).getString('user_id'),
      );

      if (mounted) {
        _setProcessing(product.goodsId, false);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.vipSubscriptionSuccess),
              backgroundColor: const Color(0xFFD9341C),
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(paymentService.lastError ?? l10n.vipSubscriptionFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.vipSubscriptionFailed}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
