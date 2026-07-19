// Generates small clipart PNGs for the image-materials palette.
//
// Flat, diagram-friendly icons at 64×64 so they stay tiny in the app bundle
// and insert at a sensible default size (~0.67" at 96 dpi).
//
// Run from the project root:
//   dart run tool/gen_image_materials.dart
//
// Output: assets/materials/*.png
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 64;
const String kOutDir = 'assets/materials';

/// Soft diagram palette (avoid neon / purple defaults).
const int kBlue = 0xFF2F6FED;
const int kBlueDark = 0xFF1E4BB8;
const int kBlueLight = 0xFF6FA0F5;
const int kTeal = 0xFF0F8A7A;
const int kTealDark = 0xFF0A6B5E;
const int kTealLight = 0xFF3BB8A6;
const int kOrange = 0xFFE07A2F;
const int kOrangeLight = 0xFFF0A35A;
const int kRed = 0xFFD64545;
const int kGreen = 0xFF2F9E5C;
const int kGray = 0xFF5A6570;
const int kGrayLight = 0xFFE8ECF1;
const int kWhite = 0xFFFFFFFF;
const int kInk = 0xFF243040;

typedef _Drawer = void Function(img.Image dst);

void main() {
  Directory(kOutDir).createSync(recursive: true);
  final drawers = <String, _Drawer>{
    // People
    'person': _drawPerson,
    'users': _drawUsers,
    'manager': _drawManager,
    'handshake': _drawHandshake,
    'support': _drawSupport,
    'id_badge': _drawIdBadge,
    'team': _drawTeam,
    'developer': _drawDeveloper,
    'customer': _drawCustomer,
    'admin': _drawAdmin,
    'nurse': _drawNurse,
    'courier': _drawCourier,
    'teacher': _drawTeacher,
    'athlete': _drawAthlete,
    'doctor': _drawDoctor,
    'chef': _drawChef,
    'farmer': _drawFarmer,
    'soldier': _drawSoldier,
    // IT
    'server': _drawServer,
    'database': _drawDatabase,
    'cloud': _drawCloud,
    'laptop': _drawLaptop,
    'phone': _drawPhone,
    'globe': _drawGlobe,
    'monitor': _drawMonitor,
    'hard_drive': _drawHardDrive,
    'code': _drawCode,
    'tablet': _drawTablet,
    'cpu': _drawCpu,
    'battery': _drawBattery,
    'usb': _drawUsb,
    'robot': _drawRobot,
    'cloud_upload': _drawCloudUpload,
    'cloud_download': _drawCloudDownload,
    'terminal': _drawTerminal,
    'keyboard': _drawKeyboard,
    'network_switch': _drawNetworkSwitch,
    'container': _drawContainer,
    'mouse': _drawMouse,
    'webcam': _drawWebcam,
    'sd_card': _drawSdCard,
    'stack': _drawStack,
    'branch': _drawBranch,
    'layers': _drawLayers,
    'browser': _drawBrowser,
    'cache': _drawCache,
    'queue': _drawQueue,
    'floppy': _drawFloppy,
    'cd': _drawCd,
    'ai': _drawAi,
    'disk': _drawDisk,
    // Office
    'document': _drawDocument,
    'folder': _drawFolder,
    'email': _drawEmail,
    'building': _drawBuilding,
    'calendar': _drawCalendar,
    'printer': _drawPrinter,
    'clipboard': _drawClipboard,
    'briefcase': _drawBriefcase,
    'sticky_note': _drawStickyNote,
    'presentation': _drawPresentation,
    'book': _drawBook,
    'inbox': _drawInbox,
    'megaphone': _drawMegaphone,
    'attachment': _drawAttachment,
    'tag': _drawTag,
    'filter': _drawFilter,
    'calculator': _drawCalculator,
    'archive': _drawArchive,
    'pen': _drawPen,
    'scissors': _drawScissors,
    'stamp': _drawStamp,
    'notepad': _drawNotepad,
    'binder': _drawBinder,
    'folder_open': _drawFolderOpen,
    'desk': _drawDesk,
    'whiteboard': _drawWhiteboard,
    'fax': _drawFax,
    'stapler': _drawStapler,
    'highlighter': _drawHighlighter,
    // Status
    'lock': _drawLock,
    'warning': _drawWarning,
    'check': _drawCheck,
    'settings': _drawSettings,
    'chart': _drawChart,
    'camera': _drawCamera,
    'info': _drawInfo,
    'cross': _drawCross,
    'star': _drawStar,
    'bell': _drawBell,
    'heart': _drawHeart,
    'key': _drawKey,
    'refresh': _drawRefresh,
    'pause': _drawPause,
    'play': _drawPlay,
    'stop': _drawStop,
    'download': _drawDownload,
    'upload': _drawUpload,
    'question': _drawQuestion,
    'power': _drawPower,
    'thumbs_up': _drawThumbsUp,
    'signal': _drawSignal,
    'bookmark': _drawBookmark,
    'share': _drawShare,
    'mute': _drawMute,
    'hourglass': _drawHourglass,
    'pin': _drawPin,
    'infinity': _drawInfinity,
    'trash': _drawTrash,
    'edit': _drawEdit,
    'copy': _drawCopy,
    'link_off': _drawLinkOff,
    'visibility': _drawVisibility,
    'clipboard_check': _drawClipboardCheck,
    'sparkles': _drawSparkles,
    // Network
    'wifi': _drawWifi,
    'router': _drawRouter,
    'firewall': _drawFirewall,
    'api': _drawApi,
    'link': _drawLink,
    'bluetooth': _drawBluetooth,
    'satellite': _drawSatellite,
    'ethernet': _drawEthernet,
    'vpn': _drawVpn,
    'dns': _drawDns,
    'gateway': _drawGateway,
    'hotspot': _drawHotspot,
    'load_balancer': _drawLoadBalancer,
    'proxy': _drawProxy,
    'mesh': _drawMesh,
    'cdn': _drawCdn,
    'webhook': _drawWebhook,
    'lan': _drawLan,
    'bridge': _drawBridge,
    'tunnel': _drawTunnel,
    // Business / process
    'lightbulb': _drawLightbulb,
    'target': _drawTarget,
    'flag': _drawFlag,
    'rocket': _drawRocket,
    'clock': _drawClock,
    'package': _drawPackage,
    'map_pin': _drawMapPin,
    'wallet': _drawWallet,
    'credit_card': _drawCreditCard,
    'shopping_cart': _drawShoppingCart,
    'trophy': _drawTrophy,
    'chart_pie': _drawChartPie,
    'barcode': _drawBarcode,
    'qr_code': _drawQrCode,
    'funnel': _drawFunnel,
    'coin': _drawCoin,
    'contract': _drawContract,
    'chart_line': _drawChartLine,
    'invoice': _drawInvoice,
    'timeline': _drawTimeline,
    'kanban': _drawKanban,
    'percent': _drawPercent,
    'gift': _drawGift,
    'balance': _drawBalance,
    'storefront': _drawStorefront,
    'auction': _drawAuction,
    'shopping_bag': _drawShoppingBag,
    'receipt': _drawReceipt,
    'deal': _drawDeal,
    'insurance': _drawInsurance,
    // Security
    'shield': _drawShield,
    'fingerprint': _drawFingerprint,
    'eye': _drawEye,
    'unlock': _drawUnlock,
    'vault': _drawVault,
    'password': _drawPassword,
    'bug': _drawBug,
    'certificate': _drawCertificate,
    'cctv': _drawCctv,
    'anonymize': _drawAnonymize,
    'alarm': _drawAlarm,
    'scan': _drawScan,
    'fire_extinguisher': _drawFireExtinguisher,
    'police': _drawPolice,
    'helmet': _drawHelmet,
    'siren': _drawSiren,
    // Transport
    'truck': _drawTruck,
    'car': _drawCar,
    'plane': _drawPlane,
    'ship': _drawShip,
    'train': _drawTrain,
    'bike': _drawBike,
    'bus': _drawBus,
    'parking': _drawParking,
    'ambulance': _drawAmbulance,
    'scooter': _drawScooter,
    'metro': _drawMetro,
    'helicopter': _drawHelicopter,
    'taxi': _drawTaxi,
    'ferry': _drawFerry,
    'submarine': _drawSubmarine,
    'forklift': _drawForklift,
    // Media
    'music': _drawMusic,
    'headphones': _drawHeadphones,
    'mic': _drawMic,
    'film': _drawFilm,
    'speaker': _drawSpeaker,
    'photo': _drawPhoto,
    'video': _drawVideo,
    'tv': _drawTv,
    'radio': _drawRadio,
    'podcast': _drawPodcast,
    'clapper': _drawClapper,
    'gamepad': _drawGamepad,
    'ebook': _drawEbook,
    'vinyl': _drawVinyl,
    'projector': _drawProjector,
    'ticket': _drawTicket,
    'newspaper': _drawNewspaper,
    // Tools
    'wrench': _drawWrench,
    'hammer': _drawHammer,
    'magnifier': _drawMagnifier,
    'compass': _drawCompass,
    'screwdriver': _drawScrewdriver,
    'ruler': _drawRuler,
    'bolt': _drawBolt,
    'paintbrush': _drawPaintbrush,
    'flashlight': _drawFlashlight,
    'ladder': _drawLadder,
    'saw': _drawSaw,
    'pliers': _drawPliers,
    'tape': _drawTape,
    'drill': _drawDrill,
    'level': _drawLevel,
    'axe': _drawAxe,
    'shovel': _drawShovel,
    // Places
    'home': _drawHome,
    'factory': _drawFactory,
    'hospital': _drawHospital,
    'school': _drawSchool,
    'warehouse': _drawWarehouse,
    'store': _drawStore,
    'lab': _drawLab,
    'airport': _drawAirport,
    'park': _drawPark,
    'bank': _drawBank,
    'gym': _drawGym,
    'hotel': _drawHotel,
    'museum': _drawMuseum,
    'church': _drawChurch,
    'stadium': _drawStadium,
    'beach': _drawBeach,
    'castle': _drawCastle,
    // Communication
    'chat': _drawChat,
    'call': _drawCall,
    'video_call': _drawVideoCall,
    'comment': _drawComment,
    'broadcast': _drawBroadcast,
    'mail_open': _drawMailOpen,
    'sms': _drawSms,
    'at_sign': _drawAtSign,
    'newsletter': _drawNewsletter,
    'voicemail': _drawVoicemail,
    'pager': _drawPager,
    'walkie': _drawWalkie,
    // Energy / environment
    'plug': _drawPlug,
    'lightning': _drawLightning,
    'sun': _drawSun,
    'leaf': _drawLeaf,
    'recycle': _drawRecycle,
    'water': _drawWater,
    'thermometer': _drawThermometer,
    'gauge': _drawGauge,
    'wind': _drawWind,
    'flame': _drawFlame,
    'battery_charging': _drawBatteryCharging,
    'hydro': _drawHydro,
    'atom': _drawAtom,
    'solar_panel': _drawSolarPanel,
    'oil': _drawOil,
    'nuclear': _drawNuclear,
    // Devices / IoT
    'sensor': _drawSensor,
    'antenna': _drawAntenna,
    'smartwatch': _drawSmartwatch,
    'drone': _drawDrone,
    'nfc': _drawNfc,
    'pcb': _drawPcb,
    'thermostat': _drawThermostat,
    'doorbell': _drawDoorbell,
    'camera_ip': _drawCameraIp,
    'smart_lock': _drawSmartLock,
    'speaker_smart': _drawSpeakerSmart,
    'fridge': _drawFridge,
    // Data
    'table': _drawTable,
    'spreadsheet': _drawSpreadsheet,
    'cube': _drawCube,
    'pipeline': _drawPipeline,
    'json': _drawJson,
    'binary': _drawBinary,
    'dataset': _drawDataset,
    'schema': _drawSchema,
    'log': _drawLog,
    'metric': _drawMetric,
    'report': _drawReport,
    'etl': _drawEtl,
    'index': _drawIndex,
    'snapshot': _drawSnapshot,
    'mirror': _drawMirror,
    // Health
    'pill': _drawPill,
    'syringe': _drawSyringe,
    'dna': _drawDna,
    'stethoscope': _drawStethoscope,
    'bandage': _drawBandage,
    'wheelchair': _drawWheelchair,
    'vaccine': _drawVaccine,
    'microscope': _drawMicroscope,
    // Nature
    'tree': _drawTree,
    'mountain': _drawMountain,
    'flower': _drawFlower,
    'fish': _drawFish,
    'bird': _drawBird,
    'rain': _drawRain,
  };

  for (final entry in drawers.entries) {
    final image = img.Image(width: kSize, height: kSize, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    entry.value(image);
    final path = '$kOutDir/${entry.key}.png';
    File(path).writeAsBytesSync(img.encodePng(image, level: 9));
    final kb = (File(path).lengthSync() / 1024).toStringAsFixed(1);
    stdout.writeln('wrote $path ($kb KB)');
  }
}

img.ColorRgba8 _c(int argb) => img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    );

void _circle(img.Image dst, int cx, int cy, int r, int color) {
  img.fillCircle(dst, x: cx, y: cy, radius: r, color: _c(color));
}

/// Axis-aligned fill. Avoid rounded-rect radius: it paints nothing on
/// transparent backgrounds in package:image 4.x.
void _rect(img.Image dst, int x0, int y0, int x1, int y1, int color) {
  img.fillRect(
    dst,
    x1: x0,
    y1: y0,
    x2: x1,
    y2: y1,
    color: _c(color),
    alphaBlend: false,
  );
}

void _drawPerson(img.Image dst) {
  _circle(dst, 32, 18, 10, kBlue);
  // Torso as circle + rect (avoids large rounded-rect radius bugs).
  _circle(dst, 32, 42, 16, kBlue);
  _rect(dst, 16, 42, 48, 58, kBlue);
  _rect(dst, 16, 52, 48, 58, kBlueDark);
}

void _drawUsers(img.Image dst) {
  _circle(dst, 22, 18, 8, kGray);
  _circle(dst, 22, 40, 12, kGray);
  _rect(dst, 10, 40, 34, 52, kGray);
  _circle(dst, 42, 16, 9, kBlue);
  _circle(dst, 42, 40, 14, kBlue);
  _rect(dst, 28, 40, 56, 54, kBlue);
}

void _drawServer(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kGray);
  for (final y in [16, 28, 40]) {
    _rect(dst, 18, y, 46, y + 8, kGrayLight);
    _circle(dst, 42, y + 4, 2, kGreen);
  }
}

void _drawDatabase(img.Image dst) {
  _rect(dst, 16, 20, 48, 46, kTeal);
  _circle(dst, 32, 20, 16, kTealLight);
  _circle(dst, 32, 46, 16, kTealDark);
  _rect(dst, 16, 20, 48, 46, kTeal);
  _circle(dst, 32, 20, 14, kTealLight);
}

void _drawCloud(img.Image dst) {
  _circle(dst, 22, 34, 12, kBlue);
  _circle(dst, 36, 28, 15, kBlue);
  _circle(dst, 48, 36, 11, kBlue);
  _rect(dst, 12, 34, 56, 48, kBlue);
}

void _drawDocument(img.Image dst) {
  _rect(dst, 16, 8, 48, 56, kWhite);
  img.drawRect(dst, x1: 16, y1: 8, x2: 48, y2: 56, color: _c(kBlueDark));
  // Folded corner.
  for (var i = 0; i < 12; i++) {
    for (var j = 0; j <= i; j++) {
      dst.setPixelRgba(48 - i, 8 + j, 0xE8, 0xEC, 0xF1, 0xFF);
    }
  }
  for (final y in [22, 30, 38, 46]) {
    _rect(dst, 22, y, 40, y + 3, kGrayLight);
  }
}

void _drawFolder(img.Image dst) {
  _rect(dst, 10, 18, 32, 28, kOrangeLight);
  _rect(dst, 10, 24, 54, 52, kOrange);
  _rect(dst, 10, 28, 54, 52, kOrangeLight);
}

void _drawLaptop(img.Image dst) {
  _rect(dst, 14, 14, 50, 40, kInk);
  _rect(dst, 17, 17, 47, 36, kBlue);
  _rect(dst, 10, 40, 54, 48, kGray);
  _rect(dst, 26, 42, 38, 45, kGrayLight);
}

void _drawPhone(img.Image dst) {
  _rect(dst, 22, 8, 42, 56, kInk);
  _rect(dst, 25, 14, 39, 46, kBlue);
  _circle(dst, 32, 51, 2, kGrayLight);
}

void _drawEmail(img.Image dst) {
  _rect(dst, 8, 18, 56, 48, kBlue);
  for (var t = 0; t <= 24; t++) {
    final y = 18 + (t * 14 / 24).round();
    dst.setPixelRgba(8 + t, y, 0xFF, 0xFF, 0xFF, 0xFF);
    dst.setPixelRgba(56 - t, y, 0xFF, 0xFF, 0xFF, 0xFF);
    if (y + 1 < kSize) {
      dst.setPixelRgba(8 + t, y + 1, 0xFF, 0xFF, 0xFF, 0xFF);
      dst.setPixelRgba(56 - t, y + 1, 0xFF, 0xFF, 0xFF, 0xFF);
    }
  }
}

