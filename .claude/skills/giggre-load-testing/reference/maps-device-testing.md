# Map rendering on a device (separate from backend load)

The backend load test sends **no** Google Maps Platform requests and cannot measure rendering. Use a real device or emulator with `integration_test` for that.

## What to measure

- **Map ready:** time from the screen opening to `onMapCreated`, then to the first frame with markers.
- **Frame build/raster times** while panning and zooming, at 50, 200, 500 and 1,000 open gigs (the global listener loads all of them).
- **Clustering CPU** on zoom changes (`gig_map_section.dart:3569`, recomputed when zoom moves by 0.3 or more).
- **Memory** after 5 minutes on the map (marker bitmaps are cached in `_icons`).

## Setup

This changes the app's dev dependencies, so ask the user first.

1. Add to `pubspec.yaml` under `dev_dependencies`:
   ```yaml
   integration_test:
     sdk: flutter
   ```
2. Copy `templates/map_render_perf_test.dart` to `integration_test/map_render_perf_test.dart`. It runs against the dev project with an account the user signs into. It does not create data.
3. Seed gig volume in **dev** only with the user's approval. Synthetic gigs show up for dev testers.
4. Run on Android:
   ```
   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/map_render_perf_test.dart --profile --flavor dev --dart-define=FLAVOR=dev
   ```
   iOS needs a physical device for `--profile`.
5. Frame timings land in `build/integration_response_data.json`. Report the 90th/99th percentile build and raster ms and missed frames (over 16 ms).

## Billing

- Mobile Maps SDK map loads aren't billed per load.
- The web build (`google_maps_flutter_web`) **is** billed per Dynamic Maps load. Don't run map perf tests on web at volume.
- The post-gig screens call Places Autocomplete and Details per debounced keystroke burst. Don't automate typing in addresses at scale.
