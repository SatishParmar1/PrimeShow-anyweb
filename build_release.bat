@echo off
REM Builds the release files for phones AND TVs (all chip types).
REM   APK -> share/sideload (phones, TVs)
REM   AAB -> upload to Google Play
setlocal
cd /d "%~dp0"

echo ==^> Getting packages
call flutter pub get || goto :error

echo ==^> Building release APK (arm, arm64, x86_64)
call flutter build apk --release || goto :error

echo ==^> Building release App Bundle for Google Play
call flutter build appbundle --release || goto :error

echo.
echo Done:
echo   APK: build\app\outputs\flutter-apk\app-release.apk
echo   AAB: build\app\outputs\bundle\release\app-release.aab
if not exist android\key.properties echo   NOTE: signed with the DEBUG key - add android\key.properties before uploading to Play (see README).
goto :eof

:error
echo.
echo Build failed - see the error above.
exit /b 1
