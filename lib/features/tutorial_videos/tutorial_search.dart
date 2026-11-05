import 'tutorial_videos_service.dart';

// Flexible search for Video Tutorials (Profile → Settings → Video Tutorials).
//
// A video matches when every part of the query is found in its title,
// description or admin keywords — in English OR Tagalog — where each part
// may also match:
//   • a synonym from the same topic: "signup" finds "Register", "Create
//     account", "Mag-register"; "cash in" finds "Top up"; …
//   • spacing / punctuation variants: "sign up" = "signup" = "sign-up"
//   • the start of a word: "regis" → "Registration"
//   • a small typo: "registr", "withdrow", "verfy"
// Results are ranked: title hits first, then keywords, then description.

/// Topics people search by. Each line is one meaning; any phrase finds the
/// others. English and Tagalog/Taglish together. Keep entries lowercase.
const List<List<String>> kTutorialSynonyms = [
  ['register', 'registration', 'sign up', 'signup', 'create account', 'new account', 'open account',
   'join', 'enroll', 'mag register', 'magregister', 'magparehistro', 'pagpaparehistro', 'gumawa ng account'],
  ['log in', 'login', 'sign in', 'signin', 'logging in', 'mag login', 'pumasok', 'password', 'forgot password'],
  ['log out', 'logout', 'sign out', 'signout'],
  ['verify', 'verification', 'verified', 'valid id', 'id', 'kyc', 'identity', 'selfie',
   'beripikasyon', 'pag verify', 'mag verify'],
  ['wallet', 'gig wallet', 'gigcash', 'gig cash', 'balance', 'pera'],
  ['top up', 'topup', 'cash in', 'cashin', 'deposit', 'load', 'add money', 'mag load', 'magdagdag ng pera'],
  ['withdraw', 'withdrawal', 'cash out', 'cashout', 'payout', 'mag withdraw', 'kunin ang pera'],
  ['send', 'send money', 'transfer', 'padala', 'magpadala'],
  ['points', 'gig points', 'reward', 'rewards', 'convert', 'puntos'],
  ['post gig', 'post a gig', 'posting', 'hire', 'hiring', 'gig host', 'host', 'find worker', 'find a worker',
   'mag post', 'maghanap ng worker'],
  ['apply', 'application', 'find work', 'find gig', 'find a gig', 'accept gig', 'accept', 'gig worker', 'worker',
   'job', 'jobs', 'work', 'trabaho', 'raket', 'maghanap ng trabaho'],
  ['quick gig', 'quick gigs', 'instant', 'quickgig'],
  ['open gig', 'open gigs'],
  ['offered gig', 'offer', 'direct offer', 'offered'],
  ['pay', 'payment', 'paying', 'bayad', 'magbayad', 'gcash', 'maya'],
  ['cancel', 'cancellation', 'refund', 'kanselahin'],
  ['rating', 'ratings', 'review', 'reviews', 'rate', 'stars', 'feedback'],
  ['profile', 'account settings', 'settings', 'edit profile'],
  ['chat', 'message', 'messages', 'messaging', 'mensahe'],
  ['notification', 'notifications', 'alert', 'alerts'],
  ['location', 'map', 'gps', 'lokasyon'],
  ['safety', 'security', 'privacy', 'scam', 'report', 'ligtas'],
];

