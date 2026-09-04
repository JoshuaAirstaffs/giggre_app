import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/call/call_user_action.dart';
import 'package:provider/provider.dart';

// ── Local message model ────────────────────────────────────────────────────────
class _Msg {
  final String? id; // null = optimistic (not yet committed)
  final String text;
  final bool isMe;
  final bool isSupport;
  final bool isAutoReply;
  final bool hasSeenBySupport;
  final bool hasSeenByPeer; // for gig chats: peer read the message
  final DateTime? time;
  final bool pending; // true while waiting for server

  const _Msg({
    this.id,
    required this.text,
    required this.isMe,
    this.isSupport = false,
    this.isAutoReply = false,
    this.hasSeenBySupport = false,
    this.hasSeenByPeer = false,
    this.time,
    this.pending = false,
  });

  _Msg copyWith({
    String? id,
    bool? pending,
    bool? hasSeenBySupport,
    bool? hasSeenByPeer,
    DateTime? time,
  }) => _Msg(
    id: id ?? this.id,
    text: text,
    isMe: isMe,
    isSupport: isSupport,
    isAutoReply: isAutoReply,
    hasSeenBySupport: hasSeenBySupport ?? this.hasSeenBySupport,
    hasSeenByPeer: hasSeenByPeer ?? this.hasSeenByPeer,
    time: time ?? this.time,
    pending: pending ?? this.pending,
  );
}

// ── Gig chat metadata (passed when room doesn't exist yet) ────────────────────
class GigChatParams {
  final String gigId;
  final String peerUid;
  final String peerName;

  const GigChatParams({
    required this.gigId,
    required this.peerUid,
    required this.peerName,
  });
}

// ── Chat screen ────────────────────────────────────────────────────────────────
class Chat extends StatefulWidget {
  final String roomId;
  final GigChatParams? gigChatParams;
  final bool isGigChat;
  const Chat({
    super.key,
    required this.roomId,
    this.gigChatParams,
    this.isGigChat = false,
  });

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

  // Stream subscriptions
  StreamSubscription? _incomingSub;
  StreamSubscription? _seenSub;
  StreamSubscription? _gigSeenSub;
  StreamSubscription? _roomSub;

  // Track the newest timestamp we've fetched, to avoid stream duplicates
  DateTime? _newestFetchedTime;

