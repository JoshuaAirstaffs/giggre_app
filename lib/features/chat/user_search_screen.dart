import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/services/rating_service.dart' show RateeRole;
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/profile_tab_theme.dart';
import 'package:giggre_app/features/gig_shared/user_profile_screen.dart';
import 'package:giggre_app/helpers/snackbar_helper.dart';
import 'package:giggre_app/screens/chat/chat.dart';

import 'user_search_service.dart';

/// Opens the direct chat with [peerUid], creating it (as a message request
/// when the two haven't worked together) through startDirectChat. Shared by
/// search results and the profile screen's Message button.
Future<void> openDirectChat(
  BuildContext context, {
  required String peerUid,
  required String peerName,
}) async {
  try {
    final start = await UserSearchService.startChat(peerUid);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Chat(
          roomId: start.roomId,
          isGigChat: true,
          gigChatParams: GigChatParams(
            gigId: '',
            peerUid: peerUid,
            peerName: start.peerName.isNotEmpty ? start.peerName : peerName,
          ),
        ),
      ),
    );
  } on DirectChatException catch (e) {
    if (context.mounted) SnackbarHelper.showError(context, e.message);
  }
}

/// Find anyone on Giggre by name and message them. Opened from the Chats
/// header. People who've turned off "Let others find me" don't appear.
class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key, this.initialQuery = ''});

  /// Pre-fills and runs a search (the Chats list's "Find … on Giggre").
  final String initialQuery;

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  // Bumped per query so a slow earlier search can't overwrite a newer one
  int _generation = 0;

  List<UserSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  Set<String> _blocked = const {};
  String? _openingUid;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
    final q = widget.initialQuery.trim();
    if (q.isNotEmpty) {
      _controller.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(q);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadBlocked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final list = (snap.data()?['blockedUsers'] as List?) ?? const [];
      if (mounted) setState(() => _blocked = list.whereType<String>().toSet());
    } catch (e) {
      debugPrint('[UserSearch] blocked list: $e');
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(text));
  }

  Future<void> _run(String text) async {
    final query = text.trim();
    final generation = ++_generation;
    if (UserSearchService.normalize(query).length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
        _lastQuery = query;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await UserSearchService.search(
        query,
        excludeUids: _blocked,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        _lastQuery = query;
      });
    } catch (e) {
      debugPrint('[UserSearch] search failed: $e');
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search right now. Check your connection and try again.";
        _lastQuery = query;
      });
    }
  }

  Future<void> _message(UserSearchResult r) async {
    if (_openingUid != null) return;
    setState(() => _openingUid = r.uid);
    await openDirectChat(context, peerUid: r.uid, peerName: r.name);
    if (mounted) setState(() => _openingUid = null);
  }

  void _openProfile(UserSearchResult r) {
    UserProfileScreen.push(
      context,
      uid: r.uid,
      fallbackName: r.name,
      surface: 'user_search',
      role: r.mostlyHost ? RateeRole.host : RateeRole.worker,
      onMessage: () => openDirectChat(context, peerUid: r.uid, peerName: r.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.words,
          onChanged: _onChanged,
          onSubmitted: (t) {
            _debounce?.cancel();
            _run(t);
          },
          style: TextStyle(fontSize: 16, color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search people by name',
            hintStyle: TextStyle(color: tokens.textMuted),
            border: InputBorder.none,
          ),
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                    onPressed: () {
                      _controller.clear();
                      _run('');
                    },
                  ),
          ),
        ],
      ),
      body: _body(tokens),
    );
  }

  Widget _body(ProfileTabTokens tokens) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _note(tokens, Icons.wifi_off_rounded, _error!);
    if (UserSearchService.normalize(_lastQuery).length < 2) {
      return _note(
        tokens,
        Icons.person_search_rounded,
        'Find Gig Workers and Gig Hosts by name. If you haven’t worked '
        'together, your first message arrives as a request they can accept.',
      );
    }
    if (_results.isEmpty) {
      return _note(
        tokens,
        Icons.search_off_rounded,
        'No one named “$_lastQuery”. Check the spelling or try their first name.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, indent: 76, color: tokens.divider),
      itemBuilder: (_, i) => _ResultTile(
        result: _results[i],
        tokens: tokens,
        opening: _openingUid == _results[i].uid,
        onTap: () => _openProfile(_results[i]),
        onMessage: () => _message(_results[i]),
      ),
    );
  }

  Widget _note(ProfileTabTokens tokens, IconData icon, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.textMuted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.tokens,
    required this.opening,
    required this.onTap,
    required this.onMessage,
  });

  final UserSearchResult result;
  final ProfileTabTokens tokens;
  final bool opening;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  String? get _ratingLine {
    final parts = <String>[];
    if (result.workerRating != null) {
      parts.add('★ ${result.workerRating!.toStringAsFixed(1)} as Gig Worker');
    }
    if (result.hostRating != null) {
      parts.add('★ ${result.hostRating!.toStringAsFixed(1)} as Gig Host');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final photo = result.photoUrl;
    final ratingLine = _ratingLine;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: kBlue.withValues(alpha: 0.12),
              backgroundImage: (photo != null && photo.isNotEmpty)
                  ? CachedNetworkImageProvider(photo)
                  : null,
              child: (photo == null || photo.isEmpty)
                  ? const Icon(Icons.person_rounded, color: kBlue)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (result.isVerified) ...[
                        const SizedBox(width: 4),
                        Semantics(
                          label: 'Verified',
                          child: const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: kBlue,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ratingLine ?? 'No ratings yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
            opening
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Message ${result.name}',
                    onPressed: onMessage,
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: kBlue,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
