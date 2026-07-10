# VSDX 文件格式速查（VSDX Format Notes）

> 本文档梳理 `.vsdx` 文件格式的关键结构，供解析器开发参考。原始权威资料见
> [`references/specifications.md`](./references/specifications.md)。

---

## 1. 文件家族

| 扩展名 | 含义 | 是否支持宏 | 计划支持 |
|---|---|---|---|
| `.vsdx` | Visio 2013+ Drawing | 否 | M1+ ✅ |
| `.vsdm` | Drawing with Macros | 是 | M1+ ✅（忽略宏） |
| `.vssx` | Stencil（模具/素材库） | 否 | M2+ ✅ |
| `.vssm` | Stencil with Macros | 是 | M2+ ✅ |
| `.vstx` | Template（模板） | 否 | M2+ ✅ |
| `.vstm` | Template with Macros | 是 | M2+ ✅ |
| `.vsd` / `.vss` / `.vst` | Visio 2003-2010 二进制（OLE2） | 是 | M9 ⚠️ 大版本 |
| `.vdx` / `.vsx` / `.vtx` | Visio 2003-2010 XML | 否 | 不规划（可后续兼容） |

`.vsdx` 与 `.docx`/`.xlsx`/`.pptx` 同属 **OOXML 家族**，皆遵循
[ISO/IEC 29500-2 OPC (Open Packaging Conventions)](https://www.iso.org/standard/71691.html)。

---

## 2. OPC 包结构

`.vsdx` 实际上是一个 **ZIP 容器**。将文件后缀改为 `.zip` 即可解开。
典型结构如下（不同来源的文件略有差异）：

```
my_diagram.vsdx
├── [Content_Types].xml                 # MIME 类型映射
├── _rels/
│   └── .rels                           # 包根关系
├── docProps/
│   ├── app.xml                         # 创建者/应用信息
│   ├── core.xml                        # 标题/作者/日期
│   ├── custom.xml                      # 自定义属性
│   └── thumbnail.emf                   # 预览图（可选）
└── visio/
    ├── document.xml                    # 文档级设置
    ├── _rels/document.xml.rels
    ├── windows.xml                     # 窗口状态
    ├── pages/
    │   ├── pages.xml                   # 页面索引
    │   ├── _rels/pages.xml.rels
    │   ├── page1.xml                   # 第 1 页所有 Shape
    │   ├── _rels/page1.xml.rels
    │   ├── page2.xml
    │   └── ...
    ├── masters/
    │   ├── masters.xml                 # Master 索引
    │   ├── _rels/masters.xml.rels
    │   ├── master1.xml                 # 单个 Master
    │   ├── _rels/master1.xml.rels
    │   ├── masters.xml.rels
    │   └── ...
    ├── theme/
    │   └── theme1.xml                  # 主题色 / 字体 / 效果
    └── media/                          # 嵌入的图像
        ├── image1.png
        ├── image2.jpeg
        └── ...
```

### 2.1 `[Content_Types].xml`

声明 ZIP 中每条路径的 MIME 类型。两种条目：

```xml
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="rels"
           ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Override PartName="/visio/document.xml"
            ContentType="application/vnd.ms-visio.drawing.main+xml"/>
  <Override PartName="/visio/pages/page1.xml"
            ContentType="application/vnd.ms-visio.page+xml"/>
  ...
</Types>
```

### 2.2 关系（Relationships）

OPC 用"关系"（`*.rels`）描述各 Part 之间的有向链接：

```xml
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
                Type="http://schemas.microsoft.com/visio/2010/relationships/document"
                Target="visio/document.xml"/>
</Relationships>
```

- 根 `_rels/.rels` 必含一条指向 `visio/document.xml` 的关系
- `visio/_rels/document.xml.rels` 指向 `pages.xml`、`masters.xml`、`theme/`、`windows.xml` 等
- `visio/pages/_rels/page1.xml.rels` 指向 master、image、超链接目标等

**Type URI 不可枚举**，解析时应按 URI 后缀（如 `/master`、`/image`、`/hyperlink`）判定。

---

## 3. `visio/document.xml`

```xml
<VisioDocument xmlns="http://schemas.microsoft.com/office/visio/2012/main">
  <DocumentSettings TopPage="0" DefaultTextStyle="3"
                    DefaultLineStyle="3" DefaultFillStyle="3" DefaultGuideStyle="4">
    <GlyphSettingsEnabled>0</GlyphSettingsEnabled>
    ...
  </DocumentSettings>
  <Colors><ColorEntry IX="0" RGB="#000000"/>...</Colors>
  <FaceNames><FaceName NameU="Calibri" UnicodeRanges="..."/>...</FaceNames>
  <StyleSheets>
    <StyleSheet ID="0" NameU="No Style"><Cell N="EnableLineProps" V="1"/>...</StyleSheet>
    ...
  </StyleSheets>
  <DocumentSheet NameU="TheDoc" UniqueID="{...}">
    <Section N="User">...</Section>
  </DocumentSheet>
</VisioDocument>
```

要点：

- **DocumentSettings**：默认样式表索引、默认页等全局开关
- **Colors**：调色板，被 `Cell` 中的 `THEMEVAL()` 或索引引用
- **FaceNames**：字体定义
- **StyleSheets**：内置样式（"No Style"、"Text Only"、"Visio 50%"…），shape 通过
  `LineStyle`/`FillStyle`/`TextStyle` 索引继承

---

## 4. `visio/pages/pages.xml` 与 `pageN.xml`

### 4.1 索引

```xml
<Pages xmlns="...">
  <Page ID="0" NameU="Page-1" ViewScale="1" ViewCenterX="4.25" ViewCenterY="5.5">
    <PageSheet LineStyle="0" FillStyle="0" TextStyle="0">
      <Cell N="PageWidth"  V="8.5"  U="IN"/>
      <Cell N="PageHeight" V="11"   U="IN"/>
      <Cell N="ShdwOffsetX" V="0.125"/>
      ...
      <Section N="Layer">...</Section>
    </PageSheet>
    <Rel r:id="rId1"/>          <!-- 指向 page1.xml -->
  </Page>
  ...
</Pages>
```

### 4.2 单页

```xml
<PageContents xmlns="...">
  <Shapes>
    <Shape ID="1" NameU="Sheet.1" Type="Shape" Master="2">
      <Cell N="PinX"   V="2.5"/>
      <Cell N="PinY"   V="9.0"/>
      <Cell N="Width"  V="1.5"/>
      <Cell N="Height" V="0.75"/>
      <Cell N="Angle"  V="0"/>
      <Cell N="FillForegnd"  V="THEMEGUARD(THEMEVAL())"  F="..."/>
      <Cell N="LineColor"    V="#000000"/>
      <Section N="Geometry" IX="0">
        <Cell N="NoFill" V="0"/>
        <Cell N="NoLine" V="0"/>
        <Row T="RelMoveTo" IX="1">
          <Cell N="X" V="0"/><Cell N="Y" V="0"/>
        </Row>
        <Row T="RelLineTo" IX="2">
          <Cell N="X" V="1"/><Cell N="Y" V="0"/>
        </Row>
        ...
      </Section>
      <Section N="Character" IX="0">
        <Row IX="0"><Cell N="Font" V="0"/><Cell N="Color" V="0"/><Cell N="Size" V="0.1666"/></Row>
      </Section>
      <Text>Hello <cp IX="0"/>Visio</Text>
      <Shapes>...</Shapes>      <!-- 子形状（Group） -->
    </Shape>
    ...
  </Shapes>
  <Connects>
    <Connect FromSheet="3" FromCell="BeginX" FromPart="9"
             ToSheet="1"   ToCell="Connections.X1" ToPart="100"/>
  </Connects>
</PageContents>
```

---

## 5. ShapeSheet 核心概念

Visio 的 "灵魂" 是 **ShapeSheet**：每个 shape 都是一张电子表格，由 `Section`/`Row`/`Cell`
三级结构组织。

### 5.1 Section（节）

按 `N` 属性区分，常见：

| Section `N` | 用途 |
|---|---|
| `Geometry` | 几何路径（多边形、Bezier、Arc、NURBS…） |
| `Character` | 字符级格式（字体、字号、颜色） |
| `Paragraph` | 段落级格式（对齐、缩进、行距） |
| `Tabs` | 制表位 |
| `Layer` | 图层定义（仅 PageSheet） |
| `User` | 用户定义变量（公式可引用） |
| `Prop` | 自定义属性（数据图形输入） |
| `Field` | 文本中的动态字段 |
| `Action` | 右键菜单/双击动作 |
| `Connection` | 连接点（用于连接器吸附） |
| `Control` | 控制点（可拖手柄） |
| `Hyperlink` | 超链接 |
| `Scratch` | 用户私有计算缓存 |
| `Reviewer` / `Annotation` | 评审 / 批注 |

### 5.2 Row（行）

通过 `T` 属性区分类型，最重要的是 Geometry 行类型：

| Row `T` | 含义 | 关键 Cell |
|---|---|---|
| `MoveTo` / `RelMoveTo` | 移动笔尖 | `X` `Y` |
| `LineTo` / `RelLineTo` | 直线段 | `X` `Y` |
| `ArcTo` / `RelArcTo` | 圆弧（含 bow 偏移） | `X` `Y` `A` |
| `EllipticalArcTo` / `RelEllipticalArcTo` | 椭圆弧 | `X` `Y` `A` `B` `C` `D` |
| `Ellipse` | 整椭圆 | `X` `Y` `A` `B` `C` `D` |
| `NURBSTo` | NURBS 段 | `X` `Y` `A` `B` `C` `E` |
| `SplineStart` / `SplineKnot` | B-Spline | `X` `Y` `A` `B` `C` `D` |
| `PolylineTo` | 多段线 | `X` `Y` `A` |
| `RelCubBezTo` / `RelQuadBezTo` | 相对 Bezier | `X` `Y` `A` `B`（`C` `D`） |
| `InfiniteLine` | 无限直线 | `X` `Y` `A` `B` |

### 5.3 Cell（单元格）

```xml
<Cell N="PinX" V="2.5" U="IN" F="某公式" E="ERR#"/>
```

- `N` Name：单元格名称
- `V` Value：当前求值结果
- `U` Unit：单位
- `F` Formula：原始公式（如 `Inh`、`Width*0.5`、`THEMEVAL()`、`GUARD(...)`、`USE(Master.x!Geometry1.X1)`）
- `E` Error：求值错误

**继承**：`F="Inh"` 表示从 Master 继承同名 Cell。Master 自身也可继承 StyleSheet。

---

## 6. 单位（Units）

`U` 属性可为：

| 单位 | 含义 | 转 inch |
|---|---|---|
| `IN` / `IN_F` | 英寸 / 分数英寸 | × 1 |
| `MM` | 毫米 | × 1/25.4 |
| `CM` | 厘米 | × 1/2.54 |
| `M` | 米 | × 100/2.54 |
| `PT` | 点 | × 1/72 |
| `PICA` | 派卡 | × 1/6 |
| `FT` | 英尺 | × 12 |
| `DT` | 显示英尺-英寸 | 由解析器解析字符串 |
| `DEG` | 度 | 仅角度 |
| `RAD` | 弧度 | 仅角度 |
| `BOOL` | 布尔 | `0`/`1` |
| `COLOR` | 颜色 | 解析为 ARGB |

解析器须在进入 Model 层前统一换算为 **inch**（长度）/ **rad**（角度）/ **ARGB**（颜色）。

---

## 7. 主题（Theme）

`visio/theme/themeN.xml` 沿用 OOXML DrawingML 的 `clrScheme` / `fontScheme` /
`fmtScheme`，外加 Visio 扩展节 `<vt:variationStyleSchemeLst>`。

Shape 中 `Cell N="FillForegnd" V="THEMEGUARD(THEMEVAL())" F="THEMEGUARD(THEMEVAL())"`
会让填充色实时取自当前主题的某个槽位，规则由 `QuickStyleType`/`QuickStyleVariation`/
`QuickStyleFillColor` 等单元格决定（共 7 槽 × 4 变体 = 28 种映射）。

完整映射表见 [`references/specifications.md`](./references/specifications.md#theme)。

---

## 8. Master（模具）

`Master` 是可复用的形状定义，引用方式：

```xml
<Shape ID="5" Master="2" ...>
  <Cell N="PinX" V="3" F="Inh"/>     <!-- 继承自 Master -->
</Shape>
```

Master 内部结构同 PageSheet + Shapes。多个实例通过覆盖少量 Cell 实现差异化，
体积小且修改 Master 即可批量更新。

---

## 9. 连接器（Connectors）

1D 形状（线/连接器）特有：

```xml
<Shape ID="7" Type="Shape" Master="6">
  <Cell N="BeginX" V="2.0"/><Cell N="BeginY" V="4.0"/>
  <Cell N="EndX"   V="6.0"/><Cell N="EndY"   V="4.0"/>
  <Section N="Geometry">...</Section>
</Shape>
<Connects>
  <Connect FromSheet="7" FromCell="BeginX" ToSheet="1" ToCell="Connections.X1"/>
  <Connect FromSheet="7" FromCell="EndX"   ToSheet="3" ToCell="Connections.X2"/>
</Connects>
```

`Connect` 描述端点吸附关系：当目标 shape 移动时，Visio 重新求值端点公式
（典型形如 `PAR(PNT(Sheet.1!Connections.X1,...))`），自动更新连接器路径。

---

## 10. 文本（Text）

```xml
<Text>
  Hello <cp IX="0"/>Big <cp IX="1"/>World
  <fld IX="0"/>           <!-- 字段，引用 Section N="Field" Row IX="0" -->
</Text>
```

- `<cp IX="n"/>`：从此处起字符格式切换到 `Section N="Character" IX="n"`
- `<pp IX="n"/>`：段落格式切换
- `<tp IX="n"/>`：制表位切换
- `<fld IX="n"/>`：插入字段
- 换行：保留原样换行符

---

## 11. 嵌入图像

```xml
<Shape ID="9" Type="Foreign">
  <ForeignData ForeignType="Bitmap" CompressionType="JPEG">
    <Rel r:id="rId3"/>     <!-- → media/image1.jpeg -->
  </ForeignData>
</Shape>
```

支持 `Bitmap`（PNG/JPEG）、`Metafile`（EMF/WMF）、`EnhMetaFile`、`Object` 等。
EMF/WMF 在 Flutter 端难以原生渲染，建议先回退到占位框（见 PLAN R3）。

---

## 12. 公式（Formula）

ShapeSheet 公式语法接近 Excel：

```
= Width * 0.5
= IF(Selected, RGB(255,0,0), THEMEVAL())
= GUARD(PAR(PNT(Sheet.5!Connections.X1, Sheet.5!Connections.Y1)))
= INTERSECTX(BeginX, BeginY, Angle, Sheet.3!PinX, Sheet.3!PinY, 0)
```

- 数字直接量 + 单位：`1.5 in`、`30 deg`
- 引用：`Width`、`Sheet.5!PinX`、`Inh`、`User.x`、`Prop.x`
- 内置函数（数百个）：算术、三角、`IF`、`MAX`、`MIN`、`SUMIF`、`GUARD`、
  `THEMEVAL`、`THEMEGUARD`、`PNT`、`PAR`、`PERP`、`INTERSECTX`、`POLYLINE`…
- 函数全集详见 [MS-VSDX] §2.2.11.2

解析器策略：
1. **M2 仅实现立即字面量 + `Inh` + 简单算术**，足以打开 90% 文件
2. **M2+** 引入完整 lexer/parser，但 evaluator 只支持只读求值（不重算）
3. **M6+** 真正支持公式重算（用于编辑/导出动态值）

---

## 13. 命名空间速查

| 前缀 | 命名空间 |
|---|---|
| `xmlns` (默认) | `http://schemas.microsoft.com/office/visio/2012/main` |
| `r` | `http://schemas.openxmlformats.org/officeDocument/2006/relationships` |
| `xr` | `http://schemas.microsoft.com/office/visio/2012/extension` |
| `vt` | `http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes` |
| `cp` | `http://schemas.openxmlformats.org/package/2006/metadata/core-properties` |

主体 XML 已使用默认命名空间，解析时建议剥离前缀按 local name 处理。

---

## 14. 实践建议

1. **从 LibreOffice 导出**一个最简 `.vsdx`（一个矩形 + 一句文本）开始研究
2. 用 `unzip -l my.vsdx` 列出 Part 清单
3. 把 `pageN.xml` 用 `xmllint --format` 美化阅读
4. 复杂场景对照 [`references/projects.md`](./references/projects.md) 中
   `libvisio-ng`、`vsdx` 的源码比对解析路径
5. 永远保留原 fixture，作为 Golden Test 的回归基准
