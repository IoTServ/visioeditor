import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import '../l10n/editor_l10n.dart';
import 'editor_controller.dart';
import 'third_party_icons.dart';

/// Right-panel editor for third-party icon pictures (pack, glyph, colour).
class IconConfigPanel extends StatefulWidget {
  const IconConfigPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<IconConfigPanel> createState() => _IconConfigPanelState();
}

class _IconConfigPanelState extends State<IconConfigPanel> {
  static const List<int> _swatches = <int>[
    0xFF243040,
    0xFF000000,
    0xFFE53935,
    0xFF43A047,
    0xFF1E88E5,
    0xFFFDD835,
    0xFFFB8C00,
    0xFF8E24AA,
    0xFF00897B,
    0xFF5D4037,
    0xFF607D8B,
    0xFFFFFFFF,
  ];

  String _query = '';
  String? _providerFilter;
  bool _busy = false;
  int? _boundIconId;
  String _boundFingerprint = '';

  EditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFromController();
    });
  }

  @override
  void didUpdateWidget(covariant IconConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncFromController();
  }

  String _fingerprint(VsdxShape icon) {
    final p = IconOps.providerId(icon) ?? '';
    final i = IconOps.iconId(icon) ?? '';
    final c = IconOps.colorArgb(icon);
    return '$p|$i|${c.toRadixString(16)}';
  }

  void _syncFromController() {
    final icon = controller.selectedIcon;
    final id = controller.selectedIconId;
    if (icon == null || id == null) {
      setState(() {
        _boundIconId = null;
        _boundFingerprint = '';
        _providerFilter = null;
      });
      return;
    }
    final fp = _fingerprint(icon);
    if (id == _boundIconId && fp == _boundFingerprint) return;
    setState(() {
      _boundIconId = id;
      _boundFingerprint = fp;
      _providerFilter = IconOps.providerId(icon);
    });
  }

  Future<void> _apply({
    String? providerId,
    String? iconId,
    int? colorArgb,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await controller.setSelectedIcon(
        providerId: providerId,
        iconId: iconId,
        colorArgb: colorArgb,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final icon = controller.selectedIcon;
    if (icon == null) return const SizedBox.shrink();

    final providerId = IconOps.providerId(icon);
    final iconId = IconOps.iconId(icon);
    final colorArgb = IconOps.colorArgb(icon);
    final entry = IconOps.resolve(icon);
    final filterId = _providerFilter ?? providerId;
    final q = _query.trim().toLowerCase();

    final providers = kThirdPartyIconProviders;
    final filterProvider = filterId == null
        ? null
        : findThirdPartyIconProvider(filterId);
    final matches = <({String providerId, ThirdPartyIcon icon})>[];
    for (final p in providers) {
      if (filterProvider != null && p.id != filterProvider.id) continue;
      for (final i in p.icons) {
        if (!thirdPartyIconMatches(i, q)) continue;
        matches.add((providerId: p.id, icon: i));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(el.panelIcon, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          el.iconConfigHint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (entry != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Icon(entry.icon, color: Color(colorArgb), size: 28),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${findThirdPartyIconProvider(providerId ?? '')?.name ?? providerId} · $iconId',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(el.iconProvider, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in providers)
              ChoiceChip(
                label: Text(p.name, style: const TextStyle(fontSize: 11)),
                selected: filterId == p.id,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _providerFilter = p.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(el.color, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final argb in _swatches)
              Tooltip(
                message: IconOps.formatColor(argb),
                child: InkWell(
                  onTap: _busy || argb == colorArgb
                      ? null
                      : () => _apply(colorArgb: argb),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(argb),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: argb == colorArgb
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: argb == colorArgb ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_busy,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: el.searchIcons,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    el.noResults,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : GridView.builder(
                  itemCount: matches.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 0.85,
                  ),
                  itemBuilder: (context, index) {
                    final m = matches[index];
                    final selected = m.providerId == providerId &&
                        m.icon.id == iconId;
                    return Tooltip(
                      message: m.icon.name,
                      child: Material(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _busy || selected
                              ? null
                              : () => _apply(
                                    providerId: m.providerId,
                                    iconId: m.icon.id,
                                  ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                m.icon.icon,
                                size: 26,
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 2),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  m.icon.name,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
