Flutter app (Android)

Quick steps:
1. Install Flutter and set up Android toolchain: https://flutter.dev/docs/get-started/install
2. From project root run: flutter pub get
3. Run on device/emulator: flutter run -d <device>

Notes:
- This folder is a minimal app; if you used `flutter create`, replace the lib/ and pubspec.yaml with these files.
- The app uses packages: http, sqflite, path. It fetches NAVAll.txt when you tap the refresh icon and stores records in a local SQLite database.
- Search with the text field and tap Search.
