import 'dart:ui';

import 'svg_path_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Giggre living avatars — the drawing data.
//
//  Ported from the design's SVG, which builds each character from shared parts
//  and a colour config. That structure is kept: the parts below are the same
//  functions, the `d` strings are copied across unchanged, and each character
//  is still just a palette plus a few flags. Adding a seventh avatar is a
//  config entry, not new drawing code.
//
//  Everything is authored in the design's 240x240 viewBox. [kAvatarViewBox]
//  is the only number a caller needs; the painter scales from it.
// ─────────────────────────────────────────────────────────────────────────────

const double kAvatarViewBox = 240;

/// Which idle animation moves a group. The design drives these from CSS
/// keyframes on class names; these are the same five, by the same names.
enum AvatarMotion {
  /// Inherits the body's rise and fall and nothing else.
  none,

  /// The whole character breathing — a slow rise and fall.
  body,

  /// Head tilting side to side.
  head,

  /// Eyes closing, on a long cycle with a very short close.
  eyes,

  /// Raised arm waving.
  arm,

  strandLeft,
  strandRight,
}

sealed class AvatarNode {
  const AvatarNode();
}

/// One painted shape. Fill and stroke are separate nodes in the source SVG's
/// terms — a shape here carries whichever of the two it was given.
final class AvatarShape extends AvatarNode {
  final Path path;
  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final double opacity;

  const AvatarShape({
    required this.path,
    this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.opacity = 1,
  });
}

/// A group of shapes that move together.
final class AvatarGroup extends AvatarNode {
  final AvatarMotion motion;
  final List<AvatarNode> children;

  const AvatarGroup(this.motion, this.children);
}

/// Per-character animation timing, in seconds. Each avatar gets its own so a
/// screenful of them never falls into lockstep.
class AvatarTiming {
  final double bobDuration;
  final double bobDelay;
  final double blinkDuration;
  final double blinkDelay;
  final double swayDuration;

  const AvatarTiming({
    required this.bobDuration,
    required this.bobDelay,
    required this.blinkDuration,
    required this.blinkDelay,
    required this.swayDuration,
  });
}

/// One finished avatar: who it is, and the scene to paint.
class GiggreAvatarArt {
  final String id;
  final String name;

  /// What it does when idle — shown under the avatar in the picker.
  final String move;

  /// The disc behind the character.
  final Color tile;

  /// The little Giggre arc over the character's head.
  final Color arc;

  final AvatarTiming timing;

  /// Painted in order, inside the circular clip.
  final List<AvatarNode> scene;

  const GiggreAvatarArt({
    required this.id,
    required this.name,
    required this.move,
    required this.tile,
    required this.arc,
    required this.timing,
    required this.scene,
  });
}

// ── Shape helpers ────────────────────────────────────────────────────────────

AvatarShape _fill(String d, Color color, {double opacity = 1}) =>
    AvatarShape(path: parseSvgPath(d), fill: color, opacity: opacity);

AvatarShape _stroke(
  String d,
  Color color,
  double width, {
  double opacity = 1,
}) => AvatarShape(
  path: parseSvgPath(d),
  stroke: color,
  strokeWidth: width,
  opacity: opacity,
);

AvatarShape _ellipse(
  double cx,
  double cy,
  double rx,
  double ry,
  Color fill, {
  double opacity = 1,
}) => AvatarShape(
  path: Path()
    ..addOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    ),
  fill: fill,
  opacity: opacity,
);

AvatarShape _circle(
  double cx,
  double cy,
  double r, {
  Color? fill,
  Color? stroke,
  double strokeWidth = 0,
  double opacity = 1,
}) => AvatarShape(
  path: Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
  fill: fill,
  stroke: stroke,
  strokeWidth: strokeWidth,
  opacity: opacity,
);

AvatarShape _rrect(
  double x,
  double y,
  double w,
  double h,
  double r, {
  Color? fill,
  Color? stroke,
  double strokeWidth = 0,
}) => AvatarShape(
  path: Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
    ),
  fill: fill,
  stroke: stroke,
  strokeWidth: strokeWidth,
);

// ── Character configuration ──────────────────────────────────────────────────

enum _Hair { short, afro, bun, scarf }

class _Cfg {
  final String id;
  final String name;
  final String move;
  final Color skin;
  final Color skinShade;
  final Color top;
  final Color topDark;
  final Color hairColor;
  final Color? hairDark;
  final Color browColor;
  final Color blush;
  final Color tile;
  final Color arc;
  final _Hair hair;
  final Color? cap;
  final Color? capDark;
  final bool wave;
  final bool openMouth;
  final bool glasses;
  final bool freckles;
  final bool earrings;
  final AvatarTiming timing;

