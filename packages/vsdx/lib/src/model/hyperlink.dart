/// Visio Hyperlink Section row.
///
/// MS-VSDX §"Hyperlink Section":
///
/// ```xml
/// <Section N="Hyperlink">
///   <Row IX="0">
///     <Cell N="Description" V="MS docs"/>
///     <Cell N="Address" V="https://learn.microsoft.com/visio"/>
///     <Cell N="SubAddress" V="#Page-2"/>
///     <Cell N="Frame" V=""/>
///     <Cell N="NewWindow" V="0"/>
///     <Cell N="Default" V="0"/>
///   </Row>
/// </Section>
/// ```
///
/// Each shape may carry multiple hyperlinks; the viewer treats the first
/// `Default == "1"` row (or, failing that, row IX=0) as the primary link
/// to invoke on tap.
library;

import 'package:meta/meta.dart';

@immutable
class VsdxHyperlink {
  const VsdxHyperlink({
    required this.id,
    this.description,
    this.address,
    this.subAddress,
    this.frame,
    this.newWindow = false,
    this.isDefault = false,
  });

  /// Row IX within the section.
  final int id;

  /// User-facing label.
  final String? description;

  /// External URL (mailto:/file:/http: etc). When `null` the link is an
  /// in-document jump expressed via [subAddress] (e.g. `#Page-2`).
  final String? address;

  /// In-document target — usually a page name prefixed with `#`. Can also
  /// reference a specific shape or named bookmark.
  final String? subAddress;

  /// HTML target frame name (mostly `_blank` / `_self`).
  final String? frame;

  /// Hint to open in a new window/tab.
  final bool newWindow;

  /// The row marked as the shape's primary hyperlink.
  final bool isDefault;

  /// Best-effort target for the click handler: the external URL if any,
  /// otherwise the in-document anchor.
  String? get effectiveTarget {
    final a = address?.trim();
    if (a != null && a.isNotEmpty) {
      if (subAddress != null && subAddress!.isNotEmpty) {
        // External URL with fragment.
        return a.contains('#') ? a : '$a$subAddress';
      }
      return a;
    }
    final s = subAddress?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  VsdxHyperlink copyWith({
    int? id,
    String? description,
    String? address,
    String? subAddress,
    String? frame,
    bool? newWindow,
    bool? isDefault,
  }) =>
      VsdxHyperlink(
        id: id ?? this.id,
        description: description ?? this.description,
        address: address ?? this.address,
        subAddress: subAddress ?? this.subAddress,
        frame: frame ?? this.frame,
        newWindow: newWindow ?? this.newWindow,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxHyperlink &&
      other.id == id &&
      other.description == description &&
      other.address == address &&
      other.subAddress == subAddress &&
      other.frame == frame &&
      other.newWindow == newWindow &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(
        id,
        description,
        address,
        subAddress,
        frame,
        newWindow,
        isDefault,
      );

  @override
  String toString() =>
      'VsdxHyperlink(#$id, desc=$description, addr=$address, sub=$subAddress)';
}