/// Lowercase, accents folded (ñ → n), anything else → single spaces.
String _norm(String s) {
  final lower = s.toLowerCase().replaceAll('ñ', 'n').replaceAll('é', 'e').replaceAll('á', 'a');
  return lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String _compact(String s) => _norm(s).replaceAll(' ', '');

List<String> _words(String s) => _norm(s).split(' ').where((w) => w.isNotEmpty).toList();

/// Allowed typos for a word of this length.
int _tolerance(int len) => len >= 8 ? 2 : (len >= 5 ? 1 : 0);

int _distance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// One searchable field of a video, pre-processed.
class _Field {
  final double weight;
  final String compact;
  final List<String> words;

  /// Where each word starts inside [compact].
  final List<int> starts;

  _Field(String text, this.weight)
      : compact = _compact(text),
        words = _words(text),
        starts = _starts(_words(text));

  static List<int> _starts(List<String> words) {
    final out = <int>[];
    var o = 0;
    for (final w in words) {
      out.add(o);
      o += w.length;
    }
    return out;
  }

  /// Does [term] (one word or a phrase) appear here, allowing for spacing,
  /// word starts and small typos?
  bool has(String term) {
    final tc = _compact(term);
    if (tc.isEmpty) return false;
    // "signup" in "Sign up now" — only from the start of a word, so "load"
    // doesn't match "upload".
    if (tc.length >= 3 && starts.any((o) => compact.startsWith(tc, o))) return true;
    final tw = _words(term);
    if (tw.length == 1) {
      final t = tw.first;
      final tol = _tolerance(t.length);
      for (final w in words) {
        if (w == t) return true;
        if (t.length >= 2 && w.startsWith(t)) return true; // "regis" → "registration"
        if (tol > 0) {
          if (_distance(t, w, tol) <= tol) return true; // "verfy" → "verify"
          // typo while still typing: compare with the word's start
          if (w.length > t.length && _distance(t, w.substring(0, t.length), tol) <= tol) return true;
        }
      }
      return false;
    }
    // Phrase: every word present, in any order ("account create").
    return tw.every((t) => words.any((w) => _wordMatches(t, w)));
  }

  static bool _wordMatches(String t, String w) {
    if (w == t || (t.length >= 2 && w.startsWith(t))) return true;
    final tol = _tolerance(t.length);
    return tol > 0 && _distance(t, w, tol) <= tol;
  }
}

/// All the phrases a query part stands for: itself plus its topic's synonyms.
List<String> _expand(String part) {
  final pc = _compact(part);
  final out = <String>{part};
  if (pc.length < 2) return out.toList();
  for (final group in kTutorialSynonyms) {
    final hit = group.any((p) {
      final c = _compact(p);
      if (c == pc) return true;
      final tol = _tolerance(pc.length);
      return tol > 0 && c.length >= 4 && _distance(pc, c, tol) <= tol;
    });
    if (hit) out.addAll(group);
  }
  return out.toList();
}

/// Splits the query into parts. A known multi-word phrase ("sign up",
/// "cash in", "create account") stays one part; other words stand alone.
List<String> _parts(String query) {
  final words = _words(query);
  final parts = <String>[];
  var i = 0;
  bool known(String phrase) =>
      kTutorialSynonyms.any((g) => g.any((p) => _compact(p) == _compact(phrase)));
  while (i < words.length) {
    var taken = 1;
    for (var n = 3; n >= 2; n--) {
      if (i + n <= words.length && known(words.sublist(i, i + n).join(' '))) {
        taken = n;
        break;
      }
    }
    final part = words.sublist(i, i + taken).join(' ');
    // Skip filler words on their own.
    if (!(taken == 1 && const {'how', 'to', 'the', 'a', 'an', 'my', 'ng', 'sa', 'paano', 'mag', 'i'}.contains(part) && words.length > 1)) {
      parts.add(part);
    }
    i += taken;
  }
  return parts;
}

/// Videos matching [query], best first (all of them, in admin order, when
/// the query is empty).
List<TutorialVideo> searchTutorialVideos(List<TutorialVideo> videos, String query) {
  final parts = _parts(query);
  if (parts.isEmpty) return videos;
  final expanded = [for (final p in parts) _expand(p)];

  final scored = <(TutorialVideo, double)>[];
  for (final v in videos) {
    final fields = <_Field>[
      _Field(v.title, 3),
      _Field(v.keywords.join(' , '), 2.5),
      _Field(v.description, 1),
      if (v.tagalog != null) ...[
        _Field(v.tagalog!.title, 3),
        _Field(v.tagalog!.description, 1),
      ],
    ];
    var score = 0.0;
    var all = true;
    for (var i = 0; i < parts.length; i++) {
      var best = 0.0;
      for (final f in fields) {
        if (f.weight <= best) continue;
        // The exact words typed count a bit more than a synonym.
        if (f.has(parts[i])) {
          best = f.weight + 0.5;
        } else if (expanded[i].any(f.has)) {
          best = f.weight;
        }
      }
      if (best == 0) {
        all = false;
        break;
      }
      score += best;
    }
    if (all) scored.add((v, score));
  }
  scored.sort((a, b) {
    final c = b.$2.compareTo(a.$2);
    return c != 0 ? c : a.$1.order.compareTo(b.$1.order);
  });
  return [for (final s in scored) s.$1];
}
