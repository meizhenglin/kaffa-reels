import 'package:flutter/material.dart';
import '../models/payment_channel.dart';

/// Unified payment channel selector (Google Play vs HaiPay)
/// Shown as a bottom sheet when user taps "Pay"
class PaymentChannelSelector extends StatelessWidget {
  const PaymentChannelSelector({
    super.key,
    required this.price,
    required this.productName,
    required this.onChannelSelected,
  });

  final String price;
  final String productName;
  final void Function(PaymentChannel channel) onChannelSelected;

  static Future<PaymentChannel?> show({
    required BuildContext context,
    required String price,
    required String productName,
  }) {
    return showModalBottomSheet<PaymentChannel>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentChannelSelector(
        price: price,
        productName: productName,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const SizedBox(height: 8),
            _buildChannelList(context),
            const SizedBox(height: 16),
            _buildCancelButton(context),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
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
                  child: const Icon(Icons.close, color: Colors.white70, size: 20),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _PaymentChannelItem(
            channel: PaymentChannel.googlePlay,
            onTap: () => onChannelSelected(PaymentChannel.googlePlay),
          ),
          const SizedBox(height: 8),
          _PaymentChannelItem(
            channel: PaymentChannel.haiPay,
            onTap: () => onChannelSelected(PaymentChannel.haiPay),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _PaymentChannelItem extends StatelessWidget {
  const _PaymentChannelItem({
    required this.channel,
    required this.onTap,
  });

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
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
          ),
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
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
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
    switch (channel) {
      case PaymentChannel.googlePlay:
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
      case PaymentChannel.haiPay:
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
  }
}