void _drawBuilding(img.Image dst) {
  _rect(dst, 14, 12, 50, 54, kGray);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      _rect(
        dst,
        20 + col * 10,
        18 + row * 10,
        26 + col * 10,
        24 + row * 10,
        kGrayLight,
      );
    }
  }
  _rect(dst, 28, 42, 36, 54, kInk);
}

void _drawGlobe(img.Image dst) {
  _circle(dst, 32, 32, 20, kBlue);
  _circle(dst, 32, 32, 16, kBlueLight);
  img.drawCircle(dst, x: 32, y: 32, radius: 20, color: _c(kBlueDark));
  img.drawCircle(dst, x: 32, y: 32, radius: 12, color: _c(kWhite));
  for (var x = 12; x <= 52; x++) {
    dst.setPixelRgba(x, 32, 0xFF, 0xFF, 0xFF, 0xCC);
  }
  for (var y = 12; y <= 52; y++) {
    dst.setPixelRgba(32, y, 0xFF, 0xFF, 0xFF, 0xCC);
  }
}

void _drawLock(img.Image dst) {
  for (var a = 0; a <= 180; a++) {
    final rad = a * math.pi / 180;
    final x = 32 + (11 * math.cos(rad)).round();
    final y = 24 - (11 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  _rect(dst, 16, 26, 48, 54, kOrange);
  _circle(dst, 32, 38, 4, kWhite);
  _rect(dst, 30, 38, 34, 48, kWhite);
}

void _drawWarning(img.Image dst) {
  for (var y = 10; y <= 52; y++) {
    final t = (y - 10) / 42;
    final half = (t * 22).round();
    for (var x = 32 - half; x <= 32 + half; x++) {
      dst.setPixelRgba(x, y, 0xE0, 0x7A, 0x2F, 0xFF);
    }
  }
  _rect(dst, 30, 22, 34, 38, kWhite);
  _circle(dst, 32, 44, 2, kWhite);
}

void _drawCheck(img.Image dst) {
  _circle(dst, 32, 32, 22, kGreen);
  for (var i = 0; i < 12; i++) {
    final x = 18 + i;
    final y = 34 + (i * 0.6).round();
    _circle(dst, x, y, 2, kWhite);
  }
  for (var i = 0; i < 18; i++) {
    final x = 28 + i;
    final y = 42 - i;
    _circle(dst, x, y, 2, kWhite);
  }
}

void _drawSettings(img.Image dst) {
  _circle(dst, 32, 32, 14, kGray);
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final x = 32 + (20 * math.cos(a)).round();
    final y = 32 + (20 * math.sin(a)).round();
    _rect(dst, x - 3, y - 3, x + 3, y + 3, kGray);
  }
  _circle(dst, 32, 32, 7, kGrayLight);
  _circle(dst, 32, 32, 4, kInk);
}

void _drawCalendar(img.Image dst) {
  _rect(dst, 12, 14, 52, 52, kWhite);
  _rect(dst, 12, 14, 52, 26, kRed);
  _rect(dst, 12, 22, 52, 26, kRed);
  for (final x in [22, 32, 42]) {
    _rect(dst, x - 1, 10, x + 1, 18, kGray);
  }
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      _rect(
        dst,
        18 + col * 11,
        30 + row * 7,
        24 + col * 11,
        34 + row * 7,
        kGrayLight,
      );
    }
  }
}

void _drawChart(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kGrayLight);
  _rect(dst, 16, 36, 24, 48, kBlue);
  _rect(dst, 28, 24, 36, 48, kTeal);
  _rect(dst, 40, 16, 48, 48, kOrange);
}

void _drawPrinter(img.Image dst) {
  _rect(dst, 20, 8, 44, 20, kGrayLight);
  _rect(dst, 12, 20, 52, 42, kGray);
  _rect(dst, 18, 38, 46, 54, kWhite);
  _circle(dst, 44, 28, 2, kGreen);
  for (final y in [44, 48]) {
    _rect(dst, 22, y, 42, y + 2, kGrayLight);
  }
}

void _drawCamera(img.Image dst) {
  _rect(dst, 10, 22, 54, 50, kInk);
  _rect(dst, 24, 14, 40, 24, kInk);
  _circle(dst, 32, 36, 10, kBlue);
  _circle(dst, 32, 36, 5, kBlueDark);
  _circle(dst, 46, 28, 2, kRed);
}

void _drawManager(img.Image dst) {
  _circle(dst, 32, 16, 9, kInk);
  _circle(dst, 32, 40, 15, kBlue);
  _rect(dst, 17, 40, 47, 56, kBlue);
  // Tie.
  for (var y = 28; y <= 48; y++) {
    final half = y < 36 ? 2 : 3;
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrange);
  }
}

void _drawHandshake(img.Image dst) {
  _rect(dst, 8, 28, 30, 42, kBlue);
  _rect(dst, 34, 28, 56, 42, kTeal);
  _rect(dst, 22, 24, 42, 46, kGrayLight);
  _rect(dst, 18, 30, 46, 40, kOrange);
}

void _drawMonitor(img.Image dst) {
  _rect(dst, 10, 10, 54, 42, kInk);
  _rect(dst, 14, 14, 50, 36, kBlue);
  _rect(dst, 28, 42, 36, 50, kGray);
  _rect(dst, 20, 50, 44, 54, kGray);
}

void _drawHardDrive(img.Image dst) {
  _rect(dst, 10, 18, 54, 48, kGray);
  _rect(dst, 14, 24, 50, 30, kGrayLight);
  _circle(dst, 44, 38, 3, kGreen);
  _circle(dst, 34, 38, 3, kGrayLight);
}

void _drawCode(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kInk);
  // </ >
  for (var i = 0; i < 10; i++) {
    _circle(dst, 20 + i, 22 + i, 2, kTealLight);
    _circle(dst, 20 + i, 42 - i, 2, kTealLight);
    _circle(dst, 44 - i, 22 + i, 2, kOrange);
    _circle(dst, 44 - i, 42 - i, 2, kOrange);
  }
  _rect(dst, 30, 18, 34, 46, kBlueLight);
}

void _drawClipboard(img.Image dst) {
  _rect(dst, 16, 12, 48, 56, kGrayLight);
  img.drawRect(dst, x1: 16, y1: 12, x2: 48, y2: 56, color: _c(kGray));
  _rect(dst, 24, 8, 40, 18, kOrange);
  for (final y in [26, 34, 42, 50]) {
    _rect(dst, 22, y, 42, y + 3, kBlue);
  }
}

void _drawBriefcase(img.Image dst) {
  _rect(dst, 24, 12, 40, 22, kGray);
  _rect(dst, 10, 20, 54, 50, kOrange);
  _rect(dst, 10, 32, 54, 38, kOrangeLight);
  _rect(dst, 28, 30, 36, 40, kInk);
}

void _drawStickyNote(img.Image dst) {
  _rect(dst, 14, 12, 52, 52, 0xFFFFE08A);
  _rect(dst, 14, 12, 52, 20, 0xFFFFD24A);
  for (final y in [28, 36, 44]) {
    _rect(dst, 22, y, 44, y + 3, 0xFFE0B84A);
  }
}

void _drawInfo(img.Image dst) {
  _circle(dst, 32, 32, 22, kBlue);
  _circle(dst, 32, 18, 3, kWhite);
  _rect(dst, 29, 26, 35, 48, kWhite);
}

void _drawCross(img.Image dst) {
  _circle(dst, 32, 32, 22, kRed);
  for (var i = 0; i < 18; i++) {
    _circle(dst, 22 + i, 22 + i, 2, kWhite);
    _circle(dst, 42 - i, 22 + i, 2, kWhite);
  }
}

void _drawStar(img.Image dst) {
  // Simple 5-point approximation via overlapping triangles / diamonds.
  final pts = <List<int>>[
    [32, 8],
    [38, 24],
    [54, 24],
    [42, 36],
    [46, 52],
    [32, 42],
    [18, 52],
    [22, 36],
    [10, 24],
    [26, 24],
  ];
  for (final p in pts) {
    _circle(dst, p[0], p[1], 5, 0xFFF5C518);
  }
  _circle(dst, 32, 30, 10, 0xFFF5C518);
}

void _drawBell(img.Image dst) {
  _circle(dst, 32, 20, 8, kOrange);
  _rect(dst, 18, 20, 46, 40, kOrange);
  _circle(dst, 32, 40, 14, kOrange);
  _rect(dst, 14, 40, 50, 46, kOrangeLight);
  _circle(dst, 32, 50, 3, kInk);
}

void _drawWifi(img.Image dst) {
  // Thick upper arcs + hotspot.
  for (final r in [10, 16, 22]) {
    for (var t = 0; t <= 180; t++) {
      final rad = t * math.pi / 180;
      final x = 32 + (r * math.cos(rad)).round();
      final y = 44 - (r * math.sin(rad)).round();
      _circle(dst, x, y, 2, kBlue);
    }
  }
  _circle(dst, 32, 46, 4, kBlue);
}

void _drawRouter(img.Image dst) {
  _rect(dst, 10, 28, 54, 50, kGray);
  _circle(dst, 20, 39, 3, kGreen);
  _circle(dst, 30, 39, 3, kGrayLight);
  _rect(dst, 18, 10, 22, 30, kInk);
  _rect(dst, 42, 10, 46, 30, kInk);
  _circle(dst, 20, 10, 3, kInk);
  _circle(dst, 44, 10, 3, kInk);
}

void _drawFirewall(img.Image dst) {
  _rect(dst, 12, 12, 52, 52, kRed);
  for (final y in [20, 30, 40]) {
    _rect(dst, 12, y, 52, y + 4, kOrange);
  }
  _rect(dst, 28, 22, 36, 48, kInk);
}

void _drawApi(img.Image dst) {
  _circle(dst, 18, 32, 8, kTeal);
  _circle(dst, 46, 32, 8, kBlue);
  _rect(dst, 24, 28, 40, 36, kGrayLight);
  _rect(dst, 30, 18, 34, 46, kOrange);
}

void _drawLightbulb(img.Image dst) {
  _circle(dst, 32, 26, 16, 0xFFF5C518);
  _rect(dst, 24, 36, 40, 44, 0xFFF5C518);
  _rect(dst, 26, 44, 38, 54, kGray);
  _rect(dst, 28, 50, 36, 56, kGrayLight);
}

void _drawTarget(img.Image dst) {
  _circle(dst, 32, 32, 22, kRed);
  _circle(dst, 32, 32, 15, kWhite);
  _circle(dst, 32, 32, 9, kRed);
  _circle(dst, 32, 32, 4, kInk);
}

void _drawFlag(img.Image dst) {
  _rect(dst, 16, 8, 20, 56, kGray);
  _rect(dst, 20, 10, 50, 30, kBlue);
  _rect(dst, 20, 30, 50, 34, kBlueDark);
}

void _drawRocket(img.Image dst) {
  _circle(dst, 32, 16, 8, kBlue);
  _rect(dst, 24, 16, 40, 42, kBlue);
  _rect(dst, 18, 36, 26, 48, kOrange);
  _rect(dst, 38, 36, 46, 48, kOrange);
  _rect(dst, 28, 42, 36, 56, kRed);
}

void _drawClock(img.Image dst) {
  _circle(dst, 32, 32, 22, kGrayLight);
  img.drawCircle(dst, x: 32, y: 32, radius: 22, color: _c(kGray));
  _rect(dst, 30, 18, 34, 34, kInk);
  _rect(dst, 30, 30, 46, 34, kInk);
  _circle(dst, 32, 32, 3, kOrange);
}

void _drawPackage(img.Image dst) {
  _rect(dst, 12, 22, 52, 52, kOrange);
  _rect(dst, 12, 22, 52, 34, kOrangeLight);
  _rect(dst, 30, 22, 34, 52, kInk);
  _rect(dst, 12, 32, 52, 36, kInk);
}

void _drawMapPin(img.Image dst) {
  _circle(dst, 32, 24, 14, kRed);
  _circle(dst, 32, 24, 6, kWhite);
  for (var y = 32; y <= 54; y++) {
    final t = (y - 32) / 22;
    final half = ((1 - t) * 10).round().clamp(1, 10);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
}

void _drawWallet(img.Image dst) {
  _rect(dst, 10, 18, 54, 50, kTeal);
  _rect(dst, 10, 18, 54, 28, kTealDark);
  _rect(dst, 36, 30, 52, 42, kTealLight);
  _circle(dst, 44, 36, 3, kOrange);
}

void _drawSupport(img.Image dst) {
  _circle(dst, 32, 28, 16, kTeal);
  _rect(dst, 14, 26, 22, 38, kTealDark);
  _rect(dst, 42, 26, 50, 38, kTealDark);
  _circle(dst, 32, 28, 6, kWhite);
  _rect(dst, 28, 40, 36, 54, kGray);
}

void _drawIdBadge(img.Image dst) {
  _rect(dst, 14, 10, 50, 56, kBlue);
  _rect(dst, 20, 16, 44, 34, kBlueLight);
  _circle(dst, 32, 24, 6, kWhite);
  _rect(dst, 22, 40, 42, 44, kWhite);
  _rect(dst, 24, 48, 40, 51, kGrayLight);
}

void _drawTablet(img.Image dst) {
  _rect(dst, 16, 8, 48, 56, kInk);
  _rect(dst, 20, 12, 44, 48, kBlue);
  _circle(dst, 32, 52, 2, kGrayLight);
}

void _drawCpu(img.Image dst) {
  _rect(dst, 18, 18, 46, 46, kGray);
  _rect(dst, 24, 24, 40, 40, kTeal);
  for (final x in [22, 30, 38]) {
    _rect(dst, x, 10, x + 4, 18, kInk);
    _rect(dst, x, 46, x + 4, 54, kInk);
  }
  for (final y in [22, 30, 38]) {
    _rect(dst, 10, y, 18, y + 4, kInk);
    _rect(dst, 46, y, 54, y + 4, kInk);
  }
}

void _drawBattery(img.Image dst) {
  _rect(dst, 10, 22, 48, 42, kGray);
  _rect(dst, 14, 26, 36, 38, kGreen);
  _rect(dst, 48, 28, 54, 36, kInk);
}

void _drawUsb(img.Image dst) {
  _rect(dst, 26, 8, 38, 24, kGray);
  _rect(dst, 22, 22, 42, 48, kInk);
  _circle(dst, 32, 34, 4, kGrayLight);
  _rect(dst, 28, 48, 36, 56, kBlue);
}

void _drawPresentation(img.Image dst) {
  _rect(dst, 10, 12, 54, 40, kBlue);
  _rect(dst, 14, 16, 50, 34, kBlueLight);
  _rect(dst, 30, 40, 34, 50, kGray);
  _rect(dst, 20, 50, 44, 54, kGray);
  _rect(dst, 18, 22, 24, 30, kOrange);
  _rect(dst, 28, 20, 34, 30, kTeal);
  _rect(dst, 38, 18, 44, 30, kGreen);
}

void _drawBook(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kBlue);
  _rect(dst, 14, 10, 22, 54, kBlueDark);
  for (final y in [20, 30, 40]) {
    _rect(dst, 28, y, 44, y + 3, kGrayLight);
  }
}

void _drawInbox(img.Image dst) {
  _rect(dst, 10, 24, 54, 52, kGray);
  _rect(dst, 10, 24, 54, 36, kGrayLight);
  _rect(dst, 22, 14, 42, 28, kBlue);
  _rect(dst, 24, 40, 40, 48, kInk);
}

void _drawMegaphone(img.Image dst) {
  for (var i = 0; i < 16; i++) {
    final half = 6 + i;
    _rect(dst, 14 + i, 32 - half ~/ 2, 15 + i, 32 + half ~/ 2, kOrange);
  }
  _rect(dst, 30, 26, 48, 38, kOrangeLight);
  _circle(dst, 50, 32, 6, kOrange);
  _rect(dst, 20, 38, 28, 52, kInk);
}

