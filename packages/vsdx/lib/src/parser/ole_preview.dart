/// Extract a canvas-ready preview from an OLE Compound File (`object/ole`).
///
/// Visio embeds Excel / Equation / … objects as CFB blobs with an
/// `\x02OlePres000` presentation stream. That stream commonly wraps an EMF
/// (CF_ENHMETAFILE) — we return the EMF bytes (or a nested WMF) so the
/// metafile pipeline can rasterise them.
library;

import 'dart:typed_data';

import 'emf_vector_parser.dart';
import 'vsd/cfb/compound_file.dart';
import 'wmf_parser.dart';

/// LibreOffice's default librevenge `GraphicObject` surface ("Blue 2").
///
/// libvisio deliberately submits an empty style for ForeignData; LibreOffice
/// therefore lets its standard graphic style show through every transparent
/// bitmap/metafile pixel. Opaque media is unaffected, while an object without
/// a usable presentation stream remains a solid surface of this colour.
const int libreOfficeForeignObjectBackgroundArgb = 0xff729fcf;

/// Backwards-compatible name retained for callers that used the original OLE
/// workbook-specific constant.
const int libreOfficeOleWorkbookBackgroundArgb =
    libreOfficeForeignObjectBackgroundArgb;

/// Whether [oleBytes] is an embedded Excel workbook package.
bool isOleWorkbook(Uint8List oleBytes) {
  if (!looksLikeCfb(oleBytes)) return false;
  try {
    final cfb = CompoundFile.open(oleBytes);
    return cfb.hasEntry('Workbook') || cfb.hasEntry('Book');
  } catch (_) {
    return false;
  }
}

