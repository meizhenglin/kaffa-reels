import 'package:flutter/material.dart';

import '../../../components/preload_network_image.dart';
import '../../recommend/models/drama.dart';

class ExploreDramaGridCard extends StatelessWidget {
  const ExploreDramaGridCard({
    super.key,
    required this.drama,
    this.onTap,
  });

  final Drama drama;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: PreloadNetworkImage(
                imageUrl: drama.coverUrl,
                preloadAsset: 'assets/images/small_preload_bg.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            drama.title.split(' / ').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
