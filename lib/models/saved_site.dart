import '../config/app_config.dart';

/// A website the user saved on the "My websites" screen.
class SavedSite {
  const SavedSite({required this.id, required this.name, required this.url});

  final String id;
  final String name;

  /// Normalised http(s) URL, e.g. `https://example.com/`.
  final String url;

  Uri get uri => Uri.parse(url);

  String get host => uri.host.toLowerCase();

  /// Host without a leading `www.` – links to this domain and its
  /// sub-domains stay inside the app.
  String get domain => host.startsWith('www.') ? host.substring(4) : host;

  /// `https://example.com` (no path).
  String get origin => '${uri.scheme}://${uri.authority}';

  /// True for primeshows.org – gets the full Primeshows navigation.
  bool get isPrimeshows => AppConfig.isAllowedHost(host);

  bool ownsHost(String? otherHost) {
    if (otherHost == null || otherHost.isEmpty) return false;
    final h = otherHost.toLowerCase();
    final d = domain;
    if (d.isEmpty) return false;
    return h == d || h.endsWith('.$d');
  }

  SavedSite copyWith({String? name, String? url}) =>
      SavedSite(id: id, name: name ?? this.name, url: url ?? this.url);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  static SavedSite? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final url = json['url'];
    if (id is! String || name is! String || url is! String) return null;
    if (Uri.tryParse(url)?.host.isNotEmpty != true) return null;
    return SavedSite(id: id, name: name, url: url);
  }

  @override
  bool operator ==(Object other) =>
      other is SavedSite && other.id == id && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(id, name, url);
}
