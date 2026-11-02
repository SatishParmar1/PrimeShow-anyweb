import 'package:flutter/material.dart';

/// What a navigation tab does.
enum TabAction {
  /// Opens [AppTab.path] on the site.
  open,

  /// Opens the "More" sheet.
  more,

  /// Goes to the site's start page.
  home,
  back,
  forward,
  reload,
}

/// A tab in the native bottom navigation bar.
class AppTab {
  const AppTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.path,
    this.action = TabAction.open,
    this.matchPaths = const [],
    this.exactMatch = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Site path to open (for [TabAction.open]).
  final String? path;

  final TabAction action;

  /// Paths that make this tab active. A path matches when the current path
  /// equals it or starts with `"$path/"`.
  final List<String> matchPaths;

  /// Only the exact path counts (used for Home, "/").
  final bool exactMatch;

  bool get isMore => action == TabAction.more;

  bool matches(String currentPath) {
    if (action != TabAction.open || path == null) return false;
    final candidates = matchPaths.isEmpty && path != null ? [path!] : matchPaths;
    for (final p in candidates) {
      if (exactMatch) {
        if (currentPath == p) return true;
      } else if (currentPath == p || currentPath.startsWith('$p/')) {
        return true;
      }
    }
    return false;
  }
}

/// A link shown in the "More" sheet.
class MenuLink {
  const MenuLink(this.label, this.icon, this.path, {this.alsoMatch = const []});
  final String label;
  final IconData icon;
  final String path;

  /// Extra paths that count as this page (e.g. `/movie/123` for Movies).
  final List<String> alsoMatch;

  bool matches(String currentPath) {
    if (path == '/') return currentPath == '/';
    for (final p in [path, ...alsoMatch]) {
      if (currentPath == p || currentPath.startsWith('$p/')) return true;
    }
    return false;
  }
}

/// ---------------------------------------------------------------------------
///  ALL APP SETTINGS LIVE HERE
/// ---------------------------------------------------------------------------
class AppConfig {
  AppConfig._();

  // ---- Website -------------------------------------------------------------
  static const String appName = 'Primeshows';
  static const String homeUrl = 'https://primeshows.org/';

  /// Domains that stay inside the app. Sub-domains are allowed automatically
  /// (e.g. `www.primeshows.org`, `cdn.primeshows.org`).
  static const List<String> allowedDomains = ['primeshows.org'];

  /// Custom URL scheme for deep links, e.g. `primeshows://movies`.
  static const String customScheme = 'primeshows';

  /// Appended to the WebView user agent so the site can detect the app.
  static const String userAgentSuffix = 'PrimeshowsApp/1.0';

  // ---- Behaviour -----------------------------------------------------------
  /// Lock the app to portrait. Fullscreen video always rotates to landscape.
  static const bool lockPortrait = true;

  /// Rotate to landscape when a video goes fullscreen.
  static const bool landscapeFullscreenVideo = true;

  /// `target="_blank"` / `window.open` links to OTHER domains:
  ///   false → blocked (most of them are ads)
  ///   true  → opened in the external browser when the user tapped them
  static const bool openExternalPopupsInBrowser = false;

  /// Hosts that always open externally when the user taps a link to them,
  /// even inside a popup (share buttons, app stores, socials).
  static const List<String> alwaysExternalHosts = [
    'wa.me',
    'whatsapp.com',
    't.me',
    'telegram.me',
    'play.google.com',
    'apps.apple.com',
    'facebook.com',
    'twitter.com',
    'x.com',
    'instagram.com',
    'youtube.com',
    'discord.gg',
    'discord.com',
    'reddit.com',
    'themoviedb.org',
  ];

  /// Block automatic (non-tap) redirects of the main page to other domains.
  static const bool blockAutoRedirects = true;

  static const bool enablePullToRefresh = true;

  /// The splash overlay is removed after the first page load, or after this
  /// timeout at the latest.
  static const Duration splashTimeout = Duration(seconds: 10);

  // ---- Colours (taken from primeshows.org) ---------------------------------
  static const Color backgroundColor = Color(0xFF00040A);
  static const Color surfaceColor = Color(0xFF0A1019);
  static const Color navBarColor = Color(0xFF080D15);
  static const Color primaryColor = Color(0xFF1657A6);
  static const Color accentColor = Color(0xFF4C9BFF);
  static const Color inactiveColor = Color(0xFF8A93A6);

