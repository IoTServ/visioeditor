import 'package:flutter/material.dart';

import '../ai/ai_chat_dialog.dart';
import '../ai/ai_engine.dart';
import '../ai/ai_help_page.dart';
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    return SegmentedButton<ThemeMode>(
                      style: narrow
                          ? const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            )
                          : null,
                      segments: <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: narrow
                              ? null
                              : Text(
                                  l10n.themeModeSystem,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          icon: const Icon(Icons.brightness_auto, size: 18),
                          tooltip: l10n.themeModeSystem,
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: narrow
                              ? null
                              : Text(
                                  l10n.themeModeLight,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          icon: const Icon(Icons.light_mode_outlined, size: 18),
                          tooltip: l10n.themeModeLight,
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: narrow
                              ? null
                              : Text(
                                  l10n.themeModeDark,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          icon: const Icon(Icons.dark_mode_outlined, size: 18),
                          tooltip: l10n.themeModeDark,
                        ),
                      ],
                      selected: <ThemeMode>{settings.themeMode},
                      onSelectionChanged: (sel) {
                        if (sel.isNotEmpty) settings.setThemeMode(sel.first);
                      },
                    );
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _LanguagePicker(
                  settings: settings,
                  l10n: l10n,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.languageHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 32),
              _sectionHeader(
                context,
                Localizations.localeOf(context).languageCode == 'zh'
                    ? 'AI 与 Agent'
                    : 'AI and agents',
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '内置对话引擎'
                      : 'Built-in chat engine',
                ),
                subtitle: Text(
                  '${settings.aiEngine.provider.label} · '
                  '${settings.aiEngine.model}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAiEngineDialog(context, settings: settings),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? 'AI 接入使用说明'
                      : 'AI integration guide',
                ),
                subtitle: Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '内置对话、实时预览、MCP、CLI 与 Agent Skill'
                      : 'Chat, live preview, MCP, CLI and Agent Skill',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiIntegrationHelpPage(),
                  ),
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

/// Collapsed searchable language dropdown (system + all supported locales).
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.settings,
    required this.l10n,
  });

  final AppSettings settings;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final selected = settings.localePreference;
    final codes = AppLocalizations.languagePreferenceCodes;
    final menuWidth = MediaQuery.sizeOf(context).width - 32;

    return DropdownMenu<String>(
      key: ValueKey<String>(selected),
      width: menuWidth,
      initialSelection: selected,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      leadingIcon: const Icon(Icons.translate_outlined),
      hintText: l10n.languageSearchHint,
      label: Text(l10n.language),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dropdownMenuEntries: [
        for (final code in codes)
          DropdownMenuEntry<String>(
            value: code,
            label: l10n.labelForLanguagePreference(code),
          ),
      ],
      onSelected: (code) {
        if (code != null) settings.setLocalePreference(code);
      },
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
