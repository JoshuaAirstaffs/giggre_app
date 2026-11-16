import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/content_filter_service.dart';
import '../../../../core/widgets/skill_icon.dart';

/// A searchable, filterable skill picker shown as a modal bottom sheet.
///
/// Usage:
/// ```dart
/// final picked = await SkillPickerSheet.show(
///   context,
///   skills: _skills,          // List<Map<String,dynamic>> with 'name' & 'category'
///   accentColor: _kPurple,
/// );
/// if (picked != null) setState(() => _selectedSkill = picked);
/// ```
/// "Other" — the host types a skill that isn't in the list. Returns the
/// trimmed skill name, or null if cancelled. Shared by the Open gig picker
/// and the Offered gig dropdown.
Future<String?> promptOtherSkill(
  BuildContext context, {
  String initial = '',
  Color accentColor = Colors.blue,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OtherSkillDialog(initial: initial, accentColor: accentColor),
  );
}

class _OtherSkillDialog extends StatefulWidget {
  final String initial;
  final Color accentColor;
  const _OtherSkillDialog({required this.initial, required this.accentColor});

  @override
  State<_OtherSkillDialog> createState() => _OtherSkillDialogState();
}

class _OtherSkillDialogState extends State<_OtherSkillDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length < 2) {
      setState(() => _error = 'Enter the skill (at least 2 characters).');
      return;
    }
    if (ContentFilterService.instance.check(v)) {
      setState(() => _error = 'Please use a different word.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Other skill', style: TextStyle(color: onSurface, fontSize: 17, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Not in the list? Type the skill this gig needs.',
            style: TextStyle(color: kSub, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Aircon cleaning',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.accentColor, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: kSub))),
        TextButton(
          onPressed: _submit,
          child: Text('Use this skill', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// The "Other — not listed" row at the end of the skill list.
class _OtherSkillTile extends StatelessWidget {
  final Color accentColor;
  final String query;
  final VoidCallback onTap;
  const _OtherSkillTile({required this.accentColor, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.edit_rounded, color: accentColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    query.trim().isEmpty ? 'Other' : 'Other: "${query.trim()}"',
                    style: TextStyle(color: onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Text('Skill not listed? Type your own', style: TextStyle(color: kSub, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accentColor),
          ],
        ),
      ),
    );
  }
}

class SkillPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> skills;
  final String? selectedSkill;
  final Color accentColor;

  const SkillPickerSheet({
    super.key,
    required this.skills,
    this.selectedSkill,
    required this.accentColor,
  });

  static Future<String?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> skills,
    String? selectedSkill,
    Color accentColor = Colors.blue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SkillPickerSheet(
        skills: skills,
        selectedSkill: selectedSkill,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<SkillPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOther() async {
    final typed = await promptOtherSkill(context, initial: _query.trim(), accentColor: widget.accentColor);
    if (typed == null || !mounted) return;
    // Same as a listed skill if it matches one (any capitalisation).
    final match = widget.skills
        .map((s) => s['name'] as String? ?? '')
        .firstWhere((n) => n.toLowerCase() == typed.toLowerCase(), orElse: () => typed);
    Navigator.pop(context, match);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final screenHeight = MediaQuery.of(context).size.height;

    final categories = widget.skills
        .map((s) => s['category'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final q = _query.toLowerCase().trim();
    final filtered = widget.skills.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final cat = s['category'] as String? ?? '';
      return (q.isEmpty || name.contains(q)) &&
          (_selectedCategory == null || cat == _selectedCategory);
    }).toList();

    return Container(
      height: screenHeight * 0.80,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.construction_rounded,
                      color: widget.accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select a Skill',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const Text('Search or filter by category',
                          style: TextStyle(color: kSub, fontSize: 12)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: kSub, size: 16),
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              autofocus: true,
              style: TextStyle(fontSize: 14, color: onSurface),
              decoration: InputDecoration(
                hintText: 'Search skills…',
                hintStyle: const TextStyle(color: kSub, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: kSub, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        child: const Icon(Icons.close_rounded,
                            color: kSub, size: 16),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Category chips
          if (categories.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _Chip(
                    label: 'All',
                    selected: _selectedCategory == null,
                    color: widget.accentColor,
                    isDark: isDark,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  ...categories.map((cat) => _Chip(
                        label: cat,
                        selected: _selectedCategory == cat,
                        color: widget.accentColor,
                        isDark: isDark,
                        onTap: () => setState(() => _selectedCategory =
                            _selectedCategory == cat ? null : cat),
                      )),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Count row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  '${filtered.length} skill${filtered.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: kSub, fontSize: 11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Skill list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_rounded,
                            color: kSub, size: 38),
                        const SizedBox(height: 10),
                        Text(
                          _query.isNotEmpty || _selectedCategory != null
                              ? 'No skills match your search.'
                              : 'No skills available.',
                          style: const TextStyle(
                              color: kSub,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _OtherSkillTile(
                            accentColor: widget.accentColor,
                            query: _query,
                            onTap: _pickOther,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: filtered.length + 1,
                    itemBuilder: (_, i) {
                      // Last row: "Other — skill not listed".
                      if (i == filtered.length) {
                        return _OtherSkillTile(
                          accentColor: widget.accentColor,
                          query: _query,
                          onTap: _pickOther,
                        );
                      }
                      final skill = filtered[i];
                      final name = skill['name'] as String? ?? '';
                      final cat = skill['category'] as String? ?? '';
                      final isSelected = name == widget.selectedSkill;
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, name),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? widget.accentColor.withValues(alpha: 0.08)
                                : isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? widget.accentColor
                                      .withValues(alpha: 0.5)
                                  : divider,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: widget.accentColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: SkillIcon(
                                    name,
                                    color: widget.accentColor,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: TextStyle(
                                            color: onSurface,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    if (cat.isNotEmpty)
                                      Text(cat,
                                          style: const TextStyle(
                                              color: kSub, fontSize: 11)),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: widget.accentColor, size: 18),
                            ],
                          ),
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

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? color
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kSub,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
