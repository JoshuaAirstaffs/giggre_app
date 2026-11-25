import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/widgets/skeleton.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/services/content_filter_service.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Reusable modal helper ─────────────────────────────────────────────────────

void _showModal(
  BuildContext context, {
  required String title,
  required String message,
  required bool isSuccess,
}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              color: isSuccess ? Colors.green : Colors.red,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSuccess ? Colors.green : Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── ContactUs ─────────────────────────────────────────────────────────────────

class ContactUs extends StatefulWidget {
  const ContactUs({super.key, this.showTicketsTab = true});

  final bool showTicketsTab;

  @override
  State<ContactUs> createState() => _ContactUsState();
}

class _ContactUsState extends State<ContactUs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.showTicketsTab ? 2 : 1,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Contact Us',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: widget.showTicketsTab
            ? TabBar(
                controller: _tabController,
                indicatorColor: kBlue,
                labelColor: kBlue,
                unselectedLabelColor: onSurface.withValues(alpha: 0.5),
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Send Message'),
                  Tab(text: 'My Tickets'),
                ],
              )
            : null,
      ),
      body: widget.showTicketsTab
          ? TabBarView(
              controller: _tabController,
              children: const [_SendMessageTab(), _MyTicketsTab()],
            )
          : const _SendMessageTab(),
    );
  }
}

// ── Send Message ──────────────────────────────────────────────────────────────

