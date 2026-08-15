import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/demo_sequence.dart';

/// Owns narration + background-music playback for one [DemoPlayerScreen]
/// play-through. Lives alongside [DemoController] for the lifetime of the
/// screen so the looping background track and the mute state survive step
/// changes and replays.
///
/// Only sequences listed in [_narrationAssetsBySequence] have any audio at
/// all — check [supports] before constructing one for a given sequence.
class DemoAudioController extends ChangeNotifier {
  DemoAudioController(this.sequence, {this.onNarrationDuration});

  final DemoSequence sequence;

  /// Called with a narrated step's total duration — its actual audio
  /// length plus [_narrationTrailingPause] — once it's known, so the caller
  /// can set the step's on-screen duration to exactly that instead of the
  /// unrelated text-based reading-time estimate. Never called for steps
  /// with no narration.
  final ValueChanged<Duration>? onNarrationDuration;

  static const _backgroundMusicVolume = 0.1;
  static const _narrationVolume = 1.0;
  static const _backgroundMusicAsset = 'audio/tutorial/Background_Music.mp3';
  static const _narrationTrailingPause = Duration(milliseconds: 2500);

  /// Caps how long a narrated step waits to hear back from the audio layer
  /// before falling back to its text-based reading-time duration. Local
  /// bundled assets normally resolve in well under a second, so this is a
  /// generous ceiling for a genuinely stuck/failed load — not a value
  /// that's expected to be hit in practice.
  static const _narrationLoadTimeout = Duration(seconds: 2);

  /// On Android, `audioplayers` requests exclusive audio focus
  /// (`AndroidAudioFocus.gain`) by default for every player — and its native
  /// side pauses a player the moment it loses focus, *even to another
  /// player in this same app*. Since narration and background music are two
  /// separate players, that default made each narration `play()` silently
  /// pause the music (which never resumed), and occasionally raced with it.
  /// Requesting no focus at all lets both mix normally, matching iOS (which
  /// doesn't have this "same-app" focus quirk to begin with).
  static final _audioContext = AudioContext(
    android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
  );

  /// Narration files for each supported sequence, in slide order. Every
  /// sequence here has more steps than narration files — [_narrationByStep]
  /// anchors the leading files to the first steps and the trailing files
  /// (see [_trailingNarrationCountOverrides]) to the last steps, whatever
  /// falls silently in between.
  static const Map<String, List<String>> _narrationAssetsBySequence = {
    'demo.intro.whatIsGiggre': [
      'audio/tutorial/01_What_Is_Giggre.mp3',
      'audio/tutorial/02_What_Is_Giggre.mp3',
      'audio/tutorial/03_What_Is_Giggre.mp3',
    ],
    'demo.host.offeredGig': [
      'audio/tutorial/01_Host_Offered_Gig.mp3',
      'audio/tutorial/02_Host_Offered_Gig.mp3',
      'audio/tutorial/03_Host_Offered_Gig.mp3',
      'audio/tutorial/04_Host_Offered_Gig.mp3',
    ],
    'demo.host.quickGig': [
      'audio/tutorial/01_Host_Quick_Gig.mp3',
      'audio/tutorial/02_Host_Quick_Gig.mp3',
      'audio/tutorial/03_Host_Quick_Gig.mp3',
    ],
    'demo.host.openGig': [
      'audio/tutorial/01_Host_Open_Gig.mp3',
      'audio/tutorial/02_Host_Open_Gig.mp3',
      'audio/tutorial/03_Host_Open_Gig.mp3',
    ],
    'demo.worker.activeMode': [
      'audio/tutorial/01_Worker_Active_Mode.mp3',
      'audio/tutorial/02_Worker_Active_Mode.mp3',
      'audio/tutorial/03_Worker_Active_Mode.mp3',
    ],
    'demo.worker.directOffer': [
      'audio/tutorial/01_Worker_Offered_Gig.mp3',
      'audio/tutorial/02_Worker_Offered_Gig.mp3',
      'audio/tutorial/03_Worker_Offered_Gig.mp3',
      'audio/tutorial/04_Worker_Offered_Gig.mp3',
    ],
    'demo.worker.openGigs': [
      'audio/tutorial/01_Worker_Open_Gig.mp3',
      'audio/tutorial/02_Worker_Open_Gig.mp3',
      'audio/tutorial/03_Worker_Open_Gig.mp3',
      'audio/tutorial/04_Worker_Open_Gig.mp3',
      'audio/tutorial/05_Worker_Open_Gig.mp3',
      'audio/tutorial/06_Worker_Open_Gig.mp3',
      'audio/tutorial/07_Worker_Open_Gig.mp3',
    ],
    'demo.worker.quickGigs': [
      'audio/tutorial/01_Worker_Quick_Gig.mp3',
      'audio/tutorial/02_Worker_Quick_Gig.mp3',
      'audio/tutorial/03_Worker_Quick_Gig.mp3',
    ],
    'demo.worker.toolchest': [
      'audio/tutorial/01_Worker_Toolchest.mp3',
      'audio/tutorial/02_Worker_Toolchest.mp3',
      'audio/tutorial/03_Worker_Toolchest.mp3',
    ],
  };

  /// How many narration files (from the end of that sequence's list) anchor
  /// to the last steps, counting backward — e.g. 2 files means "2nd-to-last
  /// slide" then "last slide". Sequences not listed here anchor just the
  /// single last file to the last step (the common "...then last slide"
  /// shape); every other file anchors to the steps from the start, in order.
  static const Map<String, int> _trailingNarrationCountOverrides = {
    'demo.worker.directOffer': 2,
    'demo.worker.toolchest': 2,
  };