void _drawHeart(img.Image dst) {
  _circle(dst, 22, 24, 10, kRed);
  _circle(dst, 42, 24, 10, kRed);
  for (var y = 24; y <= 52; y++) {
    final t = (y - 24) / 28;
    final half = ((1 - t) * 20).round().clamp(1, 20);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
}

void _drawKey(img.Image dst) {
  _circle(dst, 20, 32, 12, kOrange);
  _circle(dst, 20, 32, 5, kWhite);
  _rect(dst, 28, 28, 54, 36, kOrange);
  _rect(dst, 44, 36, 48, 46, kOrange);
  _rect(dst, 50, 36, 54, 42, kOrange);
}

void _drawRefresh(img.Image dst) {
  img.drawCircle(dst, x: 32, y: 32, radius: 16, color: _c(kBlue));
  img.drawCircle(dst, x: 32, y: 32, radius: 12, color: _c(kBlue));
  // Clear a gap and add arrow heads.
  for (var y = 14; y < 28; y++) {
    for (var x = 28; x < 50; x++) {
      dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  for (var y = 36; y < 50; y++) {
    for (var x = 14; x < 34; x++) {
      dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _circle(dst, 44, 20, 4, kBlue);
  _circle(dst, 20, 44, 4, kBlue);
  // Redraw arcs thicker.
  for (var t = 40; t <= 200; t++) {
    final rad = t * math.pi / 180;
    final x = 32 + (16 * math.cos(rad)).round();
    final y = 32 + (16 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kBlue);
  }
  for (var t = 220; t <= 380; t++) {
    final rad = t * math.pi / 180;
    final x = 32 + (16 * math.cos(rad)).round();
    final y = 32 + (16 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kBlue);
  }
}

void _drawPause(img.Image dst) {
  _circle(dst, 32, 32, 22, kBlue);
  _rect(dst, 22, 18, 28, 46, kWhite);
  _rect(dst, 36, 18, 42, 46, kWhite);
}

void _drawLink(img.Image dst) {
  // Two overlapping chain links.
  img.drawCircle(dst, x: 22, y: 32, radius: 12, color: _c(kBlue));
  img.drawCircle(dst, x: 22, y: 32, radius: 8, color: _c(kBlue));
  img.drawCircle(dst, x: 42, y: 32, radius: 12, color: _c(kTeal));
  img.drawCircle(dst, x: 42, y: 32, radius: 8, color: _c(kTeal));
  _rect(dst, 20, 28, 44, 36, kGrayLight);
}

void _drawBluetooth(img.Image dst) {
  _rect(dst, 30, 10, 34, 54, kBlue);
  for (var i = 0; i < 14; i++) {
    _circle(dst, 34 + i, 18 + i, 2, kBlue);
    _circle(dst, 34 + i, 46 - i, 2, kBlue);
    _circle(dst, 30 - i, 18 + i, 2, kBlueLight);
    _circle(dst, 30 - i, 46 - i, 2, kBlueLight);
  }
}

void _drawSatellite(img.Image dst) {
  _rect(dst, 12, 12, 28, 28, kGray);
  _rect(dst, 36, 36, 52, 52, kGray);
  _rect(dst, 26, 26, 38, 38, kBlue);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 30 + i, 30 + i, 2, kOrange);
  }
}

void _drawCreditCard(img.Image dst) {
  _rect(dst, 8, 16, 56, 48, kBlue);
  _rect(dst, 8, 24, 56, 32, kInk);
  _rect(dst, 14, 38, 28, 42, kGrayLight);
  _rect(dst, 40, 38, 50, 42, kOrange);
}

void _drawShoppingCart(img.Image dst) {
  _rect(dst, 12, 16, 20, 22, kInk);
  _rect(dst, 16, 20, 50, 24, kBlue);
  _rect(dst, 18, 24, 48, 40, kBlueLight);
  _circle(dst, 24, 48, 5, kInk);
  _circle(dst, 42, 48, 5, kInk);
}

void _drawTrophy(img.Image dst) {
  _circle(dst, 32, 22, 14, 0xFFF5C518);
  _rect(dst, 18, 22, 46, 34, 0xFFF5C518);
  _rect(dst, 12, 18, 18, 30, kOrange);
  _rect(dst, 46, 18, 52, 30, kOrange);
  _rect(dst, 28, 34, 36, 44, kGray);
  _rect(dst, 22, 44, 42, 52, kGray);
}

void _drawChartPie(img.Image dst) {
  _circle(dst, 32, 32, 22, kBlue);
  // Slice.
  for (var a = 0; a <= 110; a++) {
    final rad = a * math.pi / 180;
    for (var r = 0; r <= 22; r++) {
      final x = 32 + (r * math.cos(rad)).round();
      final y = 32 - (r * math.sin(rad)).round();
      if (x >= 0 && x < kSize && y >= 0 && y < kSize) {
        dst.setPixelRgba(x, y, 0xE0, 0x7A, 0x2F, 0xFF);
      }
    }
  }
  _circle(dst, 32, 32, 6, kWhite);
}

void _drawShield(img.Image dst) {
  for (var y = 10; y <= 54; y++) {
    final t = y < 40 ? 1.0 : 1 - (y - 40) / 14;
    final half = (18 * t).round().clamp(2, 18);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _circle(dst, 32, 28, 6, kWhite);
  _rect(dst, 30, 28, 34, 42, kWhite);
}

void _drawFingerprint(img.Image dst) {
  for (final r in [6, 10, 14, 18]) {
    img.drawCircle(dst, x: 32, y: 34, radius: r, color: _c(kTeal));
  }
  for (var y = 8; y < 24; y++) {
    for (var x = 20; x < 44; x++) {
      dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 30, 12, 34, 28, kTeal);
}

void _drawEye(img.Image dst) {
  for (var y = 20; y <= 44; y++) {
    final t = 1 - ((y - 32).abs() / 12);
    final half = (22 * t).round().clamp(2, 22);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlueLight);
  }
  _circle(dst, 32, 32, 10, kBlue);
  _circle(dst, 32, 32, 5, kInk);
  _circle(dst, 34, 30, 2, kWhite);
}

void _drawTruck(img.Image dst) {
  _rect(dst, 8, 22, 40, 42, kBlue);
  _rect(dst, 40, 26, 56, 42, kTeal);
  _rect(dst, 44, 18, 54, 28, kBlueLight);
  _circle(dst, 20, 46, 6, kInk);
  _circle(dst, 48, 46, 6, kInk);
}

void _drawCar(img.Image dst) {
  _rect(dst, 12, 28, 52, 42, kRed);
  _rect(dst, 20, 18, 44, 30, kRed);
  _rect(dst, 24, 20, 30, 28, kBlueLight);
  _rect(dst, 34, 20, 40, 28, kBlueLight);
  _circle(dst, 22, 44, 6, kInk);
  _circle(dst, 42, 44, 6, kInk);
}

void _drawPlane(img.Image dst) {
  _rect(dst, 28, 10, 36, 50, kBlue);
  _rect(dst, 10, 28, 54, 36, kBlue);
  _rect(dst, 24, 48, 40, 54, kBlueDark);
  _circle(dst, 32, 12, 5, kBlue);
}

void _drawShip(img.Image dst) {
  _rect(dst, 20, 14, 44, 34, kGray);
  _rect(dst, 28, 8, 36, 16, kInk);
  for (var y = 34; y <= 50; y++) {
    final t = (y - 34) / 16;
    final half = (22 * (1 - t * 0.35)).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 8, 50, 56, 54, kBlueDark);
}

void _drawRobot(img.Image dst) {
  _rect(dst, 18, 16, 46, 44, kGray);
  _rect(dst, 22, 20, 30, 28, kBlueLight);
  _rect(dst, 34, 20, 42, 28, kBlueLight);
  _rect(dst, 26, 32, 38, 38, kTeal);
  _rect(dst, 14, 24, 18, 34, kInk);
  _rect(dst, 46, 24, 50, 34, kInk);
  _rect(dst, 22, 44, 28, 54, kGray);
  _rect(dst, 36, 44, 42, 54, kGray);
  _circle(dst, 32, 10, 4, kOrange);
}

void _drawCloudUpload(img.Image dst) {
  _drawCloud(dst);
  _rect(dst, 30, 28, 34, 48, kWhite);
  for (var i = 0; i < 8; i++) {
    _circle(dst, 32 - i, 30 + i, 2, kWhite);
    _circle(dst, 32 + i, 30 + i, 2, kWhite);
  }
}

void _drawCloudDownload(img.Image dst) {
  _drawCloud(dst);
  _rect(dst, 30, 26, 34, 44, kWhite);
  for (var i = 0; i < 8; i++) {
    _circle(dst, 32 - i, 42 - i, 2, kWhite);
    _circle(dst, 32 + i, 42 - i, 2, kWhite);
  }
}

void _drawAttachment(img.Image dst) {
  // Paperclip.
  for (var t = 40; t <= 320; t++) {
    final rad = t * math.pi / 180;
    final x = 28 + (10 * math.cos(rad)).round();
    final y = 24 + (14 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  for (var t = 200; t <= 480; t++) {
    final rad = t * math.pi / 180;
    final x = 36 + (8 * math.cos(rad)).round();
    final y = 36 + (12 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
}

void _drawTag(img.Image dst) {
  for (var y = 14; y <= 40; y++) {
    _rect(dst, 14, y, 40, y + 1, kOrange);
  }
  for (var i = 0; i < 18; i++) {
    _rect(dst, 40 + i, 26 - i ~/ 2, 41 + i, 28 + i ~/ 2, kOrange);
  }
  _circle(dst, 24, 27, 3, kWhite);
}

void _drawFilter(img.Image dst) {
  for (var y = 12; y <= 24; y++) {
    final half = 22 - (y - 12);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 28, 24, 36, 50, kBlue);
  _rect(dst, 24, 46, 40, 52, kBlueDark);
}

void _drawPlay(img.Image dst) {
  _circle(dst, 32, 32, 22, kGreen);
  for (var x = 24; x <= 42; x++) {
    final t = (x - 24) / 18;
    final half = ((1 - t) * 12).round().clamp(1, 12);
    _rect(dst, x, 32 - half, x + 1, 32 + half, kWhite);
  }
}

void _drawStop(img.Image dst) {
  _circle(dst, 32, 32, 22, kRed);
  _rect(dst, 22, 22, 42, 42, kWhite);
}

void _drawDownload(img.Image dst) {
  _rect(dst, 30, 10, 34, 36, kBlue);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 32 - i, 34 + i, 2, kBlue);
    _circle(dst, 32 + i, 34 + i, 2, kBlue);
  }
  _rect(dst, 16, 48, 48, 54, kBlueDark);
}

void _drawUpload(img.Image dst) {
  _rect(dst, 30, 22, 34, 48, kTeal);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 32 - i, 24 - i, 2, kTeal);
    _circle(dst, 32 + i, 24 - i, 2, kTeal);
  }
  _rect(dst, 16, 48, 48, 54, kTealDark);
}

void _drawBarcode(img.Image dst) {
  _rect(dst, 10, 14, 54, 50, kWhite);
  final widths = [2, 1, 3, 1, 2, 4, 1, 2, 1, 3, 2, 1, 4, 1, 2];
  var x = 14;
  var dark = true;
  for (final w in widths) {
    if (dark) _rect(dst, x, 18, x + w, 46, kInk);
    x += w + 1;
    dark = !dark;
  }
}

void _drawQrCode(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kWhite);
  void block(int x, int y, int s) => _rect(dst, x, y, x + s, y + s, kInk);
  block(14, 14, 14);
  block(36, 14, 14);
  block(14, 36, 14);
  block(20, 20, 4);
  block(42, 20, 4);
  block(20, 42, 4);
  block(34, 34, 4);
  block(40, 40, 6);
  block(34, 46, 4);
  block(46, 34, 4);
}

void _drawUnlock(img.Image dst) {
  for (var a = 0; a <= 180; a++) {
    final rad = a * math.pi / 180;
    final x = 32 + (11 * math.cos(rad)).round();
    final y = 18 - (11 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  _rect(dst, 20, 18, 24, 28, kGray);
  _rect(dst, 16, 28, 48, 54, kGreen);
  _circle(dst, 32, 40, 4, kWhite);
  _rect(dst, 30, 40, 34, 48, kWhite);
}

void _drawTrain(img.Image dst) {
  _rect(dst, 14, 14, 50, 40, kBlue);
  _rect(dst, 18, 18, 30, 28, kBlueLight);
  _rect(dst, 34, 18, 46, 28, kBlueLight);
  _circle(dst, 22, 44, 6, kInk);
  _circle(dst, 42, 44, 6, kInk);
  _rect(dst, 10, 50, 54, 54, kGray);
}

void _drawBike(img.Image dst) {
  img.drawCircle(dst, x: 18, y: 40, radius: 10, color: _c(kInk));
  img.drawCircle(dst, x: 46, y: 40, radius: 10, color: _c(kInk));
  _rect(dst, 18, 28, 46, 32, kOrange);
  _rect(dst, 30, 16, 34, 30, kOrange);
  _rect(dst, 22, 16, 38, 20, kGray);
}

void _drawMusic(img.Image dst) {
  _circle(dst, 22, 44, 8, kBlue);
  _circle(dst, 42, 36, 8, kBlue);
  _rect(dst, 26, 16, 30, 44, kBlue);
  _rect(dst, 46, 12, 50, 36, kBlue);
  _rect(dst, 26, 12, 50, 18, kBlueDark);
}

void _drawHeadphones(img.Image dst) {
  for (var t = 0; t <= 180; t++) {
    final rad = t * math.pi / 180;
    final x = 32 + (18 * math.cos(rad)).round();
    final y = 28 - (16 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kInk);
  }
  _rect(dst, 10, 28, 20, 48, kBlue);
  _rect(dst, 44, 28, 54, 48, kBlue);
}

void _drawMic(img.Image dst) {
  _rect(dst, 26, 10, 38, 36, kRed);
  _circle(dst, 32, 36, 6, kRed);
  for (var t = 0; t <= 180; t++) {
    final rad = t * math.pi / 180;
    final x = 32 + (14 * math.cos(rad)).round();
    final y = 36 + (10 * math.sin(rad)).round();
    _circle(dst, x, y, 1, kGray);
  }
  _rect(dst, 30, 46, 34, 54, kInk);
  _rect(dst, 24, 52, 40, 56, kInk);
}

void _drawFilm(img.Image dst) {
  _rect(dst, 12, 14, 52, 50, kInk);
  for (final x in [16, 44]) {
    for (final y in [18, 26, 34, 42]) {
      _rect(dst, x, y, x + 4, y + 4, kGrayLight);
    }
  }
  _rect(dst, 24, 18, 40, 46, kBlue);
}

void _drawSpeaker(img.Image dst) {
  _rect(dst, 14, 22, 28, 42, kGray);
  for (var x = 28; x <= 40; x++) {
    final half = 6 + (x - 28);
    _rect(dst, x, 32 - half, x + 1, 32 + half, kInk);
  }
  for (final r in [6, 11, 16]) {
    for (var t = -40; t <= 40; t++) {
      final rad = t * math.pi / 180;
      final x = 42 + (r * math.cos(rad)).round();
      final y = 32 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 1, kBlue);
    }
  }
}

void _drawWrench(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    _circle(dst, 20 + i, 20 + i, 3, kGray);
  }
  _circle(dst, 18, 18, 8, kGray);
  _circle(dst, 18, 18, 4, 0x00000000);
  for (var y = 14; y < 22; y++) {
    for (var x = 14; x < 22; x++) {
      // punch hole
    }
  }
  // Clear center of head.
  _circle(dst, 18, 18, 4, kWhite);
  for (var y = 14; y <= 22; y++) {
    for (var x = 14; x <= 22; x++) {
      final dx = x - 18, dy = y - 18;
      if (dx * dx + dy * dy <= 16) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 40, 40, 52, 52, kOrange);
}

void _drawHammer(img.Image dst) {
  _rect(dst, 14, 14, 48, 26, kGray);
  _rect(dst, 28, 26, 36, 54, kOrange);
}

void _drawMagnifier(img.Image dst) {
  img.drawCircle(dst, x: 26, y: 26, radius: 14, color: _c(kBlue));
  img.drawCircle(dst, x: 26, y: 26, radius: 10, color: _c(kBlue));
  for (var i = 0; i < 16; i++) {
    _circle(dst, 36 + i, 36 + i, 3, kInk);
  }
}

void _drawCompass(img.Image dst) {
  _circle(dst, 32, 32, 22, kGrayLight);
  img.drawCircle(dst, x: 32, y: 32, radius: 22, color: _c(kGray));
  for (var i = 0; i < 14; i++) {
    _circle(dst, 32, 18 + i, 2, kRed);
    _circle(dst, 32 - i ~/ 2, 32 + i, 2, kInk);
    _circle(dst, 32 + i ~/ 2, 32 + i, 2, kInk);
  }
  _circle(dst, 32, 32, 3, kOrange);
}

void _drawHome(img.Image dst) {
  for (var y = 10; y <= 30; y++) {
    final t = (y - 10) / 20;
    final half = (t * 22).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
  _rect(dst, 16, 30, 48, 54, kOrange);
  _rect(dst, 26, 38, 38, 54, kInk);
}

void _drawFactory(img.Image dst) {
  _rect(dst, 10, 28, 54, 54, kGray);
  _rect(dst, 14, 14, 24, 28, kGray);
  _rect(dst, 28, 18, 38, 28, kGray);
  _rect(dst, 42, 10, 52, 28, kGray);
  for (final x in [16, 30, 44]) {
    _rect(dst, x, 34, x + 6, 42, kOrange);
  }
}

void _drawHospital(img.Image dst) {
  _rect(dst, 14, 16, 50, 54, kWhite);
  img.drawRect(dst, x1: 14, y1: 16, x2: 50, y2: 54, color: _c(kGray));
  _rect(dst, 28, 22, 36, 48, kRed);
  _rect(dst, 20, 30, 44, 38, kRed);
}

void _drawSchool(img.Image dst) {
  for (var y = 12; y <= 28; y++) {
    final t = (y - 12) / 16;
    final half = (t * 20).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 16, 28, 48, 52, kBlueLight);
  _rect(dst, 26, 38, 38, 52, kInk);
  _circle(dst, 32, 22, 3, 0xFFF5C518);
}

void _drawTeam(img.Image dst) {
  void person(int x, int y, int r, int c) {
    _circle(dst, x, y, r, c);
    _circle(dst, x, y + 18, r + 4, c);
    _rect(dst, x - r - 2, y + 18, x + r + 2, y + 30, c);
  }

  person(16, 20, 6, kGray);
  person(48, 20, 6, kGray);
  person(32, 16, 8, kBlue);
}

void _drawDeveloper(img.Image dst) {
  _circle(dst, 32, 16, 8, kTeal);
  _circle(dst, 32, 38, 14, kTeal);
  _rect(dst, 18, 38, 46, 54, kTeal);
  _rect(dst, 22, 40, 28, 46, kWhite);
  _rect(dst, 36, 40, 42, 46, kWhite);
  _rect(dst, 30, 44, 34, 50, kWhite);
}

void _drawTerminal(img.Image dst) {
  _rect(dst, 10, 12, 54, 52, kInk);
  _rect(dst, 14, 16, 50, 48, 0xFF1A2330);
  for (var i = 0; i < 10; i++) {
    dst.setPixelRgba(20 + i, 24 + i, 0x3B, 0xB8, 0xA6, 0xFF);
    dst.setPixelRgba(20 + i, 34 - i, 0x3B, 0xB8, 0xA6, 0xFF);
  }
  _rect(dst, 34, 36, 46, 40, kTealLight);
}

void _drawKeyboard(img.Image dst) {
  _rect(dst, 8, 22, 56, 46, kGray);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 8; col++) {
      _rect(dst, 12 + col * 5, 26 + row * 6, 15 + col * 5, 29 + row * 6, kGrayLight);
    }
  }
}

void _drawNetworkSwitch(img.Image dst) {
  _rect(dst, 10, 20, 54, 44, kBlueDark);
  for (var i = 0; i < 6; i++) {
    _rect(dst, 14 + i * 7, 26, 18 + i * 7, 38, kGrayLight);
    _circle(dst, 16 + i * 7, 30, 1, i.isEven ? kGreen : kOrange);
  }
}

void _drawContainer(img.Image dst) {
  _rect(dst, 12, 18, 52, 48, kBlue);
  _rect(dst, 12, 18, 52, 26, kBlueDark);
  for (final x in [22, 32, 42]) {
    _rect(dst, x, 18, x + 2, 48, kBlueLight);
  }
  _rect(dst, 28, 10, 36, 18, kOrange);
}

void _drawCalculator(img.Image dst) {
  _rect(dst, 16, 8, 48, 56, kInk);
  _rect(dst, 20, 12, 44, 22, kBlue);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 3; c++) {
      _rect(dst, 20 + c * 9, 26 + r * 7, 26 + c * 9, 30 + r * 7, kGrayLight);
    }
  }
}

void _drawArchive(img.Image dst) {
  _rect(dst, 12, 14, 52, 28, kOrange);
  _rect(dst, 12, 28, 52, 52, kOrangeLight);
  _rect(dst, 26, 20, 38, 24, kWhite);
  _rect(dst, 16, 34, 48, 38, kOrange);
  _rect(dst, 16, 42, 48, 46, kOrange);
}

void _drawPen(img.Image dst) {
  for (var i = 0; i < 30; i++) {
    _circle(dst, 18 + i, 46 - i, 3, kBlue);
  }
  for (var i = 0; i < 8; i++) {
    _circle(dst, 14 + i, 50 - i, 2, kOrange);
  }
  _rect(dst, 44, 12, 52, 20, kInk);
}

void _drawScissors(img.Image dst) {
  _circle(dst, 18, 42, 8, kGray);
  _circle(dst, 18, 42, 4, 0x00000000);
  for (var y = 38; y <= 46; y++) {
    for (var x = 14; x <= 22; x++) {
      final dx = x - 18, dy = y - 42;
      if (dx * dx + dy * dy <= 16) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _circle(dst, 18, 22, 8, kGray);
  for (var y = 18; y <= 26; y++) {
    for (var x = 14; x <= 22; x++) {
      final dx = x - 18, dy = y - 22;
      if (dx * dx + dy * dy <= 16) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  for (var i = 0; i < 28; i++) {
    _circle(dst, 24 + i, 32, 2, kBlue);
    _circle(dst, 24 + i, 32 - (i ~/ 3), 2, kTeal);
  }
}

void _drawQuestion(img.Image dst) {
  _circle(dst, 32, 32, 22, kBlue);
  _circle(dst, 32, 24, 8, kWhite);
  _circle(dst, 32, 24, 4, kBlue);
  _rect(dst, 28, 24, 36, 36, kWhite);
  _rect(dst, 32, 28, 40, 36, kBlue);
  _circle(dst, 32, 46, 3, kWhite);
}

void _drawPower(img.Image dst) {
  img.drawCircle(dst, x: 32, y: 34, radius: 16, color: _c(kGreen));
  img.drawCircle(dst, x: 32, y: 34, radius: 12, color: _c(kGreen));
  _rect(dst, 28, 12, 36, 34, 0x00000000);
  for (var y = 12; y < 34; y++) {
    for (var x = 28; x < 36; x++) {
      dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 30, 10, 34, 30, kGreen);
}

void _drawThumbsUp(img.Image dst) {
  _rect(dst, 14, 28, 28, 52, kOrange);
  _rect(dst, 28, 24, 50, 52, kOrangeLight);
  _rect(dst, 32, 12, 42, 28, kOrange);
  _circle(dst, 37, 14, 5, kOrange);
}

void _drawSignal(img.Image dst) {
  for (var i = 0; i < 4; i++) {
    final h = 10 + i * 10;
    _rect(dst, 14 + i * 12, 52 - h, 22 + i * 12, 52, i < 3 ? kBlue : kBlueLight);
  }
}

void _drawEthernet(img.Image dst) {
  _rect(dst, 18, 14, 46, 50, kGray);
  _rect(dst, 22, 18, 42, 36, kGrayLight);
  _rect(dst, 26, 36, 38, 44, kInk);
  for (final x in [28, 32, 36]) {
    _rect(dst, x, 44, x + 2, 50, kInk);
  }
}

void _drawVpn(img.Image dst) {
  _circle(dst, 32, 28, 16, kTeal);
  _circle(dst, 32, 28, 10, kTealLight);
  _rect(dst, 28, 40, 36, 52, kTealDark);
  _rect(dst, 24, 48, 40, 54, kTeal);
  _circle(dst, 32, 28, 4, kWhite);
}

void _drawDns(img.Image dst) {
  _circle(dst, 32, 18, 8, kBlue);
  _circle(dst, 16, 46, 8, kTeal);
  _circle(dst, 48, 46, 8, kOrange);
  for (var i = 0; i < 20; i++) {
    _circle(dst, 32 - i, 18 + (i * 28 / 20).round(), 1, kGray);
    _circle(dst, 32 + i, 18 + (i * 28 / 20).round(), 1, kGray);
    _circle(dst, 16 + i, 46, 1, kGray);
  }
}

void _drawFunnel(img.Image dst) {
  for (var y = 12; y <= 36; y++) {
    final t = (y - 12) / 24;
    final half = (20 - t * 14).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrange);
  }
  _rect(dst, 28, 36, 36, 52, kOrangeLight);
}

void _drawCoin(img.Image dst) {
  _circle(dst, 32, 32, 20, 0xFFF5C518);
  _circle(dst, 32, 32, 14, 0xFFE0A800);
  _rect(dst, 28, 22, 36, 42, 0xFFF5C518);
}

void _drawContract(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kWhite);
  img.drawRect(dst, x1: 14, y1: 10, x2: 50, y2: 54, color: _c(kBlueDark));
  for (final y in [18, 26, 34]) {
    _rect(dst, 20, y, 44, y + 3, kGrayLight);
  }
  _rect(dst, 22, 42, 30, 50, kTeal);
  for (var i = 0; i < 8; i++) {
    dst.setPixelRgba(32 + i, 44 + (i ~/ 2), 0x2F, 0x9E, 0x5C, 0xFF);
  }
}

void _drawChartLine(img.Image dst) {
  _rect(dst, 12, 12, 16, 52, kGray);
  _rect(dst, 12, 48, 52, 52, kGray);
  final pts = [16, 40, 28, 28, 40, 34, 52, 16];
  for (var i = 0; i < pts.length - 2; i += 2) {
    final x0 = pts[i], y0 = pts[i + 1], x1 = pts[i + 2], y1 = pts[i + 3];
    for (var t = 0; t <= 16; t++) {
      final x = x0 + ((x1 - x0) * t / 16).round();
      final y = y0 + ((y1 - y0) * t / 16).round();
      _circle(dst, x, y, 2, kBlue);
    }
  }
}

void _drawVault(img.Image dst) {
  _rect(dst, 12, 14, 52, 52, kGray);
  _circle(dst, 32, 34, 12, kInk);
  _circle(dst, 32, 34, 6, kGrayLight);
  _rect(dst, 30, 20, 34, 28, kOrange);
  for (var t = 0; t < 360; t += 45) {
    final rad = t * math.pi / 180;
    final x = 32 + (10 * math.cos(rad)).round();
    final y = 34 + (10 * math.sin(rad)).round();
    _circle(dst, x, y, 1, kOrange);
  }
}

void _drawPassword(img.Image dst) {
  _rect(dst, 10, 22, 54, 46, kBlueDark);
  for (final x in [18, 28, 38]) {
    _circle(dst, x, 34, 3, kWhite);
  }
  _rect(dst, 44, 30, 50, 38, kGrayLight);
}

void _drawBus(img.Image dst) {
  _rect(dst, 10, 20, 54, 44, kOrange);
  _rect(dst, 14, 24, 50, 34, kBlueLight);
  _circle(dst, 20, 48, 6, kInk);
  _circle(dst, 44, 48, 6, kInk);
  _rect(dst, 48, 28, 54, 36, kOrangeLight);
}

void _drawPhoto(img.Image dst) {
  _rect(dst, 10, 14, 54, 50, kWhite);
  img.drawRect(dst, x1: 10, y1: 14, x2: 54, y2: 50, color: _c(kGray));
  _circle(dst, 22, 26, 5, kOrange);
  for (var i = 0; i < 24; i++) {
    final y = 44 - (i < 12 ? i : 12);
    _rect(dst, 18 + i, y, 19 + i, 46, kTeal);
  }
}

void _drawVideo(img.Image dst) {
  _rect(dst, 10, 18, 40, 46, kBlue);
  for (var i = 0; i < 14; i++) {
    final half = i ~/ 2;
    _rect(dst, 40 + i, 32 - half - 4, 41 + i, 32 + half + 4, kInk);
  }
}

void _drawScrewdriver(img.Image dst) {
  _rect(dst, 28, 10, 36, 36, kOrange);
  _rect(dst, 30, 36, 34, 54, kGray);
  _rect(dst, 28, 50, 36, 56, kInk);
}

void _drawRuler(img.Image dst) {
  for (var i = 0; i < 36; i++) {
    _rect(dst, 14 + i, 20 + i ~/ 2, 18 + i, 28 + i ~/ 2, kOrangeLight);
  }
  for (var i = 0; i < 5; i++) {
    final x = 18 + i * 7;
    final y = 22 + i * 3;
    _rect(dst, x, y, x + 2, y + 6, kInk);
  }
}

void _drawBolt(img.Image dst) {
  _circle(dst, 32, 20, 10, kGray);
  _rect(dst, 28, 20, 36, 48, kGray);
  _circle(dst, 32, 20, 4, 0x00000000);
  for (var y = 16; y <= 24; y++) {
    for (var x = 28; x <= 36; x++) {
      final dx = x - 32, dy = y - 20;
      if (dx * dx + dy * dy <= 16) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  for (var y = 48; y < 56; y++) {
    final half = 6 - (y - 48);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kGray);
  }
}

void _drawWarehouse(img.Image dst) {
  for (var y = 10; y <= 24; y++) {
    final t = (y - 10) / 14;
    final half = (8 + t * 18).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kGray);
  }
  _rect(dst, 12, 24, 52, 52, kGrayLight);
  _rect(dst, 24, 34, 40, 52, kOrange);
  _rect(dst, 16, 30, 22, 36, kBlue);
  _rect(dst, 42, 30, 48, 36, kBlue);
}

void _drawStore(img.Image dst) {
  _rect(dst, 12, 28, 52, 54, kBlue);
  for (var x = 12; x <= 48; x += 8) {
    _rect(dst, x, 18, x + 8, 28, x % 16 == 12 ? kOrange : kOrangeLight);
  }
  _rect(dst, 26, 38, 38, 54, kInk);
  _rect(dst, 16, 36, 24, 44, kBlueLight);
}

void _drawLab(img.Image dst) {
  _rect(dst, 28, 10, 36, 28, kGray);
  for (var y = 28; y <= 50; y++) {
    final t = (y - 28) / 22;
    final half = (6 + t * 12).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kTeal);
  }
  _rect(dst, 22, 40, 42, 48, kTealLight);
  _circle(dst, 26, 44, 2, kWhite);
  _circle(dst, 36, 42, 2, kWhite);
}

void _drawChat(img.Image dst) {
  _rect(dst, 10, 12, 48, 40, kBlue);
  _circle(dst, 16, 40, 8, kBlue);
  _circle(dst, 48, 16, 8, kBlue);
  _circle(dst, 48, 40, 8, kBlue);
  _rect(dst, 10, 16, 48, 40, kBlue);
  for (var i = 0; i < 10; i++) {
    _rect(dst, 18 + i, 40 + i, 20 + i, 42 + i, kBlue);
  }
  for (final y in [20, 28]) {
    _rect(dst, 18, y, 40, y + 3, kWhite);
  }
}

void _drawCall(img.Image dst) {
  _rect(dst, 18, 14, 34, 50, kGreen);
  _circle(dst, 26, 20, 6, kGreen);
  _circle(dst, 26, 44, 6, kGreen);
  for (var i = 0; i < 16; i++) {
    final a = -40 + i * 5;
    final rad = a * math.pi / 180;
    final x = 34 + (10 * math.cos(rad)).round();
    final y = 20 + (10 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGreen);
  }
  for (var i = 0; i < 16; i++) {
    final a = 40 + i * 5;
    final rad = a * math.pi / 180;
    final x = 34 + (10 * math.cos(rad)).round();
    final y = 44 + (10 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGreen);
  }
  _rect(dst, 30, 24, 46, 40, kGreen);
}

void _drawVideoCall(img.Image dst) {
  _rect(dst, 10, 18, 38, 46, kTeal);
  _circle(dst, 24, 32, 8, kTealLight);
  _circle(dst, 24, 28, 4, kWhite);
  for (var i = 0; i < 12; i++) {
    final half = 4 + i ~/ 2;
    _rect(dst, 38 + i, 32 - half, 39 + i, 32 + half, kInk);
  }
}

void _drawComment(img.Image dst) {
  _rect(dst, 12, 14, 52, 42, kGrayLight);
  img.drawRect(dst, x1: 12, y1: 14, x2: 52, y2: 42, color: _c(kGray));
  for (final y in [20, 28]) {
    _rect(dst, 18, y, 46, y + 3, kGray);
  }
  for (var i = 0; i < 10; i++) {
    _rect(dst, 24 + i, 42 + i ~/ 2, 28 + i, 44 + i ~/ 2, kGrayLight);
  }
}

void _drawCustomer(img.Image dst) {
  _circle(dst, 32, 16, 9, kOrange);
  _circle(dst, 32, 40, 15, kOrange);
  _rect(dst, 17, 40, 47, 54, kOrange);
  _rect(dst, 22, 44, 42, 50, kWhite);
}

void _drawAdmin(img.Image dst) {
  _circle(dst, 32, 16, 9, kInk);
  _circle(dst, 32, 40, 15, kInk);
  _rect(dst, 17, 40, 47, 54, kInk);
  _rect(dst, 24, 12, 40, 16, 0xFFF5C518);
  _rect(dst, 28, 8, 36, 12, 0xFFF5C518);
}

void _drawMouse(img.Image dst) {
  _rect(dst, 22, 12, 42, 52, kGray);
  _rect(dst, 22, 12, 42, 28, kInk);
  _rect(dst, 30, 12, 34, 28, kGrayLight);
  _circle(dst, 32, 36, 3, kBlue);
}

void _drawWebcam(img.Image dst) {
  _circle(dst, 32, 28, 16, kInk);
  _circle(dst, 32, 28, 10, kBlue);
  _circle(dst, 32, 28, 4, kBlueLight);
  _rect(dst, 28, 44, 36, 52, kGray);
  _rect(dst, 20, 50, 44, 54, kGray);
}

void _drawSdCard(img.Image dst) {
  _rect(dst, 18, 14, 46, 54, kBlue);
  _rect(dst, 18, 14, 34, 22, kBlue);
  for (var x = 22; x <= 38; x += 5) {
    _rect(dst, x, 14, x + 3, 20, kBlueDark);
  }
  _rect(dst, 24, 30, 40, 36, kWhite);
}

void _drawStamp(img.Image dst) {
  _circle(dst, 32, 28, 16, kRed);
  _circle(dst, 32, 28, 10, kWhite);
  _rect(dst, 24, 44, 40, 54, kInk);
  _rect(dst, 28, 40, 36, 44, kGray);
}

void _drawNotepad(img.Image dst) {
  _rect(dst, 16, 10, 48, 54, kWhite);
  img.drawRect(dst, x1: 16, y1: 10, x2: 48, y2: 54, color: _c(kBlueDark));
  _rect(dst, 16, 10, 48, 18, kBlue);
  for (final y in [24, 32, 40, 48]) {
    _rect(dst, 22, y, 42, y + 2, kGrayLight);
  }
}

void _drawBookmark(img.Image dst) {
  _rect(dst, 20, 10, 44, 54, kRed);
  for (var y = 42; y < 54; y++) {
    final inset = y - 42;
    for (var x = 20; x < 44; x++) {
      if ((x - 32).abs() < inset) {
        dst.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
}

void _drawShare(img.Image dst) {
  _circle(dst, 18, 32, 6, kBlue);
  _circle(dst, 46, 18, 6, kTeal);
  _circle(dst, 46, 46, 6, kOrange);
  for (var i = 0; i < 18; i++) {
    _circle(dst, 18 + i, 32 - i, 1, kGray);
    _circle(dst, 18 + i, 32 + i, 1, kGray);
  }
}

void _drawMute(img.Image dst) {
  _rect(dst, 12, 24, 26, 40, kGray);
  for (var x = 26; x <= 38; x++) {
    final half = 4 + (x - 26);
    _rect(dst, x, 32 - half, x + 1, 32 + half, kInk);
  }
  for (var i = 0; i < 28; i++) {
    _circle(dst, 18 + i, 18 + i, 2, kRed);
  }
}

void _drawGateway(img.Image dst) {
  _rect(dst, 14, 22, 50, 42, kBlueDark);
  _rect(dst, 20, 16, 44, 22, kBlue);
  for (final x in [22, 32, 42]) {
    _rect(dst, x, 28, x + 4, 36, kGreen);
  }
  _rect(dst, 28, 42, 36, 52, kGray);
}

void _drawHotspot(img.Image dst) {
  _circle(dst, 32, 40, 4, kOrange);
  for (final r in [10, 16, 22]) {
    for (var t = 200; t <= 340; t += 4) {
      final rad = t * math.pi / 180;
      final x = 32 + (r * math.cos(rad)).round();
      final y = 40 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 1, kOrange);
    }
  }
}

void _drawLoadBalancer(img.Image dst) {
  _circle(dst, 32, 18, 8, kBlue);
  _circle(dst, 16, 48, 7, kTeal);
  _circle(dst, 32, 48, 7, kTeal);
  _circle(dst, 48, 48, 7, kTeal);
  for (var i = 0; i < 20; i++) {
    _circle(dst, 32 - (i * 16 / 20).round(), 18 + (i * 30 / 20).round(), 1, kGray);
    _circle(dst, 32, 18 + (i * 30 / 20).round(), 1, kGray);
    _circle(dst, 32 + (i * 16 / 20).round(), 18 + (i * 30 / 20).round(), 1, kGray);
  }
}

void _drawInvoice(img.Image dst) {
  _rect(dst, 14, 8, 50, 56, kWhite);
  img.drawRect(dst, x1: 14, y1: 8, x2: 50, y2: 56, color: _c(kGray));
  _rect(dst, 14, 8, 50, 18, kTeal);
  for (final y in [24, 32, 40]) {
    _rect(dst, 20, y, 36, y + 2, kGrayLight);
    _rect(dst, 40, y, 44, y + 2, kOrange);
  }
  _rect(dst, 20, 48, 44, 52, kTealLight);
}

void _drawTimeline(img.Image dst) {
  _rect(dst, 10, 30, 54, 34, kGray);
  for (final x in [16, 32, 48]) {
    _circle(dst, x, 32, 6, kBlue);
    _rect(dst, x - 2, 18, x + 2, 26, kBlueLight);
  }
}

void _drawKanban(img.Image dst) {
  for (var c = 0; c < 3; c++) {
    final x0 = 10 + c * 18;
    _rect(dst, x0, 10, x0 + 14, 54, kGrayLight);
    _rect(dst, x0 + 2, 14, x0 + 12, 22, c == 0 ? kBlue : (c == 1 ? kOrange : kGreen));
    _rect(dst, x0 + 2, 26, x0 + 12, 34, kWhite);
    if (c < 2) _rect(dst, x0 + 2, 38, x0 + 12, 46, kWhite);
  }
}

void _drawBug(img.Image dst) {
  _circle(dst, 32, 32, 12, kRed);
  _circle(dst, 32, 22, 8, kRed);
  _rect(dst, 20, 30, 24, 42, kInk);
  _rect(dst, 40, 30, 44, 42, kInk);
  _rect(dst, 28, 14, 36, 18, kInk);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 20 - i, 24 + i, 1, kInk);
    _circle(dst, 44 + i, 24 + i, 1, kInk);
  }
}

void _drawCertificate(img.Image dst) {
  _rect(dst, 12, 14, 52, 42, kWhite);
  img.drawRect(dst, x1: 12, y1: 14, x2: 52, y2: 42, color: _c(kBlueDark));
  _rect(dst, 18, 20, 34, 24, kBlue);
  _rect(dst, 18, 28, 46, 31, kGrayLight);
  _circle(dst, 42, 44, 10, kOrange);
  _circle(dst, 42, 44, 5, 0xFFF5C518);
}

void _drawParking(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kBlue);
  _rect(dst, 24, 18, 36, 46, kWhite);
  _rect(dst, 36, 18, 44, 34, kWhite);
  _rect(dst, 24, 30, 44, 34, kBlue);
}

void _drawTv(img.Image dst) {
  _rect(dst, 10, 14, 54, 44, kInk);
  _rect(dst, 14, 18, 50, 40, kBlue);
  _rect(dst, 28, 44, 36, 50, kGray);
  _rect(dst, 20, 50, 44, 54, kGray);
}

void _drawRadio(img.Image dst) {
  _rect(dst, 12, 22, 52, 50, kOrange);
  _circle(dst, 42, 36, 8, kInk);
  _rect(dst, 18, 28, 30, 32, kWhite);
  _rect(dst, 18, 36, 30, 40, kWhite);
  for (var i = 0; i < 16; i++) {
    _circle(dst, 20 + i, 22 - i, 1, kGray);
  }
}

void _drawPaintbrush(img.Image dst) {
  for (var i = 0; i < 26; i++) {
    _circle(dst, 20 + i, 44 - i, 3, kOrange);
  }
  _rect(dst, 40, 12, 52, 24, kBlue);
  _rect(dst, 36, 18, 48, 28, kBlueLight);
}

void _drawFlashlight(img.Image dst) {
  _rect(dst, 24, 8, 40, 22, kGrayLight);
  _rect(dst, 26, 22, 38, 48, kInk);
  _circle(dst, 32, 52, 4, kOrange);
  _rect(dst, 28, 30, 36, 34, kGray);
}

void _drawAirport(img.Image dst) {
  _rect(dst, 12, 28, 52, 52, kGray);
  for (var y = 10; y <= 28; y++) {
    final t = (y - 10) / 18;
    final half = (6 + t * 20).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 28, 36, 36, 52, kInk);
  _rect(dst, 16, 34, 24, 40, kBlueLight);
  _rect(dst, 40, 34, 48, 40, kBlueLight);
}

void _drawPark(img.Image dst) {
  _rect(dst, 30, 36, 34, 54, kOrange);
  _circle(dst, 32, 28, 14, kGreen);
  _circle(dst, 22, 34, 10, kGreen);
  _circle(dst, 42, 34, 10, kGreen);
  _rect(dst, 10, 52, 54, 56, kTealDark);
}

void _drawBroadcast(img.Image dst) {
  _circle(dst, 20, 32, 5, kRed);
  for (final r in [12, 18, 24]) {
    for (var t = -50; t <= 50; t += 4) {
      final rad = t * math.pi / 180;
      final x = 20 + (r * math.cos(rad)).round();
      final y = 32 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 1, kRed);
    }
  }
  _rect(dst, 40, 20, 50, 44, kInk);
  _rect(dst, 44, 44, 48, 52, kGray);
}

void _drawMailOpen(img.Image dst) {
  for (var t = 0; t <= 22; t++) {
    final y = 28 - t;
    dst.setPixelRgba(10 + t, y, 0x2F, 0x6F, 0xED, 0xFF);
    dst.setPixelRgba(54 - t, y, 0x2F, 0x6F, 0xED, 0xFF);
    if (y > 0) {
      dst.setPixelRgba(10 + t, y - 1, 0x2F, 0x6F, 0xED, 0xFF);
      dst.setPixelRgba(54 - t, y - 1, 0x2F, 0x6F, 0xED, 0xFF);
    }
  }
  _rect(dst, 10, 28, 54, 50, kBlue);
  for (var t = 0; t <= 22; t++) {
    final y = 28 + (t * 10 / 22).round();
    dst.setPixelRgba(10 + t, y, 0xFF, 0xFF, 0xFF, 0xFF);
    dst.setPixelRgba(54 - t, y, 0xFF, 0xFF, 0xFF, 0xFF);
  }
}

void _drawPlug(img.Image dst) {
  _rect(dst, 22, 28, 42, 52, kGray);
  _rect(dst, 26, 12, 32, 28, kInk);
  _rect(dst, 34, 12, 40, 28, kInk);
  _rect(dst, 28, 52, 36, 58, kGrayLight);
}

void _drawLightning(img.Image dst) {
  final pts = <List<int>>[
    [34, 8],
    [20, 32],
    [30, 32],
    [24, 56],
    [46, 28],
    [34, 28],
  ];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    for (var t = 0; t <= 20; t++) {
      final x = a[0] + ((b[0] - a[0]) * t / 20).round();
      final y = a[1] + ((b[1] - a[1]) * t / 20).round();
      _circle(dst, x, y, 3, 0xFFF5C518);
    }
  }
  // Fill roughly with scan of yellow blob via thick strokes already.
  _rect(dst, 26, 24, 36, 36, 0xFFF5C518);
}

