import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../core/config/build_flavor.dart';
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

  @override
  void initState() {
    super.initState();
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

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        decoration: const BoxDecoration(
          color: Color(0xFF2D2440),
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
        PositionedDirectional(
          start: 20,
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
        PositionedDirectional(
          end: 12,
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
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleSection(AppLocalizations l10n) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        isRtl ? 50 : 16,
        8,
        isRtl ? 16 : 50,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: isRtl ? 0 : 60,
              end: isRtl ? 60 : 0,
              top: 4,
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF8B4513), Color(0xFFD2691E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                l10n.unlockToContinue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: isRtl ? 0 : 60,
              end: isRtl ? 60 : 0,
            ),
            child: Text(
              '${l10n.episode} ${widget.episodeIndex + 1} - ${widget.dramaTitle}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _buildPriceDetail(
            label: l10n.episodePrice,
            value: '${episodePrice.toInt()} ${l10n.kCoin}',
          ),
          _buildPriceDetail(
            label: l10n.accountBalance,
            value: '$balance ${l10n.kCoin}',
          ),
        ],
      ),
    );
  }

  Widget _buildPriceDetail({required String label, required String value}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Color(0xFF333333), fontSize: 12),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildProductsGrid(AppLocalizations l10n) {
    final allProducts = widget.config.allProducts;
    debugPrint('[UnlockBottomSheet] allProducts length: ${allProducts.length}');
    debugPrint('[UnlockBottomSheet] allProducts: $allProducts');

    if (allProducts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          l10n.noProductsAvailable,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    // Keep every product card wide enough for localized names, prices, and tags.
    // Three columns leave too little usable width on compact phones.
    final crossAxisCount = allProducts.length == 1 ? 1 : 2;
    final childAspectRatio = crossAxisCount == 1 ? 3.2 : 1.75;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: childAspectRatio,
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

    final priceInt = price.toInt();
    final mainLabel = price - priceInt == 0
        ? '¥$priceInt'
        : '¥${price.toStringAsFixed(2)}';
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
      onTap: _isProcessingProduct(product.goodsId)
          ? null
          : () => _handleProductTap(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: tagLabel != null
                ? const Color(0xFF5D4391)
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
                          color: Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 4),
                        Text(
                          '¥${originalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.red,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
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
                      color: Color(0xFF5D4391),
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
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.chargingRule1,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          Text(
            l10n.chargingRule2,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          Text(
            l10n.chargingRule3,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
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
      if (BuildFlavor.isGoogle) {
        final handler = ref.read(rechargePurchaseHandlerProvider);
        final success = await handler.purchase(rechargeProduct);
        if (!success && mounted) {
          AppSnackBar.show(
            context,
            message: handler.lastError ?? l10n.purchaseFailed,
          );
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
    for (var attempt = 0; attempt < 5; attempt++) {
      await balanceNotifier.load();
      if (!mounted) return;
      balance = ref.read(coinBalanceInfoProvider).balance;
      if (balance >= episodePrice || attempt == 4) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    if (!mounted) return;
    if (balance < episodePrice) {
      _setProcessing(rechargeGoodsId, false);
      AppSnackBar.show(context, message: l10n.insufficientBalance);
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

    // Google flavor: skip HaiPay entirely — there is only one channel
    // and we go straight to the Google Play billing flow.
    if (BuildFlavor.isGoogle) {
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
          payType: 5,
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
        Navigator.of(
          context,
        ).pop(UnlockResult.success(episodeIndex: widget.episodeIndex));
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
  Future<void> _performUnlockByGooglePlay(UnlockProduct product) async {
    final l10n = AppLocalizations.of(context);
    _setProcessing(product.goodsId, true);

    try {
      final paymentService = PaymentService.instance;
      final products = await paymentService.getProducts(
        productIds: [product.googlePlayId ?? ''],
      );

      if (products.isEmpty) {
        if (mounted) {
          _setProcessing(product.goodsId, false);
          AppSnackBar.show(context, message: l10n.productUnavailable);
        }
        return;
      }

      final success = await paymentService.purchase(product: products.first);

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (success) {
        final apiService = ApiService(
          dioClient: ref.read(dioClientProvider),
          storage: ref.read(storageServiceProvider),
        );

        if (product.type == UnlockProductType.episode) {
          await apiService.getUserPayEpisodes(
            videoId: widget.videoId,
            episodesId: widget.episodeId,
            episodesNum: widget.episodesNum,
            goodsId: product.goodsId,
          );
        } else if (product.type == UnlockProductType.season) {
          await apiService.userRechange(
            payType: 5,
            payConfigId: product.goodsId,
            videoId: widget.videoId,
          );
        }

        final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
        await coinNotifier.load();

        AppSnackBar.show(context, message: l10n.purchaseSuccess);
        Navigator.of(
          context,
        ).pop(UnlockResult.success(episodeIndex: widget.episodeIndex));
      } else {
        AppSnackBar.show(
          context,
          message: paymentService.lastError ?? l10n.purchaseFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        _setProcessing(product.goodsId, false);
        AppSnackBar.show(context, message: '${l10n.purchaseFailed}: $e');
      }
    }
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
      var paymentCompleted = false;
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
            paymentCompleted = true;
            widget.onUnlockSuccess.call(widget.episodeIndex);
            AppSnackBar.show(context, message: l10n.purchaseSuccessful);
          }
        },
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (!opened) {
        AppSnackBar.show(
          context,
          message: handler.lastError ?? l10n.purchaseFailed,
        );
      } else if (paymentCompleted && mounted) {
        Navigator.of(
          context,
        ).pop(UnlockResult.success(episodeIndex: widget.episodeIndex));
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
      // Google flavor: skip HaiPay entirely — there is only one channel
      // and we go straight to the Google Play billing flow.
      if (BuildFlavor.isGoogle) {
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
      final payService = payServiceProvider;
      try {
        await payService.createOrder(payConfigId: product.goodsId);
      } catch (e) {
        debugPrint('[Unlock] Create VIP order failed: $e');
      }

      final paymentService = PaymentService.instance;
      final products = await paymentService.getProducts(
        productIds: [product.googlePlayId ?? ''],
        requireSubscriptionOnAndroid: true,
      );

      if (products.isEmpty) {
        if (mounted) {
          _setProcessing(product.goodsId, false);
          AppSnackBar.show(context, message: l10n.vipProductUnavailable);
        }
        return;
      }

      final success = await paymentService.purchase(
        product: products.first,
        applicationUserName: ref
            .read(storageServiceProvider)
            .getString('user_id'),
      );

      if (!mounted) return;
      _setProcessing(product.goodsId, false);

      if (success) {
        final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
        await coinNotifier.load();

        AppSnackBar.show(context, message: l10n.vipSubscriptionSuccess);
        Navigator.of(context).pop();
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
      // success=true here only means "payment page was opened".
      // The in-app WebView handles its own dismissal; we must NOT pop
      // the calling sheet or it will dismiss the WebView too.
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
        // Keep the sheet open. The WebView is now on top.
        // When the user completes payment, the WebView pops itself
        // and we land back here — caller should refresh state then.
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
