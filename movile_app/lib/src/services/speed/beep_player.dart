import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the countdown ticks, GO cue, and false-start cue.
///
/// Wraps every audio call in try/catch so that missing or invalid audio
/// assets degrade silently — the Velocidad feature still works without
/// audible cues if the user has not provided real MP3s yet.
class BeepPlayer {
  BeepPlayer();

  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _go = AudioPlayer();
  final AudioPlayer _falseStart = AudioPlayer();
  bool _ready = false;

  Future<void> preload() async {
    try {
      await _tick.setSource(AssetSource('sounds/beep.mp3'));
      await _go.setSource(AssetSource('sounds/beep_go.mp3'));
      await _falseStart.setSource(AssetSource('sounds/beep_false.mp3'));
      await _tick.setReleaseMode(ReleaseMode.stop);
      await _go.setReleaseMode(ReleaseMode.stop);
      await _falseStart.setReleaseMode(ReleaseMode.stop);
      _ready = true;
    } catch (e) {
      debugPrint('BeepPlayer.preload failed: $e');
    }
  }

  Future<void> tick() => _play(_tick);
  Future<void> go() => _play(_go);
  Future<void> falseStart() => _play(_falseStart);

  Future<void> _play(AudioPlayer p) async {
    if (!_ready) return;
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