void _drawSun(img.Image dst) {
  _circle(dst, 32, 32, 12, 0xFFF5C518);
  for (var t = 0; t < 360; t += 45) {
    final rad = t * math.pi / 180;
    for (var r = 16; r <= 24; r++) {
      final x = 32 + (r * math.cos(rad)).round();
      final y = 32 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 2, kOrange);
    }
  }
}

void _drawLeaf(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    final t = i / 27;
    final w = (math.sin(t * math.pi) * 12).round();
    _rect(dst, 32 - w, 12 + i, 32 + w, 13 + i, kGreen);
  }
  for (var i = 0; i < 20; i++) {
    _circle(dst, 32 + i ~/ 2, 40 + i, 1, kTealDark);
  }
}

void _drawRecycle(img.Image dst) {
  for (var ring = 0; ring < 3; ring++) {
    final base = ring * 120;
    for (var t = base; t < base + 80; t += 3) {
      final rad = t * math.pi / 180;
      final x = 32 + (18 * math.cos(rad)).round();
      final y = 32 + (18 * math.sin(rad)).round();
      _circle(dst, x, y, 3, kGreen);
    }
    final tip = (base + 80) * math.pi / 180;
    final tx = 32 + (18 * math.cos(tip)).round();
    final ty = 32 + (18 * math.sin(tip)).round();
    _circle(dst, tx, ty, 5, kGreen);
  }
}

