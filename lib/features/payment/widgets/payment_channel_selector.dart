import 'package:flutter/material.dart';
import '../../../core/config/build_flavor.dart';
import '../models/payment_channel.dart';
import '../models/hai_pay_models.dart';

/// Unified payment channel selector (Google Play + HaiPay sub-methods).
/// Shown as a bottom sheet when user taps "Pay".
/// If [haiPayMethods] is empty, falls back to a single "HaiPay" entry.
class PaymentChannelSelector extends StatelessWidget {
  const PaymentChannelSelector({
    super.key,
    required this.price,
    required this.productName,
    required this.onChannelSelected,
    this.haiPayMethods = const <HaiPayMethod>[],
  });

  final String price;
  final String productName;
  final void Function(PaymentChannel channel) onChannelSelected;
  final List<HaiPayMethod> haiPayMethods;

  /// Returns the effective list of payment channels for the current build.
  ///
  /// - google flavor -> Google Play only.
  /// - platform flavor -> exactly the backend methods, in backend order.
  static List<PaymentChannel> effectiveChannels({
    List<HaiPayMethod> haiPayMethods = const <HaiPayMethod>[],
  }) {
    if (BuildFlavor.isGoogle) {
      return const [PaymentChannel.googlePlay()];
    }

    if (haiPayMethods.isEmpty) {
      return [PaymentChannel.haiPayLegacy()];
    }

    return haiPayMethods
        .map(PaymentChannel.fromHaiPayMethod)
        .toList(growable: false);
  }

  /// Convenience for the google flavor: when the build is the google
  /// flavor there is no channel choice to make and no HaiPay state to
  /// touch, so callers can invoke this helper instead of [show] to skip
  /// the modal *and* the HaiPay methods fetch.
  ///
  /// Returns the single Google Play channel that will be used.
  static PaymentChannel pickGooglePlay() {
    assert(
      BuildFlavor.isGoogle,
      'pickGooglePlay() is only valid for the google flavor',
    );
    return const PaymentChannel.googlePlay();
  }

  static Future<PaymentChannel?> show({
    required BuildContext context,
    required String price,
    required String productName,
    List<HaiPayMethod> haiPayMethods = const <HaiPayMethod>[],
  }) {
    // Fast path: when only a single channel is available for this build
    // (e.g. the Google flavor, where HaiPay is disabled), skip the modal
    // and return that channel directly. The caller proceeds straight to
    // the Google Play billing flow — matching the pre-flavor behaviour.
    //
    // For the google flavor callers should use [pickGooglePlay] directly
    // so the HaiPay methods fetch is also skipped.
    if (BuildFlavor.isGoogle) {
      return Future.value(pickGooglePlay());
    }

    final channels = effectiveChannels(haiPayMethods: haiPayMethods);
    if (channels.length == 1) {
      return Future.value(channels.first);
    }

    return showModalBottomSheet<PaymentChannel>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(
        maxWidth: double.infinity,
      ),
      builder: (ctx) => PaymentChannelSelector(
        price: price,
        productName: productName,
        haiPayMethods: haiPayMethods,
        onChannelSelected: (channel) => Navigator.of(ctx).pop(channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF2D2440),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              const SizedBox(height: 8),
              _buildChannelList(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.payment, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Payment Method',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              productName,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(BuildContext context) {
    final channels = effectiveChannels(haiPayMethods: haiPayMethods);

    if (channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No payment methods available for this build.',
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < channels.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PaymentChannelItem(
              channel: channels[i],
              onTap: () => onChannelSelected(channels[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentChannelItem extends StatelessWidget {
  const _PaymentChannelItem({required this.channel, required this.onTap});

  final PaymentChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            _buildIcon(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    channel.description,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (channel.isGooglePlay) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Color(0xFF4285F4),
            size: 28,
          ),
        ),
      );
    }

    final method = channel.haiPayMethod;
    if (method != null) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            _iconFor(method.name),
            style: const TextStyle(fontSize: 20),
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(
          Icons.account_balance_wallet,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  String _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('mada')) return '💳';
    if (lower.contains('stc') || lower.contains('stcpay')) return '📱';
    if (lower.contains('credit') ||
        lower.contains('card') ||
        lower.contains('debit')) {
      return '💳';
    }
    if (lower.contains('apple')) return '🍎';
    if (lower.contains('fawry')) return '🛒';
    if (lower.contains('haipay')) return '🌊';
    return '💰';
  }
}
