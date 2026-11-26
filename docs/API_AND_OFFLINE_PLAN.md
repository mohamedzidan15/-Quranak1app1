# API and offline behavior

## Current website read integration
The Flutter client calls the existing PHP `index.php` read actions over HTTPS. Responses are stored in SharedPreferences. If a request fails, the API helper returns the last cached response (or an empty list on first install).

## Catalogs currently synchronized
- `get_reciters`
- `get_videos`
- `get_books` with `status=1`
- `get_azkar_categories`
- `get_hadiths`

The website also exposes additional actions such as `get_audios`, `get_azkar`, `get_video`, and `get_book`; these can be added to screens as those flows are completed.

## Offline rules
- The app can launch offline.
- Prayer times are calculated on-device from the selected city coordinates.
- The full 114-surah index is bundled.
- Five prayer background images and the supplied adhan are bundled.
- Catalogs are available offline after at least one successful sync.
- Audio files are available offline only after an explicit download.
- Video playback requires internet unless a future explicit video-download feature is added.
- Mushaf pages are cached as visited; unvisited pages require a connection on first access.
