import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';
import 'package:giggre_app/features/call/video_call_screen.dart';
import 'package:giggre_app/main.dart' show navigatorKey;
import 'package:giggre_app/screens/chat/chat.dart';
import 'package:giggre_app/features/chat/message_requests.dart';
import 'package:giggre_app/features/chat/user_search_screen.dart';
import 'package:giggre_app/features/group_chat/create_group_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';
import 'package:giggre_app/features/group_chat/group_widgets.dart';
import 'package:giggre_app/features/live_support/live_support_bubble.dart'; // TEMP: live support

// Support auto-replies are authored as HTML (rendered properly inside the
// conversation via flutter_html) — this list preview is a single-line
// ellipsis snippet, so tags are stripped rather than rendered.
String _stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class HomeChat extends StatefulWidget {
  // False when hosted as the Chat tab root inside WorkerShell — suppresses
  // the auto back arrow since there's no route to pop within the tab.
  final bool showBackButton;

  /// Bumped by the app shell each time the Chats tab is opened, so a search
  /// left from the previous visit is cleared.
  final int visitGeneration;

  const HomeChat({
    super.key,
    this.showBackButton = true,
    this.visitGeneration = 0,
  });

  @override
  State<HomeChat> createState() => _HomeChatState();
}

class _HomeChatState extends State<HomeChat>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _hasUnread = false;
  bool _hasUnreadGig = false;
  bool _hasUnreadGroup = false;
  StreamSubscription<bool>? _groupUnreadSub;
  final _resetSearch = ValueNotifier<int>(0);

  @override
  void didUpdateWidget(HomeChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitGeneration != widget.visitGeneration) {
      _resetSearch.value++;
    }
  }
  final List<StreamSubscription> _roomSubs = [];
  StreamSubscription? _gigRoomsStreamSub;
  final List<StreamSubscription> _gigRoomSubs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        // Leaving Gig Chats (for Support) clears its search too.
        if (!_tabController.indexIsChanging) {
          _resetSearch.value++;
          if (mounted) setState(() {});
        }
      });
    _listenForUnread();
    _listenForUnreadGig();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _groupUnreadSub = GroupChatService.anyUnread(uid).listen(
        (v) => mounted ? setState(() => _hasUnreadGroup = v) : null,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _groupUnreadSub?.cancel();
    _resetSearch.dispose();
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
              final otherUid =
                  participants.firstWhere((p) => p != uid, orElse: () => '')
                      as String;

              if (otherUid.isEmpty) continue;
              // Unanswered message requests don't light the badge
              if (hiddenFromInbox(room.data(), uid)) continue;

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

  void _showDeleteInfoModal(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          MediaQuery.of(ctx).viewPadding.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
                Icon(Icons.info_outline_rounded, color: kBlue),
                const SizedBox(width: 8),
                Text(
                  'Deleting messages',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You can delete a message you sent within 2 minutes of sending it. '
              'After that window passes, it can no longer be deleted.\n\n'
              'A deleted message is replaced with "Message has been removed" for '
              'both you and the other person — this can\'t be undone.',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// New chat (find someone on Giggre) or New group.
  void _showNewSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NewOption(
                icon: Icons.person_add_alt_1_rounded,
                title: 'New chat',
                subtitle: 'Find someone on Giggre',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserSearchScreen()),
                  );
                },
              ),
              _NewOption(
                icon: Icons.group_add_rounded,
                title: 'New group',
                subtitle: "With people you've already chatted with",
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        automaticallyImplyLeading: widget.showBackButton,
        title: Text(
          'Chats',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: onSurface),
            tooltip: 'About deleting messages',
            onPressed: () => _showDeleteInfoModal(context),
          ),
        ],
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
                  if (_hasUnreadGig || _hasUnreadGroup)
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
      floatingActionButton:
          _tabController.index == 0 &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? FloatingActionButton.extended(
              heroTag: 'chats_new',
              backgroundColor: kBlue,
              foregroundColor: Colors.white,
              onPressed: () => _showNewSheet(context),
              icon: const Icon(Icons.edit_square, size: 20),
              label: const Text(
                'New',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [_GigChatsTab(resetSearch: _resetSearch), const _SupportTab()],
      ),
    );
  }
}

