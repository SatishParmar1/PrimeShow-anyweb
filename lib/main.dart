import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'screens/sites_home.dart';
import 'utils/app_device.dart';
import 'utils/link_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppDevice.init();

  // TVs are always landscape – never lock them to portrait.
  await SystemChrome.setPreferredOrientations(
    AppConfig.lockPortrait && !AppDevice.isTv
        ? const [DeviceOrientation.portraitUp]
        : DeviceOrientation.values,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_overlayStyle);

  runApp(PrimeshowsApp(initialUrl: await _initialDeepLink()));
}

const SystemUiOverlayStyle _overlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light, // Android
  statusBarBrightness: Brightness.dark, // iOS
  systemNavigationBarColor: AppConfig.navBarColor,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: Colors.transparent,
);

/// The primeshows.org link the app was opened with, if any.
Future<String?> _initialDeepLink() async {
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!isMobile) return null;
  try {
    final uri = await AppLinks()
        .getInitialLink()
        .timeout(const Duration(seconds: 2));
    return uri == null ? null : LinkHandler.deepLinkToUrl(uri);
  } catch (_) {
    return null;
  }
}

class PrimeshowsApp extends StatelessWidget {
  const PrimeshowsApp({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppConfig.primaryColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppConfig.accentColor,
      surface: AppConfig.surfaceColor,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: AppConfig.backgroundColor,
          focusColor: AppConfig.primaryColor.withValues(alpha: 0.55),
          snackBarTheme: const SnackBarThemeData(
            contentTextStyle: TextStyle(color: Colors.white),
          ),
        ),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: AppConfig.backgroundColor,
        ),
        home: SitesHome(initialUrl: initialUrl),
      ),
    );
  }
}
