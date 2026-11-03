import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/app_orientation.dart';
import 'tutorial_videos_service.dart';

/// Full-screen player for an uploaded tutorial video: play / pause, seek
/// bar, ±10 s, and landscape allowed while it's open (restored on close).
class TutorialVideoPlayerScreen extends StatefulWidget {
  const TutorialVideoPlayerScreen({super.key, required this.video});
  final TutorialVideo video;

  @override
  State<TutorialVideoPlayerScreen> createState() => _TutorialVideoPlayerScreenState();
}

class _TutorialVideoPlayerScreenState extends State<TutorialVideoPlayerScreen> {
  late final VideoPlayerController _c =
      VideoPlayerController.networkUrl(Uri.parse(widget.video.videoUrl));
  bool _failed = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const []);
    _c.addListener(_onTick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
      _scheduleHide();
    }).catchError((Object e) {
      debugPrint('[TutorialVideo] $e');
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onTick() {
    if (!mounted) return;
    // Show controls again at the end so the user can replay or close.
    if (_c.value.isInitialized && !_c.value.isPlaying && !_controls) {
      setState(() => _controls = true);
    } else {
      setState(() {});
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _playPause() {
    final v = _c.value;
    if (v.isPlaying) {
      _c.pause();
    } else {
      if (v.position >= v.duration - const Duration(milliseconds: 300)) _c.seekTo(Duration.zero);
      _c.play();
      _scheduleHide();
    }
  }

  void _skip(int seconds) {
    final v = _c.value;
    var to = v.position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > v.duration) to = v.duration;
    _c.seekTo(to);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_onTick);
    _c.dispose();
    restoreAppOrientations();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: v.isInitialized ? _toggleControls : null,
        child: Stack(
          children: [
            Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "Couldn't play this video. Check your connection and try again.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : v.isInitialized
                      ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c))
                      : const CircularProgressIndicator(color: Colors.white),
            ),
            if (v.isInitialized && v.isBuffering)
              const Center(child: CircularProgressIndicator(color: Colors.white54)),
            // Top bar (always reachable to close)
            AnimatedOpacity(
              opacity: _controls || !v.isInitialized ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            if (v.isInitialized)
              IgnorePointer(
                ignoring: !_controls,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Stack(
                    children: [
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundButton(icon: Icons.replay_10_rounded, onTap: () => _skip(-10)),
                            const SizedBox(width: 28),
                            _RoundButton(
                              icon: v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 64,
                              onTap: _playPause,
                            ),
                            const SizedBox(width: 28),
                            _RoundButton(icon: Icons.forward_10_rounded, onTap: () => _skip(10)),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    _c,
                                    allowScrubbing: true,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    colors: const VideoProgressColors(
                                      playedColor: Colors.white,
                                      bufferedColor: Colors.white38,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.size = 48});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      );
}
