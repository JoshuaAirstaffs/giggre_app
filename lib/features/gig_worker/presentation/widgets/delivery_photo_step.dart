import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/delivery_photo_service.dart';
import '../../../gig_shared/active_gig_theme.dart';

/// The photo a worker must take before moving a delivery gig on: of the item
/// at the pick-up (before Start Gig) and of it handed over at the drop-off
/// (before Gig Complete). Opens the camera straight away, then shows the shot
/// with Retake / confirm. Returns the photo, or null if they backed out — the
/// caller then leaves the status as it was.
Future<File?> showDeliveryPhotoStep(
  BuildContext context, {
  required DeliveryPhotoKind kind,
}) async {
  final first = await _captureOrExplain(context);
  if (first == null || !context.mounted) return null;
  return showModalBottomSheet<File>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeliveryPhotoSheet(kind: kind, initial: first),
  );
}

Future<File?> _captureOrExplain(BuildContext context) async {
  try {
    return await DeliveryPhotoService.capture();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't open the camera. Allow camera access for Giggre in your phone's Settings, then try again.",
          ),
        ),
      );
    }
    return null;
  }
}

class _DeliveryPhotoSheet extends StatefulWidget {
  final DeliveryPhotoKind kind;
  final File initial;
  const _DeliveryPhotoSheet({required this.kind, required this.initial});

  @override
  State<_DeliveryPhotoSheet> createState() => _DeliveryPhotoSheetState();
}

class _DeliveryPhotoSheetState extends State<_DeliveryPhotoSheet> {
  late File _photo = widget.initial;

  bool get _isPickup => widget.kind == DeliveryPhotoKind.pickup;

  Future<void> _retake() async {
    final shot = await _captureOrExplain(context);
    if (shot != null && mounted) setState(() => _photo = shot);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = kWorkerAccent.solid;

    return Container(
      decoration: BoxDecoration(
        color: activeGigCardBg(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: activeGigDividerColor(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isPickup ? 'Item picked up' : 'Item delivered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: activeGigTextPrimary(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isPickup
                ? 'Make sure the item is clear in the photo. The host will see it.'
                : 'Show the item at the drop-off. The host will see it.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: activeGigTextSecondary(isDark),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: Image.file(
                _photo,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: activeGigTextPrimary(isDark),
                    side: BorderSide(color: activeGigCardBorder(isDark)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_photo),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPickup ? accent : kActiveGigSuccessGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isPickup ? 'Start delivery' : 'Mark as delivered',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
