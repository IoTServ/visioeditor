/// Heuristic classifier for [VsdxShapeKind].
///
/// We intentionally stay below full Visio container-relationship parsing —
/// that needs `<Rel>` rows and List/Swimlane membership sections which vary
/// wildly between stencil packs. Instead we key off the attributes Visio
/// *always* writes: `Type`, `Master.NameU`, shape `NameU`, and a handful of
/// well-known user-property labels.
library;

import '../model/shape_kind.dart';
import '../model/user_property.dart';

class ShapeKindDetector {
  const ShapeKindDetector();

  VsdxShapeKind detect({
    required String? xmlType,
    required String name,
    required String? masterName,
    required bool is1D,
    required bool hasImage,
    required int childCount,
    List<VsdxUserProperty> userProperties = const [],
  }) {
    if (hasImage) return VsdxShapeKind.picture;
    if (is1D) return VsdxShapeKind.connector;

    final master = (masterName ?? '').toLowerCase();
    final label = name.toLowerCase();

    if (_looksLikeCallout(master, label)) return VsdxShapeKind.callout;
    if (_looksLikeSwimlane(master, label, userProperties)) {
      return VsdxShapeKind.swimlane;
    }
    if (_looksLikeContainer(master, label, userProperties)) {
      return VsdxShapeKind.container;
    }
    if (childCount > 0 || xmlType == 'Group') return VsdxShapeKind.group;
    return VsdxShapeKind.normal;
  }

  bool _looksLikeCallout(String master, String label) {
    const keys = ['callout', 'annotation', 'speech bubble', 'comment bubble'];
    return keys.any((k) => master.contains(k) || label.contains(k));
  }

  bool _looksLikeSwimlane(
    String master,
    String label,
    List<VsdxUserProperty> props,
  ) {
    const keys = [
      'swimlane',
      'swim lane',
      'cross-functional',
      'cross functional',
      'lane (vertical)',
      'lane (horizontal)',
      'phase',
    ];
    if (keys.any((k) => master.contains(k) || label.contains(k))) return true;
    return props.any((p) {
      final n = p.name.toLowerCase();
      return n.contains('swimlane') || n.contains('lane');
    });
  }

  bool _looksLikeContainer(
    String master,
    String label,
    List<VsdxUserProperty> props,
  ) {
    const keys = [
      'container',
      'list box',
      'list item',
      'bpmn pool',
      'pool/lane',
      'subprocess',
    ];
    if (keys.any((k) => master.contains(k) || label.contains(k))) return true;
    return props.any((p) {
      final n = p.name.toLowerCase();
      return n.contains('container') || n == 'list';
    });
  }
}
