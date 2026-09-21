import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'giggre_avatar_art.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Giggre living avatars — the player.
//
//  The design animates these with CSS keyframes, which no Flutter SVG renderer
//  runs, so the five motions are reproduced here against the same keyframe
//  stops and per-character timings. Painting is vector, so one avatar is sharp
//  at 28px in a list row and at 240px on a profile, off no assets at all.
// ─────────────────────────────────────────────────────────────────────────────

/// A keyframe stop: a position in the cycle, 0..1, and the value there.
typedef _Stop = (double at, double value);

/// The design's keyframes, one list per motion.
///
/// CSS tweens these with `ease-in-out`, so the same curve runs between stops
/// here. The oscillating ones (bob, sway, strands) hold a single stop at the
/// half-way mark, which under that curve is a smooth back-and-forth.
const _bob = <_Stop>[(0, 0), (0.5, -5), (1, 0)];
const _sway = <_Stop>[(0, -1.6), (0.5, 1.6), (1, -1.6)];
const _blink = <_Stop>[(0, 1), (0.9, 1), (0.93, 0.08), (0.96, 1), (1, 1)];
const _wave = <_Stop>[
  (0, 0),
  (0.12, 13),
  (0.26, -3),
  (0.40, 11),
  (0.54, -1),
  (0.62, 0),
  (1, 0),
];
const _strandLeft = <_Stop>[(0, 2), (0.5, -2), (1, 2)];
const _strandRight = <_Stop>[(0, -2), (0.5, 2), (1, -2)];

/// The arm and hair run on fixed timings in the design rather than per
/// character, so they stay here rather than in [AvatarTiming].
const _waveDuration = 2.9;
const _waveDelay = 0.6;
const _strandDuration = 4.6;

double _sample(List<_Stop> stops, double phase) {
  for (var i = 0; i < stops.length - 1; i++) {
    final (at, value) = stops[i];
    final (nextAt, nextValue) = stops[i + 1];
    if (phase > nextAt) continue;
    if (nextAt == at) return nextValue;
    final t = Curves.easeInOut.transform(
      ((phase - at) / (nextAt - at)).clamp(0.0, 1.0),
    );
    return value + (nextValue - value) * t;
  }
  return stops.last.$2;
}

/// Where in its cycle a motion is at [seconds]. A delay holds it at the first
/// stop rather than shifting the whole cycle, matching `animation-delay`.
double _phase(double seconds, double duration, double delay) {
  if (seconds <= delay) return 0;
  return ((seconds - delay) / duration) % 1.0;
}

/// One avatar, playing its idle motion.
///
/// [playing] false freezes it at the start of every cycle — the resting pose.
/// Long lists and the picker's unselected tiles use that so a screen of
/// avatars is not a screen of moving parts.
class GiggreAvatar extends StatefulWidget {
  final GiggreAvatarArt art;
  final double size;
  final bool playing;

  /// Clips to a circle. The art is drawn to fill one, so off, the corners of
  /// the tile show as a square.
  final bool circle;

  const GiggreAvatar({
    super.key,
    required this.art,
    this.size = 96,
    this.playing = true,
    this.circle = true,
  });

  /// Looks the id up and returns null when it is unknown, so a caller can fall
  /// back to a photo or initials rather than rendering a placeholder character
  /// that is not the one the user chose.
  static GiggreAvatar? forId(
    String? id, {
    double size = 96,
    bool playing = true,
    bool circle = true,
  }) {
    final art = giggreAvatarById(id);
    if (art == null) return null;
    return GiggreAvatar(art: art, size: size, playing: playing, circle: circle);
  }

  @override
  State<GiggreAvatar> createState() => _GiggreAvatarState();
}

class _GiggreAvatarState extends State<GiggreAvatar>
    with SingleTickerProviderStateMixin {
  /// Seconds since the ticker started, and the painter's repaint signal.
  ///
  /// A raw ticker rather than an AnimationController: the six motions have
  /// durations from 2.9s to 6.8s with no useful common multiple, so a
  /// controller looping over any fixed period would jump when it wrapped.
  late final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_onTick);

  @override
  void initState() {
    super.initState();
    if (widget.playing) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    _clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void didUpdateWidget(GiggreAvatar old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _ticker.start();
    } else {
      _ticker.stop();
      _clock.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: GiggreAvatarPainter(art: widget.art, clock: _clock),
        isComplex: true,
      ),
    );
    return widget.circle ? ClipOval(child: box) : box;
  }
}

/// Paints one avatar at one instant. Exposed so a still can be rendered
/// off-screen (see [renderGiggreAvatarPng]) with the same code that animates.
class GiggreAvatarPainter extends CustomPainter {
  final GiggreAvatarArt art;

  /// Seconds into the animation. Repaints come straight off this, so the
  /// widget tree is never rebuilt to move an avatar.
  final ValueListenable<double> clock;

