import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

// ── Local message model ────────────────────────────────────────────────────────
class _Msg {
  final String? id;         // null = optimistic (not yet committed)
  final String text;
  final bool isMe;
  final bool isSupport;
  final bool isAutoReply;
  final bool hasSeenBySupport;
  final DateTime? time;
  final bool pending;       // true while waiting for server

  const _Msg({
    this.id,
    required this.text,
    required this.isMe,
    this.isSupport = false,
    this.isAutoReply = false,
    this.hasSeenBySupport = false,
    this.time,
    this.pending = false,
  });

  _Msg copyWith({String? id, bool? pending, bool? hasSeenBySupport, DateTime? time}) => _Msg(
        id: id ?? this.id,
        text: text,
        isMe: isMe,
        isSupport: isSupport,
        isAutoReply: isAutoReply,
        hasSeenBySupport: hasSeenBySupport ?? this.hasSeenBySupport,
        time: time ?? this.time,
        pending: pending ?? this.pending,
      );
}

// ── Chat screen ────────────────────────────────────────────────────────────────
class Chat extends StatefulWidget {
  final String roomId;
  const Chat({super.key, required this.roomId});

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  static const _pageSize = 20;

  final List<_Msg> _msgs = [];
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Firestore cursor for paginating older messages
  DocumentSnapshot? _oldestDoc;

  // Stream subscription for new incoming messages
  StreamSubscription? _incomingSub;
  StreamSubscription? _seenSub;

  // Track the newest timestamp we've fetched, to avoid stream duplicates
  DateTime? _newestFetchedTime;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference get _messagesRef => FirebaseFirestore.instance
      .collection('chat_rooms')
      .doc(widget.roomId)
      .collection('messages');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
    _markSupportMessagesAsSeen();
    _listenAndMarkSeen();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _seenSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll up → load older ─────────────────────────────────────────────────
  void _onScroll() {
    if (_scrollController.position.pixels <= 100) _loadMore();
  }

