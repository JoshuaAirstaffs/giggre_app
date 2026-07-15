import 'package:flutter/material.dart';

const _kBg = Color(0xFFF4F6FA);
const _kBlue = Color(0xFF2B6FB5);
const _kTitle = Color(0xFF17263D);
const _kBody = Color(0xFF94A0B0);

// ─────────────────────────────────────────────────────────────────────────────
//  Browse tab placeholder — full gig search isn't built yet.
// ─────────────────────────────────────────────────────────────────────────────
class BrowsePlaceholder extends StatelessWidget {
  final VoidCallback onGoToDashboard;

  const BrowsePlaceholder({super.key, required this.onGoToDashboard});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search_rounded,
                      color: _kBlue, size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Browse gigs',
                  style: TextStyle(
                    color: _kTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: const Text(
                    'Full gig search is coming soon. For now, find gigs near '
                    'you from your dashboard.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kBody,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: onGoToDashboard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kBlue,
                    side: const BorderSide(color: _kBlue),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Go to dashboard',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
