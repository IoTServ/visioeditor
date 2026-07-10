/// Exception hierarchy for the visiovsdxviewer project.
///
/// All layers should throw or wrap into one of these, never raw [Exception].
/// This makes error reporting (and the "copy diagnostics" UI affordance)
/// consistent across the codebase.
library;

/// Common base type so `try { ... } on VsdxException { ... }` catches all
/// project-specific failures.
abstract class VsdxException implements Exception {
  const VsdxException(this.message, {this.cause, this.partName});

  /// Human-readable message (English; the UI layer is responsible for i18n).
  final String message;

  /// Underlying cause if this was wrapped (e.g. a ZIP / XML / IO error).
  final Object? cause;

  /// Path of the OPC part that triggered the failure, when applicable.
  /// For example `visio/pages/page1.xml`. `null` when not tied to a part.
  final String? partName;

  @override
  String toString() {
    final buf = StringBuffer(runtimeType.toString())..write(': ')..write(message);
    if (partName != null) {
      buf
        ..write(' (part: ')
        ..write(partName)
        ..write(')');
    }
    if (cause != null) {
      buf
        ..write('\n  caused by: ')
        ..write(cause);
    }
    return buf.toString();
  }
}

/// Raised by the package layer (`lib/parser/package_reader.dart`).
///
/// Wraps `archive` errors, missing entries, or invalid OPC relationships.
class VsdxPackageException extends VsdxException {
  const VsdxPackageException(super.message, {super.cause, super.partName});
}

/// Raised by any XML → model parser.
///
/// Should ideally include the originating `partName` so users can locate
/// the offending fragment with `unzip my.vsdx`.
class VsdxParseException extends VsdxException {
  const VsdxParseException(super.message, {super.cause, super.partName});
}

/// Raised by the render layer.
///
/// Renderers must **swallow** per-shape failures and degrade to a placeholder
/// box, rather than aborting the whole page (see ARCHITECTURE §5.7).
/// This exception is reserved for unrecoverable page-level errors.
class VsdxRenderException extends VsdxException {
  const VsdxRenderException(super.message, {super.cause, super.partName});
}

/// Raised when the input bytes are clearly not an OPC ZIP package
/// (wrong magic, wrong content-type, encrypted, etc.).
class VsdxFormatException extends VsdxException {
  const VsdxFormatException(super.message, {super.cause, super.partName});
}

/// Raised by the export pipeline (SVG / PNG / PDF).
class VsdxExportException extends VsdxException {
  const VsdxExportException(super.message, {super.cause, super.partName});
}
