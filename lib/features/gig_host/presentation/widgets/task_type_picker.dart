import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One task type from the admin GSIN Library (gsin_task_types).
class GsinTaskTypeOption {
  final String id;
  final String name;
  final String subcategoryName;
  final String categoryName;
  /// Lowercased names of the skills linked to this task type.
  final Set<String> skills;
  const GsinTaskTypeOption({
    required this.id,
    required this.name,
    required this.subcategoryName,
    required this.categoryName,
    this.skills = const {},
  });
  String get group => '$categoryName › $subcategoryName';
  bool fitsSkill(String? skill) =>
      skill != null && skill.trim().isNotEmpty && skills.contains(skill.trim().toLowerCase());
}

/// Loads the GSIN Library (categories, sub-categories, task types).
/// Empty list when nothing has been set up yet or it can't be read.
Future<List<GsinTaskTypeOption>> loadGsinTaskTypes() async {
  try {
    final db = FirebaseFirestore.instance;
    final res = await Future.wait([
      db.collection('gsin_categories').get(),
      db.collection('gsin_subcategories').get(),
      db.collection('gsin_task_types').get(),
      db.collection('skills').get(),
    ]);
    // Skill links: task type skillIds (many-to-many) + legacy skills/{id}.taskTypeId.
    final skillName = <String, String>{};
    final legacy = <String, Set<String>>{};
    for (final d in res[3].docs) {
      final n = (d.data()['name'] ?? '').toString().toLowerCase();
      skillName[d.id] = n;
      final tt = (d.data()['taskTypeId'] ?? '').toString();
      if (tt.isNotEmpty && n.isNotEmpty) legacy.putIfAbsent(tt, () => {}).add(n);
    }
    final cats = {for (final d in res[0].docs) d.id: (d.data()['name'] ?? d.id).toString()};
    final subs = {for (final d in res[1].docs) d.id: (d.data()['name'] ?? d.id).toString()};
    final list = res[2].docs.map((d) {
      final m = d.data();
      return GsinTaskTypeOption(
        id: d.id,
        name: (m['name'] ?? d.id).toString(),
        subcategoryName: subs[m['subcategoryId']] ?? (m['subcategoryId'] ?? '').toString(),
        categoryName: cats[m['categoryId']] ?? (m['categoryId'] ?? '').toString(),
        skills: {
          for (final sid in (m['skillIds'] is List ? m['skillIds'] as List : const []))
            if ((skillName[sid.toString()] ?? '').isNotEmpty) skillName[sid.toString()]!,
          ...?legacy[d.id],
        },
      );
    }).toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        return g != 0 ? g : a.name.compareTo(b.name);
      });
    return list;
  } catch (e) {
    debugPrint('[gsin] could not load task types: $e');
    return const [];
  }
}

/// Tappable field that opens a searchable sheet of task types.
/// Shown only when the admin has set up task types; required in that case.
///
/// With [skill] (Open / Offered gigs), task types linked to that skill are
/// listed first as "Suggested", and when exactly one matches it's picked
/// automatically (the host can still change it).
///
/// With [enabled] false (editing a posted gig) it's locked: no picker, no
/// auto-pick, not required. Hosts can't set it (firestore.rules), but the
/// server re-derives it when the skill changes (gsin.ts followSkillChange).
/// So when [skill] differs from [originalSkill] it previews that result.
class TaskTypeField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? skill;
  final bool enabled;
  final String? originalSkill;
  const TaskTypeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.skill,
    this.enabled = true,
    this.originalSkill,
  });

  @override
  State<TaskTypeField> createState() => _TaskTypeFieldState();
}

class _TaskTypeFieldState extends State<TaskTypeField> {
  List<GsinTaskTypeOption>? _options;
  String? _autoPicked; // id we picked from the skill (replaced if the skill changes)

  @override
  void initState() {
    super.initState();
    loadGsinTaskTypes().then((o) {
      if (!mounted) return;
      setState(() => _options = o);
      _autoPick();
    });
  }

