import 'package:flutter/material.dart';

import '../l10n/editor_l10n.dart';
import 'diagram_templates.dart';

/// Shows a categorized template gallery. Returns the chosen [DiagramTemplate],
/// or `null` if cancelled.
Future<DiagramTemplate?> showTemplatePickerDialog(BuildContext context) {
  return showDialog<DiagramTemplate>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _TemplatePickerDialog(),
  );
}

class _TemplatePickerDialog extends StatefulWidget {
  const _TemplatePickerDialog();

  @override
  State<_TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<_TemplatePickerDialog> {
  TemplateCategory _category = TemplateCategory.blank;

  @override
  Widget build(BuildContext context) {
    final el = EditorL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final items = templatesFor(_category);

    final categoryRail = Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final cat in TemplateCategory.values)
            _CategoryTile(
              category: cat,
              selected: cat == _category,
              onTap: () => setState(() => _category = cat),
            ),
        ],
      ),
    );

    final grid = items.isEmpty
        ? Center(child: Text(el.noSelection))
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 3 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: wide ? 1.15 : 0.95,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              return _TemplateCard(
                template: t,
                locale: locale,
                onTap: () => Navigator.of(context).pop(t),
              );
            },
          );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.dashboard_customize_outlined,
                      color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      el.newFromTemplate,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: el.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                el.chooseTemplateHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 168, child: categoryRail),
                        const VerticalDivider(width: 1),
                        Expanded(child: grid),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 52,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            children: [
                              for (final cat in TemplateCategory.values) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    avatar: Icon(cat.icon, size: 16),
                                    label: Text(
                                      locale.languageCode == 'zh'
                                          ? cat.labels.$2
                                          : cat.labels.$1,
                                    ),
                                    selected: cat == _category,
                                    onSelected: (_) =>
                                        setState(() => _category = cat),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(child: grid),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final TemplateCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final label =
        locale.languageCode == 'zh' ? category.labels.$2 : category.labels.$1;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.55),
        leading: Icon(category.icon, size: 20),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    required this.template,
    required this.locale,
    required this.onTap,
  });

  final DiagramTemplate template;
  final Locale locale;
  final VoidCallback onTap;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: Material(
          color: scheme.surface,
          elevation: _hover ? 3 : 0.5,
          shadowColor: t.accent.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _hover
                  ? t.accent.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          t.accent.withValues(alpha: 0.92),
                          Color.lerp(t.accent, Colors.white, 0.35)!,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(t.icon, size: 40, color: Colors.white),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.titleFor(widget.locale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            t.descFor(widget.locale),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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
