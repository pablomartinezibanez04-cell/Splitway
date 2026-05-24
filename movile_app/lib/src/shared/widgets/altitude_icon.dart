import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AltitudeIcon extends StatelessWidget {
  const AltitudeIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SvgPicture.asset(
      'assets/icon/altitude.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
