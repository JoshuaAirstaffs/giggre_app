import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/core/services/referral_link_service.dart';

void main() {
  group('ReferralLinkService.parseCode', () {
    test('reads the code from an invite link', () {
      expect(
        ReferralLinkService.parseCode('https://go.giggre.com/r/GX82KL19'),
        'GX82KL19',
      );
      expect(
        ReferralLinkService.parseCode('https://go.giggre.com/r/gx82kl19/'),
        'GX82KL19',
      );
    });

    test('accepts a bare code, as old QR codes contain', () {
      expect(ReferralLinkService.parseCode(' gx82kl19 '), 'GX82KL19');
    });

    test('finds the link inside a copied share message', () {
      expect(
        ReferralLinkService.parseCode(
          'Join me on Giggre! Sign up with my referral code GX82KL19:\n'
          'https://go.giggre.com/r/GX82KL19',
        ),
        'GX82KL19',
      );
      expect(
        ReferralLinkService.parseCode('see https://go.giggre.com/r/GX82KL19X'),
        isNull,
      );
      expect(
        ReferralLinkService.parseCode('see https://evil.com/r/GX82KL19'),
        isNull,
      );
    });

    test('ignores other hosts, paths and random text', () {
      expect(ReferralLinkService.parseCode('https://evil.com/r/GX82KL19'), isNull);
      expect(ReferralLinkService.parseCode('https://go.giggre.com/x/GX82KL19'), isNull);
      expect(ReferralLinkService.parseCode('https://go.giggre.com/r/SHORT'), isNull);
      expect(ReferralLinkService.parseCode('PASSWORD'), isNull);
      expect(ReferralLinkService.parseCode(''), isNull);
    });

    test('linkFor round-trips through parseCode', () {
      expect(
        ReferralLinkService.parseCode(ReferralLinkService.linkFor('AB12CD34')),
        'AB12CD34',
      );
    });
  });
}
