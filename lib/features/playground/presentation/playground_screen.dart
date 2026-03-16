import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'scratchpad_tab.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.science_rounded, color: kAmber, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Flutter Playground',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kBlue,
          labelColor: kBlue,
          unselectedLabelColor: kSub,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.widgets_rounded, size: 18), text: 'Widgets'),
            Tab(icon: Icon(Icons.animation_rounded, size: 18), text: 'Animate'),
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'State'),
            Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Layout'),
            Tab(icon: Icon(Icons.edit_note_rounded, size: 18), text: 'Scratch'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WidgetsTab(),
          _AnimationsTab(),
          _StateTab(),
          _LayoutTab(),
          ScratchpadTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS TAB
// ─────────────────────────────────────────────────────────────────────────────
class _WidgetsTab extends StatefulWidget {
  const _WidgetsTab();

  @override
  State<_WidgetsTab> createState() => _WidgetsTabState();
}

class _WidgetsTabState extends State<_WidgetsTab> {
  double _sliderValue = 0.5;
  bool _switchOn = true;
  bool _checkA = true;
  bool _checkB = false;
  int _selectedChip = 0;
  final List<String> _chips = ['Flutter', 'Dart', 'Firebase', 'Provider'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Buttons',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kBlue),
                onPressed: () => _snack(context, 'ElevatedButton tapped!'),
                child: const Text('Elevated', style: TextStyle(color: Colors.white)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kBlue),
                  foregroundColor: kBlue,
                ),
                onPressed: () => _snack(context, 'OutlinedButton tapped!'),
                child: const Text('Outlined'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: kAmber),
                onPressed: () => _snack(context, 'TextButton tapped!'),
                child: const Text('TextButton'),
              ),
              IconButton(
                icon: const Icon(Icons.favorite_rounded, color: Colors.redAccent),
                onPressed: () => _snack(context, 'IconButton tapped!'),
              ),
              FloatingActionButton.small(
                backgroundColor: kBlue,
                heroTag: 'fab_small',
                onPressed: () => _snack(context, 'FAB tapped!'),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Typography',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typoRow('displaySmall', 26, FontWeight.w700, Colors.white),
              _typoRow('headlineMedium', 20, FontWeight.w700, Colors.white),
              _typoRow('titleLarge', 18, FontWeight.w600, Colors.white),
              _typoRow('bodyLarge', 16, FontWeight.normal, Colors.white70),
              _typoRow('bodyMedium', 14, FontWeight.normal, kSub),
              _typoRow('labelSmall', 11, FontWeight.w600, kSub),
            ],
          ),
        ),
        _Section(
          title: 'Chips',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_chips.length, (i) {
              final selected = _selectedChip == i;
              return FilterChip(
                label: Text(_chips[i]),
                selected: selected,
                onSelected: (_) => setState(() => _selectedChip = i),
                backgroundColor: kCard,
                selectedColor: kBlue.withValues(alpha: 0.25),
                checkmarkColor: kBlue,
                labelStyle: TextStyle(color: selected ? kBlue : kSub, fontSize: 13),
                side: BorderSide(color: selected ? kBlue : kBorder),
              );
            }),
          ),
        ),
        _Section(
          title: 'Controls',
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded, color: kSub, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _sliderValue,
                      onChanged: (v) => setState(() => _sliderValue = v),
                      activeColor: kBlue,
                      inactiveColor: kBorder,
                    ),
                  ),
                  Text(
                    '${(_sliderValue * 100).toInt()}%',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dark mode', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Switch(
                    value: _switchOn,
                    onChanged: (v) => setState(() => _switchOn = v),
                    activeColor: kBlue,
                  ),
                ],
              ),
              Row(
                children: [
                  Checkbox(
                    value: _checkA,
                    onChanged: (v) => setState(() => _checkA = v!),
                    activeColor: kBlue,
                    side: const BorderSide(color: kBorder),
                  ),
                  const Text('Flutter is awesome', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(width: 12),
                  Checkbox(
                    value: _checkB,
                    onChanged: (v) => setState(() => _checkB = v!),
                    activeColor: kBlue,
                    side: const BorderSide(color: kBorder),
                  ),
                  const Text('Dart is fun', style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'Cards & Containers',
          child: Column(
            children: [
              Card(
                color: kCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: kBorder),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kBlue.withValues(alpha: 0.2),
                    child: const Icon(Icons.flutter_dash, color: kBlue),
                  ),
                  title: const Text('ListTile Widget', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Subtitle text here', style: TextStyle(color: kSub, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: kSub),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _colorBox('kBg', kBg),
                  const SizedBox(width: 8),
                  _colorBox('kCard', kCard),
                  const SizedBox(width: 8),
                  _colorBox('kBlue', kBlue),
                  const SizedBox(width: 8),
                  _colorBox('kAmber', kAmber),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'Progress Indicators',
          child: Column(
            children: [
              const LinearProgressIndicator(
                value: 0.65,
                color: kBlue,
                backgroundColor: kBorder,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const CircularProgressIndicator(color: kBlue, strokeWidth: 3),
                  const CircularProgressIndicator(color: kAmber, strokeWidth: 3),
                  CircularProgressIndicator(
                    value: 0.75,
                    color: Colors.greenAccent,
                    backgroundColor: kBorder,
                    strokeWidth: 3,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typoRow(String name, double size, FontWeight weight, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(name, style: TextStyle(color: kSub, fontSize: 11)),
          ),
          Text('The quick brown fox', style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
        ],
      ),
    );
  }

  Widget _colorBox(String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: kSub, fontSize: 10)),
        ],
      ),
    );
  }

  void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: kCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATIONS TAB
// ─────────────────────────────────────────────────────────────────────────────
class _AnimationsTab extends StatefulWidget {
  const _AnimationsTab();

  @override
  State<_AnimationsTab> createState() => _AnimationsTabState();
}

class _AnimationsTabState extends State<_AnimationsTab>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _scaleCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _rotateCtrl;
  late AnimationController _pulseCtrl;

  bool _fadeVisible = true;
  bool _scaleExpanded = false;
  bool _slid = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _fadeCtrl.value = 1;
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scaleCtrl.dispose();
    _slideCtrl.dispose();
    _rotateCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Fade
        _Section(
          title: 'FadeTransition',
          badge: 'AnimationController',
          child: Column(
            children: [
              Container(
                height: 80,
                alignment: Alignment.center,
                child: FadeTransition(
                  opacity: _fadeCtrl,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: kBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBlue.withValues(alpha: 0.5)),
                    ),
                    child: const Text('I fade in and out ✨', style: TextStyle(color: kBlue, fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kBlue),
                onPressed: () {
                  setState(() => _fadeVisible = !_fadeVisible);
                  _fadeVisible ? _fadeCtrl.forward() : _fadeCtrl.reverse();
                },
                icon: Icon(_fadeVisible ? Icons.visibility_off : Icons.visibility, size: 16),
                label: Text(_fadeVisible ? 'Fade Out' : 'Fade In', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),

        // Scale
        _Section(
          title: 'ScaleTransition',
          badge: 'Tween',
          child: Column(
            children: [
              Container(
                height: 100,
                alignment: Alignment.center,
                child: ScaleTransition(
                  scale: Tween(begin: 0.5, end: 1.0).animate(
                    CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kAmber, kAmber.withValues(alpha: 0.5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.star_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kAmber),
                onPressed: () {
                  setState(() => _scaleExpanded = !_scaleExpanded);
                  _scaleExpanded ? _scaleCtrl.forward() : _scaleCtrl.reverse();
                },
                icon: Icon(_scaleExpanded ? Icons.compress : Icons.expand, size: 16, color: kBg),
                label: Text(_scaleExpanded ? 'Shrink' : 'Grow', style: TextStyle(color: kBg)),
              ),
            ],
          ),
        ),

        // Slide
        _Section(
          title: 'SlideTransition',
          badge: 'Offset',
          child: Column(
            children: [
              Container(
                height: 80,
                alignment: Alignment.center,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Text('I slide from the left →', style: TextStyle(color: Colors.greenAccent, fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.withValues(alpha: 0.2)),
                onPressed: () {
                  setState(() => _slid = !_slid);
                  _slid ? _slideCtrl.forward() : _slideCtrl.reverse();
                },
                icon: Icon(_slid ? Icons.arrow_back : Icons.arrow_forward, size: 16, color: Colors.greenAccent),
                label: Text(_slid ? 'Slide Out' : 'Slide In', style: const TextStyle(color: Colors.greenAccent)),
              ),
            ],
          ),
        ),

        // Rotate
        _Section(
          title: 'RotationTransition',
          badge: 'repeat()',
          child: Center(
            child: RotationTransition(
              turns: _rotateCtrl,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kBlue, kAmber],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.settings_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),

        // Pulse
        _Section(
          title: 'AnimatedBuilder  — Pulse',
          badge: 'repeat(reverse: true)',
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) {
                return Container(
                  width: 60 + (_pulseCtrl.value * 20),
                  height: 60 + (_pulseCtrl.value * 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.15 + _pulseCtrl.value * 0.25),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 28),
                );
              },
            ),
          ),
        ),

        // AnimatedContainer
        _Section(
          title: 'AnimatedContainer',
          badge: 'implicit animation',
          child: _AnimatedContainerDemo(),
        ),
      ],
    );
  }
}

class _AnimatedContainerDemo extends StatefulWidget {
  @override
  State<_AnimatedContainerDemo> createState() => _AnimatedContainerDemoState();
}

class _AnimatedContainerDemoState extends State<_AnimatedContainerDemo> {
  bool _toggled = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
          width: _toggled ? 200 : 100,
          height: _toggled ? 100 : 50,
          decoration: BoxDecoration(
            color: _toggled ? kAmber.withValues(alpha: 0.3) : kBlue.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(_toggled ? 50 : 12),
            border: Border.all(color: _toggled ? kAmber : kBlue),
          ),
          child: Center(
            child: Icon(
              _toggled ? Icons.star_rounded : Icons.circle,
              color: _toggled ? kAmber : kBlue,
              size: _toggled ? 36 : 20,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _toggled = !_toggled),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: Text(
              _toggled ? 'Reset' : 'Transform',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _StateTab extends StatefulWidget {
  const _StateTab();

  @override
  State<_StateTab> createState() => _StateTabState();
}

class _StateTabState extends State<_StateTab> {
  // Counter
  int _counter = 0;
  int _step = 1;

  // Todo list
  final List<String> _items = ['Learn Flutter', 'Build an app', 'Ship it!'];
  final _textCtrl = TextEditingController();

  // Random color generator
  Color _randomColor = kBlue;
  final _rng = Random();

  // Dart concepts
  String _futureResult = 'Tap to run Future';
  bool _futureLoading = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Counter
        _Section(
          title: 'setState  — Counter',
          badge: 'setState()',
          child: Column(
            children: [
              Text(
                '$_counter',
                style: TextStyle(
                  color: _counter >= 0 ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text('Step: $_step', style: const TextStyle(color: kSub, fontSize: 13)),
              const SizedBox(height: 4),
              Slider(
                value: _step.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_step',
                activeColor: kBlue,
                inactiveColor: kBorder,
                onChanged: (v) => setState(() => _step = v.toInt()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _counter -= _step),
                    icon: const Icon(Icons.remove_circle_rounded, color: Colors.redAccent, size: 40),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => setState(() => _counter = 0),
                    icon: const Icon(Icons.restart_alt_rounded, color: kSub, size: 36),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => setState(() => _counter += _step),
                    icon: const Icon(Icons.add_circle_rounded, color: Colors.greenAccent, size: 40),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List management
        _Section(
          title: 'Dynamic List',
          badge: 'List<T>',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Add a new item...',
                        hintStyle: const TextStyle(color: kSub, fontSize: 13),
                        filled: true,
                        fillColor: kBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: kBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: kBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_circle_rounded, color: kBlue, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedList(
                key: GlobalKey<AnimatedListState>(),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                initialItemCount: _items.length,
                itemBuilder: (ctx, i, animation) {
                  if (i >= _items.length) return const SizedBox.shrink();
                  return _buildListItem(_items[i], i, animation);
                },
              ),
            ],
          ),
        ),

        // Random color
        _Section(
          title: 'Random Color Generator',
          badge: 'dart:math',
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 80,
                decoration: BoxDecoration(
                  color: _randomColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _randomColor.withValues(alpha: 0.6)),
                ),
                child: Center(
                  child: Text(
                    '#${_randomColor.value.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                    style: TextStyle(color: _randomColor, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _randomColor),
                onPressed: () => setState(() {
                  _randomColor = Color.fromRGBO(
                    _rng.nextInt(200) + 55,
                    _rng.nextInt(200) + 55,
                    _rng.nextInt(200) + 55,
                    1,
                  );
                }),
                icon: const Icon(Icons.casino_rounded, color: Colors.white, size: 16),
                label: const Text('Generate', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),

        // Async / Future
        _Section(
          title: 'async / await  — Future',
          badge: 'Future<T>',
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '// Dart code running ↓',
                      style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Future<String> fetchData() async {\n  await Future.delayed(2.seconds);\n  return "Hello from the future!";\n}',
                      style: TextStyle(
                        color: Colors.lightGreenAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder),
                ),
                child: _futureLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: kBlue, strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Fetching...', style: TextStyle(color: kSub, fontSize: 13)),
                        ],
                      )
                    : Text(
                        _futureResult,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _futureResult.contains('Hello') ? Colors.greenAccent : kSub,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kBlue),
                onPressed: _futureLoading ? null : _runFuture,
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                label: const Text('Run Future', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListItem(String item, int index, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder),
          ),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline_rounded, color: kBlue, size: 18),
            title: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded, color: kSub, size: 16),
              onPressed: () => setState(() => _items.remove(item)),
            ),
          ),
        ),
      ),
    );
  }

  void _addItem() {
    final text = _textCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() => _items.add(text));
      _textCtrl.clear();
    }
  }

  Future<void> _runFuture() async {
    setState(() {
      _futureLoading = true;
      _futureResult = '';
    });
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _futureLoading = false;
      _futureResult = 'Hello from the future! 🎉';
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT TAB
// ─────────────────────────────────────────────────────────────────────────────
class _LayoutTab extends StatefulWidget {
  const _LayoutTab();

  @override
  State<_LayoutTab> createState() => _LayoutTabState();
}

class _LayoutTabState extends State<_LayoutTab> {
  MainAxisAlignment _mainAxis = MainAxisAlignment.start;
  CrossAxisAlignment _crossAxis = CrossAxisAlignment.start;
  bool _showRow = true;

  final _mainAxisOptions = MainAxisAlignment.values;
  final _crossAxisOptions = [
    CrossAxisAlignment.start,
    CrossAxisAlignment.center,
    CrossAxisAlignment.end,
    CrossAxisAlignment.stretch,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Row / Column explorer
        _Section(
          title: 'Row  &  Column Explorer',
          badge: 'interactive',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _tag(_showRow ? 'Row' : 'Column', kBlue),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showRow = !_showRow),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: kBorder,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Switch to ${_showRow ? 'Column' : 'Row'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('mainAxisAlignment', style: TextStyle(color: kSub, fontSize: 11)),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _mainAxisOptions.map((opt) {
                    final selected = opt == _mainAxis;
                    return GestureDetector(
                      onTap: () => setState(() => _mainAxis = opt),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected ? kBlue.withValues(alpha: 0.2) : kCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: selected ? kBlue : kBorder),
                        ),
                        child: Text(
                          opt.name,
                          style: TextStyle(
                            color: selected ? kBlue : kSub,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Text('crossAxisAlignment', style: TextStyle(color: kSub, fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                children: _crossAxisOptions.map((opt) {
                  final selected = opt == _crossAxis;
                  return GestureDetector(
                    onTap: () => setState(() => _crossAxis = opt),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected ? kAmber.withValues(alpha: 0.2) : kCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: selected ? kAmber : kBorder),
                      ),
                      child: Text(
                        opt.name,
                        style: TextStyle(
                          color: selected ? kAmber : kSub,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Container(
                height: _showRow ? 80 : 200,
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBorder, style: BorderStyle.solid),
                ),
                child: _showRow
                    ? Row(
                        mainAxisAlignment: _mainAxis,
                        crossAxisAlignment: _crossAxis,
                        children: _layoutBoxes(),
                      )
                    : Column(
                        mainAxisAlignment: _mainAxis,
                        crossAxisAlignment: _crossAxis,
                        children: _layoutBoxes(),
                      ),
              ),
            ],
          ),
        ),

        // Stack
        _Section(
          title: 'Stack  +  Positioned',
          badge: 'z-axis',
          child: SizedBox(
            height: 160,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: kBlue.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBlue),
                    ),
                    child: const Center(child: Text('Back', style: TextStyle(color: kBlue, fontSize: 12))),
                  ),
                ),
                Positioned(
                  top: 40,
                  left: 50,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAmber),
                    ),
                    child: const Center(child: Text('Middle', style: TextStyle(color: kAmber, fontSize: 12))),
                  ),
                ),
                Positioned(
                  top: 68,
                  left: 88,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6)),
                    ),
                    child: const Center(child: Text('Front', style: TextStyle(color: Colors.greenAccent, fontSize: 12))),
                  ),
                ),
                const Positioned(
                  bottom: 10,
                  right: 12,
                  child: Text('← layered with Positioned', style: TextStyle(color: kSub, fontSize: 10)),
                ),
              ],
            ),
          ),
        ),

        // GridView
        _Section(
          title: 'GridView',
          badge: 'crossAxisCount: 3',
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: List.generate(9, (i) {
              final colors = [kBlue, kAmber, Colors.greenAccent, Colors.pinkAccent, Colors.purpleAccent, Colors.orangeAccent];
              final c = colors[i % colors.length];
              return Container(
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(
                    'Grid\n${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          ),
        ),

        // Expanded / Flexible
        _Section(
          title: 'Expanded  &  Flexible',
          badge: 'flex ratios',
          child: Column(
            children: [
              const Text('Expanded: 1 : 2 : 1', style: TextStyle(color: kSub, fontSize: 11)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _flexBox('flex:1', kBlue, 50),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: _flexBox('flex:2', kAmber, 50),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _flexBox('flex:1', kBlue, 50),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Flexible vs Expanded', style: TextStyle(color: kSub, fontSize: 11)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: _flexBox('Flexible\n(shrinks)', Colors.pinkAccent, 60),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _flexBox('Expanded\n(fills)', Colors.purpleAccent, 60),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Wrap
        _Section(
          title: 'Wrap Widget',
          badge: 'auto-wraps',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Flutter', 'Dart', 'Firebase', 'Provider', 'BLoC', 'Riverpod',
              'GetX', 'Hive', 'SQLite', 'REST API', 'GraphQL', 'WebSockets',
            ].map((label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorder),
              ),
              child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            )).toList(),
          ),
        ),
      ],
    );
  }

  List<Widget> _layoutBoxes() {
    return [
      _miniBox('A', kBlue, 40),
      _miniBox('B', kAmber, 55),
      _miniBox('C', Colors.greenAccent, 35),
    ];
  }

  Widget _miniBox(String label, Color color, double size) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))),
    );
  }

  Widget _flexBox(String label, Color color, double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11)),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final String? badge;
  final Widget child;

  const _Section({required this.title, this.badge, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: kAmber.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(color: kAmber, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
