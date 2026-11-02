import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// One entry of the TV side menu.
class TvRailEntry {
  const TvRailEntry(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Android TV side menu (Google TV style). Collapsed to icons while you
/// browse; expands with labels when the remote moves focus into it.
///
/// Up / Down move between items, OK opens one, Right goes back to the page.
class TvNavRail extends StatefulWidget {
  const TvNavRail({
    super.key,
    required this.entries,
    required this.focusNodes,
    required this.selectedIndex,
    required this.onSelect,
    required this.onExit,
  });

  final List<TvRailEntry> entries;

  /// One focus node per entry (owned by the parent so it can focus the rail).
  final List<FocusNode> focusNodes;

  /// Entry for the current page, or -1.
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Called when the user presses Right to leave the menu.
  final VoidCallback onExit;

  @override
  State<TvNavRail> createState() => _TvNavRailState();
}

class _TvNavRailState extends State<TvNavRail> {
  bool _expanded = false;

  int get _focusedIndex => widget.focusNodes.indexWhere((n) => n.hasFocus);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final count = widget.focusNodes.length;

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (isDown) {
        final current = _focusedIndex < 0 ? 0 : _focusedIndex;
        final next = key == LogicalKeyboardKey.arrowDown
            ? (current + 1).clamp(0, count - 1)
            : (current - 1).clamp(0, count - 1);
        widget.focusNodes[next].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown) widget.onExit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled; // already at the left edge
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent && _focusedIndex >= 0) {
        widget.onSelect(_focusedIndex);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      onFocusChange: (hasFocus) => setState(() => _expanded = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _expanded ? 240 : 92,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppConfig.navBarColor,
              AppConfig.navBarColor.withValues(alpha: _expanded ? 0.98 : 0.92),
            ],
          ),
          border: const Border(
            right: BorderSide(color: Color(0x1FFFFFFF), width: 0.5),
          ),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              _RailLogo(expanded: _expanded),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: widget.entries.length,
                  itemBuilder: (context, i) => _RailItem(
                    entry: widget.entries[i],
                    focusNode: widget.focusNodes[i],
                    selected: i == widget.selectedIndex,
                    expanded: _expanded,
                    onTap: () => widget.onSelect(i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo({required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: 240,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              children: [
                Image.asset('assets/icon/logo_mark.png', width: 52, height: 52),
                const SizedBox(width: 10),
                AnimatedOpacity(
                  opacity: expanded ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Text(
                    AppConfig.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.entry,
    required this.focusNode,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final TvRailEntry entry;
  final FocusNode focusNode;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _focused
        ? Colors.white
        : widget.selected
            ? AppConfig.accentColor
            : AppConfig.inactiveColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(16),
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _focused
                ? AppConfig.primaryColor
                : widget.selected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
            border: Border.all(
              color: _focused ? AppConfig.accentColor : Colors.transparent,
              width: 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppConfig.accentColor.withValues(alpha: 0.45),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: 212,
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  Icon(widget.entry.icon, color: iconColor, size: 26),
                  const SizedBox(width: 18),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: widget.expanded ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Text(
                        widget.entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _focused || widget.selected
                              ? Colors.white
                              : AppConfig.inactiveColor,
                          fontSize: 17,
                          fontWeight: widget.selected || _focused
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
