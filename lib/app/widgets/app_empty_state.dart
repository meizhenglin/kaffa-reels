import 'package:flutter/material.dart';

import '../../features/home/models/home_card_layout.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.imageAsset = 'assets/images/noData.png',
  });

  final String message;
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            imageAsset,
            width: HomeCardLayout.scaled(context, 130),
            height: HomeCardLayout.scaled(context, 130),
          ),
          SizedBox(height: HomeCardLayout.scaled(context, 5)),
          Text(
            message,
            style: TextStyle(
              color: const Color(0xFF808080),
              fontSize: HomeCardLayout.scaled(context, 13),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
