import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// Parsed Android `intent://` URL.
///
/// Format: `intent://HOST/PATH#Intent;scheme=SCHEME;package=PKG;S.browser_fallback_url=URL;end`
class IntentLink {
  const IntentLink({this.targetUri, this.packageName, this.fallbackUrl});

  /// `SCHEME://HOST/PATH`, if a scheme was given.
  final Uri? targetUri;
  final String? packageName;
  final String? fallbackUrl;

  static IntentLink? parse(String raw) {
    if (!raw.toLowerCase().startsWith('intent:')) return null;
    final hashIndex = raw.indexOf('#Intent;');
    final base = hashIndex >= 0 ? raw.substring(0, hashIndex) : raw;
    final params = <String, String>{};
    if (hashIndex >= 0) {
      for (final part in raw.substring(hashIndex + '#Intent;'.length).split(';')) {
        if (part == 'end') break;
        final eq = part.indexOf('=');
        if (eq > 0) params[part.substring(0, eq)] = part.substring(eq + 1);
      }
    }

    Uri? target;
    final scheme = params['scheme'];
    if (scheme != null && scheme.isNotEmpty) {
      var rest = base.substring('intent:'.length);
      if (rest.startsWith('//')) rest = rest.substring(2);
      target = Uri.tryParse('$scheme://$rest');
    }

    String? fallback = params['S.browser_fallback_url'];
    if (fallback != null) {
      try {
        fallback = Uri.decodeComponent(fallback);
      } catch (_) {}
    }

    return IntentLink(
      targetUri: target,
      packageName: params['package'],
      fallbackUrl: fallback,
    );
  }
}

/// Decides whether a URL stays in the app, goes to another app, or is blocked.
class LinkHandler {
  LinkHandler._();

  /// Schemes the WebView handles itself.
  static const Set<String> _webViewSchemes = {
    'about',
    'data',
    'blob',
    'javascript',
    'file',
  };

  static bool isWeb(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  /// primeshows.org (and sub-domain) http(s) links.
  static bool isInternal(Uri uri) =>
      isWeb(uri) && AppConfig.isAllowedHost(uri.host);

  /// about:blank, data:, blob:, javascript: … – let the WebView deal with it.
  static bool isWebViewScheme(Uri uri) => _webViewSchemes.contains(uri.scheme);

  /// Converts an incoming deep link into a URL to load in the app,
  /// or `null` if it is not ours.
  ///
  /// * `https://primeshows.org/movie/123`  → same URL
  /// * `primeshows://movie/123`            → `https://primeshows.org/movie/123`
  static String? deepLinkToUrl(Uri uri) {
    if (isInternal(uri)) return uri.replace(scheme: 'https').toString();
    if (uri.scheme == AppConfig.customScheme) {
      final path = '/${uri.host}${uri.path}'.replaceAll(RegExp(r'/+'), '/');
      final url = AppConfig.homeUri.replace(
        path: path,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      );
      return url.toString();
    }
    return null;
  }

  /// Opens a web URL in the external browser.
  static Future<bool> openInBrowser(Uri uri) => _launch(uri);

  /// Opens tel:, mailto:, sms:, whatsapp:, market:, intent:// and other app
  /// links. Returns a primeshows.org URL to load in the WebView if an
  /// `intent://` link falls back to our own site, otherwise `null`.
  static Future<String?> openSpecial(
    String raw, {
    bool Function(Uri uri)? isInternal,
  }) async {
    final intent = IntentLink.parse(raw);
    if (intent != null) {
      final target = intent.targetUri;
      if (target != null && await _launch(target, nonBrowser: !isWeb(target))) {
        return null;
      }
      final fallback = intent.fallbackUrl;
      if (fallback != null) {
        final f = Uri.tryParse(fallback);
        if (f != null && isWeb(f)) {
          if ((isInternal ?? LinkHandler.isInternal)(f)) return f.toString();
          await _launch(f);
          return null;
        }
      }
      final pkg = intent.packageName;
      if (pkg != null && pkg.isNotEmpty) {
        if (!await _launch(Uri.parse('market://details?id=$pkg'))) {
          await _launch(Uri.parse('https://play.google.com/store/apps/details?id=$pkg'));
        }
      }
      return null;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) await _launch(uri);
    return null;
  }

  /// Hosts that always open in their own app / the browser when tapped,
  /// even from a popup (WhatsApp, Telegram, stores, socials …).
  static bool isAlwaysExternal(Uri uri) {
    final h = uri.host.toLowerCase();
    for (final d in AppConfig.alwaysExternalHosts) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  static Future<bool> _launch(Uri uri, {bool nonBrowser = false}) async {
    try {
      return await launchUrl(
        uri,
        mode: nonBrowser
            ? LaunchMode.externalNonBrowserApplication
            : LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('LinkHandler: could not open $uri ($e)');
      return false;
    }
  }
}
