# Primeshows – Flutter app

A native Android/iOS/Android TV app that opens websites in a fast WebView, with native navigation and app features around it. It starts on a **"My websites"** screen where the user adds, updates and deletes websites. These are stored on the device, and **https://primeshows.org** is added on first start.

## Features

| Feature | What it does |
|---|---|
| "My websites" start screen | A card for each saved website (icon, name, address). Tap to open. The ⋮ menu (top right) has **Update** and **Delete**, and Delete asks first. **Add website** (floating button on phones, a tile on TV) asks for an address and an optional name. `example.com` becomes `https://example.com/`, invalid addresses and duplicates are rejected, and an empty name is taken from the address. Everything is stored locally (SharedPreferences) and survives restarts. |
| Per-site navigation | primeshows.org keeps its Home · Movies · TV Shows · Search · More tabs. Any other website gets Home · Back · Forward · Reload · More. The site's own domain and sub-domains stay in the app. Back on a site's start page returns to "My websites", and the More sheet has a **My websites** button. |
| Native bottom navigation | Home · Movies · TV Shows · Search · More. The active tab follows the page you're on, including SPA route changes. Tapping the current tab scrolls to the top. Tabs navigate inside the single-page app without a full reload when possible. |
| "More" sheet | Trending, Genres, Anime, Live TV, Sports, FAQ, Contact, Privacy, Terms, plus Share, Copy link, Open in browser, Reload and Clear cache. |
| Splash screen | Native launch splash followed by a branded loading overlay until the first page is ready. |
| Pull-to-refresh and progress bar | Pull down to reload, with a thin accent progress bar while pages load. |
| Fullscreen video | Video goes landscape and immersive (system bars hidden) in fullscreen, and returns to portrait on exit. Inline playback, autoplay, Picture-in-Picture on iOS and DRM (protected media) are enabled. |
| Smart back button | Android back goes to the previous page, then Home, then "press back again to exit". It also exits fullscreen video. |
| Offline screen | A friendly error screen with Retry. The page reloads automatically when the connection returns. |
| Link handling | primeshows.org links stay in the app. Other sites open in the browser. `tel:`, `mailto:`, `whatsapp:` and `intent://` links open the right app. |
| Popup and redirect blocking | Popups to other domains and automatic redirects away from the site (usually ads) are blocked. Video iframes are never touched. |
| Deep links | Tapping a primeshows.org link in WhatsApp, Chrome or elsewhere can open it directly in the app. `primeshows://movie/123` also works. |
| App detection | The user agent includes `PrimeshowsApp/1.0` and `<html>` gets the class `in-app`, so the website can hide its own "install app" banners and similar elements. |
| Crash recovery | If the system kills the WebView, the app rebuilds and reloads it automatically. |
| Background pause | Video and audio pause when the app goes to the background (Android). |
| Android TV / Google TV | Shows on the TV home screen with its own banner. A side menu replaces the bottom bar, and the remote's arrow keys move a blue highlight between links on the website. OK opens, Back goes back, and Play/Pause controls video. See [Android TV](#android-tv). |

All settings are in **`lib/config/app_config.dart`**: the URL, allowed domains, tabs, menu links, colours, popup behaviour, portrait lock and injected CSS.

## Project structure

```
lib/
  main.dart                  App entry, theme, system UI, initial deep link
  config/app_config.dart     ← all settings live here
  models/saved_site.dart     A saved website (name + URL)
  services/site_store.dart   Saves/loads websites on the device, URL checks
  screens/sites_home.dart    "My websites" start screen (+ deep links)
  screens/web_shell.dart     WebView + navigation + all native behaviour
  utils/link_handler.dart    In-app vs external links, intent:// support
  utils/app_device.dart      TV detection + simulated taps (talks to MainActivity.kt)
  widgets/                   Site cards, add/update/delete dialogs, splash overlay,
                             offline screen, bottom bar, TV side menu, "More" sheet
assets/icon/                 App icon + splash images (generated from the logo)
assets/brand/                Logo files: mark, horizontal, stacked, app icon (SVG + PNG)
android/.../AndroidManifest.xml  Permissions, deep links, link queries
ios/Runner/Info.plist        Display name, ATS for video hosts, deep links
web_files/assetlinks.json    Upload to your website for verified App Links
setup.sh / setup.bat         One-time project setup
test/widget_test.dart        Unit tests for link handling and tab matching
```