class _SendMessageTab extends StatelessWidget {
  const _SendMessageTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Column(
            children: [
              const _HelpContainer(),
              const SizedBox(height: 16),
              Row(
                spacing: 16,
                children: [
                  Expanded(
                    child: _CopyContainer(
                      title: 'Email',
                      value: 'support@giggre.com',
                      icon: Icons.mail_outline_outlined,
                    ),
                  ),
                  Expanded(
                    child: _CopyContainer(
                      title: 'Website',
                      value: 'https://giggre.com/',
                      icon: Icons.language,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _Forms(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── My Tickets ────────────────────────────────────────────────────────────────

class _MyTicketsTab extends StatefulWidget {
  const _MyTicketsTab();

  @override
  State<_MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<_MyTicketsTab> {
  String? _filterStatus;
  static const _pageSize = 10;
  static const _statuses = ['open', 'in progress', 'resolved'];

  // ── Pagination state ───────────────────────────────────────────────────────
  final List<QueryDocumentSnapshot> _docs = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  DocumentSnapshot? _lastUser;
  DocumentSnapshot? _lastBroadcast;
  DocumentSnapshot? _lastTargeted;

  bool _userDone = false;
  bool _broadcastDone = false;
  bool _targetedDone = false;

  late final ScrollController _scrollController;
  String? _uid;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _scrollController = ScrollController()..addListener(_onScroll);
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchPage();
    }
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────
  Future<void> _fetchPage({bool reset = false}) async {
    if (_uid == null) return;
    if (!reset && (_isLoadingMore || !_hasMore)) return;

    if (reset) {
      setState(() {
        _isLoading = true;
        _docs.clear();
        _lastUser = null;
        _lastBroadcast = null;
        _lastTargeted = null;
        _userDone = false;
        _broadcastDone = false;
        _targetedDone = false;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final results = await Future.wait([
        _fetchSubQuery(
          FirebaseFirestore.instance
              .collection('support_tickets')
              .where('userId', isEqualTo: _uid)
              .orderBy('createdAt', descending: true),
          _lastUser,
          _userDone,
        ),
        _fetchSubQuery(
          FirebaseFirestore.instance
              .collection('support_tickets')
              .where('recipientType', isEqualTo: 'all')
              .orderBy('createdAt', descending: true),
          _lastBroadcast,
          _broadcastDone,
        ),
        _fetchSubQuery(
          FirebaseFirestore.instance
              .collection('support_tickets')
              .where('recipientType', isEqualTo: 'specific')
              .where('recipients', arrayContains: _uid)
              .orderBy('createdAt', descending: true),
          _lastTargeted,
          _targetedDone,
        ),
      ]);

      final userDocs = results[0];
      final broadcastDocs = results[1];
      final targetedDocs = results[2];

      if (userDocs.isNotEmpty) _lastUser = userDocs.last;
      if (broadcastDocs.isNotEmpty) _lastBroadcast = broadcastDocs.last;
      if (targetedDocs.isNotEmpty) _lastTargeted = targetedDocs.last;

      _userDone = userDocs.length < _pageSize;
      _broadcastDone = broadcastDocs.length < _pageSize;
      _targetedDone = targetedDocs.length < _pageSize;

      final newDocs = [...userDocs, ...broadcastDocs, ...targetedDocs];
      newDocs.sort((a, b) {
        final aTime = (a.data() as Map)['createdAt'] as Timestamp?;
        final bTime = (b.data() as Map)['createdAt'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _docs.addAll(newDocs);
        _hasMore = !_userDone || !_broadcastDone || !_targetedDone;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Ticket fetch error: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<List<QueryDocumentSnapshot>> _fetchSubQuery(
    Query query,
    DocumentSnapshot? lastDoc,
    bool isDone,
  ) async {
    if (isDone) return [];
    Query q = query.limit(_pageSize);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    final snap = await q.get();
    return snap.docs;
  }

  // ── Filtered docs ──────────────────────────────────────────────────────────
  List<QueryDocumentSnapshot> get _filteredDocs {
    if (_filterStatus == null) return _docs;
    return _docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['status'] == _filterStatus;
    }).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Color _badgeColor(String status) => switch (status) {
        'resolved' => Colors.green,
        'in progress' => Colors.orange,
        _ => kBlue,
      };

  static IconData _badgeIcon(String status) => switch (status) {
        'resolved' => Icons.check_circle_outline,
        'in progress' => Icons.timelapse,
        _ => Icons.radio_button_unchecked,
      };

  String _formatDate(DateTime dt) =>
      '${dt.month}/${dt.day}/${dt.year} · ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  void _onTicketTap(BuildContext context, String ticketId, Map<String, dynamic> data) {
    _showTicketDetails(context, ticketId, data);
  }

  // ── Lazily create chat room for admin broadcast tickets ────────────────────
  Future<String?> _resolveRoomId(
    BuildContext context,
    String ticketId,
    Map<String, dynamic> data,
  ) async {
    final source = data['source'] as String? ?? 'user';

    if (source == 'user') {
      return data['roomId'] as String?;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final readByRef = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(ticketId)
        .collection('readBy')
        .doc(uid);

    final readBySnap = await readByRef.get();

    if (readBySnap.exists && readBySnap.data()?['roomId'] != null) {
      return readBySnap.data()!['roomId'] as String;
    }

    try {
      final currentUser = context.read<CurrentUserProvider>();
      final roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc();

      await roomRef.set({
        'userId': uid,
        'name': currentUser.currentName ?? '',
        'subject': data['subject'] ?? '',
        'sendTo': 'Giggre Support',
        'status': 'open',
        'isSupport': true,
        'ticketId': ticketId,
        'lastMessage': '',
        'lastMessageSender': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final autoReplySnap = await FirebaseFirestore.instance
          .collection('support_settings')
          .doc('qGDefSx1JYdx86VxlznN')
          .get();

      debugPrint('Auto reply enabled: ${autoReplySnap.data()?['enabled_auto_reply']}');

      final isAutoReplyEnabled = autoReplySnap.data()?['enabled_auto_reply'] ?? false;
      final autoReply = autoReplySnap.data()?['auto_reply_message'] ??
          "Thank you for contacting us! We'll get back to you shortly.";

      if (isAutoReplyEnabled) {
        await roomRef.collection('messages').add({
          'senderId': 'support',
          'isSupport': true,
          'name': 'Giggre Support',
          'text': autoReply,
          'hasSeen': false,
          'createdAt': FieldValue.serverTimestamp(),
          'isAutoReply': true,
        });

        await roomRef.update({
          'lastMessage': autoReply,
          'lastMessageSender': 'Support',
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      }

      await readByRef.set({
        'readAt': FieldValue.serverTimestamp(),
        'roomId': roomRef.id,
      });

      return roomRef.id;
    } catch (e) {
      debugPrint('Failed to create chat room for broadcast ticket: $e');
      return null;
    }
  }

  // ── Ticket details bottom sheet ────────────────────────────────────────────
  void _showTicketDetails(
    BuildContext context,
    String ticketId,
    Map<String, dynamic> data,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['status'] as String? ?? 'open';
    final color = _badgeColor(status);
    final isAdminTicket = data['source'] == 'admin';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(_badgeIcon(status), color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data['subject'] ?? '',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (isAdminTicket) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'FROM GIGGRE',
                        style: TextStyle(
                            color: kBlue, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                          color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              if (data['ticket_number'] != null)
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Ticket No.',
                  value: data['ticket_number'] as String,
                ),
              if (!isAdminTicket) ...[
                _DetailRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: data['name'] ?? '',
                ),
                _DetailRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: data['email'] ?? '',
                ),
              ],
              if (data['createdAt'] != null)
                _DetailRow(
                  icon: Icons.access_time,
                  label: 'Submitted',
                  value: _formatDate((data['createdAt'] as Timestamp).toDate()),
                ),
              const SizedBox(height: 12),
              const Text(
                'Message',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Html(data: data['message'] ?? ''),
              const SizedBox(height: 24),
              _ViewMessageButton(
                ticketId: ticketId,
                data: data,
                resolveRoomId: _resolveRoomId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Center(child: Text('You must be logged in to view tickets.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredDocs;

    return SafeArea(
      child: Column(
        children: [
          // ── Filter chips ────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filterStatus == null,
                  color: kBlue,
                  onTap: () => setState(() => _filterStatus = null),
                ),
                const SizedBox(width: 8),
                ..._statuses.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: s.replaceAll('_', ' ').toUpperCase(),
                        selected: _filterStatus == s,
                        color: _badgeColor(s),
                        onTap: () => setState(() => _filterStatus = s),
                      ),
                    )),
              ],
            ),
          ),

          // ── List ────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const SkeletonList(circle: false)
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _filterStatus == null
                                  ? 'No tickets yet'
                                  : 'No ${_filterStatus!.replaceAll('_', ' ')} tickets',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: kBlue,
                        onRefresh: () => _fetchPage(reset: true),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: filtered.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            // ── Load more spinner ──────────────────────
                            if (i == filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: SkeletonList(count: 1, circle: false, padding: EdgeInsets.zero),
                              );
                            }

                            // ── Ticket card ────────────────────────────
                            final docSnap = filtered[i];
                            final data = docSnap.data() as Map<String, dynamic>;
                            final status = data['status'] as String? ?? 'open';
                            final color = _badgeColor(status);
                            final isAdminTicket = data['source'] == 'admin';

                            return GestureDetector(
                              onTap: () => _onTicketTap(context, docSnap.id, data),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withValues(alpha: 0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(_badgeIcon(status), color: color, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            data['subject'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isAdminTicket) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: kBlue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              'FROM GIGGRE',
                                              style: TextStyle(
                                                color: kBlue,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            status.replaceAll('_', ' ').toUpperCase(),
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Html(
                                      data: data['message'] ?? '',
                                      style: {
                                        'body': Style(
                                          maxLines: 1,
                                          textOverflow: TextOverflow.ellipsis,
                                          color: Colors.grey.shade500,
                                        ),
                                        'p': Style(
                                          margin: Margins.zero,
                                          maxLines: 1,
                                          textOverflow: TextOverflow.ellipsis,
                                          color: Colors.grey.shade500,
                                        ),
                                        'br': Style(margin: Margins.zero),
                                      },
                                      shrinkWrap: true,
                                    ),
                                    if (data['createdAt'] != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time,
                                              size: 11, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(
                                                (data['createdAt'] as Timestamp).toDate()),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade400),
                                          ),
                                          const Spacer(),
                                          Text(
                                            'Tap for details',
                                            style: TextStyle(fontSize: 11, color: kBlue),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── View Message Button ───────────────────────────────────────────────────────

class _ViewMessageButton extends StatefulWidget {
  const _ViewMessageButton({
    required this.ticketId,
    required this.data,
    required this.resolveRoomId,
  });

  final String ticketId;
  final Map<String, dynamic> data;
  final Future<String?> Function(
      BuildContext, String, Map<String, dynamic>) resolveRoomId;

  @override
  State<_ViewMessageButton> createState() => _ViewMessageButtonState();
}

class _ViewMessageButtonState extends State<_ViewMessageButton> {
  bool _loading = false;

  Future<void> _handleTap() async {
    setState(() => _loading = true);
    try {
      final roomId =
          await widget.resolveRoomId(context, widget.ticketId, widget.data);
      if (!mounted) return;
      if (roomId != null) {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/chat/$roomId');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _handleTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _loading ? Colors.grey : kBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'View Message',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Help Banner ───────────────────────────────────────────────────────────────

class _HelpContainer extends StatelessWidget {
  const _HelpContainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Icon(Icons.support_agent, color: Colors.white, size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We\'re here to help',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Send us a message and we\'ll respond within 24–48 hours.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Copy Container ────────────────────────────────────────────────────────────

class _CopyContainer extends StatelessWidget {
  const _CopyContainer({
    required this.title,
    required this.value,
    required this.icon,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        _showModal(
          context,
          title: 'Copied!',
          message: '$title has been copied to your clipboard.',
          isSuccess: true,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kBlue),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: textColor, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text('Tap to copy', style: TextStyle(color: kBlue, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Forms ─────────────────────────────────────────────────────────────────────

// A file attached to a Contact us message, uploaded after the ticket's chat
// room exists. Same types, size caps and message shape as chat.dart's
// attachments, so the ticket thread (Chat screen) shows them normally.
class _PickedAttachment {
  _PickedAttachment(this.file, this.name, this.type, this.size);
  final File file;
  final String name;
  final String type; // 'image' | 'video' | 'file'
  final int size;
}

const _kMaxContactFiles = 5;
const _kContactSizeCap = {
  'image': 10 * 1024 * 1024,
  'video': 50 * 1024 * 1024,
  'file': 20 * 1024 * 1024,
};
const _kContactVideoExt = {'.mp4', '.mov', '.avi', '.mkv', '.3gp', '.webm'};
const _kContactFileExt = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'zip'];

String _contactSizeLabel(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class _Forms extends StatefulWidget {
  const _Forms();

  @override
  State<_Forms> createState() => _FormsState();
}

class _FormsState extends State<_Forms> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isLoading = false;
  bool _prefilled = false;
  final List<_PickedAttachment> _attachments = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefilled) {
      final currentUser = context.read<CurrentUserProvider>();
      _nameController.text = currentUser.currentName ?? '';
      _emailController.text = currentUser.currentEmail ?? '';
      _prefilled = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Adds picked files, enforcing the per-type size caps and the file limit.
  Future<void> _addPicked(List<({File file, String name, String type})> picked) async {
    for (final p in picked) {
      if (_attachments.length >= _kMaxContactFiles) {
        _snack('You can attach up to $_kMaxContactFiles files.');
        break;
      }
      final size = await p.file.length();
      final cap = _kContactSizeCap[p.type]!;
      if (size > cap) {
        _snack('${p.name} is too large — the limit is ${cap ~/ (1024 * 1024)}MB.');
        continue;
      }
      if (!mounted) return;
      setState(() => _attachments.add(_PickedAttachment(p.file, p.name, p.type, size)));
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kBlue),
              title: const Text('Photo or Video'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: kBlue),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined, color: kBlue),
              title: const Text('File'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      switch (choice) {
        case 'gallery':
          final media = await ImagePicker().pickMultipleMedia(
            limit: _kMaxContactFiles - _attachments.length,
          );
          await _addPicked([
            for (final m in media)
              (
                file: File(m.path),
                name: m.name,
                type: _kContactVideoExt.any((e) => m.path.toLowerCase().endsWith(e))
                    ? 'video'
                    : 'image',
              ),
          ]);
        case 'camera':
          final photo = await ImagePicker().pickImage(source: ImageSource.camera);
          if (photo != null) {
            await _addPicked([(file: File(photo.path), name: photo.name, type: 'image')]);
          }
        case 'file':
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: _kContactFileExt,
            allowMultiple: true,
          );
          await _addPicked([
            for (final f in result?.files ?? const <PlatformFile>[])
              if (f.path != null) (file: File(f.path!), name: f.name, type: 'file'),
          ]);
      }
    } catch (e) {
      debugPrint('Contact us attachment pick error: $e');
      _snack("Couldn't open the picker. Please try again.");
    }
  }

  /// Uploads one attachment into the ticket's chat room (storage.rules lets
  /// the room's userId upload to chat_attachments/{roomId}/).
  Future<void> _uploadAttachment(
    DocumentReference<Map<String, dynamic>> roomRef,
    String uid,
    String name,
    _PickedAttachment a,
  ) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child('chat_attachments/${roomRef.id}/${ts}_${a.name}');
    await ref.putFile(a.file);
    final url = await ref.getDownloadURL();
    final text = a.type == 'image'
        ? '📷 Photo'
        : a.type == 'video'
        ? '🎥 Video'
        : '📎 ${a.name}';
    await roomRef.collection('messages').add({
      'senderId': uid,
      'isSupport': false,
      'name': name,
      'text': text,
      'attachmentUrl': url,
      'attachmentType': a.type,
      'attachmentName': a.name,
      'hasSeen': true,
      'hasSeenByAdmin': false,
      'isAutoReply': false,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await roomRef.update({
      'lastMessage': text,
      'lastMessageSender': 'You',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _submitTicket() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (name.isEmpty || email.isEmpty || subject.isEmpty || message.isEmpty) {
      _showModal(
        context,
        title: 'Incomplete Fields',
        message: 'Please fill in all required fields before submitting.',
        isSuccess: false,
      );
      return;
    }

    if (ContentFilterService.instance.check(subject) ||
        ContentFilterService.instance.check(message)) {
      _showModal(
        context,
        title: 'Submission Failed',
        message: ContentFilterService.rejectionMessage,
        isSuccess: false,
      );
      return;
    }

    setState(() => _isLoading = true);
    final failedFiles = <String>[];

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final isGuest = uid == null;

      final ticketNumber = isGuest
          ? await _generateGuestTicketNumber()
          : await _generateTicketNumber();

      if (isGuest) {
        // Guest path: create ticket only (no chat room, no auto-reply)
        await FirebaseFirestore.instance.collection('support_tickets').add({
          'source': 'maintenance',
          'ticket_number': ticketNumber,
          'userId': email,
          'name': name,
          'email': email,
          'subject': subject,
          'message': message,
          'roomId': null,
          'status': 'open',
          'hasRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'recipientType': null,
          'recipients': [],
          'createdBy': null,
        });
      } else {
        // Authenticated path: full flow with chat room + auto-reply
        final roomRef =
            FirebaseFirestore.instance.collection('chat_rooms').doc();

        await FirebaseFirestore.instance.collection('support_tickets').add({
          'source': 'user',
          'ticket_number': ticketNumber,
          'userId': uid,
          'name': name,
          'email': email,
          'subject': subject,
          'message': message,
          'roomId': roomRef.id,
          'status': 'open',
          'hasRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'recipientType': null,
          'recipients': [],
          'createdBy': null,
        });

        await roomRef.set({
          'userId': uid,
          'name': name,
          'subject': subject,
          'sendTo': 'Giggre Support',
          'status': 'open',
          'isSupport': true,
          'ticketId': null,
          'lastMessage': message,
          'lastMessageSender': 'You',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        final autoReplySnap = await FirebaseFirestore.instance
            .collection('support_settings')
            .doc('qGDefSx1JYdx86VxlznN')
            .get();

        final isAutoReplyEnabled =
            autoReplySnap.data()?['enabled_auto_reply'] ?? false;
        final autoReply = autoReplySnap.data()?['auto_reply_message'] ??
            "Thank you for contacting us! We'll get back to you shortly.";

        await roomRef.collection('messages').add({
          'senderId': uid,
          'isSupport': false,
          'name': name,
          'text': message,
          'hasSeen': true,
          'hasSeenByAdmin': isAutoReplyEnabled ? true : false,
          'createdAt': FieldValue.serverTimestamp(),
          'isAutoReply': false,
        });

        // Attachments go in after the text and before the auto-reply, so
        // the thread reads: message, files, "Thank you for contacting us".
        for (final a in List.of(_attachments)) {
          try {
            await _uploadAttachment(roomRef, uid, name, a);
          } catch (e) {
            debugPrint('Contact us attachment upload error: $e');
            failedFiles.add(a.name);
          }
        }

        await Future.delayed(const Duration(seconds: 2));

        if (isAutoReplyEnabled) {
          await roomRef.collection('messages').add({
            'senderId': 'support',
            'isSupport': true,
            'name': 'Giggre Support',
            'text': autoReply,
            'hasSeen': false,
            'hasSeenByAdmin': true,
            'createdAt': FieldValue.serverTimestamp(),
            'isAutoReply': true,
          });

          await roomRef.update({
            'lastMessage': autoReply,
            'lastMessageSender': 'Support',
            'lastMessageAt': FieldValue.serverTimestamp(),
          });
        }
      }

      _subjectController.clear();
      _messageController.clear();
      if (mounted) setState(() => _attachments.clear());

      if (mounted) {
        _showModal(
          context,
          title: 'Ticket Submitted!',
          message: failedFiles.isEmpty
              ? "We've received your message and will respond within 24–48 hours."
              : "We've received your message and will respond within 24–48 hours.\n\n"
                    "Couldn't upload: ${failedFiles.join(', ')}. You can send it in the ticket's chat.",
          isSuccess: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showModal(
          context,
          title: 'Submission Failed',
          message: 'Something went wrong. Please try again.\n\n$e',
          isSuccess: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _generateGuestTicketNumber() async {
    final counterRef = FirebaseFirestore.instance
        .collection('_counters')
        .doc('guest_support_tickets');
    final year = DateTime.now().year;

    final count = await FirebaseFirestore.instance.runTransaction<int>((t) async {
      final snap = await t.get(counterRef);
      final current = (snap.data()?['count_$year'] as int?) ?? 0;
      final next = current + 1;
      t.set(counterRef, {'count_$year': next}, SetOptions(merge: true));
      return next;
    });

    return 'TKT-$year-G${count.toString().padLeft(6, '0')}';
  }

  Future<String> _generateTicketNumber() async {
    final counterRef = FirebaseFirestore.instance
        .collection('_counters')
        .doc('support_tickets');
    final year = DateTime.now().year;

    final count = await FirebaseFirestore.instance.runTransaction<int>((t) async {
      final snap = await t.get(counterRef);
      final current = (snap.data()?['count_$year'] as int?) ?? 0;
      final next = current + 1;
      t.set(counterRef, {'count_$year': next}, SetOptions(merge: true));
      return next;
    });

    return 'TKT-$year-${count.toString().padLeft(6, '0')}';
  }

  InputDecoration _inputDecoration({
    required bool isDark,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: kBlue),
      filled: true,
      fillColor: isDark ? Colors.black : const Color(0xFFF8F8F8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBlue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Send Message',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: _inputDecoration(
              isDark: isDark,
              label: 'Name',
              hint: 'Enter your name',
              icon: Icons.person_outline,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration(
              isDark: isDark,
              label: 'Email',
              hint: 'Enter your email',
              icon: Icons.email_outlined,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subjectController,
            decoration: _inputDecoration(
              isDark: isDark,
              label: 'Subject',
              hint: 'Enter your subject',
              icon: Icons.subject,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            minLines: 3,
            maxLines: 5,
            decoration: _inputDecoration(
              isDark: isDark,
              label: 'Message',
              hint: 'Enter your message',
              icon: Icons.message,
            ),
          ),
          // Attachments need the ticket's chat room, which only signed-in
          // users get (the maintenance-mode guest path creates no room).
          // dart:io File uploads aren't available on the web build.
          if (!kIsWeb && FirebaseAuth.instance.currentUser != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading || _attachments.length >= _kMaxContactFiles
                  ? null
                  : _pickAttachment,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('Attach files'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kBlue,
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional · up to $_kMaxContactFiles files (photos 10MB, videos 50MB, documents 20MB)',
              style: TextStyle(fontSize: 11, color: kSub),
            ),
            for (var i = 0; i < _attachments.length; i++)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _attachments[i].type == 'image'
                          ? Icons.image_outlined
                          : _attachments[i].type == 'video'
                          ? Icons.videocam_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 18,
                      color: kSub,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _attachments[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _contactSizeLabel(_attachments[i].size),
                      style: const TextStyle(fontSize: 11, color: kSub),
                    ),
                    IconButton(
                      tooltip: 'Remove ${_attachments[i].name}',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _attachments.removeAt(i)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _isLoading ? null : _submitTicket,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isLoading ? Colors.grey : kBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Send',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}