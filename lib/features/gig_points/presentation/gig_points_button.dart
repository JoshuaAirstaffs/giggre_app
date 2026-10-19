import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../services/gig_points_service.dart';

/// "Gig Points" app-bar button with the user's live balance.
///
/// Styled to sit beside home_screen.dart's `_IconSquareButton`s (profile /
/// logout): same 36px height, card surface, divider border, 10px radius,
/// and plain GestureDetector tap. Navigation is left to the caller via
/// [onTap] so the home screen stays the place that owns routing.
///
/// Layout: label stacked over the balance. On very narrow screens
/// (< [_compactBreakpoint]) the label collapses to a tooltip so the app bar
/// never overflows; text scaling is clamped for the same reason.
class GigPointsButton extends StatefulWidget {
  final VoidCallback onTap;

  const GigPointsButton({super.key, required this.onTap});

  @override
  State<GigPointsButton> createState() => _GigPointsButtonState();
}

const double _compactBreakpoint = 340;

class _GigPointsButtonState extends State<GigPointsButton> {
  Stream<GigPointsBalance>? _stream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _stream = GigPointsService.balanceStream(uid);
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < _compactBreakpoint;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: StreamBuilder<GigPointsBalance>(
        stream: _stream,
        builder: (context, snap) {
          final balance = snap.data?.balance;
          final balanceText = balance == null ? '–' : formatGigPoints(balance);
          final balanceStyle = TextStyle(
            color: onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.1,
          );

          return Tooltip(
            message: 'Gig Points',
            child: Semantics(
              button: true,
              label: balance == null ? 'Gig Points' : 'Gig Points, $balance',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, color: kGold, size: 19),
                      const SizedBox(width: 6),
                      if (compact)
                        Text(balanceText, style: balanceStyle)
                      else
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Gig Points',
                              maxLines: 1,
                              style: TextStyle(
                                color: kSub,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                            Text(balanceText, maxLines: 1, style: balanceStyle),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 950 → "950", 12 400 → "12.4K", 3 200 000 → "3.2M". Keeps the app-bar
/// button a bounded width whatever the balance.
String formatGigPoints(int n) {
  String trim(double v) =>
      v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (n.abs() >= 1000000) return '${trim(n / 1000000)}M';
  if (n.abs() >= 10000) return '${trim(n / 1000)}K';
  return n.toString();
}