## Setup (one time)

Requirements: Flutter 3.35 or newer (Dart 3.9), plus Android Studio with the Android SDK (and Xcode for iOS).

```bash
# Windows
setup.bat

# macOS / Linux
bash setup.sh
```

The setup script:
1. generates any missing Android and iOS platform files with `flutter create`. Files already in the project are kept.
2. runs `flutter pub get`.
3. generates launcher icons and the native splash screen from `assets/icon/`.
4. on macOS, runs `pod install` for iOS.

Then:

```bash
flutter run                          # run on a connected phone/emulator
flutter build apk --release          # APK  → build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release    # AAB for Google Play
flutter build ipa                    # iOS (on a Mac)
```

## Before publishing

1. **Icon and logo.** The Primeshows "orbit" logo (a planet with a play button and a ring around it) is already in `assets/icon/` and `assets/brand/`. `setup.bat` / `setup.sh` turns it into the launcher icons and native splash. To change it, replace the files in `assets/icon/` with the same names and sizes (`icon.png` 1024², `icon_background.png` 1024², `icon_foreground.png` 1024² transparent with the logo inside the middle 66 %, `splash.png` 768², `splash_android12.png` 960² with the logo inside the middle 640 px circle), then run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`. The SVG files in `assets/brand/` scale to any size for the website, social media and store listings.
2. **Package ID.** The app ID is `org.primeshows.primeshows`. To change it, edit `applicationId` in `android/app/build.gradle.kts` and `PRODUCT_BUNDLE_IDENTIFIER` in Xcode.
3. **Release signing (Android).** Create a keystore:
   ```bash
   keytool -genkey -v -keystore primeshows-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias primeshows
   ```
   Then create `android/key.properties` (it is git-ignored):
   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=primeshows
   storeFile=C:/path/to/primeshows-release.jks
   ```
   The build picks it up automatically. Until then, release builds use the debug key.
4. **Verified App Links (optional).** Get your release key's SHA-256 fingerprint (`keytool -list -v -keystore primeshows-release.jks`), or copy it from Play Console › App integrity. Put it in `web_files/assetlinks.json` and upload the file to `https://primeshows.org/.well-known/assetlinks.json` (and `www.primeshows.org` if that host is used). Links will then open the app without the "Open with" chooser.
5. **iOS Universal Links (optional).** Add the *Associated Domains* capability in Xcode (`applinks:primeshows.org`) and host an `apple-app-site-association` file on the site.

## Supported Android versions

The app installs on **Android 7.0 (API 24) and newer**, on phones, tablets and TVs. That is the lowest version Flutter 3.35+ can build for (`minSdk = flutter.minSdkVersion` in `android/app/build.gradle.kts`). Android TVs and boxes on Android 7 and newer can install it, including 32-bit ARM TVs (`armeabi-v7a`), which are the most common.

Android 5.0–6.0 (API 21–23) would need an older Flutter (3.32 or earlier) and older package versions.

## Android TV

The same APK works on phones and TVs. The app detects a TV when it starts.

**What changes on a TV**

- The app appears on the Android TV / Google TV home screen (`LEANBACK_LAUNCHER`) with the banner `android/app/src/main/res/drawable-*/tv_banner.png`.
- A side menu on the left replaces the bottom bar: Home, Search, Movies, TV Shows, Trending, Live TV, Sports, Anime, Genres and More. It expands with labels when you move into it. Edit it in `AppConfig.tvRailLinks`.
- **Arrow keys** move a blue highlight between links, buttons and posters on the website. Carousels scroll sideways and the page scrolls to keep the highlight in view. Press **Left** at the left edge to open the side menu, and **Right** to go back to the page.
- **OK** opens the highlighted item. On a video player or a text field (e.g. Search), OK performs a real tap, so the player starts or the on-screen keyboard opens.
- **Back** leaves a video player or text field first, then goes to the previous page, then Home, then asks to exit. In the side menu, Back returns to the page.
- **Play/Pause, Fast-forward and Rewind** control video on the page.
- No portrait lock, no forced rotation and no pull-to-refresh.
- The user agent ends with `PrimeshowsTV`, and `<html>` gets the class `in-tv`, so the website can show a TV-friendly layout:
  ```css
  .in-tv .site-header { display: none; }   /* the app has its own menu */
  .in-tv body { font-size: 18px; }
  ```

