import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vsdx/vsdx.dart';

import 'editor_controller.dart';

typedef ExternalLinkLauncher = Future<bool> Function(Uri uri);

enum HyperlinkOpenResult {
  openedInternal,
  openedExternal,
  invalidTarget,
  targetNotFound,
  launchFailed,
}

/// Resolves the common Visio/draw.io in-document page-anchor forms.
@visibleForTesting
int? resolveInternalPageIndex(VsdxDocument? document, String rawTarget) {
  if (document == null) return null;
  var target = rawTarget.trim();
  if (target.startsWith('#')) target = target.substring(1);
  try {
    target = Uri.decodeFull(target);
  } on FormatException {
    // Malformed escapes are still useful as a literal page name.
  }
  target = target.trim();
  if (target.length >= 2 &&
      ((target.startsWith('"') && target.endsWith('"')) ||
          (target.startsWith("'") && target.endsWith("'")))) {
    target = target.substring(1, target.length - 1).trim();
  }

  // Visio may append a shape/bookmark after a page name.
  final separator = <int>[
    target.indexOf('/'),
    target.indexOf('!'),
  ].where((index) => index >= 0).fold<int?>(
        null,
        (best, index) => best == null || index < best ? index : best,
      );
  final pageTarget =
      separator == null ? target : target.substring(0, separator).trim();
  final normalized = pageTarget.toLowerCase();
  final nameIndex = document.pages.indexWhere(
    (page) => page.name.trim().toLowerCase() == normalized,
  );
  if (nameIndex >= 0) return nameIndex;

  final pageIdMatch =
      RegExp(r'^page-?(\d+)$', caseSensitive: false).firstMatch(pageTarget);
  if (pageIdMatch == null) return null;
  final pageId = int.tryParse(pageIdMatch.group(1)!);
  if (pageId == null) return null;
  final idIndex = document.pages.indexWhere((page) => page.id == pageId);
  return idIndex >= 0 ? idIndex : null;
}

/// Opens the selected shape's primary hyperlink.
///
/// Internal `#Page-X` links switch pages in-app. External links are delegated
/// to the platform and limited to schemes that cannot execute page content.
Future<HyperlinkOpenResult> openPrimaryHyperlink(
  EditorController controller, {
  ExternalLinkLauncher? launcher,
}) async {
  final link = controller.selectedLink;
  final target = link?.effectiveTarget?.trim();
  if (link == null || target == null || target.isEmpty) {
    return HyperlinkOpenResult.invalidTarget;
  }

  final address = link.address?.trim() ?? '';
  if (address.isEmpty) {
    final pageIndex =
        resolveInternalPageIndex(controller.document, link.subAddress ?? target);
    if (pageIndex == null) return HyperlinkOpenResult.targetNotFound;
    controller.selectPage(pageIndex);
    return HyperlinkOpenResult.openedInternal;
  }

  var externalTarget = target;
  if (externalTarget.toLowerCase().startsWith('www.')) {
    externalTarget = 'https://$externalTarget';
  }
  Uri? uri;
  try {
    uri = externalTarget.startsWith('/')
        ? Uri.file(externalTarget)
        : Uri.parse(externalTarget);
  } on FormatException {
    return HyperlinkOpenResult.invalidTarget;
  }
  const allowedSchemes = <String>{
    'http',
    'https',
    'mailto',
    'tel',
    'sms',
    'file',
  };
  if (!uri.hasScheme || !allowedSchemes.contains(uri.scheme.toLowerCase())) {
    return HyperlinkOpenResult.invalidTarget;
  }

  try {
    final opened = launcher == null
        ? await launchUrl(uri, mode: LaunchMode.externalApplication)
        : await launcher(uri);
    return opened
        ? HyperlinkOpenResult.openedExternal
        : HyperlinkOpenResult.launchFailed;
  } catch (_) {
    return HyperlinkOpenResult.launchFailed;
  }
}
