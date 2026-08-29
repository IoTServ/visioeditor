/// Top-level parsed representation of a `.vsdx` package.
///
/// This is the **single source of truth** consumed by the render and export
/// layers. Both parsers (`lib/parser/document_parser.dart`) and tests build
/// this graph; nothing else may bypass it.
///
/// Designed to be immutable — `copyWith` is intentionally absent for now to
/// keep the contract tight. We'll introduce `freezed` once the field set
/// stabilises (probably after M3).
library;

import 'package:meta/meta.dart';

import 'custom_property.dart';
import 'document_settings.dart';
import 'hyperlink.dart';
import 'image.dart';
import 'master.dart';
import 'page.dart';
import 'shape.dart';
import 'theme.dart';

@immutable
class VsdxDocument {
  const VsdxDocument({
    required this.pages,
    this.masters = MasterRegistry.empty,
    this.theme = VsdxTheme.empty,
    this.images = ImageRegistry.empty,
    this.settings = VsdxDocumentSettings.defaults,
    this.title,
    this.creator,
    this.subject,
    this.keywords,
    this.description,
    this.lastModifiedBy,
    this.created,
    this.modified,
    this.language,
    this.category,
    this.company,
    this.template,
    this.applicationName,
    this.customProperties = const [],
  });

  /// Pages in display order. Always at least one for a valid document.
  final List<VsdxPage> pages;

  /// `Master="N"` registry. The parser has already applied the relevant
  /// cells to each shape, so the renderer doesn't need to walk this — but
  /// future M5 panels (stencil browser, "go to master") will.
  final MasterRegistry masters;

  /// Document theme palette. The renderer uses it to resolve `THEMEVAL()`
  /// colour references recorded on each [VsdxFill] / [VsdxLine].
  final VsdxTheme theme;

  /// Embedded raster images (`visio/media/*`), indexed by absolute part name.
  final ImageRegistry images;

  /// Top-level `<DocumentSettings>` (page background, grid, glue, …).
  final VsdxDocumentSettings settings;

  /// `docProps/core.xml` → `<dc:title>`. May be `null`.
  final String? title;
  final String? creator;

  /// Remaining core / extended document metadata surfaced by libvisio.
  final String? subject;
  final String? keywords;
  final String? description;
  final String? lastModifiedBy;
  final String? created;
  final String? modified;
  final String? language;
  final String? category;
  final String? company;
  final String? template;

  /// `docProps/app.xml` → `<Application>` (e.g. "Microsoft Visio").
  final String? applicationName;

  /// `docProps/custom.xml` → user-defined document properties.
  final List<VsdxCustomProperty> customProperties;

  /// Convenience: produce an empty document (used by error fallback UI).
  static const VsdxDocument empty = VsdxDocument(pages: <VsdxPage>[]);

