import 'dart:async';

import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';
import 'package:giggre_app/features/call/video_call_screen.dart';
import 'package:giggre_app/main.dart' show navigatorKey;

class HomeChat extends StatefulWidget {
  const HomeChat({super.key});

  @override
  State<HomeChat> createState() => _HomeChatState();
}

class _HomeChatState extends State<HomeChat>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _hasUnread = false;
  final List<StreamSubscription> _roomSubs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenForUnread();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final sub in _roomSubs) sub.cancel();
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
            const Tab(icon: Icon(Icons.people_outline), text: 'Friends'),
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
        children: const [_FriendsTab(), _SupportTab()],
      ),
    );
  }
}

// ── Friends Tab ───────────────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: const [
            _TestCallCard(),
            _TestVideoCallCard(),
          ],
        ),
      ),
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
        _rooms
            .addAll(snapshot.docs.map((d) => {...d.data(), 'roomId': d.id}));
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
  });

  final String subject;
  final String message;
  final String status;
  final String roomId;
  final String sendTo;
  final DateTime? date;

  @override
  State<_ChatHomeItem> createState() => _ChatHomeItemState();
}

class _ChatHomeItemState extends State<_ChatHomeItem> {
  late final Stream<bool> _unreadStream = FirebaseFirestore.instance
      .collection('chat_rooms')
      .doc(widget.roomId)
      .collection('messages')
      .where('isSupport', isEqualTo: true)
      .where('hasSeen', isEqualTo: false)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty);

  Future<void> _markMessagesAsSeen() async {
    final snap = await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .where('isSupport', isEqualTo: true)
        .where('hasSeen', isEqualTo: false)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'hasSeen': true});
    }
    await batch.commit();
  }

  Future<void> _onTap() async {
    if (!mounted) return;
    await Navigator.pushNamed(context, '/chat/${widget.roomId}');
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
                      color: _statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.support_agent, color: Colors.white),
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
                        Text(
                          'Subject: ${widget.subject}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
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