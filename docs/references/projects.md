# 开源参考项目（Open-Source Reference Projects）

> 整理与 VSDX 解析 / 渲染 / 查看相关的开源项目。**许可证标签**指示我们能否参考其代码：
>
> - ✅ **可参考代码**：MIT / BSD / Apache-2.0 / MPL-2.0
> - ⚠️ **谨慎参考**：LGPL（Dart 无动态链接概念，要走 "看文档、重写算法"）
> - ❌ **不读源码**：GPL / AGPL（避免无意识抄袭传染许可证）

---

## 1. VSDX / Visio 解析与渲染

### 1.1 `libvisio-ng` — Python
- **仓库**：<https://pypi.org/project/libvisio-ng/>
- **作者**：Daniel Nylander
- **许可证**：GPL-3.0-or-later ❌
- **覆盖**：完整 `.vsdx` + `.vsd` + `.vstx` + `.vssx`，输出 SVG/PNG/PDF
- **结构亮点**：纯 Python 实现 OLE2 + 主题/渐变/阴影/富文本/嵌入图像
- **我们能学到的（不读源码）**：架构上的分层（vsdx parser / vsd parser / svg renderer）、
  支持矩阵、CLI 设计、Python bindings 思路

### 1.2 `libvisio-rs` — Rust
- **仓库**：<https://crates.io/crates/libvisio-rs>
- **许可证**：GPL-3.0-or-later ❌
- **覆盖**：libvisio-ng 的 Rust 移植，提供 C ABI + PyO3 + CLI `visio2svg`
- **价值**：现代语言移植案例，证明 "纯实现" 路径可行

### 1.3 `libvisio` — C++（LibreOffice）
- **仓库**：<https://gerrit.libreoffice.org/q/project:libvisio>
- **官网**：<https://wiki.documentfoundation.org/Development/libvisio>
- **许可证**：MPL-2.0 + LGPLv2.1+ ⚠️
- **覆盖**：LibreOffice 用的工业标准实现，覆盖 `.vsd` `.vsdx` `.vss` `.vst` `.vssx` `.vstx`
- **价值**：record 类型表、NURBS/曲线离散化思路、文档级别测试套件
- **使用方式**：阅读其设计文档与提交说明，**算法思路重写**

### 1.4 `vsdx` — Python（dave-howard）✅
- **仓库**：<https://github.com/dave-howard/vsdx>
- **PyPI**：<https://pypi.org/project/vsdx/>
- **许可证**：**BSD-3-Clause** ✅
- **覆盖**：偏向 VSDX 文件**操作**（增删改查 shape、jinja 模板）
- **价值**：
  - 干净易读的 OPC 解析逻辑（可大量参考）
  - 完善的单元测试 fixture（部分可借鉴生成方式）
  - 文档站 <https://vsdx.readthedocs.io/> 含教程

### 1.5 `ts-visio` — TypeScript ✅
- **仓库**：<https://github.com/zimmermanw84/ts-visio>
- **许可证**：（需查证，仓库未声明则视作私有）⚠️
- **覆盖**：现代 TS 类型化 VSDX 读取 + 创建，支持 `.vssx` 模具导入
- **价值**：类型设计与 API 风格（`VisioDocument` → `Page` → `Shape`）
  非常适合 Dart 类似 API 设计参考

### 1.6 `Aspose.Diagram for .NET / Java`（商业）
- **官网**：<https://products.aspose.com/diagram/>
- **许可证**：商业 ❌
- **价值**：API 设计参考（公开文档）

### 1.7 `Apache POI` — Java（OPC 部分）✅
- **官网**：<https://poi.apache.org/>
- **许可证**：Apache-2.0 ✅
- **价值**：Open Packaging Conventions 的标杆实现，OPC 读写代码可大胆参考

### 1.8 `Mxgraph / drawio` — JavaScript ✅
- **仓库**：<https://github.com/jgraph/drawio>
- **许可证**：Apache-2.0 ✅
- **价值**：drawio 内置 `.vsdx` 导入实现 `VsdxImport.js`，可读性高。
  对于"形状库映射"思路非常有借鉴价值

### 1.9 Inkscape — SVG / 矢量编辑器
- **仓库**：<https://gitlab.com/inkscape/inkscape.git>
- **官网**：<https://inkscape.org/>
- **许可证**：GPL-2.0-or-later（随附库含 LGPL/MPL；发行版整体 GPL-3.0+）❌
- **本地克隆**：[`third_party/inkscape/`](../../third_party/inkscape/)（见 [`third_party/README.md`](../../third_party/README.md)）
- **记录 commit**：`7fdf74dd1324ae35e4257157bea018e8e16fe9db`（2026-05-23，浅克隆）
- **覆盖**：SVG 导入/导出、路径布尔运算、Bezier/NURBS（`lib2geom`）、文本沿路径、滤镜与渐变
- **价值**（对照本项目的 M3/M7）：
  - `src/svg/` — SVG DOM 与属性映射，可对照 `lib/export/svg_serializer.dart`
  - `src/3rdparty/2geom/` — 曲线求交、路径简化、仿射变换
  - `src/path/`、`src/object/` — 路径编辑与对象树，可对照 `lib/render/path_builder.dart`
