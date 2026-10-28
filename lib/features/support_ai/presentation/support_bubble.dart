// Giggre AI support — floating chat bubble + chat popover (v1, text only).
//
// Usage (once, above your navigator):
//   MaterialApp(
//     builder: (context, child) => Stack(children: [
//       child!,
//       SupportBubble(
//         mode: currentMode,
//         visible: !hideBubble,
//         onTalkToPerson: (transcript) => createSupportTicket(transcript),
//       ),
//     ]),
//   );

import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/support_chat_service.dart';
import '../services/support_chat_store.dart';
import 'support_destinations.dart';

enum GiggreMode { worker, host }

typedef TalkToPersonCallback =
    Future<void> Function(List<SupportMessage> transcript);

class _Palette {
  static const workerGradient = [Color(0xFF2B6FB5), Color(0xFF1F4D80)];
  static const hostGradient = [Color(0xFFF0A830), Color(0xFFD88810)];
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E9F0);
  static const background = Color(0xFFF4F6FA);
  static const textPrimary = Color(0xFF1A202C);
  static const textSecondary = Color(0xFF4A5568);
  static const radius = 16.0;
}

// ---------------------------------------------------------------------------
// Floating bubble
// ---------------------------------------------------------------------------

class SupportBubble extends StatefulWidget {
  const SupportBubble({
    super.key,
    required this.mode,
    required this.onTalkToPerson,
    this.visible = true,
    this.navigatorKey,
  });

  final GiggreMode mode;
  final TalkToPersonCallback onTalkToPerson;

  /// The app's navigator. Needed when the bubble sits in MaterialApp.builder,
  /// above the Navigator, where its own context can't open the chat sheet.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Set false on screens where the bubble gets in the way
  /// (calls, check-in, camera, the support ticket chat itself).
  final bool visible;

  @override
  State<SupportBubble> createState() => _SupportBubbleState();
}

class _SupportBubbleState extends State<SupportBubble> {
  static const _size = 56.0;
  Offset? _pos;
  // The chat opens as a popover pointing at the bubble. The bubble floats
  // above the navigator, so it stays on top of it and tapping it closes it.
  Route<void>? _chatRoute;

  bool get _chatOpen => _chatRoute != null;

  List<Color> get _gradient => widget.mode == GiggreMode.worker
      ? _Palette.workerGradient
      : _Palette.hostGradient;

  void _snapToEdge(Size screen) {
    final x = _pos!.dx + _size / 2 < screen.width / 2
        ? 12.0
        : screen.width - _size - 12;
    final y = _pos!.dy.clamp(80.0, screen.height - _size - 120);
    setState(() => _pos = Offset(x, y));
  }

