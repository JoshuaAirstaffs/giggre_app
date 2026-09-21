import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/rating_review.dart';
import '../../core/models/rating_summary.dart';
import '../../core/providers/current_user_provider.dart';
import '../../core/services/rating_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/worker_skills.dart';
import '../reports/models/report_content_type.dart';
import '../reports/report_service.dart';
import 'active_gig_theme.dart';
import 'profile_header.dart';
import 'profile_stats.dart';
import 'review_card.dart';
import 'user_profile_sheet.dart';
import 'work_history.dart';
import 'work_history_widgets.dart';

/// Full-screen profile for the other party on a gig — the same information as
/// [showUserProfileSheet] with room to breathe: the complete review history
/// instead of the first handful, and a rating breakdown by star.
///
/// Laid out as identity first (avatar left, everything that identifies them to
/// its right), then a dashboard of the three numbers that decide whether to
/// work with someone, then the reviews behind those numbers.
///
/// [role] says which reputation is being viewed. Workers and hosts keep
/// entirely separate ratings and reviews, so passing the wrong one shows the
/// other side's score. It also picks the accent: blue for a worker, gold for
/// a host, matching the two Active Gig screens.
class UserProfileScreen extends StatefulWidget {
  final String uid;
  final String fallbackName;

  /// Where this was opened from — recorded on any report filed here.
  final String surface;
  final RateeRole role;

  /// When set, a "relevant experience" section lists completed gigs whose
  /// required skills overlap with these.
  final List<String> matchSkillsForCompletedGigs;

  /// Called after this user is blocked, so the opening screen can react
  /// (the applicant list declines them, for instance).
  final Future<void> Function()? onBlocked;

  const UserProfileScreen({
    super.key,
    required this.uid,
    required this.fallbackName,
    required this.surface,
    required this.role,
    this.matchSkillsForCompletedGigs = const [],
    this.onBlocked,
  });