- **使用方式**：仅作算法与数据流对照；**不复制** GPL 源码。优先阅读 SPDX 头与公开设计文档，必要时对照本地克隆。

---

## 2. Flutter / Dart 侧的关键参考

### 2.1 PDF 查看器（架构借鉴）

| 项目 | 链接 | 许可证 | 借鉴点 |
|---|---|---|---|
| `pdfrx` | <https://github.com/espresso3389/pdfrx> | MIT ✅ | 多平台 PDF Viewer 架构、Engine ↔ Widget 分层、缩略图实现 |
| `syncfusion_flutter_pdfviewer` | <https://pub.dev/packages/syncfusion_flutter_pdfviewer> | 商业 / 社区双许可 | 高级 UI 交互参考 |

### 2.2 SVG 渲染

| 项目 | 链接 | 借鉴点 |
|---|---|---|
| `flutter_svg` | <https://pub.dev/packages/flutter_svg> | XML → Path 解析模式 |
| `vector_graphics` | <https://pub.dev/packages/vector_graphics> | 二进制 vector 编码 + Flutter 渲染管线 |
| `path_drawing` | <https://pub.dev/packages/path_drawing> | SVG `d` → Flutter `Path` 转换 |

### 2.3 文档查看器（DOCX/PPTX 类）

| 项目 | 链接 | 借鉴点 |
|---|---|---|
| `docx_viewer` (santoshvandari) | <https://github.com/santoshvandari/docx_viewer> | 跨平台文件解析 + Flutter 展示 |
| `docx_file_viewer` (alihassan143) | <https://github.com/alihassan143/docx_viewer> | OOXML 部分解析思路 |

> 目前 pub.dev 上**没有任何 VSDX 原生查看器**，本项目可填补该空白。

---

## 3. ZIP / OPC / XML 通用基础库（Dart）

| 包 | 许可证 | 用途 |
|---|---|---|
| [`archive`](https://pub.dev/packages/archive) | MIT ✅ | ZIP/TAR/GZip，纯 Dart |
| [`xml`](https://pub.dev/packages/xml) | MIT ✅ | XML DOM + SAX |
| [`vector_math`](https://pub.dev/packages/vector_math) | BSD-3 ✅ | 4×4 矩阵 / Vector |
| [`image`](https://pub.dev/packages/image) | MIT ✅ | PNG/JPEG/TIFF/BMP 解码 |
| [`crypto`](https://pub.dev/packages/crypto) | BSD-3 ✅ | OPC 内部 hash（可选） |

---

## 4. 推荐"动手参考"路径

1. **结构理解**：精读 `vsdx` (Python BSD ✅) 源码中 `VisioFile.__init__` → 你将明白 OPC 解包过程
2. **形状继承**：精读 `vsdx` 中 `Shape._inherit_from_master`，可直接对照 Dart 实现
3. **几何转换**：阅读 `drawio/etc/build/VsdxImport.js`（Apache ✅），理解 Arc/EllipticalArc 转 Bezier 的实现
4. **主题映射**：参考 `Apache POI` (`org.apache.poi.xddf.usermodel.text.*`) 的 DrawingML 主题系列代码
5. **API 风格**：模仿 `ts-visio` 的 `VisioDocument` → `Page` → `Shape` 类层级
6. **Flutter 架构**：参考 `pdfrx` (MIT ✅) 把"engine（纯 Dart）"和"Flutter widget"分两层包
7. **SVG / 路径**：对照本地 `third_party/inkscape` 中 `src/svg/` 与 `2geom` 的曲线处理（GPL ❌，重写实现）

---

## 5. 测试样本的合规获取

| 来源 | 合规性 | 备注 |
|---|---|---|
| LibreOffice Draw 导出 | ✅ | 自由创建任意复杂度样本 |
| Microsoft Visio Trial | ⚠️ | 自己绘制即可，**不分发**官方模板 |
| `vsdx` 仓库 test fixtures | ✅（BSD） | 注意保留版权头 |
| `libvisio` 测试集 | ❌ | 部分包含商业模板，避免直接复制 |
| 公开 Wikipedia / Wikimedia 图 | ✅ CC-BY-SA | 注明出处 |

详见 [`fixtures.md`](./fixtures.md)。
