import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/group_chat/group_chat_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';
import 'package:giggre_app/features/group_chat/group_widgets.dart';
import 'package:giggre_app/helpers/snackbar_helper.dart';

// TEMP switch: false blocks creating a group at the Next step.
const _groupCreationEnabled = false;

/// New group: pick at least two people from your chats, then name it.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  late final Future<List<GroupPerson>> _contacts = GroupChatService.contacts(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  );
  Set<String> _selected = {};

  // Naming is its own route, so the platform back (iOS edge swipe, Android
  // back) returns here with the selection intact.
  void _next(List<GroupPerson> contacts) {
    // TEMP: group creation is switched off for now. Next shows an error
    // instead of the naming step. Set _groupCreationEnabled to true to
    // turn it back on.
    if (!_groupCreationEnabled) {
      SnackbarHelper.showError(
        context,
        "Groups can't be created right now. Please try again later.",
      );
      return;
    }
    final pickerRoute = ModalRoute.of(context)!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _NameGroupScreen(
          members: contacts.where((p) => _selected.contains(p.uid)).toList(),
          pickerRoute: pickerRoute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final canNext = _selected.length >= 2;

    return FutureBuilder<List<GroupPerson>>(
      future: _contacts,
      builder: (context, snap) {
        final contacts = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'New group',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  switch (_selected.length) {
                    0 => 'Pick at least 2 people',
                    1 => '1 selected · pick 1 more',
                    final n => '$n selected',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // In thumb reach, not top-right.
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: canNext && contacts != null
                    ? () => _next(contacts)
                    : null,
                child: Text(
                  canNext ? 'Next (${_selected.length})' : 'Next',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snap.hasError
              ? const Center(
                  child: Text("Couldn't load your chats. Try again."),
                )
              : ContactPicker(
                  contacts: contacts!,
                  selected: _selected,
                  // You count as one of the members.
                  maxSelectable: maxGroupMembers - 1,
                  onChanged: (s) => setState(() => _selected = s),
                ),
        );
      },
    );
  }
}

class _NameGroupScreen extends StatefulWidget {
  const _NameGroupScreen({required this.members, required this.pickerRoute});

  final List<GroupPerson> members;
  // Removed together with this screen once the group exists, so Back from
  // the new group goes to wherever New group was opened from.
  final Route<dynamic> pickerRoute;

  @override
  State<_NameGroupScreen> createState() => _NameGroupScreenState();
}

class _NameGroupScreenState extends State<_NameGroupScreen> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final id = await GroupChatService.create(
        name,
        widget.members.map((p) => p.uid).toList(),
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (widget.pickerRoute.isActive) nav.removeRoute(widget.pickerRoute);
      nav.pushReplacement(
        MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      showGroupError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty && !_creating;

    // Back is only held while the group is being created.
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Name your group',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Center(child: GroupAvatar(radius: 40)),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: maxGroupNameLength,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'e.g. Weekend Crew',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Members can see each other's names and photos. "
                'You can add a group photo later.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: chatMetaColor(context),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Members (${widget.members.length + 1})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  const Chip(label: Text('You')),
                  for (final p in widget.members)
                    Chip(
                      avatar: PersonAvatar(person: p, radius: 12),
                      label: Text(p.name),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: ready ? _create : null,
                  child: _creating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create group',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
