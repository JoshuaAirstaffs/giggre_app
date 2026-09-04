import Flutter
import UIKit
import GoogleMaps
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyBq12naV0Iosi7mAZMsXJNUd4RDM1Cnt98")
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // FirebaseMessaging normally does this itself in response to
    // UIApplicationDidFinishLaunchingNotification, but that fires as soon as this
    // method returns — with the implicit-engine plugin registration path, Firebase's
    // observer isn't guaranteed to be attached in time to catch it, so the device
    // never completes APNs registration. Call it directly so it isn't lost to that race.
    application.registerForRemoteNotifications()

    // firebase_messaging and flutter_local_notifications each expect to become
    // UNUserNotificationCenter's delegate via Flutter's cooperative plugin-registrant
    // chain, but under the implicit-engine registration path that chain doesn't
    // reliably wire either one up — foreground pushes then never trigger a visible
    // notification (confirmed via native device logs: willPresentNotification runs,
    // but nothing in either plugin's own handler ever does). Claim the delegate
    // directly instead of relying on that chain. See:
    // https://github.com/MaikuB/flutter_local_notifications/issues/2196
    UNUserNotificationCenter.current().delegate = self

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Claiming this delegate above means firebase_messaging's own handler
    // never runs, so PushNotificationService's onMessage listener (and the
    // custom local notification it would otherwise show — see
    // _showForeground) never fires for a foregrounded push either. Nothing
    // else is showing this notification, so always present it here.
    completionHandler([.banner, .list, .badge, .sound])
  }

  // Same problem as willPresent above, for taps instead of display: claiming
  // this delegate means nothing forwards a notification tap (body or an
  // action button) to flutter_local_notifications/firebase_messaging unless
  // we do it explicitly. Forward to super so Flutter's plugin-registrant
  // chain still gets a chance to run its own handlers.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
