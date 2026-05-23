import 'package:flutter/material.dart';

class SpeedCategoryHeader extends StatelessWidget {
  const SpeedCategoryHeader({
    super.key,
    required this.label,
    this.light = false,
  });

  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: light ? Colors.white54 : Theme.of(context).hintColor,
        ),
      ),
    );
  }
}
