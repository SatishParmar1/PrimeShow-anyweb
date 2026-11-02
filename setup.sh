#!/usr/bin/env bash
# One-time project setup for the Primeshows app (macOS / Linux).
set -e
cd "$(dirname "$0")"

echo "==> Generating any missing Android/iOS platform files (existing files are kept)"
flutter create --platforms=android,ios --org org.primeshows --project-name prime .

echo "==> Getting packages"
flutter pub get

echo "==> Generating launcher icons"
dart run flutter_launcher_icons

echo "==> Generating native splash screen"
dart run flutter_native_splash:create

if [[ "$(uname)" == "Darwin" ]] && [ -d ios ]; then
  echo "==> Installing CocoaPods"
  (cd ios && pod install --repo-update) || echo "   (pod install failed – run it manually in ios/)"
fi

echo
echo "Done. Run the app with:  flutter run"