  /// How many steps at the very end of a sequence are intentionally left
  /// with no narration, shifting the trailing block earlier — e.g. 1 means
  /// the last narration file lands on the 2nd-to-last slide instead of the
  /// true last one. Sequences not listed here don't skip any trailing
  /// steps.
  static const Map<String, int> _trailingSilentStepCountOverrides = {
    'demo.intro.whatIsGiggre': 1,
  };

  static bool supports(DemoSequence sequence) =>
      _narrationAssetsBySequence.containsKey(sequence.id);

  /// Step indices that have narration for [sequence] — known synchronously,
  /// from the sequence id and step count alone, with no audio loading
  /// involved. Passed to [DemoController] so it knows, up front, which
  /// steps to withhold its own timer for (see [DemoController._beginStep]).
  static Set<int> narratedStepsFor(DemoSequence sequence) =>
      _narrationByStepFor(sequence).keys.toSet();

  static Map<int, String> _narrationByStepFor(DemoSequence sequence) {
    final assets = _narrationAssetsBySequence[sequence.id] ?? const [];
    if (assets.isEmpty) return const {};
    final trailingCount = _trailingNarrationCountOverrides[sequence.id] ?? 1;
    final trailingSilentCount =
        _trailingSilentStepCountOverrides[sequence.id] ?? 0;
    final leadingCount = assets.length - trailingCount;
    final stepCount = sequence.steps.length;
    return {
      for (var i = 0; i < leadingCount; i++) i: assets[i],
      for (var i = 0; i < trailingCount; i++)
        stepCount - trailingSilentCount - trailingCount + i:
            assets[leadingCount + i],
    };
  }

  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _narrationPlayer = AudioPlayer();
  bool _isMuted = false;

  // Bumped on every call to `_playNarrationForStep` so a superseded call
  // (e.g. two step changes firing in quick succession) can tell it's stale
  // and stop short of touching the player — otherwise two overlapping
  // `stop()`/`play()` chains on the same player can leave two narrations
  // audible at once.
  int _narrationRequest = 0;

  // The most recently created `_narrationLoadTimeout` timer. Tracked (rather
  // than relying on `Future.timeout()`, whose internal timer isn't
  // reachable) so it can be cancelled the moment it settles, and so
  // `dispose()` can cancel it too if the screen is left mid-load — otherwise
  // it's a live `Timer` the test framework (rightly) flags as a leak if it
  // outlives the widget tree, and a real, if harmless, leak on-device too.
  Timer? _narrationTimeoutTimer;

  bool get isMuted => _isMuted;

  Map<int, String> get _narrationByStep => _narrationByStepFor(sequence);

  Future<void> start() async {
    // Fire-and-forget with its own error handling: narration must still
    // play — and `DemoController` must still get its duration callback —
    // even if the music track fails to load. `_playNarrationForStep` below
    // must never be blocked behind this.
    unawaited(_startBackgroundMusic());
    await _playNarrationForStep(0);
  }

  Future<void> _startBackgroundMusic() async {
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.play(
        AssetSource(_backgroundMusicAsset),
        volume: _isMuted ? 0 : _backgroundMusicVolume,
        ctx: _audioContext,
      );
    } catch (_) {
      // Background music is a nice-to-have; the demo itself doesn't depend
      // on it.
    }
  }

  Future<void> onStepChanged(int stepIndex) => _playNarrationForStep(stepIndex);

  /// Plays [stepIndex]'s narration (if any) and always reports a duration
  /// for it via [onNarrationDuration] — the clip's real length plus
  /// [_narrationTrailingPause] normally, or the step's own text-based
  /// reading-time duration as a fallback if playback fails OR doesn't
  /// finish loading within [_narrationLoadTimeout]. [DemoController]
  /// withholds its auto-advance timer for narrated steps entirely until
  /// this reports back (see [DemoController._beginStep]), so the fallback
  /// matters: without a *time-bounded* one, a load that hangs — rather than
  /// failing outright — would leave that step stuck with no timer at all
  /// instead of just losing its narration.
  Future<void> _playNarrationForStep(int stepIndex) async {
    final request = ++_narrationRequest;
    final fallbackDuration = sequence.steps[stepIndex].duration;
    final completer = Completer<void>();

    _narrationTimeoutTimer?.cancel();
    final timer = Timer(_narrationLoadTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Narration load timed out'));
      }
    });
    _narrationTimeoutTimer = timer;

    unawaited(
      _loadAndPlayNarration(stepIndex, request).then(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
        },
      ),
    );

    try {
      await completer.future;
    } catch (_) {
      if (request == _narrationRequest) {
        onNarrationDuration?.call(fallbackDuration);
      }
    } finally {
      timer.cancel();
    }
  }

  Future<void> _loadAndPlayNarration(int stepIndex, int request) async {
    await _narrationPlayer.stop();
    if (request != _narrationRequest) return;
    final asset = _narrationByStep[stepIndex];
    if (asset == null) return;
    await _narrationPlayer.play(
      AssetSource(asset),
      volume: _isMuted ? 0 : _narrationVolume,
      ctx: _audioContext,
    );
    if (request != _narrationRequest) return;
    final narrationDuration = await _narrationPlayer.getDuration();
    if (request != _narrationRequest) return;
    onNarrationDuration?.call(
      narrationDuration != null
          ? narrationDuration + _narrationTrailingPause
          : sequence.steps[stepIndex].duration,
    );
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _musicPlayer.setVolume(_isMuted ? 0 : _backgroundMusicVolume);
    await _narrationPlayer.setVolume(_isMuted ? 0 : _narrationVolume);
    notifyListeners();
  }

  @override
  void dispose() {
    _narrationTimeoutTimer?.cancel();
    _musicPlayer.dispose();
    _narrationPlayer.dispose();
    super.dispose();
  }
}
