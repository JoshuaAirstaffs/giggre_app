import 'package:cloud_functions/cloud_functions.dart';
import 'package:giggre_app/main.dart' show flavor;

// Functions run in us-central1 on prod and asia-east2 on dev — the same
// split as every other callable (see public_lookup_service.dart). This was
// hardcoded to asia-east2, so prod calls asked a region where the function
// doesn't exist and never got a token.
final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

// Mints a real Agora token via the generateAgoraToken Cloud Function — see
// functions/src/index.ts. Needed because this Agora project now has a
// Primary Certificate configured, so joining a channel with an empty token
// (the old default everywhere calls were started) crashes the native SDK
// instead of failing gracefully.
class AgoraTokenService {
  static Future<String> generateToken(String channelName) async {
    final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
        .httpsCallable('generateAgoraToken')
        .call({'channelName': channelName});
    return result.data['token'] as String;
  }
}