  Future<void> _openChat(String uid) async {
    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.of(context);
    final anchor = _pos!;
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black26,
      barrierLabel: 'Close Gab',
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, animation, _) => _ChatPopover(
        anchor: anchor,
        anchorSize: _size,
        gradient: _gradient,
        animation: animation,
        child: SupportChatSheet(
          uid: uid,
          mode: widget.mode,
          gradient: _gradient,
          onTalkToPerson: widget.onTalkToPerson,
        ),
      ),
    );
    setState(() => _chatRoute = route);
    await navigator.push(route);
    if (mounted) setState(() => _chatRoute = null);
  }

  void _closeChat() {
    final route = _chatRoute;
    if (route == null) return;
    if (route.isCurrent) {
      route.navigator?.pop();
    } else if (route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!widget.visible || uid == null) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final screen = media.size;
    _pos ??= Offset(screen.width - _size - 12, screen.height - _size - 140);
    // While chatting, keep the bubble (and the popover's tail) above the
    // keyboard. The popover uses the same formula.
    final top = _chatOpen
        ? _ChatPopover.bubbleTop(_pos!.dy, _size, media)
        : _pos!.dy;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: _pos!.dx,
      top: top,
      child: GestureDetector(
        // Not movable while the popover points at it.
        onPanUpdate: _chatOpen
            ? null
            : (d) => setState(() => _pos = _pos! + d.delta),
        onPanEnd: _chatOpen ? null : (_) => _snapToEdge(screen),
        onTap: () => _chatOpen ? _closeChat() : _openChat(uid),
        child: Semantics(
          button: true,
          label: _chatOpen ? 'Close Gab' : 'Open Gab',
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // gab.png has a white background, so the bubble is white too
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: _gradient.last.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              // The robot fills ~70% of the image; zoom in a little so it
              // reads at bubble size without clipping its ears.
              child: Transform.scale(
                scale: 1.15,
                child: Image.asset(
                  'assets/images/gab.png',
                  fit: BoxFit.cover,
                  // Source is 1024px; decode small for a 56px bubble.
                  cacheWidth: 256,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat popover: the chat card plus a tail pointing at the bubble
// ---------------------------------------------------------------------------

class _ChatPopover extends StatelessWidget {
  const _ChatPopover({
    required this.anchor,
    required this.anchorSize,
    required this.gradient,
    required this.animation,
    required this.child,
  });

  /// The bubble's top-left (before any keyboard lift) and size.
  final Offset anchor;
  final double anchorSize;
  final List<Color> gradient;
  final Animation<double> animation;
  final Widget child;

  static const _margin = 12.0;
  static const _gap = 6.0;
  static const _tail = 10.0;
  static const _maxWidth = 420.0;
  static const _maxHeight = 560.0;

  /// The bubble's top while the chat is open: moved up above the keyboard.
  static double bubbleTop(double top, double size, MediaQueryData media) =>
      math.max(
        0.0,
        math.min(
          top,
          media.size.height - media.viewInsets.bottom - size - _margin,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final top = bubbleTop(anchor.dy, anchorSize, media);
    final centerX = anchor.dx + anchorSize / 2;

    final minY = media.padding.top + _margin;
    final maxY =
        screen.height -
        math.max(media.viewInsets.bottom, media.padding.bottom) -
        _margin;

    // Open on the side of the bubble with more room (with the keyboard up,
    // that's above it).
    final roomAbove = top - _gap - _tail - minY;
    final roomBelow = maxY - (top + anchorSize + _gap + _tail);
    final above = roomAbove >= roomBelow;
    final height = math.max(
      0.0,
      math.min(_maxHeight, above ? roomAbove : roomBelow),
    );
    final cardTop = above
        ? top - _gap - _tail - height
        : top + anchorSize + _gap + _tail;
    final cardBottom = cardTop + height;

    final width = math.min(screen.width - _margin * 2, _maxWidth);
    final left = math.max(
      _margin,
      math.min(centerX - width / 2, screen.width - _margin - width),
    );
    final tailX = math.max(24.0, math.min(centerX - left, width - 24.0));
    // Above: the tail hangs off the white input bar. Below: off the header.
    final tailColor = above
        ? _Palette.surface
        : Color.lerp(gradient.first, gradient.last, tailX / width)!;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: above ? cardTop : cardTop - _tail,
          height: cardBottom - cardTop + _tail,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              // Grow out of the bubble.
              alignment: Alignment(tailX / width * 2 - 1, above ? 1 : -1),
              scale: Tween(begin: 0.6, end: 1.0).animate(curved),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: above ? 0 : _tail,
                    bottom: above ? _tail : 0,
                    child: Material(
                      color: _Palette.background,
                      elevation: 12,
                      shadowColor: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    ),
                  ),
                  // Painted after the card so its shadow doesn't cover it;
                  // overlaps the card by 1px to hide the seam.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: above ? null : 0,
                    bottom: above ? 0 : null,
                    height: _tail + 1,
                    child: CustomPaint(
                      painter: _TailPainter(
                        x: tailX,
                        pointsUp: !above,
                        color: tailColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({
    required this.x,
    required this.pointsUp,
    required this.color,
  });

  final double x;
  final bool pointsUp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const halfWidth = 11.0;
    final tipY = pointsUp ? 0.0 : size.height;
    final baseY = pointsUp ? size.height : 0.0;
    final path = Path()
      ..moveTo(x - halfWidth, baseY)
      ..lineTo(x, tipY)
      ..lineTo(x + halfWidth, baseY)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.x != x || old.pointsUp != pointsUp || old.color != color;
}

// ---------------------------------------------------------------------------
// Chat (shown inside the popover)
// ---------------------------------------------------------------------------

class SupportChatSheet extends StatefulWidget {
  const SupportChatSheet({
    super.key,
    required this.uid,
    required this.mode,
    required this.gradient,
    required this.onTalkToPerson,
  });

  final String uid;
  final GiggreMode mode;
  final List<Color> gradient;
  final TalkToPersonCallback onTalkToPerson;

  @override
  State<SupportChatSheet> createState() => _SupportChatSheetState();
}

class _SupportChatSheetState extends State<SupportChatSheet> {
  final _service = SupportChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<SupportMessage> _messages = [];
  DateTime? _lastActivity;
  bool _loading = true;
  bool _waiting = false;
  bool _offerHuman = false;
  int? _remaining;
  DateTime? _limitResetAt;
  String? _error;

  bool get _limited =>
      _limitResetAt != null && DateTime.now().isBefore(_limitResetAt!);

  List<String> get _suggestions => widget.mode == GiggreMode.worker
      ? const [
          'How do I apply to a gig?',
          'How does check-in work?',
          'How do I get paid?',
        ]
      : const [
          'How do I post a gig?',
          'How do I choose a worker?',
          'Can I cancel a gig?',
        ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await SupportChatStore.load(widget.uid);
    if (!mounted) return;
    setState(() {
      _messages = saved;
      _lastActivity = saved.isEmpty ? null : DateTime.now();
      _loading = false;
    });
    _scrollDown();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _waiting || _limited) return;

    // Chat left open and idle for an hour: start fresh.
    if (_lastActivity != null &&
        DateTime.now().difference(_lastActivity!) >=
            SupportChatStore.idleTimeout) {
      _messages = [];
      _offerHuman = false;
      await SupportChatStore.clear(widget.uid);
    }

    final history = List<SupportMessage>.of(_messages);
    final userMsg = SupportMessage(role: 'user', text: text);

    setState(() {
      _messages = [...history, userMsg];
      _waiting = true;
      _error = null;
      _input.clear();
    });
    _scrollDown();

    try {
      final reply = await _service.ask(
        message: text,
        history: history,
        mode: widget.mode.name,
      );
      if (!mounted) return;
      final updated = [
        ..._messages,
        SupportMessage(
          role: 'assistant',
          text: reply.answer,
          actions: reply.actions,
        ),
      ];
      setState(() {
        _messages = updated;
        _offerHuman = _offerHuman || reply.escalate;
        _remaining = reply.remaining;
        _limitResetAt = reply.remaining <= 0 ? reply.resetAt : null;
      });
      _lastActivity = DateTime.now();
      await SupportChatStore.save(widget.uid, updated);
    } on SupportLimitReached catch (e) {
      _restoreUnsent(text, history);
      setState(() {
        _limitResetAt = e.resetAt;
        _remaining = 0;
        _offerHuman = true;
      });
    } on SupportUnavailable {
      _restoreUnsent(text, history);
      setState(() {
        _error = 'Gab couldn’t answer. Try again, or talk to a person.';
        _offerHuman = true;
      });
    } finally {
      if (mounted) setState(() => _waiting = false);
      _scrollDown();
    }
  }

  // Remove the message that didn't get an answer and put it back in the box,
  // so it isn't lost and doesn't end up in the history sent to the AI.
  void _restoreUnsent(String text, List<SupportMessage> history) {
    if (!mounted) return;
    setState(() {
      _messages = history;
      _input.text = text;
    });
  }

  Future<void> _talkToPerson() async {
    final transcript = List<SupportMessage>.of(_messages);
    Navigator.of(context).pop();
    await widget.onTalkToPerson(transcript);
  }

  // Close the chat and open the screen Gab pointed to, on the same navigator.
  void _openDestination(SupportDestination destination) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (context) => destination.builder(context, widget.mode),
      ),
    );
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Sized and kept above the keyboard by _ChatPopover.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? _emptyState()
              : _messageList(),
        ),
        if (_offerHuman) _humanButton(),
        _statusLine(),
        _inputBar(),
      ],
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: widget.gradient),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gab',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'AI assistant. A person can take over anytime.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _talkToPerson,
              icon: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
              ),
              tooltip: 'Talk to a person',
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Close',
            ),
          ],
        ),
      ],
    ),
  );

  Widget _emptyState() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Hi! I’m Gab, Giggre’s AI assistant. Ask me how to do something and I’ll guide you through the steps. For now I can only explain things. I can’t post gigs or make changes to your account, but I’m still learning and getting better.',
        style: TextStyle(fontSize: 15, color: _Palette.textSecondary),
      ),
      const SizedBox(height: 16),
      ..._suggestions.map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(_Palette.radius),
            onTap: _limited ? null : () => _send(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _Palette.surface,
                border: Border.all(color: _Palette.border),
                borderRadius: BorderRadius.circular(_Palette.radius),
              ),
              child: Text(s, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _messageList() => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.all(16),
    itemCount: _messages.length + (_waiting ? 1 : 0),
    itemBuilder: (_, i) {
      if (i == _messages.length) {
        return _bubble('', isUser: false, child: const _ThinkingIndicator());
      }
      final m = _messages[i];
      final destinations = m.actions
          .map(SupportDestination.byId)
          .whereType<SupportDestination>()
          .toList();
      if (destinations.isEmpty) return _bubble(m.text, isUser: m.isUser);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bubble(m.text, isUser: m.isUser),
          ...destinations.map(_destinationButton),
        ],
      );
    },
  );

  Widget _destinationButton(SupportDestination destination) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton.icon(
      onPressed: () => _openDestination(destination),
      icon: Icon(destination.icon, size: 18),
      label: Text(destination.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.gradient.last,
        backgroundColor: _Palette.surface,
        side: BorderSide(color: widget.gradient.first),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Palette.radius),
        ),
      ),
    ),
  );

  Widget _bubble(String text, {required bool isUser, Widget? child}) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        gradient: isUser ? LinearGradient(colors: widget.gradient) : null,
        color: isUser ? null : _Palette.surface,
        border: isUser ? null : Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(_Palette.radius),
      ),
      child:
          child ??
          SelectableText(
            text,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: isUser ? Colors.white : _Palette.textPrimary,
            ),
          ),
    ),
  );

  Widget _humanButton() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: OutlinedButton.icon(
      onPressed: _talkToPerson,
      icon: const Icon(Icons.support_agent_rounded),
      label: const Text('Talk to a person'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_Palette.radius),
        ),
      ),
    ),
  );

  // Limit reached, error, or "few questions left" — one line above the input.
  Widget _statusLine() {
    String? text;
    if (_limited) {
      final time = TimeOfDay.fromDateTime(_limitResetAt!).format(context);
      text =
          'You’ve reached the limit for this hour. '
          'You can ask again at $time, or talk to a person.';
    } else if (_error != null) {
      text = _error;
    } else if (_remaining != null && _remaining! > 0 && _remaining! <= 3) {
      text = _remaining == 1
          ? '1 question left this hour'
          : '$_remaining questions left this hour';
    }
    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: _Palette.textSecondary),
      ),
    );
  }

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
    decoration: const BoxDecoration(
      color: _Palette.surface,
      border: Border(top: BorderSide(color: _Palette.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            enabled: !_limited,
            minLines: 1,
            maxLines: 4,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: _send,
            decoration: const InputDecoration(
              hintText: 'Type your question',
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
        IconButton(
          onPressed: (_waiting || _limited) ? null : () => _send(_input.text),
          icon: Icon(Icons.send_rounded, color: widget.gradient.first),
          tooltip: 'Send',
        ),
      ],
    ),
  );
}

/// "Thinking..." shown while Gab replies; each dot hops in turn.
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  static const _dots = 3;
  static const _hop = 4.0;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Each dot rises and falls over its own slice of the cycle, then rests
  double _offset(int i) {
    final t = (_controller.value - i * 0.15) % 1.0;
    if (t > 0.4) return 0;
    return -_hop * math.sin(t / 0.4 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 14.5,
      height: 1.4,
      color: _Palette.textSecondary,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('Thinking', style: style),
          for (var i = 0; i < _dots; i++)
            Transform.translate(
              offset: Offset(0, _offset(i)),
              child: const Text('.', style: style),
            ),
        ],
      ),
    );
  }
}
