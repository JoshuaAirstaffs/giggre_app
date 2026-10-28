// Giggre AI support — calls the askSupport Cloud Function.

import 'package:cloud_functions/cloud_functions.dart';

import 'support_chat_store.dart';

class SupportReply {
  const SupportReply({
    required this.answer,
    required this.escalate,
    required this.remaining,
    this.actions = const [],
    this.resetAt,
  });

  final String answer;
  final bool escalate; // true → show "Talk to a person"
  final List<String> actions; // screens to offer as buttons (destination ids)
  final int remaining; // messages left this hour
  final DateTime? resetAt; // when the hourly limit resets
}

/// The user has used all messages for this hour.
class SupportLimitReached implements Exception {
  const SupportLimitReached(this.resetAt);
  final DateTime resetAt;
}

/// Network error, timeout, or the AI could not answer.
class SupportUnavailable implements Exception {
  const SupportUnavailable();
}

class SupportChatService {
  SupportChatService({FirebaseFunctions? functions})
      : _callable = (functions ??
                // Must match askSupport's region (functions/src/askSupport.ts)
                FirebaseFunctions.instanceFor(region: 'asia-southeast1'))
            .httpsCallable(
          'askSupport',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
        );

  final HttpsCallable _callable;
  static const _historyLimit = 10;

  /// [history] is the chat so far, NOT including [message].
  Future<SupportReply> ask({
    required String message,
    required List<SupportMessage> history,
    required String mode, // 'worker' | 'host'
  }) async {
    final recent = history.length > _historyLimit
        ? history.sublist(history.length - _historyLimit)
        : history;

    try {
      final res = await _callable.call({
        'message': message,
        'history': recent.map((m) => m.toApi()).toList(),
        'mode': mode,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return SupportReply(
        answer: data['answer'] as String? ?? '',
        escalate: data['escalate'] == true,
        actions: (data['actions'] as List?)?.whereType<String>().toList() ??
            const [],
        remaining: (data['remaining'] as num?)?.toInt() ?? 0,
        resetAt: _time(data['resetAt']),
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        final details = e.details is Map
            ? Map<String, dynamic>.from(e.details as Map)
            : const <String, dynamic>{};
        throw SupportLimitReached(
          _time(details['resetAt']) ??
              DateTime.now().add(const Duration(hours: 1)),
        );
      }
      throw const SupportUnavailable();
    } catch (_) {
      throw const SupportUnavailable();
    }
  }

  static DateTime? _time(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}
