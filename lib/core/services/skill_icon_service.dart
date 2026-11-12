import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Maps skill names to their GSIN sub-category icon (an Iconify SVG URL).
///
/// The admin GSIN Library sets `gsin_subcategories/{id}.icon` to an Iconify
/// name like "material-symbols:pets". A skill's icon is its sub-category's:
/// skill name → skills doc → task types whose `skillIds` contain the doc id
/// (plus the skill's legacy `taskTypeId`) → their `subcategoryId` → icon.
/// When several sub-categories have icons, the first by sub-category name
/// (case-insensitive) wins so the choice is stable.
class SkillIconService {
  SkillIconService._();
  static final SkillIconService instance = SkillIconService._();

  /// Lowercased, trimmed skill name → SVG URL.
  final ValueNotifier<Map<String, String>> icons = ValueNotifier(const {});

  Future<void>? _loading;

  static final _iconName = RegExp(r'^([a-z0-9-]+):([a-z0-9-]+)$');

  /// Iconify SVG URL for a `set:name` icon value, or null if it's not valid.
  static String? urlFor(Object? icon) {
    if (icon is! String) return null;
    final m = _iconName.firstMatch(icon.trim());
    if (m == null) return null;
    return 'https://api.iconify.design/${m.group(1)}/${m.group(2)}.svg';
  }

  String? urlForSkill(String name) => icons.value[_key(name)];

  static String _key(String name) => name.trim().toLowerCase();

  /// Loads once per app run; a failed load is retried on the next call.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final db = FirebaseFirestore.instance;
      final res = await Future.wait([
        db.collection('skills').get(),
        db.collection('gsin_task_types').get(),
        db.collection('gsin_subcategories').get(),
      ]);
      final skills = res[0].docs;
      final taskTypes = res[1].docs;
      final subcategories = res[2].docs;

      // Sub-category id → (name, url), only those with a valid icon.
      final subIcon = <String, ({String name, String url})>{};
      for (final d in subcategories) {
        final url = urlFor(d.data()['icon']);
        if (url == null) continue;
        subIcon[d.id] = (name: (d.data()['name'] ?? d.id).toString(), url: url);
      }

      // Task type id → sub-category id, and skill doc id → task type ids.
      final taskSub = <String, String>{};
      final skillTaskTypes = <String, Set<String>>{};
      for (final d in taskTypes) {
        final sub = d.data()['subcategoryId'];
        if (sub is String && sub.isNotEmpty) taskSub[d.id] = sub;
        final ids = d.data()['skillIds'];
        if (ids is List) {
          for (final id in ids) {
            skillTaskTypes.putIfAbsent(id.toString(), () => {}).add(d.id);
          }
        }
      }

      final map = <String, String>{};
      for (final d in skills) {
        final name = d.data()['name'];
        if (name is! String || name.trim().isEmpty) continue;
        final types = {...?skillTaskTypes[d.id]};
        final legacy = d.data()['taskTypeId'];
        if (legacy is String && legacy.isNotEmpty) types.add(legacy);

        ({String name, String url})? best;
        for (final t in types) {
          final candidate = subIcon[taskSub[t]];
          if (candidate == null) continue;
          if (best == null ||
              candidate.name.toLowerCase().compareTo(best.name.toLowerCase()) <
                  0) {
            best = candidate;
          }
        }
        if (best != null) map[_key(name)] = best.url;
      }

      icons.value = map;
    } catch (e) {
      debugPrint('[SkillIconService] load failed: $e');
      _loading = null;
    }
  }
}
