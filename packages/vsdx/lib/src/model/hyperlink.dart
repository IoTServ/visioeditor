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
///     <Cell N="ExtraInfo" V=""/>
///     <Cell N="Frame" V=""/>
///     <Cell N="NewWindow" V="0"/>
///     <Cell N="Default" V="0"/>
///     <Cell N="Invisible" V="0"/>
///     <Cell N="SortKey" V=""/>
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
    this.addressFormula,
    this.subAddress,
    this.extraInfo,
    this.frame,
    this.newWindow = false,
    this.isDefault = false,
    this.invisible = false,
    this.sortKey,
  });

  /// Row IX within the section.
  final int id;

  /// User-facing label.
  final String? description;

  /// External URL (mailto:/file:/http: etc). When `null` the link is an
  /// in-document jump expressed via [subAddress] (e.g. `#Page-2`).
  final String? address;

  /// Optional `F=` on Address (parametric / HYPERLINK formulas).
  final String? addressFormula;

  /// In-document target — usually a page name prefixed with `#`. Can also
  /// reference a specific shape or named bookmark.
  final String? subAddress;

  /// `ExtraInfo` — additional query / fragment payload Visio stores separately.
  final String? extraInfo;

  /// HTML target frame name (mostly `_blank` / `_self`).
  final String? frame;

  /// Hint to open in a new window/tab.
  final bool newWindow;

  /// The row marked as the shape's primary hyperlink.
  final bool isDefault;

  /// `Invisible` — hide from Visio's hyperlink UI when true.
  final bool invisible;

  /// `SortKey` — ordering hint among multiple links.
  final String? sortKey;

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
    String? addressFormula,
    String? subAddress,
    String? extraInfo,
    String? frame,
    bool? newWindow,
    bool? isDefault,
    bool? invisible,
    String? sortKey,
    bool clearExtraInfo = false,
    bool clearFrame = false,
    bool clearSortKey = false,
    bool clearAddressFormula = false,
    bool clearDescription = false,
    bool clearAddress = false,
    bool clearSubAddress = false,
  }) =>
      VsdxHyperlink(
        id: id ?? this.id,
        description:
            clearDescription ? null : (description ?? this.description),
        address: clearAddress ? null : (address ?? this.address),
        addressFormula: clearAddressFormula
            ? null
            : (addressFormula ?? this.addressFormula),
        subAddress:
            clearSubAddress ? null : (subAddress ?? this.subAddress),
        extraInfo: clearExtraInfo ? null : (extraInfo ?? this.extraInfo),
        frame: clearFrame ? null : (frame ?? this.frame),
        newWindow: newWindow ?? this.newWindow,
        isDefault: isDefault ?? this.isDefault,
        invisible: invisible ?? this.invisible,
        sortKey: clearSortKey ? null : (sortKey ?? this.sortKey),
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxHyperlink &&
      other.id == id &&
      other.description == description &&
      other.address == address &&
      other.addressFormula == addressFormula &&
      other.subAddress == subAddress &&
      other.extraInfo == extraInfo &&
      other.frame == frame &&
      other.newWindow == newWindow &&
      other.isDefault == isDefault &&
      other.invisible == invisible &&
      other.sortKey == sortKey;

  @override
  int get hashCode => Object.hash(
        id,
        description,
        address,
        addressFormula,
        subAddress,
        extraInfo,
        frame,
        newWindow,
        isDefault,
        invisible,
        sortKey,
      );

  @override
  String toString() =>
      'VsdxHyperlink(#$id, desc=$description, addr=$address, sub=$subAddress)';
}
