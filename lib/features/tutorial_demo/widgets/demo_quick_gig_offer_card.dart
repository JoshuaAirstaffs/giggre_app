import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_host.dart';
import 'demo_theme.dart';

/// Visual fork of the real Quick Gig dispatch offer card
/// (`DispatchOfferCard`), matching its layout, copy, and "Pass"/"Take It"
/// button labels exactly. The real widget reads a live Firestore config doc
/// and calls the device's GPS via `Geolocator` — both are real I/O this
/// feature must never trigger, so this redraws the same look purely from
/// mock data and a local animation.
class DemoQuickGigOfferCard extends StatefulWidget {
  final MockGigData gig;
  final Duration countdown;

  const DemoQuickGigOfferCard({
    super.key,
    required this.gig,
    this.countdown = const Duration(seconds: 30),
  });

  @override
  State<DemoQuickGigOfferCard> createState() => _DemoQuickGigOfferCardState();
}

class _DemoQuickGigOfferCardState extends State<DemoQuickGigOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.countdown,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gig = widget.gig;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAmber.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kAmber.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  color: kAmber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Gig Offer!',
                      style: TextStyle(
                        color: kAmber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      gig.title,
                      style: const TextStyle(
                        color: dTitle,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final remaining = 1 - _controller.value;
                  final seconds = (remaining * widget.countdown.inSeconds)
                      .ceil();
                  final timerColor = remaining > 0.66
                      ? const Color(0xFF22C55E)
                      : remaining > 0.33
                      ? kAmber
                      : Colors.redAccent;
                  return Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: timerColor, width: 2),
                      color: timerColor.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Text(
                        '$seconds',
                        style: TextStyle(
                          color: timerColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: dBorder),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: dBody, size: 14),
              const SizedBox(width: 6),
              Text(mockMariaSantos.name, style: const TextStyle(color: dBody, fontSize: 12)),
              const SizedBox(width: 16),
              Text(
                '\$${gig.payment}',
                style: const TextStyle(
                  color: kAmber,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: dBody, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gig.location,
                  style: const TextStyle(color: dBody, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.social_distance_outlined, color: dBody, size: 14),
              const SizedBox(width: 6),
              Text(
                '${gig.distanceMiles} mi away',
                style: const TextStyle(color: dBody, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            gig.description,
            style: const TextStyle(color: dBody, fontSize: 12, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: dBody,
                    side: const BorderSide(color: dBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Pass',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFF22C55E),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Take It',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
