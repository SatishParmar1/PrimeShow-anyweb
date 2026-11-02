import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Branded loading overlay shown after the native splash until the first
/// page is ready. Fades out when [visible] becomes false.
class SplashOverlay extends StatelessWidget {
  const SplashOverlay({super.key, required this.visible, this.siteName});

  final bool visible;

  /// For websites other than Primeshows: shown under a small logo instead of
  /// the Primeshows splash image.
  final String? siteName;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: Container(
          color: AppConfig.backgroundColor,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (siteName == null)
                Image.asset(
                  'assets/icon/splash.png',
                  width: 230,
                  height: 230,
                  errorBuilder: (_, _, _) => const Text(
                    AppConfig.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else ...[
                Image.asset('assets/icon/logo_mark.png', width: 72, height: 72),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    siteName!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppConfig.accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
