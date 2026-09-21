import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:giggre_app/core/widgets/avatars/avatar_picker_sheet.dart';
import 'package:giggre_app/core/widgets/avatars/giggre_avatar.dart';
import 'package:giggre_app/core/widgets/avatars/giggre_avatar_art.dart';

int _shapes(List<AvatarNode> nodes) {
  var n = 0;
  for (final node in nodes) {
    switch (node) {
      case AvatarShape():
        n++;
      case AvatarGroup(:final children):
        n += _shapes(children);
    }
  }
  return n;
}

Set<AvatarMotion> _motions(List<AvatarNode> nodes) {
  final out = <AvatarMotion>{};
  for (final node in nodes) {
    if (node is AvatarGroup) {
      out.add(node.motion);
      out.addAll(_motions(node.children));
    }
  }
  return out;
}

void main() {
  test('every avatar builds a scene with distinct timing', () {
    expect(kGiggreAvatars, hasLength(6));

    final ids = <String>{};
    for (final art in kGiggreAvatars) {
      expect(ids.add(art.id), isTrue, reason: 'duplicate id ${art.id}');
      expect(art.name, isNotEmpty);
      // A character that silently lost its parts would still be a valid
      // scene, just an empty circle.
      expect(_shapes(art.scene), greaterThan(15), reason: art.id);

      final motions = _motions(art.scene);
      expect(motions, contains(AvatarMotion.body), reason: art.id);
      expect(motions, contains(AvatarMotion.head), reason: art.id);
      expect(motions, contains(AvatarMotion.eyes), reason: art.id);
    }
  });

  test('the characters that wave are the ones that have an arm', () {
    Set<String> withMotion(AvatarMotion m) => {
      for (final a in kGiggreAvatars)
        if (_motions(a.scene).contains(m)) a.id,
    };

    expect(withMotion(AvatarMotion.arm), {'kai', 'mara'});
    expect(withMotion(AvatarMotion.strandLeft), {'mara'});
    expect(withMotion(AvatarMotion.strandRight), {'mara'});
  });

  test('an unknown id resolves to nothing rather than a stand-in', () {
    expect(giggreAvatarById('kai'), isNotNull);
    expect(giggreAvatarById('retired-character'), isNull);
    expect(giggreAvatarById(null), isNull);
    expect(GiggreAvatar.forId('retired-character'), isNull);
    expect(GiggreAvatar.forId(null), isNull);
    expect(GiggreAvatar.forId('nia'), isNotNull);
  });

  testWidgets('an avatar renders to a PNG that can be uploaded as a photo', (
    tester,
  ) async {
    // The still is what every screen that only knows photoUrl ends up showing,
    // so a failure here is an avatar that silently never propagates.
    for (final art in [kGiggreAvatars.first, kGiggreAvatars[1]]) {
      late final bytes = <int>[];
      await tester.runAsync(() async {
        bytes.addAll(await renderGiggreAvatarPng(art, size: 128));
      });

      expect(bytes.length, greaterThan(1000), reason: art.id);
      // PNG magic number — proves it encoded rather than returning a buffer.
      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    }
  });

  testWidgets(
    'the picker lists every character and preselects the current one',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    chosen = await showGiggreAvatarPicker(
                      ctx,
                      currentAvatarId: 'sana',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // A running ticker means pumpAndSettle would never return.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(tester.takeException(), isNull);
      for (final art in kGiggreAvatars) {
        expect(find.text(art.name), findsOneWidget, reason: art.id);
      }

      await tester.tap(find.text('Nia'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Use this avatar'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(chosen, 'nia');
    },
  );
}