  static Future<void> push(
    BuildContext context, {
    required String uid,
    required String fallbackName,
    required String surface,
    required RateeRole role,
    List<String> matchSkillsForCompletedGigs = const [],
    Future<void> Function()? onBlocked,
  }) {
    if (uid.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          uid: uid,
          fallbackName: fallbackName,
          surface: surface,
          role: role,
          matchSkillsForCompletedGigs: matchSkillsForCompletedGigs,
          onBlocked: onBlocked,
        ),
      ),
    );
  }

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static const _reviewPageSize = 20;

  /// Master switch for "Relevant experience". False hides the section *and*
  /// skips the three completed-gig queries behind it, so turning it off costs
  /// no reads. Even when true the section only appears where the caller passes
  /// [UserProfileScreen.matchSkillsForCompletedGigs] — today just the host's
  /// applicant list.
  static const _showRelevantExperience = true;

  /// Master switch for the "Track record" card and the shared-history
  /// banner, and for the four queries behind them. Off skips the queries
  /// entirely.
  ///
  /// Those queries transfer whole gig documents, unlike the count()
  /// aggregates behind the headline gig count, so a host with hundreds of
  /// completed gigs is the expensive case — this is the dial to turn if the
  /// reads ever bite.
  static const _showWorkHistory = true;

  bool _loading = true;
  bool _loadingMore = false;
  bool _blocking = false;
  bool _blocked = false;

  /// False once a page comes back short, so "Load more" stops offering.
  bool _hasMoreReviews = true;

  /// Relevant experience shows [_relatedCollapsed] rows until this is set.
  bool _showAllRelated = false;

  Map<String, dynamic>? _data;
  RatingSummary _summary = RatingSummary.empty;
  List<RatingReview> _reviews = [];
  List<CompletedGigMatch> _matchedGigs = [];
  WorkHistoryStats _work = WorkHistoryStats.empty;

  /// Gigs completed for a worker, gigs posted for a host — the headline
  /// volume number for that side, filled by [_loadGigCount].
  int _gigCount = 0;

  final _scroll = ScrollController();

  /// Drives the collapsing top bar: 0 while the header is fully in view, 1
  /// once it has scrolled past.
  final _scrolled = ValueNotifier<double>(0);

  final _breakdownKey = GlobalKey();
  final _relatedKey = GlobalKey();
  final _reviewsKey = GlobalKey();

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isSelf => _currentUid == null || _currentUid == widget.uid;
  bool get _isWorker => widget.role == RateeRole.worker;

  ActiveGigAccent get _accent => profileAccent(widget.role);

  /// The accent legible against the page background — the solid brand colors
  /// are tuned for white surfaces and go muddy on the dark theme.
  Color _accentText(bool isDark) => isDark
      ? Color.lerp(_accent.solid, Colors.white, 0.42)!
      : _accent.onWhiteText;

  /// What the top bar fades into: the foot of the header gradient, so the two
  /// are the same colour where they meet.
  Color _barColor(bool isDark) =>
      profileHeaderGradient(widget.role, isDark).last;

  /// The bar sits on the header gradient at every scroll position, so it takes
  /// the header's foreground rather than the page's.
  ProfileHeaderPalette get _headerPalette =>
      ProfileHeaderPalette.of(widget.role);

  /// Brand blue as flat colour on a dark surface needs lifting; the gold and
  /// green already read on both.
  Color _statBlue(bool isDark) =>
      isDark ? Color.lerp(kBlue, Colors.white, 0.4)! : kBlue;
  Color _statGold(bool isDark) => isDark ? kGold : const Color(0xFFB06E00);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// Fades the top bar in over the 90px after the name has cleared it.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    _scrolled.value = ((_scroll.offset - 70) / 90).clamp(0.0, 1.0);
  }

  Future<void> _load() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final data = userDoc.data();

      final rest = await Future.wait([
        RatingService.recentReviews(
          userId: widget.uid,
          role: widget.role,
          limit: _reviewPageSize,
        ),
        _loadGigCount(data),
        !_showRelevantExperience || widget.matchSkillsForCompletedGigs.isEmpty
            ? Future.value(<CompletedGigMatch>[])
            : fetchSkillMatchedCompletedGigs(
                widget.uid,
                widget.matchSkillsForCompletedGigs,
              ),
        !_showWorkHistory
            ? Future.value(const <CompletedEngagement>[])
            : fetchCompletedEngagements(widget.uid, widget.role),
      ]);

      if (!mounted) return;
      final reviews = rest[0] as List<RatingReview>;
      setState(() {
        _data = data;
        _summary = RatingSummary.fromUserData(data, widget.role);
        _reviews = reviews;
        _gigCount = rest[1] as int;
        _matchedGigs = rest[2] as List<CompletedGigMatch>;
        _work = WorkHistoryStats.from(
          rest[3] as List<CompletedEngagement>,
          // Self-view has no counterpart to have worked with, and a logged
          // out reader has no history to share.
          viewerId: _isSelf ? null : _currentUid,
        );
        _hasMoreReviews = reviews.length == _reviewPageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[UserProfileScreen] load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Each side's headline volume: a worker is judged on gigs they finished, a
  /// host on gigs they put up — a host with three posted and none completed
  /// yet is new, not unreliable.
  Future<int> _loadGigCount(Map<String, dynamic>? data) => _isWorker
      ? countCompletedGigs(widget.uid, widget.role, data)
      : countPostedGigs(widget.uid);

  Future<void> _loadMoreReviews() async {
    if (_loadingMore || !_hasMoreReviews || _reviews.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await RatingService.recentReviews(
        userId: widget.uid,
        role: widget.role,
        limit: _reviewPageSize,
        startAfterRevealedAt: _reviews.last.revealedAt,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...next];
        _hasMoreReviews = next.length == _reviewPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('[UserProfileScreen] load more failed: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _block() async {
    final uid = _currentUid;
    if (uid == null) return;
    setState(() => _blocking = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'blockedUsers': FieldValue.arrayUnion([widget.uid]),
      });
      await widget.onBlocked?.call();
      if (!mounted) return;
      setState(() {
        _blocking = false;
        _blocked = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _blocking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not block: $e')));
    }
  }

  /// Scrolls a section into view — what the dashboard tiles do when tapped,
  /// so a number always leads to what produced it.
  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
      alignment: 0.05,
    );
  }

  String get _name => (_data?['name'] as String?)?.trim().isNotEmpty == true
      ? _data!['name'] as String
      : widget.fallbackName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = activeGigTextPrimary(isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The header runs under the status bar and the bar it collapses into is
      // the same colour, so both ends of the scroll want the same icons — dark
      // over the host's gold, light over the worker's navy.
      value: _headerPalette.overlay,
      child: Scaffold(
        backgroundColor: activeGigScreenBg(isDark),
        body: Stack(
          children: [
            RefreshIndicator(
              color: _accentText(isDark),
              // Clears the floating top bar, so the spinner is not drawn
              // underneath it.
              edgeOffset: MediaQuery.of(context).padding.top + 52,
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _header(isDark),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_blocked) ...[
                          _blockedNotice(isDark),
                          const SizedBox(height: 16),
                        ],
                        SharedHistoryBanner(stats: _work, isDark: isDark),
                        _dashboard(isDark),
                        _workHistory(isDark, onSurface),
                        _ratingBreakdown(isDark, onSurface),
                        _relatedGigs(isDark, onSurface),
                        _reviewsSection(isDark, onSurface),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _topBar(isDark),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  /// Floats over the hero, then fades into a solid bar carrying the name once
  /// the header has scrolled away — so Back, Report and Block stay reachable
  /// however far down the reviews you are.
  Widget _topBar(bool isDark) {
    final top = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<double>(
        valueListenable: _scrolled,
        builder: (context, t, _) {
          return Container(
            padding: EdgeInsets.fromLTRB(12, top + 6, 12, 8),
            decoration: BoxDecoration(
              color: _barColor(isDark).withValues(alpha: t),
              boxShadow: t == 0
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18 * t),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Row(
              children: [
                _barIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Opacity(
                    opacity: t,
                    child: Text(
                      _name,
                      style: TextStyle(
                        color: _headerPalette.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (!_isSelf) ...[
                  const SizedBox(width: 10),
                  _barIconButton(
                    icon: Icons.flag_outlined,
                    tooltip: 'Report',
                    onPressed: _blocking
                        ? null
                        : () => ReportService.show(
                            context,
                            contentType: ReportContentType.user,
                            contentId: widget.uid,
                            contentSnapshot: _data?['bio'] as String? ?? '',
                            contentAuthorId: widget.uid,
                            surface: widget.surface,
                          ),
                  ),
                  const SizedBox(width: 8),
                  _barIconButton(
                    icon: Icons.block_rounded,
                    tooltip: _blocked ? 'Blocked' : 'Block',
                    busy: _blocking,
                    tint: _blocked ? null : _headerPalette.unverified,
                    onPressed: _blocking || _blocked ? null : _block,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _barIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool busy = false,
    Color? tint,
  }) {
    final palette = _headerPalette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.chipFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.fg,
                    ),
                  )
                : Icon(
                    icon,
                    size: 17,
                    color: onPressed == null
                        ? palette.fg.withValues(alpha: 0.45)
                        : tint ?? palette.fg,
                  ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(bool isDark) {
    return ProfileHeader(
      name: _name,
      photoUrl: _data?['photoUrl'] as String? ?? '',
      avatarId: _data?['avatarId'] as String?,
      verification: _data?['isVerified'] as String? ?? 'unverified',
      allowUnverified: context
          .watch<CurrentUserProvider>()
          .allowGigAccessForUnverified,
      role: widget.role,
      summary: _summary,
      skills: workerSkillsFrom(_data),
      bio: _data?['bio'] as String? ?? '',
      memberSince: (_data?['createdAt'] as Timestamp?)?.toDate(),
      isDark: isDark,
      loading: _loading,
      // Clears the bar floating over it.
      topPadding: MediaQuery.of(context).padding.top + 62,
    );
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  /// The three numbers a profile is read for, as tappable tiles that each
  /// jump to the section behind them. Values count up once loaded, and the
  /// tiles stagger in left to right.
  Widget _dashboard(bool isDark) {
    final tiles = <Widget>[
      ProfileStatCard(
        isDark: isDark,
        icon: _isWorker ? Icons.task_alt_rounded : Icons.post_add_rounded,
        accent: _statBlue(isDark),
        label: _isWorker ? 'Gigs Completed' : 'Gigs Hosted',
        value: _loading ? null : _gigCount.toDouble(),
        // Only leads anywhere when there is a relevant-experience list to
        // lead to; the raw count has no section of its own.
        onTap: _matchedGigs.isEmpty ? null : () => _scrollTo(_relatedKey),
      ),
      ProfileStatCard(
        isDark: isDark,
        icon: Icons.reviews_rounded,
        accent: kActiveGigSuccessGreen,
        label: 'Ratings Given',
        value: _loading ? null : _summary.count.toDouble(),
        onTap: () => _scrollTo(_reviewsKey),
      ),
      ProfileStatCard(
        isDark: isDark,
        icon: Icons.star_rounded,
        accent: _statGold(isDark),
        label: 'Average Rating',
        value: _loading ? null : _summary.average,
        decimals: 1,
        valuePlaceholder: '—',
        valueSuffixIcon: Icons.star_rounded,
        valueColor: _summary.hasRatings ? _statGold(isDark) : null,
        onTap: _summary.hasRatings ? () => _scrollTo(_breakdownKey) : null,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ProfileStatRow(tiles: tiles),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  /// Recency and repeat hires — the two things a lifetime gig count cannot
  /// say. Hidden for someone with no completed gigs at all, where the
  /// dashboard's zero has already said it.
  Widget _workHistory(bool isDark, Color onSurface) {
    if (_loading || !_work.hasHistory) return const SizedBox.shrink();
    return _card(
      isDark: isDark,
      onSurface: onSurface,
      icon: Icons.trending_up_rounded,
      title: 'Track record',
      child: WorkHistoryBody(
        stats: _work,
        role: widget.role,
        accent: _accentText(isDark),
        isDark: isDark,
      ),
    );
  }

  /// Card shell every body section shares, so the page reads as one stack.
  Widget _card({
    required bool isDark,
    required Color onSurface,
    required IconData icon,
    required String title,
    String? trailingLabel,
    Key? anchor,
    required Widget child,
  }) {
    return ProfileEntrance(
      slideOffset: 20,
      child: Container(
        key: anchor,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: activeGigCardBg(isDark),
          borderRadius: BorderRadius.circular(kActiveGigCardRadius),
          border: Border.all(color: activeGigCardBorder(isDark)),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.26)
                  : const Color(0xFF17263D).withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              isDark: isDark,
              onSurface: onSurface,
              icon: icon,
              title: title,
              trailingLabel: trailingLabel,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required bool isDark,
    required Color onSurface,
    required IconData icon,
    required String title,
    String? trailingLabel,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _accent.solid.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 14, color: _accentText(isDark)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailingLabel != null)
          Text(
            trailingLabel,
            style: TextStyle(
              color: activeGigTextMuted(isDark),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  /// Star distribution. Only meaningful once there are ratings, and only
  /// covers ratings recorded through the ratings collection — the histogram
  /// is built by the aggregation trigger, not backfilled from anywhere.
  Widget _ratingBreakdown(bool isDark, Color onSurface) {
    if (!_summary.hasRatings) return const SizedBox.shrink();
    final average = _summary.average!;

    return _card(
      isDark: isDark,
      onSurface: onSurface,
      anchor: _breakdownKey,
      icon: Icons.insights_rounded,
      title: 'Rating breakdown',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedCountText(
                value: average,
                decimals: 1,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedStarRating(
                rating: average,
                size: 14,
                emptyColor: activeGigTrackBg(isDark),
              ),
              const SizedBox(height: 5),
              Text(
                '${_summary.count} '
                '${_summary.count == 1 ? 'rating' : 'ratings'}',
                style: TextStyle(
                  color: activeGigTextMuted(isDark),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  AnimatedRatingBar(
                    star: star,
                    count: _summary.histogram[star] ?? 0,
                    total: _summary.count,
                    isDark: isDark,
                    // Top bar first, so the distribution draws downward.
                    delay: Duration(milliseconds: 70 * (5 - star)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How many matched gigs show before "Show all" is offered.
  static const _relatedCollapsed = 3;

  Widget _relatedGigs(bool isDark, Color onSurface) {
    if (_matchedGigs.isEmpty) return const SizedBox.shrink();
    final total = _matchedGigs.length;
    final shown = _showAllRelated
        ? _matchedGigs
        : _matchedGigs.take(_relatedCollapsed).toList();

    return _card(
      isDark: isDark,
      onSurface: onSurface,
      anchor: _relatedKey,
      icon: Icons.verified_outlined,
      title: 'Relevant experience',
      trailingLabel: total == 1 ? '1 match' : '$total matches',
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: 18, color: activeGigDividerColor(isDark)),
            _relatedGigRow(shown[i], isDark, onSurface),
          ],
          if (total > _relatedCollapsed) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _showAllRelated = !_showAllRelated),
                style: TextButton.styleFrom(
                  foregroundColor: _accentText(isDark),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_showAllRelated ? 'Show less' : 'Show all $total'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One completed gig: what it was and when, then the skills it shares with
  /// the gig being staffed — the row has to answer "relevant how?" on its own.
  Widget _relatedGigRow(CompletedGigMatch gig, bool isDark, Color onSurface) {
    final muted = activeGigTextMuted(isDark);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.check_circle_rounded,
            color: kActiveGigSuccessGreen,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      gig.title.isNotEmpty ? gig.title : 'Untitled gig',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM y').format(gig.completedAt),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
              if (gig.gigType.isNotEmpty || gig.matchedSkills.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (gig.gigType.isNotEmpty)
                      Text(
                        gig.gigType,
                        style: TextStyle(
                          color: muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ...gig.matchedSkills.map(
                      (skill) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _accent.solid.withValues(
                            alpha: isDark ? 0.18 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _accent.solid.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          skill,
                          style: TextStyle(
                            color: _accentText(isDark),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Reviews sit straight on the page: each card carries its own surface, and
  /// nesting those inside another card flattens both.
  Widget _reviewsSection(bool isDark, Color onSurface) {
    return Column(
      key: _reviewsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
          child: _sectionHeader(
            isDark: isDark,
            onSurface: onSurface,
            icon: Icons.reviews_outlined,
            title: 'Reviews',
            trailingLabel: _reviews.isEmpty ? null : '${_reviews.length} shown',
          ),
        ),
        if (_loading)
          _reviewsPlaceholder(isDark)
        else if (_reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: activeGigCardBg(isDark),
              borderRadius: BorderRadius.circular(kActiveGigCardRadius),
              border: Border.all(color: activeGigCardBorder(isDark)),
            ),
            child: _emptyState(
              isDark,
              Icons.rate_review_outlined,
              // An aggregate can be ahead of the list: ratings stay hidden
              // until both sides have rated or the reveal window closes.
              _summary.hasRatings
                  ? 'No reviews to show yet — ratings appear here once both '
                        'sides have rated.'
                  : 'No reviews yet.',
            ),
          )
        else ...[
          for (var i = 0; i < _reviews.length; i++)
            ReviewCard(
              review: _reviews[i],
              isDark: isDark,
              onSurface: onSurface,
              // Only the first screenful is worth staggering; past that the
              // delay would just hold up a card the reader scrolled to.
              animationDelay: Duration(milliseconds: 70 * (i < 4 ? i : 0)),
            ),
          if (_hasMoreReviews)
            Center(
              child: TextButton.icon(
                onPressed: _loadingMore ? null : _loadMoreReviews,
                style: TextButton.styleFrom(
                  foregroundColor: _accentText(isDark),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: _accent.solid.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                icon: _loadingMore
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accentText(isDark),
                        ),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(_loadingMore ? 'Loading…' : 'Load more'),
              ),
            ),
        ],
      ],
    );
  }

  /// Shaped like the cards it will become, so the list does not jump when the
  /// reviews land.
  Widget _reviewsPlaceholder(bool isDark) => Column(
    children: [
      for (var i = 0; i < 2; i++)
        Container(
          height: 104,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: activeGigCardBg(isDark).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: activeGigCardBorder(isDark)),
          ),
        ),
    ],
  );

  Widget _emptyState(bool isDark, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: activeGigTextDisabled(isDark)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: activeGigTextMuted(isDark),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _blockedNotice(bool isDark) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: kActiveGigDestructiveRed.withValues(alpha: isDark ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: activeGigDestructiveBorder(isDark)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.block_rounded,
          color: kActiveGigDestructiveRed,
          size: 16,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'You have blocked this user.',
            style: TextStyle(
              color: kActiveGigDestructiveRed,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
