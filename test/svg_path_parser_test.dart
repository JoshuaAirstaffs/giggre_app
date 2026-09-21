import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/core/widgets/avatars/svg_path_parser.dart';

void main() {
  test('absolute line commands trace the box they describe', () {
    final p = parseSvgPath('M 10 20 L 30 20 L 30 40 Z');
    expect(p.getBounds(), const Rect.fromLTRB(10, 20, 30, 40));
  });

  test('relative commands accumulate from the current point', () {
    // The body shape uses exactly this form: M, h, v, h, Z.
    final p = parseSvgPath('M108 140 h24 v20 h-24 Z');
    expect(p.getBounds(), const Rect.fromLTRB(108, 140, 132, 160));
  });

  test('a repeated coordinate pair after moveto is a lineto', () {
    final implicit = parseSvgPath('M0 0 10 0 10 10');
    final explicit = parseSvgPath('M0 0 L10 0 L10 10');
    expect(implicit.getBounds(), explicit.getBounds());
  });

  test('curve control points land where the d string puts them', () {
    // getBounds is the control-point hull rather than the tight curve, which
    // makes it a direct read-out of where the controls were parsed to.
    final q = parseSvgPath('M105 129 Q120 143 135 129');
    expect(q.getBounds(), const Rect.fromLTRB(105, 129, 135, 143));

    final c = parseSvgPath('M174 182 C190 176 202 152 198 126');
    expect(c.getBounds(), const Rect.fromLTRB(174, 126, 202, 182));

    // Relative curves offset from the current point, not the origin.
    final rel = parseSvgPath('M100 100 c10 -10 20 -10 30 0');
    expect(rel.getBounds(), const Rect.fromLTRB(100, 90, 130, 100));
  });

  test('a close returns the pen to the start of the subpath', () {
    final p = parseSvgPath('M0 0 L10 0 L10 10 Z L -5 0');
    expect(p.getBounds().left, closeTo(-5, 0.01));
  });

  test('negative and decimal runs split without separators', () {
    final p = parseSvgPath('M166 56 l-11 -2 M166 56 l-3 11');
    expect(p.getBounds(), const Rect.fromLTRB(155, 54, 166, 67));
  });

  test('an unsupported command is reported, not skipped', () {
    expect(
      () => parseSvgPath('M0 0 A 10 10 0 0 1 20 20'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a wrong argument count is reported', () {
    expect(() => parseSvgPath('M0 0 L 10'), throwsA(isA<FormatException>()));
  });
}