  const _Cfg({
    required this.id,
    required this.name,
    required this.move,
    required this.skin,
    required this.skinShade,
    required this.top,
    required this.topDark,
    required this.hairColor,
    required this.browColor,
    required this.blush,
    required this.tile,
    required this.arc,
    required this.hair,
    required this.timing,
    this.hairDark,
    this.cap,
    this.capDark,
    this.wave = false,
    this.openMouth = false,
    this.glasses = false,
    this.freckles = false,
    this.earrings = false,
  });
}

// ── Parts ────────────────────────────────────────────────────────────────────

List<AvatarNode> _ears(_Cfg c) => [
  _ellipse(71, 116, 8, 11, c.skin),
  _ellipse(169, 116, 8, 11, c.skin),
  _ellipse(71, 116, 3.5, 5, c.skinShade),
  _ellipse(169, 116, 3.5, 5, c.skinShade),
];

List<AvatarNode> _hairBack(_Cfg c) {
  switch (c.hair) {
    case _Hair.afro:
      const puffs = [
        [86.0, 66.0],
        [110.0, 50.0],
        [134.0, 50.0],
        [158.0, 66.0],
        [70.0, 94.0],
        [172.0, 94.0],
        [120.0, 46.0],
        [76.0, 120.0],
        [166.0, 120.0],
      ];
      return [
        for (final p in puffs) _circle(p[0], p[1], 23, fill: c.hairColor),
      ];
    case _Hair.bun:
      return [
        _fill(
          'M70 150 Q66 96 120 92 Q174 96 170 150 Q120 132 70 150 Z',
          c.hairColor,
        ),
      ];
    case _Hair.short:
    case _Hair.scarf:
      return const [];
  }
}

List<AvatarNode> _hairMain(_Cfg c) {
  switch (c.hair) {
    case _Hair.scarf:
      return [
        _fill(
          'M56 128 Q48 54 120 44 Q192 54 184 128 Q180 150 168 150 '
          'Q176 116 160 90 Q148 72 120 72 Q92 72 80 90 Q64 116 72 150 '
          'Q60 150 56 128 Z',
          c.hairColor,
        ),
        _fill(
          'M74 148 Q120 168 166 148 L166 176 Q120 190 74 176 Z',
          c.hairDark!,
        ),
        _stroke('M116 96 Q126 108 120 122', c.hairDark!, 3, opacity: 0.6),
      ];
    // The afro reads as one silhouette behind the head; a fringe on top of it
    // would only cut the puffs in half.
    case _Hair.afro:
      return const [];
    case _Hair.short:
    case _Hair.bun:
      return [
        _fill(
          'M64 108 Q60 52 120 46 Q180 52 176 108 Q168 92 150 96 '
          'Q152 78 120 78 Q88 78 90 96 Q72 92 64 108 Z',
          c.hairColor,
        ),
      ];
  }
}

List<AvatarNode> _face(_Cfg c) => [
  _ellipse(90, 123, 9, 5.5, c.blush, opacity: 0.38),
  _ellipse(150, 123, 9, 5.5, c.blush, opacity: 0.38),
  _stroke('M90 92 Q101 86 112 91', c.browColor, 4),
  _stroke('M128 91 Q139 86 150 92', c.browColor, 4),
  AvatarGroup(AvatarMotion.eyes, [
    _ellipse(101, 107, 7, 9, const Color(0xFF2B2320)),
    _ellipse(139, 107, 7, 9, const Color(0xFF2B2320)),
    _circle(103.5, 103.5, 2.4, fill: const Color(0xFFFFFFFF)),
    _circle(141.5, 103.5, 2.4, fill: const Color(0xFFFFFFFF)),
  ]),
  _stroke('M120 110 Q124 118 118 120', c.skinShade, 2.4, opacity: 0.7),
  if (c.openMouth) ...[
    _fill(
      'M103 127 Q120 150 137 127 Q120 135 103 127 Z',
      const Color(0xFF8A3B30),
    ),
    _fill('M108 131 Q120 139 132 131', const Color(0xFFFFFFFF), opacity: 0.85),
  ] else
    _stroke('M105 129 Q120 143 135 129', const Color(0xFF8A3B30), 4),
  if (c.freckles) ...[
    for (final p in const [
      [90.0, 120.0],
      [97.0, 123.0],
      [84.0, 124.0],
      [150.0, 120.0],
      [143.0, 123.0],
      [156.0, 124.0],
    ])
      _circle(p[0], p[1], 1.6, fill: c.skinShade, opacity: 0.7),
  ],
  if (c.glasses) ...[
    _rrect(
      87,
      97,
      27,
      21,
      9,
      fill: const Color(0x1FFFFFFF),
      stroke: const Color(0xFF241C18),
      strokeWidth: 3,
    ),
    _rrect(
      126,
      97,
      27,
      21,
      9,
      fill: const Color(0x1FFFFFFF),
      stroke: const Color(0xFF241C18),
      strokeWidth: 3,
    ),
    _stroke('M114 105 h12', const Color(0xFF241C18), 3),
  ],
];