void _drawWater(img.Image dst) {
  for (var y = 12; y <= 36; y++) {
    final t = (y - 12) / 24;
    final half = (t * 14).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _circle(dst, 32, 42, 14, kBlue);
  _circle(dst, 28, 40, 3, kBlueLight);
}

void _drawThermometer(img.Image dst) {
  _rect(dst, 28, 8, 36, 44, kGrayLight);
  img.drawRect(dst, x1: 28, y1: 8, x2: 36, y2: 44, color: _c(kGray));
  _circle(dst, 32, 48, 10, kRed);
  _rect(dst, 30, 28, 34, 48, kRed);
}

void _drawGauge(img.Image dst) {
  for (var t = 200; t <= 340; t += 2) {
    final rad = t * math.pi / 180;
    final x = 32 + (20 * math.cos(rad)).round();
    final y = 40 + (20 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  for (var i = 0; i < 16; i++) {
    _circle(dst, 32 + i, 40 - i, 2, kOrange);
  }
  _circle(dst, 32, 40, 4, kInk);
}

void _drawNurse(img.Image dst) {
  _circle(dst, 32, 16, 9, kTeal);
  _circle(dst, 32, 40, 15, kTeal);
  _rect(dst, 17, 40, 47, 54, kTeal);
  _rect(dst, 28, 10, 36, 22, kWhite);
  _rect(dst, 24, 14, 40, 18, kRed);
}

void _drawCourier(img.Image dst) {
  _circle(dst, 28, 16, 8, kOrange);
  _circle(dst, 28, 38, 13, kOrange);
  _rect(dst, 15, 38, 41, 52, kOrange);
  _rect(dst, 40, 30, 54, 44, kBlue);
  _rect(dst, 44, 26, 50, 30, kBlueDark);
}

void _drawStack(img.Image dst) {
  for (var i = 0; i < 3; i++) {
    final y = 14 + i * 14;
    _rect(dst, 14 + i * 2, y, 50 - i * 2, y + 10, i == 2 ? kBlue : kBlueLight);
  }
}

void _drawBranch(img.Image dst) {
  _rect(dst, 18, 12, 22, 52, kGray);
  _circle(dst, 20, 16, 5, kGreen);
  _circle(dst, 20, 48, 5, kGreen);
  for (var i = 0; i < 18; i++) {
    _circle(dst, 20 + i, 28 + (i ~/ 3), 2, kOrange);
  }
  _circle(dst, 44, 40, 5, kOrange);
}

void _drawLayers(img.Image dst) {
  for (var i = 0; i < 3; i++) {
    final y = 14 + i * 14;
    final inset = i * 3;
    _rect(dst, 12 + inset, y, 52 - inset, y + 10,
        i == 0 ? kTeal : (i == 1 ? kBlue : kOrange));
  }
}

void _drawBinder(img.Image dst) {
  _rect(dst, 16, 10, 50, 54, kBlue);
  _rect(dst, 12, 16, 20, 48, kBlueDark);
  for (final y in [22, 32, 42]) {
    _circle(dst, 16, y, 2, kGrayLight);
  }
}

void _drawFolderOpen(img.Image dst) {
  _rect(dst, 10, 20, 30, 28, kOrangeLight);
  _rect(dst, 10, 28, 54, 40, kOrange);
  for (var y = 36; y <= 52; y++) {
    final t = (y - 36) / 16;
    final shift = (t * 8).round();
    _rect(dst, 10 + shift, y, 54 + shift, y + 1, kOrangeLight);
  }
}

void _drawHourglass(img.Image dst) {
  _rect(dst, 18, 10, 46, 16, kInk);
  _rect(dst, 18, 48, 46, 54, kInk);
  for (var y = 16; y <= 32; y++) {
    final t = (y - 16) / 16;
    final half = (14 - t * 12).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrange);
  }
  for (var y = 32; y <= 48; y++) {
    final t = (y - 32) / 16;
    final half = (2 + t * 12).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrangeLight);
  }
}

void _drawPin(img.Image dst) {
  _circle(dst, 32, 20, 10, kRed);
  _circle(dst, 32, 20, 4, kWhite);
  for (var y = 28; y <= 52; y++) {
    final t = (y - 28) / 24;
    final half = (6 - t * 5).round().clamp(1, 6);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
}

void _drawInfinity(img.Image dst) {
  for (var t = 0; t < 360; t += 3) {
    final rad = t * math.pi / 180;
    final x = 32 + (18 * math.cos(rad)).round();
    final y = 32 + (10 * math.sin(2 * rad)).round();
    _circle(dst, x, y, 2, kBlue);
  }
}

void _drawProxy(img.Image dst) {
  _rect(dst, 8, 24, 24, 40, kBlue);
  _rect(dst, 40, 24, 56, 40, kTeal);
  _rect(dst, 24, 28, 40, 36, kGray);
  _circle(dst, 32, 18, 6, kOrange);
  _rect(dst, 30, 18, 34, 28, kOrange);
}

void _drawMesh(img.Image dst) {
  final nodes = [
    [16, 16],
    [48, 16],
    [16, 48],
    [48, 48],
    [32, 32],
  ];
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      final a = nodes[i], b = nodes[j];
      for (var t = 0; t <= 12; t++) {
        final x = a[0] + ((b[0] - a[0]) * t / 12).round();
        final y = a[1] + ((b[1] - a[1]) * t / 12).round();
        _circle(dst, x, y, 1, kGray);
      }
    }
  }
  for (final n in nodes) {
    _circle(dst, n[0], n[1], 5, kBlue);
  }
}

void _drawPercent(img.Image dst) {
  _circle(dst, 20, 20, 7, kBlue);
  _circle(dst, 44, 44, 7, kBlue);
  for (var i = 0; i < 28; i++) {
    _circle(dst, 18 + i, 46 - i, 2, kInk);
  }
}

void _drawGift(img.Image dst) {
  _rect(dst, 14, 28, 50, 54, kRed);
  _rect(dst, 12, 20, 52, 30, kRed);
  _rect(dst, 30, 20, 34, 54, 0xFFF5C518);
  _rect(dst, 12, 32, 52, 36, 0xFFF5C518);
  _circle(dst, 26, 18, 5, 0xFFF5C518);
  _circle(dst, 38, 18, 5, 0xFFF5C518);
}

void _drawBalance(img.Image dst) {
  _rect(dst, 30, 12, 34, 48, kInk);
  _rect(dst, 14, 20, 50, 24, kInk);
  _circle(dst, 18, 36, 8, kOrange);
  _circle(dst, 46, 36, 8, kOrange);
  _rect(dst, 24, 48, 40, 54, kGray);
}

