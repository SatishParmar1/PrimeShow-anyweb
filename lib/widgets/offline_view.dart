import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Shown when the page can't be loaded. The shell reloads automatically when
/// the connection comes back.
class OfflineView extends StatelessWidget {
  const OfflineView({
    super.key,
    required this.isOffline,
    required this.onRetry,
    this.retrying = false,
  });

  /// true → "No internet", false → generic "couldn't load" message.
  final bool isOffline;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final title = isOffline ? 'You\'re offline' : 'Couldn\'t load the page';
    final message = isOffline
        ? 'Check your Wi-Fi or mobile data. We\'ll reload automatically as soon as you\'re back online.'
        : 'Something went wrong while loading ${AppConfig.appName}. Please try again.';

    return Container(
      color: AppConfig.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConfig.primaryColor.withValues(alpha: 0.15),
            ),
            child: Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 44,
              color: AppConfig.accentColor,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppConfig.inactiveColor,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 180,
            height: 48,
            child: FilledButton.icon(
              onPressed: retrying ? null : onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: retrying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text(
                'Retry',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
