/// Read-only MS-CFB (OLE2 Compound File) parser for Visio `.vsd` packages.
///
/// Implements enough of [MS-CFB] to open a file, walk the directory, and read
/// named streams (notably `VisioDocument`). Not a general-purpose writer.
library;

import 'dart:typed_data';

import '../../../core/exceptions.dart';

/// CFB magic: `D0 CF 11 E0 A1 B1 1A E1`.
const List<int> kCfbMagic = <int>[
  0xD0,
  0xCF,
  0x11,
  0xE0,
  0xA1,
  0xB1,
  0x1A,
  0xE1,
];

bool looksLikeCfb(Uint8List bytes) {
  if (bytes.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != kCfbMagic[i]) return false;
  }
  return true;
}

/// One directory entry in a compound file.
class CfbEntry {
  const CfbEntry({
    required this.name,
    required this.type,
    required this.startSector,
    required this.streamSize,
    required this.childId,
    required this.leftSibling,
    required this.rightSibling,
    required this.creationTime,
    required this.modifiedTime,
  });

  final String name;

  /// 0 unknown, 1 storage, 2 stream, 5 root storage.
  final int type;
  final int startSector;
  final int streamSize;
  final int childId;
  final int leftSibling;
  final int rightSibling;

  /// Raw CFB FILETIME values (100 ns ticks since 1601-01-01 UTC).
  final int creationTime;
  final int modifiedTime;

  bool get isStream => type == 2;
  bool get isStorage => type == 1 || type == 5;
}

/// Opened compound file with stream access by absolute path (`VisioDocument`).
class CompoundFile {
  CompoundFile._({
    required this.bytes,
    required this.sectorSize,
    required this.miniSectorSize,
    required this.miniStreamCutoff,
    required List<int> fat,
    required List<int> miniFat,
    required List<CfbEntry> entries,
    required Uint8List miniStream,
  })  : _fat = fat,
        _miniFat = miniFat,
        _entries = entries,
        _miniStream = miniStream;

  final Uint8List bytes;
  final int sectorSize;
  final int miniSectorSize;
  final int miniStreamCutoff;
  final List<int> _fat;
  final List<int> _miniFat;
  final List<CfbEntry> _entries;
  final Uint8List _miniStream;

  static const int _endOfChain = 0xFFFFFFFE;
  static const int _freeSect = 0xFFFFFFFF;
  static const int _fatSect = 0xFFFFFFFD;
  static const int _difatSect = 0xFFFFFFFC;

  /// Parse [bytes] as a compound file. Throws [VsdxFormatException] on failure.
  static CompoundFile open(Uint8List bytes) {
    if (!looksLikeCfb(bytes)) {
      throw const VsdxFormatException('Not an OLE2 compound file');
    }
    if (bytes.length < 0x200) {
      throw const VsdxFormatException('Compound file truncated');
    }
    final bd = ByteData.sublistView(bytes);
    final sectorShift = bd.getUint16(0x1E, Endian.little);
    final miniSectorShift = bd.getUint16(0x20, Endian.little);
    final sectorSize = 1 << sectorShift;
    final miniSectorSize = 1 << miniSectorShift;
    final numFatSectors = bd.getUint32(0x2C, Endian.little);
    final firstDirSector = bd.getUint32(0x30, Endian.little);
    final miniStreamCutoff = bd.getUint32(0x38, Endian.little);
    final firstMiniFatSector = bd.getUint32(0x3C, Endian.little);
    final numMiniFatSectors = bd.getUint32(0x40, Endian.little);
    final firstDifatSector = bd.getUint32(0x44, Endian.little);
    final numDifatSectors = bd.getUint32(0x48, Endian.little);

    // Build DIFAT (first 109 entries in header, then DIFAT sectors).
    final difat = <int>[];
    for (var i = 0; i < 109; i++) {
      final v = bd.getUint32(0x4C + i * 4, Endian.little);
      if (v != _freeSect) difat.add(v);
    }
    var difatSect = firstDifatSector;
    for (var n = 0; n < numDifatSectors && difatSect < _difatSect; n++) {
      final off = _sectorOffset(difatSect, sectorSize);
      if (off + sectorSize > bytes.length) break;
      final sbd = ByteData.sublistView(bytes, off, off + sectorSize);
      final entriesPerSector = (sectorSize ~/ 4) - 1;
      for (var i = 0; i < entriesPerSector; i++) {
        final v = sbd.getUint32(i * 4, Endian.little);
        if (v != _freeSect) difat.add(v);
      }
      difatSect = sbd.getUint32(entriesPerSector * 4, Endian.little);
    }
    if (difat.length < numFatSectors) {
      // Tolerate short DIFAT when NumFatSectors is padded.
    }

    // Build FAT.
    final fat = <int>[];
    final fatSectors =
        difat.take(numFatSectors == 0 ? difat.length : numFatSectors);
    for (final fs in fatSectors) {
      final off = _sectorOffset(fs, sectorSize);
      if (off + sectorSize > bytes.length) {
        throw const VsdxFormatException('FAT sector out of range');
      }
      final sbd = ByteData.sublistView(bytes, off, off + sectorSize);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(sbd.getUint32(i * 4, Endian.little));
      }
    }

