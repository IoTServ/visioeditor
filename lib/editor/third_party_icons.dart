import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// An open-source icon from a third-party pack, insertable as a picture node.
class ThirdPartyIcon {
  const ThirdPartyIcon({
    required this.id,
    required this.name,
    required this.icon,
    this.keywords = const <String>[],
  });

  /// Stable id within its provider (e.g. `cloud`).
  final String id;

  /// English display name.
  final String name;

  final IconData icon;

  /// Extra search terms (lowercase).
  final List<String> keywords;
}

/// One icon provider (license is free for commercial use).
class ThirdPartyIconProvider {
  const ThirdPartyIconProvider({
    required this.id,
    required this.name,
    required this.license,
    required this.icons,
  });

  final String id;
  final String name;

  /// Short license label shown in the palette footer.
  final String license;

  final List<ThirdPartyIcon> icons;
}

/// Default edge length (inches) when inserting a rasterised icon.
const double kThirdPartyIconMaxInches = 0.75;

/// Pixel size used when painting an [IconData] to PNG.
const int kThirdPartyIconRasterPx = 128;

ThirdPartyIcon _i(String id, String name, IconData icon,
        [List<String> keywords = const <String>[]]) =>
    ThirdPartyIcon(id: id, name: name, icon: icon, keywords: keywords);

