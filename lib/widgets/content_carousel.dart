import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../core/providers/current_user_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_orientation.dart';
import '../features/auth/presentation/welcome_screen.dart'
    show welcomeRouteObserver;

// ─────────────────────────────────────────────
//  Content Carousel — Home, Gig Worker and Gig Host (slides from giggre-admin)
// ─────────────────────────────────────────────
class _CarouselItem {
  /// Firestore doc id: how the last slide shown is remembered, so reordering
  /// or adding slides in giggre-admin doesn't move people to another one.
  final String id;
  final String picture;
  final int sortNumber;

  /// Optional MP4 (set in giggre-admin's Content Management). `picture`, if
  /// also set, is shown as the video's cover while it loads.
  final String video;

  /// ISO country codes (e.g. PH, US) this slide is limited to, set in
  /// giggre-admin. Empty — including slides saved before the field existed —
  /// means every country.
  final List<String> countries;

  /// Video slides only (set in giggre-admin): the role button — 'worker' or
  /// 'host' — that jumps the carousel to this video and plays it from the
  /// start. Empty for images and older videos. Every slide still shows in the
  /// normal rotation either way.
  final String audience;

  const _CarouselItem({
    required this.id,
    required this.picture,
    required this.sortNumber,
    this.video = '',
    this.countries = const [],
    this.audience = '',
  });

  bool get hasVideo => video.isNotEmpty;

  /// Country used when neither the user's location nor a PHP currency says
  /// otherwise (location off, permission denied, lookup failed) — they see
  /// the US slides.
  static const defaultCountry = 'US';

  bool showsIn(String? countryCode) =>
      countries.isEmpty ||
      countries.contains((countryCode ?? defaultCountry).toUpperCase());

  factory _CarouselItem.fromMap(String id, Map<String, dynamic> data) {
    final rawCountries = data['countries'];
    return _CarouselItem(
      id: id,
      picture: data['picture'] as String? ?? '',
      sortNumber: (data['sortNumber'] as num?)?.toInt() ?? 0,
      video: data['video'] as String? ?? '',
      countries: rawCountries is List
          ? rawCountries
                .whereType<String>()
                .map((c) => c.toUpperCase())
                .toList()
          : const [],
      audience: switch (data['audience']) {
        'worker' => 'worker',
        'host' => 'host',
        _ => '',
      },
    );
  }
}

/// The app's three carousels, each its own `app_content/{section}` doc of
/// slides managed in giggre-admin (Content Management → Carousel): Home, Gig
/// Worker and Gig Host. Same slides format and behaviour everywhere; the
/// options below set what differs.
class ContentCarousel extends StatefulWidget {
  static const homeSection = 'carousel_items';
  static const workerSection = 'worker_carousel_items';
  static const hostSection = 'host_carousel_items';

  /// Height of the dashboards' banner carousels (giggre-admin previews and
  /// advises slide sizes for exactly this).
  static const bannerHeight = 140.0;

  const ContentCarousel({
    super.key,
    this.section = homeSection,
    this.height,
    this.soundOnFirstPlay = true,
    this.active = true,
    this.padding = EdgeInsets.zero,
    this.showLoading = true,
  });

  /// `app_content` doc holding the slides.
  final String section;

  /// Null: 16:9 (Home). Otherwise a banner this tall; slides are cropped to
  /// fill it.
  final double? height;

  /// Home: a video's first play on the device has sound. The dashboards
  /// (screens people keep open) always start muted. Either way, once the
  /// viewer taps mute/unmute, later videos follow that choice.
  final bool soundOnFirstPlay;

  /// False while the screen holding the carousel isn't the one showing (a
  /// dashboard on another tab of its shell): videos stop, nothing advances.
  final bool active;

  /// Around the carousel, only while it has slides — so an empty or hidden
  /// carousel takes no space at all.
  final EdgeInsetsGeometry padding;

  /// Home shows a loading box; the dashboards show nothing until slides
  /// arrive (most of the time there are none, and the box would just flash).
  final bool showLoading;

  @override
  State<ContentCarousel> createState() => ContentCarouselState();
}

class ContentCarouselState extends State<ContentCarousel> with RouteAware {
  // The last slide shown per carousel, so it reopens on it: kept in memory
  // for screens that rebuild (switching roles) and saved for the next app
  // launch. Home keeps its original prefs key.
  static final Map<String, String?> _lastSlideIds = {};
  static final Set<String> _lastSlideLoaded = {};
  String get _lastSlideKey => widget.section == ContentCarousel.homeSection
      ? 'home_carousel_last_slide'
      : '${widget.section}_last_slide';
  String? get _lastSlideId => _lastSlideIds[widget.section];
  // Set on the carousel's first build, once the slides for this country
  // are known: where it opens.
  int? _initialPage;

