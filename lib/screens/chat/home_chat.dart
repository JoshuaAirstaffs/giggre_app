import 'dart:async';

import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';
import 'package:giggre_app/features/call/video_call_screen.dart';
import 'package:giggre_app/main.dart' show navigatorKey;
import 'package:giggre_app/screens/chat/chat.dart';

class HomeChat extends StatefulWidget {
  const HomeChat({super.key});

  @override
  State<HomeChat> createState() => _HomeChatState();
}

class _HomeChatState extends State<HomeChat>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _hasUnread = false;
  bool _hasUnreadGig = false;
  final List<StreamSubscription> _roomSubs = [];
  StreamSubscription? _gigRoomsStreamSub;
  final List<StreamSubscription> _gigRoomSubs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenForUnread();
    _listenForUnreadGig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final sub in _roomSubs) sub.cancel();
    _gigRoomsStreamSub?.cancel();
    for (final sub in _gigRoomSubs) sub.cancel();
    super.dispose();
  }

  void _listenForUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('userId', isEqualTo: uid)
        .where('isSupport', isEqualTo: true)
        .get()
        .then((roomsSnap) {
      if (roomsSnap.docs.isEmpty) return;

      final Map<int, bool> roomUnread = {};

          for (int i = 0; i < roomsSnap.docs.length; i++) {
            final room = roomsSnap.docs[i];
            final sub = FirebaseFirestore.instance
                .collection('chat_rooms')
                .doc(room.id)
                .collection('messages')
                .where('isSupport', isEqualTo: true)
                .where('hasSeen', isEqualTo: false)
                .limit(1)
                .snapshots()
                .map((s) => s.docs.isNotEmpty)
                .listen(
                  (hasUnread) {
                    roomUnread[i] = hasUnread;
                    final anyUnread = roomUnread.values.any((v) => v);
                    if (mounted) setState(() => _hasUnread = anyUnread);
                  },
                  onError: (e) =>
                      debugPrint('[HomeChat] message stream error: $e'),
                );
            _roomSubs.add(sub);
          }
        });
  }

  void _listenForUnreadGig() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _gigRoomsStreamSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen(
          (roomsSnap) {
            for (final sub in _gigRoomSubs) sub.cancel();
            _gigRoomSubs.clear();

            if (roomsSnap.docs.isEmpty) {
              if (mounted) setState(() => _hasUnreadGig = false);
              return;
            }

            final Map<int, bool> roomUnread = {};

            for (int i = 0; i < roomsSnap.docs.length; i++) {
              final room = roomsSnap.docs[i];
              final participants =
                  (room.data()['participants'] as List<dynamic>?) ?? [];
              final otherUid = participants.firstWhere(
                (p) => p != uid,
                orElse: () => '',
              ) as String;

              if (otherUid.isEmpty) continue;

              final sub = FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(room.id)
                  .collection('messages')
                  .where('senderId', isEqualTo: otherUid)
                  .where('hasSeen', isEqualTo: false)
                  .limit(1)
                  .snapshots()
                  .map((s) => s.docs.isNotEmpty)
                  .listen(
                    (hasUnread) {
                      roomUnread[i] = hasUnread;
                      final anyUnread = roomUnread.values.any((v) => v);
                      if (mounted) setState(() => _hasUnreadGig = anyUnread);
                    },
                    onError: (e) =>
                        debugPrint('[HomeChat] gig message stream error: $e'),
                  );
              _gigRoomSubs.add(sub);
            }
          },
          onError: (e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[HomeChat] gig rooms stream error: $e');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Chats',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kBlue,
          labelColor: kBlue,
          unselectedLabelColor: onSurface.withValues(alpha: 0.5),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded),
                  if (_hasUnreadGig)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              text: 'Gig Chats',
            ),
            Tab(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.confirmation_number_outlined),
                  if (_hasUnread)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              text: 'Support',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_GigChatsTab(), _SupportTab()],
      ),
    );
  }
}

// ── Gig Chats Tab ─────────────────────────────────────────────────────────────

class _GigChatsTab extends StatefulWidget {
  const _GigChatsTab();

  @override
  State<_GigChatsTab> createState() => _GigChatsTabState();
}

