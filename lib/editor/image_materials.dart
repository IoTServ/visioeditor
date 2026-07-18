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

const List<ImageMaterialGroup> kImageMaterialGroups = <ImageMaterialGroup>[
  ImageMaterialGroup('People', <ImageMaterial>[
    ImageMaterial(
        id: 'person', name: 'Person', assetPath: 'assets/materials/person.png'),
    ImageMaterial(
        id: 'users', name: 'Users', assetPath: 'assets/materials/users.png'),
  ]),
  ImageMaterialGroup('IT', <ImageMaterial>[
    ImageMaterial(
        id: 'server', name: 'Server', assetPath: 'assets/materials/server.png'),
    ImageMaterial(
        id: 'database',
        name: 'Database',
        assetPath: 'assets/materials/database.png'),
    ImageMaterial(
        id: 'cloud', name: 'Cloud', assetPath: 'assets/materials/cloud.png'),
    ImageMaterial(
        id: 'laptop', name: 'Laptop', assetPath: 'assets/materials/laptop.png'),
    ImageMaterial(
        id: 'phone', name: 'Phone', assetPath: 'assets/materials/phone.png'),
    ImageMaterial(
        id: 'globe', name: 'Globe', assetPath: 'assets/materials/globe.png'),
  ]),
  ImageMaterialGroup('Office', <ImageMaterial>[
    ImageMaterial(
        id: 'document',
        name: 'Document',
        assetPath: 'assets/materials/document.png'),
    ImageMaterial(
        id: 'folder', name: 'Folder', assetPath: 'assets/materials/folder.png'),
    ImageMaterial(
        id: 'email', name: 'Email', assetPath: 'assets/materials/email.png'),
    ImageMaterial(
        id: 'building',
        name: 'Building',
        assetPath: 'assets/materials/building.png'),
    ImageMaterial(
        id: 'calendar',
        name: 'Calendar',
        assetPath: 'assets/materials/calendar.png'),
    ImageMaterial(
        id: 'printer',
        name: 'Printer',
        assetPath: 'assets/materials/printer.png'),
  ]),
  ImageMaterialGroup('Status', <ImageMaterial>[
    ImageMaterial(
        id: 'lock', name: 'Lock', assetPath: 'assets/materials/lock.png'),
    ImageMaterial(
        id: 'warning',
        name: 'Warning',
        assetPath: 'assets/materials/warning.png'),
    ImageMaterial(
        id: 'check', name: 'Check', assetPath: 'assets/materials/check.png'),
    ImageMaterial(
        id: 'settings',
        name: 'Settings',
        assetPath: 'assets/materials/settings.png'),
    ImageMaterial(
        id: 'chart', name: 'Chart', assetPath: 'assets/materials/chart.png'),
    ImageMaterial(
        id: 'camera', name: 'Camera', assetPath: 'assets/materials/camera.png'),
  ]),
];

final List<ImageMaterial> kImageMaterials = <ImageMaterial>[
  for (final g in kImageMaterialGroups) ...g.items,
];