  VsdxDocument copyWith({
    List<VsdxPage>? pages,
    MasterRegistry? masters,
    VsdxTheme? theme,
    ImageRegistry? images,
    VsdxDocumentSettings? settings,
    String? title,
    String? creator,
    String? subject,
    String? keywords,
    String? description,
    String? lastModifiedBy,
    String? created,
    String? modified,
    String? language,
    String? category,
    String? company,
    String? template,
    String? applicationName,
    List<VsdxCustomProperty>? customProperties,
  }) {
    return VsdxDocument(
      pages: pages ?? this.pages,
      masters: masters ?? this.masters,
      theme: theme ?? this.theme,
      images: images ?? this.images,
      settings: settings ?? this.settings,
      title: title ?? this.title,
      creator: creator ?? this.creator,
      subject: subject ?? this.subject,
      keywords: keywords ?? this.keywords,
      description: description ?? this.description,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      created: created ?? this.created,
      modified: modified ?? this.modified,
      language: language ?? this.language,
      category: category ?? this.category,
      company: company ?? this.company,
      template: template ?? this.template,
      applicationName: applicationName ?? this.applicationName,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  /// Returns a copy with the page at [index] replaced by [page]. Out-of-range
  /// indices return `this` unchanged.
  VsdxDocument replacePage(int index, VsdxPage page) {
    if (index < 0 || index >= pages.length) return this;
    final newPages = List<VsdxPage>.of(pages);
    newPages[index] = page;
    return copyWith(pages: newPages);
  }

  /// Rename a page and keep in-document hyperlinks pointing at it.
  ///
  /// Visio stores page jumps as textual `SubAddress` values, so changing only
  /// the page name would leave links such as `#Page-2/Shape-4` dangling. The
  /// rename and every inbound retarget are returned as one immutable document
  /// update so callers can record them as one undo step.
  VsdxDocument renamePageAndRetargetLinks(int index, String name) {
    if (index < 0 || index >= pages.length) return this;
    final nextName = name.trim();
    final oldName = pages[index].name;
    if (nextName.isEmpty || nextName == oldName) return this;

    String? retarget(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      var target = raw.trim();
      final hash = target.startsWith('#');
      if (hash) target = target.substring(1).trim();
      try {
        target = Uri.decodeFull(target);
      } on FormatException {
        // A malformed escape can still be a literal page name.
      }
      final separators = <int>[
        target.indexOf('/'),
        target.indexOf('!'),
      ].where((value) => value >= 0);
      int? separator;
      for (final value in separators) {
        if (separator == null || value < separator) separator = value;
      }
      final token =
          (separator == null ? target : target.substring(0, separator)).trim();
      final suffix = separator == null ? '' : target.substring(separator);
      String? quote;
      var pageName = token;
      if (token.length >= 2 &&
          ((token.startsWith('"') && token.endsWith('"')) ||
              (token.startsWith("'") && token.endsWith("'")))) {
        quote = token.substring(0, 1);
        pageName = token.substring(1, token.length - 1).trim();
      }
      if (pageName.toLowerCase() != oldName.trim().toLowerCase()) return null;
      final renamed = quote == null ? nextName : '$quote$nextName$quote';
      return '${hash ? '#' : ''}$renamed$suffix';
    }

    VsdxShape rewriteShape(VsdxShape shape) {
      var linksChanged = false;
      final links = <VsdxHyperlink>[];
      for (final link in shape.hyperlinks) {
        final target = link.address?.trim().isNotEmpty == true
            ? null
            : retarget(link.subAddress);
        if (target == null) {
          links.add(link);
        } else {
          linksChanged = true;
          links.add(link.copyWith(subAddress: target));
        }
      }
      var childrenChanged = false;
      final children = <VsdxShape>[];
      for (final child in shape.children) {
        final rewritten = rewriteShape(child);
        childrenChanged |= !identical(rewritten, child);
        children.add(rewritten);
      }
      if (!linksChanged && !childrenChanged) return shape;
      return shape.copyWith(hyperlinks: links, children: children);
    }

    final nextPages = <VsdxPage>[];
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      var shapesChanged = false;
      final shapes = <VsdxShape>[];
      for (final shape in page.shapes) {
        final rewritten = rewriteShape(shape);
        shapesChanged |= !identical(rewritten, shape);
        shapes.add(rewritten);
      }
      nextPages.add(
        pageIndex == index || shapesChanged
            ? page.copyWith(
                name: pageIndex == index ? nextName : null,
                shapes: shapesChanged ? shapes : null,
              )
            : page,
      );
    }
    return copyWith(pages: nextPages);
  }

  /// Smallest page id greater than every existing page id.
  int nextPageId() {
    var maxId = -1;
    for (final p in pages) {
      if (p.id > maxId) maxId = p.id;
    }
    return maxId + 1;
  }

  /// Page with [id], or `null`.
  VsdxPage? pageById(int? id) {
    if (id == null) return null;
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Resolved Visio `BackPage` underlay for [page], or `null`.
  VsdxPage? backgroundFor(VsdxPage page) => pageById(page.backgroundPageId);

  /// Insert [page] at [index] (clamped).
  VsdxDocument insertPage(int index, VsdxPage page) {
    final newPages = List<VsdxPage>.of(pages)
      ..insert(index.clamp(0, pages.length), page);
    return copyWith(pages: newPages);
  }

  /// Remove the page at [index]. Out-of-range indices return `this`.
  ///
  /// Also clears any remaining page's [VsdxPage.backgroundPageId] that pointed
  /// at the removed page so export / writer do not keep a dangling BackPage.
  VsdxDocument removePageAt(int index) {
    if (index < 0 || index >= pages.length) return this;
    final removedId = pages[index].id;
    final newPages = <VsdxPage>[
      for (var i = 0; i < pages.length; i++)
        if (i != index)
          pages[i].backgroundPageId == removedId
              ? pages[i].copyWith(backgroundPageId: null)
              : pages[i],
    ];
    return copyWith(pages: newPages);
  }

  /// Move the page at [from] to [to] (draw.io page-tab reorder). Indices are
  /// clamped; a no-op when [from] == [to] or either is out of range.
  VsdxDocument movePage(int from, int to) {
    if (from < 0 ||
        from >= pages.length ||
        to < 0 ||
        to >= pages.length ||
        from == to) {
      return this;
    }
    final newPages = List<VsdxPage>.of(pages);
    final page = newPages.removeAt(from);
    newPages.insert(to, page);
    return copyWith(pages: newPages);
  }

  @override
  String toString() =>
      'VsdxDocument(title: $title, pages: ${pages.length}, '
      'masters: ${masters.length})';
}

/// Attach captured draw.io stencil rasters that [document.images] does not
/// yet own. LibreOffice only collects ForeignData from media parts, so a
/// palette drop or probe write that only `addShape`s would otherwise emit
/// an empty picture.
VsdxDocument mergeDrawioStencilImages(VsdxDocument document) {
  var images = document.images;
  var changed = false;
  void visit(VsdxShape shape) {
    final part = shape.imagePartName;
    if (part != null && images.findByPart(part) == null) {
      final image = drawioStencilImageForPart(part);
      if (image != null) {
        images = images.withImage(image);
        changed = true;
      }
    }
    for (final child in shape.children) {
      visit(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      visit(shape);
    }
  }
  return changed ? document.copyWith(images: images) : document;
}
