import 'package:flutter/material.dart';

class RtlBackButton extends StatelessWidget {
  const RtlBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.size = 20,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });

  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final image = Image.asset(
      'assets/images/back_icon.png',
      width: size,
      height: size,
      color: color,
      errorBuilder: (_, __, ___) => Icon(
        Icons.arrow_back,
        color: color,
        size: size,
      ),
    );

    return IconButton(
      onPressed: onPressed,
      padding: padding,
      constraints: constraints,
      icon: Transform(
        alignment: Alignment.center,
        transform: isRtl
            ? (Matrix4.identity()..scale(-1.0, 1.0, 1.0))
            : Matrix4.identity(),
        child: image,
      ),
    );
  }
}
