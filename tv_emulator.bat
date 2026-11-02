@echo off
REM Builds the app for 32-bit ARM and runs it on the Android TV emulator.
REM The x86 TV emulator runs ARM apps through translation; Flutters own
REM "flutter run" refuses it because it only checks the x86 part.
REM Usage:  tv_emulator.bat            (uses emulator-5554)
REM         tv_emulator.bat emulator-5556

setlocal
set DEVICE=%~1
if "%DEVICE%"=="" set DEVICE=emulator-5554
cd /d "%~dp0"

echo ==^> Building release APK for armeabi-v7a
call flutter build apk --release --target-platform android-arm || goto :error

echo ==^> Installing on %DEVICE%
adb -s %DEVICE% install -r build\app\outputs\flutter-apk\app-release.apk || goto :error

echo ==^> Starting Primeshows
adb -s %DEVICE% shell am start -n org.primeshows.primeshows/com.example.prime.MainActivity || goto :error

echo.
echo Running. App logs (Ctrl+C to stop):
adb -s %DEVICE% logcat -v brief -s flutter:V
goto :eof

:error
echo.
echo Failed - see the error above.
exit /b 1
