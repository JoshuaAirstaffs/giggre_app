# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One shared Giggre design language on iOS and Android (confirmed), not separate Cupertino and Material looks. Platform-native behavior is kept where users expect it: back gestures, sheets, pickers, permissions, and system share and notification surfaces.

## Users

Two equally important sides (confirmed):

- **Gig Workers**: people in the Philippines and the United States looking for short, nearby paid gigs on their phones, such as cleaning, repairs, errands, events, and admin help.
- **Gig Hosts**: individuals and small businesses who need help quickly and post gigs for workers to apply to or accept.

One account can act in both roles. The app has separate worker and host shells (`lib/screens/worker/`, `lib/screens/host/`).

## Product Purpose

Giggre connects people who need short-term help with nearby workers. It covers the whole gig in one app: posting, discovery, applying or accepting, chat and calls, doing the work, payment, and ratings. Success means a host gets the gig filled and done, and the worker gets paid, with trust on both sides.

## Positioning

**Hyperlocal and fast** (confirmed): gigs are found on a map, near the worker, and can start the same day (Quick Gigs). Wallet, verification, and rewards support this mechanism but are not the headline.

## Operating Context

- Markets: **the Philippines and the United States** for now (confirmed). Both are first-class, so copy, currency, phone formats, and payment methods must work for either.
  - Philippines: PHP, with cash-in through GCash and Maya.
  - United States: USD. Signup offers US numbers (+1), and the US is currently the default country. For now, US hosts pay workers person to person, outside the app (confirmed). Stripe exists in code but is disabled ("coming soon"). US screens must not suggest in-app payment, but they should leave room for Stripe to arrive later.
  - Amounts are converted and displayed through FX rates (`lib/core/services/fx_rates.dart`). The unverified-account cap is set in USD.
- Mobile-first, often used on the move. Location and maps are central (Google Maps, geolocator).
- Ways to post a gig: **Quick Gig**, **Open Gig** (accepts applicants), and **Offered Gig** (sent to a specific worker).
- Supporting flows: in-app chat, Agora voice and video calls, push notifications, referral invite links via `go.giggre.com` (`hosting/invite.html`), in-app tutorials and a demo hub.
- Environments: `dev` and `prod` Firebase flavors (see README).

## Capabilities and Constraints

- **Gig Wallet**: cash-in, sending money, transaction history.
- **Gig Points**: rewards earned from gig tasks. Balances are written only by the backend (`functions/src/gigPoints.ts`). The app never writes them. Points can be pending or reserved, and screens must say when data is cached or offline rather than live.
- **Verification**: ID verification with an admin-controlled cap on how much an unverified account can transact (`lib/core/services/unverified_limit.dart`). Admins can also toggle gig access for unverified users. Unverified users are labelled as such, not blocked outright.
- **Trust**: ratings and reviews, blocking, reports, account suspension, and a maintenance mode.
- Estimate fields on gig posts, such as duration and hours, stay optional and non-binding so workers keep flexibility.
- Never assume a single country: avoid PH-only or US-only defaults in copy, currency, addresses, or payment methods unless the feature truly is region-specific.
- Terminology to keep: Gig Worker, Gig Host, Gig Wallet, Gig Points, Quick, Open, and Offered Gig.

## Brand Commitments

- Name: **Giggre**. Logo assets: `assets/images/logo.png`, `assets/images/g-logo.png`, `assets/icons/logo_app.png`.
- Welcome illustration tiles for trade categories: `assets/welcome/`.
- No voice or tone guidelines have been confirmed yet.

## Evidence on Hand

- Tutorial video and audio in `assets/video/tutorial`, `assets/audio/tutorial`. Demo-hub music and image licenses are in `lib/features/tutorial_demo/`.
- In-app content screens: About, FAQ, Terms, Privacy (`lib/screens/app_contents/`).
- No testimonials, user counts, earnings figures, or press were found. Do not invent them.

## Product Principles

1. **Nearby and now first.** Distance, timing, and pay should be readable at a glance. Getting from a gig to a decision takes as few steps as possible.
2. **Both sides are first-class.** A change to one role's flow should not make the other role's experience worse.
3. **Trust without gatekeeping.** Show verification and limits clearly, and don't block people who haven't verified yet.
4. **Money and points stay honest.** Show pending, reserved, and offline states clearly. Never present an estimate or cached value as final.
5. **Flexible by default.** Gig details that are estimates stay optional and non-binding.
