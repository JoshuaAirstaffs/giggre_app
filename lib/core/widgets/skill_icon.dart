import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/skill_icon_service.dart';

/// A skill's GSIN sub-category icon (see [SkillIconService]).
///
/// Without an icon it shows [fallback]; pass `fallback: null` to draw nothing
/// (for text chips, so every icon-less skill doesn't get the same tool icon).
/// [gap] adds trailing space only when something is drawn.
class SkillIcon extends StatelessWidget {
  final String skillName;
  final double size;
  final Color? color;
  final IconData? fallback;
  final double gap;

  const SkillIcon(
    this.skillName, {
    super.key,
    this.size = 18,
    this.color,
    this.fallback = Icons.handshake_outlined,
    this.gap = 0,
  });

  @override
  Widget build(BuildContext context) {
    final service = SkillIconService.instance;
    service.ensureLoaded();
    final tint = color ?? IconTheme.of(context).color;

    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: service.icons,
      builder: (context, icons, child) {
        final url = service.urlForSkill(skillName);
        final fallbackIcon = fallback == null
            ? null
            : Icon(fallback, size: size, color: tint);

        final Widget? drawn = url != null
            ? SvgPicture.network(
                url,
                width: size,
                height: size,
                colorFilter: tint == null
                    ? null
                    : ColorFilter.mode(tint, BlendMode.srcIn),
                placeholderBuilder: (context) =>
                    SizedBox(width: size, height: size),
                errorBuilder: (context, error, stackTrace) =>
                    fallbackIcon ?? SizedBox(width: size, height: size),
              )
            : fallbackIcon;

        if (drawn == null) return const SizedBox.shrink();
        if (gap <= 0) return drawn;
        return Padding(
          padding: EdgeInsetsDirectional.only(end: gap),
          child: drawn,
        );
      },
    );
  }
}