  // ---- Bottom navigation ---------------------------------------------------
  static const List<AppTab> tabs = [
    AppTab(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      path: '/',
      exactMatch: true,
    ),
    AppTab(
      label: 'Movies',
      icon: Icons.movie_outlined,
      activeIcon: Icons.movie_rounded,
      path: '/movies',
      matchPaths: ['/movies', '/movie'],
    ),
    AppTab(
      label: 'TV Shows',
      icon: Icons.live_tv_outlined,
      activeIcon: Icons.live_tv_rounded,
      path: '/tv',
      matchPaths: ['/tv'],
    ),
    AppTab(
      label: 'Search',
      icon: Icons.search_rounded,
      activeIcon: Icons.manage_search_rounded,
      path: '/search',
    ),
    AppTab(
      label: 'More',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      action: TabAction.more,
    ),
  ];

  /// Bottom bar for websites the user added themselves (not primeshows.org).
  static const List<AppTab> genericTabs = [
    AppTab(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      action: TabAction.home,
    ),
    AppTab(
      label: 'Back',
      icon: Icons.arrow_back_rounded,
      activeIcon: Icons.arrow_back_rounded,
      action: TabAction.back,
    ),
    AppTab(
      label: 'Forward',
      icon: Icons.arrow_forward_rounded,
      activeIcon: Icons.arrow_forward_rounded,
      action: TabAction.forward,
    ),
    AppTab(
      label: 'Reload',
      icon: Icons.refresh_rounded,
      activeIcon: Icons.refresh_rounded,
      action: TabAction.reload,
    ),
    AppTab(
      label: 'More',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      action: TabAction.more,
    ),
  ];

  // ---- "More" sheet --------------------------------------------------------
  static const List<MenuLink> menuLinks = [
    MenuLink('Trending', Icons.local_fire_department_outlined, '/trending'),
    MenuLink('Genres', Icons.category_outlined, '/genres'),
    MenuLink('Anime', Icons.auto_awesome_outlined, '/anime'),
    MenuLink('Live TV', Icons.connected_tv_outlined, '/live-tv'),
    MenuLink('Sports', Icons.sports_soccer_outlined, '/sports'),
    MenuLink('FAQ', Icons.help_outline_rounded, '/faq'),
    MenuLink('Contact', Icons.mail_outline_rounded, '/contact'),
    MenuLink('Privacy', Icons.privacy_tip_outlined, '/privacy'),
    MenuLink('Terms', Icons.description_outlined, '/terms'),
  ];

  // ---- Android TV ----------------------------------------------------------
  /// Side menu shown on Android TV instead of the bottom bar. A "More" item
  /// (FAQ, Contact, Share, Reload …) is added at the end automatically.
  static const List<MenuLink> tvRailLinks = [
    MenuLink('Home', Icons.home_rounded, '/'),
    MenuLink('Search', Icons.search_rounded, '/search'),
    MenuLink('Movies', Icons.movie_rounded, '/movies', alsoMatch: ['/movie']),
    MenuLink('TV Shows', Icons.live_tv_rounded, '/tv'),
    MenuLink('Trending', Icons.local_fire_department_rounded, '/trending'),
    MenuLink('Live TV', Icons.connected_tv_rounded, '/live-tv'),
    MenuLink('Sports', Icons.sports_soccer_rounded, '/sports'),
    MenuLink('Anime', Icons.auto_awesome_rounded, '/anime'),
    MenuLink('Genres', Icons.category_rounded, '/genres'),
  ];

  /// Focus ring colour for the remote-control (D-pad) cursor on TV.
  static const String tvFocusColor = '#4C9BFF';

  // ---- CSS injected into every page ---------------------------------------
  /// Use the `.in-app` class (added to <html>) to target the app only.
  static const String injectedCss = '''
html { -webkit-tap-highlight-color: transparent; }
html.in-app body { -webkit-touch-callout: none; }
''';

  // ---- Helpers -------------------------------------------------------------
  static Uri get homeUri => Uri.parse(homeUrl);

  static String urlForPath(String path) =>
      homeUri.resolve(path.startsWith('/') ? path : '/$path').toString();

  static bool isAllowedHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();
    for (final d in allowedDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }
}
