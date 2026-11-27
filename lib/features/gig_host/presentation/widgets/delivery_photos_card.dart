import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/delivery_photo_service.dart';
import '../../../gig_shared/active_gig_theme.dart';

/// The pick-up and drop-off photos of a delivery gig, for the host. Live:
/// a photo appears as soon as the worker's upload lands. Covers both
/// single-worker gigs (photos on the gig doc) and multi-worker gigs (one row
/// per worker, from workers/{uid}). Renders nothing until a photo exists.
class DeliveryPhotosCard extends StatefulWidget {
  final String collection;
  final String gigId;
  final EdgeInsetsGeometry margin;

  const DeliveryPhotosCard({
    super.key,
    required this.collection,
    required this.gigId,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  State<DeliveryPhotosCard> createState() => _DeliveryPhotosCardState();
}

class _DeliveryPhotosCardState extends State<DeliveryPhotosCard> {
  Map<String, dynamic>? _gig;
  List<Map<String, dynamic>> _slots = const [];
  StreamSubscription? _gigSub;
  StreamSubscription? _slotSub;

  @override
  void initState() {
    super.initState();
    final ref = FirebaseFirestore.instance
        .collection(widget.collection)
        .doc(widget.gigId);
    _gigSub = ref.snapshots().listen((s) {
      if (mounted) setState(() => _gig = s.data());
    }, onError: (_) {});
    _slotSub = ref.collection('workers').snapshots().listen((s) {
      if (mounted) setState(() => _slots = s.docs.map((d) => d.data()).toList());
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _gigSub?.cancel();
    _slotSub?.cancel();
    super.dispose();
  }

  static bool _hasAny(Map<String, dynamic>? d) =>
      d != null &&
      DeliveryPhotoKind.values.any((k) => d[k.atField] != null);

  @override
  Widget build(BuildContext context) {
    final rows = <Map<String, dynamic>>[
      if (_hasAny(_gig)) _gig!,
      ..._slots.where(_hasAny),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showNames = rows.length > 1;

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: activeGigCardBg(isDark),
        borderRadius: BorderRadius.circular(kActiveGigCardRadius),
        border: Border.all(color: activeGigCardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DELIVERY PHOTOS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: activeGigTextMuted(isDark),
            ),
          ),
          for (final d in rows) ...[
            const SizedBox(height: 10),
            if (showNames)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  (d['workerName'] as String?)?.trim().isNotEmpty == true
                      ? d['workerName'] as String
                      : 'Worker',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: activeGigTextPrimary(isDark),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _PhotoTile(
                    data: d,
                    kind: DeliveryPhotoKind.pickup,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PhotoTile(
                    data: d,
                    kind: DeliveryPhotoKind.dropoff,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final DeliveryPhotoKind kind;
  final bool isDark;

  const _PhotoTile({
    required this.data,
    required this.kind,
    required this.isDark,
  });

  String get _label =>
      kind == DeliveryPhotoKind.pickup ? 'Pick-up' : 'Drop-off';

  @override
  Widget build(BuildContext context) {
    final url = data[kind.urlField] as String?;
    final takenAt = (data[kind.atField] as Timestamp?)?.toDate();
    final status = data[kind.statusField] as String?;

    final Widget body;
    if (url != null && url.isNotEmpty) {
      body = GestureDetector(
        onTap: () => _openFull(context, url),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, _) => _placeholder(Icons.image_outlined, null),
          errorWidget: (_, _, _) =>
              _placeholder(Icons.broken_image_outlined, "Couldn't load"),
        ),
      );
    } else if (takenAt == null) {
      body = _placeholder(Icons.photo_camera_outlined, 'Not yet');
    } else if (status == 'failed') {
      body = _placeholder(Icons.cloud_off_outlined, "Photo didn't upload");
    } else {
      body = _placeholder(Icons.cloud_upload_outlined, 'Uploading…');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 1, child: body),
        ),
        const SizedBox(height: 6),
        Text(
          _label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: activeGigTextPrimary(isDark),
          ),
        ),
        if (takenAt != null)
          Text(
            TimeOfDay.fromDateTime(takenAt).format(context),
            style: TextStyle(fontSize: 11.5, color: activeGigTextMuted(isDark)),
          ),
      ],
    );
  }

  Widget _placeholder(IconData icon, String? text) => Container(
    color: activeGigTrackBg(isDark).withValues(alpha: 0.5),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: activeGigTextMuted(isDark), size: 26),
        if (text != null) ...[
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: activeGigTextMuted(isDark)),
          ),
        ],
      ],
    ),
  );

  void _openFull(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.of(dialogContext).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
