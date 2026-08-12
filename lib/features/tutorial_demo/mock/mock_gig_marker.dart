import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../gig_worker/presentation/widgets/gig_map_section.dart' show GigMarkerData;
import 'mock_gig.dart';

/// Builds a local, throwaway [GigMarkerData] value object from mock demo
/// data so the demo can reuse the real (pure, data-in/callback-out)
/// `OfferedGigOfferCard` / `GigAssignedDialog` widgets. `GigMarkerData` is
/// just a value class — building one here never touches Firestore.
const _manila = LatLng(14.5995, 120.9842);

GigMarkerData mockGigMarker(MockGigData gig, {required String hostName}) {
  return GigMarkerData(
    id: 'demo-${gig.gigType}',
    title: gig.title,
    gigType: gig.gigType,
    budget: gig.payment.toDouble(),
    currencyCode: gig.currencyCode,
    status: gig.status,
    hostName: hostName,
    address: gig.location,
    position: _manila,
    experienceLevel: '',
    requiredSkills: gig.requiredSkill != null ? [gig.requiredSkill!] : const [],
    hostId: 'demo-host',
  );
}
