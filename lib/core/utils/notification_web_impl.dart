// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> showBrowserNotification(String title, String body, [String? icon]) async {
  if (!html.Notification.supported) return;

  void fire() {
    html.Notification(
      title,
      body: body,
      icon: icon,
    );
  }

  if (html.Notification.permission == 'granted') {
    fire();
  } else if (html.Notification.permission != 'denied') {
    final permission = await html.Notification.requestPermission();
    if (permission == 'granted') fire();
  }
}
