import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';

const _avatarTint = Color(0xFF3B82F6);

/// A group's photo, or a people icon when it has none.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, this.photoUrl, this.radius = 20});

  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarTint.withValues(alpha: 0.15),
      backgroundImage: url != null && url.isNotEmpty
          ? CachedNetworkImageProvider(url)
          : null,
      child: url == null || url.isEmpty
          ? Icon(Icons.groups_rounded, color: _avatarTint, size: radius * 1.1)
          : null,
    );
  }
}

/// A person's photo, or the same person icon the one-to-one chats use.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, this.person, this.radius = 20});

  final GroupPerson? person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = person?.photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarTint.withValues(alpha: 0.15),
      backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
      child: url == null
          ? Icon(Icons.person_rounded, color: _avatarTint, size: radius * 1.1)
          : null,
    );
  }
}

/// Picks people from the user's accepted chats. Used to create a group and
/// to add members to one ([exclude] = people already in it).
class ContactPicker extends StatefulWidget {
  const ContactPicker({
    super.key,
    required this.contacts,
    required this.selected,
    required this.onChanged,
    this.exclude = const {},
    this.maxSelectable,
  });

  final List<GroupPerson> contacts;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Set<String> exclude;
  final int? maxSelectable;

  @override
  State<ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<ContactPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final q = _query.trim().toLowerCase();
    final shown = widget.contacts
        .where((p) => !widget.exclude.contains(p.uid))
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    final atMax =
        widget.maxSelectable != null &&
        widget.selected.length >= widget.maxSelectable!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your chats',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (widget.selected.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in widget.contacts.where(
                  (p) => widget.selected.contains(p.uid),
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InputChip(
                      avatar: PersonAvatar(person: p, radius: 12),
                      label: Text(p.name.split(' ').first),
                      onDeleted: () =>
                          widget.onChanged({...widget.selected}..remove(p.uid)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: widget.contacts.isEmpty
              ? const _PickerEmpty(
                  title: 'No chats yet',
                  body:
                      'You can add people you already have a chat with. '
                      'Message someone first, then make a group.',
                )
              : shown.isEmpty
              ? _PickerEmpty(
                  title: q.isEmpty ? 'Everyone is already here' : 'No matches',
                  body: q.isEmpty
                      ? 'All your chats are already in this group.'
                      : 'Only people you already chat with show up here.',
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final p = shown[i];
                    final on = widget.selected.contains(p.uid);
                    return CheckboxListTile(
                      value: on,
                      activeColor: kBlue,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: PersonAvatar(person: p),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: !on && atMax
                          ? null
                          : (v) => widget.onChanged(
                              v == true
                                  ? ({...widget.selected}..add(p.uid))
                                  : ({...widget.selected}..remove(p.uid)),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

void showGroupError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          e is GroupChatException
              ? e.message
              : 'Something went wrong. Try again.',
        ),
      ),
    );
}

/// A group in the Chats list, styled like the one-to-one rows there
/// (home_chat.dart's _ChatHomeItem).
class GroupListTile extends StatelessWidget {
  const GroupListTile({
    super.key,
    required this.groupId,
    required this.group,
    required this.myUid,
    required this.onTap,
  });

  final String groupId;
  final Map<String, dynamic> group;
  final String myUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? Colors.grey[400] : Colors.grey[600];
    final unread = GroupChatService.isUnread(group, myUid);
    final muted = GroupChatService.isMuted(group, myUid);
    final at = (group['lastMessageAt'] as Timestamp?)?.toDate();
    final senderId = group['lastMessageSenderId'] as String? ?? '';
    final senderName = group['lastMessageSenderName'] as String? ?? '';
    final last = group['lastMessage'] as String? ?? '';
    final preview = senderId.isEmpty
        ? last
        : '${senderId == myUid ? 'You' : senderName.split(' ').first}: $last';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? kCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GroupAvatar(photoUrl: group['photoUrl'] as String?),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group['name'] as String? ?? 'Group',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (muted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 14,
                          color: sub,
                        ),
                      ],
                      if (unread) ...[
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
                      if (at != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _listTime(at),
                          style: TextStyle(fontSize: 11, color: sub),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: sub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Same format as the one-to-one rows: "3:04 PM", "Yesterday 3:04 PM",
// "Tue 3:04 PM", then "Nov 5 3:04 PM".
String _listTime(DateTime dt) {
  final now = DateTime.now();
  final diff = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final time =
      '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  if (diff == 0) return time;
  if (diff == 1) return 'Yesterday $time';
  if (diff < 7) return '${days[dt.weekday - 1]} $time';
  return '${months[dt.month - 1]} ${dt.day} $time';
}