**Testing on an emulator**

The Android TV emulator images for Windows/Intel PCs are **32-bit x86** ("AOSP TV on x86"). Flutter doesn't support 32-bit x86, so `flutter devices` lists them as **unsupported**. This happens with every Flutter app, not only this one. Check with:

```
adb -s emulator-5554 shell getprop ro.product.cpu.abilist
```

- **The output contains `x86_64`.** Build and install the app manually (Flutter only refuses to *launch* it):
  ```
  flutter build apk --debug --target-platform android-x64
  adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
  adb -s emulator-5554 shell monkey -p org.primeshows.primeshows 1
  ```
- **The output is `x86,armeabi-v7a,armeabi`** (most Android TV emulators). The emulator translates ARM apps, so build the 32-bit ARM version and install it yourself. The included script does all of it:
  ```
  tv_emulator.bat                 # or: tv_emulator.bat emulator-5556
  ```
  It runs `flutter build apk --release --target-platform android-arm`, installs the APK, starts the app and shows its logs. Hot reload isn't available this way. Use option 2 below for quick UI work.
- **The output is only `x86`.** Flutter can't run on that emulator. Use one of these:
  1. **A real TV or TV stick (best).** On the TV, open Settings › Device Preferences › About and press *Build* 7 times. Then go to Developer options and turn on *USB debugging* / *Network debugging*. On the PC run `adb connect <TV-IP>:5555` and accept the prompt on the TV. Then `flutter run` works normally (TVs use ARM, which Flutter supports).
  2. **TV mode on a normal emulator.** Create a 64-bit (x86_64) tablet emulator, e.g. *Pixel Tablet*, rotate it to landscape, then run:
     ```
     flutter run --dart-define=FORCE_TV=true
     ```
     The app shows the TV side menu and remote navigation. Use the keyboard arrows and Enter, or the emulator's extended controls › *Directional pad*.

**Installing on a real TV:** run `flutter build apk --release` and copy `build/app/outputs/flutter-apk/app-release.apk` to the TV (e.g. with a USB stick and a file manager, or `adb connect <tv-ip>` then `adb install app-release.apk`). Publishing in Google Play for TV requires the banner (already included) and Google's TV review.

## Making the website feel native inside the app

The app adds the class `in-app` to `<html>` on every page, so CSS alone is enough, for example to hide the site's own footer or install banner because the app already has navigation:

```css
.in-app .site-footer, .in-app .install-banner { display: none; }
```

In JavaScript, check the user agent:

```js
if (navigator.userAgent.includes('PrimeshowsApp')) { /* running in the app */ }
```

Or put CSS directly in `AppConfig.injectedCss`.

## Troubleshooting

- **The build asks for a different NDK or minSdk.** Apply the change that Gradle prints in `android/app/build.gradle.kts`, for example `ndkVersion = "27.0.12077973"` or `minSdk = 21`.
- **External links in a popup (`target="_blank"`) don't open.** Set `openExternalPopupsInBrowser = true` in `app_config.dart`, or add the host to `alwaysExternalHosts`.
- **A link the user taps is blocked as a redirect.** Set `blockAutoRedirects = false` in `app_config.dart`.
- **The TV emulator says "unsupported".** It is a 32-bit x86 image, which Flutter can't run. Use a real TV over Wi-Fi ADB, or a tablet emulator with `--dart-define=FORCE_TV=true` (see [Android TV](#android-tv)).
- **Something on the website can't be reached with the remote.** It needs to be a link, a button, or have `tabindex="0"` / `role="button"`. Elements inside video-player iframes are controlled by the player itself.
- **Debugging the website inside the app.** In debug builds, open `chrome://inspect` in desktop Chrome while the phone is connected (Safari › Develop on iOS).
