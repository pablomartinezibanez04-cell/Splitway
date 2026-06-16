import 'dart:async';

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
    this.showFinish = false,
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

  /// When true, a checkered-flag chip is appended after the last sector.
  final bool showFinish;

  @override
  State<SectorChipsBar> createState() => _SectorChipsBarState();
}

class _SectorChipsBarState extends State<SectorChipsBar> {
  final ScrollController _controller = ScrollController();
  Timer? _returnTimer;

  /// Width of one chip slot including the trailing gap; set during build so the
  /// auto-scroll maths can reuse it.
  double _slotExtent = 0;

  /// True while the user's finger is on the scroll area.
  bool _pointerDown = false;

  /// True after the user manually scrolled, until the auto-return fires.
  bool _manualMode = false;

  int get _totalSlots =>
      widget.tiers.length + (widget.showFinish ? 1 : 0);

  bool get _scrolls => _totalSlots > widget.visibleCount;

  @override
  void didUpdateWidget(SectorChipsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_scrolls && _manualMode) {
      _manualMode = false;
      _returnTimer?.cancel();
    }
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_manualMode) _scrollToActive();
      });
    }
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToActive({
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) {
    final active = widget.activeIndex;
    if (!_scrolls || active == null || !_controller.hasClients) return;
    final total = _totalSlots;
    final firstVisible = (active - 1).clamp(0, total - widget.visibleCount);
    final target = (firstVisible * _slotExtent)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target, duration: duration, curve: curve);
  }

  void _startReturnTimer() {
    _returnTimer?.cancel();
    _returnTimer = Timer(const Duration(seconds: 5), () {
      _manualMode = false;
      _scrollToActive(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    });
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
    final allSectorsCrossed = widget.activeIndex != null &&
        widget.activeIndex! >= n;

    if (!_scrolls) {
      return Row(
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            Expanded(child: _chip(i)),
          ],
          if (widget.showFinish) ...[
            SizedBox(width: widget.spacing),
            FinishChip(crossed: allSectorsCrossed),
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

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_manualMode) _scrollToActive();
        });

        return Listener(
          onPointerDown: (_) {
            _pointerDown = true;
            _manualMode = true;
            _returnTimer?.cancel();
          },
          onPointerUp: (_) => _pointerDown = false,
          onPointerCancel: (_) => _pointerDown = false,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              if (_manualMode && !_pointerDown) {
                _startReturnTimer();
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: widget.spacing),
                    SizedBox(width: chipWidth, child: _chip(i)),
                  ],
                  if (widget.showFinish) ...[
                    SizedBox(width: widget.spacing),
                    SizedBox(
                      width: chipWidth,
                      child: FinishChip(crossed: allSectorsCrossed),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
