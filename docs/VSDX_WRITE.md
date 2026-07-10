# Writer 详细设计（.vsdx 往返写回）

> 这是本编辑器的**核心新组件**（查看器只读，无此能力）。目标：把编辑后的
> `VsdxDocument` 保真写回 `.vsdx`。格式细节见 [`VSDX_FORMAT.md`](./VSDX_FORMAT.md)；
> 代码参考见 [`references/projects.md`](./references/projects.md)（首推 `vsdx` BSD 库）。

---

## 1. 为什么不能"全量重写"

`.vsdx` 的灵魂是 ShapeSheet：每个 Cell 可能带公式 `F`（`Inh`、`Width*0.5`、`THEMEVAL()`、
`GUARD(...)`）。解析进模型时公式语义大多被求值/丢弃。如果保存时把整个语义模型重新
序列化成 XML，会**丢失公式、Master 继承、主题绑定、未知节**，产出退化文件。

因此 Writer 以**保真透传**为第一原则。

---

## 2. 两种写回路径

### 2.1 load-preserve-patch（打开已有文件后保存，主路径）

思想：以**原始包字节**为基准，只对用户**显式编辑过**的部分打最小补丁。

步骤：

1. **保留原始包**：`open()` 时缓存原始 `Uint8List` bytes（以及解出的 part 列表 / 关系）。
2. **重解 XML DOM**：保存时用 `package:archive` 解出需要修改的 part（通常是若干
   `visio/pages/pageN.xml`），用 `package:xml` 解析为**可变 `XmlDocument`**。
3. **建立映射**：模型侧每个 `VsdxShape` 记有 `page index` + `Shape ID`；据此定位 XML 中
   `<Shape ID="...">` 节点（含嵌套子 Shape，递归匹配）。
4. **打补丁（仅改动过的 Cell）**：
   - 位置/尺寸/角度：`PinX PinY Width Height Angle FlipX FlipY`
   - 1D 端点：`BeginX BeginY EndX EndY`
   - 样式：`FillForegnd LineColor LineWeight`（及 `FillPattern=0`/`LinePattern=0` 表达无填充/无线）
   - 文本：`<Text>` 子节点内容（首版按纯文本写回，富文本增量后置）
   - 写法：设置 `Cell/@V`；若该 Cell 原有 `@F` 且为公式/`Inh`，则**移除 `@F`** 或改写为
     `GUARD(<value>)`，避免被 Visio 重算覆盖（见 §4）。
5. **增删 Shape**：
   - 删除：移除对应 `<Shape>`，并清理引用它的 `<Connect>`（`FromSheet`/`ToSheet`）。
   - 新增：生成新的 `<Shape>`（XForm + `Section N="Geometry"` + 基本样式 Cell），分配当前页
     未占用的 `Shape ID`；必要时更新 `pages.xml`。
6. **未触及 part 原样复制**：`masters/*`、`theme/*`、`windows.xml`、`docProps/*`、
   `media/*`、`[Content_Types].xml`、所有 `.rels` 以及任何未知 part —— **字节级复制**。
7. **重打包**：用 `ZipEncoder` 写出新的 `.vsdx`（保持 part 名与目录结构不变）。

### 2.2 emit-from-scratch（新建文档，辅路径）

无原始包时，按 [`VSDX_FORMAT.md`](./VSDX_FORMAT.md) 生成**最小合法包**：

```
[Content_Types].xml
_rels/.rels                       -> visio/document.xml
docProps/{app,core}.xml
visio/document.xml
visio/_rels/document.xml.rels     -> pages.xml (+windows.xml)
visio/pages/pages.xml
visio/pages/_rels/pages.xml.rels  -> page1.xml
visio/pages/page1.xml             -> <PageContents><Shapes/>...
```

新增的形状用与 §2.1(5) 相同的 `<Shape>` 生成逻辑填入 `page1.xml`。

---

## 3. Shape 生成模板（新增形状）

- **矩形**（2D）：XForm（PinX/PinY/Width/Height/Angle）+ 一个 `Geometry` 节，5 行
  `RelMoveTo/RelLineTo` 描出矩形（0,0)->(1,0)->(1,1)->(0,1)->close。
- **椭圆**：`Geometry` 用一行 `Ellipse`（X=Width/2, Y=Height/2, A/B 控制点）。
- **直线 / 连接器**（1D）：`BeginX/BeginY/EndX/EndY` + `Geometry`（MoveTo Begin, LineTo End，
  或 L 形两段）；连接器另写 `<Connect>` 行绑定两端形状。
- 样式：`FillForegnd`/`FillPattern`/`LineColor`/`LineWeight`/`LinePattern` 直接量（不引主题，
  保证可预测）。

> 参考：`third_party/vsdx`（BSD）中 shape 创建/复制与 OPC 重打包；`third_party/drawio`
> 的 `VsdxExport`/`VsdxImport` 中几何模板与 Arc→Bezier。

---

## 4. 公式/继承的处理策略（首版）

- 用户**未改动**的 Cell：连同 `@F` 原样保留（透传）。
- 用户**改动**的 Cell：写死 `@V=<新值>`，并移除 `@F`（若原为 `Inh` 或依赖式）。可选加
  `GUARD()` 语义以阻断重算。仅作用于被编辑 Cell，最小化对文件其余部分的影响。
- 主题绑定（`THEMEVAL()`）：未编辑则保留；用户显式改色则转为直接量颜色。

---

## 5. 测试策略

- **往返恒等**：`open(bytes) -> save() -> open()`，断言关键字段一致；对未编辑文件，比较
  受影响 part 数量最小、其余 part 字节不变。
- **编辑往返**：移动/改色/改文本某形状 -> save -> 重开，断言变更生效、其余无损。
- **交叉验证**：`soffice --headless --convert-to pdf out.vsdx`（或用 LibreOffice Draw 打开）
  确认不报错、渲染正确。
- **样例合规**：LibreOffice Draw 导出、`third_party/vsdx` 的 BSD fixtures（保留版权头）、
  自绘；不分发商业模板。

---

## 6. 里程碑对应

对应 [`PLAN.md`](./PLAN.md) §7 E4。**Slice-0 收官**：改一个形状能正确保存并被
LibreOffice/Visio 读回。
