import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_html/flutter_html.dart' hide Marker;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/services/content_filter_service.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/map_style.dart';
import 'package:giggre_app/core/widgets/content_rejection_modal.dart';
import 'package:giggre_app/features/reports/models/report_content_type.dart';
import 'package:giggre_app/features/reports/report_service.dart';
import 'package:giggre_app/features/call/call_helper.dart';
import 'package:giggre_app/helpers/snackbar_helper.dart';
import 'package:giggre_app/features/call/call_log.dart';
import 'package:giggre_app/features/call/call_user_action.dart';
import 'package:provider/provider.dart';

// ── Local message model ────────────────────────────────────────────────────────
class _Msg {
  final String? id; // null = optimistic (not yet committed)
  final String text;
  final bool isMe;
  final String senderId;
  final bool isSupport;
  final bool isAutoReply;
  final bool hasSeenBySupport;
  final bool hasSeenByPeer; // for gig chats: peer read the message
  final DateTime? time;
  final bool pending; // true while waiting for server
  // Web-only origin (giggre-website's ChatPage) — soft-deleted messages keep
  // their doc (order/hasSeen bookkeeping stays intact) but flip this instead
  // of removing it. Rendered here as "Message has been removed" too, so a
  // deletion from either platform looks the same on both.
  final bool isDeleted;
  // Set only for a shared-location message (worker "share location" action).
  // `text` still carries a "📍 <address or "Shared location">" fallback for
  // previews/notifications, but the bubble renders a map instead of that
  // text, plus `locationAddress` (if reverse-geocoding succeeded) as a label.
  final GeoPoint? location;
  final String? locationAddress;
  // Set only for an attachment message (composer paperclip). `text` still
  // carries a "📷 Photo" / "🎥 Video" / "📎 <filename>" fallback for
  // previews/notifications, but the bubble renders media/a file card
  // instead of that text. `attachmentUrl` is null while the optimistic
  // message is still uploading.
  final String? attachmentUrl;
  final String? attachmentType; // 'image' | 'video' | 'file'
  final String? attachmentName;
  // Set only for a call-log message (see call_log.dart), written by the
  // caller once a voice/video call ends. `text` still carries a plain
  // fallback ("📞 Missed voice call", …) for previews/notifications, but the
  // bubble renders _CallLogBubble instead of that text.
  final String? callType; // 'voice' | 'video'
  final String? callStatus; // 'completed' | 'declined' | 'missed'
  final int callDuration; // seconds; 0 unless completed

  bool get isCallLog => callType != null;

  const _Msg({
    this.id,
    required this.text,
    required this.isMe,
    this.senderId = '',
    this.isSupport = false,
    this.isAutoReply = false,
    this.hasSeenBySupport = false,
    this.hasSeenByPeer = false,
    this.time,
    this.pending = false,
    this.isDeleted = false,
    this.location,
    this.locationAddress,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentName,
    this.callType,
    this.callStatus,
    this.callDuration = 0,
  });

  _Msg copyWith({
    String? id,
    bool? pending,
    bool? hasSeenBySupport,
    bool? hasSeenByPeer,
    DateTime? time,
    bool? isDeleted,
    String? attachmentUrl,
  }) => _Msg(
    id: id ?? this.id,
    text: text,
    isMe: isMe,
    senderId: senderId,
    isSupport: isSupport,
    isAutoReply: isAutoReply,
    hasSeenBySupport: hasSeenBySupport ?? this.hasSeenBySupport,
    hasSeenByPeer: hasSeenByPeer ?? this.hasSeenByPeer,
    time: time ?? this.time,
    pending: pending ?? this.pending,
    isDeleted: isDeleted ?? this.isDeleted,
    location: location,
    locationAddress: locationAddress,
    attachmentUrl: attachmentUrl ?? this.attachmentUrl,
    attachmentType: attachmentType,
    attachmentName: attachmentName,
    callType: callType,
    callStatus: callStatus,
    callDuration: callDuration,
  );
}

// ── Gig chat metadata (passed when room doesn't exist yet) ────────────────────
class GigChatParams {
  final String gigId;
  final String peerUid;
  final String peerName;
  // Statically known at the call site (a host-facing screen passes false, a
  // worker-facing screen passes true) — threaded through so Chat can show
  // worker/host-specific UI (quick-reply chips, share-location button)
  // without a round trip to Firestore. Null when the caller doesn't know
  // (e.g. reopening a room from the chat list or a push notification) —
  // Chat then falls back to reading hostUid/workerUid off the room doc.
  final bool? viewerIsWorker;