  int _current = 0;
  // Another screen is on top of Home — the carousel stays mounted under it,
  // so videos must stop and auto-slide must not land on (and start) one.
  bool _covered = false;
  // False once Home is scrolled so that less than half the carousel shows
  bool _inView = true;
  PageRoute<void>? _subscribedRoute;
  List<_CarouselItem> _slides = [];
  bool _loading = true;
  // Sound of the video playing now. Each play sets it fresh: a video's first
  // play on this device has sound, every replay starts muted (see
  // _PlayedVideos). The mute button switches it either way, and the choice
  // carries on if the video is paused or covered and then resumes.
  bool _muted = true;
  // Once the worker taps mute/unmute, later videos follow that choice
  // instead of the first-play/replay rule (null = they haven't chosen).
  bool? _chosenMuted;
  final _playedVideos = _PlayedVideos();
  final CarouselSliderController _carousel = CarouselSliderController();
  final _videos = _CarouselVideoCache();
  // Slide whose video already advanced the carousel — two copies of a slide
  // can be built at once mid-swipe, and only one may move it on.
  int? _advancedFrom;
  // Bumped per slide id to make that video start over (see playForRole)
  final Map<String, int> _replays = {};
  // Slide a role button just switched to: its video continues from where it
  // stopped instead of starting over (see playForRole). Used once.
  String? _resumeId;

  @override
  void initState() {
    super.initState();
    _fetchSlides();
    // Slides can be limited by country; make sure it gets detected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CurrentUserProvider>().ensureCountryCode();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // welcomeRouteObserver is the app's one RouteObserver (main.dart's
    // navigatorObservers), not specific to WelcomeScreen.
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) welcomeRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      welcomeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() => setState(() => _covered = false);

  @override
  void dispose() {
    welcomeRouteObserver.unsubscribe(this);
    _videos.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // Reported after a short delay, so the carousel may be gone by now
    if (!mounted) return;
    final inView = info.visibleFraction >= 0.5;
    if (inView != _inView) setState(() => _inView = inView);
  }

  void _advanceFrom(int index) {
    if (index != _current || _advancedFrom == index) return;
    _advancedFrom = index;
    _carousel.nextPage();
  }

  // Pull-to-refresh: new slides without remounting, so a playing video and
  // the current position carry on
  Future<void> refreshSlides() => _fetchSlides();

  // Only the slides meant for this user's country. Until a location is
  // detected, a stored PHP currency still means the Philippines (USD is
  // also the provider's unset default, so it can't say US); otherwise US.
  // Filtered at build time rather than at fetch time so a country detected
  // after loading still applies.
  static String? _countryOf(CurrentUserProvider p) =>
      p.countryCode ?? (p.currencyCode == 'PHP' ? 'PH' : null);

  List<_CarouselItem> _slidesFor(String? countryCode) =>
      _slides.where((s) => s.showsIn(countryCode)).toList();