  @override
  void didUpdateWidget(TaskTypeField old) {
    super.didUpdateWidget(old);
    if (old.skill != widget.skill) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoPick();
      });
    }
  }

  void _autoPick() {
    if (!widget.enabled) return;
    final opts = _options;
    if (opts == null) return;
    // Only replace an empty choice or one we auto-picked — never the host's own pick.
    if (widget.value != null && widget.value != _autoPicked) return;
    final matches = opts.where((o) => o.fitsSkill(widget.skill)).toList();
    final next = matches.length == 1 ? matches.first.id : null;
    if (next == widget.value) return;
    if (next == null && _autoPicked == null) return;
    _autoPicked = next;
    widget.onChanged(next);
  }

  GsinTaskTypeOption? get _selected {
    final opts = _options;
    if (opts == null || widget.value == null) return null;
    for (final o in opts) {
      if (o.id == widget.value) return o;
    }
    return null;
  }

  static String _norm(String? s) => (s ?? '').trim().toLowerCase();

  bool get _skillChanged =>
      !widget.enabled &&
      _norm(widget.skill).isNotEmpty &&
      _norm(widget.skill) != _norm(widget.originalSkill);

  /// Locked + skill changed: what the server will set (mirrors
  /// followSkillChange). Null → it'll be cleared for an admin to assign.
  GsinTaskTypeOption? get _previewAfterSkillChange {
    final opts = _options ?? const [];
    final current = _selected;
    if (current != null && current.fitsSkill(widget.skill)) return current;
    final matches = opts.where((o) => o.fitsSkill(widget.skill)).toList();
    return matches.length == 1 ? matches.first : null;
  }

  Future<void> _open(FormFieldState<String> field) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TaskTypeSheet(options: _options ?? const [], selected: widget.value, skill: widget.skill),
    );
    if (picked != null) {
      _autoPicked = null; // host's own choice from here on
      widget.onChanged(picked);
      field.didChange(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options;
    // Still loading, or the admin hasn't set up task types yet → nothing to pick.
    if (opts == null || opts.isEmpty) return const SizedBox.shrink();
    final textColor = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<String>(
        initialValue: widget.value,
        validator: (_) =>
            widget.enabled && widget.value == null ? 'Pick the type of task' : null,
        builder: (field) {
          final locked = !widget.enabled;
          final skillChanged = _skillChanged;
          final sel = skillChanged ? _previewAfterSkillChange : _selected;
          final willChange = skillChanged && sel?.id != widget.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task Type',
                style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: locked ? null : () => _open(field),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: locked
                        ? textColor.withValues(alpha: 0.04)
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: field.hasError ? Colors.redAccent : borderColor,
                      width: field.hasError ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: sel == null
                            ? Text(
                                locked
                                    ? (skillChanged ? 'Assigned by Giggre' : 'Not set')
                                    : 'Choose what kind of task this is',
                                style: TextStyle(color: textColor.withValues(alpha: 0.35), fontSize: 14))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(sel.name,
                                      style: TextStyle(
                                          color: locked ? textColor.withValues(alpha: 0.7) : textColor,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(sel.group,
                                      style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11)),
                                ],
                              ),
                      ),
                      Icon(
                        locked ? Icons.lock_outline_rounded : Icons.expand_more,
                        size: locked ? 18 : 24,
                        color: textColor.withValues(alpha: locked ? 0.4 : 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                      willChange
                          ? 'Updates to match the new skill when you save.'
                          : 'Set from the skill. It updates when the skill changes.',
                      style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11)),
                ),
              if (field.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(field.errorText!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskTypeSheet extends StatefulWidget {
  final List<GsinTaskTypeOption> options;
  final String? selected;
  final String? skill;
  const _TaskTypeSheet({required this.options, required this.selected, this.skill});

  @override
  State<_TaskTypeSheet> createState() => _TaskTypeSheetState();
}

class _TaskTypeSheetState extends State<_TaskTypeSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final q = _q.trim().toLowerCase();
    final matches = widget.options
        .where((o) => q.isEmpty || '${o.name} ${o.group}'.toLowerCase().contains(q))
        .toList();
    // Task types linked to the gig's skill first, under their own heading.
    final suggested = matches.where((o) => o.fitsSkill(widget.skill)).toList();
    final list = [...suggested, ...matches.where((o) => !o.fitsSkill(widget.skill))];
    String groupOf(int i) => i < suggested.length ? 'Suggested for ${widget.skill!.trim()}' : list[i].group;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text('Task Type',
                        style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search task types…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text('No match',
                            style: TextStyle(color: textColor.withValues(alpha: 0.5))),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final o = list[i];
                          final showGroup = i == 0 || groupOf(i - 1) != groupOf(i);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showGroup)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                                  child: Text(groupOf(i).toUpperCase(),
                                      style: TextStyle(
                                          color: textColor.withValues(alpha: 0.45),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5)),
                                ),
                              ListTile(
                                title: Text(o.name, style: TextStyle(color: textColor, fontSize: 14)),
                                subtitle: i < suggested.length
                                    ? Text(o.group,
                                        style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11))
                                    : null,
                                trailing: o.id == widget.selected
                                    ? const Icon(Icons.check_circle, color: kAmber)
                                    : null,
                                onTap: () => Navigator.pop(context, o.id),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
