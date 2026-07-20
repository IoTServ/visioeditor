import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vsdx/vsdx.dart';

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

/// Default ink colour for newly inserted icons.
const Color kThirdPartyIconDefaultColor = Color(0xFF243040);

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
      _i('badge', 'Badge', Icons.badge_outlined, const ['id', 'employee']),
      _i('dns', 'Server', Icons.dns_outlined, const ['server', 'host']),
      _i('storage', 'Database', Icons.storage_outlined, const ['db', 'data']),
      _i('cloud', 'Cloud', Icons.cloud_outlined),
      _i('cloud_queue', 'Cloud Queue', Icons.cloud_queue_outlined,
          const ['queue']),
      _i('laptop', 'Laptop', Icons.laptop_outlined, const ['computer']),
      _i('desktop', 'Desktop', Icons.desktop_windows_outlined, const ['pc']),
      _i('phone', 'Phone', Icons.phone_android_outlined, const ['mobile']),
      _i('tablet', 'Tablet', Icons.tablet_mac_outlined),
      _i('public', 'Globe', Icons.public_outlined, const ['world', 'web']),
      _i('description', 'Document', Icons.description_outlined,
          const ['file', 'doc']),
      _i('article', 'Article', Icons.article_outlined, const ['text']),
      _i('folder', 'Folder', Icons.folder_outlined),
      _i('email', 'Email', Icons.email_outlined, const ['mail']),
      _i('inbox', 'Inbox', Icons.inbox_outlined),
      _i('business', 'Building', Icons.business_outlined, const ['office']),
      _i('factory', 'Factory', Icons.factory_outlined, const ['plant']),
      _i('store', 'Store', Icons.storefront_outlined, const ['shop']),
      _i('calendar', 'Calendar', Icons.calendar_today_outlined),
      _i('schedule', 'Schedule', Icons.schedule_outlined, const ['time']),
      _i('print', 'Printer', Icons.print_outlined),
      _i('lock', 'Lock', Icons.lock_outline, const ['security']),
      _i('vpn_key', 'VPN Key', Icons.vpn_key_outlined, const ['key']),
      _i('warning', 'Warning', Icons.warning_amber_outlined, const ['alert']),
      _i('error', 'Error', Icons.error_outline, const ['fail']),
      _i('check', 'Check', Icons.check_circle_outline, const ['ok', 'done']),
      _i('cancel', 'Cancel', Icons.cancel_outlined, const ['close']),
      _i('settings', 'Settings', Icons.settings_outlined, const ['gear']),
      _i('tune', 'Tune', Icons.tune_outlined, const ['adjust']),
      _i('bar_chart', 'Chart', Icons.bar_chart_outlined, const ['analytics']),
      _i('pie_chart', 'Pie Chart', Icons.pie_chart_outline, const ['analytics']),
      _i('timeline', 'Timeline', Icons.timeline_outlined),
      _i('camera', 'Camera', Icons.photo_camera_outlined),
      _i('wifi', 'Wi‑Fi', Icons.wifi_outlined, const ['network']),
      _i('bluetooth', 'Bluetooth', Icons.bluetooth_outlined),
      _i('router', 'Router', Icons.router_outlined, const ['network']),
      _i('shield', 'Shield', Icons.shield_outlined, const ['security']),
      _i('home', 'Home', Icons.home_outlined),
      _i('apartment', 'Apartment', Icons.apartment_outlined),
      _i('link', 'Link', Icons.link, const ['url']),
      _i('search', 'Search', Icons.search),
      _i('download', 'Download', Icons.download_outlined),
      _i('upload', 'Upload', Icons.upload_outlined),
      _i('sync', 'Sync', Icons.sync_outlined, const ['refresh']),
      _i('code', 'Code', Icons.code, const ['developer']),
      _i('terminal', 'Terminal', Icons.terminal_outlined, const ['console']),
      _i('bug', 'Bug', Icons.bug_report_outlined),
      _i('rocket', 'Rocket', Icons.rocket_launch_outlined, const ['launch']),
      _i('bolt', 'Bolt', Icons.bolt_outlined, const ['zap', 'power']),
      _i('battery', 'Battery', Icons.battery_charging_full_outlined),
      _i('key', 'Key', Icons.key_outlined),
      _i('map', 'Map', Icons.map_outlined),
      _i('place', 'Place', Icons.place_outlined, const ['location', 'pin']),
      _i('chat', 'Chat', Icons.chat_bubble_outline, const ['message']),
      _i('forum', 'Forum', Icons.forum_outlined, const ['discussion']),
      _i('image', 'Image', Icons.image_outlined),
      _i('videocam', 'Video', Icons.videocam_outlined),
      _i('mic', 'Mic', Icons.mic_none_outlined, const ['audio']),
      _i('headphones', 'Headphones', Icons.headphones_outlined),
      _i('shopping', 'Cart', Icons.shopping_cart_outlined, const ['shop']),
      _i('payments', 'Payments', Icons.payments_outlined, const ['money']),
      _i('inventory', 'Inventory', Icons.inventory_2_outlined, const ['box']),
      _i('local_shipping', 'Shipping', Icons.local_shipping_outlined,
          const ['truck', 'delivery']),
      _i('hub', 'Hub', Icons.hub_outlined, const ['network', 'node']),
      _i('memory', 'Memory', Icons.memory_outlined, const ['chip', 'cpu']),
      _i('smart_toy', 'Robot', Icons.smart_toy_outlined, const ['bot', 'ai']),
      _i('psychology', 'AI', Icons.psychology_outlined, const ['brain', 'ai']),
      _i('extension', 'Extension', Icons.extension_outlined, const ['plugin']),
      _i('api', 'API', Icons.api_outlined, const ['integration']),
      _i('webhook', 'Webhook', Icons.webhook_outlined),
      _i('dataset', 'Dataset', Icons.dataset_outlined, const ['table']),
      _i('analytics', 'Analytics', Icons.analytics_outlined),
      _i('support', 'Support', Icons.support_agent_outlined, const ['help']),
      _i('verified', 'Verified', Icons.verified_outlined, const ['badge']),
      _i('fingerprint', 'Fingerprint', Icons.fingerprint, const ['biometric']),
      _i('visibility', 'Visibility', Icons.visibility_outlined, const ['eye']),
      _i('favorite', 'Favorite', Icons.favorite_outline, const ['heart']),
      _i('star', 'Star', Icons.star_outline),
      _i('flag', 'Flag', Icons.flag_outlined),
      _i('bookmark', 'Bookmark', Icons.bookmark_outline),
      _i('edit', 'Edit', Icons.edit_outlined, const ['pencil']),
      _i('delete', 'Delete', Icons.delete_outline, const ['trash']),
      _i('add', 'Add', Icons.add_circle_outline, const ['plus']),
      _i('remove', 'Remove', Icons.remove_circle_outline, const ['minus']),
      _i('layers', 'Layers', Icons.layers_outlined),
      _i('dashboard', 'Dashboard', Icons.dashboard_outlined),
      _i('widgets', 'Widgets', Icons.widgets_outlined),
      _i('account_tree', 'Tree', Icons.account_tree_outlined,
          const ['hierarchy', 'org']),
      _i('schema', 'Schema', Icons.schema_outlined, const ['diagram']),
      _i('device_hub', 'Device Hub', Icons.device_hub_outlined),
      _i('lan', 'LAN', Icons.lan_outlined, const ['ethernet']),
      _i('security', 'Security', Icons.security_outlined),
      _i('password', 'Password', Icons.password_outlined),
      _i('notifications', 'Notifications', Icons.notifications_outlined,
          const ['bell']),
      _i('lightbulb', 'Idea', Icons.lightbulb_outline, const ['idea']),
      _i('science', 'Science', Icons.science_outlined, const ['lab']),
      _i('biotech', 'Biotech', Icons.biotech_outlined),
      _i('health', 'Health', Icons.health_and_safety_outlined, const ['medical']),
      _i('school', 'School', Icons.school_outlined, const ['education']),
      _i('work', 'Work', Icons.work_outline, const ['briefcase']),
      _i('flight', 'Flight', Icons.flight_outlined, const ['plane']),
      _i('directions_car', 'Car', Icons.directions_car_outlined),
      _i('train', 'Train', Icons.train_outlined),
      _i('anchor', 'Anchor', Icons.anchor_outlined, const ['ship']),
      _i('park', 'Park', Icons.park_outlined, const ['nature']),
      _i('water', 'Water', Icons.water_drop_outlined),
      _i('energy', 'Energy', Icons.energy_savings_leaf_outlined,
          const ['green']),
    ],
  ),
  ThirdPartyIconProvider(
    id: 'lucide',
    name: 'Lucide',
    license: 'ISC',
    icons: <ThirdPartyIcon>[
      _i('user', 'User', LucideIcons.user, const ['person']),
      _i('users', 'Users', LucideIcons.users, const ['group', 'team']),
      _i('user_cog', 'User Settings', LucideIcons.user_cog),
      _i('server', 'Server', LucideIcons.server),
      _i('database', 'Database', LucideIcons.database, const ['db']),
      _i('cloud', 'Cloud', LucideIcons.cloud),
      _i('cloud_cog', 'Cloud Settings', LucideIcons.cloud_cog),
      _i('laptop', 'Laptop', LucideIcons.laptop, const ['computer']),
      _i('smartphone', 'Phone', LucideIcons.smartphone, const ['mobile']),
      _i('tablet', 'Tablet', LucideIcons.tablet),
      _i('globe', 'Globe', LucideIcons.globe, const ['world', 'web']),
      _i('file', 'File', LucideIcons.file, const ['document']),
      _i('file_text', 'Document', LucideIcons.file_text, const ['doc']),
      _i('files', 'Files', LucideIcons.files),
      _i('folder', 'Folder', LucideIcons.folder),
      _i('folder_open', 'Folder Open', LucideIcons.folder_open),
      _i('mail', 'Mail', LucideIcons.mail, const ['email']),
      _i('inbox', 'Inbox', LucideIcons.inbox),
      _i('building', 'Building', LucideIcons.building, const ['office']),
      _i('building_2', 'Buildings', LucideIcons.building_2),
      _i('factory', 'Factory', LucideIcons.factory),
      _i('store', 'Store', LucideIcons.store),
      _i('calendar', 'Calendar', LucideIcons.calendar),
      _i('clock', 'Clock', LucideIcons.clock, const ['time']),
      _i('printer', 'Printer', LucideIcons.printer),
      _i('lock', 'Lock', LucideIcons.lock, const ['security']),
      _i('unlock', 'Unlock', LucideIcons.lock_open),
      _i('triangle_alert', 'Warning', LucideIcons.triangle_alert,
          const ['alert']),
      _i('circle_alert', 'Alert', LucideIcons.circle_alert),
      _i('circle_check', 'Check', LucideIcons.circle_check, const ['ok']),
      _i('circle_x', 'Cancel', LucideIcons.circle_x),
      _i('settings', 'Settings', LucideIcons.settings, const ['gear']),
      _i('sliders_horizontal', 'Sliders', LucideIcons.sliders_horizontal),
      _i('chart_bar', 'Chart', LucideIcons.chart_bar, const ['analytics']),
      _i('chart_pie', 'Pie Chart', LucideIcons.chart_pie),
      _i('chart_line', 'Line Chart', LucideIcons.chart_line),
      _i('camera', 'Camera', LucideIcons.camera),
      _i('wifi', 'Wi‑Fi', LucideIcons.wifi, const ['network']),
      _i('bluetooth', 'Bluetooth', LucideIcons.bluetooth),
      _i('router', 'Router', LucideIcons.router),
      _i('shield', 'Shield', LucideIcons.shield, const ['security']),
      _i('shield_check', 'Shield Check', LucideIcons.shield_check),
      _i('house', 'Home', LucideIcons.house),
      _i('link', 'Link', LucideIcons.link, const ['url']),
      _i('search', 'Search', LucideIcons.search),
      _i('download', 'Download', LucideIcons.download),
      _i('upload', 'Upload', LucideIcons.upload),
      _i('refresh_cw', 'Refresh', LucideIcons.refresh_cw, const ['sync']),
      _i('code', 'Code', LucideIcons.code),
      _i('bug', 'Bug', LucideIcons.bug),
      _i('rocket', 'Rocket', LucideIcons.rocket, const ['launch']),
      _i('zap', 'Zap', LucideIcons.zap, const ['bolt', 'power']),
      _i('battery_charging', 'Battery', LucideIcons.battery_charging),
      _i('key', 'Key', LucideIcons.key),
      _i('map', 'Map', LucideIcons.map),
      _i('map_pin', 'Map Pin', LucideIcons.map_pin, const ['location']),
      _i('message_square', 'Message', LucideIcons.message_square,
          const ['chat']),
      _i('messages_square', 'Messages', LucideIcons.messages_square),
      _i('image', 'Image', LucideIcons.image),
      _i('video', 'Video', LucideIcons.video),
      _i('mic', 'Mic', LucideIcons.mic),
      _i('headphones', 'Headphones', LucideIcons.headphones),
      _i('shopping_cart', 'Cart', LucideIcons.shopping_cart),
      _i('credit_card', 'Card', LucideIcons.credit_card, const ['payment']),
      _i('package', 'Package', LucideIcons.package, const ['box']),
      _i('truck', 'Truck', LucideIcons.truck, const ['delivery']),
      _i('hard_drive', 'Hard Drive', LucideIcons.hard_drive, const ['disk']),
      _i('network', 'Network', LucideIcons.network),
      _i('cpu', 'CPU', LucideIcons.cpu, const ['processor']),
      _i('monitor', 'Monitor', LucideIcons.monitor, const ['display']),
      _i('briefcase', 'Briefcase', LucideIcons.briefcase, const ['work']),
      _i('layers', 'Layers', LucideIcons.layers),
      _i('layout_dashboard', 'Dashboard', LucideIcons.layout_dashboard),
      _i('terminal', 'Terminal', LucideIcons.terminal, const ['console']),
      _i('git_branch', 'Git Branch', LucideIcons.git_branch, const ['git']),
      _i('git_merge', 'Git Merge', LucideIcons.git_merge),
      _i('bot', 'Bot', LucideIcons.bot, const ['robot', 'ai']),
      _i('sparkles', 'Sparkles', LucideIcons.sparkles, const ['ai', 'magic']),
      _i('brain', 'Brain', LucideIcons.brain, const ['ai']),
      _i('workflow', 'Workflow', LucideIcons.workflow),
      _i('blocks', 'Blocks', LucideIcons.blocks, const ['modules']),
      _i('puzzle', 'Puzzle', LucideIcons.puzzle, const ['plugin']),
      _i('webhook', 'Webhook', LucideIcons.webhook),
      _i('table', 'Table', LucideIcons.table, const ['grid']),
      _i('list_tree', 'Tree', LucideIcons.list_tree, const ['hierarchy']),
      _i('fingerprint', 'Fingerprint', LucideIcons.fingerprint_pattern),
      _i('eye', 'Eye', LucideIcons.eye, const ['visibility']),
      _i('heart', 'Heart', LucideIcons.heart),
      _i('star', 'Star', LucideIcons.star),
      _i('flag', 'Flag', LucideIcons.flag),
      _i('bookmark', 'Bookmark', LucideIcons.bookmark),
      _i('pencil', 'Edit', LucideIcons.pencil, const ['edit']),
      _i('trash', 'Trash', LucideIcons.trash, const ['delete']),
      _i('plus', 'Plus', LucideIcons.plus, const ['add']),
      _i('minus', 'Minus', LucideIcons.minus),
      _i('bell', 'Bell', LucideIcons.bell, const ['notification']),
      _i('lightbulb', 'Idea', LucideIcons.lightbulb, const ['idea']),
      _i('flask_conical', 'Lab', LucideIcons.flask_conical, const ['science']),
      _i('graduation_cap', 'School', LucideIcons.graduation_cap,
          const ['education']),
      _i('plane', 'Plane', LucideIcons.plane, const ['flight']),
      _i('car', 'Car', LucideIcons.car),
      _i('train_front', 'Train', LucideIcons.train_front),
      _i('ship', 'Ship', LucideIcons.ship),
      _i('leaf', 'Leaf', LucideIcons.leaf, const ['green']),
      _i('droplets', 'Water', LucideIcons.droplets),
      _i('sun', 'Sun', LucideIcons.sun),
      _i('moon', 'Moon', LucideIcons.moon),
    ],
  ),
  ThirdPartyIconProvider(
    id: 'phosphor',
    name: 'Phosphor',
    license: 'MIT',
    icons: <ThirdPartyIcon>[
      _i('user', 'User', PhosphorIconsRegular.user, const ['person']),
      _i('users', 'Users', PhosphorIconsRegular.users, const ['group']),
      _i('identification_badge', 'Badge',
          PhosphorIconsRegular.identificationBadge),
      _i('hard_drives', 'Server', PhosphorIconsRegular.hardDrives,
          const ['server', 'host']),
      _i('database', 'Database', PhosphorIconsRegular.database, const ['db']),
      _i('cloud', 'Cloud', PhosphorIconsRegular.cloud),
      _i('cloud_check', 'Cloud Check', PhosphorIconsRegular.cloudCheck),
      _i('laptop', 'Laptop', PhosphorIconsRegular.laptop, const ['computer']),
      _i('phone', 'Phone', PhosphorIconsRegular.deviceMobile, const ['mobile']),
      _i('tablet', 'Tablet', PhosphorIconsRegular.deviceTablet),
      _i('globe', 'Globe', PhosphorIconsRegular.globe, const ['world']),
      _i('file', 'File', PhosphorIconsRegular.file),
      _i('file_text', 'Document', PhosphorIconsRegular.fileText, const ['doc']),
      _i('folder', 'Folder', PhosphorIconsRegular.folder),
      _i('folder_open', 'Folder Open', PhosphorIconsRegular.folderOpen),
      _i('mail', 'Mail', PhosphorIconsRegular.envelopeSimple, const ['email']),
      _i('tray', 'Inbox', PhosphorIconsRegular.tray),
      _i('building', 'Building', PhosphorIconsRegular.buildings,
          const ['office']),
      _i('factory', 'Factory', PhosphorIconsRegular.factory),
      _i('storefront', 'Store', PhosphorIconsRegular.storefront),
      _i('calendar', 'Calendar', PhosphorIconsRegular.calendarBlank),
      _i('clock', 'Clock', PhosphorIconsRegular.clock),
      _i('printer', 'Printer', PhosphorIconsRegular.printer),
      _i('lock', 'Lock', PhosphorIconsRegular.lock, const ['security']),
      _i('lock_open', 'Unlock', PhosphorIconsRegular.lockOpen),
      _i('warning', 'Warning', PhosphorIconsRegular.warning, const ['alert']),
      _i('check', 'Check', PhosphorIconsRegular.checkCircle, const ['ok']),
      _i('x_circle', 'Cancel', PhosphorIconsRegular.xCircle),
      _i('settings', 'Settings', PhosphorIconsRegular.gear, const ['gear']),
      _i('sliders', 'Sliders', PhosphorIconsRegular.sliders),
      _i('chart', 'Chart', PhosphorIconsRegular.chartBar, const ['analytics']),
      _i('chart_pie', 'Pie Chart', PhosphorIconsRegular.chartPie),
      _i('chart_line', 'Line Chart', PhosphorIconsRegular.chartLine),
      _i('camera', 'Camera', PhosphorIconsRegular.camera),
      _i('wifi', 'Wi‑Fi', PhosphorIconsRegular.wifiHigh, const ['network']),
      _i('bluetooth', 'Bluetooth', PhosphorIconsRegular.bluetooth),
      _i('broadcast', 'Broadcast', PhosphorIconsRegular.broadcast),
      _i('shield', 'Shield', PhosphorIconsRegular.shield, const ['security']),
      _i('shield_check', 'Shield Check', PhosphorIconsRegular.shieldCheck),
      _i('house', 'Home', PhosphorIconsRegular.house),
      _i('link', 'Link', PhosphorIconsRegular.link, const ['url']),
      _i('search', 'Search', PhosphorIconsRegular.magnifyingGlass),
      _i('download', 'Download', PhosphorIconsRegular.downloadSimple),
      _i('upload', 'Upload', PhosphorIconsRegular.uploadSimple),
      _i('arrows_clockwise', 'Sync', PhosphorIconsRegular.arrowsClockwise),
      _i('code', 'Code', PhosphorIconsRegular.code),
      _i('bug', 'Bug', PhosphorIconsRegular.bug),
      _i('rocket', 'Rocket', PhosphorIconsRegular.rocket, const ['launch']),
      _i('lightning', 'Bolt', PhosphorIconsRegular.lightning, const ['zap']),
      _i('battery_charging', 'Battery',
          PhosphorIconsRegular.batteryChargingVertical),
      _i('key', 'Key', PhosphorIconsRegular.key),
      _i('map_trifold', 'Map', PhosphorIconsRegular.mapTrifold),
      _i('map_pin', 'Map Pin', PhosphorIconsRegular.mapPin, const ['location']),
      _i('chat', 'Chat', PhosphorIconsRegular.chatCircle, const ['message']),
      _i('chats', 'Chats', PhosphorIconsRegular.chatsCircle),
      _i('image', 'Image', PhosphorIconsRegular.image),
      _i('video', 'Video', PhosphorIconsRegular.videoCamera),
      _i('microphone', 'Mic', PhosphorIconsRegular.microphone),
      _i('headphones', 'Headphones', PhosphorIconsRegular.headphones),
      _i('shopping_cart', 'Cart', PhosphorIconsRegular.shoppingCart),
      _i('credit_card', 'Card', PhosphorIconsRegular.creditCard),
      _i('package', 'Package', PhosphorIconsRegular.package),
      _i('truck', 'Truck', PhosphorIconsRegular.truck),
      _i('hard_drive', 'Hard Drive', PhosphorIconsRegular.hardDrive),
      _i('desktop', 'Desktop', PhosphorIconsRegular.desktopTower,
          const ['computer', 'pc']),
      _i('cpu', 'CPU', PhosphorIconsRegular.cpu),
      _i('monitor', 'Monitor', PhosphorIconsRegular.monitor),
      _i('briefcase', 'Briefcase', PhosphorIconsRegular.briefcase),
      _i('stack', 'Layers', PhosphorIconsRegular.stack),
      _i('squares_four', 'Dashboard', PhosphorIconsRegular.squaresFour),
      _i('terminal', 'Terminal', PhosphorIconsRegular.terminalWindow),
      _i('git_branch', 'Git Branch', PhosphorIconsRegular.gitBranch),
      _i('git_merge', 'Git Merge', PhosphorIconsRegular.gitMerge),
      _i('robot', 'Bot', PhosphorIconsRegular.robot, const ['ai']),
      _i('sparkle', 'Sparkles', PhosphorIconsRegular.sparkle, const ['ai']),
      _i('brain', 'Brain', PhosphorIconsRegular.brain, const ['ai']),
      _i('flow_arrow', 'Workflow', PhosphorIconsRegular.flowArrow),
      _i('puzzle', 'Puzzle', PhosphorIconsRegular.puzzlePiece),
      _i('plugs', 'Plugs', PhosphorIconsRegular.plugsConnected,
          const ['api', 'integration']),
      _i('table', 'Table', PhosphorIconsRegular.table),
      _i('tree_structure', 'Tree', PhosphorIconsRegular.treeStructure),
      _i('fingerprint', 'Fingerprint', PhosphorIconsRegular.fingerprint),
      _i('eye', 'Eye', PhosphorIconsRegular.eye),
      _i('info', 'Info', PhosphorIconsRegular.info),
      _i('question', 'Help', PhosphorIconsRegular.question, const ['help']),
      _i('heart', 'Heart', PhosphorIconsRegular.heart),
      _i('star', 'Star', PhosphorIconsRegular.star),
      _i('flag', 'Flag', PhosphorIconsRegular.flag),
      _i('bookmark', 'Bookmark', PhosphorIconsRegular.bookmarkSimple),
      _i('pencil', 'Edit', PhosphorIconsRegular.pencilSimple, const ['edit']),
      _i('trash', 'Trash', PhosphorIconsRegular.trash, const ['delete']),
      _i('plus', 'Plus', PhosphorIconsRegular.plus, const ['add']),
      _i('minus', 'Minus', PhosphorIconsRegular.minus),
      _i('bell', 'Bell', PhosphorIconsRegular.bell, const ['notification']),
      _i('lightbulb', 'Idea', PhosphorIconsRegular.lightbulb),
      _i('flask', 'Lab', PhosphorIconsRegular.flask),
      _i('graduation_cap', 'School', PhosphorIconsRegular.graduationCap),
      _i('airplane', 'Plane', PhosphorIconsRegular.airplane),
      _i('car', 'Car', PhosphorIconsRegular.car),
      _i('train', 'Train', PhosphorIconsRegular.train),
      _i('boat', 'Ship', PhosphorIconsRegular.boat),
      _i('leaf', 'Leaf', PhosphorIconsRegular.leaf),
      _i('drop', 'Water', PhosphorIconsRegular.drop),
      _i('sun', 'Sun', PhosphorIconsRegular.sun),
      _i('moon', 'Moon', PhosphorIconsRegular.moon),
      _i('tag', 'Tag', PhosphorIconsRegular.tag),
      _i('music', 'Music', PhosphorIconsRegular.musicNote),
    ],
  ),
  ThirdPartyIconProvider(
    id: 'cupertino',
    name: 'Cupertino',
    license: 'MIT (Flutter)',
    icons: <ThirdPartyIcon>[
      _i('person', 'Person', CupertinoIcons.person, const ['user']),
      _i('person_2', 'People', CupertinoIcons.person_2, const ['group']),
      _i('cloud', 'Cloud', CupertinoIcons.cloud),
      _i('device_laptop', 'Laptop', CupertinoIcons.device_laptop,
          const ['computer']),
      _i('device_phone', 'Phone', CupertinoIcons.device_phone_portrait,
          const ['mobile']),
      _i('desktopcomputer', 'Desktop', CupertinoIcons.desktopcomputer),
      _i('globe', 'Globe', CupertinoIcons.globe, const ['world']),
      _i('doc', 'Document', CupertinoIcons.doc, const ['file']),
      _i('folder', 'Folder', CupertinoIcons.folder),
      _i('mail', 'Mail', CupertinoIcons.mail, const ['email']),
      _i('building', 'Building', CupertinoIcons.building_2_fill,
          const ['office']),
      _i('calendar', 'Calendar', CupertinoIcons.calendar),
      _i('clock', 'Clock', CupertinoIcons.clock),
      _i('alarm', 'Alarm', CupertinoIcons.alarm),
      _i('printer', 'Printer', CupertinoIcons.printer),
      _i('lock', 'Lock', CupertinoIcons.lock, const ['security']),
      _i('warning', 'Warning', CupertinoIcons.exclamationmark_triangle,
          const ['alert']),
      _i('check', 'Check', CupertinoIcons.checkmark_circle, const ['ok']),
      _i('settings', 'Settings', CupertinoIcons.gear, const ['gear']),
      _i('chart', 'Chart', CupertinoIcons.chart_bar, const ['analytics']),
      _i('camera', 'Camera', CupertinoIcons.camera),
      _i('wifi', 'Wi‑Fi', CupertinoIcons.wifi, const ['network']),
      _i('bluetooth', 'Bluetooth', CupertinoIcons.bluetooth),
      _i('antenna', 'Antenna', CupertinoIcons.antenna_radiowaves_left_right,
          const ['signal']),
      _i('shield', 'Shield', CupertinoIcons.shield, const ['security']),
      _i('house', 'Home', CupertinoIcons.house),
      _i('link', 'Link', CupertinoIcons.link, const ['url']),
      _i('search', 'Search', CupertinoIcons.search),
      _i('download', 'Download', CupertinoIcons.cloud_download),
      _i('upload', 'Upload', CupertinoIcons.cloud_upload),
      _i('bolt', 'Bolt', CupertinoIcons.bolt, const ['zap', 'power']),
      _i('battery', 'Battery', CupertinoIcons.battery_100),
      _i('rocket', 'Rocket', CupertinoIcons.rocket_fill, const ['launch']),
      _i('map', 'Map', CupertinoIcons.map),
      _i('location', 'Location', CupertinoIcons.location, const ['pin']),
      _i('chat', 'Chat', CupertinoIcons.chat_bubble, const ['message']),
      _i('photo', 'Photo', CupertinoIcons.photo, const ['image']),
      _i('video', 'Video', CupertinoIcons.videocam),
      _i('headphones', 'Headphones', CupertinoIcons.headphones),
      _i('cart', 'Cart', CupertinoIcons.cart, const ['shop']),
      _i('creditcard', 'Card', CupertinoIcons.creditcard, const ['payment']),
      _i('gift', 'Gift', CupertinoIcons.gift),
      _i('flag', 'Flag', CupertinoIcons.flag),
      _i('bell', 'Bell', CupertinoIcons.bell, const ['notification']),
      _i('heart', 'Heart', CupertinoIcons.heart),
      _i('star', 'Star', CupertinoIcons.star),
      _i('tag', 'Tag', CupertinoIcons.tag),
      _i('bookmark', 'Bookmark', CupertinoIcons.bookmark),
      _i('trash', 'Trash', CupertinoIcons.trash, const ['delete']),
      _i('plus', 'Plus', CupertinoIcons.plus_circle, const ['add']),
      _i('minus', 'Minus', CupertinoIcons.minus_circle),
    ],
  ),
];

