/// Built-in image clipart for the materials palette.
///
/// Assets live under `assets/materials/` (64×64 PNGs). Insertion loads the
/// bytes and embeds them via [EditorController.insertImage] — these are not
/// geometric stencils.
class ImageMaterial {
  const ImageMaterial({
    required this.id,
    required this.name,
    required this.assetPath,
  });

  /// Stable id / filename stem (also used for l10n: `im_<id>`).
  final String id;

  /// English display name.
  final String name;

  /// Flutter asset path, e.g. `assets/materials/person.png`.
  final String assetPath;

  String get fileExtension => 'png';
}

class ImageMaterialGroup {
  const ImageMaterialGroup(this.name, this.items);

  final String name;
  final List<ImageMaterial> items;
}

/// Default max edge length (inches) when inserting a material image so large
/// source files cannot dominate the page. 64×64 @ 96 dpi is ~0.67".
const double kImageMaterialMaxInches = 1.0;

ImageMaterial _m(String id, String name) => ImageMaterial(
      id: id,
      name: name,
      assetPath: 'assets/materials/$id.png',
    );

/// Diagram-friendly clipart grouped for the materials sidebar.
final List<ImageMaterialGroup> kImageMaterialGroups = <ImageMaterialGroup>[
  ImageMaterialGroup('People', <ImageMaterial>[
    _m('person', 'Person'),
    _m('users', 'Users'),
    _m('manager', 'Manager'),
    _m('handshake', 'Handshake'),
  ]),
  ImageMaterialGroup('IT', <ImageMaterial>[
    _m('server', 'Server'),
    _m('database', 'Database'),
    _m('cloud', 'Cloud'),
    _m('laptop', 'Laptop'),
    _m('phone', 'Phone'),
    _m('globe', 'Globe'),
    _m('monitor', 'Monitor'),
    _m('hard_drive', 'Hard Drive'),
    _m('code', 'Code'),
  ]),
  ImageMaterialGroup('Office', <ImageMaterial>[
    _m('document', 'Document'),
    _m('folder', 'Folder'),
    _m('email', 'Email'),
    _m('building', 'Building'),
    _m('calendar', 'Calendar'),
    _m('printer', 'Printer'),
    _m('clipboard', 'Clipboard'),
    _m('briefcase', 'Briefcase'),
    _m('sticky_note', 'Sticky Note'),
  ]),
  ImageMaterialGroup('Status', <ImageMaterial>[
    _m('lock', 'Lock'),
    _m('warning', 'Warning'),
    _m('check', 'Check'),
    _m('cross', 'Cross'),
    _m('info', 'Info'),
    _m('settings', 'Settings'),
    _m('chart', 'Chart'),
    _m('camera', 'Camera'),
    _m('star', 'Star'),
    _m('bell', 'Bell'),
  ]),
  ImageMaterialGroup('Network', <ImageMaterial>[
    _m('wifi', 'Wifi'),
    _m('router', 'Router'),
    _m('firewall', 'Firewall'),
    _m('api', 'API'),
  ]),
  ImageMaterialGroup('Business', <ImageMaterial>[
    _m('lightbulb', 'Lightbulb'),
    _m('target', 'Target'),
    _m('flag', 'Flag'),
    _m('rocket', 'Rocket'),
    _m('clock', 'Clock'),
    _m('package', 'Package'),
    _m('map_pin', 'Map Pin'),
    _m('wallet', 'Wallet'),
  ]),
];

final List<ImageMaterial> kImageMaterials = <ImageMaterial>[
  for (final g in kImageMaterialGroups) ...g.items,
];