  /// Highlighting the Gig Worker / Gig Host button: jump to that role's video
  /// (set in giggre-admin). Switching from the other role's video continues it
  /// from where it stopped (from the start if it never played or already
  /// ended); tapping the role whose video is showing starts it over. When it
  /// ends the carousel moves on as usual. No video for the role in this
  /// country: nothing changes.
  void playForRole(String role) {
    if (_loading || _initialPage == null) return;
    final slides = _slidesFor(_countryOf(context.read<CurrentUserProvider>()));
    final index = slides.indexWhere((s) => s.hasVideo && s.audience == role);
    if (index < 0) return;
    final slide = slides[index];
    setState(() {
      if (index == _current) {
        _replays[slide.id] = (_replays[slide.id] ?? 0) + 1;
      } else {
        _resumeId = slide.id;
      }
      _advancedFrom = null;
    });
    if (index != _current) {
      // Becoming the current slide starts its video from the beginning
      if (MediaQuery.of(context).disableAnimations) {
        _carousel.jumpToPage(index);
      } else {
        _carousel.animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  // A video slide calls this as it starts playing from the beginning, and
  // gets back whether to start muted
  bool _onPlayStart(String videoUrl) {
    final replay = _playedVideos.contains(videoUrl);
    _playedVideos.add(videoUrl);
    final startMuted = _chosenMuted ?? (replay || !widget.soundOnFirstPlay);
    if (_muted != startMuted && mounted) setState(() => _muted = startMuted);
    return startMuted;
  }

  // A video slide calls this as it continues from where it stopped (role
  // switch); gets back whether to play muted. Keeps the viewer's mute choice,
  // otherwise the sound the video had when it was left.
  bool _onResume(String slideId, bool wasMuted) {
    if (_resumeId == slideId) _resumeId = null;
    final m = _chosenMuted ?? wasMuted;
    if (_muted != m && mounted) setState(() => _muted = m);
    return m;
  }

  Future<void> _loadLastSlide() async {
    final section = widget.section;
    if (!_lastSlideLoaded.add(section)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastSlideIds[section] ??= prefs.getString(_lastSlideKey);
    } catch (e) {
      debugPrint('[Carousel] last slide: $e');
    }
  }

  void _rememberSlide(_CarouselItem slide) {
    if (_lastSlideId == slide.id) return;
    _lastSlideIds[widget.section] = slide.id;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_lastSlideKey, slide.id))
        .catchError((Object e) {
          debugPrint('[Carousel] save last slide: $e');
          return false;
        });
  }

  Future<void> _fetchSlides() async {
    // Before any slide can play, so a first play is never mistaken
    await _playedVideos.load();
    // Before the slides show, so the carousel opens on the right one
    await _loadLastSlide();
    try {
      final section = FirebaseFirestore.instance
          .collection('app_content')
          .doc(widget.section);

      // The admin can hide the whole carousel (CMS "Shown in app" switch)
      final sectionSnap = await section.get();
      if (sectionSnap.data()?['hidden'] == true) {
        if (mounted) {
          setState(() {
            _slides = [];
            _loading = false;
          });
        }
        return;
      }

      final snapshot = await section.collection('items').get();

      final items =
          snapshot.docs
              .map((doc) => _CarouselItem.fromMap(doc.id, doc.data()))
              // A slide shows with an image, a video, or both
              .where(
                (item) =>
                    item.sortNumber != 0 &&
                    (item.picture.isNotEmpty || item.hasVideo),
              )
              .toList()
            ..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));

      if (mounted) {
        setState(() {
          _slides = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      if (!widget.showLoading) return const SizedBox.shrink();
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _SlideBox(
          height: widget.height,
          child: Container(
            color: Theme.of(context).cardColor,
            child: const Center(
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    // This user's country's slides (see _countryOf)
    final countryCode = context.select<CurrentUserProvider, String?>(
      _countryOf,
    );
    final slides = _slidesFor(countryCode);

    if (slides.isEmpty) return const SizedBox.shrink();

    // First build with slides: open on the last one shown (if it still
    // exists for this country), else the first.
    if (_initialPage == null) {
      final saved = slides.indexWhere((s) => s.id == _lastSlideId);
      _initialPage = saved < 0 ? 0 : saved;
      _current = _initialPage!;
    }

    final current = _current.clamp(0, slides.length - 1);
    // A lone slide stays put — no auto-advance, looping, swipe or dots.
    final hasMultiple = slides.length > 1;
    // Reduce Motion, or a screen reader that can't keep up with slides
    // changing under it: no auto-advance, people swipe through themselves.
    final media = MediaQuery.of(context);
    final autoAdvance =
        hasMultiple && !media.disableAnimations && !media.accessibleNavigation;
    // A video slide holds the carousel until it finishes, then advances itself.
    final currentIsVideo = slides[current].hasVideo;

    // Playing / auto-advancing allowed: on screen and in view
    final showing = !_covered && _inView && widget.active;

    return Padding(
      padding: widget.padding,
      child: Column(
        children: [
          VisibilityDetector(
            key: Key('carousel-${widget.section}'),
            onVisibilityChanged: _onVisibilityChanged,
            child: SizedBox(
              width: double.infinity,
              child: CarouselSlider.builder(
                carouselController: _carousel,
                itemCount: slides.length,
                options: CarouselOptions(
                  // Null keeps the package's 16:9 (Home)
                  height: widget.height,
                  viewportFraction: 1.0,
                  initialPage: _initialPage!,
                  padEnds: false,
                  enlargeCenterPage: false,
                  autoPlay: autoAdvance && !currentIsVideo && showing,
                  enableInfiniteScroll: hasMultiple,
                  scrollPhysics: hasMultiple
                      ? null
                      : const NeverScrollableScrollPhysics(),
                  autoPlayInterval: const Duration(seconds: 5),
                  autoPlayAnimationDuration: const Duration(milliseconds: 600),
                  autoPlayCurve: Curves.easeInOut,
                  onPageChanged: (index, _) {
                    setState(() {
                      _current = index;
                      _advancedFrom = null;
                    });
                    _rememberSlide(slides[index]);
                  },
                ),
                itemBuilder: (context, index, _) {
                  final slide = slides[index];
                  if (!slide.hasVideo) {
                    return _SlideItem(
                      pictureUrl: slide.picture,
                      height: widget.height,
                    );
                  }
                  return _VideoSlideItem(
                    height: widget.height,
                    videoUrl: slide.video,
                    coverUrl: slide.picture,
                    videos: _videos,
                    isActive: index == _current,
                    replayToken: _replays[slide.id] ?? 0,
                    resume: _resumeId == slide.id,
                    onResume: (wasMuted) => _onResume(slide.id, wasMuted),
                    onScreen: showing,
                    loop: !hasMultiple,
                    muted: _muted,
                    onToggleMute: () => setState(() {
                      _muted = !_muted;
                      _chosenMuted = _muted;
                    }),
                    onPlayStart: _onPlayStart,
                    // Without auto-advance a finished video just stops
                    onFinished: autoAdvance ? () => _advanceFrom(index) : null,
                  );
                },
              ),
            ),
          ),
          if (hasMultiple) ...[
            const SizedBox(height: 12),
            AnimatedSmoothIndicator(
              activeIndex: current,
              count: slides.length,
              effect: const ExpandingDotsEffect(
                activeDotColor: kGold,
                dotColor: Color(0x5994A3B8), // kSub @ 35% opacity
                dotHeight: 6,
                dotWidth: 6,
                expansionFactor: 3.5,
                spacing: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A slide's frame: 16:9 when [height] is null (Home), otherwise a
/// full-width banner that tall.
class _SlideBox extends StatelessWidget {
  final double? height;
  final Widget child;
  const _SlideBox({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final h = height;
    if (h == null) return AspectRatio(aspectRatio: 16 / 9, child: child);
    return SizedBox(width: double.infinity, height: h, child: child);
  }
}

class _SlideItem extends StatelessWidget {
  final String pictureUrl;
  final double? height;

  const _SlideItem({required this.pictureUrl, this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _SlideBox(
        height: height,
        child: CachedNetworkImage(
          imageUrl: pictureUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (context, url) => Container(
            color: Theme.of(context).cardColor,
            child: const Center(
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) =>
              Container(color: Theme.of(context).cardColor),
        ),
      ),
    );
  }
}

/// A carousel slide that plays an MP4 over its cover image, with a
/// mute/unmute button.
///
/// Only the slide on screen loads and plays its video (so the carousel doesn't
/// download every video up front). Its player comes from [videos], which keeps
/// it after the slide scrolls away, so coming back plays again instantly. When
/// it finishes, [onFinished] advances the carousel; a lone slide loops
/// instead. If the video can't load, the cover stays up and the carousel moves
/// on after the usual 5 seconds.
class _VideoSlideItem extends StatefulWidget {
  // Banner height, or null for 16:9 (see _SlideBox)
  final double? height;
  final String videoUrl;
  final String coverUrl;
  final _CarouselVideoCache videos;
  final bool isActive;
  // Changes when the video should start over while it's showing (its role
  // button was highlighted again)
  final int replayToken;
  // Continue from where this video stopped instead of starting over (a role
  // button switched back to it). [onResume] gets whether it was muted and
  // returns whether to play muted.
  final bool resume;
  final bool Function(bool wasMuted)? onResume;
  // False while another screen covers Home
  final bool onScreen;
  final bool loop;
  final bool muted;
  final VoidCallback onToggleMute;
  // Called as playback starts from the beginning; returns whether to start
  // muted (true for a replay)
  final bool Function(String videoUrl) onPlayStart;
  final VoidCallback? onFinished;

  const _VideoSlideItem({
    this.height,
    required this.videoUrl,
    required this.coverUrl,
    required this.videos,
    required this.isActive,
    this.replayToken = 0,
    this.resume = false,
    this.onResume,
    required this.onScreen,
    required this.loop,
    required this.muted,
    required this.onToggleMute,
    required this.onPlayStart,
    this.onFinished,
  });

  @override
  State<_VideoSlideItem> createState() => _VideoSlideItemState();
}

class _VideoSlideItemState extends State<_VideoSlideItem>
    with WidgetsBindingObserver {
  // Where a video was left when its whole carousel went away mid-play (the
  // screen was replaced — e.g. switching Gig Worker ↔ Gig Host — and its
  // player disposed with it), by video URL. Coming back to that slide
  // carries on from there instead of starting over. In memory only.
  static final Map<String, ({Duration position, bool muted})> _leftAt = {};

  VideoPlayerController? _controller;
  bool _ready = false;
  bool _finishedFired = false;
  Timer? _fallback;
  // Fires at the video's exact end — position updates only arrive about
  // every 500ms, and some devices send the completion event late.
  Timer? _endTimer;
  // While the video is open full screen, that page handles its ending
  bool _fullscreen = false;
  // Where the lone looping slide was on the last tick, and whether its
  // first lap has wrapped round yet (see _onTick)
  Duration _lastPosition = Duration.zero;
  bool _lapped = false;
  // Paused by the viewer — shared with the full screen page so both agree
  final _paused = ValueNotifier<bool>(false);
  // False while the app is in the background or the phone is locked. Handled
  // here, not by rebuilding: no frames run then, and the carousel's timers
  // could otherwise move on to this slide and start it with the screen off.
  bool _appActive = true;

  // Allowed to play: the current slide, Home is the visible screen, and the
  // app is in front. Our own full screen page covers Home too, but the video
  // carries on there.
  bool get _on =>
      widget.isActive && (widget.onScreen || _fullscreen) && _appActive;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (_on) _activate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasOn = _on;
    _appActive = state == AppLifecycleState.resumed;
    if (_on && !wasOn) {
      _resumePlayback();
    } else if (!_on && wasOn) {
      _pausePlayback();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoSlideItem old) {
    super.didUpdateWidget(old);
    final wasOn = old.isActive && (old.onScreen || _fullscreen) && _appActive;
    if (_on && !wasOn) {
      old.isActive ? _resumePlayback() : _activate();
    } else if (!_on && wasOn) {
      _pausePlayback();
    } else if (_on && widget.replayToken != old.replayToken) {
      // Already showing: start over from the beginning (also un-pauses)
      _activate();
    }
    if (widget.muted != old.muted && _ready) {
      _controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  Future<void> _activate() async {
    _endTimer?.cancel();
    _fallback?.cancel();
    // Hold the "finished" signal until playback has really restarted — a
    // reused player still reports its last run as completed until the seek.
    _finishedFired = true;
    try {
      final controller = await widget.videos.obtain(widget.videoUrl);
      if (!mounted) return;
      if (!identical(controller, _controller)) {
        // First time here, or the cache swapped in the downloaded copy
        _controller?.removeListener(_onTick);
        controller.addListener(_onTick);
        setState(() {
          _controller = controller;
          _ready = true;
        });
      }
      if (!_on) return;
      // Left mid-play when the carousel went away: continue from there
      final left = _leftAt.remove(widget.videoUrl);
      if (left != null && !widget.resume) {
        final duration = controller.value.duration;
        if (duration <= Duration.zero || left.position < duration) {
          final muted = widget.onResume?.call(left.muted) ?? left.muted;
          _lastPosition = left.position;
          await controller.setVolume(muted ? 0 : 1);
          await controller.setLooping(widget.loop);
          await controller.seekTo(left.position);
          if (!mounted || !_on) return;
          _paused.value = false;
          await controller.play();
          _finishedFired = false;
          _onTick();
          return;
        }
      }
      if (widget.resume && widget.onResume != null) {
        final v = controller.value;
        final stoppedMidway =
            v.position > Duration.zero &&
            !v.isCompleted &&
            (v.duration <= Duration.zero || v.position < v.duration);
        // Consumed either way, so a later swipe back starts over as usual
        final muted = widget.onResume!(v.volume == 0);
        if (stoppedMidway) {
          _lastPosition = v.position;
          await controller.setVolume(muted ? 0 : 1);
          await controller.setLooping(widget.loop);
          if (!mounted || !_on) return;
          _paused.value = false;
          await controller.play();
          _finishedFired = false;
          _onTick();
          return;
        }
      }
      // First play on this device with sound, a replay muted
      final startMuted = widget.onPlayStart(widget.videoUrl);
      _lastPosition = Duration.zero;
      _lapped = false;
      await controller.setVolume(startMuted ? 0 : 1);
      await controller.setLooping(widget.loop);
      await controller.seekTo(Duration.zero);
      if (!mounted || !_on) return;
      _paused.value = false;
      await controller.play();
      _finishedFired = false;
    } catch (e) {
      debugPrint('Carousel video error: $e');
      // Keep the cover image and let the carousel move on as for an image.
      if (mounted && _on && widget.onFinished != null) {
        _finishedFired = false;
        _fallback = Timer(const Duration(seconds: 5), _finish);
      }
    }
  }

  void _pausePlayback() {
    _fallback?.cancel();
    _endTimer?.cancel();
    _controller?.pause();
  }

  // Back in view on the same slide (Home uncovered, or the app reopened):
  // carry on from where it stopped, unless the viewer paused it or it ended.
  void _resumePlayback() {
    final controller = _controller;
    if (!_ready || controller == null) {
      _activate();
      return;
    }
    if (!_paused.value &&
        !controller.value.isPlaying &&
        !controller.value.isCompleted) {
      controller.play();
      _finishedFired = false;
    }
    _onTick();
  }

  void _onTick() {
    final v = _controller?.value;
    // A lone slide loops on one player, so its second lap is a replay too:
    // mute once as it wraps round. Later laps keep whatever the viewer picks.
    if (widget.loop &&
        v != null &&
        v.isInitialized &&
        _on &&
        !_fullscreen &&
        !_lapped) {
      final wrapped = v.position + const Duration(seconds: 1) < _lastPosition;
      _lastPosition = v.position;
      if (wrapped) {
        _lapped = true;
        widget.onPlayStart(widget.videoUrl);
      }
    }
    if (v == null || !v.isInitialized || widget.loop || !_on || _fullscreen) {
      return;
    }
    // The player's own completion event, with the position as a backup for
    // platforms that report it a beat late — either way, advance right away.
    final ended =
        v.isCompleted ||
        (v.duration > Duration.zero && v.position >= v.duration);
    if (ended) {
      _finish();
      return;
    }
    // Re-aimed on every update so it tracks the real playback position;
    // held off while paused or buffering so a stall can't advance early.
    _endTimer?.cancel();
    if (v.isPlaying && !v.isBuffering && v.duration > Duration.zero) {
      _endTimer = Timer(v.duration - v.position, _finish);
    }
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    if (controller == null || _fullscreen) return;
    _fullscreen = true;
    _endTimer?.cancel();
    final ended = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(
          controller: controller,
          muted: widget.muted,
          onToggleMute: widget.onToggleMute,
          paused: _paused,
          endsOnFinish: !widget.loop,
        ),
      ),
    );
    _fullscreen = false;
    if (!mounted) return;
    // Finished while full screen: move the carousel on, as it would have.
    // Closed early: carry on playing here and re-aim the end timer.
    ended == true ? _finish() : _onTick();
  }

  void _finish() {
    if (_finishedFired || !mounted || !widget.isActive) return;
    _finishedFired = true;
    widget.onFinished?.call();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    _paused.value = !_paused.value;
    _paused.value ? controller.pause() : controller.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    _endTimer?.cancel();
    // The player belongs to the carousel's cache, which outlives this slide
    _controller?.removeListener(_onTick);
    if (widget.isActive) {
      // Still the current slide, so the carousel itself is going away:
      // remember where the video was for when it comes back (see _leftAt)
      final v = _controller?.value;
      if (v != null &&
          v.isInitialized &&
          v.position > Duration.zero &&
          !v.isCompleted &&
          (v.duration <= Duration.zero || v.position < v.duration)) {
        _leftAt[widget.videoUrl] = (position: v.position, muted: v.volume == 0);
      }
      _controller?.pause();
    }
    _paused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _SlideBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.coverUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: widget.coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Theme.of(context).cardColor),
                errorWidget: (context, url, error) =>
                    Container(color: Theme.of(context).cardColor),
              )
            else
              // No cover: a spinner until the first frame is ready
              Container(
                color: Theme.of(context).cardColor,
                child: _ready
                    ? null
                    : const Center(
                        child: CircularProgressIndicator(
                          color: kGold,
                          strokeWidth: 2,
                        ),
                      ),
              ),
            if (_ready && controller != null)
              // Tapping the video pauses it and brings up the controls, which
              // stay until it plays again (tap again, or the center button)
              ValueListenableBuilder<bool>(
                valueListenable: _paused,
                builder: (context, paused, _) => _AutoHideControls(
                  pinned: paused,
                  onTap: _togglePlay,
                  semanticsLabel: paused ? 'Video, paused' : 'Video, playing',
                  controls: [
                    if (paused)
                      Center(
                        child: _VideoOverlayButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play',
                          size: 32,
                          onTap: _togglePlay,
                        ),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: _VideoCountdown(controller: controller),
                    ),
                    // Clears the always-on mute button below (10 + 44 + 8 gap)
                    Positioned(
                      right: 62,
                      bottom: 10,
                      child: _VideoOverlayButton(
                        icon: Icons.fullscreen_rounded,
                        label: 'Full screen',
                        onTap: _openFullscreen,
                      ),
                    ),
                  ],
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),
            // Always up, not behind a tap: sound must be one tap from off
            if (_ready && controller != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: _VideoOverlayButton(
                  icon: widget.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: widget.muted ? 'Unmute' : 'Mute',
                  onTap: widget.onToggleMute,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Remaining time of a video, e.g. 0:07, on a dark pill
class _VideoCountdown extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoCountdown({required this.controller});

  // Rounded up so it reads 0:01 until the very end
  static String _format(Duration d) {
    final total = (d.inMilliseconds / 1000).ceil();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final left = v.duration - v.position;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _format(left.isNegative ? Duration.zero : left),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// Round translucent icon button shown over a video
class _VideoOverlayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  const _VideoOverlayButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        // 12 around a 20pt icon = 44pt, the iOS minimum touch size
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            color: Colors.white,
            size: size,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

/// A carousel video played full screen in landscape, on the same player as
/// its slide so it carries on from where it was. Pops with `true` when the
/// video finishes (if [endsOnFinish]), so the carousel can move on.
class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final bool muted;
  final VoidCallback onToggleMute;
  // The slide's own paused state, so pausing here carries back to it
  final ValueNotifier<bool> paused;
  final bool endsOnFinish;

  const _FullscreenVideoPage({
    required this.controller,
    required this.muted,
    required this.onToggleMute,
    required this.paused,
    required this.endsOnFinish,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late bool _muted = widget.muted;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    // Back to the app's rule (portrait on phones, free on tablets) with the
    // status/navigation bars on — not a hard portrait lock, which stuck iPads
    restoreAppOrientations();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _onTick() {
    final v = widget.controller.value;
    if (!widget.endsOnFinish || !v.isInitialized) return;
    final ended =
        v.isCompleted ||
        (v.duration > Duration.zero && v.position >= v.duration);
    if (ended) _close(true);
  }

  void _close(bool ended) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(ended);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.onToggleMute();
  }

  void _togglePlay() {
    final paused = widget.paused;
    paused.value = !paused.value;
    paused.value ? widget.controller.pause() : widget.controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: widget.paused,
        builder: (context, paused, _) => _AutoHideControls(
          // Controls stay up while paused
          pinned: paused,
          controls: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    children: [
                      _VideoOverlayButton(
                        icon: paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: paused ? 'Play' : 'Pause',
                        onTap: _togglePlay,
                      ),
                      const SizedBox(width: 12),
                      _VideoCountdown(controller: controller),
                      const SizedBox(width: 12),
                      // Drag or tap to jump; the vertical padding gives the
                      // thin bar a finger-sized touch area
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          colors: VideoProgressColors(
                            playedColor: kGold,
                            bufferedColor: Colors.white.withValues(alpha: 0.4),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _VideoOverlayButton(
                        icon: _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 8),
                      _VideoOverlayButton(
                        icon: Icons.fullscreen_exit_rounded,
                        label: 'Exit full screen',
                        onTap: () => _close(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}

/// Video controls that start hidden. Tapping the video fades them in; they
/// fade slowly away again after [_showFor] without a touch, and tapping the
/// video while they're up hides them straight away. With [onTap], tapping the
/// video calls that instead. While [pinned] (e.g. paused) they stay up.
class _AutoHideControls extends StatefulWidget {
  final Widget child;
  // Laid out in a Stack over [child], e.g. Positioned buttons
  final List<Widget> controls;
  final bool pinned;
  final VoidCallback? onTap;
  // Names the video for screen readers, whose tap then plays or pauses it
  final String? semanticsLabel;

  const _AutoHideControls({
    required this.child,
    required this.controls,
    this.pinned = false,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  State<_AutoHideControls> createState() => _AutoHideControlsState();
}

class _AutoHideControlsState extends State<_AutoHideControls> {
  static const _showFor = Duration(seconds: 3);

  late bool _visible = widget.pinned;
  Timer? _hideTimer;
  // Fingers on the controls — no fading out mid-drag on the time slider
  int _touches = 0;

  @override
  void didUpdateWidget(covariant _AutoHideControls old) {
    super.didUpdateWidget(old);
    if (widget.pinned == old.pinned) return;
    if (widget.pinned) {
      _hideTimer?.cancel();
      setState(() => _visible = true);
    } else if (_visible) {
      // Unpinned (e.g. playing again): fade out after the usual delay
      _restartHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    _visible ? _restartHideTimer() : _hideTimer?.cancel();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_touches > 0 || widget.pinned) return;
    _hideTimer = Timer(_showFor, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _release() {
    if (_touches > 0) _touches--;
    if (_visible) _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          container: true,
          button: widget.semanticsLabel != null,
          label: widget.semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap ?? _toggle,
            child: widget.child,
          ),
        ),
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            // Quick to appear, slow to fade out
            duration: Duration(milliseconds: _visible ? 200 : 800),
            curve: Curves.easeInOut,
            // Using a control keeps them up, then 3s more after letting go
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _touches++;
                _hideTimer?.cancel();
              },
              onPointerUp: (_) => _release(),
              onPointerCancel: (_) => _release(),
              child: Stack(fit: StackFit.expand, children: widget.controls),
            ),
          ),
        ),
      ],
    );
  }
}

/// Carousel videos that have already played on this device, by URL — a newly
/// uploaded video has a new URL, so it counts as unplayed. Kept in
/// shared_preferences across launches and capped, oldest first, so it can't
/// grow without end as slides are replaced.
class _PlayedVideos {
  static const _prefsKey = 'home_carousel_played_videos';
  static const _max = 50;

  List<String> _urls = const [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _urls = prefs.getStringList(_prefsKey) ?? const [];
    } catch (e) {
      // Unreadable: every video counts as new, so plays with sound once
      debugPrint('Played videos load failed: $e');
    }
    _loaded = true;
  }

  bool contains(String url) => _urls.contains(url);

  void add(String url) {
    if (_urls.contains(url)) return;
    final urls = [..._urls, url];
    _urls = urls.length > _max ? urls.sublist(urls.length - _max) : urls;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_prefsKey, _urls))
        .catchError((Object e) {
          debugPrint('Played videos save failed: $e');
          return false;
        });
  }
}

class _CachedPlayer {
  final VideoPlayerController controller;
  final bool fromFile;

  const _CachedPlayer(this.controller, {required this.fromFile});
}

/// The carousel's video players, kept for as long as the carousel is on
/// screen so swiping back to a video that already played starts it again
/// instantly rather than reloading it.
///
/// Each video is also saved to the device the first time it plays (in its
/// own cache, so big videos don't push the carousel images out of theirs).
/// Once that copy is ready, the next visit swaps the streaming player for one
/// that reads the file — streaming players can re-download from the start
/// after a replay — and later app launches play from the file straight away.
class _CarouselVideoCache {
  static final _files = CacheManager(
    Config(
      'carouselVideos',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 20,
    ),
  );

  final _players = <String, Future<_CachedPlayer>>{};
  final _downloading = <String>{};
  // Streaming players replaced by a downloaded copy. A slide may still be
  // showing one for a moment, so they're only disposed with the carousel.
  final _retired = <VideoPlayerController>[];
  bool _disposed = false;

  Future<VideoPlayerController> obtain(String url) async {
    final pending = _players[url] ??= _create(url);
    var player = await pending;
    if (!player.fromFile && identical(_players[url], pending)) {
      final cached = await _files.getFileFromCache(url);
      if (cached != null && identical(_players[url], pending)) {
        final upgrade = _upgrade(player, cached.file);
        _players[url] = upgrade;
        player = await upgrade;
      }
    }
    return player.controller;
  }

  Future<_CachedPlayer> _create(String url) async {
    final cached = await _files.getFileFromCache(url);
    final controller = cached != null
        ? VideoPlayerController.file(
            cached.file,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
    try {
      await controller.initialize();
    } catch (_) {
      _players.remove(url);
      await controller.dispose();
      rethrow;
    }
    if (_disposed) {
      await controller.dispose();
      throw StateError('Carousel closed');
    }
    if (cached == null) _download(url);
    return _CachedPlayer(controller, fromFile: cached != null);
  }

  // Falls back to the streaming player if the saved file won't open
  Future<_CachedPlayer> _upgrade(_CachedPlayer streaming, File file) async {
    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('Carousel video cache error: $e');
      await controller.dispose();
      return streaming;
    }
    if (_disposed) {
      await controller.dispose();
      return streaming;
    }
    _retired.add(streaming.controller);
    return _CachedPlayer(controller, fromFile: true);
  }

  void _download(String url) {
    if (!_downloading.add(url)) return;
    _files
        .downloadFile(url)
        .then<void>(
          (_) {},
          onError: (Object e) =>
              debugPrint('Carousel video download failed: $e'),
        )
        .whenComplete(() => _downloading.remove(url));
  }

  void dispose() {
    _disposed = true;
    for (final pending in _players.values) {
      pending.then((p) => p.controller.dispose()).catchError((_) {});
    }
    for (final controller in _retired) {
      controller.dispose();
    }
    _players.clear();
    _retired.clear();
  }
}
