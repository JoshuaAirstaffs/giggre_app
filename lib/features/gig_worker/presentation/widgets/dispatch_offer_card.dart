import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'gig_map_section.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Dispatch Offer Card — countdown overlay for incoming quick gigs
//  Countdown duration is driven by review_window_seconds in Firestore:
//  /quick_gig_config/matching_engine
// ─────────────────────────────────────────────────────────────────────────────
class DispatchOfferCard extends StatefulWidget {
  final GigMarkerData gig;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const DispatchOfferCard({
    super.key,
    required this.gig,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<DispatchOfferCard> createState() => _DispatchOfferCardState();
}

class _DispatchOfferCardState extends State<DispatchOfferCard> {
  static const _defaultSeconds = 30;
  static const _configPath = 'quick_gig_config';
  static const _configDoc = 'matching_engine';

  Timer? _timer;
  int _seconds = _defaultSeconds;
  int _total = _defaultSeconds;
  double? _distanceMeters;

  @override
  void initState() {
    super.initState();
    _loadConfigAndStart();
    _loadDistance();
  }

  Future<void> _loadDistance() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _distanceMeters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          widget.gig.position.latitude,
          widget.gig.position.longitude,
        );
      });
    } catch (_) {
      // distance stays hidden
    }
  }

  String _fmtDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  Future<void> _openInGoogleMaps() async {
    final dest = widget.gig.position;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${dest.latitude},${dest.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  Future<void> _loadConfigAndStart() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_configPath)
          .doc(_configDoc)
          .get();
      final reviewWindow =
          (doc.data()?['review_window_seconds'] as num?)?.toInt() ??
              _defaultSeconds;
      if (mounted) {
        setState(() {
          _seconds = reviewWindow;
          _total = reviewWindow;
        });
      }
    } catch (_) {
      // use defaults
    }
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) {
        _timer?.cancel();
        widget.onDecline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF22C55E);

    final timerColor = _seconds > (_total * 0.66).round()
        ? green
        : _seconds > (_total * 0.33).round()
            ? kAmber
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAmber.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kAmber.withValues(alpha: isDark ? 0.2 : 0.15),
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
                child: const Icon(Icons.flash_on_rounded,
                    color: kAmber, size: 22),
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
                          letterSpacing: 0.5),
                    ),
                    Text(
                      widget.gig.title,
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: timerColor, width: 2),
                  color: timerColor.withValues(alpha: 0.1),
                ),
                child: Center(
                  child: Text(
                    '$_seconds',
                    style: TextStyle(
                        color: timerColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: divider),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: kSub, size: 14),
              const SizedBox(width: 6),
              Text(
                widget.gig.hostName.isNotEmpty ? widget.gig.hostName : 'Host',
                style: const TextStyle(color: kSub, fontSize: 12),
              ),
              const SizedBox(width: 16),
              // const Icon(Icons.attach_money_rounded, color: kAmber, size: 14),
              Text(
                CurrencyFormatter.format(widget.gig.budget, widget.gig.currencyCode),
                style: const TextStyle(
                    color: kAmber,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (widget.gig.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: kSub, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.gig.address,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 1
                  ),
                ),
              ],
            ),
          ],
          if (_distanceMeters != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.social_distance_outlined, color: kSub, size: 14),
                const SizedBox(width: 6),
                Text(
                  _fmtDistance(_distanceMeters!),
                  style: const TextStyle(color: kSub, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _openInGoogleMaps,
              style: TextButton.styleFrom(
                foregroundColor: kAmber,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text(
                'View in Google Maps',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kSub,
                    side: BorderSide(color: divider),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept Gig',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