/// Curated diagram-friendly icons from free/commercial-friendly packs.
/// Grouped by provider for the palette; searchable by name / keywords.
final List<ThirdPartyIconProvider> kThirdPartyIconProviders =
    <ThirdPartyIconProvider>[
  ThirdPartyIconProvider(
    id: 'material',
    name: 'Material Icons',
    license: 'Apache-2.0',
    icons: <ThirdPartyIcon>[
      _i('person', 'Person', Icons.person_outline, const ['user', 'people']),
      _i('group', 'Group', Icons.group_outlined, const ['users', 'team']),
      _i('dns', 'Server', Icons.dns_outlined, const ['server', 'host']),
      _i('storage', 'Database', Icons.storage_outlined, const ['db', 'data']),
      _i('cloud', 'Cloud', Icons.cloud_outlined),
      _i('laptop', 'Laptop', Icons.laptop_outlined, const ['computer']),
      _i('phone', 'Phone', Icons.phone_android_outlined, const ['mobile']),
      _i('public', 'Globe', Icons.public_outlined, const ['world', 'web']),
      _i('description', 'Document', Icons.description_outlined,
          const ['file', 'doc']),
      _i('folder', 'Folder', Icons.folder_outlined),
      _i('email', 'Email', Icons.email_outlined, const ['mail']),
      _i('business', 'Building', Icons.business_outlined, const ['office']),
      _i('calendar', 'Calendar', Icons.calendar_today_outlined),
      _i('print', 'Printer', Icons.print_outlined),
      _i('lock', 'Lock', Icons.lock_outline, const ['security']),
      _i('warning', 'Warning', Icons.warning_amber_outlined, const ['alert']),
      _i('check', 'Check', Icons.check_circle_outline, const ['ok', 'done']),
      _i('settings', 'Settings', Icons.settings_outlined, const ['gear']),
      _i('bar_chart', 'Chart', Icons.bar_chart_outlined, const ['analytics']),
      _i('camera', 'Camera', Icons.photo_camera_outlined),
      _i('wifi', 'Wi‑Fi', Icons.wifi_outlined, const ['network']),
      _i('shield', 'Shield', Icons.shield_outlined, const ['security']),
      _i('home', 'Home', Icons.home_outlined),
      _i('link', 'Link', Icons.link, const ['url']),
      _i('search', 'Search', Icons.search),
      _i('download', 'Download', Icons.download_outlined),
      _i('upload', 'Upload', Icons.upload_outlined),
      _i('code', 'Code', Icons.code, const ['developer']),
      _i('bug', 'Bug', Icons.bug_report_outlined),
      _i('rocket', 'Rocket', Icons.rocket_launch_outlined, const ['launch']),
      _i('bolt', 'Bolt', Icons.bolt_outlined, const ['zap', 'power']),
      _i('key', 'Key', Icons.key_outlined),
      _i('map', 'Map', Icons.map_outlined),
      _i('chat', 'Chat', Icons.chat_bubble_outline, const ['message']),
      _i('image', 'Image', Icons.image_outlined),
      _i('videocam', 'Video', Icons.videocam_outlined),
    ],
  ),
  ThirdPartyIconProvider(
    id: 'lucide',
    name: 'Lucide',
    license: 'ISC',
    icons: <ThirdPartyIcon>[
      _i('user', 'User', LucideIcons.user, const ['person']),
      _i('users', 'Users', LucideIcons.users, const ['group', 'team']),
      _i('server', 'Server', LucideIcons.server),
      _i('database', 'Database', LucideIcons.database, const ['db']),
      _i('cloud', 'Cloud', LucideIcons.cloud),
      _i('laptop', 'Laptop', LucideIcons.laptop, const ['computer']),
      _i('smartphone', 'Phone', LucideIcons.smartphone, const ['mobile']),
      _i('globe', 'Globe', LucideIcons.globe, const ['world', 'web']),
      _i('file', 'File', LucideIcons.file, const ['document']),
      _i('file_text', 'Document', LucideIcons.file_text, const ['doc']),
      _i('folder', 'Folder', LucideIcons.folder),
      _i('mail', 'Mail', LucideIcons.mail, const ['email']),
      _i('building', 'Building', LucideIcons.building, const ['office']),
      _i('calendar', 'Calendar', LucideIcons.calendar),
      _i('printer', 'Printer', LucideIcons.printer),
      _i('lock', 'Lock', LucideIcons.lock, const ['security']),
      _i('triangle_alert', 'Warning', LucideIcons.triangle_alert,
          const ['alert']),
      _i('circle_check', 'Check', LucideIcons.circle_check, const ['ok']),
      _i('settings', 'Settings', LucideIcons.settings, const ['gear']),
      _i('chart_bar', 'Chart', LucideIcons.chart_bar, const ['analytics']),
      _i('camera', 'Camera', LucideIcons.camera),
      _i('wifi', 'Wi‑Fi', LucideIcons.wifi, const ['network']),
      _i('shield', 'Shield', LucideIcons.shield, const ['security']),
      _i('house', 'Home', LucideIcons.house),
      _i('link', 'Link', LucideIcons.link, const ['url']),
      _i('search', 'Search', LucideIcons.search),
      _i('download', 'Download', LucideIcons.download),
      _i('upload', 'Upload', LucideIcons.upload),
      _i('code', 'Code', LucideIcons.code),
      _i('bug', 'Bug', LucideIcons.bug),
      _i('rocket', 'Rocket', LucideIcons.rocket, const ['launch']),
      _i('zap', 'Zap', LucideIcons.zap, const ['bolt', 'power']),
      _i('key', 'Key', LucideIcons.key),
      _i('map', 'Map', LucideIcons.map),
      _i('message_square', 'Message', LucideIcons.message_square,
          const ['chat']),
      _i('image', 'Image', LucideIcons.image),
      _i('video', 'Video', LucideIcons.video),
      _i('hard_drive', 'Hard Drive', LucideIcons.hard_drive, const ['disk']),
      _i('network', 'Network', LucideIcons.network),
      _i('cpu', 'CPU', LucideIcons.cpu, const ['processor']),
      _i('monitor', 'Monitor', LucideIcons.monitor, const ['display']),
      _i('briefcase', 'Briefcase', LucideIcons.briefcase, const ['work']),
      _i('layers', 'Layers', LucideIcons.layers),
      _i('package', 'Package', LucideIcons.package, const ['box']),
      _i('terminal', 'Terminal', LucideIcons.terminal, const ['console']),
      _i('git_branch', 'Git Branch', LucideIcons.git_branch, const ['git']),
      _i('bot', 'Bot', LucideIcons.bot, const ['robot', 'ai']),
      _i('sparkles', 'Sparkles', LucideIcons.sparkles, const ['ai', 'magic']),
    ],
  ),
  ThirdPartyIconProvider(
    id: 'phosphor',
    name: 'Phosphor',
    license: 'MIT',
    icons: <ThirdPartyIcon>[
      _i('user', 'User', PhosphorIconsRegular.user, const ['person']),
      _i('users', 'Users', PhosphorIconsRegular.users, const ['group']),
      _i('hard_drives', 'Server', PhosphorIconsRegular.hardDrives,
          const ['server', 'host']),
      _i('database', 'Database', PhosphorIconsRegular.database, const ['db']),
      _i('cloud', 'Cloud', PhosphorIconsRegular.cloud),
      _i('laptop', 'Laptop', PhosphorIconsRegular.laptop, const ['computer']),
      _i('phone', 'Phone', PhosphorIconsRegular.deviceMobile, const ['mobile']),
      _i('globe', 'Globe', PhosphorIconsRegular.globe, const ['world']),
      _i('folder', 'Folder', PhosphorIconsRegular.folder),
      _i('mail', 'Mail', PhosphorIconsRegular.envelopeSimple, const ['email']),
      _i('building', 'Building', PhosphorIconsRegular.buildings,
          const ['office']),
      _i('calendar', 'Calendar', PhosphorIconsRegular.calendarBlank),
      _i('printer', 'Printer', PhosphorIconsRegular.printer),
      _i('lock', 'Lock', PhosphorIconsRegular.lock, const ['security']),
      _i('warning', 'Warning', PhosphorIconsRegular.warning, const ['alert']),
      _i('check', 'Check', PhosphorIconsRegular.checkCircle, const ['ok']),
      _i('settings', 'Settings', PhosphorIconsRegular.gear, const ['gear']),
      _i('chart', 'Chart', PhosphorIconsRegular.chartBar, const ['analytics']),
      _i('camera', 'Camera', PhosphorIconsRegular.camera),
      _i('wifi', 'Wi‑Fi', PhosphorIconsRegular.wifiHigh, const ['network']),
      _i('shield', 'Shield', PhosphorIconsRegular.shield, const ['security']),
      _i('house', 'Home', PhosphorIconsRegular.house),
      _i('link', 'Link', PhosphorIconsRegular.link, const ['url']),
      _i('search', 'Search', PhosphorIconsRegular.magnifyingGlass),
      _i('download', 'Download', PhosphorIconsRegular.downloadSimple),
      _i('upload', 'Upload', PhosphorIconsRegular.uploadSimple),
      _i('image', 'Image', PhosphorIconsRegular.image),
      _i('video', 'Video', PhosphorIconsRegular.videoCamera),
      _i('hard_drive', 'Hard Drive', PhosphorIconsRegular.hardDrive),
      _i('desktop', 'Desktop', PhosphorIconsRegular.desktopTower,
          const ['computer', 'pc']),
      _i('info', 'Info', PhosphorIconsRegular.info),
      _i('question', 'Help', PhosphorIconsRegular.question, const ['help']),
      _i('heart', 'Heart', PhosphorIconsRegular.heart),
      _i('star', 'Star', PhosphorIconsRegular.star),
      _i('bell', 'Bell', PhosphorIconsRegular.bell, const ['notification']),
      _i('tag', 'Tag', PhosphorIconsRegular.tag),
      _i('bookmark', 'Bookmark', PhosphorIconsRegular.bookmarkSimple),
      _i('pencil', 'Edit', PhosphorIconsRegular.pencilSimple, const ['edit']),
      _i('trash', 'Trash', PhosphorIconsRegular.trash, const ['delete']),
      _i('map_pin', 'Map Pin', PhosphorIconsRegular.mapPin, const ['location']),
      _i('music', 'Music', PhosphorIconsRegular.musicNote),
      _i('plus', 'Plus', PhosphorIconsRegular.plus, const ['add']),
      _i('minus', 'Minus', PhosphorIconsRegular.minus),
    ],
  ),
];

/// True if [icon] matches a lowercase [query] (name, id, or keywords).
bool thirdPartyIconMatches(ThirdPartyIcon icon, String query) {
  if (query.isEmpty) return true;
  if (icon.name.toLowerCase().contains(query)) return true;
  if (icon.id.toLowerCase().contains(query)) return true;
  for (final k in icon.keywords) {
    if (k.contains(query)) return true;
  }
  return false;
}

/// Paint [icon] to a transparent PNG suitable for embedding in the document.
Future<Uint8List> rasterizeThirdPartyIcon(
  IconData icon, {
  int size = kThirdPartyIconRasterPx,
  Color color = const Color(0xFF243040),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final fontSize = size * 0.72;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = (size - tp.width) / 2;
  final dy = (size - tp.height) / 2;
  tp.paint(canvas, Offset(dx, dy));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) return Uint8List(0);
  return bytes.buffer.asUint8List();
}