void _drawCctv(img.Image dst) {
  _rect(dst, 12, 22, 40, 40, kGray);
  _circle(dst, 40, 31, 10, kInk);
  _circle(dst, 42, 31, 5, kBlue);
  _rect(dst, 18, 40, 24, 52, kGray);
  _rect(dst, 12, 50, 30, 54, kInk);
}

void _drawAnonymize(img.Image dst) {
  _circle(dst, 32, 18, 10, kGray);
  _circle(dst, 32, 42, 16, kGray);
  _rect(dst, 16, 42, 48, 56, kGray);
  _rect(dst, 18, 16, 46, 28, kInk);
  _circle(dst, 24, 22, 2, kWhite);
  _circle(dst, 40, 22, 2, kWhite);
}

void _drawAmbulance(img.Image dst) {
  _rect(dst, 10, 24, 50, 44, kWhite);
  img.drawRect(dst, x1: 10, y1: 24, x2: 50, y2: 44, color: _c(kGray));
  _rect(dst, 36, 16, 50, 24, kWhite);
  img.drawRect(dst, x1: 36, y1: 16, x2: 50, y2: 24, color: _c(kGray));
  _rect(dst, 26, 28, 34, 40, kRed);
  _rect(dst, 22, 32, 38, 36, kRed);
  _circle(dst, 20, 48, 6, kInk);
  _circle(dst, 42, 48, 6, kInk);
}

void _drawScooter(img.Image dst) {
  _circle(dst, 16, 48, 7, kInk);
  _circle(dst, 48, 48, 7, kInk);
  _rect(dst, 16, 40, 48, 44, kBlue);
  _rect(dst, 44, 20, 48, 40, kBlueDark);
  _rect(dst, 36, 18, 50, 22, kGray);
}

void _drawPodcast(img.Image dst) {
  _circle(dst, 32, 24, 10, kOrange);
  _rect(dst, 28, 24, 36, 40, kOrange);
  for (final r in [14, 20]) {
    for (var t = 30; t <= 150; t += 4) {
      final rad = t * math.pi / 180;
      final x = 32 + (r * math.cos(rad)).round();
      final y = 28 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 1, kOrangeLight);
    }
  }
  _rect(dst, 30, 40, 34, 50, kInk);
  _rect(dst, 24, 50, 40, 54, kInk);
}

void _drawClapper(img.Image dst) {
  _rect(dst, 10, 24, 54, 52, kInk);
  for (var i = 0; i < 5; i++) {
    _rect(dst, 12 + i * 9, 24, 16 + i * 9, 36, kWhite);
  }
  for (var i = 0; i < 20; i++) {
    _rect(dst, 10 + i, 12 + (i ~/ 2), 14 + i, 24 + (i ~/ 2), kGray);
  }
}

void _drawLadder(img.Image dst) {
  _rect(dst, 18, 10, 24, 54, kOrange);
  _rect(dst, 40, 10, 46, 54, kOrange);
  for (final y in [18, 28, 38, 48]) {
    _rect(dst, 18, y, 46, y + 4, kOrangeLight);
  }
}

void _drawSaw(img.Image dst) {
  _rect(dst, 10, 28, 40, 36, kGray);
  for (var i = 0; i < 8; i++) {
    final x = 12 + i * 4;
    _rect(dst, x, 22, x + 2, 28, kGrayLight);
  }
  _rect(dst, 40, 24, 54, 40, kOrange);
}

void _drawBank(img.Image dst) {
  for (var y = 10; y <= 22; y++) {
    final t = (y - 10) / 12;
    final half = (8 + t * 18).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlueDark);
  }
  for (final x in [16, 28, 40]) {
    _rect(dst, x, 22, x + 8, 48, kGrayLight);
  }
  _rect(dst, 12, 48, 52, 54, kBlue);
}

void _drawGym(img.Image dst) {
  _circle(dst, 14, 32, 8, kInk);
  _circle(dst, 50, 32, 8, kInk);
  _rect(dst, 14, 28, 50, 36, kGray);
  _circle(dst, 22, 32, 6, kGrayLight);
  _circle(dst, 42, 32, 6, kGrayLight);
}

void _drawSms(img.Image dst) {
  _rect(dst, 10, 14, 54, 42, kGreen);
  for (var i = 0; i < 10; i++) {
    _rect(dst, 20 + i, 42 + i, 24 + i, 44 + i, kGreen);
  }
  for (final y in [22, 30]) {
    _rect(dst, 18, y, 46, y + 3, kWhite);
  }
}

void _drawAtSign(img.Image dst) {
  img.drawCircle(dst, x: 32, y: 32, radius: 18, color: _c(kBlue));
  img.drawCircle(dst, x: 32, y: 32, radius: 14, color: _c(kBlue));
  _circle(dst, 32, 32, 6, kBlue);
  _circle(dst, 32, 32, 3, 0x00000000);
  for (var y = 29; y <= 35; y++) {
    for (var x = 29; x <= 35; x++) {
      final dx = x - 32, dy = y - 32;
      if (dx * dx + dy * dy <= 9) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 38, 28, 42, 44, kBlue);
}

void _drawWind(img.Image dst) {
  for (final y in [18, 32, 46]) {
    for (var x = 12; x <= 50; x++) {
      final wave = (math.sin((x + y) / 6) * 2).round();
      _circle(dst, x, y + wave, 2, kTeal);
    }
  }
}

void _drawFlame(img.Image dst) {
  for (var y = 12; y <= 48; y++) {
    final t = (y - 12) / 36;
    final half = ((1 - (t - 0.3).abs()) * 14).round().clamp(2, 14);
    _rect(dst, 32 - half, y, 32 + half, y + 1, y < 28 ? kOrange : kRed);
  }
  _circle(dst, 32, 44, 10, kOrangeLight);
}

void _drawBatteryCharging(img.Image dst) {
  _rect(dst, 12, 20, 48, 44, kGray);
  _rect(dst, 48, 26, 54, 38, kGrayLight);
  _rect(dst, 16, 24, 32, 40, kGreen);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 30 + i, 36 - i, 2, 0xFFF5C518);
  }
  _rect(dst, 34, 28, 40, 36, 0xFFF5C518);
}

void _drawSensor(img.Image dst) {
  _rect(dst, 18, 28, 46, 52, kGray);
  _circle(dst, 32, 22, 12, kTeal);
  _circle(dst, 32, 22, 6, kTealLight);
  _circle(dst, 32, 22, 2, kWhite);
  for (final x in [24, 32, 40]) {
    _rect(dst, x - 1, 36, x + 1, 46, kInk);
  }
}

void _drawAntenna(img.Image dst) {
  _rect(dst, 30, 28, 34, 54, kGray);
  _rect(dst, 20, 50, 44, 56, kInk);
  for (var i = 0; i < 18; i++) {
    _circle(dst, 32 - i, 28 - i, 2, kOrange);
    _circle(dst, 32 + i, 28 - i, 2, kOrange);
  }
  _circle(dst, 32, 28, 4, kOrange);
}

void _drawSmartwatch(img.Image dst) {
  _rect(dst, 24, 8, 40, 18, kGray);
  _rect(dst, 24, 46, 40, 56, kGray);
  _rect(dst, 20, 18, 44, 46, kInk);
  _rect(dst, 24, 22, 40, 42, kBlue);
  _circle(dst, 32, 32, 3, kWhite);
}

void _drawDrone(img.Image dst) {
  _rect(dst, 24, 28, 40, 40, kInk);
  for (final p in [
    [14, 20],
    [50, 20],
    [14, 48],
    [50, 48]
  ]) {
    for (var t = 0; t <= 12; t++) {
      final x = 32 + ((p[0] - 32) * t / 12).round();
      final y = 34 + ((p[1] - 34) * t / 12).round();
      _circle(dst, x, y, 2, kBlue);
    }
    _circle(dst, p[0], p[1], 8, kGray);
    _circle(dst, p[0], p[1], 3, kGrayLight);
  }
  _circle(dst, 32, 34, 4, kOrange);
}

void _drawNfc(img.Image dst) {
  _rect(dst, 18, 12, 46, 52, kBlue);
  for (final r in [6, 11, 16]) {
    for (var t = -60; t <= 60; t += 4) {
      final rad = t * math.pi / 180;
      final x = 32 + (r * math.cos(rad)).round();
      final y = 32 + (r * math.sin(rad)).round();
      _circle(dst, x, y, 1, kWhite);
    }
  }
  _circle(dst, 32, 32, 3, kWhite);
}

void _drawPcb(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kGreen);
  for (var y = 16; y <= 48; y += 8) {
    _rect(dst, 14, y, 50, y + 2, kTealDark);
  }
  for (final p in [
    [20, 20],
    [32, 28],
    [44, 20],
    [20, 40],
    [44, 40]
  ]) {
    _circle(dst, p[0], p[1], 4, kGray);
    _circle(dst, p[0], p[1], 2, 0xFFF5C518);
  }
}

void _drawTeacher(img.Image dst) {
  _circle(dst, 32, 16, 9, kBlue);
  _circle(dst, 32, 40, 15, kBlue);
  _rect(dst, 17, 40, 47, 54, kBlue);
  _rect(dst, 20, 28, 44, 34, kOrange);
}

void _drawAthlete(img.Image dst) {
  _circle(dst, 32, 14, 8, kOrange);
  _rect(dst, 26, 22, 38, 40, kTeal);
  _rect(dst, 18, 40, 28, 54, kInk);
  _rect(dst, 36, 40, 46, 54, kInk);
  _rect(dst, 22, 28, 26, 36, kOrange);
  _rect(dst, 38, 28, 42, 36, kOrange);
}

void _drawBrowser(img.Image dst) {
  _rect(dst, 10, 12, 54, 52, kGray);
  _rect(dst, 10, 12, 54, 22, kInk);
  _circle(dst, 16, 17, 2, kRed);
  _circle(dst, 24, 17, 2, 0xFFF5C518);
  _circle(dst, 32, 17, 2, kGreen);
  _rect(dst, 14, 28, 50, 46, kBlueLight);
}

void _drawCache(img.Image dst) {
  _rect(dst, 14, 14, 50, 50, kBlue);
  _rect(dst, 20, 20, 44, 44, kBlueDark);
  _rect(dst, 26, 26, 38, 38, kBlueLight);
  _circle(dst, 32, 32, 4, kWhite);
}

void _drawQueue(img.Image dst) {
  for (var i = 0; i < 4; i++) {
    _rect(dst, 10 + i * 12, 22, 18 + i * 12, 42, i == 3 ? kOrange : kBlue);
  }
  _rect(dst, 48, 28, 56, 36, kOrangeLight);
}

void _drawDesk(img.Image dst) {
  _rect(dst, 10, 28, 54, 36, kOrange);
  _rect(dst, 14, 36, 20, 52, kInk);
  _rect(dst, 44, 36, 50, 52, kInk);
  _rect(dst, 24, 16, 40, 28, kBlue);
  _rect(dst, 28, 12, 36, 16, kGray);
}

void _drawWhiteboard(img.Image dst) {
  _rect(dst, 10, 12, 54, 48, kWhite);
  img.drawRect(dst, x1: 10, y1: 12, x2: 54, y2: 48, color: _c(kGray));
  _rect(dst, 16, 20, 40, 24, kBlue);
  _rect(dst, 16, 30, 34, 34, kTeal);
  _rect(dst, 24, 48, 40, 54, kInk);
}

void _drawTrash(img.Image dst) {
  _rect(dst, 18, 20, 46, 54, kGray);
  _rect(dst, 14, 16, 50, 22, kInk);
  _rect(dst, 26, 10, 38, 16, kInk);
  for (final x in [24, 32, 40]) {
    _rect(dst, x, 28, x + 2, 46, kGrayLight);
  }
}

void _drawEdit(img.Image dst) {
  _rect(dst, 12, 40, 36, 52, kBlueLight);
  for (var i = 0; i < 24; i++) {
    _circle(dst, 28 + i, 36 - i, 3, kOrange);
  }
  _rect(dst, 48, 10, 54, 18, kInk);
}

void _drawCopy(img.Image dst) {
  _rect(dst, 18, 18, 50, 52, kBlue);
  _rect(dst, 14, 12, 46, 46, kBlueLight);
  img.drawRect(dst, x1: 14, y1: 12, x2: 46, y2: 46, color: _c(kBlueDark));
  for (final y in [20, 28, 36]) {
    _rect(dst, 20, y, 40, y + 2, kWhite);
  }
}

void _drawCdn(img.Image dst) {
  _circle(dst, 32, 32, 10, kOrange);
  for (final p in [
    [16, 16],
    [48, 16],
    [16, 48],
    [48, 48]
  ]) {
    _circle(dst, p[0], p[1], 7, kBlue);
    for (var t = 0; t <= 10; t++) {
      final x = 32 + ((p[0] - 32) * t / 10).round();
      final y = 32 + ((p[1] - 32) * t / 10).round();
      _circle(dst, x, y, 1, kGray);
    }
  }
}

void _drawWebhook(img.Image dst) {
  _circle(dst, 20, 32, 8, kTeal);
  _circle(dst, 44, 20, 8, kBlue);
  _circle(dst, 44, 44, 8, kOrange);
  for (var i = 0; i < 16; i++) {
    _circle(dst, 20 + i, 32 - i, 1, kGray);
    _circle(dst, 20 + i, 32 + i, 1, kGray);
  }
  _rect(dst, 16, 28, 24, 36, kWhite);
}

void _drawStorefront(img.Image dst) {
  _rect(dst, 12, 28, 52, 54, kBlue);
  for (var x = 12; x < 52; x += 10) {
    _rect(dst, x, 18, x + 10, 28, (x ~/ 10).isEven ? kOrange : kOrangeLight);
  }
  _rect(dst, 26, 36, 38, 54, kInk);
  _rect(dst, 16, 36, 24, 44, kBlueLight);
}

void _drawAuction(img.Image dst) {
  for (var i = 0; i < 22; i++) {
    _circle(dst, 18 + i, 20 + i, 3, kInk);
  }
  _rect(dst, 34, 36, 52, 44, kOrange);
  _circle(dst, 16, 16, 8, kGray);
}

void _drawAlarm(img.Image dst) {
  _circle(dst, 32, 34, 16, kRed);
  _circle(dst, 32, 34, 10, kWhite);
  _rect(dst, 30, 22, 34, 34, kRed);
  _rect(dst, 30, 34, 40, 38, kRed);
  _circle(dst, 18, 18, 4, kInk);
  _circle(dst, 46, 18, 4, kInk);
}

void _drawScan(img.Image dst) {
  _rect(dst, 14, 14, 50, 50, kGrayLight);
  img.drawRect(dst, x1: 14, y1: 14, x2: 50, y2: 50, color: _c(kGray));
  _rect(dst, 14, 30, 50, 34, kGreen);
  _rect(dst, 14, 14, 24, 18, kBlue);
  _rect(dst, 14, 14, 18, 24, kBlue);
  _rect(dst, 40, 46, 50, 50, kBlue);
  _rect(dst, 46, 40, 50, 50, kBlue);
}

void _drawMetro(img.Image dst) {
  _rect(dst, 12, 18, 52, 44, kBlue);
  _rect(dst, 16, 22, 48, 34, kBlueLight);
  for (final x in [20, 32, 44]) {
    _rect(dst, x - 2, 36, x + 2, 40, kWhite);
  }
  _circle(dst, 20, 48, 5, kInk);
  _circle(dst, 44, 48, 5, kInk);
  _rect(dst, 28, 10, 36, 18, kRed);
}

void _drawHelicopter(img.Image dst) {
  _rect(dst, 10, 20, 54, 24, kGray);
  _rect(dst, 30, 24, 34, 30, kInk);
  _rect(dst, 20, 30, 48, 44, kBlue);
  _rect(dst, 48, 34, 56, 38, kBlueDark);
  _circle(dst, 26, 48, 5, kInk);
  _circle(dst, 42, 48, 5, kInk);
}

void _drawGamepad(img.Image dst) {
  _rect(dst, 10, 22, 54, 46, kInk);
  _circle(dst, 22, 34, 6, kGray);
  _rect(dst, 20, 28, 24, 40, kGrayLight);
  _rect(dst, 16, 32, 28, 36, kGrayLight);
  _circle(dst, 42, 30, 3, kRed);
  _circle(dst, 48, 36, 3, kBlue);
  _circle(dst, 38, 38, 3, kGreen);
}

void _drawEbook(img.Image dst) {
  _rect(dst, 16, 10, 48, 54, kBlue);
  _rect(dst, 20, 14, 44, 48, kWhite);
  for (final y in [20, 28, 36]) {
    _rect(dst, 24, y, 40, y + 2, kGrayLight);
  }
  _rect(dst, 28, 48, 36, 52, kInk);
}

void _drawPliers(img.Image dst) {
  for (var i = 0; i < 22; i++) {
    _circle(dst, 20 + i, 18 + i, 3, kGray);
    _circle(dst, 20 + i, 46 - i, 3, kGray);
  }
  _rect(dst, 38, 28, 54, 36, kOrange);
}

