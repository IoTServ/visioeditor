/// Emit DrawingML `theme1.xml` from a [VsdxTheme] colour palette.
///
/// Visio / OOXML theme parts carry fonts and effects as well; we emit a
/// minimal but valid stub (`fontScheme` / `fmtScheme`) so packages without an
/// existing theme part still open in Visio / Edraw. When an existing theme is
/// being updated the writer prefers patching only `<a:clrScheme>`.
library;

import 'package:xml/xml.dart';

import '../model/theme.dart';
import '../parser/theme_parser.dart';
import '../utils/color.dart';

/// Serialises / patches DrawingML theme colour schemes.
abstract final class ThemeSerializer {
  ThemeSerializer._();

  static const String drawingMlNs =
      'http://schemas.openxmlformats.org/drawingml/2006/main';

  /// Slot local-name → [ThemeSlot] id (inverse of [ThemeParser] map).
  static const Map<int, String> _nameForSlot = <int, String>{
    ThemeSlot.dk1: 'dk1',
    ThemeSlot.lt1: 'lt1',
    ThemeSlot.dk2: 'dk2',
    ThemeSlot.lt2: 'lt2',
    ThemeSlot.accent1: 'accent1',
    ThemeSlot.accent2: 'accent2',
    ThemeSlot.accent3: 'accent3',
    ThemeSlot.accent4: 'accent4',
    ThemeSlot.accent5: 'accent5',
    ThemeSlot.accent6: 'accent6',
    ThemeSlot.hyperlink: 'hlink',
    ThemeSlot.followedHyperlink: 'folHlink',
  };

  /// Full `theme1.xml` document for [theme]. [name] labels the theme / scheme.
  static String emit(VsdxTheme theme, {String name = 'Office'}) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<a:theme xmlns:a="$drawingMlNs" name="${_esc(name)}">',
      )
      ..writeln('  <a:themeElements>')
      ..writeln('    <a:clrScheme name="${_esc(name)}">');
    for (final e in _nameForSlot.entries) {
      final c = theme.resolve(e.key) ?? _fallback(e.key);
      buf.writeln(
        '      <a:${e.value}><a:srgbClr val="${_rgbHex(c)}"/></a:${e.value}>',
      );
    }
    buf
      ..writeln('    </a:clrScheme>')
      ..writeln('    <a:fontScheme name="${_esc(name)}">')
      ..writeln(
        '      <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/>'
        '<a:cs typeface=""/></a:majorFont>',
      )
      ..writeln(
        '      <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/>'
        '<a:cs typeface=""/></a:minorFont>',
      )
      ..writeln('    </a:fontScheme>')
      ..writeln('    <a:fmtScheme name="${_esc(name)}">')
      ..writeln(
        '      <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/>'
        '</a:solidFill></a:fillStyleLst>',
      )
      ..writeln(
        '      <a:lnStyleLst><a:ln w="12700"><a:solidFill>'
        '<a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>',
      )
      ..writeln(
        '      <a:effectStyleLst><a:effectStyle><a:effectLst/>'
        '</a:effectStyle></a:effectStyleLst>',
      )
      ..writeln(
        '      <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/>'
        '</a:solidFill></a:bgFillStyleLst>',
      )
      ..writeln('    </a:fmtScheme>')
      ..writeln('  </a:themeElements>')
      ..writeln('  <a:objectDefaults/>')
      ..writeln('</a:theme>');
    return buf.toString();
  }

  /// Replace colours inside an existing theme document's `<a:clrScheme>`.
  /// Returns `true` when anything changed. Leaves font/effect sections intact.
  /// When [name] is set, updates `a:theme` / `a:clrScheme` `@name` attributes.
  static bool patchClrScheme(
    XmlDocument doc,
    VsdxTheme theme, {
    String? name,
  }) {
    XmlElement? scheme;
    XmlElement? themeRoot;
    for (final node in doc.descendants) {
      if (node is! XmlElement) continue;
      if (node.name.local == 'theme' && themeRoot == null) themeRoot = node;
      if (node.name.local == 'clrScheme' && scheme == null) scheme = node;
    }
    if (scheme == null) return false;
    var changed = false;
    if (name != null) {
      if (themeRoot != null && themeRoot.getAttribute('name') != name) {
        themeRoot.setAttribute('name', name);
        changed = true;
      }
      if (scheme.getAttribute('name') != name) {
        scheme.setAttribute('name', name);
        changed = true;
      }
    }
    final present = <int>{};
    for (final el in scheme.childElements) {
      final slot = ThemeParser.slotForName(el.name.local);
      if (slot == null) continue;
      present.add(slot);
      final want = theme.resolve(slot);
      if (want == null) continue;
      final hex = _rgbHex(want);
      // Prefer updating an existing srgbClr; otherwise replace children.
      XmlElement? srgb;
      for (final c in el.childElements) {
        if (c.name.local == 'srgbClr') {
          srgb = c;
          break;
        }
      }
      if (srgb != null) {
        final cur = (srgb.getAttribute('val') ?? '').toUpperCase();
        if (cur != hex) {
          srgb.setAttribute('val', hex);
          changed = true;
        }
        continue;
      }
      // sysClr or empty — replace with srgbClr.
      el.children.clear();
      el.children.add(XmlElement(
        XmlName('srgbClr', 'a'),
        <XmlAttribute>[XmlAttribute(XmlName('val'), hex)],
      ));
      changed = true;
    }
    // Append any slots present in [theme] but missing from the scheme.
    for (final e in _nameForSlot.entries) {
      if (present.contains(e.key)) continue;
      final want = theme.resolve(e.key);
      if (want == null) continue;
      scheme.children.add(XmlElement(
        XmlName(e.value, 'a'),
        const <XmlAttribute>[],
        <XmlNode>[
          XmlElement(
            XmlName('srgbClr', 'a'),
            <XmlAttribute>[XmlAttribute(XmlName('val'), _rgbHex(want))],
          ),
        ],
      ));
      changed = true;
    }
    return changed;
  }

  /// Builtin display name for [theme], or `Custom` / `Office`.
  static String nameFor(VsdxTheme theme) {
    for (final t in VsdxTheme.builtins) {
      if (_themesEqual(t.theme, theme)) return t.name;
    }
    return theme.isEmpty ? 'Office' : 'Custom';
  }

  static bool themesEqual(VsdxTheme a, VsdxTheme b) => _themesEqual(a, b);

  static bool _themesEqual(VsdxTheme a, VsdxTheme b) {
    if (identical(a, b)) return true;
    if (a.colors.length != b.colors.length) return false;
    for (final e in a.colors.entries) {
      if (b.colors[e.key]?.value != e.value.value) return false;
    }
    return true;
  }

  static VsdxColor _fallback(int slot) =>
      VsdxTheme.office.resolve(slot) ?? VsdxColor.black;

  static String _rgbHex(VsdxColor c) {
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '$r$g$b'.toUpperCase();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