List<AvatarNode> _topAccessory(_Cfg c) {
  if (c.hair == _Hair.bun) {
    return [
      _circle(120, 42, 17, fill: c.hairColor),
      _circle(
        120,
        42,
        17,
        stroke: c.hairDark ?? const Color(0x22000000),
        strokeWidth: 2,
        opacity: 0.4,
      ),
    ];
  }
  if (c.cap != null) {
    return [
      _fill('M70 88 Q120 42 170 88 Q120 76 70 88 Z', c.cap!),
      _fill('M150 88 Q186 84 190 100 Q160 102 148 92 Z', c.capDark!),
      _circle(120, 52, 4.5, fill: c.capDark!),
    ];
  }
  return const [];
}

List<AvatarNode> _earrings(_Cfg c) => c.earrings
    ? [
        _circle(
          71,
          130,
          4.5,
          stroke: const Color(0xFFE8B94A),
          strokeWidth: 2.4,
        ),
        _circle(
          169,
          130,
          4.5,
          stroke: const Color(0xFFE8B94A),
          strokeWidth: 2.4,
        ),
      ]
    : const [];

List<AvatarNode> _body(_Cfg c) => [
  _fill('M108 140 h24 v20 h-24 Z', c.skin),
  _fill(
    'M52 200 C56 166 86 150 120 150 C154 150 184 166 188 200 '
    'L188 212 L52 212 Z',
    c.top,
  ),
  _fill(
    'M96 152 C104 172 136 172 144 152 L152 150 C150 176 90 176 88 150 Z',
    c.topDark,
  ),
  _fill('M110 152 L120 176 L130 152 Z', const Color(0xFFFFFFFF)),
  _stroke('M115 156 C115 172 118 182 118 196', c.topDark, 3),
  _stroke('M125 156 C125 172 122 182 122 196', c.topDark, 3),
];

AvatarNode _arm(_Cfg c) => AvatarGroup(AvatarMotion.arm, [
  _stroke('M174 182 C190 176 202 152 198 126', c.top, 22),
  _circle(198, 120, 15, fill: c.skin),
  _stroke('M190 112 v-9 M198 110 v-11 M206 112 v-9', c.skin, 7),
]);

List<AvatarNode> _arcOverhead(Color color) => [
  // Dashed to a dotted trail, exactly as the wordmark's arc is drawn.
  AvatarShape(
    path: _dashed(parseSvgPath('M74 58 Q120 34 166 56'), 0.1, 11),
    stroke: color,
    strokeWidth: 4.5,
    opacity: 0.45,
  ),
  _stroke('M166 56 l-11 -2 M166 56 l-3 11', color, 4.5, opacity: 0.45),
];

/// Flutter has no `stroke-dasharray`, so the dashes are cut into the path
/// itself. A round cap on a near-zero-length dash is what makes each one a dot.
Path _dashed(Path source, double on, double off) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      out.addPath(
        metric.extractPath(distance, (distance + on).clamp(0, metric.length)),
        Offset.zero,
      );
      distance += on + off;
    }
  }
  return out;
}

// ── Assembly ─────────────────────────────────────────────────────────────────

GiggreAvatarArt _standard(_Cfg c) => GiggreAvatarArt(
  id: c.id,
  name: c.name,
  move: c.move,
  tile: c.tile,
  arc: c.arc,
  timing: c.timing,
  scene: [
    ..._arcOverhead(c.arc),
    AvatarGroup(AvatarMotion.body, [
      ..._body(c),
      AvatarGroup(AvatarMotion.head, [
        ..._ears(c),
        _ellipse(120, 108, 50, 54, c.skin),
        ..._hairBack(c),
        ..._hairMain(c),
        ..._face(c),
        ..._topAccessory(c),
        ..._earrings(c),
      ]),
      if (c.wave) _arm(c),
    ]),
  ],
);