// ── Gig Chats Tab ─────────────────────────────────────────────────────────────

class _GigChatsTab extends StatefulWidget {
  const _GigChatsTab({required this.resetSearch});

  /// Fires when the user leaves and comes back; clears the search.
  final ValueNotifier<int> resetSearch;

  @override
  State<_GigChatsTab> createState() => _GigChatsTabState();
}

class _GigChatsTabState extends State<_GigChatsTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _groupStream;
  // "Missed calls" filter — rooms where the peer's last call to me went
  // unanswered and hasn't been followed up by another call since (see
  // missedCallFor in call_log.dart).
  bool _missedOnly = false;
  final _search = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    widget.resetSearch.removeListener(_clearSearch);
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_search.text.isEmpty && _query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _search.clear();
      _query = '';
    });
  }

  // Filters once typing pauses, not on every keystroke.
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.resetSearch.addListener(_clearSearch);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _stream = uid == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('chat_rooms')
              .where('participants', arrayContains: uid)
              .snapshots();
    _groupStream = uid == null
        ? const Stream.empty()
        : GroupChatService.myGroups(uid);
  }

  @override
  Widget build(BuildContext context) {
    // Groups (group_chats) are listed together with the one-to-one rooms.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groupStream,
      builder: (context, groupSnap) {
        if (groupSnap.hasError) {
          debugPrint('GigChatsTab groups error: ${groupSnap.error}');
        }
        final groups = groupSnap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return _buildRooms(context, groups);
      },
    );
  }

  Widget _buildRooms(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
  ) {
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

        // Blocking a peer no longer hides this room from the list — the
        // conversation stays visible (with history), it's just no longer
        // possible to send/receive messages in it. See Chat's _isBlocked.
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final all = snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final requestCount = all
            .where(
              (d) =>
                  d.data()['requestStatus'] == 'pending' &&
                  isRequestToMe(d.data(), myUid) &&
                  !isEmptyDirectChat(d.data()),
            )
            .length;
        final docs = all
            .where((d) => !hiddenFromInbox(d.data(), myUid))
            .toList();
        docs.sort((a, b) {
          final aTime = a.data()['lastMessageAt'] as Timestamp?;
          final bTime = b.data()['lastMessageAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        final requestsEntry = _RequestsEntry(
          count: requestCount,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _MessageRequestsScreen()),
          ),
        );

        if (docs.isEmpty && groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  'No chats yet',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap New to message someone or start a group',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                if (requestCount > 0) ...[
                  const SizedBox(height: 16),
                  requestsEntry,
                ],
              ],
            ),
          );
        }

        final missedDocs =
            docs.where((d) => d.data()['missedCallFor'] == myUid).toList()
              ..sort((a, b) {
                final aTime = a.data()['missedCallAt'] as Timestamp?;
                final bTime = b.data()['missedCallAt'] as Timestamp?;
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });
        final byTab = _missedOnly ? missedDocs : docs;
        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty
            ? byTab
            : byTab
                  .where(
                    (d) => _peerName(d.data(), myUid).toLowerCase().contains(q),
                  )
                  .toList();
        // Groups are listed under All only, and searched by group name.
        final shownGroups = _missedOnly
            ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
            : q.isEmpty
            ? groups
            : groups
                  .where(
                    (g) => ((g.data()['name'] as String?) ?? '')
                        .toLowerCase()
                        .contains(q),
                  )
                  .toList();

        return Column(
          children: [
            if (requestCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: SizedBox(width: double.infinity, child: requestsEntry),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _SearchChatsField(
                controller: _search,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchDebounce?.cancel();
                  setState(() {
                    _search.clear();
                    _query = '';
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    showCheckmark: false,
                    label: const Text('All'),
                    selected: !_missedOnly,
                    onSelected: (_) => setState(() => _missedOnly = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(
                      Icons.call_missed_rounded,
                      size: 16,
                      color: missedDocs.isEmpty ? null : Colors.red,
                    ),
                    label: Text(
                      missedDocs.isEmpty
                          ? 'Missed calls'
                          : 'Missed calls (${missedDocs.length})',
                    ),
                    selected: _missedOnly,
                    onSelected: (_) => setState(() => _missedOnly = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty && shownGroups.isEmpty && q.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No chats match "${_query.trim()}"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _FindOnGiggre(query: _query.trim()),
                          ],
                        ),
                      ),
                    )
                  : shown.isEmpty && shownGroups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.call_missed_rounded,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No missed calls',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildList(shown, shownGroups, findQuery: q.isEmpty ? null : _query.trim()),
            ),
          ],
        );
      },
    );
  }

  // The other person's name as this user sees it. If the current user created
  // the room, the peer is sendTo; if they're the receiver, it's createdByName.
  String _peerName(Map<String, dynamic> data, String uid) {
    final createdByUid = data['createdByUid'] as String? ?? '';
    final createdByName = data['createdByName'] as String? ?? '';
    final sendTo = data['sendTo'] as String? ?? 'Gig Chat';
    return (createdByUid.isNotEmpty && uid != createdByUid)
        ? (createdByName.isNotEmpty ? createdByName : sendTo)
        : sendTo;
  }

  Widget _buildList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rooms,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groups, {
    String? findQuery,
  }) {
    // Rooms arrive already sorted (or in missed-call order); groups are
    // slotted in by their latest message.
    final docs = [...rooms];
    if (groups.isNotEmpty) {
      DateTime? at(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
          (d.data()['lastMessageAt'] as Timestamp?)?.toDate();
      docs
        ..addAll(groups)
        ..sort((a, b) {
          final ta = at(a), tb = at(b);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
    }
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView.builder(
        // Bottom room so the New button never covers the last chat.
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        itemCount: docs.length + (findQuery == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == docs.length) {
            // After the matching chats: the same name among everyone.
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FindOnGiggre(query: findQuery!),
            );
          }
          if (docs[i].reference.parent.id == 'group_chats') {
            final id = docs[i].id;
            return GroupListTile(
              key: ValueKey('group_$id'),
              groupId: id,
              group: docs[i].data(),
              myUid: myUid,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(groupId: id),
                ),
              ),
            );
          }
          final data = docs[i].data();
          final rawDate = _missedOnly
              ? (data['missedCallAt'] ?? data['lastMessageAt'])
              : (data['lastMessageAt'] ?? data['createdAt']);
          final date = rawDate != null ? (rawDate as Timestamp).toDate() : null;

          final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
          final participants = (data['participants'] as List<dynamic>?) ?? [];
          final peerUid =
              participants.firstWhere((p) => p != uid, orElse: () => '')
                  as String;

          final peerDisplayName = _peerName(data, uid);

          // Gig chats are stored as plain text (never HTML), and the room
          // doc is shared by both participants — 'You' is only correct
          // from the sender's own point of view, so the label is derived
          // here from who actually sent it rather than trusted verbatim.
          final senderId = data['lastMessageSenderId'] as String? ?? '';
          final sender = senderId.isEmpty
              ? ''
              : (senderId == uid ? 'You' : peerDisplayName);
          final lastMessage = data['lastMessage'] as String? ?? '';
          final displayMessage = _missedOnly
              ? (data['missedCallType'] == 'video'
                    ? '🎥 Missed video call'
                    : '📞 Missed voice call')
              : sender.isNotEmpty
              ? '$sender: $lastMessage'
              : lastMessage;

          return _ChatHomeItem(
            // Keyed so a row's loaded photo and unread state stay with its
            // chat when search or a new message reorders the list.
            key: ValueKey(docs[i].id),
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
  }
}

/// "Find "ana" on Giggre": takes a chat search over to people search.
class _FindOnGiggre extends StatelessWidget {
  const _FindOnGiggre({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? kCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserSearchScreen(initialQuery: query),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: blueText(context).withValues(alpha: 0.12),
                child: Icon(Icons.person_search_rounded, color: blueText(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Find ',
                    children: [
                      TextSpan(
                        text: '"$query"',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' on Giggre'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: blueText(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: blueText(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewOption extends StatelessWidget {
  const _NewOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: blueText(context).withValues(alpha: 0.12),
        child: Icon(icon, color: blueText(context)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

/// Filters the Gig Chats list by the other person's name.
class _SearchChatsField extends StatelessWidget {
  const _SearchChatsField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search chats',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              ),
        isDense: true,
        filled: true,
        fillColor: isDark ? kCard : Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ── Message requests ──────────────────────────────────────────────────────────

/// "Message requests (n)" row above the chat list.
class _RequestsEntry extends StatelessWidget {
  const _RequestsEntry({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: kBlue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_chat_unread_outlined, color: kBlue),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  count == 1
                      ? '1 message request'
                      : '$count message requests',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chats from people the user hasn't worked with, waiting for Accept or
/// Decline. Declined ones stay here so they can still be accepted.
class _MessageRequestsScreen extends StatefulWidget {
  const _MessageRequestsScreen();

  @override
  State<_MessageRequestsScreen> createState() => _MessageRequestsScreenState();
}

class _MessageRequestsScreenState extends State<_MessageRequestsScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: _uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Message requests',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = (snap.data?.docs ?? const [])
              .where(
                (d) =>
                    isRequestToMe(d.data(), _uid) &&
                    !isEmptyDirectChat(d.data()),
              )
              .toList()
            ..sort((a, b) {
              final aTime = a.data()['lastMessageAt'] as Timestamp?;
              final bTime = b.data()['lastMessageAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'No message requests. When someone you haven’t worked '
                  'with messages you, it shows up here first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final participants =
                  (data['participants'] as List<dynamic>?) ?? [];
              final peerUid =
                  participants.firstWhere((p) => p != _uid, orElse: () => '')
                      as String;
              // The asker created the room, so they're createdByName
              final peerName = (data['createdByName'] as String?) ?? '';
              final declined = data['requestStatus'] == 'declined';
              final rawDate = data['lastMessageAt'] ?? data['createdAt'];
              return _ChatHomeItem(
                key: ValueKey(docs[i].id),
                roomId: docs[i].id,
                sendTo: peerName.isNotEmpty ? peerName : 'Someone',
                subject: 'Direct message',
                message: declined
                    ? 'Declined'
                    : (data['lastMessage'] as String?) ?? '',
                status: data['status'] as String? ?? 'open',
                date: rawDate is Timestamp ? rawDate.toDate() : null,
                isGigChat: true,
                peerUid: peerUid,
              );
            },
          );
        },
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('User not found')));
        }
        return;
      }

      final targetDocId = targetSnap.docs.first.id;

      await FirebaseFirestore.instance.collection('users').doc(targetDocId).set(
        {
          'incomingCall': {
            'callerId': me.uid,
            'callerName': myName,
            'channelName': _channelName,
            'token': _token,
            'status': 'ringing',
            'createdAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

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
          builder: (_) =>
              VoiceCallScreen(channelName: _channelName, token: _token),
        ),
      );
    } catch (e) {
      debugPrint('Call error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
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
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('User not found')));
        }
        return;
      }

      final targetDocId = targetSnap.docs.first.id;

      await FirebaseFirestore.instance.collection('users').doc(targetDocId).set(
        {
          'incomingCall': {
            'callerId': me.uid,
            'callerName': myName,
            'channelName': _channelName,
            'token': _token,
            'status': 'ringing',
            'isVideo': true,
            'createdAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

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
          builder: (_) =>
              VideoCallScreen(channelName: _channelName, token: _token),
        ),
      );
    } catch (e) {
      debugPrint('Video call error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
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
                child: const Icon(
                  Icons.videocam_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _targetUserId,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(_limit);

      if (_lastDoc != null) query = query.startAfterDocument(_lastDoc!);

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDoc = snapshot.docs.last;
        _rooms.addAll(snapshot.docs.map((d) => {...d.data(), 'roomId': d.id}));
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
          final date = rawDate != null ? (rawDate as Timestamp).toDate() : null;
          final sender = room['lastMessageSender'] as String? ?? '';
          final lastMessage = _stripHtml(room['lastMessage'] as String? ?? '');
          final displayMessage = sender.isNotEmpty
              ? '$sender: $lastMessage'
              : lastMessage;

          return _ChatHomeItem(
            key: ValueKey(room['roomId'] ?? i),
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
    super.key,
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
  // Photo URLs fetched this session ('' = no photo), so rows that search
  // hides and shows again don't read the user doc again.
  static final Map<String, String> _photoCache = {};

  String? _peerPhotoUrl;
  late final String _unreadKey;
  late final _UnreadWatch _unread;

  @override
  void initState() {
    super.initState();
    if (widget.isGigChat && widget.peerUid.isNotEmpty) {
      final cached = _photoCache[widget.peerUid];
      if (cached != null) {
        _peerPhotoUrl = cached.isEmpty ? null : cached;
      } else {
        _fetchPeerPhoto();
      }
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _unreadKey = '$uid|${widget.isGigChat}|${widget.roomId}';
    _unread = _UnreadWatch.acquire(_unreadKey, _unreadQuery);
  }

  @override
  void dispose() {
    _unread.release(_unreadKey);
    super.dispose();
  }

  bool get _isLiveSupport => isLiveSupportAccount(widget.peerUid); // TEMP: live support

  Future<void> _fetchPeerPhoto() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.peerUid)
          .get();
      final url = doc.data()?['photoUrl'] as String?;
      _photoCache[widget.peerUid] = url ?? '';
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() => _peerPhotoUrl = url);
      }
    } catch (_) {}
  }

  Query<Map<String, dynamic>> _unreadQuery() {
    final messages = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .where('hasSeen', isEqualTo: false);
    return widget.isGigChat
        ? messages.where(
            'senderId',
            isNotEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
          )
        : messages.where('isSupport', isEqualTo: true);
  }

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
    final backgroundColor = isDarkMode ? kCard : Colors.white;

    return ValueListenableBuilder<bool>(
      valueListenable: _unread.value,
      builder: (context, hasUnread, _) {

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
                  widget.isGigChat
                      ? CircleAvatar(
                          radius: 20,
                          backgroundColor: _isLiveSupport // TEMP: live support
                              ? Colors.white
                              : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          backgroundImage: _isLiveSupport // TEMP: live support
                              ? liveSupportAvatar
                              : (_peerPhotoUrl != null &&
                                    _peerPhotoUrl!.isNotEmpty)
                              ? CachedNetworkImageProvider(_peerPhotoUrl!)
                              : null,
                          child:
                              !_isLiveSupport && // TEMP: live support
                                  (_peerPhotoUrl == null ||
                                      _peerPhotoUrl!.isEmpty)
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: Color(0xFF3B82F6),
                                )
                              : null,
                        )
                      : Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _statusColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.support_agent,
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

/// One unread listener per chat row, shared by every row showing that chat
/// and kept for a minute after the last one goes. Search hides and re-shows
/// rows constantly; without this each change closed and re-opened a
/// Firestore query per chat.
class _UnreadWatch {
  _UnreadWatch._(Query<Map<String, dynamic>> query) {
    _sub = query.limit(1).snapshots().listen(
      (snap) => value.value = snap.docs.isNotEmpty,
      onError: (Object e) => debugPrint('[HomeChat] unread stream error: $e'),
    );
  }

  static final Map<String, _UnreadWatch> _all = {};

  final ValueNotifier<bool> value = ValueNotifier(false);
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _sub;
  int _users = 0;
  Timer? _closeTimer;

  static _UnreadWatch acquire(
    String key,
    Query<Map<String, dynamic>> Function() query,
  ) {
    final watch = _all.putIfAbsent(key, () => _UnreadWatch._(query()));
    watch._users++;
    watch._closeTimer?.cancel();
    watch._closeTimer = null;
    return watch;
  }

  void release(String key) {
    if (--_users > 0) return;
    _closeTimer = Timer(const Duration(minutes: 1), () {
      _sub.cancel();
      value.dispose();
      _all.remove(key);
    });
  }
}
