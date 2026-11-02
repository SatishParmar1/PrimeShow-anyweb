import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/saved_site.dart';
import '../services/site_store.dart';

/// Arrow Up/Down move between fields and buttons (TV remotes), instead of
/// moving the text cursor.
const Map<ShortcutActivator, Intent> _dpadShortcuts = {
  SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
};

/// Add a new website, or update [existing]. Returns true when saved.
Future<bool> showSiteEditor(
  BuildContext context, {
  required SiteStore store,
  SavedSite? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _SiteEditorDialog(store: store, existing: existing),
  );
  return saved ?? false;
}

/// Asks before deleting. Returns true when the user confirmed.
Future<bool> confirmDeleteSite(BuildContext context, SavedSite site) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppConfig.surfaceColor,
      title: const Text('Delete website?', style: TextStyle(color: Colors.white)),
      content: Text(
        '"${site.name}" will be removed from your list.',
        style: const TextStyle(color: AppConfig.inactiveColor, height: 1.4),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _SiteEditorDialog extends StatefulWidget {
  const _SiteEditorDialog({required this.store, this.existing});

  final SiteStore store;
  final SavedSite? existing;

  @override
  State<_SiteEditorDialog> createState() => _SiteEditorDialogState();
}

class _SiteEditorDialogState extends State<_SiteEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  final _formKey = GlobalKey<FormState>();
  String? _urlError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _urlError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final result = _isEdit
        ? await widget.store.update(widget.existing!.id, name: _name.text, url: _url.text)
        : await widget.store.add(name: _name.text, url: _url.text);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case SiteSaveResult.saved:
        Navigator.pop(context, true);
      case SiteSaveResult.invalidUrl:
        setState(() => _urlError = 'Enter a valid web address, e.g. example.com');
      case SiteSaveResult.duplicate:
        setState(() => _urlError = 'This website is already in your list');
      case SiteSaveResult.notFound:
        Navigator.pop(context, false);
    }
  }

  InputDecoration _decoration(String label, String hint, IconData icon, {String? error}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        prefixIcon: Icon(icon, color: AppConfig.inactiveColor),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        labelStyle: const TextStyle(color: AppConfig.inactiveColor),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConfig.accentColor, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _dpadShortcuts,
      child: AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        title: Text(
          _isEdit ? 'Update website' : 'Add website',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _url,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    decoration: _decoration(
                      'Website address',
                      'example.com',
                      Icons.language_rounded,
                      error: _urlError,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter a web address';
                      if (SiteStore.normalizeUrl(v) == null) {
                        return 'Enter a valid web address, e.g. example.com';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      if (_urlError != null) setState(() => _urlError = null);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    maxLength: 40,
                    style: const TextStyle(color: Colors.white),
                    decoration: _decoration(
                      'Name (optional)',
                      'My website',
                      Icons.label_outline_rounded,
                    ).copyWith(counterText: ''),
                    onFieldSubmitted: (_) => _save(),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppConfig.primaryColor),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_isEdit ? 'Update' : 'Save'),
          ),
        ],
      ),
    );
  }
}
