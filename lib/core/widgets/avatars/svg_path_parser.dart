import 'dart:ui';

/// Minimal SVG path-data parser — exactly what the avatar art uses and no
/// more: `M m L l H h V v C c Q q Z z`.
///
/// Arcs and the smooth/shorthand curve commands are deliberately absent. The
/// art does not use them, and a parser that quietly skipped a command it did
/// not understand would drop a limb and leave no trace, so anything else
/// throws.
///
/// Exists so the character art can carry the `d` strings from the design
/// verbatim. Retyping them as `lineTo`/`cubicTo` calls would be one transcription
/// error per curve, in art nobody can proofread by reading the code.
Path parseSvgPath(String d) {
  final path = Path();
  var current = Offset.zero;
  var subpathStart = Offset.zero;

  for (final match in _command.allMatches(d)) {
    final letter = match.group(1)!;
    final args = [
      for (final n in _number.allMatches(match.group(2) ?? ''))
        double.parse(n.group(0)!),
    ];
    final relative = letter == letter.toLowerCase();
    var op = letter.toUpperCase();

    if (op == 'Z') {
      path.close();
      current = subpathStart;
      continue;
    }

    final arity = _arity[op];
    if (arity == null) {
      throw FormatException('Unsupported path command "$letter" in "$d"');
    }
    if (args.isEmpty || args.length % arity != 0) {
      throw FormatException(
        '"$letter" takes a multiple of $arity numbers, got ${args.length}'
        ' in "$d"',
      );
    }

    for (var i = 0; i < args.length; i += arity) {
      final a = args.sublist(i, i + arity);
      Offset point(int index) {
        final p = Offset(a[index], a[index + 1]);
        return relative ? current + p : p;
      }

      switch (op) {
        case 'M':
          current = point(0);
          path.moveTo(current.dx, current.dy);
          subpathStart = current;
          // A second coordinate pair after a moveto is a lineto, per the
          // spec — the art relies on this in the hair and body outlines.
          op = 'L';
        case 'L':
          current = point(0);
          path.lineTo(current.dx, current.dy);
        case 'H':
          current = Offset(relative ? current.dx + a[0] : a[0], current.dy);
          path.lineTo(current.dx, current.dy);
        case 'V':
          current = Offset(current.dx, relative ? current.dy + a[0] : a[0]);
          path.lineTo(current.dx, current.dy);
        case 'Q':
          final control = point(0);
          current = point(2);
          path.quadraticBezierTo(
            control.dx,
            control.dy,
            current.dx,
            current.dy,
          );
        case 'C':
          final c1 = point(0);
          final c2 = point(2);
          current = point(4);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
      }
    }
  }
  return path;
}

/// One command letter and the run of numbers after it. Unsupported letters are
/// captured too, so the parser can name them when it throws rather than
/// silently swallowing the rest of the string.
final _command = RegExp(r'([A-Za-z])([^A-Za-z]*)');

final _number = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?');

const _arity = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'Q': 4, 'C': 6};
