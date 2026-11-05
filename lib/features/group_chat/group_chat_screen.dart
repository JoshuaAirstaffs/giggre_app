import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';
import 'package:giggre_app/features/group_chat/group_info_screen.dart';
import 'package:giggre_app/features/group_chat/group_widgets.dart';
import 'package:giggre_app/features/live_support/live_support_bubble.dart'
    show HidesLiveSupport; // TEMP: live support
import 'package:giggre_app/features/reports/models/report_content_type.dart';
import 'package:giggre_app/features/reports/report_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with HidesLiveSupport {
  final _text = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final _groupStream = GroupChatService.group(widget.groupId);
  late final _messageStream = GroupChatService.messages(widget.groupId);
  StreamSubscription? _readSub;
  Timer? _readTimer;
  Map<String, GroupPerson> _people = {};
  List<String> _peopleFor = const [];
  bool _sending = false;
  // Shown dimmed at the bottom until the server copy arrives.
  final List<_Pending> _pending = [];

  @override
  void initState() {
    super.initState();
    // Anything that arrives while the chat is open counts as read.
    _readSub = _messageStream.listen((_) => _scheduleRead());
  }

  @override
  void dispose() {
    _readSub?.cancel();
    _readTimer?.cancel();
    GroupChatService.markRead(widget.groupId);
    _text.dispose();
    super.dispose();
  }

  void _scheduleRead() {
    _readTimer?.cancel();
    _readTimer = Timer(
      const Duration(milliseconds: 600),
      () => GroupChatService.markRead(widget.groupId),
    );
  }

  void _loadPeople(List<String> uids) {
    if (_sameList(uids, _peopleFor)) return;
    _peopleFor = uids;
    GroupChatService.people(uids).then((p) {
      if (mounted) setState(() => _people = p);
    });
  }

  String get _myName => context.read<CurrentUserProvider>().currentName ?? '';

  Future<void> _run(String label, Future<void> Function() send) async {
    final pending = _Pending(label);
    setState(() => _pending.add(pending));
    try {
      await send();
    } catch (e) {
      if (mounted) showGroupError(context, e);
    } finally {
      if (mounted) setState(() => _pending.remove(pending));
    }
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    _sending = true;
    _text.clear();
    // Firestore shows the new message straight away, so no pending copy.
    try {
      await GroupChatService.sendText(widget.groupId, text, _myName);
    } catch (e) {
      if (mounted) {
        if (_text.text.isEmpty) _text.text = text;
        showGroupError(context, e);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null || !mounted) return;
    await _run(
      '📷 Photo',
      () => GroupChatService.sendImage(
        widget.groupId,
        File(picked.path),
        _myName,
      ),
    );
  }

  Future<void> _sendLocation() async {
    void snack(String m) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) snack('Turn on location services to share your location.');
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        snack('Location permission is required to share your location.');
      }
      return;
    }
    if (!mounted) return;
    await _run('📍 Location', () async {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final address = await _addressOf(pos);
      await GroupChatService.sendLocation(
        widget.groupId,
        GeoPoint(pos.latitude, pos.longitude),
        address,
        _myName,
      );
    });
  }

  // Same address format as Chat._shareLocation; falls back to coordinates.
  Future<String> _addressOf(Position pos) async {
    try {
      final marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      ).timeout(const Duration(seconds: 10));
      if (marks.isNotEmpty) {
        final p = marks.first;
        final hasName =
            p.name != null && p.name!.isNotEmpty && p.name != p.street;
        final parts = [
          if (hasName) p.name,
          if (p.street?.isNotEmpty == true) p.street,
          if (p.subLocality?.isNotEmpty == true) p.subLocality,
          if (p.locality?.isNotEmpty == true) p.locality,
          if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea,
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (e) {
      debugPrint('[GroupChat] geocode: $e');
    }
    return '${pos.latitude.toStringAsFixed(5)}, '
        '${pos.longitude.toStringAsFixed(5)}';
  }

  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kBlue),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _sendPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: kBlue),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _sendPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined, color: kBlue),
              title: const Text('Share my location'),
              onTap: () {
                Navigator.pop(ctx);
                _sendLocation();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onMessageLongPress(String id, Map<String, dynamic> m) {
    final senderId = m['senderId'] as String? ?? '';
    final text = m['text'] as String? ?? '';
    final canReport = senderId.isNotEmpty && senderId != _uid;
    final canCopy = m['type'] == 'text' && text.isNotEmpty;
    if (!canReport && !canCopy) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                },
              ),
            if (canReport)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Report message',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ReportService.show(
                    context,
                    contentType: ReportContentType.message,
                    contentId: id,
                    contentSnapshot: text,
                    contentAuthorId: senderId,
                    surface: 'group_chat',
                    roomId: 'group_chats/${widget.groupId}',
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openInfo() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => GroupInfoScreen(groupId: widget.groupId)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _groupStream,
      builder: (context, groupSnap) {
        final group = groupSnap.data?.data();
        final members = List<String>.from(
          (group?['participants'] as List?) ?? const [],
        );
        final isMember = members.contains(_uid);
        // A removed member's read is denied, which surfaces as an error.
        final gone =
            groupSnap.hasError ||
            (groupSnap.hasData && (group == null || !isMember));
        if (isMember) _loadPeople(members);

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: isMember ? _openInfo : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    GroupAvatar(
                      photoUrl: group?['photoUrl'] as String?,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group?['name'] as String? ?? 'Group',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isMember)
                            Text(
                              '${members.length} members',
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isMember)
                IconButton(
                  tooltip: 'Group info',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: _openInfo,
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: gone
                    ? const _NotInGroup()
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _messageStream,
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _messageList(snap.data!.docs, isDark);
                        },
                      ),
              ),
              if (!gone) _composer(isDark, onSurface),
            ],
          ),
        );
      },
    );
  }

  Widget _messageList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool isDark,
  ) {
    // docs are newest first, and the list is reversed (index 0 = bottom).
    final pending = _pending.reversed.toList();
    final count = pending.length + docs.length;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: count,
      itemBuilder: (context, i) {
        if (i < pending.length) {
          return _Bubble(
            isMe: true,
            text: pending[i].label,
            isDark: isDark,
            pending: true,
            isLastInRun: i == 0,
          );
        }
        final j = i - pending.length;
        final doc = docs[j];
        final m = doc.data();
        final type = m['type'] as String? ?? 'text';
        final at = (m['createdAt'] as Timestamp?)?.toDate();
        final older = j + 1 < docs.length ? docs[j + 1].data() : null;
        final newer = j > 0 ? docs[j - 1].data() : null;
        final olderAt = (older?['createdAt'] as Timestamp?)?.toDate();
        final newDay =
            at != null && (olderAt == null || !_sameDay(at, olderAt));

        Widget item;
        if (type == 'system') {
          item = _SystemLine(text: m['text'] as String? ?? '');
        } else {
          final senderId = m['senderId'] as String? ?? '';
          final isMe = senderId == _uid;
          bool sameSender(Map<String, dynamic>? o) =>
              o != null && o['type'] != 'system' && o['senderId'] == senderId;
          final newerAt = (newer?['createdAt'] as Timestamp?)?.toDate();
          // A run of messages from one person shows their name on the first
          // and their avatar and the time on the last.
          final firstInRun = newDay || !sameSender(older);
          final lastInRun =
              !sameSender(newer) ||
              (newerAt != null && at != null && !_sameDay(newerAt, at));
          final person = _people[senderId];
          item = GestureDetector(
            onLongPress: () => _onMessageLongPress(doc.id, m),
            child: _Bubble(
              isMe: isMe,
              text: m['text'] as String? ?? '',
              type: type,
              imageUrl: m['imageUrl'] as String?,
              location: m['location'] as GeoPoint?,
              address: m['locationAddress'] as String?,
              time: at,
              isDark: isDark,
              senderName: isMe || !firstInRun
                  ? null
                  : (person?.name ?? m['senderName'] as String? ?? ''),
              sender: person,
              pending: doc.metadata.hasPendingWrites,
              isLastInRun: lastInRun,
            ),
          );
        }
        if (!newDay) return item;
        return Column(
          children: [
            _DayDivider(day: at),
            item,
          ],
        );
      },
    );
  }

  Widget _composer(bool isDark, Color onSurface) {
    final fill = isDark ? Colors.grey.shade900 : Colors.grey.shade100;
    return Container(
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
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RoundButton(
              icon: Icons.add_rounded,
              color: fill,
              iconColor: onSurface.withValues(alpha: 0.7),
              tooltip: 'Photo or location',
              onTap: _showAttachMenu,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 14, color: onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Message the group',
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundButton(
              icon: Icons.send_rounded,
              color: kBlue,
              iconColor: Colors.white,
              tooltip: 'Send',
              onTap: _sendText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pending {
  _Pending(this.label);
  final String label;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.isMe,
    required this.text,
    required this.isDark,
    this.type = 'text',
    this.imageUrl,
    this.location,
    this.address,
    this.time,
    this.senderName,
    this.sender,
    this.pending = false,
    this.isLastInRun = true,
  });

  final bool isMe;
  final String text;
  final bool isDark;
  final String type;
  final String? imageUrl;
  final GeoPoint? location;
  final String? address;
  final DateTime? time;
  final String? senderName;
  final GroupPerson? sender;
  final bool pending;
  final bool isLastInRun;

  @override
  Widget build(BuildContext context) {
    final media = type == 'image' && imageUrl != null;
    final mapCard = type == 'location' && location != null;
    final bg = isMe
        ? kBlue
        : isDark
        ? Colors.grey.shade800
        : Colors.grey.shade200;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(!isMe && isLastInRun ? 4 : 16),
      bottomRight: Radius.circular(isMe && isLastInRun ? 4 : 16),
    );

    Widget body;
    if (media) {
      body = _ImageMessage(url: imageUrl!, radius: radius);
    } else if (mapCard) {
      body = _LocationMessage(
        location: location!,
        address: address,
        isMe: isMe,
        bg: bg,
        radius: radius,
      );
    } else {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Text(
          text,
          style: TextStyle(fontSize: 14, color: isMe ? Colors.white : null),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLastInRun ? 10 : 2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Visibility(
              visible: isLastInRun,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: PersonAvatar(person: sender, radius: 12),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.75,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (senderName != null && senderName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        senderName!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  Opacity(opacity: pending ? 0.6 : 1, child: body),
                  if (isLastInRun) ...[
                    const SizedBox(height: 3),
                    pending
                        ? Icon(
                            Icons.access_time,
                            size: 10,
                            color: Colors.grey.shade400,
                          )
                        : Text(
                            time == null ? '' : _time(time!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageMessage extends StatelessWidget {
  const _ImageMessage({required this.url, required this.radius});
  final String url;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _PhotoViewer(url: url),
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: url,
          width: 220,
          height: 260,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: 220,
            height: 260,
            color: Colors.grey.withValues(alpha: 0.2),
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          errorWidget: (_, _, _) => Container(
            width: 220,
            height: 120,
            color: Colors.grey.withValues(alpha: 0.2),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _LocationMessage extends StatelessWidget {
  const _LocationMessage({
    required this.location,
    required this.address,
    required this.isMe,
    required this.bg,
    required this.radius,
  });

  final GeoPoint location;
  final String? address;
  final bool isMe;
  final Color bg;
  final BorderRadius radius;

  Future<void> _open() => launchUrl(
    Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${location.latitude},${location.longitude}',
    ),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : null;
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.white : kBlue).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: isMe ? Colors.white : kBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address ?? 'Shared location',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open in Maps',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white70 : kBlue,
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
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
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
    final label = diff == 0
        ? 'Today'
        : diff == 1
        ? 'Yesterday'
        : '${months[d.month - 1]} ${d.day}${d.year == now.year ? '' : ', ${d.year}'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _NotInGroup extends StatelessWidget {
  const _NotInGroup();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              "You're no longer in this group",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'You left, were removed, or the group was deleted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
