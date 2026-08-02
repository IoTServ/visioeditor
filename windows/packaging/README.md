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
  identity_name: cloud.iothub.visioeditor
  file_extension: .vsdx, .vsdm, .vstx, .vstm, .vssx, .vssm, .vsd
```

Then `dart run msix:create`. The installer registers the extensions and points
them at the packaged executable — no manual registry edits.

## Option B — Registry (dev / manual / Inno Setup)

`visioeditor-file-association.reg` registers the OPC extensions under
`VisioEditor.Drawing` and legacy `.vsd` under `VisioEditor.Drawing.Binary`
(per-user, `HKCU\Software\Classes`).

1. Edit the file and replace `C:\Path\To\visioeditor.exe` with the real path.
2. Double-click it (or `reg import visioeditor-file-association.reg`).

An installer such as Inno Setup can perform the same writes at install time.

The Windows runner forwards command-line arguments to Dart. The app filters
those arguments against the supported Visio extensions and opens associated
files on startup.
