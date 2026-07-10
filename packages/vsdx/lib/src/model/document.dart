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
import 'image.dart';
import 'master.dart';
import 'page.dart';
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

  /// Smallest page id greater than every existing page id.
  int nextPageId() {
    var maxId = -1;
    for (final p in pages) {
      if (p.id > maxId) maxId = p.id;
    }
    return maxId + 1;
  }

  /// Insert [page] at [index] (clamped).
  VsdxDocument insertPage(int index, VsdxPage page) {
    final newPages = List<VsdxPage>.of(pages)
      ..insert(index.clamp(0, pages.length), page);
    return copyWith(pages: newPages);
  }

  /// Remove the page at [index]. Out-of-range indices return `this`.
  VsdxDocument removePageAt(int index) {
    if (index < 0 || index >= pages.length) return this;
    final newPages = List<VsdxPage>.of(pages)..removeAt(index);
    return copyWith(pages: newPages);
  }

  @override
  String toString() =>
      'VsdxDocument(title: $title, pages: ${pages.length}, '
      'masters: ${masters.length})';
}