/// Flat lookup map: `providerId/iconId` → entry.
final Map<String, ThirdPartyIcon> kThirdPartyIconByKey = <String, ThirdPartyIcon>{
  for (final p in kThirdPartyIconProviders)
    for (final icon in p.icons) '${p.id}/${icon.id}': icon,
};

/// Lookup provider by [id], or null.
ThirdPartyIconProvider? findThirdPartyIconProvider(String id) {
  for (final p in kThirdPartyIconProviders) {
    if (p.id == id) return p;
  }
  return null;
}

/// Lookup icon by provider + id, or null.
ThirdPartyIcon? findThirdPartyIcon(String providerId, String iconId) =>
    kThirdPartyIconByKey['$providerId/$iconId'];

/// Provider id for a catalog [icon] instance, or null if not from the catalog.
String? findProviderIdForIcon(ThirdPartyIcon icon) {
  for (final p in kThirdPartyIconProviders) {
    if (p.icons.contains(icon)) return p.id;
  }
  return null;
}

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
  Color color = kThirdPartyIconDefaultColor,
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

// ---------------------------------------------------------------------------
// Persistence / rebuild helpers (Charts-style userCells)
// ---------------------------------------------------------------------------

/// Metadata keys written onto icon picture shapes.
abstract final class IconOps {
  IconOps._();