  const GigChatParams({
    required this.gigId,
    required this.peerUid,
    required this.peerName,
    this.viewerIsWorker,
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
  // Anchors the quick-reply popup menu to the button that opens it.
  final _quickReplyButtonKey = GlobalKey();
  final _scrollController = ScrollController();

  static const _pageSize = 20;
  // Senders can only delete a message while it's still fresh — mirrors an
  // "unsend" window rather than allowing deletion indefinitely.
  static const _deleteWindow = Duration(minutes: 2);

  // Role-specific canned messages shown as tappable chips above the
  // composer — mirrors giggre-website's quick-reply chips, gig chats only.
  static const _workerQuickReplies = [
    'On my way',
    "I've arrived",
    'Running a few minutes late',
    'On it!',
    'All done',
    'Thanks!',
  ];
  static const _hostQuickReplies = [
    'Thanks for the update',
    'Can you confirm your ETA?',
    'Sounds good',
    'Great work, thank you!',
    'Please see the gig details',
    'Let me know if anything changes',
  ];

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
  // null = role not yet known — role-specific quick replies stay hidden
  // until this resolves, either from GigChatParams (fresh navigation) or
  // the room doc's hostUid/workerUid fields (reopened from the chat list /
  // a notification). Share-location isn't role-gated, so it's unaffected.
  bool? _viewerIsWorker;
  // Guards _resolveRoleFromGig so it's only ever kicked off once per Chat
  // instance — both initState and _listenRoomStatus can trigger it (the
  // latter for the roomId-only entry point, e.g. main.dart's `/chat/{id}`
  // route, which carries no GigChatParams at all).
  bool _roleLookupStarted = false;
  bool _isBlocked = false; // I blocked the peer
  bool _isBlockedByPeer = false; // the peer blocked me
  StreamSubscription<DocumentSnapshot>? _blockedSub;
  StreamSubscription<DocumentSnapshot>? _blockedByPeerSub;

  // Either direction of block disables the composer and call actions — the
  // peer's own block of me isn't something I can undo from here (unlike
  // _isBlocked, which shows an Unblock option), it just needs to be reflected.
  bool get _chatDisabled => _isBlocked || _isBlockedByPeer;
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
    _viewerIsWorker = params?.viewerIsWorker;
    // Most opens of an existing gig chat (from the Gig Chats list, or a
    // push notification tap) carry a gigId but no viewerIsWorker — resolve
    // it by looking the gig up directly rather than leaving the
    // role-specific quick replies hidden for the common case.
    if (_viewerIsWorker == null && params != null && params.gigId.isNotEmpty) {
      _roleLookupStarted = true;
      _resolveRoleFromGig(params.gigId);
    }
    if (params != null) {
      _roomCreated = false;
      _peerName = params.peerName;
      // Stays true until _listenRoomStatus's first snapshot says whether the
      // room exists — clearing it here showed the "Say hello" empty state
      // for a moment before every existing conversation loaded.
      _fetchPeerPhoto(params.peerUid);
    } else {
      _loadInitial();
      _listenAndMarkSeen();
    }
    _listenRoomStatus();
    if (_isGigChat && params != null) _listenBlockedStatus(params.peerUid);
  }

  // A gig lives in exactly one of these — gig_templates is deliberately
  // excluded, a template isn't a postable/chattable gig.
  static const _liveGigCollections = [
    'quick_gigs',
    'open_gigs',
    'offered_gigs',
  ];

  // Fallback role resolution when the caller didn't know (or pass) whether
  // the viewer is the worker or host — looks the gig up directly by id and
  // compares its hostId against the current uid. Also backfills the room
  // doc's hostUid/workerUid so future opens (by either party) resolve
  // instantly from _listenRoomStatus instead of repeating this lookup.
  Future<void> _resolveRoleFromGig(
    String gigId, {
    String? peerUidOverride,
  }) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[Chat] role lookup skipped: not signed in');
      return;
    }
    debugPrint(
      '[Chat] role lookup starting: roomId=${widget.roomId} gigId=$gigId uid=$uid',
    );
    try {
      for (final col in _liveGigCollections) {
        final doc = await FirebaseFirestore.instance
            .collection(col)
            .doc(gigId)
            .get();
        if (!doc.exists) continue;

        final hostId = doc.data()?['hostId'] as String? ?? '';
        if (hostId.isEmpty) {
          debugPrint(
            '[Chat] role lookup: found $col/$gigId but hostId is empty',
          );
          return;
        }
        final isWorker = uid != hostId;
        debugPrint(
          '[Chat] role lookup: found $col/$gigId, hostId=$hostId → isWorker=$isWorker',
        );

        if (mounted && _viewerIsWorker == null) {
          setState(() => _viewerIsWorker = isWorker);
        }

        // hostId comes straight from the gig doc either way; the gig
        // models don't reliably expose a workerId, so when the viewer IS
        // the host, the worker's uid is taken from the chat peer instead.
        final workerUid = isWorker
            ? uid
            : (peerUidOverride ?? widget.gigChatParams?.peerUid ?? '');
        if (workerUid.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('chat_rooms')
              .doc(widget.roomId)
              .set({
                'workerUid': workerUid,
                'hostUid': hostId,
              }, SetOptions(merge: true));
        } else {
          debugPrint(
            '[Chat] role lookup: viewer is host but no peer uid available — '
            'hostUid/workerUid not persisted to the room doc',
          );
        }
        return;
      }
      debugPrint(
        '[Chat] role lookup: gigId=$gigId not found in any of $_liveGigCollections',
      );
    } catch (e) {
      debugPrint('[Chat] role lookup error: $e');
    }
  }

  // Watches both directions of blocking, to disable the composer and hide
  // the call actions either way: whether *I* have blocked the peer (my own
  // doc), and whether the peer has blocked *me* (their doc — readable per
  // the public `allow read: if true` rule on users/{uid}).
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

    _blockedByPeerSub = FirebaseFirestore.instance
        .collection('users')
        .doc(peerUid)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final blocked =
              (snap.data()?['blockedUsers'] as List<dynamic>?) ?? [];
          final isBlockedByPeer = blocked.contains(uid);
          if (isBlockedByPeer != _isBlockedByPeer) {
            setState(() => _isBlockedByPeer = isBlockedByPeer);
          }
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
    _blockedByPeerSub?.cancel();
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

          // It's a new message from support/the peer — or a call log, which
          // the caller writes from CallUserAction (not through this
          // screen's optimistic send path), so it arrives here as "mine".
          if (!msg.isMe || msg.isCallLog) {
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
        .listen(
          (snap) {
            if (!mounted) return;

            if (!snap.exists) {
              // Brand-new gig chat with no messages yet — nothing to load.
              setState(() {
                _roomCreated = false;
                _isLoadingInitial = false;
              });
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

            // Self-heal _isGigChat too — the roomId-only entry point
            // (main.dart's `/chat/{roomId}` named route, used e.g. by
            // home_chat.dart's fallback when peerUid wasn't resolved) never
            // sets widget.isGigChat/gigChatParams at all, which otherwise
            // hides every gig-only affordance (quick replies, share location).
            final roomIsGigChat = data['isGigChat'] as bool? ?? false;
            if (!_isGigChat && roomIsGigChat) {
              setState(() => _isGigChat = true);
            }

            if (_viewerIsWorker == null) {
              final workerUid = data['workerUid'] as String?;
              final hostUid = data['hostUid'] as String?;
              bool? resolvedRole;
              if (currentUid.isNotEmpty && currentUid == workerUid) {
                resolvedRole = true;
              } else if (currentUid.isNotEmpty && currentUid == hostUid) {
                resolvedRole = false;
              }
              if (resolvedRole != null) {
                setState(() => _viewerIsWorker = resolvedRole);
              } else if (widget.roomId.startsWith('dm_') &&
                  createdByUid.isNotEmpty) {
                // Direct messages (directMessageRoomId, worker_message_action.
                // dart) have no gig to look up at all — but they're only ever
                // created by WorkerMessageAction, always from the host side,
                // so whoever created the room IS the host by construction.
                final isWorker = currentUid != createdByUid;
                debugPrint(
                  '[Chat] role resolved from DM room creator: '
                  'createdByUid=$createdByUid → isWorker=$isWorker',
                );
                setState(() => _viewerIsWorker = isWorker);
                final participants =
                    (data['participants'] as List<dynamic>?) ?? [];
                final peerUid =
                    participants.firstWhere(
                          (p) => p != currentUid,
                          orElse: () => '',
                        )
                        as String;
                final workerUid = isWorker ? currentUid : peerUid;
                if (workerUid.isNotEmpty) {
                  FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .doc(widget.roomId)
                      .set({
                        'workerUid': workerUid,
                        'hostUid': createdByUid,
                      }, SetOptions(merge: true));
                }
              } else if (!_roleLookupStarted && roomIsGigChat) {
                final paramsGigId = widget.gigChatParams?.gigId ?? '';
                final roomGigId = data['gigId'] as String? ?? '';
                // Last resort: GigChatAction always names the room
                // 'gig_<gigId>' — parse it back out in case the room doc
                // itself never got a gigId field written.
                const roomIdPrefix = 'gig_';
                final roomIdGigId = widget.roomId.startsWith(roomIdPrefix)
                    ? widget.roomId.substring(roomIdPrefix.length)
                    : '';
                final gigId = paramsGigId.isNotEmpty
                    ? paramsGigId
                    : roomGigId.isNotEmpty
                    ? roomGigId
                    : roomIdGigId;
                debugPrint(
                  '[Chat] role still unknown for roomId=${widget.roomId} — '
                  'paramsGigId="$paramsGigId" roomGigId="$roomGigId" '
                  'roomIdGigId="$roomIdGigId" → using "$gigId"',
                );
                if (gigId.isNotEmpty) {
                  _roleLookupStarted = true;
                  final participants =
                      (data['participants'] as List<dynamic>?) ?? [];
                  final peerUid =
                      participants.firstWhere(
                            (p) => p != currentUid,
                            orElse: () => '',
                          )
                          as String;
                  _resolveRoleFromGig(
                    gigId,
                    peerUidOverride: peerUid.isNotEmpty ? peerUid : null,
                  );
                }
              }
            }

            debugPrint(
              '[Chat] status: roomId=${widget.roomId} currentUid=$currentUid '
              'isGigChat=$_isGigChat viewerIsWorker=$_viewerIsWorker '
              'isResolved=$_isResolved chatDisabled=$_chatDisabled',
            );

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
          },
          onError: (Object e) {
            debugPrint('Room status stream error: $e');
            if (mounted && _isLoadingInitial) {
              setState(() => _isLoadingInitial = false);
            }
          },
        );
  }

  // Lazy-creates the gig chat room on the first message of the thread —
  // shared by _sendText and _shareLocation, since either can be the first
  // message sent. hostUid/workerUid are only written when the role is known
  // (fresh navigation via GigChatParams.viewerIsWorker) — left unset for an
  // unknown-role sender, same as older rooms created before this existed.
  Future<void> _ensureRoomCreated(String? uid, String name) async {
    if (_roomCreated || widget.gigChatParams == null) return;
    final p = widget.gigChatParams!;
    final isWorker = _viewerIsWorker;
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
          if (isWorker != null) 'workerUid': isWorker ? uid : p.peerUid,
          if (isWorker != null) 'hostUid': isWorker ? p.peerUid : uid,
        });
    if (mounted) setState(() => _roomCreated = true);
  }

  // ── Send: optimistic UI ────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await _sendText(text);
  }

  // Pops the role-specific canned phrases up over the composer, anchored to
  // the quick-reply button — showMenu flips it above the anchor automatically
  // when (as here) there isn't room below it. Picking one sends it as-is,
  // same as _sendMessage, without touching whatever's already typed.
  Future<void> _showQuickReplies() async {
    final replies = _viewerIsWorker == true
        ? _workerQuickReplies
        : _hostQuickReplies;
    final buttonBox =
        _quickReplyButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) return;

    final buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final position = RelativeRect.fromLTRB(
      buttonTopLeft.dx,
      buttonTopLeft.dy,
      overlayBox.size.width - buttonTopLeft.dx - buttonBox.size.width,
      overlayBox.size.height - buttonTopLeft.dy,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        for (final phrase in replies)
          PopupMenuItem<String>(
            value: phrase,
            child: Text(phrase, style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
    if (selected != null) _sendText(selected);
  }

  // Shared by the composer's send button and the quick-reply chips — a chip
  // tap calls this directly with its preset phrase, without touching
  // whatever the user has already typed into the composer.
  Future<void> _sendText(String text) async {
    if (_isResolved || _chatDisabled) return;

    if (ContentFilterService.instance.check(text)) {
      showContentRejectionModal(context);
      return;
    }

    final uid = _uid;
    final name = context.read<CurrentUserProvider>().currentName ?? '';

    // 1. Add optimistic message immediately — no flicker, no wait
    final optimistic = _Msg(
      text: text,
      isMe: true,
      senderId: uid ?? '',
      time: DateTime.now(),
      pending: true,
    );
    setState(() => _msgs.add(optimistic));
    _scrollToBottom();

    try {
      // 2. Lazy-create gig chat room on first message
      await _ensureRoomCreated(uid, name);

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
        'isDeleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _updateRoomLastMessage(text, uid);

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

  Future<void> _updateRoomLastMessage(String text, String? uid) async {
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
  }

  // ── Share location (either side, one-time pin) ──────────────────────────────
  Future<void> _shareLocation() async {
    if (_isResolved || _chatDisabled) return;

    try {
      var enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showErrorSnack('Turn on location services to share your location.');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showErrorSnack(
          'Location permission is required to share your location.',
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final location = GeoPoint(pos.latitude, pos.longitude);

      // Best-effort reverse geocode — same field concatenation as the gig
      // address lookup in post_offered_gig_screen.dart. Never blocks the
      // send: a failure just falls back to the generic label.
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        ).timeout(const Duration(seconds: 10));
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final hasName =
              p.name != null && p.name!.isNotEmpty && p.name != p.street;
          final parts = [
            if (hasName) p.name,
            if (p.street != null && p.street!.isNotEmpty) p.street,
            if (p.subLocality != null && p.subLocality!.isNotEmpty)
              p.subLocality,
            if (p.locality != null && p.locality!.isNotEmpty) p.locality,
            if (p.administrativeArea != null &&
                p.administrativeArea!.isNotEmpty)
              p.administrativeArea,
          ];
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (e) {
        debugPrint('Reverse geocode error: $e');
      }
      // Reverse geocoding is unreliable in some environments (notably the
      // iOS Simulator) — fall back to raw coordinates rather than leaving
      // the address row empty every time that happens.
      address ??=
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      if (!mounted) return;

      final text = '📍 $address';

      final uid = _uid;
      final name = context.read<CurrentUserProvider>().currentName ?? '';

      final optimistic = _Msg(
        text: text,
        isMe: true,
        senderId: uid ?? '',
        time: DateTime.now(),
        pending: true,
        location: location,
        locationAddress: address,
      );
      setState(() => _msgs.add(optimistic));
      _scrollToBottom();

      try {
        await _ensureRoomCreated(uid, name);

        final docRef = await _messagesRef.add({
          'senderId': uid,
          'isSupport': false,
          'name': name,
          'text': text,
          'location': location,
          'locationAddress': address,
          'hasSeen': false,
          'hasSeenByAdmin': false,
          if (_isGigChat) 'hasSeenByPeer': false,
          'isAutoReply': false,
          'isDeleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _updateRoomLastMessage(text, uid);

        if (mounted) {
          setState(() {
            final idx = _msgs.indexWhere(
              (m) => m.pending && m.isMe && m.location == location,
            );
            if (idx != -1) {
              _msgs[idx] = _msgs[idx].copyWith(id: docRef.id, pending: false);
            }
          });
        }
      } catch (e) {
        debugPrint('Share location send error: $e');
        if (mounted) {
          setState(
            () => _msgs.removeWhere((m) => m.pending && m.location == location),
          );
          if (e is FirebaseException && e.code == 'permission-denied') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can no longer message this user.'),
              ),
            );
          } else {
            _showErrorSnack("Couldn't share your location. Please try again.");
          }
        }
      }
    } catch (e) {
      debugPrint('Get location error: $e');
      _showErrorSnack("Couldn't get your location. Please try again.");
    }
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Attachments (photo/video/file, either side, no role gate) ──────────────
  static const _videoExtensions = {
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.3gp',
    '.webm',
  };
  static const _fileExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'txt',
    'zip',
  ];
  static const _imageSizeCap = 10 * 1024 * 1024;
  static const _videoSizeCap = 50 * 1024 * 1024;
  static const _fileSizeCap = 20 * 1024 * 1024;

  Future<void> _showAttachmentMenu() async {
    if (_isResolved || _chatDisabled) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: kBlue),
                title: const Text('Photo or Video'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: kBlue),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, 'camera_photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, color: kBlue),
                title: const Text('Record Video'),
                onTap: () => Navigator.pop(ctx, 'camera_video'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.insert_drive_file_outlined,
                  color: kBlue,
                ),
                title: const Text('File'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
              if (_isGigChat)
                ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: kBlue),
                  title: const Text('Share Location'),
                  onTap: () => Navigator.pop(ctx, 'location'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    switch (selected) {
      case 'gallery':
        await _pickGalleryMedia();
      case 'camera_photo':
        await _pickCameraMedia(video: false);
      case 'camera_video':
        await _pickCameraMedia(video: true);
      case 'file':
        await _pickFile();
      case 'location':
        await _shareLocation();
    }
  }

  bool _looksLikeVideo(String path) {
    final lower = path.toLowerCase();
    return _videoExtensions.any((ext) => lower.endsWith(ext));
  }

  Future<void> _pickGalleryMedia() async {
    try {
      final picked = await ImagePicker().pickMedia();
      if (picked == null) return;
      final isVideo = _looksLikeVideo(picked.path);
      await _sendAttachment(
        file: File(picked.path),
        attachmentType: isVideo ? 'video' : 'image',
        attachmentName: picked.name,
      );
    } catch (e) {
      debugPrint('Pick gallery media error: $e');
      _showErrorSnack("Couldn't open your photo library. Please try again.");
    }
  }

  Future<void> _pickCameraMedia({required bool video}) async {
    try {
      final picker = ImagePicker();
      final picked = video
          ? await picker.pickVideo(source: ImageSource.camera)
          : await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      await _sendAttachment(
        file: File(picked.path),
        attachmentType: video ? 'video' : 'image',
        attachmentName: picked.name,
      );
    } catch (e) {
      debugPrint('Camera capture error: $e');
      _showErrorSnack("Couldn't use the camera. Please try again.");
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _fileExtensions,
      );
      final picked = result?.files.single;
      if (picked?.path == null) return;
      await _sendAttachment(
        file: File(picked!.path!),
        attachmentType: 'file',
        attachmentName: picked.name,
      );
    } catch (e) {
      debugPrint('Pick file error: $e');
      _showErrorSnack("Couldn't open the file picker. Please try again.");
    }
  }

  Future<void> _sendAttachment({
    required File file,
    required String attachmentType,
    required String attachmentName,
  }) async {
    if (_isResolved || _chatDisabled) return;

    final sizeCap = attachmentType == 'image'
        ? _imageSizeCap
        : attachmentType == 'video'
        ? _videoSizeCap
        : _fileSizeCap;
    final length = await file.length();
    if (length > sizeCap) {
      final capMb = sizeCap ~/ (1024 * 1024);
      _showErrorSnack('That file is too large — the limit is ${capMb}mb.');
      return;
    }
    if (!mounted) return;

    final text = attachmentType == 'image'
        ? '📷 Photo'
        : attachmentType == 'video'
        ? '🎥 Video'
        : '📎 $attachmentName';

    final uid = _uid;
    final name = context.read<CurrentUserProvider>().currentName ?? '';

    final optimistic = _Msg(
      text: text,
      isMe: true,
      senderId: uid ?? '',
      time: DateTime.now(),
      pending: true,
      attachmentType: attachmentType,
      attachmentName: attachmentName,
    );
    setState(() => _msgs.add(optimistic));
    _scrollToBottom();

    try {
      await _ensureRoomCreated(uid, name);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'chat_attachments/${widget.roomId}/${ts}_$attachmentName',
      );
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      final docRef = await _messagesRef.add({
        'senderId': uid,
        'isSupport': false,
        'name': name,
        'text': text,
        'attachmentUrl': url,
        'attachmentType': attachmentType,
        'attachmentName': attachmentName,
        'hasSeen': false,
        'hasSeenByAdmin': false,
        if (_isGigChat) 'hasSeenByPeer': false,
        'isAutoReply': false,
        'isDeleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _updateRoomLastMessage(text, uid);

      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere(
            (m) =>
                m.pending &&
                m.isMe &&
                m.attachmentType == attachmentType &&
                m.attachmentName == attachmentName,
          );
          if (idx != -1) {
            _msgs[idx] = _msgs[idx].copyWith(
              id: docRef.id,
              pending: false,
              attachmentUrl: url,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Send attachment error: $e');
      if (mounted) {
        setState(
          () => _msgs.removeWhere(
            (m) =>
                m.pending &&
                m.attachmentType == attachmentType &&
                m.attachmentName == attachmentName,
          ),
        );
        if (e is FirebaseException && e.code == 'permission-denied') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can no longer message this user.'),
            ),
          );
        } else {
          _showErrorSnack("Couldn't send attachment. Please try again.");
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
      senderId: data['senderId'] as String? ?? '',
      isSupport: data['isSupport'] as bool? ?? false,
      isAutoReply: data['isAutoReply'] as bool? ?? false,
      hasSeenBySupport: data['hasSeenByAdmin'] as bool? ?? false,
      hasSeenByPeer: data['hasSeenByPeer'] as bool? ?? false,
      time: ts?.toDate(),
      pending: false,
      isDeleted: data['isDeleted'] as bool? ?? false,
      location: data['location'] as GeoPoint?,
      locationAddress: data['locationAddress'] as String?,
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentType: data['attachmentType'] as String?,
      attachmentName: data['attachmentName'] as String?,
      callType: data['callType'] as String?,
      callStatus: data['callStatus'] as String?,
      callDuration: (data['callDuration'] as num?)?.toInt() ?? 0,
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
  // Owns the whole sheet lifecycle (confirm -> submitting -> done) as one
  // continuously-open bottom sheet — same pattern as ReportService and
  // showUserProfileSheet, so block/unblock gets the same in-place
  // confirmation instead of a SnackBar after the sheet closes.
  Future<void> _showBlockConfirmSheet({
    required bool block,
    required String peerName,
    required String uid,
    required String peerUid,
  }) {
    final accent = block ? Colors.redAccent : kBlue;
    bool submitting = false;
    bool done = false;

    return showModalBottomSheet<void>(
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
                  if (done) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            block
                                ? Icons.block_rounded
                                : Icons.lock_open_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            block ? 'User blocked' : 'User unblocked',
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
                    Text(
                      block
                          ? '$peerName has been blocked. You won\'t see their content anymore, and they can\'t message you.'
                          : '$peerName has been unblocked. You can message each other again.',
                      style: const TextStyle(
                        color: kSub,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: accent.withValues(alpha: 0.12),
                          backgroundImage:
                              (_peerPhotoUrl != null &&
                                  _peerPhotoUrl!.isNotEmpty)
                              ? CachedNetworkImageProvider(_peerPhotoUrl!)
                              : null,
                          child:
                              (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty)
                              ? Icon(
                                  Icons.person_rounded,
                                  color: accent,
                                  size: 34,
                                )
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
                            block
                                ? Icons.block_rounded
                                : Icons.lock_open_rounded,
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
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      block
                          ? 'Neither of you will be able to send messages to each other. You can undo this anytime.'
                          : 'You\'ll be able to message each other again.',
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
                        onPressed: submitting
                            ? null
                            : () async {
                                setSheetState(() => submitting = true);
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({
                                        'blockedUsers': block
                                            ? FieldValue.arrayUnion([peerUid])
                                            : FieldValue.arrayRemove([peerUid]),
                                      });
                                  setSheetState(() {
                                    submitting = false;
                                    done = true;
                                  });
                                } catch (e) {
                                  setSheetState(() => submitting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Something went wrong. Please try again.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
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
                        onPressed: submitting ? null : () => Navigator.pop(ctx),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: kSub, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleBlockUser() async {
    final uid = _uid;
    final peerUid = widget.gigChatParams?.peerUid;
    if (uid == null || peerUid == null || peerUid.isEmpty) return;
    final peerName = widget.gigChatParams?.peerName ?? 'this user';

    await _showBlockConfirmSheet(
      block: !_isBlocked,
      peerName: peerName,
      uid: uid,
      peerUid: peerUid,
    );
  }

  Future<void> _reportUser() async {
    final peerUid = widget.gigChatParams?.peerUid;
    if (peerUid == null || peerUid.isEmpty) return;
    await ReportService.show(
      context,
      contentType: ReportContentType.user,
      contentId: peerUid,
      contentSnapshot: '',
      contentAuthorId: peerUid,
      surface: 'chat',
    );
  }

  Future<void> _reportMessage(_Msg msg) async {
    if (msg.id == null || msg.senderId.isEmpty) return;
    await ReportService.show(
      context,
      contentType: ReportContentType.message,
      contentId: msg.id!,
      contentSnapshot: msg.text,
      contentAuthorId: msg.senderId,
      surface: 'chat',
      roomId: widget.roomId,
    );
  }

  // Soft-delete — mirrors giggre-website's ChatPage.tsx: flips `isDeleted`
  // instead of removing the doc, so the thread's order and hasSeen
  // bookkeeping stay intact. Rendered as "Message has been removed" by
  // _MessageBubble on both platforms.
  Future<void> _deleteMessage(_Msg msg) async {
    if (msg.id == null) return;
    // Re-check the window at delete time, not just when the long-press menu
    // was opened — time may have passed the 2-minute mark in between.
    if (msg.time == null ||
        DateTime.now().difference(msg.time!) > _deleteWindow) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to delete message — the 2-minute window to delete it has passed.',
            ),
          ),
        );
      }
      return;
    }
    try {
      await _messagesRef.doc(msg.id).update({'isDeleted': true});
      // If this was the room's most recent message, the chat list screen
      // reads its preview straight off `chat_rooms.lastMessage` (a
      // denormalized copy) rather than the message doc, so it would keep
      // showing the removed text forever unless we refresh it here too.
      final latestSnap = await _messagesRef
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latestSnap.docs.isNotEmpty && latestSnap.docs.first.id == msg.id) {
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(widget.roomId)
            .update({'lastMessage': 'Message has been removed'});
      }
      // Optimistic local update — _startIncomingStream's listener only
      // watches for messages with createdAt greater than what's already
      // loaded, so it structurally never sees a `modified` event for a
      // message that was already on screen (i.e. every message except ones
      // that arrived after this chat was opened). Without this, deleting an
      // older message wouldn't show as removed until the chat is reopened.
      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            _msgs[idx] = _msgs[idx].copyWith(isDeleted: true);
          }
        });
      }
    } catch (e) {
      debugPrint('Delete message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t delete this message. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteMessage(_Msg msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text(
          'It will be replaced with "Message has been removed" for both of you. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteMessage(msg);
  }

  Future<void> _showMessageActions(
    _Msg msg, {
    required bool canReport,
    required bool canDelete,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (canReport)
                ListTile(
                  leading: const Icon(Icons.flag_rounded, color: Colors.orange),
                  title: const Text('Report message'),
                  onTap: () => Navigator.pop(ctx, 'report'),
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete message',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == 'report') _reportMessage(msg);
    if (selected == 'delete') _confirmDeleteMessage(msg);
  }

  // Time under a message — the day itself is shown by the date divider.
  String _formatClock(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  // Label for the date divider above the first message of each day.
  String _formatDay(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
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
    return '${mo[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  // Whether _msgs[j] and the message after it form one visual group:
  // same sender, same day, sent within a few minutes of each other. Call
  // logs never group with regular messages.
  bool _groupsWithNext(int j) {
    if (j + 1 >= _msgs.length) return false;
    final a = _msgs[j];
    final b = _msgs[j + 1];
    if (a.isCallLog || b.isCallLog) return false;
    if (a.isMe != b.isMe || a.senderId != b.senderId) return false;
    final at = a.time;
    final bt = b.time;
    if (at == null || bt == null) return true;
    return _sameDay(at, bt) && bt.difference(at).inMinutes.abs() < 5;
  }

  String get _composerHint {
    final first = (_peerName ?? '').trim().split(' ').first;
    return _isGigChat && first.isNotEmpty
        ? 'Message $first...'
        : 'Type a message...';
  }

  bool get _canCallPeer =>
      _isGigChat &&
      widget.gigChatParams != null &&
      !_chatDisabled &&
      !_isResolved;

  Future<void> _callPeer({required bool isVideo}) async {
    final p = widget.gigChatParams;
    if (p == null) return;
    final busy = await CallHelper.getCallStatus(p.peerUid);
    if (!mounted) return;
    if (busy != null) {
      SnackbarHelper.showWarning(context, busy);
      return;
    }
    await placeCall(
      context: context,
      targetUserId: p.peerUid,
      targetUserName: p.peerName,
      isVideo: isVideo,
      gigId: p.gigId,
      viewerIsWorker: _viewerIsWorker,
    );
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
                if (!_chatDisabled) ...[
                  CallUserAction(
                    targetUserId: widget.gigChatParams!.peerUid,
                    targetUserName: widget.gigChatParams!.peerName,
                    callType: CallType.voice,
                    gigId: widget.gigChatParams!.gigId,
                    viewerIsWorker: _viewerIsWorker,
                  ),
                  CallUserAction(
                    targetUserId: widget.gigChatParams!.peerUid,
                    targetUserName: widget.gigChatParams!.peerName,
                    callType: CallType.video,
                    gigId: widget.gigChatParams!.gigId,
                    viewerIsWorker: _viewerIsWorker,
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
                      final j = _isLoadingMore ? i - 1 : i;
                      final msg = _msgs[j];
                      final prev = j > 0 ? _msgs[j - 1] : null;

                      final showDate =
                          msg.time != null &&
                          (prev == null || !_sameDay(prev.time, msg.time));

                      Widget withDate(Widget child) => showDate
                          ? Column(
                              children: [
                                _DateDivider(
                                  label: _formatDay(msg.time!),
                                  isDark: isDark,
                                ),
                                child,
                              ],
                            )
                          : child;

                      if (msg.isCallLog) {
                        return withDate(
                          _CallLogCard(
                            call: msg,
                            isDark: isDark,
                            formatClock: _formatClock,
                            onCall: _canCallPeer
                                ? () => _callPeer(
                                    isVideo: msg.callType == 'video',
                                  )
                                : null,
                          ),
                        );
                      }

                      final canReport =
                          !msg.isCallLog &&
                          !msg.isMe &&
                          !msg.isSupport &&
                          !msg.isAutoReply &&
                          msg.id != null &&
                          !msg.isDeleted &&
                          msg.senderId.isNotEmpty;
                      final canDelete =
                          !msg.isCallLog &&
                          msg.isMe &&
                          msg.id != null &&
                          !msg.isDeleted &&
                          msg.time != null &&
                          DateTime.now().difference(msg.time!) <= _deleteWindow;
                      return withDate(
                        GestureDetector(
                          onLongPress: (canReport || canDelete)
                              ? () => _showMessageActions(
                                  msg,
                                  canReport: canReport,
                                  canDelete: canDelete,
                                )
                              : null,
                          child: _MessageBubble(
                            msg: msg,
                            isDark: isDark,
                            timeStr: msg.time != null
                                ? _formatClock(msg.time!)
                                : '',
                            isGigChat: _isGigChat,
                            peerPhotoUrl: _peerPhotoUrl,
                            isLastInGroup: !_groupsWithNext(j),
                          ),
                        ),
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
          else if (_isBlockedByPeer)
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
                      'This user has blocked you.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w500,
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attachments + share location (gig chats) live behind
                    // this one button — see _showAttachmentMenu.
                    GestureDetector(
                      onTap: _showAttachmentMenu,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade900
                              : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: onSurface.withValues(alpha: 0.7),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade900
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _msgController,
                                minLines: 1,
                                maxLines: 4,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: _composerHint,
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            if (_isGigChat &&
                                _viewerIsWorker != null &&
                                !_isResolved &&
                                !_chatDisabled)
                              IconButton(
                                key: _quickReplyButtonKey,
                                onPressed: _showQuickReplies,
                                tooltip: 'Quick replies',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.bolt_rounded,
                                  color: kBlue,
                                  size: 20,
                                ),
                              )
                            else
                              const SizedBox(width: 12),
                          ],
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
                          size: 22,
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
    this.isLastInGroup = true,
  });

  final _Msg msg;
  final bool isDark;
  final String timeStr;
  final bool isGigChat;
  final String? peerPhotoUrl;
  // Consecutive messages from the same sender are grouped (see
  // _ChatState._groupsWithNext): only the last one in a group shows the
  // avatar, the time/seen row and the bubble's tail corner.
  final bool isLastInGroup;

  bool get _isHtml => msg.text.contains('<') && msg.text.contains('>');

  // Image/video (like the location map) render edge-to-edge with no bubble
  // padding/background — a file attachment keeps the normal padded/colored
  // bubble, since its content (an icon + filename) reads fine inside one.
  bool get _isEdgeToEdgeMedia =>
      msg.location != null ||
      msg.attachmentType == 'image' ||
      msg.attachmentType == 'video';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLastInGroup ? 10 : 2),
      child: Row(
        mainAxisAlignment: msg.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            Visibility(
              visible: isLastInGroup,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: isGigChat
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
                    padding: _isEdgeToEdgeMedia
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      border: _isEdgeToEdgeMedia
                          ? null
                          : msg.isDeleted
                          ? Border.all(
                              color: Colors.grey.withValues(alpha: 0.4),
                              width: 1,
                            )
                          : (msg.isMe && !msg.isAutoReply)
                          ? null
                          : Border.all(
                              color: msg.isMe
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : isGigChat
                                  ? const Color(0xFF3B82F6)
                                  : kAmber,
                              width: 1.5,
                            ),
                      color: _isEdgeToEdgeMedia
                          ? Colors.transparent
                          : msg.isDeleted
                          ? (isDark
                                ? Colors.grey.shade800.withValues(alpha: 0.4)
                                : Colors.grey.shade200.withValues(alpha: 0.6))
                          : msg.isMe
                          ? kBlue
                          : isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(
                          !msg.isMe && isLastInGroup ? 4 : 16,
                        ),
                        bottomRight: Radius.circular(
                          msg.isMe && isLastInGroup ? 4 : 16,
                        ),
                      ),
                    ),
                    child: msg.isDeleted
                        ? Text(
                            'Message has been removed',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade500,
                            ),
                          )
                        : msg.location != null
                        ? _LocationBubble(
                            location: msg.location!,
                            address: msg.locationAddress,
                            isDark: isDark,
                          )
                        : msg.attachmentType == 'image'
                        ? _ImageAttachmentBubble(url: msg.attachmentUrl)
                        : msg.attachmentType == 'video'
                        ? _VideoAttachmentBubble(url: msg.attachmentUrl)
                        : msg.attachmentType == 'file'
                        ? _FileAttachmentBubble(
                            url: msg.attachmentUrl,
                            name: msg.attachmentName ?? 'File',
                            isMe: msg.isMe,
                          )
                        : Column(
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
                if (isLastInGroup || msg.pending) ...[
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
                          (isGigChat
                              ? msg.hasSeenByPeer
                              : msg.hasSeenBySupport))
                        Icon(
                          Icons.done_all,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Location message bubble ───────────────────────────────────────────────────
// Renders a shared-location message (see Chat._shareLocation) as a small
// non-interactive Google Map with a pin, the reverse-geocoded address (when
// available), and a tap-through to open the coordinates in the device's
// maps app. Neither sending nor viewing is role-gated — either side of a
// gig chat can share their location.
class _LocationBubble extends StatelessWidget {
  const _LocationBubble({
    required this.location,
    required this.address,
    required this.isDark,
  });

  final GeoPoint location;
  final String? address;
  final bool isDark;

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${location.latitude},${location.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(location.latitude, location.longitude);
    return Container(
      width: 220,
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: IgnorePointer(
              child: GoogleMap(
                style: isDark ? kDarkMapStyle : null,
                initialCameraPosition: CameraPosition(target: target, zoom: 15),
                markers: {
                  Marker(
                    markerId: const MarkerId('shared_location'),
                    position: target,
                  ),
                },
                // Small, purely-illustrative preview — every gesture and
                // control is off, and liteMode (Android only) renders a
                // static bitmap instead of a live map instance, which
                // matters here since a long location-sharing thread could
                // otherwise mount many live GoogleMap controllers at once.
                liteModeEnabled: true,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          if (address != null && address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openInMaps,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_rounded, color: kBlue, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Open in Maps',
                      style: TextStyle(
                        color: kBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Image attachment bubble ───────────────────────────────────────────────────
// `url` is null while the optimistic message is still uploading — shows a
// spinner placeholder until the confirmed doc (with a real download URL)
// replaces it.
class _ImageAttachmentBubble extends StatelessWidget {
  const _ImageAttachmentBubble({required this.url});

  final String? url;

  void _openFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null) {
      return Container(
        width: 220,
        height: 160,
        color: Colors.grey.shade300,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return GestureDetector(
      onTap: () => _openFullscreen(context, url),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 220,
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, _, _) => Container(
            width: 220,
            height: 160,
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}

// ── Video attachment bubble ───────────────────────────────────────────────────
// No thumbnail-generation package exists in this app, so the "thumbnail"
// before playback is a plain placeholder with a play icon rather than an
// actual video frame.
class _VideoAttachmentBubble extends StatefulWidget {
  const _VideoAttachmentBubble({required this.url});

  final String? url;

  @override
  State<_VideoAttachmentBubble> createState() => _VideoAttachmentBubbleState();
}

// Shows the video's first frame as its preview (there's no separate
// thumbnail upload, so this also works for videos sent before this
// existed). Never plays inline — tapping opens _FullscreenVideoPage.
class _VideoAttachmentBubbleState extends State<_VideoAttachmentBubble> {
  VideoPlayerController? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _VideoAttachmentBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An optimistic message gets its url once the upload finishes.
    if (oldWidget.url != widget.url) {
      _preview?.dispose();
      _preview = null;
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final url = widget.url;
    if (url == null) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      // iOS can stay black until a frame is explicitly requested.
      await controller.seekTo(const Duration(milliseconds: 1));
    } catch (e) {
      debugPrint('Video preview error: $e');
      controller.dispose();
      return;
    }
    if (!mounted || widget.url != url) {
      controller.dispose();
      return;
    }
    setState(() => _preview = controller);
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final preview = _preview;
    final ready = preview != null && preview.value.isInitialized;

    const width = 220.0;
    final height = ready
        ? (width / preview.value.aspectRatio).clamp(140.0, 300.0)
        : 160.0;

    return GestureDetector(
      onTap: url == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _FullscreenVideoPage(url: url),
              ),
            ),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black87),
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: preview.value.size.width,
                  height: preview.value.size.height,
                  child: VideoPlayer(preview),
                ),
              ),
            Center(
              child: url == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
            ),
            if (ready)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _fmt(preview.value.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Fullscreen video player ───────────────────────────────────────────────────
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.url});

  final String url;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late final VideoPlayerController _controller;
  bool _failed = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(_onTick);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('Video init error: $e');
          if (mounted) setState(() => _failed = true);
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _togglePlay() {
    final v = _controller.value;
    if (v.isPlaying) {
      _controller.pause();
    } else {
      // Replay from the start once it has finished.
      if (v.position >= v.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: _failed
                  ? const Text(
                      "Couldn't play this video.",
                      style: TextStyle(color: Colors.white70),
                    )
                  : v.isInitialized
                  ? AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            if (v.isInitialized && !_failed && _showControls) ...[
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      v.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Text(
                          _fmt(v.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            colors: const VideoProgressColors(
                              playedColor: kBlue,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _fmt(v.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_showControls || _failed)
              Positioned(
                top: 0,
                left: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── File attachment card ──────────────────────────────────────────────────────
// ── Date divider ───────────────────────────────────────────────────────────────
class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Call log card ──────────────────────────────────────────────────────────────
// One call log (see call_log.dart). Sits on the caller's side of the
// conversation — right if I called, left if the peer did — and is worded
// from the viewer's point of view ("Missed" for the one who was called,
// "Unanswered" for the caller).
class _CallLogCard extends StatefulWidget {
  const _CallLogCard({
    required this.call,
    required this.isDark,
    required this.formatClock,
    this.onCall,
  });

  final _Msg call;
  final bool isDark;
  final String Function(DateTime) formatClock;
  // Null hides the Call back / Call again button (e.g. chat disabled).
  final Future<void> Function()? onCall;

  @override
  State<_CallLogCard> createState() => _CallLogCardState();
}

class _CallLogCardState extends State<_CallLogCard> {
  bool _calling = false;

  Future<void> _call() async {
    if (_calling || widget.onCall == null) return;
    setState(() => _calling = true);
    try {
      await widget.onCall!();
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.call;
    final isMe = first.isMe;
    final isVideo = first.callType == 'video';
    final status = first.callStatus ?? 'missed';
    final kind = isVideo ? 'Video Call' : 'Voice Call';

    final String title;
    final IconData icon;
    final Color accent;
    switch (status) {
      case 'completed':
        title = kind;
        icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
        accent = kBlue;
      case 'declined':
        title = 'Declined $kind';
        icon = Icons.call_end_rounded;
        accent = Colors.grey;
      default:
        final word = isMe ? 'Unanswered' : 'Missed';
        title = '$word $kind';
        icon = isMe
            ? Icons.call_made_rounded
            : (isVideo
                  ? Icons.missed_video_call_rounded
                  : Icons.call_missed_rounded);
        accent = isMe ? Colors.grey : Colors.red;
    }

    final times = first.time != null ? widget.formatClock(first.time!) : '';
    final subtitle = status == 'completed'
        ? [
            if (times.isNotEmpty) times,
            formatCallDuration(first.callDuration),
          ].join(' · ')
        : times;

    final showButton = widget.onCall != null && status != 'completed';
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.grey.shade900
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: onSurface.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showButton) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _calling ? null : _call,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: kBlue.withValues(alpha: 0.35),
                        ),
                      ),
                      child: _calling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kBlue,
                              ),
                            )
                          : Text(
                              isMe ? 'Call again' : 'Call back',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kBlue,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentBubble extends StatelessWidget {
  const _FileAttachmentBubble({
    required this.url,
    required this.name,
    required this.isMe,
  });

  final String? url;
  final String name;
  final bool isMe;

  IconData get _icon {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'zip':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _open() async {
    final url = this.url;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final contentColor = isMe ? Colors.white : null;
    return InkWell(
      onTap: url == null ? null : _open,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: isMe ? Colors.white : kBlue, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: contentColor,
                decoration: url == null ? null : TextDecoration.underline,
              ),
            ),
          ),
          if (url == null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isMe ? Colors.white : kBlue,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
