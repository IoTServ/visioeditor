/// Visio "Connect" entries — the wiring between a 1-D connector shape and
/// the shapes it touches at each end.
///
/// On a real Visio document the `<Connects>` block lives at the page level
/// (one entry per glued endpoint). Each entry has:
///   * `FromSheet` — the connector shape id
///   * `FromCell`  — `BeginX` or `EndX` (which end of the connector)
///   * `FromPart`  — numeric part code (0 = start, 9 = end, …)
///   * `ToSheet`   — the target shape id
///   * `ToCell`    — usually `PinX` (the centre) or a named connection point
///   * `ToPart`    — `3` = whole shape, otherwise an index into the target's
///     `<Section N="Connection">` rows.
///
/// We keep these as raw integers / strings so downstream layers (router,
/// hit-test, export) can decide how to resolve them.
library;

import 'package:meta/meta.dart';

@immutable
class VsdxConnect {
  const VsdxConnect({
    required this.fromSheetId,
    required this.fromCell,
    required this.toSheetId,
    required this.toCell,
    this.fromPart,
    this.toPart,
  });

  final int fromSheetId;
  final String fromCell;
  final int? fromPart;
  final int toSheetId;
  final String toCell;
  final int? toPart;

  /// `true` if this entry describes a connector's *begin* endpoint.
  bool get isBegin =>
      fromCell.toLowerCase().contains('beginx') ||
      fromCell.toLowerCase() == 'begin' ||
      fromPart == 9;

  /// `true` if this entry describes a connector's *end* endpoint.
  bool get isEnd =>
      fromCell.toLowerCase().contains('endx') ||
      fromCell.toLowerCase() == 'end' ||
      fromPart == 12;

  @override
  String toString() =>
      'VsdxConnect($fromSheetId.$fromCell → $toSheetId.$toCell '
      '${fromPart == null ? '' : '[${fromPart!}]'})';
}

/// A lightweight index of all connects on a page, grouped by connector
/// shape id for O(1) lookup during routing / inspection.
@immutable
class ConnectIndex {
  ConnectIndex(Iterable<VsdxConnect> entries)
      : _byConnector = _group(entries);

  final Map<int, List<VsdxConnect>> _byConnector;

  static const ConnectIndex empty = ConnectIndex._empty();
  const ConnectIndex._empty() : _byConnector = const {};

  /// All connect entries that originate from connector shape [shapeId].
  List<VsdxConnect> forConnector(int shapeId) =>
      _byConnector[shapeId] ?? const <VsdxConnect>[];

  int get length =>
      _byConnector.values.fold(0, (acc, list) => acc + list.length);

  /// Find every shape the given connector touches (target shape ids).
  List<int> targetsOf(int connectorId) {
    final ws = forConnector(connectorId);
    return [for (final c in ws) c.toSheetId];
  }

  static Map<int, List<VsdxConnect>> _group(Iterable<VsdxConnect> entries) {
    final out = <int, List<VsdxConnect>>{};
    for (final c in entries) {
      out.putIfAbsent(c.fromSheetId, () => <VsdxConnect>[]).add(c);
    }
    return Map.unmodifiable(
      out.map((k, v) => MapEntry(k, List<VsdxConnect>.unmodifiable(v))),
    );
  }
}