  static const String userIcon = 'visioeditor.Icon';
  static const String userProvider = 'visioeditor.IconProvider';
  static const String userId = 'visioeditor.IconId';
  static const String userColor = 'visioeditor.IconColor';

  static const int defaultColorArgb = 0xFF243040;

  static bool isIcon(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userIcon && (c.value == '1' || c.value == 'true')) {
        return true;
      }
    }
    return false;
  }

  static String? providerId(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userProvider) return c.value;
    }
    return null;
  }

  static String? iconId(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userId) return c.value;
    }
    return null;
  }

  static int colorArgb(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userColor) {
        final raw = (c.value ?? '').trim();
        var hex = raw.startsWith('#') ? raw.substring(1) : raw;
        if (hex.length == 6) hex = 'FF$hex';
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return v;
      }
    }
    return defaultColorArgb;
  }

  static String formatColor(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  static List<VsdxUserCell> meta({
    required String providerId,
    required String iconId,
    required int colorArgb,
  }) =>
      <VsdxUserCell>[
        const VsdxUserCell(name: userIcon, value: '1'),
        VsdxUserCell(name: userProvider, value: providerId),
        VsdxUserCell(name: userId, value: iconId),
        VsdxUserCell(name: userColor, value: formatColor(colorArgb)),
      ];

  static ThirdPartyIcon? resolve(VsdxShape s) {
    final p = providerId(s);
    final id = iconId(s);
    if (p == null || id == null) return null;
    return findThirdPartyIcon(p, id);
  }
}
