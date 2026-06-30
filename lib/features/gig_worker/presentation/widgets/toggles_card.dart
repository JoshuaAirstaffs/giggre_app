import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  TogglesCard — 2-column: Quick Gigs + Auto Accept
//  Availability toggle lives in the hero card in gig_worker_screen.dart.
// ─────────────────────────────────────────────────────────────────────────────
class TogglesCard extends StatelessWidget {
  final bool seekingQuickGigs;
  final bool autoAccept;
  final ValueChanged<bool> onQuickGigsChanged;
  final ValueChanged<bool> onAutoAcceptChanged;
  final String isVerified;

  const TogglesCard({
    super.key,
    required this.seekingQuickGigs,
    required this.autoAccept,
    required this.onQuickGigsChanged,
    required this.onAutoAcceptChanged,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ToggleCard(
            icon: Icons.power_settings_new_rounded,
            iconBg: kSub.withValues(alpha: 0.12),
            iconColor: kSub,
            label: 'Quick Gigs',
            description: 'Go online to receive quick gig offers near you',
            value: seekingQuickGigs,
            activeColor: const Color(0xFF2BB673),
            onChanged: (v) {
              if (isVerified == 'verified') {
                onQuickGigsChanged(v);
              } else {
                _showModal(context);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToggleCard(
            icon: Icons.bolt_rounded,
            iconBg: kGold.withValues(alpha: 0.12),
            iconColor: kGold,
            label: 'Auto Accept',
            description: 'Gigs matching your skills are auto accepted',
            value: autoAccept,
            activeColor: kGold,
            onChanged: (v) {
              if (isVerified == 'verified') {
                onAutoAcceptChanged(v);
              } else {
                _showModal(context);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String description;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: activeColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: onSurface,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(color: kSub, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Verification required dialog (preserved from original)
// ─────────────────────────────────────────────────────────────────────────────
void _showModal(BuildContext context) {
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
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Account not Verified',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account needs to be verified before you can continue. '
            'Please request verification from the admin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child:
                  const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}
