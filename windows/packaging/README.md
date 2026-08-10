# Windows packaging

`flutter build windows` produces an unpackaged runner. For Microsoft Store
distribution, package as MSIX. For local/dev installs, use the registry file.

Windows product name: **Flowcharts Editor** (other platforms keep
"Editor for Visio Diagrams").

## Option A — MSIX (Microsoft Store)

Identity and packaging live in `pubspec.yaml` under `msix_config` (must match
Partner Center → Product management → Product identity). Reference copy:
`store/microsoft-store/`.

```bash
# On a Windows machine with Flutter:
dart run msix:create
```

Key fields (see `pubspec.yaml` for the full block):

| Field | Value |
| --- | --- |
| display_name | Flowcharts Editor |
| identity_name | 38916OpenIoTHubCloud.FlowchartsEditor |
| publisher | CN=5F64CEA2-463E-41A3-AE89-6979242A61DF |
| publisher_display_name | OpenIoTHub Cloud |
| store | true |
| file_extension | .vsdx, .vsdm, .vstx, .vstm, .vssx, .vssm, .vsd |

`store: true` produces a Store-uploadable package (Microsoft signs it after
upload). Bump `msix_version` (a.b.c.d) with each Store submission; keep it in
sync with `version:` in `pubspec.yaml` when possible (e.g. `1.0.1+6` →
`1.0.1.6`).

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
