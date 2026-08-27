import 'package:cloud_functions/cloud_functions.dart';

// Mints a real Agora token via the generateAgoraToken Cloud Function — see
// functions/src/index.ts. Needed because this Agora project now has a
// Primary Certificate configured, so joining a channel with an empty token
// (the old default everywhere calls were started) crashes the native SDK
// instead of failing gracefully.
class AgoraTokenService {
  static Future<String> generateToken(String channelName) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-east2')
        .httpsCallable('generateAgoraToken')
        .call({'channelName': channelName});
    return result.data['token'] as String;
  }
}
