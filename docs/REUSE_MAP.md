# 恢复映射（Reuse / Recovery Map）

> 本编辑器的引擎与渲染层从**查看器 `visiovsdxviewer`** 的 git 历史恢复而来。
> 源提交：`0fcaf66^`（即 “Make libvisio FFI the default engine and remove the
> pre-pivot Dart stack.” 的父提交），此时仓库仍保有完整的**纯 Dart `.vsdx` 栈**。
> 许可证：查看器主仓为 **MIT**，恢复到本 MIT 仓库合规。

恢复方式（逐文件）：

```bash
SRC=~/git/visiovsdxviewer
git -C "$SRC" show '0fcaf66^:lib/<path>' > packages/vsdx/lib/src/<path>   # 纯 Dart
git -C "$SRC" show '0fcaf66^:lib/render/<f>' > lib/render/<f>             # Flutter 渲染
```

导入后需：修正相对 import；把 `package:visiovsdxviewer/...` 改为包内路径或
`package:vsdx/vsdx.dart`；剔除对 `ir_*`（旧 libvisio IR 管线）的依赖。

---

## 1. 纯 Dart → `packages/vsdx/lib/src/`

### core/（4）
`exceptions.dart` · `result.dart` · `diagnostics.dart` · `version.dart`

### utils/（4）
`units.dart` · `color.dart` · `transform.dart` · `xml_extensions.dart`

### model/（20，编辑器需为其新增 `copyWith`）
`document.dart` · `page.dart` · `shape.dart` · `geometry.dart` · `rich_text.dart` ·
`fill.dart` · `line.dart` · `effects.dart` · `connect.dart` · `layer.dart` ·
`master.dart` · `theme.dart` · `hyperlink.dart` · `image.dart` ·
`custom_property.dart` · `user_property.dart` · `document_settings.dart` ·
`shape_kind.dart`

### parser/（22）
`package_reader.dart`(OPC ZIP) · `relationships.dart` · `document_parser.dart` ·
`document_parser_isolate.dart` · `document_settings_parser.dart` · `pages_parser.dart` ·
`page_parser.dart` · `masters_parser.dart` · `master_parser.dart` · `theme_parser.dart` ·
`style_parser.dart` · `geometry_parser.dart` · `formula.dart` · `rich_text_parser.dart` ·
`connect_parser.dart` · `layer_parser.dart` · `hyperlink_parser.dart` ·
`image_parser.dart` · `custom_properties_parser.dart` · `user_property_parser.dart` ·
`shape_kind_detector.dart` · `cell_helpers.dart`

> `formula.dart` 为只读求值；编辑期公式重算为 v0.1 之后事项。

---

## 2. 依赖 Flutter → `lib/render/`（13）

`vsdx_painter.dart`(CustomPainter) · `path_builder.dart`(Geometry→Path) ·
`arrow_library.dart` · `pattern_fill.dart` · `shape_bounds.dart` ·
`connector_router.dart` · `font_fallback.dart` · `image_cache.dart` ·
`page_picture_cache.dart` · `dash_path.dart`

**跳过**（旧 IR 管线，编辑器不用）：`ir_painter.dart` · `ir_image_cache.dart` ·
`ir_embedded_fonts.dart`

---

## 3. 暂缓恢复（v0.1 之后）

- `export/`：`svg_serializer.dart` · `pdf_exporter.dart` · `png_exporter.dart`
- `io/byte_loader_web.dart`（Web 不做）

---

## 4. 编辑器新增（非恢复）

- `packages/vsdx/lib/src/writer/` —— 写回器（见 [`VSDX_WRITE.md`](./VSDX_WRITE.md)）
- 模型各类的 `copyWith`
- `lib/editor/`、`lib/commands/`、`lib/app/`、`lib/io/`

---

## 5. 改动记录（随恢复更新）

- （待 E1 填写：每个文件的 import 修正 / API 调整）
