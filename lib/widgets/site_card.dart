import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/saved_site.dart';

/// Round site icon: the site's favicon, or a coloured letter if it has none.
class SiteAvatar extends StatelessWidget {
  const SiteAvatar({super.key, required this.site, this.size = 52});

  final SavedSite site;
  final double size;

  static const List<Color> _palette = [
    Color(0xFF1657A6), Color(0xFF7B4DFF), Color(0xFF0E9F8E), Color(0xFFD9488F),
    Color(0xFFE07A1F), Color(0xFF3F8CFF), Color(0xFF8E44AD), Color(0xFF16A34A),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = site.name.trim().isNotEmpty
        ? site.name.trim()[0].toUpperCase()
        : (site.domain.isNotEmpty ? site.domain[0].toUpperCase() : '?');
    final color = _palette[site.domain.hashCode.abs() % _palette.length];

    final fallback = Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final Widget content = site.isPrimeshows
        ? Container(
            color: AppConfig.backgroundColor,
            child: Image.asset('assets/icon/logo_mark.png', fit: BoxFit.contain),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              // Letter shows until (or instead of) the favicon.
              fallback,
              Image.network(
                '${site.origin}/favicon.ico',
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                    frame == null && !wasSynchronouslyLoaded
                        ? const SizedBox.shrink()
                        : Container(
                            color: Colors.white,
                            padding: EdgeInsets.all(size * 0.16),
                            child: child,
                          ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ],
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

/// A saved website. Tap/OK opens it; the ⋮ button opens Edit / Delete.
class SiteCard extends StatefulWidget {
  const SiteCard({
    super.key,
    required this.site,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.autofocus = false,
  });

  final SavedSite site;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool autofocus;

  @override
  State<SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<SiteCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: AppConfig.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused ? AppConfig.accentColor : Colors.white.withValues(alpha: 0.07),
          width: _focused ? 2.5 : 1,
        ),
        boxShadow: _focused
            ? [BoxShadow(color: AppConfig.accentColor.withValues(alpha: 0.4), blurRadius: 18)]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            // Open area
            Expanded(
              child: InkWell(
                autofocus: widget.autofocus,
                onTap: widget.onOpen,
                onFocusChange: (f) => setState(() => _focused = f),
                focusColor: Colors.transparent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(
                    children: [
                      SiteAvatar(site: site),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _displayUrl(site.url),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppConfig.inactiveColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ⋮ menu (top-right)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: PopupMenuButton<String>(
                  tooltip: 'Options',
                  color: const Color(0xFF151B27),
                  position: PopupMenuPosition.under,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (value) {
                    if (value == 'edit') widget.onEdit();
                    if (value == 'delete') widget.onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                          SizedBox(width: 12),
                          Text('Update', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: Color(0xFFFF6B6B), size: 20),
                          SizedBox(width: 12),
                          Text('Delete', style: TextStyle(color: Color(0xFFFF6B6B))),
                        ],
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.more_vert_rounded, color: Colors.white70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _displayUrl(String url) {
    var s = url.replaceFirst(RegExp(r'^https?://'), '');
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }
}

/// "Add website" tile (used on TV, where there's no floating button).
class AddSiteCard extends StatefulWidget {
  const AddSiteCard({super.key, required this.onTap, this.autofocus = false});

  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<AddSiteCard> createState() => _AddSiteCardState();
}

class _AddSiteCardState extends State<AddSiteCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: _focused
            ? AppConfig.primaryColor.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused ? AppConfig.accentColor : Colors.white.withValues(alpha: 0.18),
          width: _focused ? 2.5 : 1.2,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded, color: AppConfig.accentColor, size: 28),
              SizedBox(width: 12),
              Text(
                'Add website',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