class _GigChatsTabState extends State<_GigChatsTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _stream = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          debugPrint('GigChatsTab error: ${snap.error}');
          return Center(
            child: Text(
              'Error loading chats:\n${snap.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          );
        }

        final docs = List.of(snap.data?.docs ?? []);
        docs.sort((a, b) {
          final aTime = a.data()['lastMessageAt'] as Timestamp?;
          final bTime = b.data()['lastMessageAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  'No gig chats yet',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final rawDate = data['lastMessageAt'] ?? data['createdAt'];
              final date =
                  rawDate != null ? (rawDate as Timestamp).toDate() : null;
              final sender = data['lastMessageSender'] as String? ?? '';
              final lastMessage = data['lastMessage'] as String? ?? '';
              final displayMessage =
                  sender.isNotEmpty ? '$sender: $lastMessage' : lastMessage;

              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              final participants =
                  (data['participants'] as List<dynamic>?) ?? [];
              final peerUid = participants
                  .firstWhere((p) => p != uid, orElse: () => '')
                  as String;

              // Resolve the correct display name for the peer.
              // If the current user created the room, the peer is sendTo.
              // If the current user is the receiver, the peer is createdByName.
              final createdByUid = data['createdByUid'] as String? ?? '';
              final createdByName = data['createdByName'] as String? ?? '';
              final sendTo = data['sendTo'] as String? ?? 'Gig Chat';
              final peerDisplayName = (createdByUid.isNotEmpty && uid != createdByUid)
                  ? (createdByName.isNotEmpty ? createdByName : sendTo)
                  : sendTo;

              return _ChatHomeItem(
                roomId: docs[i].id,
                sendTo: peerDisplayName,
                subject: data['subject'] as String? ?? 'Gig Chat',
                message: displayMessage,
                status: data['status'] as String? ?? 'open',
                date: date,
                isGigChat: true,
                gigId: data['gigId'] as String? ?? '',
                peerUid: peerUid,
              );
            },
          ),
        );
      },
    );
  }
}

// ── Test Voice Call Card ──────────────────────────────────────────────────────

class _TestCallCard extends StatefulWidget {
  const _TestCallCard();

  @override
  State<_TestCallCard> createState() => _TestCallCardState();
}