/// Pull EMF/WMF presentation bytes out of an OLE2 package, or `null`.
Uint8List? extractOlePresentationMetafile(Uint8List oleBytes) {
  if (!looksLikeCfb(oleBytes)) return null;
  try {
    final cfb = CompoundFile.open(oleBytes);
    for (final name in cfb.entryNames) {
      // Stream names are often prefixed with \x01 / \x02 control chars.
      final normalizedName = name.toUpperCase();
      if (!normalizedName.contains('OLEPRES') &&
          !normalizedName.contains('CONTENTS')) {
        continue;
      }
      final data = cfb.readStream(name);
      if (data == null || data.length < 40) continue;
      // A complete WMF can begin at the conventional 40-byte presentation
      // offset even when the clipboard format says CF_ENHMETAFILE. Office's
      // dual-mode wrapper splits the authoritative EMF across WMFC comment
      // records; a loose EMF signature scan returns only its first chunk and
      // loses later chart labels. Keep the WMF so the facade can reassemble it.
      final bd = ByteData.sublistView(data);
      final clipboardFormat = bd.getUint32(4, Endian.little);
      final presentationBody = Uint8List.sublistView(data, 40);
      if (looksLikeWmf(presentationBody)) return presentationBody;
      final emfOff = findEmfOffset(data);
      if (emfOff != null) {
        return data.sublist(emfOff);
      }
      // OLE presentation headers vary between Office and Equation versions.
      // Validate each plausible even-aligned prefix instead of assuming that
      // a WMF payload always begins at byte 0 or byte 40.
      final scanEnd = data.length < 512 ? data.length : 512;
      for (var offset = 0; offset + 18 <= scanEnd; offset += 2) {
        final candidate = Uint8List.sublistView(data, offset);
        if (looksLikeWmf(candidate)) return candidate;
      }
      // Placeable WMF
      if (data.length > 22 &&
          data[0] == 0xd7 &&
          data[1] == 0xcd &&
          data[2] == 0xc6 &&
          data[3] == 0x9a) {
        return data;
      }
      // CF_METAFILEPICT (3): presentation header then WMF without placeable.
      if (data.length > 40) {
        if (clipboardFormat == 3 /* CF_METAFILEPICT */ ||
            clipboardFormat == 14 /* CF_ENHMETAFILE */) {
          // Skip ~40 byte OLE presentation header used by POI samples.
          final body = data.sublist(40);
          final nested = findEmfOffset(body);
          if (nested != null) return body.sublist(nested);
          if (body.length > 18 &&
              (body[0] == 1 || body[0] == 2) &&
              body[1] == 0) {
            return body;
          }
        }
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Pack [metafile] (WMF or EMF) into a one-stream OLE2 package whose
/// `\x02OlePres000` payload [extractOlePresentationMetafile] can read back.
///
/// Used by tests and by the LibreOffice write path that unwraps a Visio
/// `ForeignType=Object` preview into native `MetaFile` / `EnhMetaFile`.
Uint8List wrapOlePresentation(Uint8List metafile) {
  final clip = looksLikeEmf(metafile) ? 14 : 3;
  final stream = Uint8List(40 + metafile.length);
  ByteData.sublistView(stream).setUint32(4, clip, Endian.little);
  stream.setRange(40, stream.length, metafile);
  return _cfbWithSingleStream('\u0002OlePres000', stream);
}

const int _cfbFree = 0xFFFFFFFF;
const int _cfbEndOfChain = 0xFFFFFFFE;
const int _cfbFatSect = 0xFFFFFFFD;
const int _cfbSector = 512;
const int _cfbMiniSector = 64;
const int _cfbMiniCutoff = 4096;

Uint8List _cfbWithSingleStream(String name, Uint8List stream) {
  if (stream.length < _cfbMiniCutoff) {
    return _cfbMiniStreamPackage(name, stream);
  }
  return _cfbRegularStreamPackage(name, stream);
}

Uint8List _cfbRegularStreamPackage(String name, Uint8List stream) {
  final dataSectors = stream.isEmpty ? 0 : (stream.length + _cfbSector - 1) ~/ _cfbSector;
  final fat = List<int>.filled(_cfbSector ~/ 4, _cfbFree);
  fat[0] = _cfbFatSect;
  fat[1] = _cfbEndOfChain;
  for (var i = 0; i < dataSectors; i++) {
    fat[2 + i] = i + 1 < dataSectors ? 3 + i : _cfbEndOfChain;
  }
  final out = BytesBuilder();
  out.add(_cfbHeader(
    firstDirSector: 1,
    fatSectorCount: 1,
    firstMiniFat: _cfbEndOfChain,
    miniFatCount: 0,
    fatSector0: 0,
  ));
  out.add(_cfbFatSector(fat));
  out.add(_cfbDirectorySector(
    streamName: name,
    streamStart: dataSectors == 0 ? _cfbEndOfChain : 2,
    streamSize: stream.length,
    rootStart: _cfbEndOfChain,
    rootSize: 0,
  ));
  if (dataSectors > 0) {
    final padded = Uint8List(dataSectors * _cfbSector)..setAll(0, stream);
    out.add(padded);
  }
  return out.toBytes();
}

Uint8List _cfbMiniStreamPackage(String name, Uint8List stream) {
  final miniCount =
      stream.isEmpty ? 0 : (stream.length + _cfbMiniSector - 1) ~/ _cfbMiniSector;
  final miniBytes = miniCount * _cfbMiniSector;
  final miniSectors =
      miniBytes == 0 ? 0 : (miniBytes + _cfbSector - 1) ~/ _cfbSector;
  final fat = List<int>.filled(_cfbSector ~/ 4, _cfbFree);
  fat[0] = _cfbFatSect;
  fat[1] = _cfbEndOfChain;
  fat[2] = _cfbEndOfChain;
  for (var i = 0; i < miniSectors; i++) {
    fat[3 + i] = i + 1 < miniSectors ? 4 + i : _cfbEndOfChain;
  }
  final miniFat = List<int>.filled(_cfbSector ~/ 4, _cfbFree);
  for (var i = 0; i < miniCount; i++) {
    miniFat[i] = i + 1 < miniCount ? i + 1 : _cfbEndOfChain;
  }
  final out = BytesBuilder();
  out.add(_cfbHeader(
    firstDirSector: 1,
    fatSectorCount: 1,
    firstMiniFat: 2,
    miniFatCount: 1,
    fatSector0: 0,
  ));
  out.add(_cfbFatSector(fat));
  out.add(_cfbDirectorySector(
    streamName: name,
    streamStart: miniCount == 0 ? _cfbEndOfChain : 0,
    streamSize: stream.length,
    rootStart: miniSectors == 0 ? _cfbEndOfChain : 3,
    rootSize: miniBytes,
  ));
  out.add(_cfbFatSector(miniFat));
  if (miniSectors > 0) {
    final padded = Uint8List(miniSectors * _cfbSector)..setAll(0, stream);
    out.add(padded);
  }
  return out.toBytes();
}

Uint8List _cfbHeader({
  required int firstDirSector,
  required int fatSectorCount,
  required int firstMiniFat,
  required int miniFatCount,
  required int fatSector0,
}) {
  final header = Uint8List(_cfbSector);
  final bd = ByteData.sublistView(header);
  for (var i = 0; i < kCfbMagic.length; i++) {
    header[i] = kCfbMagic[i];
  }
  bd.setUint16(0x18, 0x003E, Endian.little);
  bd.setUint16(0x1A, 0x0003, Endian.little);
  bd.setUint16(0x1C, 0xFFFE, Endian.little);
  bd.setUint16(0x1E, 9, Endian.little);
  bd.setUint16(0x20, 6, Endian.little);
  bd.setUint32(0x2C, fatSectorCount, Endian.little);
  bd.setUint32(0x30, firstDirSector, Endian.little);
  bd.setUint32(0x38, _cfbMiniCutoff, Endian.little);
  bd.setUint32(0x3C, firstMiniFat, Endian.little);
  bd.setUint32(0x40, miniFatCount, Endian.little);
  bd.setUint32(0x44, _cfbEndOfChain, Endian.little);
  for (var i = 0; i < 109; i++) {
    bd.setUint32(0x4C + i * 4, i == 0 ? fatSector0 : _cfbFree, Endian.little);
  }
  return header;
}

Uint8List _cfbFatSector(List<int> entries) {
  final sector = Uint8List(_cfbSector);
  final bd = ByteData.sublistView(sector);
  for (var i = 0; i < entries.length && i < _cfbSector ~/ 4; i++) {
    bd.setUint32(i * 4, entries[i], Endian.little);
  }
  return sector;
}

Uint8List _cfbDirectorySector({
  required String streamName,
  required int streamStart,
  required int streamSize,
  required int rootStart,
  required int rootSize,
}) {
  final sector = Uint8List(_cfbSector);
  _writeCfbEntry(
    sector,
    0,
    name: 'Root Entry',
    type: 5,
    child: 1,
    start: rootStart,
    size: rootSize,
  );
  _writeCfbEntry(
    sector,
    128,
    name: streamName,
    type: 2,
    child: _cfbFree,
    start: streamStart,
    size: streamSize,
  );
  return sector;
}

void _writeCfbEntry(
  Uint8List sector,
  int offset, {
  required String name,
  required int type,
  required int child,
  required int start,
  required int size,
}) {
  final units = name.codeUnits;
  for (var i = 0; i < units.length && i < 31; i++) {
    sector[offset + i * 2] = units[i] & 0xff;
    sector[offset + i * 2 + 1] = (units[i] >> 8) & 0xff;
  }
  final bd = ByteData.sublistView(sector, offset, offset + 128);
  bd.setUint16(0x40, (units.length + 1) * 2, Endian.little);
  sector[offset + 0x42] = type;
  sector[offset + 0x43] = 1;
  bd.setUint32(0x44, _cfbFree, Endian.little);
  bd.setUint32(0x48, _cfbFree, Endian.little);
  bd.setUint32(0x4C, child, Endian.little);
  bd.setUint32(0x74, start, Endian.little);
  bd.setUint32(0x78, size, Endian.little);
}
