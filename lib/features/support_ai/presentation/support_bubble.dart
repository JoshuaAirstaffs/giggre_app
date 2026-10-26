// Giggre AI support — floating chat bubble + chat sheet (v1, text only).
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/support_chat_service.dart';
import '../services/support_chat_store.dart';

enum GiggreMode { worker, host }

typedef TalkToPersonCallback = Future<void> Function(
    List<SupportMessage> transcript);

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
  // The bubble floats above the navigator, so hide it while its own sheet
  // is open instead of drawing it over the chat.
  bool _chatOpen = false;

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
    final sheetContext = widget.navigatorKey?.currentContext ?? context;
    setState(() => _chatOpen = true);
    await showModalBottomSheet(
      context: sheetContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupportChatSheet(
        uid: uid,
        mode: widget.mode,
        gradient: _gradient,
        onTalkToPerson: widget.onTalkToPerson,
      ),
    );
    if (mounted) setState(() => _chatOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!widget.visible || uid == null || _chatOpen) {
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    _pos ??= Offset(screen.width - _size - 12, screen.height - _size - 140);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: _pos!.dx,
      top: _pos!.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = _pos! + d.delta),
        onPanEnd: (_) => _snapToEdge(screen),
        onTap: () => _openChat(uid),
        child: Semantics(
          button: true,
          label: 'Open Giggre Help',
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _gradient.last.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat sheet
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
        SupportMessage(role: 'assistant', text: reply.answer),
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
        _error = 'Giggre Help couldn’t answer. Try again, or talk to a person.';
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, _) => Container(
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: const BoxDecoration(
          color: _Palette.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
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
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: widget.gradient),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white54,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Giggre Help',
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
                  icon: const Icon(Icons.support_agent_rounded,
                      color: Colors.white),
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
            'Ask anything about using Giggre.',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          if (i == _messages.length) return _bubble('…', isUser: false);
          final m = _messages[i];
          return _bubble(m.text, isUser: m.isUser);
        },
      );

  Widget _bubble(String text, {required bool isUser}) => Align(
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
          child: SelectableText(
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
      text = 'You’ve reached the limit for this hour. '
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

  Widget _inputBar() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                onPressed:
                    (_waiting || _limited) ? null : () => _send(_input.text),
                icon: Icon(Icons.send_rounded, color: widget.gradient.first),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      );
}
