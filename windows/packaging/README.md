# Windows file association

`flutter build windows` produces an unpackaged runner; Windows file
associations live in the **registry** and are set at install/packaging time,
not by the Flutter build. Two supported ways:

## Option A — MSIX (recommended for distribution)

Package with the [`msix`](https://pub.dev/packages/msix) tool and declare the
associations in `pubspec.yaml`:

```yaml
msix_config:
  display_name: Editor for Visio Diagrams
  identity_name: com.example.visioeditor
  file_extension: .vsdx, .vsdm, .vstx, .vstm, .vssx, .vssm
```

Then `dart run msix:create`. The installer registers the extensions and points
them at the packaged executable — no manual registry edits.

## Option B — Registry (dev / manual / Inno Setup)

`visioeditor-file-association.reg` registers the six extensions under a shared
`VisioEditor.Drawing` ProgID (per-user, `HKCU\Software\Classes`).

1. Edit the file and replace `C:\Path\To\visioeditor.exe` with the real path.
2. Double-click it (or `reg import visioeditor-file-association.reg`).

An installer such as Inno Setup can perform the same writes at install time.

## Remaining runtime step

With the association in place Windows launches the app with the drawing path as
`argv[1]` (the runner already reads command-line args in
`windows/runner/utils.cpp`). To actually open it, that path must be forwarded to
Dart (mirroring the macOS `MethodChannel('visioeditor/files')` bridge); until
then the app launches but does not auto-open the passed file.
