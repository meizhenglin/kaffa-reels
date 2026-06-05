import 'package:flutter/material.dart';

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
            width: 130,
            height: 130,
          ),
          const SizedBox(height: 5),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF808080),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
