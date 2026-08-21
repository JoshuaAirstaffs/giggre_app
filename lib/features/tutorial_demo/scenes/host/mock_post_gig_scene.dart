import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_gig.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_pulse_highlight.dart';
import '../../widgets/demo_theme.dart';

/// "Host fills in the gig details" scene — reused for Quick/Open/Offered
/// Gig sequences. Fields fade in one after another to look like the host
/// is actively completing the form, then a submit button (its real
/// Giggre label — "Post Quick Gig" / "Post Open Gig" / "Send Offer") gets
/// a simulated press right before the step ends.
class MockPostGigFormScene extends StatelessWidget {
  final String heading;
  final MockGigData gig;
  final String? requiredSkillLabel;
  final String? workerName;
  final String? submitLabel;

  const MockPostGigFormScene({
    super.key,
    required this.heading,
    required this.gig,
    this.requiredSkillLabel,
    this.workerName,
    this.submitLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: const TextStyle(
              color: dTitle,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          if (workerName != null) ...[
            DemoFadeIn(
              child: _field('Worker', workerName!, Icons.person_outline_rounded, highlight: true),
            ),
            const SizedBox(height: 12),
          ],
          DemoFadeIn(
            delay: const Duration(milliseconds: 150),
            child: _field('Title', gig.title, Icons.title_rounded),
          ),
          const SizedBox(height: 12),
          DemoFadeIn(
            delay: const Duration(milliseconds: 500),
            child: _field(
              'Description',
              gig.description,
              Icons.notes_rounded,
              maxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          DemoFadeIn(
            delay: const Duration(milliseconds: 850),
            child: _field(
              'Payment',
              '\$${gig.payment}',
              Icons.payments_outlined,
            ),
          ),
          const SizedBox(height: 12),
          DemoFadeIn(
            delay: const Duration(milliseconds: 1150),
            child: _field(
              'Location',
              gig.location,
              Icons.location_on_outlined,
            ),
          ),
          if (requiredSkillLabel != null) ...[
            const SizedBox(height: 12),
            DemoFadeIn(
              delay: const Duration(milliseconds: 1450),
              child: _field(
                'Required Skill',
                requiredSkillLabel!,
                Icons.build_outlined,
                highlight: true,
              ),
            ),
          ],
          if (submitLabel != null) ...[
            const SizedBox(height: 20),
            DemoFadeIn(
              delay: const Duration(milliseconds: 1750),
              child: DemoTapPulse(
                delay: const Duration(milliseconds: 2300),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            submitLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String value,
    IconData icon, {
    int maxLines = 1,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? kGold : dBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: highlight ? kGold : dMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: dMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlight ? kGold : dTitle,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brief "submitting" transition between the form and the next scene.
class MockPostingScene extends StatelessWidget {
  final String label;
  const MockPostingScene({super.key, this.label = 'Posting your gig…'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(color: kGold, strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: dTitle,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
