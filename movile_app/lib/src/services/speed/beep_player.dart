import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Pre-loads audio assets into a small pool of [AudioPlayer]s so that
/// countdown ticks, GO, and false-start cues play with minimal latency.
///
/// Two tick players alternate (double-buffer) to avoid cutting off a
/// still-playing beep when the next tick fires.
class BeepPlayer {
  BeepPlayer();

  static const _tickSrc = 'sounds/beep.mp3';
  static const _goSrc = 'sounds/beep_go.mp3';
  static const _falseSrc = 'sounds/beep_false.mp3';

  bool _assetsReady = false;
  final List<AudioPlayer> _tickPool = [];
  int _tickIndex = 0;
  AudioPlayer? _goPlayer;
  AudioPlayer? _falsePlayer;

  Future<void> preload() async {
    try {
      for (var i = 0; i < 2; i++) {
        _tickPool.add(await _prepare(_tickSrc));
      }
      _goPlayer = await _prepare(_goSrc);
      _falsePlayer = await _prepare(_falseSrc);
      _assetsReady = true;
    } catch (e) {
      debugPrint('BeepPlayer.preload failed (assets missing?): $e');
    }
  }

  Future<AudioPlayer> _prepare(String src) async {
    final p = AudioPlayer();
    await p.setSource(AssetSource(src));
    return p;
  }

  void tick() {
    HapticFeedback.lightImpact();
    if (!_assetsReady || _tickPool.isEmpty) return;
    _replay(_tickPool[_tickIndex++ % _tickPool.length], _tickSrc);
  }

  void go() {
    HapticFeedback.mediumImpact();
    _replay(_goPlayer, _goSrc);
  }

  void falseStart() {
    HapticFeedback.heavyImpact();
    _replay(_falsePlayer, _falseSrc);
  }

  void _replay(AudioPlayer? p, String src) {
    if (!_assetsReady || p == null) return;
    p.stop().then((_) => p.play(AssetSource(src))).catchError((Object e) {
      debugPrint('BeepPlayer playback failed: $e');
    });
  }

  Future<void> dispose() async {
    for (final p in _tickPool) {
      await p.dispose();
    }
    _tickPool.clear();
    await _goPlayer?.dispose();
    await _falsePlayer?.dispose();
  }
}
