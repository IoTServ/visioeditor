# 规范与标准文档（Specifications）

> 实现 VSDX 解析必读的官方/权威资料。所有链接均为公开文档，可自由阅读引用，
> 但不可整段拷贝到项目源码或文档中。

---

## 1. Microsoft 官方

### 1.1 MS-VSDX —— **核心规范**

**[MS-VSDX]: Visio Graphics Service Web Drawing File Format**

- Overview：<https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-vsdx/29bd5bbc-db66-46f9-906e-140c5a4e59c8>
- PDF（Open Specifications）：<https://winprotocoldoc.blob.core.windows.net/productionwindowsarchives/MS-VSDX/%5BMS-VSDX%5D.pdf>
- 主要章节速查：

| 章节 | 内容 |
|---|---|
| §1.3 | Overview：包结构总览 |
| §2.1 | Package Structure：OPC 分部与关系 |
| §2.2.1 | Document XML Part |
| §2.2.2 | Pages / Page XML Part |
| §2.2.3 | Masters / Master XML Part |
| §2.2.4 | Themes XML Part |
| §2.2.5 | StyleSheet & Style Inheritance |
| §2.2.6 | Shapes & Sub-Shapes |
| §2.2.7 | Sections / Rows / Cells (ShapeSheet) |
| §2.2.8 | Geometry Section |
| §2.2.9 | Text Block & Character / Paragraph |
| §2.2.10 | Data Connections / Recordsets / Bindings |
| §2.2.11 | Formulas（函数表 + 语法 BNF） |
| §2.3 | Schema Appendix (XSD) |

> ⚠️ MS-VSDX 标注 "unused and MUST be ignored" 的字段仅指**Web Drawing in SharePoint 场景**。
> 我们做 Visio 编辑器级查看器时需要解析这些字段。

### 1.2 Introduction to the Visio file format (.vsdx)

- <https://learn.microsoft.com/en-us/office/client-developer/visio/introduction-to-the-visio-file-formatvsdx>
- 介绍 ZIP/OPC 结构、与 .vsd / .vdx 的对比、各部件作用

### 1.3 Visio File Format Reference

- 旧版 SDK 文档（VBA + XML）：<https://learn.microsoft.com/en-us/office/vba/api/overview/visio>
- ShapeSheet 函数参考（极有用）：<https://learn.microsoft.com/en-us/office/vba/api/visio.shapesheet>

### 1.4 Visio XML Schemas（XSD）

- 全套 XSD（包含 main / theme / pages / masters / drawing）随 MS-VSDX 附录提供
- 也可在 Office 2013/2016 安装目录 `Office16\Visio\Schemas\` 找到 `VisioSchema*.xsd`

---

## 2. OPC / OOXML 通用规范

### 2.1 Open Packaging Conventions

- **ISO/IEC 29500-2:2021** ⟶ <https://www.iso.org/standard/71691.html>
- ECMA-376 Part 2 ⟶ <https://ecma-international.org/publications-and-standards/standards/ecma-376/>
- 介绍 ZIP 包结构、`[Content_Types].xml`、`_rels/` 关系语法

### 2.2 OOXML Part 1 (DrawingML 共享部分)

- ECMA-376 Part 1 ⟶ <https://ecma-international.org/publications-and-standards/standards/ecma-376/>
- VSDX 主题部分直接复用 `<a:clrScheme>` `<a:fontScheme>` `<a:fmtScheme>`

### 2.3 EMF / WMF（嵌入图像格式）

- [MS-EMF]：<https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/>
- [MS-EMFPLUS]：<https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emfplus/>
- [MS-WMF]：<https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/>

---

## 3. 二进制 `.vsd` 相关（M9 才需要）

### 3.1 OLE2 Compound File Binary

- [MS-CFB]：<https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/>
- OpenOffice 1.x 反向工程笔记：<https://www.openoffice.org/sc/excelfileformat.pdf>

### 3.2 Visio 二进制 record 结构

- libvisio 文档（C++）：<https://wiki.documentfoundation.org/Development/libvisio>
- libvisio-ng 源码注释（Python，GPL）—— 只读源码理解 record 类型表，再独立实现

---

## 4. 第三方解读 / 教程

| 资源 | 链接 | 价值 |
|---|---|---|
| File Format Wiki | <https://wiki.fileformat.com/image/vsdx/> | 中文友好的 VSDX 结构概览 |
| File Format Wiki — VSD | <https://wiki.fileformat.com/image/vsd/> | 老格式速览 |
| LoC FDD VSDX | <https://loc.gov/preservation/digital/formats/fdd/fdd000021.shtml> | 归档保存视角 |
| Aspose Docs | <https://docs.aspose.com/diagram/net/working-with-vsdx-file-format/> | 商业实现的 API 描述（思路参考） |
| Visio Insights Blog | <https://techcommunity.microsoft.com/category/microsoft365/blog/microsoft-365-blog/visio> | 官方更新动态 |

---

## 5. 阅读建议路径

1. **半小时入门**：先读 MS-VSDX §1.3 Overview + Microsoft Learn "Introduction" 一文
2. **建立心智模型**：精读 §2.1（OPC 结构）+ §2.2.1–§2.2.6（Document/Page/Master/Shape）
3. **动手挑战**：用 LibreOffice 画一个矩形保存为 `.vsdx`，解压观察文件树
4. **深挖几何**：精读 §2.2.7–§2.2.8（ShapeSheet + Geometry）
5. **样式继承**：§2.2.5 + 配合 `libvisio-ng/src/libvisio/vsdx/parser.py` 中
   `_resolve_style_inheritance` 算法描述（注意只读源码，不复制）
6. **公式系统**：§2.2.11 函数表（300+ 函数，按需查阅）

---

## 6. 引用本仓库的方式

如果你的论文 / 博客需要引用本项目对 VSDX 的实现，请引用：

```
visiovsdxviewer: A pure Dart/Flutter VSDX viewer.
https://github.com/<owner>/visiovsdxviewer
```

并在论文中标注：本项目仅基于公开 [MS-VSDX] 规范独立实现，与 libvisio 系列代码无衍生关系。
