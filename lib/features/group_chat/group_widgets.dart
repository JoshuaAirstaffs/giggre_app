import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/widgets/avatar_image.dart';
import 'package:giggre_app/features/chat/user_search_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';

const _avatarTint = Color(0xFF3B82F6);

// White initials on each of these measure 5.02–6.29:1. Blue is left out so a
// group never looks like the blue person placeholder.
const _groupColors = [
  Color(0xFF0F766E), // teal
  Color(0xFF7C3AED), // violet
  Color(0xFFBE123C), // rose
  Color(0xFFB45309), // amber
  Color(0xFF15803D), // green
  Color(0xFFC2410C), // orange
  Color(0xFF0E7490), // cyan
];

final _initialChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// "Weekend Crew" → "WC", "Sunday" → "S", "🔥" → "" (falls back to the icon).
String groupInitials(String name) {
  final letters = <String>[];
  for (final word in name.trim().split(RegExp(r'\s+'))) {
    final m = _initialChar.firstMatch(word);
    if (m != null) letters.add(m.group(0)!.toUpperCase());
    if (letters.length == 2) break;
  }
  return letters.join();
}

/// A group's photo; without one, its initials on a color fixed by its id
/// (so the same group is always the same color), or a people icon when
/// there's no id or usable name yet.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    this.photoUrl,
    this.radius = 20,
    this.groupId,
    this.name,
  });

  final String? photoUrl;
  final double radius;
  final String? groupId;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _avatarTint.withValues(alpha: 0.15),
        backgroundImage: avatarImage(context, url, radius),
      );
    }
    final id = groupId;
    final initials = groupInitials(name ?? '');
    if (id != null && id.isNotEmpty && initials.isNotEmpty) {
      final hash = id.codeUnits.fold<int>(
        0,
        (h, c) => (h * 31 + c) & 0x7fffffff,
      );
      return CircleAvatar(
        radius: radius,
        backgroundColor: _groupColors[hash % _groupColors.length],
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: radius * (initials.length > 1 ? 0.72 : 0.85),
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarTint.withValues(alpha: 0.15),
      child: Icon(Icons.groups_rounded, color: _avatarTint, size: radius * 1.1),
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
      backgroundImage: url != null ? avatarImage(context, url, radius) : null,
      child: url == null
          ? Icon(Icons.person_rounded, color: _avatarTint, size: radius * 1.1)
          : null,
    );
  }
}

/// A name followed by the verified check when the person is verified, the
/// same mark user search shows. The check is announced as "Verified".
class VerifiedName extends StatelessWidget {
  const VerifiedName({
    super.key,
    required this.name,
    required this.verified,
    this.style,
    this.checkSize = 16,
  });

  final String name;
  final bool verified;
  final TextStyle? style;
  final double checkSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified_rounded,
            size: checkSize,
            color: blueText(context),
            semanticLabel: 'Verified',
          ),
        ],
      ],
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
        if (widget.contacts.isNotEmpty)
          _PickerNote(
            text: atMax
                ? 'Groups can have up to $maxGroupMembers people, '
                      "including you. Remove someone to pick another."
                : "Only people you've chatted with are listed.",
            action: atMax ? null : 'Someone missing?',
            onAction: () => _explainMissing(context),
          ),
        if (widget.selected.isNotEmpty)
          // Sized by its chips (not a fixed height), so large text sizes
          // don't clip them.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
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
              ? _PickerEmpty(
                  title: 'No one to add yet',
                  body:
                      "Groups are made from people you've already chatted "
                      'with. Message someone first, then come back.',
                  action: 'Find people',
                  onAction: () => _openPeopleSearch(context, ''),
                )
              : shown.isEmpty && q.isEmpty
              ? const _PickerEmpty(
                  title: 'Everyone is already here',
                  body: 'Everyone you chat with is already in this group.',
                )
              : shown.isEmpty
              ? _PickerEmpty(
                  title: 'No one named "${_query.trim()}" in your chats',
                  body:
                      'To add someone new, message them first. If they '
                      'get it as a message request, they need to accept it '
                      'before you can add them.',
                  action: 'Find "${_query.trim()}" on Giggre',
                  onAction: () => _openPeopleSearch(context, _query.trim()),
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

void _openPeopleSearch(BuildContext context, String query) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => UserSearchScreen(initialQuery: query)),
  );
}

/// "Someone missing?": who can be added, and how to fix it.
void _explainMissing(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final muted = Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7);
      Widget line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: blueText(ctx)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 14, color: muted)),
            ),
          ],
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Who you can add',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              line(
                Icons.chat_bubble_outline_rounded,
                'People you have a chat with: a gig chat, a chat with a '
                'favorite worker, or a message they accepted.',
              ),
              line(
                Icons.schedule_rounded,
                "Not yet: someone who hasn't accepted your message request, "
                "or someone you've never messaged, like a worker who only "
                'applied to your gig.',
              ),
              line(
                Icons.block_rounded,
                "Never: people you've blocked or who blocked you.",
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openPeopleSearch(context, '');
                  },
                  child: const Text('Message someone new'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One line of context under the picker's search field.
class _PickerNote extends StatelessWidget {
  const _PickerNote({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, color: muted)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: blueText(context),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                action!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 48,
              color: onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.85),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: blueText(context),
                  backgroundColor: blueText(context).withValues(alpha: 0.12),
                ),
                child: Text(
                  action!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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

    // One announcement per row: "Weekend Crew, unread, muted, Ana: see
    // you at 9, Tue 3:04 PM, button".
    final label = [
      group['name'] as String? ?? 'Group',
      if (unread) 'unread',
      if (muted) 'muted',
      if (preview.isNotEmpty) preview,
      if (at != null) _listTime(at),
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      // excludeSemantics drops the inner GestureDetector's action too, so
      // the tap is exposed here.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
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
              GroupAvatar(
                photoUrl: group['photoUrl'] as String?,
                groupId: groupId,
                name: group['name'] as String?,
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