  // ── Initial load ───────────────────────────────────────────────────────────
  Future<void> _loadInitial() async {
    try {
      final snap = await _messagesRef
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      final docs = snap.docs.reversed.toList();
      final msgs = docs.map((d) => _docToMsg(d)).toList();

      if (!mounted) return;
      setState(() {
        _msgs.clear();
        _msgs.addAll(msgs);
        _hasMore = snap.docs.length == _pageSize;
        _oldestDoc = docs.isNotEmpty ? docs.first : null;
        _newestFetchedTime = msgs.isNotEmpty ? msgs.last.time : null;
        _isLoadingInitial = false;
      });

      _startIncomingStream();
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } catch (e) {
      debugPrint('Initial load error: $e');
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  // ── Load older messages ────────────────────────────────────────────────────
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _oldestDoc == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final snap = await _messagesRef
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_oldestDoc!)
          .limit(_pageSize)
          .get();

      final docs = snap.docs.reversed.toList();
      final msgs = docs.map((d) => _docToMsg(d)).toList();

      if (!mounted) return;

      final prevExtent = _scrollController.position.maxScrollExtent;

      setState(() {
        // Remove any duplicates before inserting
        final existingIds = _msgs.map((m) => m.id).toSet();
        final fresh = msgs.where((m) => !existingIds.contains(m.id)).toList();
        _msgs.insertAll(0, fresh);
        _hasMore = snap.docs.length == _pageSize;
        if (docs.isNotEmpty) _oldestDoc = docs.first;
        _isLoadingMore = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final diff = _scrollController.position.maxScrollExtent - prevExtent;
          _scrollController.jumpTo(_scrollController.offset + diff);
        }
      });
    } catch (e) {
      debugPrint('Load more error: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // ── Stream: only listen for messages newer than what we fetched ────────────
  void _startIncomingStream() {
    Query q = _messagesRef.orderBy('createdAt', descending: false);

    // Scope stream to only new messages
    if (_newestFetchedTime != null) {
      q = q.where('createdAt',
          isGreaterThan: Timestamp.fromDate(_newestFetchedTime!));
    }

    _incomingSub = q.snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;

      bool changed = false;
      for (final change in snap.docChanges) {
        final msg = _docToMsg(change.doc);

        if (change.type == DocumentChangeType.added) {
          // Skip if it's already in list (e.g. our own optimistic message)
          final existingIdx = _msgs.indexWhere((m) => m.id == msg.id);
          if (existingIdx != -1) continue;

          // Also skip if it matches a pending optimistic message we sent
          final optimisticIdx = _msgs.indexWhere(
            (m) => m.pending && m.isMe && m.text == msg.text,
          );
          if (optimisticIdx != -1) {
            // Replace optimistic with confirmed
            _msgs[optimisticIdx] = msg;
            changed = true;
            continue;
          }

          // It's a new message from support
          if (!msg.isMe) {
            _msgs.add(msg);
            changed = true;
          }
        } else if (change.type == DocumentChangeType.modified) {
          // e.g. hasSeenByAdmin updated
          final idx = _msgs.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _msgs[idx] = msg;
            changed = true;
          }
        }
      }

      if (changed && mounted) {
        setState(() {});
        // Only scroll to bottom if we're already near the bottom
        if (_scrollController.hasClients &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 100) {
          _scrollToBottom();
        }
      }
    });
  }

  // ── Send: optimistic UI ────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    final uid = _uid;
    final name = context.read<CurrentUserProvider>().currentName ?? '';

    // 1. Add optimistic message immediately — no flicker, no wait
    final optimistic = _Msg(
      text: text,
      isMe: true,
      time: DateTime.now(),
      pending: true,
    );
    setState(() => _msgs.add(optimistic));
    _scrollToBottom();

    try {
      // 2. Write to Firestore
      final docRef = await _messagesRef.add({
        'senderId': uid,
        'isSupport': false,
        'name': name,
        'text': text,
        'hasSeen': false,
        'hasSeenByAdmin': false,
        'isAutoReply': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.roomId)
          .update({
        'lastMessage': text,
        'lastMessageSender': 'You',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      // 3. Confirm: replace optimistic with real doc id + remove pending flag
      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere((m) => m.pending && m.text == text && m.isMe);
          if (idx != -1) {
            _msgs[idx] = _msgs[idx].copyWith(id: docRef.id, pending: false);
          }
        });
      }
    } catch (e) {
      debugPrint('Send error: $e');
      // Remove the optimistic message on failure
      if (mounted) {
        setState(() => _msgs.removeWhere((m) => m.pending && m.text == text));
      }
    }
  }

  // ── Mark seen ──────────────────────────────────────────────────────────────
  Future<void> _markSupportMessagesAsSeen() async {
    try {
      final snap = await _messagesRef
          .where('isSupport', isEqualTo: true)
          .where('hasSeen', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'hasSeen': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Mark seen error: $e');
    }
  }

  void _listenAndMarkSeen() {
    _seenSub = _messagesRef
        .where('isSupport', isEqualTo: true)
        .where('hasSeen', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'hasSeen': true});
      }
      await batch.commit();
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
_Msg _docToMsg(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final ts = data['createdAt'] as Timestamp?;
  return _Msg(
    id: doc.id,
    text: data['text'] as String? ?? '',
    isMe: data['senderId'] == _uid,
    isSupport: data['isSupport'] as bool? ?? false,
    isAutoReply: data['isAutoReply'] as bool? ?? false,
    hasSeenBySupport: data['hasSeenByAdmin'] as bool? ?? false,
    time: ts?.toDate(),
    pending: false,
  );
}

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:$m $period';
    if (diff == 0) return timeStr;
    if (diff == 1) return 'Yesterday $timeStr';
    if (diff < 7) return '${['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][dt.weekday - 1]} $timeStr';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[dt.month - 1]} ${dt.day} $timeStr';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.support_agent, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Giggre Support',
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Text('We\'ll respond within 24–48 hours',
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.5), fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Message list ─────────────────────────────────────────────────
          Expanded(
            child: _isLoadingInitial
                ? const Center(child: CircularProgressIndicator())
                : _msgs.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSay hello! 👋',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        itemCount: _msgs.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (_isLoadingMore && i == 0) {
                            return const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            );
                          }
                          final msg = _msgs[_isLoadingMore ? i - 1 : i];
                          return _MessageBubble(
                            msg: msg,
                            isDark: isDark,
                            timeStr: msg.time != null
                                ? _formatTime(msg.time!)
                                : '',
                          );
                        },
                      ),
          ),

          // ── Input bar ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade900
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _msgController,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(fontSize: 14, color: onSurface),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: kBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isDark,
    required this.timeStr,
  });

  final _Msg msg;
  final bool isDark;
  final String timeStr;

  bool get _isHtml => msg.text.contains('<') && msg.text.contains('>');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.support_agent,
                  color: Colors.white, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Opacity(
                  // Slightly dim pending messages like Messenger does
                  opacity: msg.pending ? 0.6 : 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: (msg.isMe && !msg.isAutoReply)
                          ? null
                          : Border.all(
                              color: msg.isMe
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : kAmber,
                              width: 1.5,
                            ),
                      color: msg.isMe
                          ? kBlue
                          : isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                        bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.isAutoReply) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_fix_high,
                                  size: 15,
                                  color: msg.isMe
                                      ? Colors.white70
                                      : Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text('Auto Reply',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: msg.isMe
                                          ? Colors.white70
                                          : Colors.grey.shade600,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        _isHtml
                            ? Html(
                                data: msg.text,
                                style: {
                                  'body': Style(
                                    fontSize: FontSize(14),
                                    color: msg.isMe
                                        ? Colors.white
                                        : isDark
                                            ? Colors.white
                                            : Colors.black87,
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                  ),
                                  'div': Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero),
                                },
                              )
                            : Text(
                                msg.text,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: msg.isMe ? Colors.white : null),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    if (msg.pending)
                      Icon(Icons.access_time,
                          size: 10, color: Colors.grey.shade400)
                    else
                      Text(timeStr,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade400)),
                    if (msg.isMe && msg.hasSeenBySupport)
                      Icon(Icons.done_all,
                          size: 12, color: Colors.grey.shade400),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}