@echo off
REM One-time project setup for the Primeshows app (Windows).
cd /d "%~dp0"

echo ==^> Generating any missing Android/iOS platform files (existing files are kept)
call flutter create --platforms=android,ios --org org.primeshows --project-name prime . || goto :error

echo ==^> Getting packages
call flutter pub get || goto :error

echo ==^> Generating launcher icons
call dart run flutter_launcher_icons || goto :error

echo ==^> Generating native splash screen
call dart run flutter_native_splash:create || goto :error

echo.
echo Done. Run the app with:  flutter run
goto :eof

:error
echo.
echo Setup failed - see the error above.
exit /b 1
