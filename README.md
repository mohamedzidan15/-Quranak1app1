# قرآنك — Native Android source (v8 integration)

This repository contains the Flutter Android application source and the website API integration for `https://quran1.kesug.com`.

## What is included
- Flutter native Android app source (`quranak_flutter_app/`).
- Website read API integration for reciters, videos, books, azkar categories and hadiths.
- Local catalog caching using SharedPreferences. Previously synchronized catalogs remain available when the device is offline.
- Quran surah index bundled in Dart source; prayer-time calculations run locally.
- Offline audio download manager for tracks the user chooses to save.
- Supplied adhan audio bundled in Flutter assets and Android raw resources.
- Five supplied prayer background images bundled locally (no network needed for those images).
- GitHub Actions workflow to generate Android Gradle scaffolding, analyze, test, build a release APK and publish it as an artifact.

## Important offline behavior
The app shell, prayer-time calculations, surah index, supplied prayer images, and bundled adhan do not require internet. Reciters/videos/books/azkar/hadith catalogs are cached after a successful sync. Audio becomes offline only after the user downloads it. Streaming videos and Quran page images that have not previously been cached still require internet. This repository does not claim that every remote media file is preloaded on installation.

## API
The app uses read-only GET endpoints on the existing website, for example:
- `index.php?action=get_reciters`
- `index.php?action=get_videos`
- `index.php?action=get_books&status=1`
- `index.php?action=get_azkar_categories`
- `index.php?action=get_hadiths`

The Android app does not connect directly to MySQL and does not contain database credentials. The existing PHP site remains the data source.

## Build on GitHub
1. Upload the contents of this repository to the root of your GitHub repository, preserving `.github/` and `tool/`.
2. Push to `main` or `master`, or manually run **Quranak Android CI** from the Actions tab.
3. Open the successful workflow run and download the `Quranak-Android-release` artifact.

The workflow runs `flutter analyze`, `flutter test`, and `flutter build apk --release`. A successful APK is not claimed until GitHub Actions reports success.

## Security
Never upload `config.php`, database dumps, admin passwords, API secrets, or production credentials to this mobile repository. The website database password was present in a previously shared config file; rotate that database password at the hosting provider and update the live server config. Firebase client configuration is not a substitute for server-side authorization; configure Firebase rules securely if Firebase features remain enabled.
