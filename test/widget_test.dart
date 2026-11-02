import 'package:flutter_test/flutter_test.dart';

import 'package:prime/config/app_config.dart';
import 'package:prime/models/saved_site.dart';
import 'package:prime/services/site_store.dart';
import 'package:prime/utils/link_handler.dart';

void main() {
  group('LinkHandler', () {
    test('primeshows.org links stay in the app', () {
      expect(LinkHandler.isInternal(Uri.parse('https://primeshows.org/movies')), isTrue);
      expect(LinkHandler.isInternal(Uri.parse('https://www.primeshows.org/tv/1')), isTrue);
      expect(LinkHandler.isInternal(Uri.parse('https://example.com/')), isFalse);
      expect(LinkHandler.isInternal(Uri.parse('https://notprimeshows.org/')), isFalse);
      expect(LinkHandler.isInternal(Uri.parse('tel:123')), isFalse);
    });

    test('deep links map to site URLs', () {
      expect(
        LinkHandler.deepLinkToUrl(Uri.parse('https://primeshows.org/movie/42')),
        'https://primeshows.org/movie/42',
      );
      expect(
        LinkHandler.deepLinkToUrl(Uri.parse('primeshows://movie/42')),
        'https://primeshows.org/movie/42',
      );
      expect(LinkHandler.deepLinkToUrl(Uri.parse('https://google.com')), isNull);
    });

    test('intent:// links are parsed', () {
      final link = IntentLink.parse(
        'intent://send?text=hi#Intent;scheme=whatsapp;package=com.whatsapp;'
        'S.browser_fallback_url=https%3A%2F%2Fwa.me%2F;end',
      )!;
      expect(link.targetUri.toString(), 'whatsapp://send?text=hi');
      expect(link.packageName, 'com.whatsapp');
      expect(link.fallbackUrl, 'https://wa.me/');
    });
  });

  group('AppTab', () {
    test('active tab follows the path', () {
      final movies = AppConfig.tabs[1];
      expect(movies.matches('/movies'), isTrue);
      expect(movies.matches('/movie/123'), isTrue);
      expect(movies.matches('/moviesx'), isFalse);
      expect(AppConfig.tabs[0].matches('/'), isTrue);
      expect(AppConfig.tabs[0].matches('/tv'), isFalse);
    });
  });

  group('TV side menu', () {
    test('menu entries match the current page', () {
      final home = AppConfig.tvRailLinks.first;
      final movies = AppConfig.tvRailLinks.firstWhere((l) => l.path == '/movies');
      expect(home.matches('/'), isTrue);
      expect(home.matches('/movies'), isFalse);
      expect(movies.matches('/movie/550'), isTrue);
      expect(movies.matches('/movies'), isTrue);
    });
  });

  group('Saved websites', () {
    test('addresses are cleaned up and checked', () {
      expect(SiteStore.normalizeUrl('example.com'), 'https://example.com/');
      expect(SiteStore.normalizeUrl('  Example.COM/path  '), 'https://example.com/path');
      expect(SiteStore.normalizeUrl('http://192.168.1.5:8080/app'), 'http://192.168.1.5:8080/app');
      expect(SiteStore.normalizeUrl(''), isNull);
      expect(SiteStore.normalizeUrl('not a url'), isNull);
      expect(SiteStore.normalizeUrl('ftp://example.com'), isNull);
      expect(SiteStore.normalizeUrl('localhost'), 'https://localhost/');
      expect(SiteStore.normalizeUrl('http://localhost:3000'), 'http://localhost:3000/');
      expect(SiteStore.normalizeUrl('exa_mple.com'), isNull);
    });

    test('default names come from the address', () {
      expect(SiteStore.defaultNameFor('https://www.my-site.com/'), 'My-site');
      expect(SiteStore.defaultNameFor('https://news.example.org/'), 'News');
    });

    test('a site owns its domain and sub-domains', () {
      const site = SavedSite(id: '1', name: 'Ex', url: 'https://www.example.com/');
      expect(site.ownsHost('example.com'), isTrue);
      expect(site.ownsHost('www.example.com'), isTrue);
      expect(site.ownsHost('cdn.example.com'), isTrue);
      expect(site.ownsHost('notexample.com'), isFalse);
      expect(site.isPrimeshows, isFalse);
      expect(SiteStore.defaultSite.isPrimeshows, isTrue);
    });

    test('sites survive a save/load round trip', () {
      const site = SavedSite(id: '1', name: 'Ex', url: 'https://example.com/');
      expect(SavedSite.fromJson(site.toJson()), site);
      expect(SavedSite.fromJson({'id': 1}), isNull);
    });
  });
}
