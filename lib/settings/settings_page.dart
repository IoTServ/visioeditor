import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_settings.dart';

/// App preferences: language, dark/light theme, and accent colour.
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.settings, super.key});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _sectionHeader(context, l10n.appearance),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(l10n.themeMode),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text(l10n.themeModeSystem),
                      icon: const Icon(Icons.brightness_auto, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text(l10n.themeModeLight),
                      icon: const Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text(l10n.themeModeDark),
                      icon: const Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                  ],
                  selected: <ThemeMode>{settings.themeMode},
                  onSelectionChanged: (sel) {
                    if (sel.isNotEmpty) settings.setThemeMode(sel.first);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.themeColor),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final argb in AppSettings.seedPresets)
                      _SeedSwatch(
                        color: Color(argb),
                        selected: settings.seedColorValue == argb,
                        onTap: () => settings.setSeedColor(Color(argb)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  l10n.themeColorHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 32),
              _sectionHeader(context, l10n.language),
              RadioGroup<String>(
                groupValue: settings.localePreference,
                onChanged: (v) {
                  if (v != null) settings.setLocalePreference(v);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(l10n.languageSystem),
                      value: 'system',
                    ),
                    RadioListTile<String>(
                      title: Text(l10n.languageEnglish),
                      value: 'en',
                    ),
                    RadioListTile<String>(
                      title: Text(l10n.languageChinese),
                      value: 'zh',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.languageHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: Text(l10n.resetDefaults),
                subtitle: Text(l10n.resetDefaultsHint),
                onTap: () => settings.resetToDefaults(),
              ),
              const Divider(height: 32),
              _sectionHeader(context, l10n.about),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.appTitle),
                subtitle: Text(l10n.aboutBody),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
        : Border.all(color: Colors.black26);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border,
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              )
            : null,
      ),
    );
  }
}