void _drawTape(img.Image dst) {
  _circle(dst, 32, 32, 20, kOrange);
  _circle(dst, 32, 32, 10, kOrangeLight);
  _circle(dst, 32, 32, 5, 0x00000000);
  for (var y = 27; y <= 37; y++) {
    for (var x = 27; x <= 37; x++) {
      final dx = x - 32, dy = y - 32;
      if (dx * dx + dy * dy <= 25) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
}

void _drawHotel(img.Image dst) {
  _rect(dst, 14, 16, 50, 54, kBlue);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      _rect(dst, 20 + col * 10, 22 + row * 10, 26 + col * 10, 28 + row * 10,
          kBlueLight);
    }
  }
  _rect(dst, 28, 46, 36, 54, kInk);
  _rect(dst, 24, 10, 40, 16, kOrange);
}

void _drawMuseum(img.Image dst) {
  for (var y = 10; y <= 22; y++) {
    final t = (y - 10) / 12;
    final half = (10 + t * 16).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kInk);
  }
  for (final x in [16, 28, 40]) {
    _rect(dst, x, 22, x + 8, 48, kGrayLight);
  }
  _rect(dst, 12, 48, 52, 54, kOrange);
}

void _drawNewsletter(img.Image dst) {
  _rect(dst, 12, 10, 52, 54, kWhite);
  img.drawRect(dst, x1: 12, y1: 10, x2: 52, y2: 54, color: _c(kBlueDark));
  _rect(dst, 12, 10, 52, 22, kBlue);
  for (final y in [28, 36, 44]) {
    _rect(dst, 18, y, 46, y + 3, kGrayLight);
  }
}

void _drawVoicemail(img.Image dst) {
  _circle(dst, 20, 32, 10, kBlue);
  _circle(dst, 44, 32, 10, kBlue);
  _rect(dst, 20, 28, 44, 36, kBlue);
  _circle(dst, 20, 32, 4, kWhite);
  _circle(dst, 44, 32, 4, kWhite);
}

void _drawHydro(img.Image dst) {
  _rect(dst, 12, 36, 52, 52, kBlue);
  for (var x = 12; x <= 48; x += 8) {
    final h = 8 + ((x * 3) % 16);
    _rect(dst, x, 36 - h, x + 5, 36, kBlueLight);
  }
  _circle(dst, 32, 20, 8, kTeal);
}

void _drawAtom(img.Image dst) {
  _circle(dst, 32, 32, 5, kOrange);
  for (final rot in [0.0, 1.047, 2.094]) {
    for (var t = 0; t < 360; t += 6) {
      final rad = t * math.pi / 180;
      final x = 32 + (20 * math.cos(rad) * math.cos(rot) - 8 * math.sin(rad) * math.sin(rot)).round();
      final y = 32 + (20 * math.cos(rad) * math.sin(rot) + 8 * math.sin(rad) * math.cos(rot)).round();
      _circle(dst, x, y, 1, kBlue);
    }
  }
}

void _drawThermostat(img.Image dst) {
  _circle(dst, 32, 32, 20, kGray);
  _circle(dst, 32, 32, 14, kGrayLight);
  for (var i = 0; i < 14; i++) {
    _circle(dst, 32 + i, 32 - i ~/ 2, 2, kOrange);
  }
  _circle(dst, 32, 32, 4, kInk);
}

void _drawDoorbell(img.Image dst) {
  _rect(dst, 22, 10, 42, 54, kInk);
  _circle(dst, 32, 28, 10, kGrayLight);
  _circle(dst, 32, 28, 5, kOrange);
  _rect(dst, 28, 42, 36, 48, kGray);
}

void _drawCameraIp(img.Image dst) {
  _rect(dst, 12, 24, 40, 46, kGray);
  _circle(dst, 40, 35, 12, kInk);
  _circle(dst, 42, 35, 7, kBlue);
  _circle(dst, 44, 35, 3, kBlueLight);
  _rect(dst, 16, 46, 22, 54, kInk);
}

void _drawTable(img.Image dst) {
  _rect(dst, 10, 14, 54, 50, kWhite);
  img.drawRect(dst, x1: 10, y1: 14, x2: 54, y2: 50, color: _c(kGray));
  _rect(dst, 10, 14, 54, 24, kBlue);
  for (final x in [24, 38]) {
    _rect(dst, x, 14, x + 2, 50, kGrayLight);
  }
  for (final y in [32, 40]) {
    _rect(dst, 10, y, 54, y + 2, kGrayLight);
  }
}

void _drawSpreadsheet(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kWhite);
  img.drawRect(dst, x1: 10, y1: 10, x2: 54, y2: 54, color: _c(kGreen));
  _rect(dst, 10, 10, 54, 20, kGreen);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 3; c++) {
      _rect(dst, 14 + c * 14, 24 + r * 8, 24 + c * 14, 28 + r * 8, kGrayLight);
    }
  }
}

void _drawCube(img.Image dst) {
  // Isometric-ish cube with parallelograms approximated by rects + diagonals.
  _rect(dst, 16, 24, 40, 48, kBlue);
  for (var i = 0; i < 12; i++) {
    _rect(dst, 40 + i, 24 - i, 52 + i, 48 - i, kBlueDark);
    _rect(dst, 16 + i, 12 + i, 40 + i, 24 + i, kBlueLight);
  }
}

void _drawPipeline(img.Image dst) {
  for (var i = 0; i < 3; i++) {
    final x = 10 + i * 18;
    _rect(dst, x, 24, x + 12, 40, i == 2 ? kOrange : kTeal);
    if (i < 2) {
      for (var t = 0; t < 8; t++) {
        _circle(dst, x + 12 + t, 32, 2, kGray);
      }
    }
  }
}

void _drawJson(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kInk);
  for (final y in [18, 28, 38, 46]) {
    _rect(dst, 20, y, 34, y + 3, kTealLight);
    _rect(dst, 38, y, 44, y + 3, kOrange);
  }
}

void _drawBinary(img.Image dst) {
  final bits = '10110010';
  for (var i = 0; i < bits.length; i++) {
    final row = i ~/ 4, col = i % 4;
    final on = bits[i] == '1';
    _rect(dst, 12 + col * 12, 14 + row * 20, 20 + col * 12, 28 + row * 20,
        on ? kBlue : kGrayLight);
  }
}

void _drawDoctor(img.Image dst) {
  _circle(dst, 32, 16, 9, kTeal);
  _circle(dst, 32, 40, 15, kTeal);
  _rect(dst, 17, 40, 47, 54, kTeal);
  _rect(dst, 28, 28, 36, 48, kWhite);
  _rect(dst, 22, 34, 42, 38, kWhite);
}

void _drawChef(img.Image dst) {
  _circle(dst, 32, 22, 10, kOrange);
  _circle(dst, 32, 44, 14, kOrange);
  _rect(dst, 18, 44, 46, 56, kOrange);
  _rect(dst, 20, 8, 44, 18, kWhite);
  _circle(dst, 22, 12, 6, kWhite);
  _circle(dst, 42, 12, 6, kWhite);
  _circle(dst, 32, 8, 6, kWhite);
}

void _drawFloppy(img.Image dst) {
  _rect(dst, 14, 12, 50, 52, kBlue);
  _rect(dst, 20, 12, 44, 24, kGrayLight);
  _rect(dst, 18, 30, 46, 48, kBlueDark);
  _rect(dst, 24, 34, 40, 44, kWhite);
}

void _drawCd(img.Image dst) {
  _circle(dst, 32, 32, 22, kGray);
  _circle(dst, 32, 32, 16, kBlueLight);
  _circle(dst, 32, 32, 6, kGrayLight);
  _circle(dst, 32, 32, 3, 0x00000000);
  for (var y = 29; y <= 35; y++) {
    for (var x = 29; x <= 35; x++) {
      final dx = x - 32, dy = y - 32;
      if (dx * dx + dy * dy <= 9) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
}

void _drawFax(img.Image dst) {
  _rect(dst, 12, 20, 52, 48, kGray);
  _rect(dst, 16, 12, 48, 22, kWhite);
  img.drawRect(dst, x1: 16, y1: 12, x2: 48, y2: 22, color: _c(kBlueDark));
  for (var x = 18; x <= 42; x += 6) {
    _rect(dst, x, 28, x + 3, 36, kInk);
  }
  _rect(dst, 18, 40, 46, 44, kGreen);
}

void _drawLinkOff(img.Image dst) {
  for (var i = 0; i < 14; i++) {
    _circle(dst, 16 + i, 24 + i, 3, kBlue);
    _circle(dst, 34 + i, 24 + i, 3, kBlue);
  }
  _circle(dst, 18, 22, 8, kBlue);
  _circle(dst, 46, 42, 8, kBlue);
  for (var i = 0; i < 28; i++) {
    _circle(dst, 18 + i, 46 - i, 2, kRed);
  }
}

void _drawVisibility(img.Image dst) {
  for (var y = 20; y <= 44; y++) {
    final t = (y - 20) / 24;
    final half = ((1 - (2 * t - 1).abs()) * 22).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _circle(dst, 32, 32, 8, kWhite);
  _circle(dst, 32, 32, 4, kInk);
}

void _drawLan(img.Image dst) {
  _rect(dst, 26, 12, 38, 24, kBlue);
  for (final x in [14, 32, 50]) {
    _rect(dst, x - 6, 40, x + 6, 52, kTeal);
    for (var t = 0; t <= 12; t++) {
      final px = 32 + ((x - 32) * t / 12).round();
      final py = 24 + (16 * t / 12).round();
      _circle(dst, px, py, 1, kGray);
    }
  }
}

void _drawShoppingBag(img.Image dst) {
  _rect(dst, 16, 24, 48, 54, kOrange);
  for (var t = 0; t <= 180; t += 4) {
    final rad = t * math.pi / 180;
    final x = 32 + (12 * math.cos(rad)).round();
    final y = 24 - (10 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kInk);
  }
  _rect(dst, 28, 32, 36, 40, kOrangeLight);
}

void _drawReceipt(img.Image dst) {
  _rect(dst, 18, 8, 46, 56, kWhite);
  img.drawRect(dst, x1: 18, y1: 8, x2: 46, y2: 56, color: _c(kGray));
  for (final y in [16, 24, 32, 40]) {
    _rect(dst, 22, y, 42, y + 2, kGrayLight);
  }
  for (var x = 18; x < 46; x += 4) {
    _rect(dst, x, 52, x + 2, 56, 0x00000000);
    for (var y = 52; y < 56; y++) {
      for (var xx = x; xx < x + 2 && xx < 46; xx++) {
        dst.setPixelRgba(xx, y, 0, 0, 0, 0);
      }
    }
  }
}

void _drawFireExtinguisher(img.Image dst) {
  _rect(dst, 24, 18, 40, 52, kRed);
  _circle(dst, 32, 18, 8, kRed);
  _rect(dst, 28, 8, 36, 14, kInk);
  _rect(dst, 36, 12, 48, 18, kGray);
  _rect(dst, 22, 28, 26, 40, kInk);
}

void _drawPolice(img.Image dst) {
  _circle(dst, 32, 18, 9, kBlueDark);
  _circle(dst, 32, 42, 15, kBlueDark);
  _rect(dst, 17, 42, 47, 56, kBlueDark);
  _rect(dst, 22, 10, 42, 16, kInk);
  _circle(dst, 32, 12, 3, 0xFFF5C518);
}

void _drawTaxi(img.Image dst) {
  _rect(dst, 10, 26, 54, 44, 0xFFF5C518);
  _rect(dst, 18, 16, 46, 26, 0xFFF5C518);
  _rect(dst, 22, 18, 42, 24, kBlueLight);
  _circle(dst, 20, 48, 6, kInk);
  _circle(dst, 44, 48, 6, kInk);
  _rect(dst, 28, 12, 36, 16, kInk);
}

void _drawFerry(img.Image dst) {
  _rect(dst, 12, 28, 52, 40, kBlue);
  _rect(dst, 20, 16, 44, 28, kBlueLight);
  _rect(dst, 28, 10, 36, 16, kInk);
  for (var y = 40; y <= 52; y++) {
    final t = (y - 40) / 12;
    final half = (20 + t * 8).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlueDark);
  }
}

void _drawVinyl(img.Image dst) {
  _circle(dst, 32, 32, 22, kInk);
  _circle(dst, 32, 32, 14, kGray);
  _circle(dst, 32, 32, 6, kOrange);
  _circle(dst, 32, 32, 2, kInk);
}

void _drawProjector(img.Image dst) {
  _rect(dst, 12, 24, 52, 44, kGray);
  _circle(dst, 24, 34, 8, kInk);
  _circle(dst, 24, 34, 4, kBlue);
  _rect(dst, 36, 28, 48, 40, kGrayLight);
  _rect(dst, 20, 44, 28, 52, kInk);
  _rect(dst, 36, 44, 44, 52, kInk);
}

void _drawDrill(img.Image dst) {
  _rect(dst, 12, 24, 40, 40, kOrange);
  _rect(dst, 40, 28, 54, 36, kGray);
  _rect(dst, 16, 16, 28, 24, kInk);
  _circle(dst, 22, 32, 4, kGrayLight);
}

void _drawLevel(img.Image dst) {
  _rect(dst, 10, 26, 54, 38, kOrange);
  _rect(dst, 26, 28, 38, 36, kBlueLight);
  _circle(dst, 32, 32, 3, kGreen);
}

void _drawChurch(img.Image dst) {
  _rect(dst, 18, 28, 46, 54, kGrayLight);
  for (var y = 12; y <= 28; y++) {
    final t = (y - 12) / 16;
    final half = (t * 14).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 30, 8, 34, 16, kInk);
  _rect(dst, 26, 10, 38, 14, kInk);
  _rect(dst, 28, 42, 36, 54, kInk);
}

void _drawStadium(img.Image dst) {
  for (var y = 16; y <= 48; y++) {
    final t = (y - 16) / 32;
    final half = (10 + math.sin(t * math.pi) * 18).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, y < 28 ? kBlue : kGreen);
  }
  _rect(dst, 20, 36, 44, 44, kGrayLight);
}

void _drawPager(img.Image dst) {
  _rect(dst, 12, 20, 52, 44, kInk);
  _rect(dst, 16, 24, 48, 36, kGreen);
  for (final x in [20, 28, 36, 44]) {
    _rect(dst, x - 2, 38, x + 2, 40, kGrayLight);
  }
}

void _drawSolarPanel(img.Image dst) {
  _rect(dst, 12, 18, 52, 48, kBlueDark);
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 4; c++) {
      _rect(dst, 16 + c * 9, 22 + r * 8, 22 + c * 9, 28 + r * 8, kBlue);
    }
  }
  _rect(dst, 28, 48, 36, 56, kGray);
}

void _drawSmartLock(img.Image dst) {
  _rect(dst, 20, 28, 44, 54, kBlue);
  for (var t = 0; t <= 180; t += 4) {
    final rad = t * math.pi / 180;
    final x = 32 + (10 * math.cos(rad)).round();
    final y = 14 + (12 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kBlueDark);
  }
  _circle(dst, 32, 40, 5, kGrayLight);
  _rect(dst, 30, 40, 34, 48, kGrayLight);
}

void _drawSpeakerSmart(img.Image dst) {
  _rect(dst, 20, 12, 44, 52, kInk);
  _circle(dst, 32, 28, 10, kGray);
  _circle(dst, 32, 28, 5, kBlue);
  _rect(dst, 26, 42, 38, 46, kGrayLight);
}

void _drawDataset(img.Image dst) {
  for (var i = 0; i < 3; i++) {
    final y = 14 + i * 14;
    _rect(dst, 14, y, 50, y + 10, i == 0 ? kTeal : (i == 1 ? kBlue : kOrange));
    for (final x in [20, 32, 44]) {
      _circle(dst, x, y + 5, 2, kWhite);
    }
  }
}

void _drawSchema(img.Image dst) {
  _rect(dst, 12, 12, 30, 28, kBlue);
  _rect(dst, 34, 12, 52, 28, kTeal);
  _rect(dst, 22, 36, 42, 52, kOrange);
  for (var t = 0; t <= 10; t++) {
    _circle(dst, 21 + t, 28 + t, 1, kGray);
    _circle(dst, 43 - t, 28 + t, 1, kGray);
  }
}

void _drawLog(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kInk);
  for (var i = 0; i < 6; i++) {
    _rect(dst, 18, 16 + i * 6, 30 + (i % 3) * 6, 18 + i * 6, kTealLight);
  }
}

void _drawMetric(img.Image dst) {
  _rect(dst, 12, 12, 16, 52, kGray);
  _rect(dst, 12, 48, 52, 52, kGray);
  final hs = [16, 28, 20, 36];
  for (var i = 0; i < hs.length; i++) {
    final x = 20 + i * 10;
    _rect(dst, x, 48 - hs[i], x + 6, 48, i == 3 ? kOrange : kBlue);
  }
}

void _drawReport(img.Image dst) {
  _rect(dst, 14, 8, 50, 56, kWhite);
  img.drawRect(dst, x1: 14, y1: 8, x2: 50, y2: 56, color: _c(kBlueDark));
  _rect(dst, 14, 8, 50, 18, kBlue);
  for (final y in [24, 32, 40]) {
    _rect(dst, 20, y, 44, y + 2, kGrayLight);
  }
  _rect(dst, 20, 46, 28, 52, kTeal);
  _rect(dst, 32, 42, 40, 52, kOrange);
}

