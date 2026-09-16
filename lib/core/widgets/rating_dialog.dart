import 'package:flutter/material.dart';
import '../services/rating_service.dart';
import '../theme/app_colors.dart';

/// The single rating dialog for both directions of a gig.
///
/// Replaces three near-identical copies (`_RatingDialog` in gig_detail_sheet,
/// `_WorkerRatingDialog` in gig_progress_tracker, `_HostRatingDialog` in
/// working_ui) that each carried their own copy of the submit logic.
class RatingDialog extends StatefulWidget {
  final String rateeId;
  final String rateeName;
  final RateeRole rateeRole;
  final String gigId;
  final String gigCollection;

  /// Denormalised onto the rating so the history screens can render it
  /// without re-reading the gig.
  final String gigTitle;

  /// Set for multi-worker gigs — the rating is recorded against that
  /// worker's own slot doc rather than the gig doc.
  final String? slotWorkerId;

  /// Renders the dialog without ever writing to Firestore, for the preview
  /// entries in Developer Options. Submitting returns the selection to the
  /// caller instead of creating a rating.
  final bool preview;

  const RatingDialog({
    super.key,
    required this.rateeId,
    required this.rateeName,
    required this.rateeRole,
    required this.gigId,
    required this.gigCollection,
    required this.gigTitle,
    this.slotWorkerId,
    this.preview = false,
  });

  /// Resolves to the chosen stars, tags and comment when [preview] is set,
  /// and to null otherwise (or whenever the rater skips).
  static Future<({int stars, List<String> tags, String? comment})?> show({
    required BuildContext context,
    required String rateeId,
    required String rateeName,
    required RateeRole rateeRole,
    required String gigId,
    required String gigCollection,
    required String gigTitle,
    String? slotWorkerId,
    bool preview = false,
  }) {
    return showDialog<({int stars, List<String> tags, String? comment})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(
        rateeId: rateeId,
        rateeName: rateeName,
        rateeRole: rateeRole,
        gigId: gigId,
        gigCollection: gigCollection,
        gigTitle: gigTitle,
        slotWorkerId: slotWorkerId,
        preview: preview,
      ),
    );
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _selected = 0;
  bool _submitting = false;
  String? _error;
  final _tags = <String>{};
  final _commentController = TextEditingController();

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];
  static const _green = Color(0xFF22C55E);
  static const _starActive = Color(0xFFFACC15);

  /// Mirrors the 500-character ceiling the `ratings` create rule enforces, so
  /// an over-long comment cannot be typed rather than being rejected by
  /// Firestore only once the rater hits Submit.
  static const _maxComment = 500;

  /// Counting up from zero on a field most raters leave empty is noise, so the
  /// counter stays hidden until the ceiling is actually in play.
  static const _counterFrom = 400;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String get _title => widget.rateeRole == RateeRole.worker
      ? 'Rate Your Worker'
      : 'Rate Your Host';

  /// Null rather than empty: [RatingService.submit] omits the field entirely
  /// when there is nothing to say, and the preview result reads the same way.
  String? get _comment {
    final text = _commentController.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (_selected == 0) return;
    if (widget.preview) {
      Navigator.pop(
        context,
        (stars: _selected, tags: _tags.toList(), comment: _comment),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await RatingService.submit(
        gigCollection: widget.gigCollection,
        gigId: widget.gigId,
        rateeId: widget.rateeId,
        rateeRole: widget.rateeRole,
        stars: _selected,
        rateeName: widget.rateeName,
        gigTitle: widget.gigTitle,
        tags: _tags.toList(),
        comment: _comment,
        slotWorkerId: widget.slotWorkerId,
      );
    } catch (e, st) {
      debugPrint('[RatingDialog] submit failed: $e\n$st');
      // Previously a bare `catch (_) {}` followed by a pop, so a rating that
      // never landed looked identical to one that did. Keep the dialog open
      // with the stars still selected so one tap retries.
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not save your rating. Please try again.';
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Widget? _commentCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    int? maxLength,
  }) => currentLength < _counterFrom
      ? null
      : Text(
          '$currentLength/$maxLength',
          style: const TextStyle(color: kSub, fontSize: 10),
        );

  static OutlineInputBorder _commentBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final label = _selected > 0 ? _labels[_selected] : 'Tap a star to rate';

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: _green,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _title,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.preview) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'PREVIEW · nothing is saved',
                  style: TextStyle(
                    color: kAmber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'How was ${widget.rateeName}?',
              style: const TextStyle(color: kSub, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starNum = i + 1;
                return GestureDetector(
                  onTap: _submitting
                      ? null
                      : () => setState(() => _selected = starNum),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starNum <= _selected
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: starNum <= _selected ? _starActive : kSub,
                      size: 40,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                label,
                key: ValueKey(label),
                style: TextStyle(
                  color: _selected > 0 ? _starActive : kSub,
                  fontSize: 13,
                  fontWeight:
                      _selected > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            // Tags only appear once a star is picked, so the dialog opens at
            // the same size and complexity it always has.
            if (_selected > 0) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: RatingService.tagsFor(widget.rateeRole).map((tag) {
                  final on = _tags.contains(tag);
                  return GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => setState(
                            () => on ? _tags.remove(tag) : _tags.add(tag),
                          ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: on
                            ? _green.withValues(alpha: 0.15)
                            : Colors.transparent,
                        border: Border.all(
                          color: on ? _green : kSub.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: on ? _green : kSub,
                          fontSize: 11,
                          fontWeight:
                              on ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _commentController,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: _maxComment,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: onSurface, fontSize: 13),
                buildCounter: _commentCounter,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.rateeRole == RateeRole.worker
                      ? 'Anything else about their work? (optional)'
                      : 'Anything else about this host? (optional)',
                  hintStyle: const TextStyle(color: kSub, fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: _commentBorder(kSub.withValues(alpha: 0.4)),
                  enabledBorder: _commentBorder(kSub.withValues(alpha: 0.4)),
                  disabledBorder: _commentBorder(kSub.withValues(alpha: 0.2)),
                  focusedBorder: _commentBorder(_green),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: kSub, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_selected == 0 || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _green.withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _error == null ? 'Submit' : 'Try Again',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
