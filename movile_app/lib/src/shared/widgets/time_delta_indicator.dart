import 'package:flutter/material.dart';

import '../../features/history/run_comparison.dart';

/// Shows the % faster/slower of a run vs the route's normal time, with a
/// coloured arrow: faster = green down-arrow (less time), slower = red up-arrow
/// (more time). Renders nothing when the delta can't be computed.
class TimeDeltaIndicator extends StatelessWidget {
  const TimeDeltaIndicator({
    super.key,
    required this.expected,
    required this.actual,
  });

  final Duration expected;
  final Duration actual;

  @override
  Widget build(BuildContext context) {
    final pct = runDeltaPercent(expected: expected, actual: actual);
    if (pct == null) return const SizedBox.shrink();

    final faster = pct < 0;
    final color = faster ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final icon = faster ? Icons.arrow_downward : Icons.arrow_upward;
    final label = '${pct.abs().toStringAsFixed(0)} %';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
