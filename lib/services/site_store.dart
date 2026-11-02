import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/saved_site.dart';

/// Result of adding/updating a site.
enum SiteSaveResult { saved, invalidUrl, duplicate, notFound }

/// Saved websites, stored locally on the device (SharedPreferences).
class SiteStore extends ChangeNotifier {
  static const String _sitesKey = 'saved_sites_v1';
  static const String _seededKey = 'saved_sites_seeded_v1';

  List<SavedSite> _sites = const [];
  bool _loaded = false;

  List<SavedSite> get sites => List.unmodifiable(_sites);
  bool get isLoaded => _loaded;

  /// Primeshows, added on the very first start (the user can delete it).
  static SavedSite get defaultSite => const SavedSite(
        id: 'default-primeshows',
        name: AppConfig.appName,
        url: AppConfig.homeUrl,
      );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sitesKey);
      var sites = <SavedSite>[];
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            sites = decoded.map(SavedSite.fromJson).whereType<SavedSite>().toList();
          }
        } catch (e) {
          debugPrint('SiteStore: could not read saved sites ($e)');
        }
      }
      if (!(prefs.getBool(_seededKey) ?? false)) {
        if (sites.isEmpty) sites = [defaultSite];
        await prefs.setBool(_seededKey, true);
        await prefs.setString(_sitesKey, _encode(sites));
      }
      _sites = sites;
    } catch (e) {
      debugPrint('SiteStore: storage unavailable ($e)');
      _sites = [defaultSite];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<SiteSaveResult> add({required String name, required String url}) async {
    final normalized = normalizeUrl(url);
    if (normalized == null) return SiteSaveResult.invalidUrl;
    if (containsUrl(normalized)) return SiteSaveResult.duplicate;
    final site = SavedSite(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? defaultNameFor(normalized) : name.trim(),
      url: normalized,
    );
    _sites = [..._sites, site];
    await _persist();
    return SiteSaveResult.saved;
  }

  Future<SiteSaveResult> update(
    String id, {
    required String name,
    required String url,
  }) async {
    final index = _sites.indexWhere((s) => s.id == id);
    if (index < 0) return SiteSaveResult.notFound;
    final normalized = normalizeUrl(url);
    if (normalized == null) return SiteSaveResult.invalidUrl;
    if (containsUrl(normalized, exceptId: id)) return SiteSaveResult.duplicate;
    final updated = _sites[index].copyWith(
      name: name.trim().isEmpty ? defaultNameFor(normalized) : name.trim(),
      url: normalized,
    );
    _sites = [..._sites]..[index] = updated;
    await _persist();
    return SiteSaveResult.saved;
  }

  Future<void> remove(String id) async {
    _sites = _sites.where((s) => s.id != id).toList();
    await _persist();
  }

  SavedSite? byId(String id) {
    for (final s in _sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The saved site that owns [host], if any.
  SavedSite? siteForHost(String host) {
    for (final s in _sites) {
      if (s.ownsHost(host)) return s;
    }
    return null;
  }

  bool containsUrl(String normalizedUrl, {String? exceptId}) {
    final key = _compareKey(normalizedUrl);
    return _sites.any((s) => s.id != exceptId && _compareKey(s.url) == key);
  }

  Future<void> _persist() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sitesKey, _encode(_sites));
    } catch (e) {
      debugPrint('SiteStore: could not save ($e)');
    }
  }

  static String _encode(List<SavedSite> sites) =>
      jsonEncode(sites.map((s) => s.toJson()).toList());

  /// `HTTPS://WWW.Example.com/` and `https://example.com` count as the same.
  static String _compareKey(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    var host = u.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    var path = u.path;
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    final query = u.hasQuery ? '?${u.query}' : '';
    final port = u.hasPort ? ':${u.port}' : '';
    return '$host$port$path$query';
  }

  static final RegExp _hostPattern =
      RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$');

  /// Turns user input into a clean http(s) URL, or `null` if it isn't one.
  ///
  /// `example.com` → `https://example.com/`,
  /// `http://192.168.1.5:8080/app` stays as is.
  static String? normalizeUrl(String input) {
    var text = input.trim();
    if (text.isEmpty || text.contains(' ')) return null;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty || !_hostPattern.hasMatch(host)) return null;
    // Needs a dot (example.com) unless it's localhost.
    if (!host.contains('.') && host != 'localhost') return null;
    final cleaned = uri.replace(
      scheme: scheme,
      host: host,
      path: uri.path.isEmpty ? '/' : uri.path,
    );
    return cleaned.toString();
  }

  /// `https://www.my-site.com/` → `My-site`.
  static String defaultNameFor(String url) {
    var host = Uri.tryParse(url)?.host ?? url;
    if (host.startsWith('www.')) host = host.substring(4);
    final first = host.split('.').first;
    if (first.isEmpty) return host;
    return first[0].toUpperCase() + first.substring(1);
  }
}
