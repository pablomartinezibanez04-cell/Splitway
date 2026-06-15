import 'package:flutter/material.dart';

import 'sector_chip.dart';

/// Lays out a row of [SectorChip]s.
///
/// With up to [visibleCount] sectors the chips share the full width equally
/// (each wrapped in an [Expanded]). With more sectors the bar becomes a
/// horizontal scroll list where every chip keeps the width of one slot —
/// [visibleCount] chips fit on screen at a time — and, when [activeIndex] is
/// provided (live tracking), it auto-scrolls to keep the sector in progress in
/// view as earlier ones are completed.
class SectorChipsBar extends StatefulWidget {
  const SectorChipsBar({
    super.key,
    required this.tiers,
    this.times,
    this.activeIndex,
    this.dotSeparator = true,
    this.visibleCount = 3,
    this.spacing = 8,
  })  : assert(times == null || times.length == tiers.length),
        assert(visibleCount > 0);

  /// Tier (colour) for each chip, in order. Length defines the chip count.
  final List<SectorChipTier> tiers;

  /// Optional per-chip time shown above the number (history view). When null,
  /// only the coloured number is shown (live view).
  final List<Duration?>? times;

  /// Index of the sector currently in progress (first not-yet-completed). When
  /// set and the bar scrolls, it auto-scrolls to keep this sector visible.
  final int? activeIndex;

  final bool dotSeparator;

  /// Number of chips that share the width / fit in the viewport before the bar
  /// starts scrolling.
  final int visibleCount;

  final double spacing;

  @override
  State<SectorChipsBar> createState() => _SectorChipsBarState();
}

class _SectorChipsBarState extends State<SectorChipsBar> {
  final ScrollController _controller = ScrollController();

  /// Width of one chip slot including the trailing gap; set during build so the
  /// auto-scroll maths can reuse it.
  double _slotExtent = 0;

  bool get _scrolls => widget.tiers.length > widget.visibleCount;

  @override
  void didUpdateWidget(SectorChipsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToActive() {
    final active = widget.activeIndex;
    if (!_scrolls || active == null || !_controller.hasClients) return;
    final n = widget.tiers.length;
    // Keep one completed sector visible to the left of the active one.
    final firstVisible = (active - 1).clamp(0, n - widget.visibleCount);
    final target = (firstVisible * _slotExtent)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  SectorChip _chip(int i) => SectorChip(
        sectorNumber: i + 1,
        tier: widget.tiers[i],
        time: widget.times?[i],
        dotSeparator: widget.dotSeparator,
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.tiers.length;

    if (!_scrolls) {
      return Row(
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            Expanded(child: _chip(i)),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalGap = widget.spacing * (widget.visibleCount - 1);
        final chipWidth =
            (constraints.maxWidth - totalGap) / widget.visibleCount;
        _slotExtent = chipWidth + widget.spacing;

        // Position the active sector on the first build once we know the width.
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());

        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: widget.spacing),
                SizedBox(width: chipWidth, child: _chip(i)),
              ],
            ],
          ),
        );
      },
    );
  }
}