class _TestCallCardState extends State<_TestCallCard> {
  static String _generateChannelName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return '${uid}_$timestamp';
  }

  static const _targetUserId = 'GIG000014';
  static const _targetUserName = 'htest';
  static const _token = '';

  final _channelName = _generateChannelName();
  bool _isCalling = false;

  Future<void> _startCall() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .get();
    final myName = myDoc.data()?['name'] ?? 'Unknown';

    setState(() => _isCalling = true);

    StreamSubscription? callStatusSub;

    try {
      final targetSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: _targetUserId)
          .limit(1)
          .get();

      if (targetSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final targetDocId = targetSnap.docs.first.id;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetDocId)
          .set({
        'incomingCall': {
          'callerId': me.uid,
          'callerName': myName,
          'channelName': _channelName,
          'token': _token,
          'status': 'ringing',
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;

      callStatusSub = FirebaseFirestore.instance
          .collection('users')
          .doc(targetDocId)
          .snapshots()
          .listen((snap) {
        final incomingCall = snap.data()?['incomingCall'];
        if (incomingCall == null) {
          callStatusSub?.cancel();
          final ctx = navigatorKey?.currentContext;
          if (ctx != null && Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
          }
        }
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceCallScreen(
            channelName: _channelName,
            token: _token,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Call error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    } finally {
      callStatusSub?.cancel();

      final targetSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: _targetUserId)
          .limit(1)
          .get();
      if (targetSnap.docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(targetSnap.docs.first.id)
            .update({'incomingCall': FieldValue.delete()});
      }

      if (mounted) setState(() => _isCalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.call, color: kBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Test Voice Call',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.person, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _targetUserName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _targetUserId,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCalling ? null : _startCall,
              icon: _isCalling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.call, size: 18),
              label: Text(
                _isCalling
                    ? 'Calling $_targetUserName...'
                    : 'Call $_targetUserName',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Test Video Call Card ──────────────────────────────────────────────────────

class _TestVideoCallCard extends StatefulWidget {
  const _TestVideoCallCard();

  @override
  State<_TestVideoCallCard> createState() => _TestVideoCallCardState();
}

class _TestVideoCallCardState extends State<_TestVideoCallCard> {
  static String _generateChannelName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return '${uid}_$timestamp';
  }

  static const _targetUserId = 'GIG000014';
  static const _targetUserName = 'htest';
  static const _token = '';

  late String _channelName;
  bool _isCalling = false;

  @override
  void initState() {
    super.initState();
    _channelName = _generateChannelName();
  }

  Future<void> _startCall() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .get();
    final myName = myDoc.data()?['name'] ?? 'Unknown';

    // ✅ only flip the flag, channel name stays fixed for this call
    setState(() => _isCalling = true);

    StreamSubscription? callStatusSub;

    try {
      final targetSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: _targetUserId)
          .limit(1)
          .get();

      if (targetSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final targetDocId = targetSnap.docs.first.id;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetDocId)
          .set({
        'incomingCall': {
          'callerId': me.uid,
          'callerName': myName,
          'channelName': _channelName,
          'token': _token,
          'status': 'ringing',
          'isVideo': true,
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;

      callStatusSub = FirebaseFirestore.instance
          .collection('users')
          .doc(targetDocId)
          .snapshots()
          .listen((snap) {
        final incomingCall = snap.data()?['incomingCall'];
        if (incomingCall == null) {
          callStatusSub?.cancel();
          final ctx = navigatorKey?.currentContext;
          if (ctx != null && Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
          }
        }
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            channelName: _channelName,
            token: _token,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Video call error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    } finally {
      callStatusSub?.cancel();

      final targetSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: _targetUserId)
          .limit(1)
          .get();
      if (targetSnap.docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(targetSnap.docs.first.id)
            .update({'incomingCall': FieldValue.delete()});
      }

      if (mounted) {
        setState(() {
          _isCalling = false;
          _channelName = _generateChannelName(); // ✅ fresh for next call
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Test Video Call',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.person, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _targetUserName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _targetUserId,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCalling ? null : _startCall,
              icon: _isCalling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.videocam_rounded, size: 18),
              label: Text(
                _isCalling
                    ? 'Calling $_targetUserName...'
                    : 'Video Call $_targetUserName',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Support Tab ───────────────────────────────────────────────────────────────

class _SupportTab extends StatefulWidget {
  const _SupportTab();

  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> {
  static const _limit = 10;

  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _rooms = [];

  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _fetchRooms();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms({bool refresh = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (refresh) {
      _rooms.clear();
      _lastDoc = null;
      _hasMore = true;
    }

    try {
      var query = FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('userId',
              isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(_limit);

      if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDoc = snapshot.docs.last;
        _rooms.addAll(
            snapshot.docs.map((d) => {...d.data(), 'roomId': d.id}));
      }

      if (snapshot.docs.length < _limit) _hasMore = false;
    } catch (e) {
      debugPrint('Error fetching rooms: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _rooms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No support tickets yet',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchRooms(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _rooms.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _rooms.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final room = _rooms[i];
          final rawDate = room['lastMessageAt'] ?? room['createdAt'];
          final date =
              rawDate != null ? (rawDate as Timestamp).toDate() : null;
          final sender = room['lastMessageSender'] as String? ?? '';
          final lastMessage = room['lastMessage'] as String? ?? '';
          final displayMessage =
              sender.isNotEmpty ? '$sender: $lastMessage' : lastMessage;

          return _ChatHomeItem(
            roomId: room['roomId'] ?? '',
            sendTo: room['sendTo'] ?? '',
            subject: room['subject'] ?? 'No subject',
            message: displayMessage,
            status: room['status'] ?? 'open',
            date: date,
          );
        },
      ),
    );
  }
}

// ── Chat Home Item ────────────────────────────────────────────────────────────

class _ChatHomeItem extends StatefulWidget {
  const _ChatHomeItem({
    required this.subject,
    required this.message,
    required this.status,
    required this.roomId,
    required this.sendTo,
    this.date,
    this.isGigChat = false,
    this.gigId = '',
    this.peerUid = '',
  });

  final String subject;
  final String message;
  final String status;
  final String roomId;
  final String sendTo;
  final DateTime? date;
  final bool isGigChat;
  final String gigId;
  final String peerUid;

  @override
  State<_ChatHomeItem> createState() => _ChatHomeItemState();
}

class _ChatHomeItemState extends State<_ChatHomeItem> {
  late final Stream<bool> _unreadStream = widget.isGigChat
      ? FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.roomId)
          .collection('messages')
          .where('hasSeen', isEqualTo: false)
          .where('senderId',
              isNotEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .limit(1)
          .snapshots()
          .map((snap) => snap.docs.isNotEmpty)
      : FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.roomId)
          .collection('messages')
          .where('isSupport', isEqualTo: true)
          .where('hasSeen', isEqualTo: false)
          .limit(1)
          .snapshots()
          .map((snap) => snap.docs.isNotEmpty);

  Future<void> _markMessagesAsSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final base = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .where('hasSeen', isEqualTo: false);

    final q = widget.isGigChat
        ? base.where('senderId', isNotEqualTo: uid)
        : base.where('isSupport', isEqualTo: true);

    final snap = await q.get();
    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'hasSeen': true});
    }
    await batch.commit();
  }

  Future<void> _onTap() async {
    if (!mounted) return;
    if (widget.isGigChat && widget.peerUid.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Chat(
            roomId: widget.roomId,
            isGigChat: true,
            gigChatParams: GigChatParams(
              gigId: widget.gigId,
              peerUid: widget.peerUid,
              peerName: widget.sendTo,
            ),
          ),
        ),
      );
    } else {
      await Navigator.pushNamed(context, '/chat/${widget.roomId}');
    }
    await _markMessagesAsSeen();
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
    if (diff < 7) return '${_weekday(dt.weekday)} $timeStr';
    return '${_shortDate(dt)} $timeStr';
  }

  String _weekday(int wd) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[wd - 1];
  }

  String _shortDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  Color get _statusColor => switch (widget.status) {
        'resolved' => Colors.green,
        'in_progress' => Colors.orange,
        _ => const Color(0xFFFBBF24),
      };

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[900] : Colors.white;

    return StreamBuilder<bool>(
      stream: _unreadStream,
      builder: (context, snapshot) {
        final hasUnread = snapshot.data ?? false;

        return GestureDetector(
          onTap: _onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.isGigChat
                          ? const Color(0xFF3B82F6)
                          : _statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.isGigChat
                          ? Icons.work_outline_rounded
                          : Icons.support_agent,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.sendTo,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kBlue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'New',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            if (widget.date != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                _formatTime(widget.date!),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!widget.isGigChat) ...[
                          Text(
                            'Subject: ${widget.subject}',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                        ],
                        SizedBox(
                          width: 200,
                          child: Text(
                            widget.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}