import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/group_chat/group_chat_screen.dart';
import 'package:giggre_app/features/group_chat/group_chat_service.dart';
import 'package:giggre_app/features/group_chat/group_widgets.dart';

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
  final _name = TextEditingController();
  Set<String> _selected = {};
  bool _naming = false;
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
      final id = await GroupChatService.create(name, _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final canNext = _selected.length >= 2;

    return PopScope(
      canPop: !_naming,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_creating) setState(() => _naming = false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _naming ? 'Name your group' : 'New group',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
          actions: [
            if (!_naming)
              TextButton(
                onPressed: canNext
                    ? () => setState(() => _naming = true)
                    : null,
                child: const Text('Next'),
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
            final contacts = snap.data!;
            if (_naming) return _nameStep(contacts);
            return ContactPicker(
              contacts: contacts,
              selected: _selected,
              // You count as one of the members.
              maxSelectable: maxGroupMembers - 1,
              onChanged: (s) => setState(() => _selected = s),
            );
          },
        ),
      ),
    );
  }

  Widget _nameStep(List<GroupPerson> contacts) {
    final members = contacts.where((p) => _selected.contains(p.uid)).toList();
    final ready = _name.text.trim().isNotEmpty && !_creating;

    return SafeArea(
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
            'Members can see each other\'s names and photos. '
            'You can add a group photo later.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: chatMetaColor(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Members (${members.length + 1})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              const Chip(label: Text('You')),
              for (final p in members)
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
    );
  }
}