  bool _isResolved = false;
  bool _resolvedNotified = false;
  bool _isGigChat = false;
  String? _peerName;
  String? _peerPhotoUrl;
  bool _isBlocked = false;
  StreamSubscription<DocumentSnapshot>? _blockedSub;
  // True once the room doc exists in Firestore — false for lazy gig chats
  // until the first message is sent.
  bool _roomCreated = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference get _messagesRef => FirebaseFirestore.instance
      .collection('chat_rooms')
      .doc(widget.roomId)
      .collection('messages');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _isGigChat = widget.isGigChat || widget.gigChatParams != null;
    final params = widget.gigChatParams;
    if (params != null) {
      _roomCreated = false;
      _peerName = params.peerName;
      _isLoadingInitial = false;
      _fetchPeerPhoto(params.peerUid);
    } else {
      _loadInitial();
      _listenAndMarkSeen();
    }
    _listenRoomStatus();
    if (_isGigChat && params != null) _listenBlockedStatus(params.peerUid);
  }

  // Watches whether *I* have blocked the peer, to disable the composer and
  // hide the call actions. The reverse (peer blocked me) isn't tracked here —
  // that's enforced server-side and surfaces as a permission-denied error
  // from _sendMessage instead.
  void _listenBlockedStatus(String peerUid) {
    final uid = _uid;
    if (uid == null || peerUid.isEmpty) return;
    _blockedSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final blocked =
              (snap.data()?['blockedUsers'] as List<dynamic>?) ?? [];
          final isBlocked = blocked.contains(peerUid);
          if (isBlocked != _isBlocked) setState(() => _isBlocked = isBlocked);
        });
  }

  Future<void> _fetchPeerPhoto(String uid) async {
    if (uid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      final url = doc.data()?['photoUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        setState(() => _peerPhotoUrl = url);
      }
    } catch (e) {
      debugPrint('Fetch peer photo error: $e');
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _seenSub?.cancel();
    _gigSeenSub?.cancel();
    _roomSub?.cancel();
    _blockedSub?.cancel();
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
      q = q.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(_newestFetchedTime!),
      );
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

  // ── Listen to room status (close + block input when resolved) ─────────────
  void _listenRoomStatus() {
    bool firstExistingSnapshot = true;
    _roomSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;

          if (!snap.exists) {
            if (_roomCreated) setState(() => _roomCreated = false);
            return;
          }

          // Room now exists — if it just appeared (other user sent first), start streams.
          if (!_roomCreated) {
            setState(() => _roomCreated = true);
            _loadInitial();
            _listenAndMarkSeen();
          }

          final data = snap.data() as Map<String, dynamic>;
          final resolved = (data['status'] as String? ?? '') == 'resolved';
          final createdByUid = data['createdByUid'] as String? ?? '';
          final createdByName = data['createdByName'] as String? ?? '';
          final sendTo = data['sendTo'] as String? ?? '';
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          final peer = (createdByUid.isNotEmpty && currentUid != createdByUid)
              ? (createdByName.isNotEmpty ? createdByName : sendTo)
              : sendTo;
          if (peer != _peerName) {
            setState(() => _peerName = peer.isNotEmpty ? peer : null);
          }

          if (firstExistingSnapshot) {
            _markSupportMessagesAsSeen();
          }

          if (resolved && firstExistingSnapshot) {
            setState(() => _isResolved = true);
          } else if (resolved && !_resolvedNotified) {
            setState(() {
              _isResolved = true;
              _resolvedNotified = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This conversation has been resolved and closed.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.of(context).pop();
            });
          }

          firstExistingSnapshot = false;
        });
  }

  // ── Send: optimistic UI ────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    if (_isResolved || _isBlocked) return;
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
      // 2. Lazy-create gig chat room on first message
      if (!_roomCreated && widget.gigChatParams != null) {
        final p = widget.gigChatParams!;
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(widget.roomId)
            .set({
              'gigId': p.gigId,
              'isGigChat': true,
              'participants': [uid, p.peerUid],
              'sendTo': p.peerName,
              'createdByUid': uid,
              'createdByName': name,
              'subject': 'Gig Chat',
              'status': 'open',
              'lastMessage': '',
              'lastMessageSender': '',
              'lastMessageSenderId': '',
              'lastMessageAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
            });
        if (mounted) setState(() => _roomCreated = true);
      }

      // 3. Write to Firestore
      final docRef = await _messagesRef.add({
        'senderId': uid,
        'isSupport': false,
        'name': name,
        'text': text,
        'hasSeen': false,
        'hasSeenByAdmin': false,
        if (_isGigChat) 'hasSeenByPeer': false,
        'isAutoReply': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.roomId)
          .update({
            'lastMessage': text,
            'lastMessageSender': 'You',
            // Gig chats are shared between two real participants — 'You' above
            // is only correct from the sender's own point of view. Gig Chats
            // tab derives the display label from this uid instead (correctly
            // showing the peer's name when they're not the one who sent it).
            'lastMessageSenderId': uid,
            'lastMessageAt': FieldValue.serverTimestamp(),
          });

      // 4. Confirm: replace optimistic with real doc id + remove pending flag
      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere(
            (m) => m.pending && m.text == text && m.isMe,
          );
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
        // The peer having blocked *me* isn't tracked client-side — it only
        // surfaces here, as the security rule rejecting the write.
        if (e is FirebaseException && e.code == 'permission-denied') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can no longer message this user.'),
            ),
          );
        }
      }
    }
  }

  // ── Mark seen ──────────────────────────────────────────────────────────────
  Future<void> _markSupportMessagesAsSeen() async {
    try {
      final uid = _uid ?? '';
      final base = _messagesRef.where('hasSeen', isEqualTo: false);
      final q = _isGigChat
          ? base.where('senderId', isNotEqualTo: uid)
          : base.where('isSupport', isEqualTo: true);
      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snap.docs) {
          batch.update(doc.reference, {'hasSeen': true});
        }
        await batch.commit();
      }

      // For gig chats: also mark hasSeenByPeer on messages sent by the peer,
      // so the sender's bubble shows a "Seen" indicator.
      if (_isGigChat) {
        final peerSnap = await _messagesRef
            .where('senderId', isNotEqualTo: uid)
            .where('hasSeenByPeer', isEqualTo: false)
            .get();
        if (peerSnap.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in peerSnap.docs) {
            batch.update(doc.reference, {'hasSeenByPeer': true});
          }
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint('Mark seen error: $e');
    }
  }

  void _listenAndMarkSeen() {
    // For support chats: mark admin messages seen in real-time.
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

    // For gig chats: stream peer messages and mark hasSeenByPeer in real-time.
    if (_isGigChat) {
      final uid = _uid ?? '';
      _gigSeenSub = _messagesRef
          .where('senderId', isNotEqualTo: uid)
          .where('hasSeenByPeer', isEqualTo: false)
          .snapshots()
          .listen((snap) async {
            if (snap.docs.isEmpty) return;
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in snap.docs) {
              batch.update(doc.reference, {'hasSeenByPeer': true});
            }
            await batch.commit();
          });
    }
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
      hasSeenByPeer: data['hasSeenByPeer'] as bool? ?? false,
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

  // ── Block / report ──────────────────────────────────────────────────────────
  Future<bool?> _showBlockConfirmSheet({
    required bool block,
    required String peerName,
  }) {
    final accent = block ? Colors.redAccent : kBlue;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(ctx).viewPadding.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: accent.withValues(alpha: 0.12),
                      backgroundImage:
                          (_peerPhotoUrl != null && _peerPhotoUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(_peerPhotoUrl!)
                          : null,
                      child: (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty)
                          ? Icon(Icons.person_rounded, color: accent, size: 34)
                          : null,
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 2.5),
                      ),
                      child: Icon(
                        block ? Icons.block_rounded : Icons.lock_open_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  block ? 'Block $peerName?' : 'Unblock $peerName?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  block
                      ? 'Neither of you will be able to send messages to each other, and this conversation will disappear from your Gig Chats list. You can undo this anytime.'
                      : 'You\'ll be able to message each other again, and this conversation will reappear in your Gig Chats list.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kSub,
                    height: 1.5,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      block ? 'Block user' : 'Unblock user',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: kSub, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleBlockUser() async {
    final uid = _uid;
    final peerUid = widget.gigChatParams?.peerUid;
    if (uid == null || peerUid == null || peerUid.isEmpty) return;
    final peerName = widget.gigChatParams?.peerName ?? 'this user';

    final block = !_isBlocked;
    final confirmed = await _showBlockConfirmSheet(
      block: block,
      peerName: peerName,
    );
    if (confirmed != true || !mounted) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'blockedUsers': block
          ? FieldValue.arrayUnion([peerUid])
          : FieldValue.arrayRemove([peerUid]),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(block ? '$peerName blocked.' : '$peerName unblocked.'),
        ),
      );
    }
  }

  static const _reportReasons = [
    'Harassment or abuse',
    'Spam',
    'Inappropriate content',
    'Scam or fraud',
    'Other',
  ];

  Future<void> _reportUser() async {
    final uid = _uid;
    final peerUid = widget.gigChatParams?.peerUid;
    if (uid == null || peerUid == null || peerUid.isEmpty) return;
    final peerName = widget.gigChatParams?.peerName ?? 'this user';

    String? selectedReason;
    final detailsController = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cardColor = Theme.of(ctx).cardColor;
          final onSurface = Theme.of(ctx).colorScheme.onSurface;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                MediaQuery.of(ctx).viewPadding.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.flag_rounded,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Report $peerName',
                            style: TextStyle(
                              color: onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tell us what\'s wrong. Our team will review this conversation.',
                      style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    for (final reason in _reportReasons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              setSheetState(() => selectedReason = reason),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: selectedReason == reason
                                  ? kBlue.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedReason == reason
                                    ? kBlue
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selectedReason == reason
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  size: 18,
                                  color: selectedReason == reason
                                      ? kBlue
                                      : kSub,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  reason,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      style: TextStyle(fontSize: 14, color: onSurface),
                      decoration: InputDecoration(
                        hintText: 'Additional details (optional)',
                        hintStyle: const TextStyle(color: kSub, fontSize: 13),
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedReason == null
                            ? null
                            : () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          disabledBackgroundColor: Colors.grey.withValues(
                            alpha: 0.3,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Submit report',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: kSub, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    final details = detailsController.text.trim();
    detailsController.dispose();
    if (submitted != true || selectedReason == null || !mounted) return;

    await FirebaseFirestore.instance.collection('reports').add({
      'reporterId': uid,
      'reportedUserId': peerUid,
      'reportedUserName': widget.gigChatParams?.peerName ?? '',
      'roomId': widget.roomId,
      'reason': selectedReason,
      'details': details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Our team will review it.'),
        ),
      );
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
    if (diff < 7)
      return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1]} $timeStr';
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
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
            _isGigChat
                ? CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(
                      0xFF3B82F6,
                    ).withValues(alpha: 0.15),
                    backgroundImage:
                        (_peerPhotoUrl != null && _peerPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(_peerPhotoUrl!)
                        : null,
                    child: (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty)
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF3B82F6),
                            size: 18,
                          )
                        : null,
                  )
                : Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isGigChat ? (_peerName ?? 'Gig Chat') : 'Giggre Support',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isGigChat
                      ? 'Gig conversation'
                      : 'We\'ll respond within 24–48 hours',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: (_isGigChat && widget.gigChatParams != null)
            ? [
                if (!_isBlocked) ...[
                  CallUserAction(
                    targetUserId: widget.gigChatParams!.peerUid,
                    targetUserName: widget.gigChatParams!.peerName,
                    callType: CallType.voice,
                  ),
                  CallUserAction(
                    targetUserId: widget.gigChatParams!.peerUid,
                    targetUserName: widget.gigChatParams!.peerName,
                    callType: CallType.video,
                  ),
                ],
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: onSurface.withValues(alpha: 0.7),
                  ),
                  onSelected: (value) {
                    if (value == 'report') _reportUser();
                    if (value == 'block') _toggleBlockUser();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report user'),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text(_isBlocked ? 'Unblock user' : 'Block user'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ]
            : null,
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
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final msg = _msgs[_isLoadingMore ? i - 1 : i];
                      return _MessageBubble(
                        msg: msg,
                        isDark: isDark,
                        timeStr: msg.time != null ? _formatTime(msg.time!) : '',
                        isGigChat: _isGigChat,
                        peerPhotoUrl: _peerPhotoUrl,
                      );
                    },
                  ),
          ),

          // ── Input bar / resolved banner ──────────────────────────────────
          if (_isResolved)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Colors.green.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'This conversation is resolved and closed.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_isBlocked)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.block_rounded,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'You\'ve blocked this user.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _toggleBlockUser,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text(
                        'Unblock',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
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
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
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
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
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
    required this.isGigChat,
    this.peerPhotoUrl,
  });

  final _Msg msg;
  final bool isDark;
  final String timeStr;
  final bool isGigChat;
  final String? peerPhotoUrl;

  bool get _isHtml => msg.text.contains('<') && msg.text.contains('>');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: msg.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            isGigChat
                ? CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(
                      0xFF3B82F6,
                    ).withValues(alpha: 0.15),
                    backgroundImage:
                        (peerPhotoUrl != null && peerPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(peerPhotoUrl!)
                        : null,
                    child: (peerPhotoUrl == null || peerPhotoUrl!.isEmpty)
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF3B82F6),
                            size: 14,
                          )
                        : null,
                  )
                : Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.support_agent,
                      color: Colors.white,
                      size: 14,
                    ),
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
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: (msg.isMe && !msg.isAutoReply)
                          ? null
                          : Border.all(
                              color: msg.isMe
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : isGigChat
                                  ? const Color(0xFF3B82F6)
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
                              Icon(
                                Icons.auto_fix_high,
                                size: 15,
                                color: msg.isMe
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Auto-Reply',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: msg.isMe
                                      ? Colors.white70
                                      : Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                                    padding: HtmlPaddings.zero,
                                  ),
                                },
                              )
                            : Text(
                                msg.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: msg.isMe ? Colors.white : null,
                                ),
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
                      Icon(
                        Icons.access_time,
                        size: 10,
                        color: Colors.grey.shade400,
                      )
                    else
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    if (msg.isMe &&
                        (isGigChat ? msg.hasSeenByPeer : msg.hasSeenBySupport))
                      Icon(
                        Icons.done_all,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
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