  GiggreAvatarPainter({required this.art, required this.clock})
    : super(repaint: clock);

  /// Cached per paint pass: a group's rotation origin depends on its own
  /// bounds, which never change, but computing them walks every child path.
  static final Map<List<AvatarNode>, Rect> _bounds = {};

  static Rect _boundsOf(List<AvatarNode> nodes) =>
      _bounds.putIfAbsent(nodes, () {
        Rect? out;
        void visit(List<AvatarNode> list) {
          for (final node in list) {
            switch (node) {
              case AvatarShape(:final path):
                final b = path.getBounds();
                out = out == null ? b : out!.expandToInclude(b);
              case AvatarGroup(:final children):
                visit(children);
            }
          }
        }

        visit(nodes);
        return out ?? Rect.zero;
      });

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    canvas.save();
    canvas.scale(size.width / kAvatarViewBox, size.height / kAvatarViewBox);

    const centre = Offset(kAvatarViewBox / 2, kAvatarViewBox / 2);
    canvas.drawCircle(centre, 118, Paint()..color = art.tile);

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: 118)),
    );
    _paintNodes(canvas, art.scene, t);
    canvas.restore();

    // The rim sits over the clip, as a ring on the very edge of the tile.
    canvas.drawCircle(
      centre,
      116,
      Paint()
        ..color = const Color(0x59FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.restore();
  }

  void _paintNodes(Canvas canvas, List<AvatarNode> nodes, double t) {
    for (final node in nodes) {
      switch (node) {
        case AvatarShape():
          _paintShape(canvas, node);
        case AvatarGroup(:final motion, :final children):
          canvas.save();
          _applyMotion(canvas, motion, children, t);
          _paintNodes(canvas, children, t);
          canvas.restore();
      }
    }
  }

  /// The transform for one motion, about the same origin the design's CSS
  /// uses: the group's own box for head, eyes and strands, absolute viewBox
  /// coordinates for the waving arm.
  void _applyMotion(
    Canvas canvas,
    AvatarMotion motion,
    List<AvatarNode> children,
    double t,
  ) {
    final timing = art.timing;
    switch (motion) {
      case AvatarMotion.none:
        return;
      case AvatarMotion.body:
        canvas.translate(
          0,
          _sample(_bob, _phase(t, timing.bobDuration, timing.bobDelay)),
        );
      case AvatarMotion.head:
        final b = _boundsOf(children);
        _rotate(
          canvas,
          Offset(b.left + b.width * 0.5, b.top + b.height * 0.92),
          _sample(_sway, _phase(t, timing.swayDuration, 0)),
        );
      case AvatarMotion.eyes:
        final b = _boundsOf(children);
        final scale = _sample(
          _blink,
          _phase(t, timing.blinkDuration, timing.blinkDelay),
        );
        canvas.translate(b.center.dx, b.center.dy);
        canvas.scale(1, scale);
        canvas.translate(-b.center.dx, -b.center.dy);
      case AvatarMotion.arm:
        _rotate(
          canvas,
          const Offset(174, 180),
          _sample(_wave, _phase(t, _waveDuration, _waveDelay)),
        );
      case AvatarMotion.strandLeft:
      case AvatarMotion.strandRight:
        final b = _boundsOf(children);
        _rotate(
          canvas,
          Offset(b.center.dx, b.top),
          _sample(
            motion == AvatarMotion.strandLeft ? _strandLeft : _strandRight,
            _phase(t, _strandDuration, 0),
          ),
        );
    }
  }

  void _rotate(Canvas canvas, Offset origin, double degrees) {
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-origin.dx, -origin.dy);
  }

  void _paintShape(Canvas canvas, AvatarShape shape) {
    final fill = shape.fill;
    if (fill != null) {
      canvas.drawPath(
        shape.path,
        Paint()
          ..color = fill.withValues(alpha: fill.a * shape.opacity)
          ..isAntiAlias = true,
      );
    }
    final stroke = shape.stroke;
    if (stroke != null && shape.strokeWidth > 0) {
      canvas.drawPath(
        shape.path,
        Paint()
          ..color = stroke.withValues(alpha: stroke.a * shape.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth
          // Every stroke in the art is round-capped and round-joined; the
          // design sets stroke-linecap on all of them.
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(GiggreAvatarPainter old) =>
      old.art != art || old.clock != clock;
}

/// Renders an avatar's resting pose to PNG bytes.
///
/// This is what gets uploaded as the user's photo, so every screen that only
/// knows about `photoUrl` — gig cards, chat, applicant lists — shows the
/// avatar they picked without having to learn about avatars at all.
Future<Uint8List> renderGiggreAvatarPng(
  GiggreAvatarArt art, {
  double size = 512,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  GiggreAvatarPainter(
    art: art,
    clock: ValueNotifier(0),
  ).paint(canvas, Size(size, size));

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size.round(), size.round());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Could not encode the ${art.id} avatar as a PNG');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
