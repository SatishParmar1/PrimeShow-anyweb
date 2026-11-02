import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../models/saved_site.dart';
import '../utils/app_device.dart';
import '../utils/link_handler.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/more_sheet.dart';
import '../widgets/offline_view.dart';
import '../widgets/splash_overlay.dart';
import '../widgets/tv_nav_rail.dart';

/// Shows one saved website in a WebView and wraps it with native navigation,
/// fullscreen video, offline handling and link routing.
///
/// primeshows.org gets its own tabs (Movies, TV Shows …); any other website
/// gets Home / Back / Forward / Reload.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.site, this.initialUrl});

  final SavedSite site;

  /// URL to open first (e.g. from a deep link). Defaults to the site's URL.
  final String? initialUrl;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefresh;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _splashTimer;

  late String _startUrl;
  late String _currentUrl;
  String? _pageTitle;
  String? _failedUrl;

  int _progress = 0;
  int _selectedTab = 0;
  int _webViewGeneration = 0;

  bool _showSplash = true;
  bool _hasError = false;
  bool _loadFailed = false;
  bool _isOffline = false;
  bool _retrying = false;
  bool _isFullscreen = false;

  /// Back-stack index of the Home page we loaded as a "back" fallback.
  /// Back never goes behind it (prevents loops), it asks to exit instead.
  int? _rootHistoryIndex;
  bool _markNextHomeAsRoot = false;

  DateTime? _lastUserNavigation;

  // ---- Android TV ----
  final FocusNode _webFocus = FocusNode(debugLabel: 'web');
  final GlobalKey _webAreaKey = GlobalKey();
  late final List<_TvItem> _tvItems = _buildTvItems();
  late final List<FocusNode> _railNodes = List.generate(
    _tvItems.length,
    (i) => FocusNode(debugLabel: 'rail-$i'),
  );

  bool get _isTv => AppDevice.isTv;

  // ---- The website shown by this shell ----
  String get _homeUrl => widget.site.url;
  bool get _isPrimeshows => widget.site.isPrimeshows;
  List<AppTab> get _tabs => _isPrimeshows ? AppConfig.tabs : AppConfig.genericTabs;

  /// Links to this website (and its sub-domains) stay in the app.
  bool _isInternal(Uri uri) =>
      LinkHandler.isWeb(uri) && widget.site.ownsHost(uri.host);

  String _urlForPath(String path) => Uri.parse(_homeUrl)
      .resolve(path.startsWith('/') ? path : '/$path')
      .toString();

  /// TV side menu: Primeshows pages, or Home/Back/Forward/Reload for other
  /// sites; always followed by "More" and "My websites".
  List<_TvItem> _buildTvItems() => [
        if (_isPrimeshows)
          for (final l in AppConfig.tvRailLinks)
            _TvItem(l.label, l.icon, TabAction.open, link: l)
        else ...const [
          _TvItem('Home', Icons.home_rounded, TabAction.home),
          _TvItem('Back', Icons.arrow_back_rounded, TabAction.back),
          _TvItem('Forward', Icons.arrow_forward_rounded, TabAction.forward),
          _TvItem('Reload', Icons.refresh_rounded, TabAction.reload),
        ],
        const _TvItem('More', Icons.grid_view_rounded, TabAction.more),
        const _TvItem('My websites', Icons.apps_rounded, null),
      ];

  int _tvSelectedIndex() {
    for (var i = 0; i < _tvItems.length; i++) {
      final item = _tvItems[i];
      if (item.link != null && item.link!.matches(_currentPath)) return i;
      if (item.action == TabAction.home && _isHome(_currentUrl)) return i;
    }
    return -1;
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isMobile => _isAndroid || _isIOS;

  int get _moreTabIndex => _tabs.indexWhere((t) => t.isMore);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _startUrl = widget.initialUrl ?? _homeUrl;
    _currentUrl = _startUrl;
    _selectedTab = _tabIndexFor(_startUrl, fallback: 0);
    _pullToRefresh = _createPullToRefresh();

    _splashTimer = Timer(AppConfig.splashTimeout, _hideSplash);
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _splashTimer?.cancel();
    if (_isFullscreen) _restoreSystemUi();
    _webFocus.dispose();
    for (final n in _railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Pause video/audio when the app goes to the background (Android).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !_isAndroid) return;
    if (state == AppLifecycleState.paused) {
      c.evaluateJavascript(source: _pauseMediaJs);
      c.pause();
      c.pauseTimers();
    } else if (state == AppLifecycleState.resumed) {
      c.resume();
      c.resumeTimers();
    }
  }

  PullToRefreshController? _createPullToRefresh() {
    if (!_isMobile || _isTv || !AppConfig.enablePullToRefresh) return null;
    return PullToRefreshController(
      settings: PullToRefreshSettings(
        color: AppConfig.accentColor,
        backgroundColor: AppConfig.surfaceColor,
      ),
      onRefresh: () async {
        final c = _controller;
        if (c == null) return;
        if (_isAndroid) {
          await c.reload();
        } else {
          final url = await c.getUrl();
          await c.loadUrl(
            urlRequest: URLRequest(url: url ?? WebUri(_currentUrl)),
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final offline = _isNoConnection(results);
    if (!mounted) return;
    setState(() => _isOffline = offline);
    // Connection is back → reload the page that failed.
    if (!offline && _hasError) _retry();
  }

  static bool _isNoConnection(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  // ---------------------------------------------------------------------------
  // URL / tab helpers
  // ---------------------------------------------------------------------------

  static String _pathOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '/';
    var path = uri.path.isEmpty ? '/' : uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  String get _currentPath => _pathOf(_currentUrl);

  bool _isHome(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && _isInternal(uri) && _pathOf(url) == _pathOf(_homeUrl);
  }

  int _tabIndexFor(String url, {required int fallback}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isInternal(uri)) return fallback;
    if (!_isPrimeshows) {
      return _isHome(url) ? _tabs.indexWhere((t) => t.action == TabAction.home) : -1;
    }
    final path = _pathOf(url);
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (!tab.isMore && tab.matches(path)) return i;
    }
    for (final link in AppConfig.menuLinks) {
      if (path == link.path || path.startsWith('${link.path}/')) {
        return _moreTabIndex;
      }
    }
    return -1;
  }

  void _onUrlChanged(WebUri? url) {
    if (url == null) return;
    final value = url.toString();
    if (!value.startsWith('http')) return;
    _currentUrl = value;
    if (!_isHome(value)) _markNextHomeAsRoot = false;
    final index = _tabIndexFor(value, fallback: _selectedTab);
    if (index != _selectedTab && mounted) {
      setState(() => _selectedTab = index);
    }
  }

  void _loadUrl(String url) {
    final c = _controller;
    if (c == null) {
      setState(() {
        _startUrl = url;
        _webViewGeneration++;
      });
      return;
    }
    c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Navigates inside the single-page app without a full reload when the
  /// page has a matching link; falls back to a normal page load.
  Future<void> _navigateTo(String path) async {
    final url = _urlForPath(path);
    final c = _controller;
    if (c == null || _hasError) {
      _loadUrl(url);
      return;
    }
    try {
      final result = await c.evaluateJavascript(source: _spaNavigateJs(path));
      if (result == true || result == 'true') return;
    } catch (_) {}
    _loadUrl(url);
  }

  void _scrollToTop() {
    _controller?.evaluateJavascript(
      source: "window.scrollTo({top: 0, behavior: 'smooth'});",
    );
  }

  void _hideSplash() {
    _splashTimer?.cancel();
    if (_showSplash && mounted) setState(() => _showSplash = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: AppConfig.surfaceColor,
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Bottom navigation & "More"
  // ---------------------------------------------------------------------------

  void _onTabTap(int index) {
    final tab = _tabs[index];
    switch (tab.action) {
      case TabAction.more:
        _openMore();
        return;
      case TabAction.home:
      case TabAction.back:
      case TabAction.forward:
      case TabAction.reload:
        _runAction(tab.action);
        return;
      case TabAction.open:
        break;
    }
    final path = tab.path!;
    // Tapping the tab of the page you're on scrolls to the top.
    if (!_hasError && _currentPath == path) {
      _scrollToTop();
      return;
    }
    setState(() => _selectedTab = index);
    _navigateTo(path);
  }

  /// Home / Back / Forward / Reload (bottom bar or TV menu).
  Future<void> _runAction(TabAction action) async {
    final c = _controller;
    switch (action) {
      case TabAction.home:
        if (!_hasError && _isHome(_currentUrl)) {
          _scrollToTop();
        } else {
          _loadUrl(_homeUrl);
        }
      case TabAction.back:
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else {
          _snack('No previous page');
        }
      case TabAction.forward:
        if (c != null && await c.canGoForward()) {
          await c.goForward();
        } else {
          _snack('No next page');
        }
      case TabAction.reload:
        if (_hasError || c == null) {
          _retry();
        } else {
          await c.reload();
        }
      case TabAction.more:
        await _openMore();
      case TabAction.open:
        break;
    }
  }

  /// Back to the "My websites" list.
  void _exitToSites() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _openMore() async {
    final action = await showMoreSheet(
      context,
      currentPath: _currentPath,
      links: _isPrimeshows ? AppConfig.menuLinks : const [],
    );
    if (action == null || !mounted) return;

    switch (action.type) {
      case MoreActionType.openPath:
        setState(() => _selectedTab = _moreTabIndex);
        await _navigateTo(action.path!);
      case MoreActionType.sites:
        _exitToSites();
      case MoreActionType.share:
        await _share();
      case MoreActionType.copyLink:
        await Clipboard.setData(ClipboardData(text: await _pageUrl()));
        _snack('Link copied');
      case MoreActionType.openInBrowser:
        await LinkHandler.openInBrowser(Uri.parse(await _pageUrl()));
      case MoreActionType.reload:
        if (_hasError) {
          _retry();
        } else {
          await _controller?.reload();
        }
      case MoreActionType.clearCache:
        await InAppWebViewController.clearAllCache();
        await _controller?.reload();
        _snack('Cache cleared');
    }
  }

  Future<String> _pageUrl() async {
    final url = await _controller?.getUrl();
    final value = url?.toString();
    return (value != null && value.startsWith('http')) ? value : _currentUrl;
  }

  Future<void> _share() async {
    final url = await _pageUrl();
    final title = (_pageTitle ?? '').trim();
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: title.isEmpty ? url : '$title\n$url',
        subject: title.isEmpty ? AppConfig.appName : title,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Back button
  // ---------------------------------------------------------------------------

  Future<void> _handleBack() async {
    final c = _controller;

    if (_isFullscreen) {
      await c?.evaluateJavascript(source: _exitFullscreenJs);
      return;
    }

    if (_isTv) {
      // Back in the side menu → return to the page.
      if (_railNodes.any((n) => n.hasFocus)) {
        _webFocus.requestFocus();
        return;
      }
      // Back inside a video player / text field → leave it first.
      try {
        final r = await c?.evaluateJavascript(
          source: 'window.__tvBack ? window.__tvBack() : false',
        );
        if (r == true || r == 'true') {
          _webFocus.requestFocus();
          return;
        }
      } catch (_) {}
    }

    if (c != null) {
      var canGoBack = await c.canGoBack();
      if (canGoBack && _rootHistoryIndex != null) {
        final history = await c.getCopyBackForwardList();
        final index = history?.currentIndex ?? 0;
        if (index <= _rootHistoryIndex!) canGoBack = false;
      }
      if (canGoBack) {
        await c.goBack();
        return;
      }
    }

    if (!mounted) return;
    // Not on the start page (or it failed on another page) → go to the start
    // page first. If the start page itself is what failed, leave instead.
    final failedOnHome = _hasError && _isHome(_failedUrl ?? _currentUrl);
    if (!failedOnHome && (!_isHome(_currentUrl) || _hasError)) {
      setState(() => _selectedTab = _tabIndexFor(_homeUrl, fallback: 0));
      _markNextHomeAsRoot = true;
      _loadUrl(_homeUrl);
      return;
    }

    // On the site's start page → back to "My websites".
    _exitToSites();
  }

  // ---------------------------------------------------------------------------
  // Errors / offline
  // ---------------------------------------------------------------------------

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final url = _failedUrl ?? _currentUrl;
    if (_controller == null) {
      _loadUrl(url);
    } else {
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _onMainFrameError(String url, WebResourceError error) async {
    // A cancelled navigation (e.g. the user tapped another link) isn't an error.
    final type = error.type.toString().toUpperCase();
    if (type.contains('CANCEL')) return;
    if (!url.startsWith('http')) return;

    _loadFailed = true;
    _failedUrl = url;
    _pullToRefresh?.endRefreshing();

    var offline = _isOffline;
    try {
      offline = _isNoConnection(await Connectivity().checkConnectivity());
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _isOffline = offline;
    });
    _hideSplash();
  }

  // ---------------------------------------------------------------------------
  // Fullscreen video
  // ---------------------------------------------------------------------------

  void _onEnterFullscreen() {
    setState(() => _isFullscreen = true);
    _pullToRefresh?.setEnabled(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (AppConfig.landscapeFullscreenVideo && !_isTv) {
      SystemChrome.setPreferredOrientations(
        _isIOS
            // iOS' native player rotates by itself; just allow landscape.
            ? const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      );
    }
  }

  void _onExitFullscreen() {
    setState(() => _isFullscreen = false);
    _pullToRefresh?.setEnabled(AppConfig.enablePullToRefresh);
    _restoreSystemUi();
    if (_isTv) _webFocus.requestFocus();
  }

  /// Normal system bars and orientation (after fullscreen video).
  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(
      AppConfig.lockPortrait && !_isTv
          ? const [DeviceOrientation.portraitUp]
          : DeviceOrientation.values,
    );
  }

  // ---------------------------------------------------------------------------
  // Link routing
  // ---------------------------------------------------------------------------

  bool _isUserInitiated(NavigationAction action) {
    if (action.hasGesture == true) return true;
    if (action.navigationType == NavigationType.LINK_ACTIVATED) return true;
    // Server redirect straight after a tap (e.g. tracking links).
    final last = _lastUserNavigation;
    if (action.isRedirect == true &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 3)) {
      return true;
    }
    return false;
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    NavigationAction action,
  ) async {
    final url = action.request.url;
    if (url == null) return NavigationActionPolicy.ALLOW;

    // Never touch iframes (video players live there).
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;

    final raw = url.toString();
    final userInitiated = _isUserInitiated(action);
    if (userInitiated) _lastUserNavigation = DateTime.now();
    final allowed = userInitiated || !AppConfig.blockAutoRedirects;

    // Android intent:// links.
    if (raw.toLowerCase().startsWith('intent:')) {
      if (allowed) {
        final fallback = await LinkHandler.openSpecial(raw, isInternal: _isInternal);
        if (fallback != null) _loadUrl(fallback);
      }
      return NavigationActionPolicy.CANCEL;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (LinkHandler.isWebViewScheme(uri)) return NavigationActionPolicy.ALLOW;
    if (_isInternal(uri)) return NavigationActionPolicy.ALLOW;

    if (LinkHandler.isWeb(uri)) {
      if (allowed) {
        await LinkHandler.openInBrowser(uri);
      } else {
        debugPrint('Blocked automatic redirect to $uri');
      }
      return NavigationActionPolicy.CANCEL;
    }

    // tel:, mailto:, whatsapp:, market:, …
    if (allowed) await LinkHandler.openSpecial(raw, isInternal: _isInternal);
    return NavigationActionPolicy.CANCEL;
  }

  /// `target="_blank"` and `window.open`.
  Future<bool> _onCreateWindow(CreateWindowAction action) async {
    final url = action.request.url;
    if (url == null) return false; // about:blank pop-unders → blocked
    final raw = url.toString();
    final userInitiated = action.hasGesture ?? true;
    final uri = Uri.tryParse(raw);

    if (uri != null && _isInternal(uri)) {
      _loadUrl(raw); // our own pages open in the same view
      return false;
    }
    if (!userInitiated) return false;

    if (uri != null && LinkHandler.isWeb(uri)) {
      if (AppConfig.openExternalPopupsInBrowser ||
          LinkHandler.isAlwaysExternal(uri)) {
        await LinkHandler.openInBrowser(uri);
      } else {
        debugPrint('Blocked popup to $uri');
      }
      return false;
    }
    if (uri != null && LinkHandler.isWebViewScheme(uri)) return false;

    final fallback = await LinkHandler.openSpecial(raw, isInternal: _isInternal);
    if (fallback != null) _loadUrl(fallback);
    return false;
  }

  // ---------------------------------------------------------------------------
  // WebView
  // ---------------------------------------------------------------------------

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        isInspectable: kDebugMode,
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        useShouldOverrideUrlLoading: true,
        useOnRenderProcessGone: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        allowsAirPlayForMediaPlayback: true,
        iframeAllowFullscreen: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        thirdPartyCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        applicationNameForUserAgent: _isTv
            ? '${AppConfig.userAgentSuffix} PrimeshowsTV'
            : AppConfig.userAgentSuffix,
        transparentBackground: true,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        allowsBackForwardNavigationGestures: true,
        allowsLinkPreview: false,
        disableDefaultErrorPage: true,
        safeBrowsingEnabled: true,
      );

  Widget _buildWebView() {
    return InAppWebView(
      key: ValueKey('webview-$_webViewGeneration'),
      initialUrlRequest: URLRequest(url: WebUri(_startUrl)),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _documentStartJs(tv: _isTv),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        if (_isTv)
          UserScript(
            source: _tvNavigationJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          ),
      ]),
      pullToRefreshController: _pullToRefresh,
      onWebViewCreated: (controller) {
        _controller = controller;
        if (_isTv) _addTvJavaScriptHandlers(controller);
      },
      onLoadStart: (controller, url) {
        _loadFailed = false;
        _onUrlChanged(url);
      },
      onLoadStop: (controller, url) async {
        _pullToRefresh?.endRefreshing();
        _onUrlChanged(url);
        if (!_loadFailed && mounted) {
          setState(() {
            _hasError = false;
            _failedUrl = null;
          });
        }
        if (!_loadFailed && _markNextHomeAsRoot && _isHome(_currentUrl)) {
          _markNextHomeAsRoot = false;
          final history = await controller.getCopyBackForwardList();
          _rootHistoryIndex = history?.currentIndex;
        }
        _hideSplash();
      },
      onProgressChanged: (controller, progress) {
        if (progress == 100) _pullToRefresh?.endRefreshing();
        if (progress >= 80) _hideSplash();
        if (mounted) setState(() => _progress = progress);
      },
      onUpdateVisitedHistory: (controller, url, isReload) => _onUrlChanged(url),
      onTitleChanged: (controller, title) => _pageTitle = title,
      shouldOverrideUrlLoading: (controller, action) =>
          _shouldOverrideUrlLoading(action),
      onCreateWindow: (controller, action) => _onCreateWindow(action),
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == false) return;
        _onMainFrameError(request.url.toString(), error);
      },
      onEnterFullscreen: (controller) => _onEnterFullscreen(),
      onExitFullscreen: (controller) => _onExitFullscreen(),
      onPermissionRequest: (controller, request) async {
        // Allow DRM-protected video; deny camera/microphone.
        final granted = request.resources
            .where((r) => r == PermissionResourceType.PROTECTED_MEDIA_ID)
            .toList();
        return PermissionResponse(
          resources: granted,
          action: granted.isEmpty
              ? PermissionResponseAction.DENY
              : PermissionResponseAction.GRANT,
        );
      },
      // Crash recovery: the system killed the WebView → build a fresh one.
      onRenderProcessGone: (controller, detail) {
        _controller = null;
        if (!mounted) return;
        setState(() {
          _startUrl = _currentUrl;
          _pullToRefresh = _createPullToRefresh();
          _webViewGeneration++;
        });
      },
      onWebContentProcessDidTerminate: (controller) => controller.reload(),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildWebArea() {
    final showProgress =
        _progress < 100 && !_showSplash && !_isFullscreen && !_hasError;
    return Stack(
      children: [
        Positioned.fill(
          child: SizedBox.expand(key: _webAreaKey, child: _buildWebView()),
        ),
        if (_hasError)
          Positioned.fill(
            child: OfflineView(
              isOffline: _isOffline,
              retrying: _retrying,
              onRetry: _retry,
            ),
          ),
        if (showProgress)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              color: AppConfig.accentColor,
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneLayout() {
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: false,
        child: _buildWebArea(),
      ),
      bottomNavigationBar: _isFullscreen
          ? null
          : AppBottomBar(tabs: _tabs, currentIndex: _selectedTab, onTap: _onTabTap),
    );
  }

  Widget _buildTvLayout() {
    final selected = _tvSelectedIndex();
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      body: Row(
        children: [
          // Hidden (not removed) during fullscreen video so the WebView
          // keeps its place in the tree.
          Visibility(
            visible: !_isFullscreen,
            child: TvNavRail(
              entries: [for (final t in _tvItems) TvRailEntry(t.label, t.icon)],
              focusNodes: _railNodes,
              selectedIndex: selected,
              onSelect: _onTvRailSelect,
              onExit: () => _webFocus.requestFocus(),
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: _webFocus,
              autofocus: true,
              onKeyEvent: _onTvKey,
              child: _buildWebArea(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Stack(
        children: [
          _isTv ? _buildTvLayout() : _buildPhoneLayout(),
          Positioned.fill(
            child: SplashOverlay(
              visible: _showSplash,
              siteName: _isPrimeshows ? null : widget.site.name,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Android TV: remote control (D-pad)
  // ---------------------------------------------------------------------------

  void _focusRail() {
    if (!_isTv || _isFullscreen || _railNodes.isEmpty) return;
    final selected = _tvSelectedIndex();
    _railNodes[selected < 0 ? 0 : selected].requestFocus();
  }

  Future<void> _onTvRailSelect(int index) async {
    final item = _tvItems[index];
    final action = item.action;
    if (action == null) {
      _exitToSites(); // "My websites"
      return;
    }
    if (action == TabAction.more) {
      await _openMore();
      if (mounted) _webFocus.requestFocus();
      return;
    }
    if (action != TabAction.open) {
      _webFocus.requestFocus();
      await _runAction(action);
      return;
    }
    final link = item.link!;
    _webFocus.requestFocus();
    if (!_hasError && _currentPath == link.path) {
      _scrollToTop();
    } else {
      await _navigateTo(link.path);
    }
  }

  void _addTvJavaScriptHandlers(InAppWebViewController controller) {
    // The page reached its left edge → move into the side menu.
    controller.addJavaScriptHandler(
      handlerName: 'tvEdge',
      callback: (List<dynamic> args) {
        if (args.isNotEmpty && args.first == 'left') _focusRail();
        return null;
      },
    );
    // OK pressed on something that needs a real tap (video player, text field).
    controller.addJavaScriptHandler(
      handlerName: 'tvTap',
      callback: (List<dynamic> args) {
        if (args.length >= 2 && args[0] is num && args[1] is num) {
          _nativeTap((args[0] as num).toDouble(), (args[1] as num).toDouble());
        }
        return null;
      },
    );
  }

  /// Keys from the remote while the page (not the native WebView) has focus.
  KeyEventResult _onTvKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;

    final String? dir = key == LogicalKeyboardKey.arrowUp
        ? 'up'
        : key == LogicalKeyboardKey.arrowDown
            ? 'down'
            : key == LogicalKeyboardKey.arrowLeft
                ? 'left'
                : key == LogicalKeyboardKey.arrowRight
                    ? 'right'
                    : null;
    if (dir != null) {
      if (isDown) _tvNavigate(dir);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) _tvSelect();
      return KeyEventResult.handled;
    }

    final String? media = key == LogicalKeyboardKey.mediaPlayPause ||
            key == LogicalKeyboardKey.mediaPlay ||
            key == LogicalKeyboardKey.mediaPause
        ? 'toggle'
        : key == LogicalKeyboardKey.mediaFastForward
            ? 'ff'
            : key == LogicalKeyboardKey.mediaRewind
                ? 'rw'
                : null;
    if (media != null) {
      if (event is KeyDownEvent) {
        _controller?.evaluateJavascript(
          source: "window.__tvMedia && window.__tvMedia('$media');",
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _tvNavigate(String dir) async {
    final c = _controller;
    if (c == null || _hasError) {
      if (dir == 'left') _focusRail();
      return;
    }
    try {
      final r = await c.evaluateJavascript(
        source: "window.__tvNav ? window.__tvNav('$dir') : 'edge'",
      );
      if (r?.toString() == 'edge' && dir == 'left') _focusRail();
    } catch (_) {
      if (dir == 'left') _focusRail();
    }
  }

  Future<void> _tvSelect() async {
    if (_hasError) {
      _retry();
      return;
    }
    final c = _controller;
    if (c == null) return;
    try {
      final r = await c.evaluateJavascript(
        source: 'window.__tvSelect ? window.__tvSelect() : null',
      );
      if (r == null) return;
      final data = r is String ? jsonDecode(r) : r;
      if (data is Map && data['tap'] == true) {
        await _nativeTap(
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('TV select failed: $e');
    }
  }

  /// Real touch at page coordinates (CSS px = logical px).
  Future<void> _nativeTap(double x, double y) async {
    final box = _webAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final origin = box.localToGlobal(Offset.zero);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    await AppDevice.tap((origin.dx + x) * dpr, (origin.dy + y) * dpr);
  }

  // ---------------------------------------------------------------------------
  // JavaScript
  // ---------------------------------------------------------------------------

  /// Runs before the page's own scripts: marks the page as running in the
  /// app (`html.in-app`) and injects [AppConfig.injectedCss].
  static String _documentStartJs({required bool tv}) => '''
(function () {
  var css = ${jsonEncode(AppConfig.injectedCss)};
  var classes = ${tv ? "['in-app', 'in-tv']" : "['in-app']"};
  var root = document.documentElement;
  function mark() {
    if (!root) return;
    for (var i = 0; i < classes.length; i++) {
      if (!root.classList.contains(classes[i])) root.classList.add(classes[i]);
    }
  }
  function addCss() {
    if (!css || document.getElementById('__primeshows_app_css')) return;
    var style = document.createElement('style');
    style.id = '__primeshows_app_css';
    style.textContent = css;
    (document.head || root).appendChild(style);
  }
  mark();
  addCss();
  try {
    new MutationObserver(mark).observe(root, { attributes: true, attributeFilter: ['class'] });
  } catch (e) {}
  document.addEventListener('DOMContentLoaded', function () { mark(); addCss(); });
  window.addEventListener('load', function () { mark(); addCss(); });
})();
''';

  /// Android TV: moves a highlight between links/buttons with the remote's
  /// arrow keys ("spatial navigation") and activates it with OK.
  /// Written in ES5 so it also runs on older TV WebViews.
  static final String _tvNavigationJs = r'''
(function () {
  if (window.__tvNav) return;
  var COLOR = '__COLOR__';
  var SEL = 'a[href],button,input:not([type=hidden]),select,textarea,iframe,video,summary,' +
    '[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[role=checkbox],' +
    '[tabindex]:not([tabindex="-1"]),[contenteditable=true]';
  var TAP_TAGS = { IFRAME: 1, VIDEO: 1, TEXTAREA: 1, SELECT: 1 };
  var cur = null;

  var style = document.createElement('style');
  style.textContent =
    '.__tvf{outline:3px solid ' + COLOR + ' !important;outline-offset:-3px !important;' +
    'box-shadow:0 0 0 3px rgba(76,155,255,.35),0 0 26px rgba(76,155,255,.6) !important;' +
    'border-radius:10px;transition:box-shadow .12s ease}' +
    'iframe.__tvf,video.__tvf{outline-offset:-5px !important}';
  (document.head || document.documentElement).appendChild(style);

  function call() {
    try {
      var h = window.flutter_inappwebview;
      if (h && h.callHandler) h.callHandler.apply(h, arguments);
    } catch (e) {}
  }

  function isTextInput(el) {
    if (!el) return false;
    if (el.tagName === 'INPUT') {
      return !/^(button|submit|checkbox|radio|reset|image|range|color|file)$/i.test(el.type || '');
    }
    return el.tagName === 'TEXTAREA' || el.isContentEditable === true;
  }

  function needsTap(el) {
    return !!TAP_TAGS[el.tagName] || isTextInput(el);
  }

  function inHorizontalScroller(el) {
    var p = el.parentElement;
    while (p && p !== document.body && p !== document.documentElement) {
      if (p.scrollWidth > p.clientWidth + 2) {
        var o = getComputedStyle(p).overflowX;
        if (o === 'auto' || o === 'scroll') return true;
      }
      p = p.parentElement;
    }
    return false;
  }

  function visible(el) {
    if (el.disabled) return false;
    if (el.closest && el.closest('[aria-hidden="true"],[inert],[hidden]')) return false;
    var r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    var cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || parseFloat(cs.opacity) === 0) return false;
    // Off-screen sideways: only allowed inside horizontal carousels
    // (keeps hidden slide-out menus out of reach).
    if ((r.right <= 0 || r.left >= window.innerWidth) && !inHorizontalScroller(el)) return false;
    return true;
  }

  function valid(el) {
    return !!el && document.documentElement.contains(el) && visible(el);
  }

  function candidates() {
    var all = document.querySelectorAll(SEL), out = [];
    for (var i = 0; i < all.length; i++) if (visible(all[i])) out.push(all[i]);
    return out;
  }

  function firstInView() {
    var c = candidates(), best = null, bestScore = Infinity;
    for (var i = 0; i < c.length; i++) {
      var r = c[i].getBoundingClientRect();
      if (r.top >= 0 && r.bottom <= window.innerHeight && r.left >= 0 && r.right <= window.innerWidth) {
        var s = r.top * 2 + r.left;
        if (s < bestScore) { bestScore = s; best = c[i]; }
      }
    }
    return best || c[0] || null;
  }

  function setCur(el) {
    if (cur && cur.classList) cur.classList.remove('__tvf');
    cur = el;
    el.classList.add('__tvf');
    // Don't move keyboard focus into iframes/inputs – that would trap the remote.
    if (!needsTap(el)) {
      try {
        if (!el.hasAttribute('tabindex') && !/^(A|BUTTON|SUMMARY)$/.test(el.tagName)) {
          el.setAttribute('tabindex', '-1');
        }
        el.focus({ preventScroll: true });
      } catch (e) {}
    }
    try {
      el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
    } catch (e) {
      el.scrollIntoView(false);
    }
  }

  // Lower is better; -1 = not in that direction.
  function score(a, r, dir) {
    var acx = (a.left + a.right) / 2, acy = (a.top + a.bottom) / 2;
    var rcx = (r.left + r.right) / 2, rcy = (r.top + r.bottom) / 2;
    var main, cross, overlap;
    if (dir === 'right') {
      if (rcx <= acx + 1 || r.right <= a.right) return -1;
      main = Math.max(0, r.left - a.right); cross = Math.abs(rcy - acy);
      overlap = Math.min(a.bottom, r.bottom) - Math.max(a.top, r.top);
    } else if (dir === 'left') {
      if (rcx >= acx - 1 || r.left >= a.left) return -1;
      main = Math.max(0, a.left - r.right); cross = Math.abs(rcy - acy);
      overlap = Math.min(a.bottom, r.bottom) - Math.max(a.top, r.top);
    } else if (dir === 'down') {
      if (rcy <= acy + 1 || r.bottom <= a.bottom) return -1;
      main = Math.max(0, r.top - a.bottom); cross = Math.abs(rcx - acx);
      overlap = Math.min(a.right, r.right) - Math.max(a.left, r.left);
    } else {
      if (rcy >= acy - 1 || r.top >= a.top) return -1;
      main = Math.max(0, a.top - r.bottom); cross = Math.abs(rcx - acx);
      overlap = Math.min(a.right, r.right) - Math.max(a.left, r.left);
    }
    return main + cross * (overlap > 0 ? 0.3 : 2);
  }

  function scrollPage(dir) {
    var h = window.innerHeight * 0.6;
    var max = document.documentElement.scrollHeight - window.innerHeight;
    if (dir === 'up' && window.scrollY > 0) {
      window.scrollBy({ top: -h, behavior: 'smooth' }); return 'scrolled';
    }
    if (dir === 'down' && window.scrollY < max - 2) {
      window.scrollBy({ top: h, behavior: 'smooth' }); return 'scrolled';
    }
    return 'edge';
  }

  window.__tvNav = function (dir) {
    if (!valid(cur)) {
      var f = firstInView();
      if (f) { setCur(f); return 'moved'; }
      return scrollPage(dir);
    }
    var a = cur.getBoundingClientRect(), c = candidates(), best = null, bestScore = Infinity;
    for (var i = 0; i < c.length; i++) {
      var el = c[i];
      if (el === cur || el.contains(cur) || cur.contains(el)) continue;
      var s = score(a, el.getBoundingClientRect(), dir);
      if (s >= 0 && s < bestScore) { bestScore = s; best = el; }
    }
    if (best) { setCur(best); return 'moved'; }
    return scrollPage(dir);
  };

  window.__tvSelect = function () {
    if (!valid(cur)) {
      var f = firstInView();
      if (f) setCur(f);
      return JSON.stringify({ none: true });
    }
    if (needsTap(cur)) {
      var r = cur.getBoundingClientRect();
      var x = Math.min(Math.max(r.left + r.width / 2, 1), window.innerWidth - 1);
      var y = Math.min(Math.max(r.top + r.height / 2, 1), window.innerHeight - 1);
      return JSON.stringify({ tap: true, x: x, y: y });
    }
    cur.click();
    return JSON.stringify({ clicked: true });
  };

  window.__tvBack = function () {
    var ae = document.activeElement;
    if (ae && (ae.tagName === 'IFRAME' || ae.tagName === 'VIDEO' || isTextInput(ae))) {
      try { ae.blur(); } catch (e) {}
      try { window.focus(); } catch (e) {}
      return true;
    }
    return false;
  };

  window.__tvMedia = function (cmd) {
    var v = document.querySelector('video');
    if (!v) return false;
    try {
      if (cmd === 'toggle') { if (v.paused) v.play(); else v.pause(); }
      else if (cmd === 'ff') v.currentTime += 10;
      else if (cmd === 'rw') v.currentTime -= 10;
    } catch (e) {}
    return true;
  };

  // When the WebView itself has keyboard focus (e.g. after OK on a text
  // field), the remote's keys arrive here instead of in Flutter.
  document.addEventListener('keydown', function (e) {
    var k = e.key || '', kc = e.keyCode;
    var dir = (k === 'ArrowUp' || kc === 38) ? 'up'
      : (k === 'ArrowDown' || kc === 40) ? 'down'
      : (k === 'ArrowLeft' || kc === 37) ? 'left'
      : (k === 'ArrowRight' || kc === 39) ? 'right' : null;
    var typing = isTextInput(document.activeElement);
    if (dir) {
      if (typing && (dir === 'left' || dir === 'right')) return; // move the caret
      e.preventDefault();
      e.stopPropagation();
      if (typing) { try { document.activeElement.blur(); } catch (x) {} }
      if (window.__tvNav(dir) === 'edge' && dir === 'left') call('tvEdge', 'left');
      return;
    }
    if ((k === 'Enter' || kc === 13) && !typing && valid(cur)) {
      e.preventDefault();
      e.stopPropagation();
      var res = JSON.parse(window.__tvSelect());
      if (res.tap) call('tvTap', res.x, res.y);
    }
  }, true);
})();
'''.replaceAll('__COLOR__', AppConfig.tvFocusColor);

  static String _spaNavigateJs(String path) => '''
(function (p) {
  try {
    var full = location.origin + p;
    var links = document.querySelectorAll('a[href]');
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var h = a.getAttribute('href');
      if ((h === p || h === full) && (!a.target || a.target === '_self')) {
        a.click();
        return true;
      }
    }
  } catch (e) {}
  return false;
})(${jsonEncode(path)});
''';

  static const String _pauseMediaJs = '''
document.querySelectorAll('video, audio').forEach(function (m) {
  try { m.pause(); } catch (e) {}
});
''';

  static const String _exitFullscreenJs = '''
if (document.fullscreenElement && document.exitFullscreen) {
  document.exitFullscreen();
} else if (document.webkitFullscreenElement && document.webkitExitFullscreen) {
  document.webkitExitFullscreen();
}
''';
}

/// An entry of the TV side menu. `action == null` means "My websites".
class _TvItem {
  const _TvItem(this.label, this.icon, this.action, {this.link});

  final String label;
  final IconData icon;
  final TabAction? action;

  /// Primeshows page for [TabAction.open].
  final MenuLink? link;
}
