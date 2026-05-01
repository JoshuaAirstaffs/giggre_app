import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Quick Gig Power Button
// ─────────────────────────────────────────────────────────────────────────────
class QuickGigPowerButton extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  final String isVerified;
  const QuickGigPowerButton({super.key, required this.active, required this.onChanged, required this.isVerified});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    const green = Color(0xFF22C55E);
    final activeColor = active ? green : kSub;

    return GestureDetector(
      onTap: () {
        if (isVerified == 'verified') {
          onChanged(!active);
        } else {
          _showModal(context);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: active ? green.withValues(alpha: 0.07) : cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? green.withValues(alpha: 0.5) : divider,
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: green.withValues(alpha: 0.3),
                          blurRadius: 14,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                color: activeColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Quick Gigs',
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    active
                        ? 'Quick Gig: On — waiting for nearby gigs...'
                        : 'Tap to go online and receive quick gig offers',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: activeColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                active ? 'ON' : 'OFF',
                style: TextStyle(
                    color: activeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showModal(
  BuildContext context, 
) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ( Colors.red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Account not Verified',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account needs to be verified before you can continue. Please request verification from the admin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:  Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}