    // MiniFAT.
    final miniFat = <int>[];
    var miniFatSect = firstMiniFatSector;
    for (var n = 0; n < numMiniFatSectors && miniFatSect < _endOfChain; n++) {
      final off = _sectorOffset(miniFatSect, sectorSize);
      if (off + sectorSize > bytes.length) break;
      final sbd = ByteData.sublistView(bytes, off, off + sectorSize);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        miniFat.add(sbd.getUint32(i * 4, Endian.little));
      }
      if (miniFatSect >= fat.length) break;
      miniFatSect = fat[miniFatSect];
    }

    // Directory entries — chain from FirstDirSectorLocation.
    final dirBytes = _readChain(
      bytes: bytes,
      fat: fat,
      startSector: firstDirSector,
      sectorSize: sectorSize,
      // Directory length unknown; read until end-of-chain.
      maxBytes: null,
    );
    final entries = <CfbEntry>[];
    for (var i = 0; i + 128 <= dirBytes.length; i += 128) {
      entries.add(_parseEntry(dirBytes, i));
    }
    if (entries.isEmpty) {
      throw const VsdxFormatException('Empty CFB directory');
    }

    // Mini-stream lives in the root storage's stream data.
    final root = entries.first;
    final miniStream = root.streamSize > 0
        ? _readChain(
            bytes: bytes,
            fat: fat,
            startSector: root.startSector,
            sectorSize: sectorSize,
            maxBytes: root.streamSize,
          )
        : Uint8List(0);

    return CompoundFile._(
      bytes: bytes,
      sectorSize: sectorSize,
      miniSectorSize: miniSectorSize,
      miniStreamCutoff: miniStreamCutoff,
      fat: fat,
      miniFat: miniFat,
      entries: entries,
      miniStream: miniStream,
    );
  }

  /// Read a stream by its directory name (root-level only for Visio).
  Uint8List? readStream(String name) {
    final entry = _findByName(name);
    if (entry == null || !entry.isStream) return null;
    return _readStreamData(entry);
  }

  /// True when a root-level stream/storage named [name] exists.
  bool hasEntry(String name) => _findByName(name) != null;

  Iterable<String> get entryNames => _entries.map((e) => e.name);

  /// Root-storage modified timestamp. Visio exposes this as both creation and
  /// modification time, matching libvisio's `VSDMetaData::parseTimes`.
  DateTime? get rootModifiedDateTime => _fileTimeToDateTime(
        _entries.isEmpty ? 0 : _entries.first.modifiedTime,
      );

  CfbEntry? _findByName(String name) {
    final lower = name.toLowerCase();
    for (final e in _entries) {
      if (e.name.toLowerCase() == lower) return e;
    }
    return null;
  }

  Uint8List _readStreamData(CfbEntry entry) {
    if (entry.streamSize == 0) return Uint8List(0);
    if (entry.streamSize < miniStreamCutoff) {
      return _readMiniChain(entry.startSector, entry.streamSize);
    }
    return _readChain(
      bytes: bytes,
      fat: _fat,
      startSector: entry.startSector,
      sectorSize: sectorSize,
      maxBytes: entry.streamSize,
    );
  }

  Uint8List _readMiniChain(int start, int size) {
    if (size <= 0 || _miniStream.isEmpty) return Uint8List(0);
    final out = BytesBuilder(copy: false);
    var sector = start;
    var remaining = size;
    final seen = <int>{};
    while (sector < _endOfChain && remaining > 0) {
      if (!seen.add(sector)) {
        throw const VsdxFormatException('MiniFAT cycle detected');
      }
      final off = sector * miniSectorSize;
      if (off >= _miniStream.length) break;
      final take = remaining < miniSectorSize ? remaining : miniSectorSize;
      final end = (off + take).clamp(0, _miniStream.length);
      out.add(_miniStream.sublist(off, end));
      remaining -= end - off;
      if (sector >= _miniFat.length) break;
      sector = _miniFat[sector];
    }
    return out.takeBytes();
  }

  static int _sectorOffset(int sector, int sectorSize) =>
      512 + sector * sectorSize;

  static Uint8List _readChain({
    required Uint8List bytes,
    required List<int> fat,
    required int startSector,
    required int sectorSize,
    required int? maxBytes,
  }) {
    final out = BytesBuilder(copy: false);
    var sector = startSector;
    var remaining = maxBytes ?? 0x7fffffff;
    final seen = <int>{};
    while (sector < _endOfChain && remaining > 0) {
      if (sector == _freeSect || sector == _fatSect || sector == _difatSect) {
        break;
      }
      if (!seen.add(sector)) {
        throw const VsdxFormatException('FAT cycle detected');
      }
      final off = _sectorOffset(sector, sectorSize);
      if (off >= bytes.length) break;
      final end = (off + sectorSize).clamp(0, bytes.length);
      var chunk = bytes.sublist(off, end);
      if (chunk.length > remaining) {
        chunk = chunk.sublist(0, remaining);
      }
      out.add(chunk);
      remaining -= chunk.length;
      if (sector >= fat.length) break;
      sector = fat[sector];
    }
    final result = out.takeBytes();
    if (maxBytes != null && result.length > maxBytes) {
      return Uint8List.sublistView(result, 0, maxBytes);
    }
    return result;
  }

  static CfbEntry _parseEntry(Uint8List dir, int offset) {
    final bd = ByteData.sublistView(dir, offset, offset + 128);
    final nameLen = bd.getUint16(0x40, Endian.little);
    final nameBytes =
        nameLen > 2 ? dir.sublist(offset, offset + nameLen - 2) : Uint8List(0);
    final name = nameBytes.isEmpty
        ? ''
        : String.fromCharCodes(
            List<int>.generate(
              nameBytes.length ~/ 2,
              (i) => nameBytes[i * 2] | (nameBytes[i * 2 + 1] << 8),
            ),
          );
    return CfbEntry(
      name: name,
      type: bd.getUint8(0x42),
      leftSibling: bd.getUint32(0x44, Endian.little),
      rightSibling: bd.getUint32(0x48, Endian.little),
      childId: bd.getUint32(0x4C, Endian.little),
      creationTime: bd.getUint64(0x64, Endian.little),
      modifiedTime: bd.getUint64(0x6C, Endian.little),
      startSector: bd.getUint32(0x74, Endian.little),
      streamSize: bd.getUint32(0x78, Endian.little),
    );
  }

  static DateTime? _fileTimeToDateTime(int value) {
    if (value <= 116444736000000000) return null;
    final millis = (value - 116444736000000000) ~/ 10000;
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } on ArgumentError {
      return null;
    }
  }
}
