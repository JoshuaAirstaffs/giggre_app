import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/services/rating_service.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/chat/user_search_screen.dart'
    show openDirectChat;
import 'package:giggre_app/features/gig_shared/user_profile_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';
import 'package:giggre_app/features/group_chat/group_widgets.dart';
import 'package:giggre_app/features/live_support/live_support_bubble.dart'
    show HidesLiveSupport; // TEMP: live support
import 'package:image_picker/image_picker.dart';

/// Members, name, photo, mute and leave. Admin-only actions are hidden for
/// everyone else (and refused by the server regardless).
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen>
    with HidesLiveSupport {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final _stream = GroupChatService.group(widget.groupId);
  Map<String, GroupPerson> _people = {};
  String _peopleKey = '';
  bool _busy = false;

  void _loadPeople(List<String> uids) {
    final key = uids.join(',');
    if (key == _peopleKey) return;
    _peopleKey = key;
    GroupChatService.people(uids).then((p) {
      if (mounted) setState(() => _people = p);
    });
  }

  Future<void> _guard(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) showGroupError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _rename(String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: current),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == current) return;
    await _guard(() => GroupChatService.rename(widget.groupId, trimmed));
  }

  Future<void> _changePhoto(bool hasPhoto) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: blueText(context),
              ),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: blueText(context),
              ),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      await _guard(() => GroupChatService.removePhoto(widget.groupId));
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (picked == null) return;
    await _guard(
      () => GroupChatService.setPhoto(widget.groupId, File(picked.path)),
    );
  }

  Future<void> _addPeople(List<String> members) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddMembersScreen(
          groupId: widget.groupId,
          existing: members.toSet(),
        ),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Added to the group')));
    }
  }

  void _memberActions({
    required GroupPerson person,
    required bool iAmAdmin,
    required bool theyAreAdmin,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PersonAvatar(person: person),
              title: Text(
                person.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(ctx);
                UserProfileScreen.push(
                  context,
                  uid: person.uid,
                  fallbackName: person.name,
                  surface: 'group_info',
                  role: RateeRole.worker,
                  onMessage: () => openDirectChat(
                    context,
                    peerUid: person.uid,
                    peerName: person.name,
                  ),
                );
              },
            ),
            if (iAmAdmin && !theyAreAdmin)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Make group admin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _guard(
                    () =>
                        GroupChatService.makeAdmin(widget.groupId, person.uid),
                    done: '${person.name} is now an admin',
                  );
                },
              ),
            if (iAmAdmin)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove from group',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirm(
                    title: 'Remove ${person.name}?',
                    body:
                        "They'll stop getting messages and won't see "
                        'the chat anymore.',
                    action: 'Remove',
                  );
                  if (ok) {
                    await _guard(
                      () => GroupChatService.removeMember(
                        widget.groupId,
                        person.uid,
                      ),
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _leave({required bool lastAdmin}) async {
    final ok = await _confirm(
      title: 'Leave this group?',
      body: lastAdmin
          ? "You won't see this chat anymore. You're the only admin, so "
                'the longest-standing member will become admin.'
          : "You won't see this chat or get its messages anymore.",
      action: 'Leave',
    );
    if (!ok) return;
    await _guard(() async {
      await GroupChatService.leave(widget.groupId);
      if (!mounted) return;
      // Back past the chat itself to wherever it was opened from.
      var popped = 0;
      Navigator.of(context).popUntil((_) => popped++ >= 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          final group = snap.data?.data();
          if (snap.hasError || (snap.hasData && group == null)) {
            return const Center(child: Text("This group isn't available."));
          }
          if (group == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = List<String>.from(group['participants'] as List);
          final admins = Set<String>.from(group['admins'] as List? ?? const []);
          final creator = group['createdBy'] as String? ?? '';
          if (!members.contains(_uid)) {
            return const Center(child: Text("You're no longer in this group."));
          }
          _loadPeople(members);
          final iAmAdmin = admins.contains(_uid);
          final name = group['name'] as String? ?? 'Group';
          final photo = group['photoUrl'] as String?;
          final muted = GroupChatService.isMuted(group, _uid);
          // You first, then the creator, then admins, then everyone by name.
          final sorted = [...members]
            ..sort((a, b) {
              if (a == _uid) return -1;
              if (b == _uid) return 1;
              if (a == creator) return -1;
              if (b == creator) return 1;
              final aa = admins.contains(a), ba = admins.contains(b);
              if (aa != ba) return aa ? -1 : 1;
              return (_people[a]?.name ?? '').toLowerCase().compareTo(
                (_people[b]?.name ?? '').toLowerCase(),
              );
            });

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: Semantics(
                      button: iAmAdmin,
                      image: true,
                      label: iAmAdmin ? 'Change group photo' : 'Group photo',
                      onTap: iAmAdmin
                          ? () => _changePhoto(photo?.isNotEmpty == true)
                          : null,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: iAmAdmin
                            ? () => _changePhoto(photo?.isNotEmpty == true)
                            : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GroupAvatar(
                              photoUrl: photo,
                              radius: 48,
                              groupId: widget.groupId,
                              name: name,
                            ),
                            if (iAmAdmin)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: kBlue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (iAmAdmin)
                          IconButton(
                            tooltip: 'Rename group',
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                            onPressed: () => _rename(name),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'Group · ${members.length} members',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    isDark: isDark,
                    child: SwitchListTile(
                      value: muted,
                      activeThumbColor: kBlue,
                      secondary: Icon(
                        muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_none_rounded,
                      ),
                      title: const Text('Mute notifications'),
                      subtitle: const Text(
                        'Messages still arrive, without alerts',
                      ),
                      onChanged: (v) => _guard(
                        () => GroupChatService.setMuted(widget.groupId, v),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      '${members.length} MEMBERS',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  _Section(
                    isDark: isDark,
                    child: Column(
                      children: [
                        if (iAmAdmin && members.length < maxGroupMembers)
                          ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: blueText(
                                context,
                              ).withValues(alpha: 0.12),
                              child: Icon(
                                Icons.person_add_alt_1_rounded,
                                color: blueText(context),
                              ),
                            ),
                            title: Text(
                              'Add people',
                              style: TextStyle(
                                color: blueText(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => _addPeople(members),
                          ),
                        for (final uid in sorted)
                          ListTile(
                            leading: PersonAvatar(person: _people[uid]),
                            title: VerifiedName(
                              name: uid == _uid
                                  ? 'You'
                                  : _people[uid]?.name ?? '…',
                              verified: _people[uid]?.isVerified ?? false,
                            ),
                            // Trust at a glance: how they're rated, same
                            // wording as user search.
                            subtitle: _people[uid] == null
                                ? null
                                : Text(
                                    _people[uid]!.ratingLine ??
                                        'No ratings yet',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: chatMetaColor(context),
                                    ),
                                  ),
                            // The creator shows as Creator (even though
                            // they're an admin too); later admins as Admin.
                            trailing: uid == creator
                                ? const _RoleBadge(label: 'Creator')
                                : admins.contains(uid)
                                ? const _RoleBadge(label: 'Admin')
                                : null,
                            onTap: uid == _uid || _people[uid] == null
                                ? null
                                : () => _memberActions(
                                    person: _people[uid]!,
                                    iAmAdmin: iAmAdmin,
                                    theyAreAdmin: admins.contains(uid),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    isDark: isDark,
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout_rounded,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        'Leave group',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () =>
                          _leave(lastAdmin: iAmAdmin && admins.length == 1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text(
                      'To report someone, tap their name and open their '
                      'profile. To report a message, press and hold it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final blue = blueText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: blue,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.isDark, required this.child});
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? kCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _AddMembersScreen extends StatefulWidget {
  const _AddMembersScreen({required this.groupId, required this.existing});

  final String groupId;
  final Set<String> existing;

  @override
  State<_AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<_AddMembersScreen> {
  late final Future<List<GroupPerson>> _contacts = GroupChatService.contacts(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  );
  Set<String> _selected = {};
  bool _adding = false;

  Future<void> _add() async {
    if (_selected.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await GroupChatService.addMembers(widget.groupId, _selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      showGroupError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = maxGroupMembers - widget.existing.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add people'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _adding ? null : _add,
            child: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_selected.isEmpty ? 'Add' : 'Add (${_selected.length})'),
          ),
        ],
      ),
      body: FutureBuilder<List<GroupPerson>>(
        future: _contacts,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(
              child: Text("Couldn't load your chats. Try again."),
            );
          }
          return ContactPicker(
            contacts: snap.data!,
            selected: _selected,
            exclude: widget.existing,
            maxSelectable: room,
            onChanged: (s) => setState(() => _selected = s),
          );
        },
      ),
    );
  }
}

/// Owns its text controller, so it's disposed only once the dialog has
/// finished closing (disposing it as soon as showDialog returned broke the
/// still-animating TextField).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Group name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxGroupNameLength,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
