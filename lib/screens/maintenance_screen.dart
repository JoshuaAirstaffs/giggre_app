import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import 'app_contents/contact_us.dart';

class MaintenanceScreen extends StatelessWidget {
  final String message;
  final String? startDate;
  final String? endDate;

  const MaintenanceScreen({
    super.key,
    required this.message,
    this.startDate,
    this.endDate,
  });

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedStart = _formatDate(startDate);
    final formattedEnd = _formatDate(endDate);
    final hasWindow = formattedStart.isNotEmpty || formattedEnd.isNotEmpty;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // Background decorative blobs
          Positioned(
            top: -80,
            right: -60,
            child: _DecorativeCircle(
              size: 260,
              color: kBlue.withValues(alpha: 0.08),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: _DecorativeCircle(
              size: 320,
              color: const Color(0xFFBA7517).withValues(alpha: 0.06),
            ),
          ),
          Positioned(
            top: 180,
            left: -40,
            child: _DecorativeCircle(
              size: 140,
              color: kBlue.withValues(alpha: 0.05),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Image.asset(
                      'assets/images/logo.png',
                      height: 40,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 40),

                    // Animated gear illustration with glow
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A2744).withValues(alpha: 0.6),
                        boxShadow: [
                          BoxShadow(
                            color: kBlue.withValues(alpha: 0.18),
                            blurRadius: 60,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: _AnimatedGearIcon(size: 196),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFBA7517).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFBA7517).withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(color: const Color(0xFFFFBF24)),
                          const SizedBox(width: 8),
                          const Text(
                            'Scheduled Maintenance',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFBF24),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      "We'll be right\nback",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Message from Firestore
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: kSub,
                        height: 1.6,
                      ),
                    ),

                    if (hasWindow) ...[
                      const SizedBox(height: 32),
                      _TimeWindowCard(start: formattedStart, end: formattedEnd),
                    ],

                    const SizedBox(height: 40),

                    // Contact support button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: kBorder, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: Icon(Icons.headset_mic_rounded, size: 20, color: kBlue),
                        label: const Text('Contact Support'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContactUs(showTicketsTab: false),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated gear icon ────────────────────────────────────────────────────────

class _AnimatedGearIcon extends StatefulWidget {
  final double size;
  const _AnimatedGearIcon({required this.size});

  @override
  State<_AnimatedGearIcon> createState() => _AnimatedGearIconState();
}

class _AnimatedGearIconState extends State<_AnimatedGearIcon>
    with TickerProviderStateMixin {
  late final AnimationController _largeCtrl;
  late final AnimationController _smallCtrl;

  @override
  void initState() {
    super.initState();
    _largeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _smallCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _largeCtrl.dispose();
    _smallCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final scale = s / 300.0;

    // Original SVG gear centers (from viewBox 0 0 300 300)
    const largeCx = 130.0;
    const largeCy = 160.0;
    const smallCx = 218.0;
    const smallCy = 95.0;

    // Gear sizes: large gear outer extent ≈ 96px, small ≈ 62px (radius)
    final largeSize = 192.0 * scale;
    final smallSize = 124.0 * scale;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        children: [
          // Large gear — clockwise
          Positioned(
            left: largeCx * scale - largeSize / 2,
            top: largeCy * scale - largeSize / 2,
            child: AnimatedBuilder(
              animation: _largeCtrl,
              builder: (_, _) => Transform.rotate(
                angle: _largeCtrl.value * 2 * math.pi,
                child: SizedBox(
                  width: largeSize,
                  height: largeSize,
                  child: SvgPicture.string(_kLargeGearSvg),
                ),
              ),
            ),
          ),

          // Small gear — counter-clockwise
          Positioned(
            left: smallCx * scale - smallSize / 2,
            top: smallCy * scale - smallSize / 2,
            child: AnimatedBuilder(
              animation: _smallCtrl,
              builder: (_, _) => Transform.rotate(
                angle: -_smallCtrl.value * 2 * math.pi,
                child: SizedBox(
                  width: smallSize,
                  height: smallSize,
                  child: SvgPicture.string(_kSmallGearSvg),
                ),
              ),
            ),
          ),

          // Wrench — static, rendered in full 300×300 space
          Positioned.fill(
            child: SvgPicture.string(_kWrenchSvg),
          ),
        ],
      ),
    );
  }
}

// SVG pieces — each gear is centered at (0,0) in its own viewBox so
// Transform.rotate spins it around its own center.

const _kLargeGearSvg = '''
<svg viewBox="-96 -96 192 192" xmlns="http://www.w3.org/2000/svg">
  <circle cx="0" cy="0" r="72" fill="#185FA5"/>
  <circle cx="0" cy="0" r="32" fill="#E6F1FB"/>
  <g fill="#185FA5">
    <rect x="-10" y="-92" width="20" height="24" rx="4"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(30)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(60)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(90)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(120)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(150)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(180)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(210)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(240)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(270)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(300)"/>
    <rect x="-10" y="-92" width="20" height="24" rx="4" transform="rotate(330)"/>
  </g>
  <circle cx="0" cy="0" r="18" fill="#185FA5"/>
  <circle cx="0" cy="0" r="11" fill="#E6F1FB"/>
</svg>
''';

const _kSmallGearSvg = '''
<svg viewBox="-62 -62 124 124" xmlns="http://www.w3.org/2000/svg">
  <circle cx="0" cy="0" r="44" fill="#BA7517"/>
  <circle cx="0" cy="0" r="20" fill="#FAEEDA"/>
  <g fill="#BA7517">
    <rect x="-7" y="-58" width="14" height="17" rx="3"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(45)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(90)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(135)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(180)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(225)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(270)"/>
    <rect x="-7" y="-58" width="14" height="17" rx="3" transform="rotate(315)"/>
  </g>
  <circle cx="0" cy="0" r="12" fill="#BA7517"/>
  <circle cx="0" cy="0" r="7" fill="#FAEEDA"/>
</svg>
''';

const _kWrenchSvg = '''
<svg viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg">
  <g transform="translate(152, 185) rotate(-40)">
    <rect x="-7" y="0" width="14" height="74" rx="6" fill="#0C447C"/>
    <rect x="-21" y="-32" width="42" height="36" rx="6" fill="#0C447C"/>
    <rect x="-12" y="-26" width="24" height="23" rx="4" fill="#E6F1FB"/>
    <rect x="-21" y="-12" width="9" height="14" rx="3" fill="#E6F1FB"/>
    <rect x="12" y="-12" width="9" height="14" rx="3" fill="#E6F1FB"/>
  </g>
</svg>
''';

// ── Supporting widgets ────────────────────────────────────────────────────────

class _TimeWindowCard extends StatelessWidget {
  final String start;
  final String end;

  const _TimeWindowCard({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder, width: 1),
      ),
      child: Column(
        children: [
          Text(
            'MAINTENANCE WINDOW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kSub,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (start.isNotEmpty) Expanded(child: _TimeSlot(label: 'Starts', value: start)),
              if (start.isNotEmpty && end.isNotEmpty)
                Container(
                  width: 1,
                  height: 36,
                  color: kBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
              if (end.isNotEmpty) Expanded(child: _TimeSlot(label: 'Ends', value: end)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeSlot extends StatelessWidget {
  final String label;
  final String value;

  const _TimeSlot({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _DecorativeCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
