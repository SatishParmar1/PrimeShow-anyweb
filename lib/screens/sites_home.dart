import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/saved_site.dart';
import '../services/site_store.dart';
import '../utils/app_device.dart';
import '../utils/link_handler.dart';
import '../widgets/site_card.dart';
import '../widgets/site_dialogs.dart';
import 'web_shell.dart';

/// Start screen: the user's saved websites (stored on the device).
/// Tap a card to open it; ⋮ → Update / Delete; "Add website" to add one.
class SitesHome extends StatefulWidget {
  const SitesHome({super.key, this.initialUrl});

  /// primeshows.org link the app was opened with (deep link).
  final String? initialUrl;

  @override
  State<SitesHome> createState() => _SitesHomeState();
}

class _SitesHomeState extends State<SitesHome> {
  final SiteStore _store = SiteStore();
  StreamSubscription<Uri>? _linkSub;
  bool _skipInitialLink = false;
  DateTime? _lastBackPress;

  bool get _isTv => AppDevice.isTv;

  @override
  void initState() {
    super.initState();
    _skipInitialLink = widget.initialUrl != null;
    _start();
  }

  Future<void> _start() async {
    await _store.load();
    if (!mounted) return;
    final initial = widget.initialUrl;
    if (initial != null) _openUrl(initial);
    _listenForDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _store.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Deep links (primeshows.org/… or primeshows://…)
  // ---------------------------------------------------------------------------

  void _listenForDeepLinks() {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) return;
    try {
      _linkSub = AppLinks().uriLinkStream.listen(
        (uri) {
          final url = LinkHandler.deepLinkToUrl(uri);
          if (url == null) return;
          // app_links may re-emit the link the app was started with.
          if (_skipInitialLink && url == widget.initialUrl) {
            _skipInitialLink = false;
            return;
          }
          _skipInitialLink = false;
          _openUrl(url);
        },
        onError: (Object e) => debugPrint('Deep link error: $e'),
      );
    } catch (e) {
      debugPrint('Deep links unavailable: $e');
    }
  }

  /// Opens [url] in the saved site it belongs to (or Primeshows).
  void _openUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    final site = _store.siteForHost(host) ?? SiteStore.defaultSite;
    _openSite(site, initialUrl: url);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openSite(SavedSite site, {String? initialUrl}) async {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WebShell(site: site, initialUrl: initialUrl),
      ),
    );
    // Back on this screen: restore its look (a site may have gone fullscreen).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _add() async {
    final saved = await showSiteEditor(context, store: _store);
    if (saved) _snack('Website added');
  }

  Future<void> _edit(SavedSite site) async {
    final saved = await showSiteEditor(context, store: _store, existing: site);
    if (saved) _snack('Website updated');
  }

  Future<void> _delete(SavedSite site) async {
    final ok = await confirmDeleteSite(context, site);
    if (!ok) return;
    await _store.remove(site.id);
    _snack('"${site.name}" deleted');
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

  void _onBack() {
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      _snack('Press back again to exit');
      return;
    }
    SystemNavigator.pop();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppConfig.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppConfig.backgroundColor,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: _isTv ? 84 : 64,
          titleSpacing: _isTv ? 40 : 16,
          title: Row(
            children: [
              Image.asset('assets/icon/logo_mark.png', width: 38, height: 38),
              const SizedBox(width: 10),
              const Text(
                AppConfig.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _isTv
            ? null
            : FloatingActionButton.extended(
                onPressed: _add,
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add website'),
              ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            if (!_store.isLoaded) {
              return const Center(
                child: CircularProgressIndicator(color: AppConfig.accentColor),
              );
            }
            final sites = _store.sites;
            if (sites.isEmpty) return _buildEmpty();
            return _buildGrid(sites);
          },
        ),
      ),
    );
  }

  Widget _buildGrid(List<SavedSite> sites) {
    final pad = _isTv ? 40.0 : 16.0;
    // TV gets an "Add website" tile at the end (no floating button there).
    final count = sites.length + (_isTv ? 1 : 0);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              'My websites · ${sites.length}',
              style: const TextStyle(
                color: AppConfig.inactiveColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, _isTv ? 40 : 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _isTv ? 440 : 560,
              mainAxisExtent: 84,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (i >= sites.length) {
                  return AddSiteCard(onTap: _add);
                }
                final site = sites[i];
                return SiteCard(
                  key: ValueKey(site.id),
                  site: site,
                  autofocus: _isTv && i == 0,
                  onOpen: () => _openSite(site),
                  onEdit: () => _edit(site),
                  onDelete: () => _delete(site),
                );
              },
              childCount: count,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              child: const Icon(Icons.language_rounded,
                  size: 46, color: AppConfig.accentColor),
            ),
            const SizedBox(height: 24),
            const Text(
              'No websites yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add a website to open it here like an app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppConfig.inactiveColor, fontSize: 15),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              autofocus: true,
              onPressed: _add,
              style: FilledButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add website'),
            ),
          ],
        ),
      ),
    );
  }
}