/// Mara is drawn separately in the design — loose strands either side, a
/// different hairline and lashes — so she keeps her own assembly rather than
/// growing four more flags on the shared one.
GiggreAvatarArt _mara(_Cfg c) {
  final hair = c.hairColor;
  final hairDark = c.hairDark!;
  return GiggreAvatarArt(
    id: c.id,
    name: c.name,
    move: c.move,
    tile: c.tile,
    arc: c.arc,
    timing: c.timing,
    scene: [
      ..._arcOverhead(c.arc),
      AvatarGroup(AvatarMotion.body, [
        ..._body(c),
        AvatarGroup(AvatarMotion.strandLeft, [
          _fill('M70 96 C58 118 60 140 68 156 C74 142 74 118 78 100 Z', hair),
        ]),
        AvatarGroup(AvatarMotion.strandRight, [
          _fill(
            'M170 96 C182 118 180 140 172 156 C166 142 166 118 162 100 Z',
            hair,
          ),
        ]),
        AvatarGroup(AvatarMotion.head, [
          _ellipse(71, 116, 8, 11, c.skin),
          _ellipse(169, 116, 8, 11, c.skin),
          _circle(71, 126, 2.4, fill: const Color(0xFFE8B94A)),
          _circle(169, 126, 2.4, fill: const Color(0xFFE8B94A)),
          _fill(
            'M68 150 Q62 92 120 88 Q178 92 172 150 Q120 130 68 150 Z',
            hair,
          ),
          _ellipse(120, 109, 51, 53, c.skin),
          _fill(
            'M66 106 Q60 54 120 48 Q180 54 174 106 Q168 88 150 92 '
            'Q150 76 120 76 Q90 76 90 92 Q72 88 66 106 Z',
            hair,
          ),
          _ellipse(90, 124, 9, 5.5, c.blush, opacity: 0.4),
          _ellipse(150, 124, 9, 5.5, c.blush, opacity: 0.4),
          _stroke('M89 93 Q101 87 112 92', c.browColor, 4),
          _stroke('M128 92 Q139 87 151 93', c.browColor, 4),
          AvatarGroup(AvatarMotion.eyes, [
            _ellipse(101, 108, 7.5, 8.8, const Color(0xFF3A2B22)),
            _ellipse(139, 108, 7.5, 8.8, const Color(0xFF3A2B22)),
            _circle(103.5, 104.5, 2.5, fill: const Color(0xFFFFFFFF)),
            _circle(141.5, 104.5, 2.5, fill: const Color(0xFFFFFFFF)),
            _stroke(
              'M93 103 l-4 -3 M109 103 l4 -3',
              const Color(0xFF3A2B22),
              2.4,
            ),
            _stroke(
              'M131 103 l-4 -3 M147 103 l4 -3',
              const Color(0xFF3A2B22),
              2.4,
            ),
          ]),
          _stroke('M120 111 Q124 118 118 120', c.skinShade, 2.2, opacity: 0.7),
          _stroke('M105 130 Q120 145 135 130', const Color(0xFF8A3B30), 4),
          _circle(120, 44, 17, fill: hair),
          _stroke('M108 40 Q120 34 132 40', hairDark, 2.4, opacity: 0.5),
          _stroke('M110 50 Q120 56 130 50', hairDark, 2.4, opacity: 0.5),
        ]),
        _arm(c),
      ]),
    ],
  );
}

// ── The set ──────────────────────────────────────────────────────────────────

