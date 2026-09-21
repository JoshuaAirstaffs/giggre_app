/// A worker's skills, read from the field that actually holds them.
///
/// Skills live in `skillsXP` on the user document — a map of skill name to
/// experience points, maintained by the Toolchest through the admin approval
/// flow in `skill_requests`.
///
/// There is also a `skills` array on every user document, but it is written
/// as `[]` at registration and never touched again. Reading that one is why
/// profiles showed no skills at all: the list was not empty by accident, it
/// was never filled. It is still consulted as a fallback here, so any account
/// that did get one keeps working, but `skillsXP` is the source of truth.
///
/// Ordered strongest first, so the skills someone has actually worked at lead
/// — a profile that shows four of eight should show the four that matter.
/// Ties fall back to alphabetical so the order is stable between reads.
List<String> workerSkillsFrom(Map<String, dynamic>? userData) {
  final xp = userData?['skillsXP'] as Map<String, dynamic>?;

  if (xp != null && xp.isNotEmpty) {
    final ranked =
        xp.entries
            .map(
              (e) => (name: e.key.trim(), xp: (e.value as num?)?.toInt() ?? 0),
            )
            .where((e) => e.name.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final byXp = b.xp.compareTo(a.xp);
            return byXp != 0
                ? byXp
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    if (ranked.isNotEmpty) return [for (final e in ranked) e.name];
  }

  return (userData?['skills'] as List<dynamic>? ?? const [])
      .map((s) => s.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
