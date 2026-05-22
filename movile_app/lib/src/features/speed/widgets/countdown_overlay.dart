import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.value});

  /// `value` is null on the GO frame.
  final int? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = value == null ? l.speedSessionGo : '$value';
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            text,
            key: ValueKey(text),
            style: const TextStyle(
              fontSize: 180,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(blurRadius: 24, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
