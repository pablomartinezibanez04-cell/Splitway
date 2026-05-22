import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays the countdown ticks, GO cue, and false-start cue.
///
/// Uses `SystemSound` + `HapticFeedback` as the primary mechanism so that the
/// feature works on every device without bundled audio assets. If real MP3
/// assets are dropped into `assets/sounds/` they are also played on top, so
/// users can override with custom drag-strip sounds.
class BeepPlayer {
  BeepPlayer();

  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _go = AudioPlayer();
  final AudioPlayer _falseStart = AudioPlayer();
  bool _assetsReady = false;

  Future<void> preload() async {
    try {
      await _tick.setSource(AssetSource('sounds/beep.mp3'));
      await _go.setSource(AssetSource('sounds/beep_go.mp3'));
      await _falseStart.setSource(AssetSource('sounds/beep_false.mp3'));
      await _tick.setReleaseMode(ReleaseMode.stop);
      await _go.setReleaseMode(ReleaseMode.stop);
      await _falseStart.setReleaseMode(ReleaseMode.stop);
      _assetsReady = true;
    } catch (e) {
      debugPrint('BeepPlayer.preload failed (assets invalid?): $e');
      _assetsReady = false;
    }
  }

  Future<void> tick() async {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    await _tryAsset(_tick);
  }

  Future<void> go() async {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
    await _tryAsset(_go);
  }

  Future<void> falseStart() async {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    await _tryAsset(_falseStart);
  }

  Future<void> _tryAsset(AudioPlayer p) async {
    if (!_assetsReady) return;
    try {
      await p.stop();
      await p.resume();
    } catch (e) {
      debugPrint('BeepPlayer playback failed: $e');
    }
  }

  Future<void> dispose() async {
    await _tick.dispose();
    await _go.dispose();
    await _falseStart.dispose();
  }
}
