import 'package:flutter/material.dart';

import '../config/app_config.dart';

enum MoreActionType {
  openPath,
  sites,
  share,
  copyLink,
  openInBrowser,
  reload,
  clearCache,
}

class MoreAction {
  const MoreAction(this.type, [this.path]);
  final MoreActionType type;
  final String? path;
}

/// Shows the "More" bottom sheet and returns the chosen action (or null).
///
/// [links] are the site's own pages (shown under "Browse"); pass an empty
/// list for websites without a menu.
Future<MoreAction?> showMoreSheet(
  BuildContext context, {
  required String currentPath,
  List<MenuLink> links = const [],
}) {
  return showModalBottomSheet<MoreAction>(
    context: context,
    backgroundColor: AppConfig.surfaceColor,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _MoreSheet(currentPath: currentPath, links: links),
  );
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.currentPath, required this.links});

  final String currentPath;
  final List<MenuLink> links;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (links.isNotEmpty) ...[
            const _SectionTitle('Browse'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final (i, link) in links.indexed)
                  _LinkTile(
                    link: link,
                    autofocus: i == 0, // TV remote starts on the first item
                    selected: currentPath == link.path ||
                        currentPath.startsWith('${link.path}/'),
                    onTap: () => Navigator.pop(
                      context,
                      MoreAction(MoreActionType.openPath, link.path),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ],
            const _SectionTitle('App'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _ActionRow(Icons.apps_rounded, 'My websites',
                  () => Navigator.pop(context, const MoreAction(MoreActionType.sites)),
                  showDivider: false, autofocus: links.isEmpty),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('This page'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _ActionRow(Icons.share_outlined, 'Share',
                      () => Navigator.pop(context, const MoreAction(MoreActionType.share))),
                  _ActionRow(Icons.link_rounded, 'Copy link',
                      () => Navigator.pop(context, const MoreAction(MoreActionType.copyLink))),
                  _ActionRow(Icons.open_in_browser_rounded, 'Open in browser',
                      () => Navigator.pop(context, const MoreAction(MoreActionType.openInBrowser))),
                  _ActionRow(Icons.refresh_rounded, 'Reload',
                      () => Navigator.pop(context, const MoreAction(MoreActionType.reload))),
                  _ActionRow(Icons.cleaning_services_outlined, 'Clear cache',
                      () => Navigator.pop(context, const MoreAction(MoreActionType.clearCache)),
                      showDivider: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppConfig.inactiveColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final MenuLink link;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppConfig.primaryColor.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        autofocus: autofocus,
        focusColor: AppConfig.primaryColor.withValues(alpha: 0.7),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(link.icon,
                color: selected ? Colors.white : AppConfig.accentColor, size: 26),
            const SizedBox(height: 8),
            Text(
              link.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.icon, this.label, this.onTap,
      {this.showDivider = true, this.autofocus = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(icon, color: Colors.white70),
          title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          onTap: onTap,
          autofocus: autofocus,
          focusColor: AppConfig.primaryColor.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        if (showDivider)
          Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.06)),
      ],
    );
  }
}
