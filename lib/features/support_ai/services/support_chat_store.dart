// Giggre AI support — chat history kept on the phone only.
// Cleared after 1 hour of inactivity, and on logout via clearAll().
// Stored per user, so a different account on the same phone never sees it.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SupportMessage {
  const SupportMessage({
    required this.role,
    required this.text,
    this.actions = const [],
  });

  final String role; // 'user' | 'assistant'
  final String text;
  final List<String> actions; // "open this screen" buttons on Gab's reply

  bool get isUser => role == 'user';

  /// Shape the askSupport function expects.
  Map<String, String> toApi() => {'role': role, 'content': text};

  Map<String, dynamic> toJson() => {
    'r': role,
    't': text,
    if (actions.isNotEmpty) 'a': actions,
  };

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    role: json['r'] as String,
    text: json['t'] as String,
    actions: (json['a'] as List?)?.whereType<String>().toList() ?? const [],
  );
}

class SupportChatStore {
  static const idleTimeout = Duration(hours: 1);
  static const _prefix = 'giggre_support_chat_';
  static const _maxStored = 40;

  static String _key(String uid) => '$_prefix$uid';

  /// Returns the saved chat, or an empty list if there is none
  /// or it has been idle for an hour (in which case it is deleted).
  static Future<List<SupportMessage>> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null) return [];

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final lastActivity =
          DateTime.fromMillisecondsSinceEpoch(data['lastActivity'] as int);
      if (DateTime.now().difference(lastActivity) >= idleTimeout) {
        await clear(uid);
        return [];
      }
      return (data['messages'] as List)
          .map((m) =>
              SupportMessage.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (_) {
      await clear(uid);
      return [];
    }
  }

  /// Saves the chat and marks now as the last activity.
  static Future<void> save(String uid, List<SupportMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxStored
        ? messages.sublist(messages.length - _maxStored)
        : messages;
    await prefs.setString(
      _key(uid),
      jsonEncode({
        'lastActivity': DateTime.now().millisecondsSinceEpoch,
        'messages': trimmed.map((m) => m.toJson()).toList(),
      }),
    );
  }

  static Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }

  /// Call this in your logout flow, before FirebaseAuth.signOut().
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
