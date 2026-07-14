/// Thin `dart:ffi` binding to the libvisio shim (see `native/libvisio_shim.cpp`).
///
/// libvisio is the reference C++ Visio importer (Document Liberation Project).
/// We use it as an *oracle*: parse each fixture with libvisio and diff the
/// result against our own parser (see `libvisio_diff_test.dart`).
///
/// The binding loads lazily and returns `null` from [tryLoad] when the shim
/// hasn't been built (`native/build.sh`) or libvisio isn't installed, so the
/// differential tests skip cleanly on machines without the oracle.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _ToSvgNative = Pointer<Char> Function(Pointer<Uint8>, UnsignedLong);
typedef _ToSvgDart = Pointer<Char> Function(Pointer<Uint8>, int);
typedef _FreeNative = Void Function(Pointer<Char>);
typedef _FreeDart = void Function(Pointer<Char>);

class LibvisioOracle {
  LibvisioOracle._(this._toSvg, this._free);

  final _ToSvgDart _toSvg;
  final _FreeDart _free;

  /// Sentinel the shim inserts between per-page SVGs.
  static const String _pageSeparator = '\n<!--__VSDX_PAGE__-->\n';

  /// Load the shim, or return `null` if it (or libvisio) is unavailable.
  static LibvisioOracle? tryLoad() {
    final path = _locateDylib();
    if (path == null) return null;
    try {
      final lib = DynamicLibrary.open(path);
      final toSvg =
          lib.lookupFunction<_ToSvgNative, _ToSvgDart>('vsdx_shim_to_svg');
      final free = lib.lookupFunction<_FreeNative, _FreeDart>('vsdx_shim_free');
      return LibvisioOracle._(toSvg, free);
    } catch (_) {
      return null;
    }
  }

  static String? _locateDylib() {
    const names = <String>[
      'native/libvisio_shim.dylib',
      'packages/vsdx/native/libvisio_shim.dylib',
      'native/libvisio_shim.so',
    ];
    for (final n in names) {
      final f = File(n);
      if (f.existsSync()) return f.absolute.path;
    }
    return null;
  }

  /// libvisio's SVG for each page of [bytes], or `null` when it can't parse
  /// the document.
  List<String>? svgPages(Uint8List bytes) {
    final ptr = malloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final res = _toSvg(ptr, bytes.length);
      if (res == nullptr) return null;
      try {
        return res.cast<Utf8>().toDartString().split(_pageSeparator);
      } finally {
        _free(res);
      }
    } finally {
      malloc.free(ptr);
    }
  }
}
