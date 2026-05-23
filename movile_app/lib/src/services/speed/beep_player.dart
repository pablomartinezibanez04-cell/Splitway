import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays the countdown ticks, GO cue, and false-start cue.
///
/// Each call creates a short-lived [AudioPlayer] that auto-disposes on
/// completion, avoiding state issues with reusing a single player instance
/// across rapid successive plays.
class BeepPlayer {
  BeepPlayer();

  static const _tickSrc = 'sounds/beep.mp3';
  static const _goSrc = 'sounds/beep_go.mp3';
  static const _falseSrc = 'sounds/beep_false.mp3';

  bool _assetsReady = false;
  final List<AudioPlayer> _active = [];

  Future<void> preload() async {
    try {
      final test = AudioPlayer();
      await test.setSource(AssetSource(_tickSrc));
      await test.dispose();
      _assetsReady = true;
    } catch (e) {
      debugPrint('BeepPlayer.preload failed (assets missing?): $e');
    }
  }

  void tick() {
    HapticFeedback.lightImpact();
    _fire(_tickSrc);
  }

  void go() {
    HapticFeedback.mediumImpact();
    _fire(_goSrc);
  }

  void falseStart() {
    HapticFeedback.heavyImpact();
    _fire(_falseSrc);
  }

  void _fire(String src) {
    if (!_assetsReady) return;
    final p = AudioPlayer();
    _active.add(p);
    p.onPlayerComplete.listen((_) {
      _active.remove(p);
      p.dispose();
    });
    p.play(AssetSource(src)).catchError((Object e) {
      debugPrint('BeepPlayer playback failed: $e');
      _active.remove(p);
      p.dispose();
    });
  }

  Future<void> dispose() async {
    final copy = List<AudioPlayer>.of(_active);
    _active.clear();
    for (final p in copy) {
      await p.dispose();
    }
  }
}
