import 'package:flutter/material.dart';

class PreloadNetworkImage extends StatelessWidget {
  const PreloadNetworkImage({
    super.key,
    required this.imageUrl,
    required this.preloadAsset,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fadeInDuration = const Duration(milliseconds: 300),
  });

  final String imageUrl;
  final String preloadAsset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;

  @override
  Widget build(BuildContext context) {
    final borderRadius = this.borderRadius;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: SizedBox(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(preloadAsset, width: double.infinity, height: double.infinity, fit: fit),
            Image.network(
              imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: fit,
              frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return AnimatedOpacity(
                    opacity: 1,
                    duration: fadeInDuration,
                    child: child,
                  );
                }
                return const SizedBox.shrink();
              },
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
