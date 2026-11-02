import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Device information and native helpers (Android only).
class AppDevice {
  AppDevice._();

  static const MethodChannel _channel = MethodChannel('primeshows/device');

  /// True on Android TV / Google TV. Set once by [init].
  static bool isTv = false;

  /// Test the TV interface on a phone/tablet emulator or device:
  ///   flutter run --dart-define=FORCE_TV=true
  static const bool forceTv = bool.fromEnvironment('FORCE_TV');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (forceTv) {
      isTv = true;
      return;
    }
    if (!isAndroid) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (e) {
      debugPrint('AppDevice.init failed: $e');
    }
  }

  /// Simulates a tap at physical-pixel coordinates in the Flutter view.
  static Future<void> tap(double x, double y) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('tap', {'x': x, 'y': y});
    } catch (e) {
      debugPrint('AppDevice.tap failed: $e');
    }
  }
}