void _drawEtl(img.Image dst) {
  _rect(dst, 8, 22, 22, 42, kBlue);
  _rect(dst, 26, 18, 38, 46, kOrange);
  _rect(dst, 42, 22, 56, 42, kTeal);
  for (var t = 0; t < 6; t++) {
    _circle(dst, 22 + t, 32, 2, kGray);
    _circle(dst, 38 + t, 32, 2, kGray);
  }
}

void _drawPill(img.Image dst) {
  _rect(dst, 16, 24, 48, 40, kRed);
  _circle(dst, 16, 32, 8, kRed);
  _circle(dst, 48, 32, 8, kWhite);
  _rect(dst, 32, 24, 48, 40, kWhite);
  img.drawRect(dst, x1: 32, y1: 24, x2: 48, y2: 40, color: _c(kGray));
}

void _drawSyringe(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    _circle(dst, 18 + i, 46 - i, 3, kTeal);
  }
  _rect(dst, 40, 12, 52, 24, kGrayLight);
  _rect(dst, 14, 48, 22, 56, kInk);
}

void _drawDna(img.Image dst) {
  for (var y = 10; y <= 54; y++) {
    final t = y / 8;
    final x1 = 32 + (12 * math.sin(t)).round();
    final x2 = 32 - (12 * math.sin(t)).round();
    _circle(dst, x1, y, 2, kBlue);
    _circle(dst, x2, y, 2, kTeal);
    if (y % 6 == 0) {
      for (var x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
        _circle(dst, x, y, 1, kGray);
      }
    }
  }
}

void _drawStethoscope(img.Image dst) {
  _circle(dst, 20, 16, 6, kGray);
  _circle(dst, 44, 16, 6, kGray);
  for (var t = 0; t <= 180; t += 3) {
    final rad = t * math.pi / 180;
    final x = 32 + (14 * math.cos(rad)).round();
    final y = 28 + (14 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kInk);
  }
  _circle(dst, 32, 48, 8, kBlue);
  _rect(dst, 18, 16, 22, 28, kInk);
  _rect(dst, 42, 16, 46, 28, kInk);
}

void _drawBandage(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    _rect(dst, 14 + i, 20 + i ~/ 2, 22 + i, 36 + i ~/ 2, kOrangeLight);
  }
  _rect(dst, 26, 26, 38, 38, kOrange);
  for (final p in [
    [30, 30],
    [34, 30],
    [30, 34],
    [34, 34]
  ]) {
    _circle(dst, p[0], p[1], 1, kInk);
  }
}

void _drawWheelchair(img.Image dst) {
  _circle(dst, 36, 44, 12, kBlue);
  _circle(dst, 36, 44, 7, 0x00000000);
  for (var y = 37; y <= 51; y++) {
    for (var x = 29; x <= 43; x++) {
      final dx = x - 36, dy = y - 44;
      if (dx * dx + dy * dy <= 49) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 20, 20, 36, 24, kInk);
  _rect(dst, 20, 20, 24, 40, kInk);
  _circle(dst, 18, 44, 5, kGray);
  _circle(dst, 28, 14, 5, kOrange);
}

void _drawFarmer(img.Image dst) {
  _circle(dst, 32, 18, 9, kOrange);
  _circle(dst, 32, 42, 15, kOrange);
  _rect(dst, 17, 42, 47, 56, kOrange);
  _rect(dst, 18, 12, 46, 18, kTealDark);
  _rect(dst, 14, 16, 50, 20, kTealDark);
}

void _drawSoldier(img.Image dst) {
  _circle(dst, 32, 18, 9, kGreen);
  _circle(dst, 32, 42, 15, kGreen);
  _rect(dst, 17, 42, 47, 56, kGreen);
  _rect(dst, 22, 8, 42, 16, kTealDark);
  _rect(dst, 28, 4, 36, 8, kTealDark);
}

void _drawAi(img.Image dst) {
  _rect(dst, 14, 14, 50, 50, kBlueDark);
  _circle(dst, 32, 32, 12, kBlue);
  _circle(dst, 26, 28, 3, kWhite);
  _circle(dst, 38, 28, 3, kWhite);
  _rect(dst, 26, 38, 38, 42, kTealLight);
  for (final p in [
    [18, 18],
    [46, 18],
    [18, 46],
    [46, 46]
  ]) {
    _circle(dst, p[0], p[1], 3, kOrange);
  }
}

void _drawDisk(img.Image dst) {
  _circle(dst, 32, 32, 22, kGray);
  _circle(dst, 32, 32, 14, kInk);
  _circle(dst, 32, 32, 5, kGrayLight);
  _rect(dst, 30, 10, 34, 22, kOrange);
}

void _drawStapler(img.Image dst) {
  _rect(dst, 12, 28, 52, 40, kInk);
  _rect(dst, 16, 16, 48, 28, kGray);
  _rect(dst, 40, 20, 50, 36, kOrange);
}

void _drawHighlighter(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    _circle(dst, 18 + i, 46 - i, 4, 0xFFF5C518);
  }
  _rect(dst, 40, 12, 52, 24, kOrange);
}

void _drawClipboardCheck(img.Image dst) {
  _rect(dst, 16, 14, 48, 54, kWhite);
  img.drawRect(dst, x1: 16, y1: 14, x2: 48, y2: 54, color: _c(kGray));
  _rect(dst, 24, 8, 40, 18, kOrange);
  for (var i = 0; i < 12; i++) {
    _circle(dst, 24 + i, 30 + i ~/ 2, 2, kGreen);
    if (i < 8) _circle(dst, 36 + i, 36 - i, 2, kGreen);
  }
}

void _drawSparkles(img.Image dst) {
  void star(int cx, int cy, int s, int c) {
    _rect(dst, cx - 1, cy - s, cx + 1, cy + s, c);
    _rect(dst, cx - s, cy - 1, cx + s, cy + 1, c);
  }

  star(22, 22, 8, 0xFFF5C518);
  star(44, 28, 6, kOrange);
  star(30, 46, 7, 0xFFF5C518);
}

void _drawBridge(img.Image dst) {
  _rect(dst, 8, 40, 56, 46, kGray);
  for (var t = 0; t <= 180; t += 3) {
    final rad = t * math.pi / 180;
    final x = 32 + (22 * math.cos(rad)).round();
    final y = 40 - (14 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kBlue);
  }
  _rect(dst, 14, 20, 18, 40, kInk);
  _rect(dst, 46, 20, 50, 40, kInk);
}

void _drawTunnel(img.Image dst) {
  for (var t = 0; t <= 180; t += 2) {
    final rad = t * math.pi / 180;
    final x = 32 + (20 * math.cos(rad)).round();
    final y = 40 - (20 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  _rect(dst, 12, 40, 52, 52, kInk);
  _rect(dst, 24, 28, 40, 40, kOrange);
}

void _drawDeal(img.Image dst) {
  _rect(dst, 10, 24, 30, 48, kBlue);
  _rect(dst, 34, 24, 54, 48, kTeal);
  for (var i = 0; i < 10; i++) {
    _circle(dst, 26 + i, 28 + i, 2, kOrange);
    _circle(dst, 38 - i, 28 + i, 2, kOrange);
  }
}

void _drawInsurance(img.Image dst) {
  _rect(dst, 14, 18, 50, 52, kWhite);
  img.drawRect(dst, x1: 14, y1: 18, x2: 50, y2: 52, color: _c(kBlueDark));
  for (var y = 10; y <= 22; y++) {
    final t = (y - 10) / 12;
    final half = (8 + t * 10).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kBlue);
  }
  _rect(dst, 28, 28, 36, 44, kGreen);
  _rect(dst, 24, 34, 40, 38, kGreen);
}

void _drawHelmet(img.Image dst) {
  for (var y = 14; y <= 36; y++) {
    final t = (y - 14) / 22;
    final half = (8 + t * 14).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrange);
  }
  _rect(dst, 14, 36, 50, 44, kInk);
  _rect(dst, 28, 20, 36, 36, 0xFFF5C518);
}

void _drawSiren(img.Image dst) {
  _rect(dst, 20, 36, 44, 52, kInk);
  for (var y = 12; y <= 36; y++) {
    final t = (y - 12) / 24;
    final half = (4 + t * 12).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
  _circle(dst, 32, 20, 4, kOrangeLight);
}

void _drawSubmarine(img.Image dst) {
  _rect(dst, 12, 28, 52, 44, kBlueDark);
  _circle(dst, 12, 36, 8, kBlueDark);
  _circle(dst, 52, 36, 8, kBlueDark);
  _rect(dst, 28, 18, 40, 28, kBlue);
  _rect(dst, 32, 12, 36, 18, kInk);
  _circle(dst, 22, 36, 3, kBlueLight);
}

void _drawForklift(img.Image dst) {
  _rect(dst, 20, 24, 48, 44, kOrange);
  _rect(dst, 12, 20, 20, 48, kInk);
  _rect(dst, 8, 20, 28, 24, kGray);
  _circle(dst, 28, 48, 6, kInk);
  _circle(dst, 44, 48, 6, kInk);
  _rect(dst, 36, 16, 46, 24, kBlueLight);
}

void _drawTicket(img.Image dst) {
  _rect(dst, 10, 20, 54, 44, kOrange);
  for (var y = 26; y <= 38; y++) {
    for (var x = 4; x <= 16; x++) {
      final dx = x - 10, dy = y - 32;
      if (dx * dx + dy * dy <= 36) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
    for (var x = 48; x < 64; x++) {
      final dx = x - 54, dy = y - 32;
      if (dx * dx + dy * dy <= 36) dst.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  _rect(dst, 24, 26, 40, 30, kWhite);
  _rect(dst, 24, 34, 36, 38, kWhite);
}

void _drawNewspaper(img.Image dst) {
  _rect(dst, 10, 12, 54, 52, kWhite);
  img.drawRect(dst, x1: 10, y1: 12, x2: 54, y2: 52, color: _c(kGray));
  _rect(dst, 14, 16, 50, 24, kInk);
  for (final y in [30, 36, 42]) {
    _rect(dst, 14, y, 30, y + 2, kGrayLight);
    _rect(dst, 34, y, 50, y + 2, kGrayLight);
  }
}

void _drawAxe(img.Image dst) {
  for (var i = 0; i < 28; i++) {
    _circle(dst, 22 + i, 18 + i, 3, kOrange);
  }
  _rect(dst, 14, 12, 36, 28, kGray);
  _rect(dst, 28, 8, 40, 20, kGrayLight);
}

void _drawShovel(img.Image dst) {
  _rect(dst, 28, 8, 36, 40, kOrange);
  for (var y = 40; y <= 54; y++) {
    final t = (y - 40) / 14;
    final half = (4 + t * 10).round();
    _rect(dst, 32 - half, y, 32 + half, y + 1, kGray);
  }
}

void _drawBeach(img.Image dst) {
  _rect(dst, 0, 36, 63, 54, 0xFFF5C518);
  _rect(dst, 0, 20, 63, 36, kBlueLight);
  _circle(dst, 48, 14, 8, 0xFFF5C518);
  _rect(dst, 16, 28, 20, 44, kOrange);
  for (var y = 20; y <= 28; y++) {
    final t = (y - 20) / 8;
    final half = (2 + t * 10).round();
    _rect(dst, 18 - half, y, 18 + half, y + 1, kRed);
  }
}

void _drawCastle(img.Image dst) {
  _rect(dst, 12, 28, 52, 54, kGray);
  for (final x in [12, 28, 44]) {
    _rect(dst, x, 14, x + 10, 28, kGray);
    _rect(dst, x, 10, x + 4, 14, kGrayLight);
    _rect(dst, x + 6, 10, x + 10, 14, kGrayLight);
  }
  _rect(dst, 28, 40, 36, 54, kInk);
}

void _drawWalkie(img.Image dst) {
  _rect(dst, 22, 18, 42, 52, kInk);
  _rect(dst, 26, 22, 38, 34, kGreen);
  _rect(dst, 30, 8, 34, 18, kGray);
  _rect(dst, 26, 38, 38, 42, kGrayLight);
  _rect(dst, 26, 46, 38, 48, kGrayLight);
}

void _drawOil(img.Image dst) {
  _rect(dst, 20, 20, 44, 52, kInk);
  _rect(dst, 24, 12, 40, 20, kGray);
  _circle(dst, 32, 36, 8, kOrange);
  for (var y = 8; y <= 14; y++) {
    _rect(dst, 30, y, 34, y + 1, kGrayLight);
  }
}

void _drawNuclear(img.Image dst) {
  _circle(dst, 32, 32, 22, 0xFFF5C518);
  _circle(dst, 32, 32, 6, kInk);
  for (var i = 0; i < 3; i++) {
    final a0 = i * 120;
    for (var t = a0 + 20; t <= a0 + 100; t += 3) {
      final rad = t * math.pi / 180;
      for (var r = 10; r <= 18; r++) {
        final x = 32 + (r * math.cos(rad)).round();
        final y = 32 + (r * math.sin(rad)).round();
        _circle(dst, x, y, 1, kInk);
      }
    }
  }
}

void _drawFridge(img.Image dst) {
  _rect(dst, 18, 8, 46, 56, kGrayLight);
  img.drawRect(dst, x1: 18, y1: 8, x2: 46, y2: 56, color: _c(kGray));
  _rect(dst, 18, 28, 46, 30, kGray);
  _rect(dst, 40, 14, 44, 24, kBlue);
  _rect(dst, 40, 36, 44, 48, kBlue);
}

void _drawIndex(img.Image dst) {
  _rect(dst, 14, 12, 50, 52, kBlue);
  for (var i = 0; i < 5; i++) {
    _rect(dst, 18, 16 + i * 7, 34, 20 + i * 7, kWhite);
    _rect(dst, 38, 16 + i * 7, 46, 20 + i * 7, kOrange);
  }
}

void _drawSnapshot(img.Image dst) {
  _rect(dst, 12, 16, 52, 48, kBlue);
  _circle(dst, 32, 32, 10, kBlueLight);
  _circle(dst, 32, 32, 5, kWhite);
  _rect(dst, 40, 18, 48, 24, kOrange);
}

void _drawMirror(img.Image dst) {
  _rect(dst, 14, 14, 34, 50, kTeal);
  _rect(dst, 30, 14, 50, 50, kTealLight);
  for (var i = 0; i < 20; i++) {
    _circle(dst, 24 + i, 20 + i, 1, kWhite);
  }
}

void _drawVaccine(img.Image dst) {
  _rect(dst, 26, 8, 38, 36, kTeal);
  _circle(dst, 32, 36, 8, kTeal);
  _rect(dst, 28, 40, 36, 54, kGray);
  _rect(dst, 22, 12, 42, 16, kTealDark);
}

void _drawMicroscope(img.Image dst) {
  _rect(dst, 16, 48, 48, 56, kGray);
  _rect(dst, 28, 20, 36, 48, kInk);
  _circle(dst, 32, 16, 10, kBlue);
  _rect(dst, 36, 24, 50, 32, kGrayLight);
  _circle(dst, 32, 40, 4, kOrange);
}

void _drawTree(img.Image dst) {
  _rect(dst, 28, 36, 36, 56, kOrange);
  _circle(dst, 32, 24, 16, kGreen);
  _circle(dst, 22, 30, 10, kGreen);
  _circle(dst, 42, 30, 10, kGreen);
}

void _drawMountain(img.Image dst) {
  for (var y = 16; y <= 52; y++) {
    final t = (y - 16) / 36;
    final half = (t * 24).round();
    _rect(dst, 24 - half ~/ 2, y, 24 + half ~/ 2, y + 1, kGray);
    _rect(dst, 40 - half, y, 40 + half, y + 1, kBlueDark);
  }
  _rect(dst, 0, 48, 63, 56, kGreen);
}

void _drawFlower(img.Image dst) {
  for (final p in [
    [32, 18],
    [20, 28],
    [44, 28],
    [24, 42],
    [40, 42]
  ]) {
    _circle(dst, p[0], p[1], 8, kRed);
  }
  _circle(dst, 32, 32, 7, 0xFFF5C518);
  _rect(dst, 30, 40, 34, 56, kGreen);
}

void _drawFish(img.Image dst) {
  _circle(dst, 28, 32, 14, kBlue);
  for (var i = 0; i < 12; i++) {
    final half = 8 - i ~/ 2;
    _rect(dst, 40 + i, 32 - half, 41 + i, 32 + half, kBlueDark);
  }
  _circle(dst, 22, 28, 2, kWhite);
  _rect(dst, 24, 18, 30, 22, kBlueLight);
}

void _drawBird(img.Image dst) {
  _circle(dst, 32, 30, 12, kOrange);
  _circle(dst, 40, 24, 8, kOrange);
  _circle(dst, 44, 22, 2, kInk);
  for (var i = 0; i < 14; i++) {
    _rect(dst, 18 + i, 28 - i ~/ 2, 19 + i, 34 + i ~/ 2, kOrangeLight);
  }
  _rect(dst, 46, 24, 54, 28, 0xFFF5C518);
}

void _drawRain(img.Image dst) {
  _circle(dst, 22, 20, 10, kGray);
  _circle(dst, 36, 16, 12, kGray);
  _circle(dst, 48, 22, 9, kGray);
  _rect(dst, 14, 20, 54, 30, kGray);
  for (final x in [18, 28, 38, 48]) {
    _rect(dst, x, 34, x + 2, 50, kBlue);
    _rect(dst, x + 4, 40, x + 6, 54, kBlueLight);
  }
}
