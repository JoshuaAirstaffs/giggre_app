import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  SCRATCHPAD — Your personal Flutter/Dart sandbox
//
//  HOW TO USE:
//   • Scroll down to the "MyScratch" widget at the bottom of this file.
//   • Edit it freely — the preview above will reflect your changes on hot reload.
//   • Everything above MyScratch is just the frame; you don't need to touch it.
//
//  QUICK TIPS:
//   • Hot reload  →  save the file (Cmd+S) or press 'r' in terminal
//   • Hot restart →  press 'R' in terminal (resets all state)
//   • Wrap a widget with another: place cursor on it → Cmd+. → "Wrap with..."
// ═══════════════════════════════════════════════════════════════════════════════

class ScratchpadTab extends StatelessWidget {
  const ScratchpadTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kAmber.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: kAmber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scratchpad',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Edit MyScratch at the bottom of scratchpad_tab.dart → hot reload to see changes',
                      style: TextStyle(color: kSub, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Live preview of MyScratch ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live Preview',
                    style: TextStyle(color: kSub, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Center(child: MyScratch()),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Dart cheat-sheet ──────────────────────────────────────────────────
        _CodeCard(
          title: 'Dart Cheat Sheet',
          snippets: [
            _Snippet('Variable types',
                'var name = "Gemar";     // inferred\n'
                'String city = "Manila"; // explicit\n'
                'final pi = 3.14;        // immutable, runtime\n'
                'const MAX = 100;        // compile-time constant'),
            _Snippet('Collections',
                'List<int> nums = [1, 2, 3];\n'
                'Map<String, int> scores = {"Dart": 10, "Flutter": 20};\n'
                'Set<String> tags = {"mobile", "ui"};\n'
                'nums.map((n) => n * 2).toList(); // [2, 4, 6]'),
            _Snippet('Null safety',
                'String? name;          // nullable\n'
                'String name2 = "hi";   // non-null\n'
                'print(name?.length);   // null-aware access\n'
                'print(name ?? "anon"); // fallback value'),
            _Snippet('Functions',
                '// Named parameters\n'
                'void greet({required String name, int age = 18}) {}\n\n'
                '// Arrow function\n'
                'int double(int x) => x * 2;\n\n'
                '// Anonymous / lambda\n'
                'final add = (int a, int b) => a + b;'),
            _Snippet('async / await',
                'Future<String> fetchUser() async {\n'
                '  await Future.delayed(Duration(seconds: 1));\n'
                '  return "Gemar";\n'
                '}\n\n'
                '// Call it:\n'
                'final user = await fetchUser();'),
            _Snippet('Classes',
                'class Dog {\n'
                '  final String name;\n'
                '  Dog(this.name);          // shorthand constructor\n\n'
                '  void bark() => print("Woof! I am \$name");\n'
                '}\n\n'
                'final d = Dog("Rex");\n'
                'd.bark();'),
          ],
        ),

        const SizedBox(height: 12),

        _CodeCard(
          title: 'Flutter Widget Patterns',
          snippets: [
            _Snippet('StatefulWidget skeleton',
                'class MyWidget extends StatefulWidget {\n'
                '  const MyWidget({super.key});\n'
                '  @override\n'
                '  State<MyWidget> createState() => _MyWidgetState();\n'
                '}\n\n'
                'class _MyWidgetState extends State<MyWidget> {\n'
                '  int count = 0;\n'
                '  @override\n'
                '  Widget build(BuildContext context) {\n'
                '    return Text("\$count");\n'
                '  }\n'
                '}'),
            _Snippet('GestureDetector',
                'GestureDetector(\n'
                '  onTap: () => print("tapped"),\n'
                '  onLongPress: () => print("long pressed"),\n'
                '  child: Container(width: 100, height: 100),\n'
                ')'),
            _Snippet('FutureBuilder',
                'FutureBuilder<String>(\n'
                '  future: fetchUser(),\n'
                '  builder: (ctx, snapshot) {\n'
                '    if (snapshot.connectionState == ConnectionState.waiting)\n'
                '      return CircularProgressIndicator();\n'
                '    if (snapshot.hasError)\n'
                '      return Text("Error: \${snapshot.error}");\n'
                '    return Text(snapshot.data!);\n'
                '  },\n'
                ')'),
            _Snippet('MediaQuery — responsive sizing',
                'final width  = MediaQuery.of(context).size.width;\n'
                'final height = MediaQuery.of(context).size.height;\n'
                'final isTablet = width > 600;\n\n'
                '// Use as fraction:\n'
                'Container(width: width * 0.8)'),
          ],
        ),
      ],
    );
  }
}

// ── Code card helper ──────────────────────────────────────────────────────────

class _Snippet {
  final String title;
  final String code;
  const _Snippet(this.title, this.code);
}

class _CodeCard extends StatelessWidget {
  final String title;
  final List<_Snippet> snippets;

  const _CodeCard({required this.title, required this.snippets});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...snippets.map((s) => _SnippetTile(s)),
        ],
      ),
    );
  }
}

class _SnippetTile extends StatefulWidget {
  final _Snippet snippet;
  const _SnippetTile(this.snippet);

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: kBorder, height: 1),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  color: kSub,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.snippet.title,
                    style: TextStyle(
                      color: _expanded ? kBlue : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: Text(
              widget.snippet.code,
              style: const TextStyle(
                color: Colors.lightGreenAccent,
                fontSize: 11.5,
                fontFamily: 'monospace',
                height: 1.6,
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//
//  ✏️  YOUR SANDBOX — Edit freely below this line!
//
//  This is "MyScratch". Change it to whatever you want to experiment with.
//  Hot reload (Cmd+S) and the Live Preview above will update instantly.
//
//  Ideas to try:
//   • Change colors, sizes, shapes
//   • Add new widgets inside the Column
//   • Make it a StatefulWidget and add a counter
//   • Try a Stack, GridView, or AnimatedContainer
//
// ═══════════════════════════════════════════════════════════════════════════════

class MyScratch extends StatelessWidget {
  const MyScratch({super.key});

  @override
  Widget build(BuildContext context) {
    // ↓ Start editing here ↓
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kBlue, kAmber],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.code_rounded, color: Colors.white, size: 52),
        ),
        const SizedBox(height: 16),
        const Text(
          'Hello, Playground!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Edit MyScratch in scratchpad_tab.dart',
          style: TextStyle(color: kSub, fontSize: 12),
        ),
      ],
    );
    // ↑ End editing here ↑
  }
}
