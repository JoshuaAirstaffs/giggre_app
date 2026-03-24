import 'package:flutter/material.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
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
              color: (isSuccess ? Colors.green : Colors.red)
                  .withValues(alpha: 0.1),
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
  const ContactUs({super.key});

  @override
  State<ContactUs> createState() => _ContactUsState();
}

class _ContactUsState extends State<ContactUs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kBlue,
          labelColor: kBlue,
          unselectedLabelColor: onSurface.withValues(alpha: 0.5),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Send Message'),
            Tab(text: 'My Tickets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_SendMessageTab(), _MyTicketsTab()],
      ),
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
                      value: 'www.giggre.com',
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

  static const _statuses = ['open', 'in_progress', 'resolved'];

  static Color _badgeColor(String status) => switch (status) {
        'resolved' => Colors.green,
        'in_progress' => Colors.orange,
        _ => kBlue,
      };

  static IconData _badgeIcon(String status) => switch (status) {
        'resolved' => Icons.check_circle_outline,
        'in_progress' => Icons.timelapse,
        _ => Icons.radio_button_unchecked,
      };

  String _formatDate(DateTime dt) =>
      '${dt.month}/${dt.day}/${dt.year} · ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  void _showTicketDetails(BuildContext context, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['status'] as String? ?? 'open';
    final color = _badgeColor(status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _DetailRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: data['name'] ?? ''),
              _DetailRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: data['email'] ?? ''),
              if ((data['roomId'] as String?)?.isNotEmpty == true)
                _DetailRow(
                    icon: Icons.meeting_room_outlined,
                    label: 'Room ID',
                    value: data['roomId']),
              if (data['createdAt'] != null)
                _DetailRow(
                  icon: Icons.access_time,
                  label: 'Submitted',
                  value: _formatDate(
                      (data['createdAt'] as Timestamp).toDate()),
                ),
              const SizedBox(height: 12),
              const Text('Message',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 6),
              Text(data['message'] ?? '',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (uid == null) {
      return const Center(
          child: Text('You must be logged in to view tickets.'));
    }

    var query = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    if (_filterStatus != null) {
      query = query.where('status', isEqualTo: _filterStatus);
    }

    return SafeArea(
      child: Column(
        children: [
          // ── Filter chips ────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

          // ── Ticket list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
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
                  );
                }

                return RefreshIndicator(
                  color: kBlue,
                  onRefresh: () async =>
                      Future.delayed(const Duration(milliseconds: 500)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final status = data['status'] as String? ?? 'open';
                      final color = _badgeColor(status);

                      return GestureDetector(
                        onTap: () => _showTicketDetails(context, data),
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
                                  Icon(_badgeIcon(status),
                                      color: color, size: 16),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status
                                          .replaceAll('_', ' ')
                                          .toUpperCase(),
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
                              Text(
                                data['message'] ?? '',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (data['createdAt'] != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.access_time,
                                        size: 11,
                                        color: Colors.grey.shade400),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate((data['createdAt']
                                              as Timestamp)
                                          .toDate()),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade400),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Tap for details',
                                      style:
                                          TextStyle(fontSize: 11, color: kBlue),
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
                );
              },
            ),
          ),
        ],
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
                  'Send us a message and we\'ll respond within 24 - 48 hours.',
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

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final roomId =
          FirebaseFirestore.instance.collection('chat_rooms').doc().id;

      // 1. create the ticket
      await FirebaseFirestore.instance.collection('support_tickets').add({
        'userId': uid,
        'name': name,
        'email': email,
        'subject': subject,
        'message': message,
        'roomId': roomId,
        'status': 'open',
        'hasRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. create the chat_rooms document with user's first message
      final roomRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId);

      await roomRef.set({
        'userId': uid,
        'name': name,
        'subject': subject,
        'sendTo': 'Giggre Support',
        'status': 'open',
        'lastMessage': message,
        'lastMessageSender': 'You',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. save user's first message to subcollection
      await roomRef.collection('messages').add({
        'senderId': uid,
        'isSupport': false,
        'name': name,
        'text': message,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. auto-reply from support after slight delay
      await Future.delayed(const Duration(seconds: 2));

      const autoReply =
          'Thank you for contacting us! We\'ll get back to you shortly.';

      await roomRef.collection('messages').add({
        'senderId': 'support',
        'isSupport': true,
        'name': 'Giggre Support',
        'text': autoReply,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 5. update chat_rooms with latest message (auto-reply)
      await roomRef.update({
        'lastMessage': autoReply,
        'lastMessageSender': 'Support',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      _nameController.clear();
      _emailController.clear();
      _subjectController.clear();
      _messageController.clear();

      if (mounted) {
        _showModal(
          context,
          title: 'Ticket Submitted!',
          message:
              'We\'ve received your message and will respond within 24–48 hours.',
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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