const _configs = <_Cfg>[
  _Cfg(
    id: 'kai',
    name: 'Kai',
    move: 'Waves hello',
    skin: Color(0xFFF1C7A5),
    skinShade: Color(0xFFE0A87F),
    top: Color(0xFF22406B),
    topDark: Color(0xFF183253),
    hair: _Hair.short,
    hairColor: Color(0xFF2A2320),
    browColor: Color(0xFF2A2320),
    blush: Color(0xFFF7A81B),
    tile: Color(0xFFD9EDFB),
    arc: Color(0xFFF7A81B),
    wave: true,
    openMouth: true,
    timing: AvatarTiming(
      bobDuration: 3.2,
      bobDelay: 0,
      blinkDuration: 4.4,
      blinkDelay: 0.2,
      swayDuration: 5.6,
    ),
  ),
  _Cfg(
    id: 'mara',
    name: 'Mara',
    move: 'Head tilt & wave',
    skin: Color(0xFFEAB48E),
    skinShade: Color(0xFFD89A6E),
    top: Color(0xFFF19A1B),
    topDark: Color(0xFFD9820C),
    hair: _Hair.bun,
    hairColor: Color(0xFF6B4A2F),
    hairDark: Color(0xFF513723),
    browColor: Color(0xFF5A3D26),
    blush: Color(0xFFE8693E),
    tile: Color(0xFFFDE7C2),
    arc: Color(0xFF2379BE),
    timing: AvatarTiming(
      bobDuration: 3.8,
      bobDelay: 0.4,
      blinkDuration: 5.1,
      blinkDelay: 1.1,
      swayDuration: 6.4,
    ),
  ),
  _Cfg(
    id: 'theo',
    name: 'Theo',
    move: 'Blinks & breathes',
    skin: Color(0xFFC98B5F),
    skinShade: Color(0xFFB0754B),
    top: Color(0xFF2AA79B),
    topDark: Color(0xFF1F8B80),
    hair: _Hair.short,
    hairColor: Color(0xFF161616),
    browColor: Color(0xFF161616),
    blush: Color(0xFFF7A81B),
    glasses: true,
    tile: Color(0xFFD9EDFB),
    arc: Color(0xFFF7A81B),
    timing: AvatarTiming(
      bobDuration: 3.5,
      bobDelay: 0.8,
      blinkDuration: 4.0,
      blinkDelay: 0.5,
      swayDuration: 6.0,
    ),
  ),
  _Cfg(
    id: 'sana',
    name: 'Sana',
    move: 'Soft sway',
    skin: Color(0xFFE9B78E),
    skinShade: Color(0xFFD69C6E),
    top: Color(0xFFB23A2E),
    topDark: Color(0xFF8E2C22),
    hair: _Hair.scarf,
    hairColor: Color(0xFFE06A4A),
    hairDark: Color(0xFFC9583B),
    browColor: Color(0xFF5A3D26),
    blush: Color(0xFFE8693E),
    tile: Color(0xFFFDE7C2),
    arc: Color(0xFF2379BE),
    timing: AvatarTiming(
      bobDuration: 4.0,
      bobDelay: 0.2,
      blinkDuration: 5.4,
      blinkDelay: 1.6,
      swayDuration: 6.8,
    ),
  ),
  _Cfg(
    id: 'leo',
    name: 'Leo',
    move: 'Peppy bob',
    skin: Color(0xFFF1C7A5),
    skinShade: Color(0xFFE0A87F),
    top: Color(0xFF3E6DA6),
    topDark: Color(0xFF2E5688),
    hair: _Hair.short,
    hairColor: Color(0xFF8A5A2C),
    browColor: Color(0xFF8A5A2C),
    blush: Color(0xFFF7A81B),
    cap: Color(0xFF2379BE),
    capDark: Color(0xFF1B5E96),
    freckles: true,
    tile: Color(0xFFD9EDFB),
    arc: Color(0xFFF7A81B),
    timing: AvatarTiming(
      bobDuration: 3.0,
      bobDelay: 0.6,
      blinkDuration: 4.7,
      blinkDelay: 0.9,
      swayDuration: 5.2,
    ),
  ),
  _Cfg(
    id: 'nia',
    name: 'Nia',
    move: 'Bright & bubbly',
    skin: Color(0xFF8C5A3B),
    skinShade: Color(0xFF754A30),
    top: Color(0xFFF2901C),
    topDark: Color(0xFFDA7C0D),
    hair: _Hair.afro,
    hairColor: Color(0xFF241C18),
    browColor: Color(0xFF241C18),
    blush: Color(0xFFE8693E),
    earrings: true,
    openMouth: true,
    tile: Color(0xFFFDE7C2),
    arc: Color(0xFF2379BE),
    timing: AvatarTiming(
      bobDuration: 3.6,
      bobDelay: 1.0,
      blinkDuration: 4.9,
      blinkDelay: 0.3,
      swayDuration: 6.2,
    ),
  ),
];

/// Built once on first use — parsing the paths for six characters is cheap but
/// there is no reason to repeat it per widget.
final List<GiggreAvatarArt> kGiggreAvatars = List.unmodifiable([
  for (final c in _configs) c.id == 'mara' ? _mara(c) : _standard(c),
]);

final Map<String, GiggreAvatarArt> _byId = {
  for (final a in kGiggreAvatars) a.id: a,
};

/// The avatar stored under [id], or null if the id is unknown — a character
/// retired after someone picked it, or a value from a newer build.
GiggreAvatarArt? giggreAvatarById(String? id) => id == null ? null : _byId[id];
