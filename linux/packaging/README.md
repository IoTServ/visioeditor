# Linux file association

`flutter build linux` does **not** register file types — that is an install-time
step. These artifacts associate `.vsdx` / `.vsd` (and the
`.vsdm/.vstx/.vstm/.vssx/.vssm` family) with the app so double-clicking a
drawing in a file manager offers / launches *Editor for Visio Diagrams*.

## Files

- `visioeditor.desktop` — the application launcher, declaring the Visio
  `MimeType`s and `Exec=visioeditor %f` (the `%f` passes the opened file path).
- `visioeditor-mime.xml` — a `shared-mime-info` definition mapping the Visio
  file extensions to their MIME types (OPC types sub-class `application/zip`;
  legacy `.vsd` uses `application/vnd.visio`).

## Install (per-user)

```sh
# 1. MIME types
install -Dm644 visioeditor-mime.xml \
  ~/.local/share/mime/packages/visioeditor-mime.xml
update-mime-database ~/.local/share/mime

# 2. Desktop entry (ensure `visioeditor` is on PATH or edit Exec= to an
#    absolute path to the built bundle's binary)
install -Dm644 visioeditor.desktop \
  ~/.local/share/applications/visioeditor.desktop
# App icon (Icon=visioeditor in the desktop entry)
install -Dm644 visioeditor.png \
  ~/.local/share/icons/hicolor/512x512/apps/visioeditor.png
update-desktop-database ~/.local/share/applications
gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null || true
```

For a system-wide install use `/usr/share/mime/packages/` and
`/usr/share/applications/` (run the `update-*` commands without the `~` prefix).

## Remaining runtime step

The association makes the OS launch the app with the file path in `argv`
(`%f`). To actually load it, the Linux runner must forward that path to Dart
(mirroring the macOS `MethodChannel('visioeditor/files')` bridge). Until then
the app launches but does not auto-open the passed file.
