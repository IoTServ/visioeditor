# Editor for Visio Diagrams — 开发规划与状态跟踪表（Roadmap & Tracker）

> 本文件是**主开发规划与进度跟踪表**。每完成一个任务，更新其状态标记与
> [进度日志](#进度日志)。配套文档：
> [`ARCHITECTURE.md`](./ARCHITECTURE.md) ·
> [`VSDX_WRITE.md`](./VSDX_WRITE.md) ·
> [`REUSE_MAP.md`](./REUSE_MAP.md) ·
> [`VSDX_FORMAT.md`](./VSDX_FORMAT.md) ·
> [`CHANGELOG.md`](./CHANGELOG.md) ·
> [`RELEASE_NOTES.md`](./RELEASE_NOTES.md) ·
> [`references/`](./references/)

状态标记：`TODO` 未开始 · `DOING` 进行中 · `DONE` 完成 · `LATER` v0.1 之后

---

## 1. 项目愿景

`Editor for Visio Diagrams` 是一个**原生、跨平台的 Microsoft Visio (`.vsdx`) 编辑器**，
基于 Flutter/Dart。区别于隔壁只读查看器 `visiovsdxviewer`（libvisio→FFI→有损只读 IR），
本项目采用**原生 Dart 往返引擎**：

- 直接解析 `.vsdx`（OPC/ZIP + XML）为**强类型可编辑模型**；
- 在画布上编辑（选择/变换/文本/样式/形状/连接器）；
- **保真回写 `.vsdx`**（load-preserve-patch：仅改动用户编辑的 Cell，其余原样透传）。

首发范围：**核心编辑器 + macOS 桌面优先**。老格式 `.vsd` 导入、其他平台、模具库、
自动路由、导出等进入 v0.1 之后的里程碑。

---

## 2. 里程碑总览（Milestones）

- **E0 文档与参考落地** — `DONE`
- **E1 恢复引擎（读+建模+渲染）** — `DONE`
- **E2 只读画布（macOS）** — `DONE`
- **E3 可编辑模型 + 选择/变换 + 撤销重做** — `DOING`（核心完成；缩放/旋转手柄待补 = E3b）
- **E4 写回器 Writer（往返保存）** — `DONE`  ← 核心新组件 / **Slice-0 达成**
- **E5 创建形状 + 文本 + 样式** — `DONE`（连接器 glue / 新建文档留待后续）
- **E6 完善与打包 v0.1** — `DOING`

执行原则：**先整体后细节** —— 先打通端到端最薄纵向切片（Slice-0：打开→渲染→选中移动
一个形状→保存→重开无损），再逐块加深。

---

## 3. E0 —— 文档与参考落地  `DONE`

- [x] `git init`（分支 `main`）
- [x] 应用品牌名：macOS `CFBundleDisplayName = "Editor for Visio Diagrams"`；更新版权串
- [x] 下载参考到 `third_party/`：vsdx(BSD) / libvisio(MPL) / drawio(Apache)，记录 commit/license（见 [`third_party/README.md`](../third_party/README.md)）
- [x] `.gitignore` 忽略 `third_party/*`（仅保留 README）
- [x] `pubspec.yaml` 依赖 + `packages/vsdx` 纯 Dart 包骨架；`flutter pub get` 通过
- [x] 复用格式文档：`docs/VSDX_FORMAT.md` 与 `docs/references/*`
- [x] 主文档：PLAN.md / ARCHITECTURE.md / VSDX_WRITE.md / REUSE_MAP.md
- [x] 重写根 `README.md` + 新增 `LICENSE`(MIT)
- [ ] 首次提交（E0 基线）—— 待用户确认后提交（默认不自动 commit）

验收：`flutter pub get` 通过；docs 齐全；third_party 就位且不入库。 **E0 基本完成。**

---

## 4. E1 —— 恢复引擎（读 + 建模 + 渲染）  `DONE`

源：`visiovsdxviewer@0fcaf66^`（MIT）。详见 [`REUSE_MAP.md`](./REUSE_MAP.md)。

- [x] 恢复 `core/`（4）+ `utils/`（4）到 `packages/vsdx/lib/src/`
- [x] 恢复 `model/`（18）到 `packages/vsdx/lib/src/model/`
- [x] 恢复 `parser/`（21，剔除 Flutter 依赖的 `document_parser_isolate.dart`）到 `packages/vsdx/lib/src/parser/`
- [x] 修正包内 import；`packages/vsdx/lib/vsdx.dart` 导出公共面
- [x] 恢复 `render/`（10：vsdx_painter/path_builder/arrow_library/pattern_fill/shape_bounds/connector_router/font_fallback/image_cache/page_picture_cache/dash_path）到 `lib/render/`，剔除 `ir_*`；import 改 `package:vsdx`
- [x] 打通 `VsdxPackage.open(bytes) → DocumentParser().parse → VsdxDocument`
- [x] 纯 Dart 单测：解析 test1/test9/test4 样例，断言 pages/shapes/几何/页尺寸（4/4 通过）
- [x] `flutter analyze` 零问题；修正 vector_math 弃用 API

验收：`dart test`（packages/vsdx）通过（4/4），样例产出非空 `VsdxDocument`。**E1 完成。**

---

## 5. E2 —— 只读画布（macOS）  `DONE`

- [x] App 外壳：`MaterialApp`（`VisioEditorApp`）+ AppBar/工具栏；标题 "Editor for Visio Diagrams"，Material 3 深浅色主题
- [x] 打开文件：`file_picker` 选择 + `desktop_drop` 拖入 `.vsdx`（`lib/io/document_io.dart`）
- [x] 画布：`InteractiveViewer` + `CustomPaint(VsdxPainter)`；auto-fit、缩放控件（`lib/editor/page_canvas.dart`）
- [x] 多页页签（`ChoiceChip` 底栏）
- [x] 错误态/空态 UI（`_EmptyState` + SnackBar）
- [x] `flutter analyze` 零问题；`flutter test` 冒烟通过；`flutter build macos --debug` 成功

验收：macOS 构建产出 `visioeditor.app`（显示名 "Editor for Visio Diagrams"）；读→渲染管线在目标平台编译链接通过。**E2 完成**（交互式渲染观感待用户运行验证）。

---

## 6. E3 —— 可编辑模型 + 选择/变换 + 撤销重做  `DOING`

核心（选择/移动/撤销）已完成；缩放/旋转手柄作为细节在 Slice-0（E4）之后补。

- [x] 模型 `copyWith`：VsdxDocument/Page/Shape + `updateShapeById`（递归）/`replacePage`（保持 `@immutable`，结构共享）
- [x] `EditorController`（ChangeNotifier）：当前文档/当前页/`selection`/脏标记；事务式历史（drag 一次 undo）
- [x] 命中测试（复用 `shape_bounds` + 绘制顺序取最上层）：点选/清除
- [x] 移动：拖拽选中形状（含 1D begin/end 同步）；空白拖拽平移画布；滚轮平移、Ctrl/Cmd+滚轮缩放
- [x] 选择叠加层：外框 + 8 手柄（渲染）
- [x] 命令栈：快照式 undo/redo（工具栏按钮）
- [x] 纯 Dart 单测：copyWith / updateShapeById / replacePage / 不可变性 / 结构共享（4/4）
- [x] 变换手柄**交互（缩放）**：8 向缩放手柄，几何随尺寸缩放（`scalePathCommand`/`VsdxShape.resizeTo`），单选非旋转 2D 形状
- [x] **旋转手柄**：单选 2D 形状顶部旋钮，绕 pin 旋转（`rotateShape`）；Writer 补丁 `Angle`；旋转往返单测
- [x] undo/redo 键盘快捷键（Cmd+Z / Cmd+Shift+Z）—— 见 E6

验收：选中→移动/缩放/旋转→撤销/重做，画面与模型一致（已达成）。

---

## 7. E4 —— 写回器 Writer（往返保存）  `DONE`（核心 / Slice-0 达成）

详细设计见 [`VSDX_WRITE.md`](./VSDX_WRITE.md)。实现于 `packages/vsdx/lib/src/writer/vsdx_writer.dart`。

- [x] 打开时缓存原始 bytes（`EditorController._originalBytes`），作为写回基准与未触及 part 来源
- [x] `load-preserve-patch`：`document→pages.xml→Rel` 定位 `pageN.xml`；按 Page index + Shape ID（递归含子形状）就地补丁 XForm Cell（PinX/PinY/Width/Height/Angle/FlipX/FlipY/BeginX..EndY）
- [x] 仅当值相对基线变化才改写，改写时写入原 Cell 的 `U` 单位（`fromInches`/`fromRadians`）并移除 `F`/`E`，避免被 Visio 重算；缺失 Cell 自动补建
- [x] 未触及 part（masters/theme/media/docProps/未知节/rels/[Content_Types]）**字节级原样复制**，`ZipEncoder` 重打包
- [x] 保存 UI：`EditorController.exportToBytes()`/`markSaved()`；工具栏 Save + Save As…；保存后清脏、成为新基线
- [x] 测试：编辑往返（移动→save→reopen 位置正确）、未编辑形状无损、无编辑保存保留全部 part 名与值（3/3，共 11/11）
- [ ] 删除/新增 Shape 的 XML 处理、`emit-from-scratch` 新建文档 —— 归入 E5
- [x] LibreOffice `soffice --headless` 交叉验证 —— CI job 安装 LibreOffice；
  本机无 soffice 时测试 skip（`REQUIRE_SOFFICE=1` 强制失败）

验收：**Slice-0 达成** —— 打开→渲染→选中移动→保存→重开位置正确、其余无损（引擎单测证明）。Visio/LibreOffice 人工核验待安装 soffice。

---

## 8. E5 —— 创建形状 + 文本 + 样式  `DONE`（核心；连接器 glue / 新建文档留待后续）

引擎：`shape_factory.dart`（rect/ellipse/line）+ `VsdxPage.addShape/removeShapeById/nextFreeShapeId`；
Writer 扩展为新增/删除 `<Shape>` + 样式/文本补丁；`VsdxFill/VsdxLine.copyWith`。

- [x] 形状工具：矩形/椭圆（MoveTo/LineTo、Ellipse 行）、直线（1D，Begin/End + 局部几何）；工具条 + 拖拽创建 + 虚线预览 + 单击默认尺寸
- [x] 就地文本编辑：双击形状 → **画布上叠加编辑器**（随形状框定位/缩放；Enter 换行、
  Cmd/Ctrl+Enter 或点击别处提交、Esc 取消）→ `setShapeText`（同步 richText run，画布即时
  WYSIWYG）→ Writer 写回 `<Text>`
- [x] 样式面板：填充/线条色板 + 无填充/无线 + 线宽（pt）→ `FillForegnd`/`FillPattern`/`LineColor`/`LineWeight`/`LinePattern`
- [x] 删除：Delete/Backspace 键 + 面板按钮；Writer 移除 `<Shape>`
- [x] Writer 新增/删除/样式/文本单测（创建矩形、删除、改色往返，共 14/14）；`flutter analyze` 零问题、macOS 构建成功
- [ ] 连接器 `Connect` 行与端点吸附（glue）—— 留待后续（当前“线”为独立 1D 形状，无自动吸附）
- [ ] 复制 / 粘贴 / duplicate、新建空文档（emit-from-scratch）—— 并入 E6

验收：能新增矩形/椭圆/线、改填充/线条/线宽、双击编辑文本、删除，保存后重开保真（引擎单测证明）。

---

## 9. E6 —— 完善与打包 v0.1  `DOING`（关键项完成；打包细节留待后续）

- [x] 快捷键：Cmd+S 保存 / Cmd+Z 撤销 / Cmd+Shift+Z 重做 / Cmd+D 复制、Delete 删除、Esc（`CallbackShortcuts`）
- [x] 复制（duplicate）/ 复制粘贴（Cmd+C/V，应用内剪贴板）：`duplicateSelection` / `copySelection` / `paste`
- [x] **新建空文档**（emit-from-scratch）：`VsdxWriter.emptyDocument` 生成最小合法包，`newDocument`（Cmd+N / 工具栏 / 空态按钮）
- [x] 打开 / 另存为 / 保存；缩放控件 + 适应窗口 + 缩放百分比读数
- [x] 底部状态栏：页面尺寸 / 当前页 / 未保存标记 / 选中数
- [x] `CHANGELOG.md` + 根 `NOTICE`（依赖 + 参考 attribution）
- [x] 最近文件、未保存关闭拦截、基础网格与吸附
- [x] **应用图标**：品牌流程图图标（蓝色圆角瓷砖 + 白色双节点/连接线/箭头），可复现生成脚本 `tool/gen_app_icon.dart`
- [x] **`.vsdx` OS 文件关联（UTI）+ 启动即打开**：`Info.plist` 声明 `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`（`com.microsoft.visio.drawing`，扩展 vsdx/vsdm/vstx/vstm/vssx/vssm）；`AppDelegate.application(_:open:)` → `FileOpenBridge`（缓冲+就绪刷新）→ `MethodChannel('visioeditor/files')` → Dart `_openPath`（Finder 双击 / “打开方式” / `open`）。LaunchServices 已确认 claimed UTI 与 Editor 角色
- [x] **v0.1 正式发布说明**（[`RELEASE_NOTES.md`](./RELEASE_NOTES.md)：亮点 / 运行方式 / 快捷键 / 已知限制 / 验证）
- [ ] macOS 代码签名 / 公证（notarization）—— 需 Apple 开发者证书，本地环境不具备

验收：从零 `flutter build macos` 可打开/编辑/保存 `.vsdx`（已达成）；应用图标、`.vsdx` 文件关联与启动打开已完成并验证；发布说明已就位；仅剩签名/公证（依赖证书）。

---

## 10. 依赖清单

- `packages/vsdx`（纯 Dart）：archive ^3.6.1, xml ^6.5.0, path ^1.9.0, vector_math ^2.1.4, meta ^1.15.0, collection ^1.18.0, crypto ^3.0.5, logging ^1.2.0
- App（`lib`）：path_drawing ^1.0.1, vector_math, file_picker ^8.1.4, desktop_drop ^0.4.4, shared_preferences ^2.5.3, intl ^0.20.2 + flutter_localizations, url_launcher ^6.3.2, collection, logging
- dev：flutter_lints ^6.0.0, test ^1.25.0, mocktail ^1.0.4

---

## 11. 风险登记（Risk Register）

- **公式与继承**：编辑改 `V` 而原 `F` 为公式/`Inh` 时可能被 Visio 重算覆盖 → 首版对被编辑
  Cell 写死 `V` 并去 `F`/加 `GUARD`，范围仅限用户显式改动，其余保真透传。
- **往返保真**：复杂文件未知节必须原样透传；**禁止**全量重写语义模型再序列化（会丢公式/结构）。
- **恢复耦合**：`render/*` 依赖 Flutter 与旧 IR，恢复时剔除 `ir_*`，仅取模型驱动路径。
- **依赖版本**：沿用查看器版本以复用代码，升级留到主干跑通后。
- **范围蔓延**：严格限定 v0.1 = 核心编辑 + macOS。

---

## 12. v0.1 之后（LATER）

已在 v0.1 之后补齐：**新建空文档**、**旋转手柄**、**复制/粘贴**、**导出 SVG/PNG**
（SVG 由恢复的 `VsdxToSvgSerializer` 纯模型序列化；PNG 由 `VsdxPainter` 光栅化）。

已补：**网格 + 吸附**、**未保存关闭拦截**、**最近文件**（shared_preferences）、
**连接器 glue**（连接两形状、移动自动重路由、`<Connects>` 往返）。

已补：多文件 Tab、多选（Shift 点选 + 框选）、对齐/分布、PDF 导出、**图层面板**（显隐切换，
写回 pages.xml 的 PageSheet，保真持久化）。

已补：文本格式化、方向键微调、**模具/形状库面板**（流程图常见形状：矩形/椭圆/菱形/平行四边形/
三角形/六边形/五边形/箭头，点击落到页面中心，多边形/椭圆几何往返安全）。

已补：多页管理（新增/复制/删除/重命名，Writer 按页 ID 匹配 + 增删 pageN.xml/rels/[Content_Types] 部件，往返）。

已补：**macOS 产品集成** —— 应用图标（`tool/gen_app_icon.dart` 可复现）、`.vsdx` OS 文件关联（UTI +
`CFBundleDocumentTypes`）、Finder 双击 / “打开方式” / `open` 启动即打开（原生 open 事件经
`MethodChannel` 交给 Dart）。

已补：**对齐 drawio 交互** —— 智能对齐辅助线（拖拽吸附邻近形状边/中心、连接点、等距间隔与页面中心，
蓝/紫/橙参考线，纯函数
`snap_guides.dart` 可单测）、右键上下文菜单、复制/粘贴样式、**分组/取消分组**（往返，Writer
重建 `<Shape>` 子树）、drawio 快捷键（全选/剪切/置顶置底/分组/复制粘贴样式）与画布键盘缩放。

已补：**格式面板对齐 drawio** —— 线条虚线样式（实线/虚线/点线/点划线）、箭头（起/止）、
填充/线条不透明度滑块；均往返（`LinePattern`/`BeginArrow`/`EndArrow`/`FillForegndTrans`/
`LineColorTrans`）。移动拖拽按住 Shift 锁定单轴。

已补：**连接器直线/正交路由**（每条连接器可选直线或正交肘形，`straightRoute` 标记随重路由保持）、
Ctrl/Cmd 拖拽复制；Alt/Option 在拖拽期间临时关闭吸附。

已补：**连接器可拖拽折点（waypoints）** —— 选中连接器显示折点（实心）与线段中点（空心）手柄：
拖中点新增折点、拖折点移动、双击折点删除；`VsdxShape.waypoints` + `VsdxPage.connectorRoute/
setConnectorWaypoints`，路由经折点且随重路由/移动保持（移动连接器时折点同步平移）。

已补：**文本 Format 面板补全 + 阴影** —— 字体族（下拉）、下划线、垂直对齐（上/中/下）、投影开关；
均往返（`Font`/`Style` 下划线位/`VerticalAlign`/`ShadowPattern`）。

已补：**Arrange 面板对齐 drawio** —— 数值位置/尺寸（X/Y/W/H）与旋转角输入、水平/垂直翻转、
旋转 90°（Cmd+R/Cmd+Shift+R）、单步 Bring Forward/Send Backward（补足既有置顶/置底）、
双形状交换位置、复制/粘贴尺寸及连接线反向；均往返（`PinX/PinY/Width/Height/Angle`、
`FlipX/FlipY`、`<Shape>` 重排、`<Connect>` 与 1-D 起止端）。

已补：**查找（Cmd+F）** —— 浮动查找条按当前页形状文本/名匹配，计数并循环（Enter/Shift+Enter），
选中并居中命中形状；**缩放到选区**（reveal 机制：控制器请求、画布 `_handleReveal` 居中/适配）。

已补：**箭头类型选择器** —— 起/止箭头改为类型下拉（无/实心/开口/细/隐形/菱形/圆等，带预览），
往返 `BeginArrow`/`EndArrow`。

已补：**悬停连线（drawio HoverIcons）** —— 选择工具下悬停形状显示四向连接箭头，从箭头拖出即新建连接器
（落到形状则两端胶合、落到空白则终点为落点），拖动中高亮目标形状；连接器工具拖动同样高亮落点目标。

已补：**画布拖拽细化** —— 移动时网格吸附（无邻居对齐轴回退到网格）、缩放 Shift 锁长宽比 / Alt 从中心缩放、
Esc 取消进行中的拖拽（回退到手势前状态、不记历史）。

已补：**默认样式继承（drawio currentVertexStyle）** —— 记忆最近应用的填充/线条，新建形状自动继承
（线/连接器仅取描边），记忆随文档重置。

已补：**圆角矩形** —— `EllipticalArcTo` 四角圆弧（Writer 新增弧线序列化，往返安全），属性面板 Corner radius
滑块可给任意矩形加/去圆角，形状面板含 Rounded 模具。

已补：**文本工具 + 边标签 + 连接器默认箭头（drawio）** —— 独立**文本工具**（`EditorTool.text` +
`VsdxShapeFactory.textBox`：无填充/无描边的矩形盒，创建后即进入画布内联编辑；未输入即提交/取消则自动删除，
drawio 行为）；**连接器边标签**——连接器文字绘制于**路由弧长中点**（`VsdxPage.connectorMidpoint` 单一真源，
画笔与内联编辑器共用）并加页色底衬，双击连接器即可标注；**新连接器默认末端箭头**（指向目标，描边继承记忆样式）；
画笔不再把内部占位名 `Sheet.N`（及 1-D 形状名）当作标签渲染。修复形状面板重复的 Rounded 模具。

已补：**页面格式面板（drawio "Diagram" 标签页）** —— 无选中时右侧常驻页面级设置面板：网格/吸附开关、
背景色板、**纸张尺寸预设**（Letter/Legal/Tabloid/A3–A6/B4–B5）+ 横/纵向切换（保持纸张尺寸交换宽高）+
自定义宽高数值字段；控制器 `setPageSize/setPageLandscape/setBackgroundColor` 与 `pageSize/pageIsLandscape/
pageBackgroundColor`，**Writer 补丁 PageSheet 的 `PageWidth`/`PageHeight`/`PageColor`**（新建 Cell 插到首个
Section 之前保持元素顺序，尊重原 Cell 单位）——完整往返。

已补：**Edit Data（drawio Cmd+M 形状数据）** —— 编辑单选形状的 Shape Data（Visio `<Section N="Property">`）：
独立 `lib/editor/edit_data_dialog.dart` 对话框（名/值行、增/删、Apply＝单撤销步），Cmd+M / 右键菜单 / More 菜单 /
属性面板 **Data 区**（读出当前属性 + "Edit Data…" 按钮）四处入口；控制器 `setShapeProperties`（去空名/去重）+
`selectedProperties`/`singleSelectedId`；**Writer 往返** —— `_patchUserProperties` 就地补丁现有行（按 `N` 名匹配、
保留未建模的 Cell，仅改 `Value`/`Label`/`Prompt`/`Format`/`Type`）、新增/删除行、清空则移除整节，新建形状经
`_buildPropertySection` 发射；`VsdxUserProperty` 加 `copyWith`/`==`/`hashCode`。

已补：**曲线连接器（drawio Curved edges）** —— 连接器路由样式从二态扩为**三态**（Straight / Orthogonal /
Curved）：`VsdxShape.curved`（会话级标记，同 `straightRoute`）；`VsdxPage.curveThrough`（Catmull-Rom 样条穿过
路由控制点，采样为密集折线，端点精确落在 begin/end）+ `_catmullRom`；`rerouteConnectors`/`setConnectorWaypoints`/
`setConnectorStyle`（加 `curved` 形参 + 尊重 waypoints）在 curved 时把控制点折线**烘焙为平滑折线几何**——因此
**渲染层与 Writer 零改动**（仍是 `MoveTo`/`LineTo`），且曲线**视觉往返一致**（几何本身即曲线采样点）；
`isConnectorCurved`。控制器加 `ConnectorRouteStyle{straight,orthogonal,curved}` 枚举、`selectedConnectorRouteStyle`/
`setConnectorRouteStyle`（保留 `setConnectorStyle(straight:)`/`selectedConnectorStraight` 兼容），属性面板连接器区
改**三选一** ChoiceChip。

已补：**超链接（drawio Edit Link / Cmd+K）** —— 编辑单选形状的超链接（Visio `<Section N="Hyperlink">`），解析器早已能读，
本批补齐编辑与**完整往返写回**。模型 `VsdxHyperlink` 加 `copyWith`/`==`/`hashCode`；**Writer** `_patchHyperlinks`
（按行 `IX` 就地补丁 Address/SubAddress/Description/Frame/NewWindow/Default，保留未建模 Cell，新增/删除行，清空移除整节）
+ `_buildHyperlinkSection`（新形状发射）+ `_hyperlinksEqual`（并补 `hyperlink.dart` 导入）；控制器 `selectedHyperlinks`/
`selectedLink`/`setShapeHyperlinks`（单撤销步）；新增对话框 `lib/editor/edit_link_dialog.dart`（Link 字段：`#` 前缀视为
页内锚点，否则外部地址；可选 Label；Apply/Remove/Cancel），入口＝**Cmd+K**、右键菜单 "Edit Link…"、⋯ More 菜单、
属性面板新增 **Link 区**（读出当前链接 + 按钮）。

已补：**Outline 缩略图导航面板（drawio 第三面板）** —— 补齐 drawio 三大面板（此前已有 Shapes 模具面板、Format
属性面板，独缺 Outline）。右下角常驻缩略图显示整页 + 当前视口矩形，点击/拖拽即把主画布重新居中到该处。实现：
轻量 `lib/editor/canvas_camera.dart`（`CanvasCamera` ChangeNotifier，PageCanvas **单向发布** scale/offset/viewport/content，
变化才通知；`visibleContentRect` 由变换反推可见 content-px 矩形）；PageCanvas 加可选 `camera` 参数并在 build 后发布，
`_handleReveal` 支持**任意页点定位**；控制器 `revealPagePoint(x,y)`（复用既有 reveal 机制、不改选择，`revealShape/
revealSelection` 会清除待定点）；`lib/editor/outline_panel.dart` 复用 `VsdxPainter` 画缩略图 + 视口框；`main.dart`
拥有 `CanvasCamera`、AppBar 加 Outline 开关、把画布包进 `Stack` 叠加面板。

已补：**标尺（drawio Rulers）** —— 画布顶部/左侧英寸标尺，复用 `CanvasCamera` 的变换随平移/缩放实时更新，
刻度用"nice-number"步长（任意缩放下标签不拥挤），并高亮当前选区的 X/Y 范围。实现：`lib/editor/ruler.dart`
纯函数 `niceRulerStepInches`（按屏幕每英寸像素选步长）+ `rulerTicksInches`（对齐原点生成刻度，封顶防极端缩放）、
`RulerOverlay`（`IgnorePointer` 不拦截画布手势，读 camera + 选区 AABB）+ `_RulerPainter`（刻度/标签/次刻度/选区高亮/角）；
`main.dart` 加 `_showRulers`（默认开）+ AppBar 开关（`Icons.straighten`）+ 画布 `Stack` 叠加（位于 Outline 之下）。

已补：**锁定/解锁形状（drawio Lock/Unlock，Cmd+L）** —— 选中形状可锁定；锁定后仍可选中，但不可移动/缩放/
旋转/删除/文本编辑/悬停连线（对齐 drawio locked 语义），选中框显示为**红色**且不显示缩放/旋转手柄。模型
`VsdxShape.locked`，**往返写回** Visio 保护 Cell（`LockMoveX/LockMoveY/LockWidth/LockHeight/LockAspect/
LockRotate/LockDelete/LockTextEdit`，解析以 `LockMoveX` 为代表位读回，含 master 继承）；入口＝Cmd+L、右键菜单、
⋯ More 菜单、属性面板 Arrange 区锁按钮（锁定时隐藏翻转/旋转/数值几何控件）。

已补：**插入图片（drawio Insert > Image）** —— 选本地栅格图片（png/jpg/gif/bmp/webp）→ 以其像素尺寸（96dpi）
定框、缩放适配页面 → 落到页面中心为 **picture 形状**（`VsdxShapeFactory.picture`，无描边/填充，`imagePartName` 指向
`/visio/media/imageN.ext`），媒体字节挂到 `VsdxDocument.images`（`ImageRegistry.withImage`）使画布**即时渲染**
（接入 `VsdxImageCache` 解码，此前图片仅显示占位框）。**完整往返写回**：Writer 检测新图片形状 → 嵌入 media 部件
（字节）+ 在页 rels 增图片关系（缺 rels 部件则新建，支持空文档/新页）+ 在 `[Content_Types]` 补扩展名 Default +
发射 `<Shape Type="Foreign">` 的 `<ForeignData><Rel r:id/></ForeignData>`（`imageRels` 参数按页透传给
`_buildShapeElement`，保持 `const VsdxWriter`）；解析器早已能读 ForeignData，故往返一致。控制器 `insertImage`
以**跨 undo 单调递增**的会话计数分配 `imageN` 部件名（避免重插时命中解码缓存旧图），入口＝工具栏图片按钮 + ⋯ More 菜单。

已补：**连接器端点重连/分离（drawio 端点编辑）+ 清除折点** —— 选中连接器时在其起/终点显示**绿色端点手柄**，
拖动即可：落到另一形状 → 重新胶合到该形状（重建 `<Connect>` 行）、落到空白 → **分离**为浮动端点（移除该端
`<Connect>` 行、端点定位到落点）；拖动中高亮目标形状，Esc 取消回退。引擎 `VsdxPage.setConnectorEndpoint`（重建
connects + 端点种子 + 重路由，胶合端由 `_edgePoint` 精修、浮动端用自身 begin/end）与 `clearConnectorWaypoints`；
控制器 `reconnectEndpoint`（transient 拖拽、提交单撤销步）、`clearSelectedConnectorWaypoints`/`canClearWaypoints`；
画布新增 `_DragMode.moveEndpoint`（优先于折点/命中测试）与 `_SelectionPainter.endpointHandles`，右键菜单
"Clear Waypoints"。**往返零改动**——完全复用现有 `<Connects>` + `BeginX..EndY` + 几何补丁。

已补：**固定连接点（drawio Fixed connection points）** —— 连接器端点可钉到目标形状的**固定连接点**（drawio 蓝色叉），
而非仅"整形状边缘吸附"。模型 `VsdxShape.connectionPoints`（形状局部英寸，origin 左下），解析 `<Section N="Connection">`
的 X/Y 行（含 master 继承）；`VsdxPage.localToPage`/`connectionPointPage`/`effectiveConnectionPoints`/
`defaultConnectionPoints`（无显式点时的标准 5 点：上/右/下/左/中），`fixedConnectionIndex`（`ToPart≥100 → 点索引`）；
`rerouteConnectors` 对固定点连接（`ToPart=100+k`）把端点定位到该点的页面坐标（含旋转/翻转），否则边缘吸附；
`setConnectorEndpoint` 加 `connectionPointIndex`（钉固定点时若目标无点则**物化标准 5 点**、写 `ToCell=Connections.X{k+1}`/
`ToPart=100+k`）。**Writer** 新建形状发射 Connection 节、`_patchConnectionPoints` 给现有形状补丁（物化时新增节、
保留未建模 Cell）。控制器 `reconnectEndpoint`/`createConnector` 加固定点参数；画布拖端点/连线时显示目标连接点（蓝叉）、
就近吸附（`_connSnapIndex`，半径 13px）并高亮，落点即钉固定点。完整往返。

已补：**形状库拖放 + 光标处粘贴（drawio 放置交互）** —— 形状库面板每个模具改为 `Draggable<Stencil>`
（`pointerDragAnchorStrategy`，拖动预览 + 拖动中原位淡化，点击仍落中心），画布用 `DragTarget<Stencil>` 接收，
经 `ClipRect` GlobalKey 把全局落点转画布坐标 → `EditorController.addShapeFromBuilderAt`（落点放置、网格吸附、继承记忆样式、
选中）。右键空白菜单加 **"Paste Here"** → `pasteAt(cx,cy)`（把剪贴板包围盒中心对齐到光标；`paste` 复用之，无坐标＝原偏移）。

已补：**圆角连接器（drawio "Rounded" 边）** —— 连接器路由拐角可**圆角化**：直角肘形/带折点路由的每个拐角用小段
二次贝塞尔圆角替代尖角。模型 `VsdxShape.rounded`（会话级标记，同 `curved`/`straightRoute` + copyWith）；引擎
`VsdxPage.roundCorners`（每个内部拐角沿相邻两段各回退 `radius`＝ min(radius, 较短邻段/2)，以拐点为控制点采样二次
贝塞尔，端点精确保留、<3 点原样返回）+ `_quadBezier`，并抽出**单一烘焙助手** `_bakeRoute`（curved 优先→rounded→
原样折线），接入 `rerouteConnectors`/`setConnectorStyle`/`setConnectorWaypoints`/`setConnectorEndpoint` 四处几何
烘焙点；新增 `setConnectorRounded(ids, bool)`（保留路由样式，从当前 begin/end/waypoints 重算并烘焙）与
`isConnectorRounded`。与 `curved` 同构——**渲染层与 Writer 零改动**（仍 `MoveTo`/`LineTo`）、圆角**完整往返**、随重路由/
移动保持；端点/折点手柄仍落在逻辑控制点（`connectorRoute`），curved 时圆角无意义（已平滑）。控制器
`selectedConnectorRounded`/`setConnectorRounded`（单撤销步）；属性面板 Connector 区在三选一 ChoiceChip 下加
**Rounded 开关**（curved 时禁用）。测试：引擎 2 例（`roundCorners` 圆角化+端点精确+拐点回退、圆角连接器烘焙折线且
经重路由保持）+ Writer 1 例（圆角连接器几何真实 `.vsdx` 往返，共 54）、控制器 1 例（圆角开关+重路由保持+撤销，App 共 52）。

剩余：
- macOS 代码签名 / 公证（notarization，需证书）；其他平台（Windows/Linux/Android/iOS）
- `.vsd` 加密 / masters 深编辑 / 写回二进制（产品决策：导入 → 另存 `.vsdx` only；不实现 OLE2 写回）

---

## 13. 决议记录（ADR 简化版）

- **ADR-1**：编辑引擎走**原生 Dart 往返**而非 libvisio。理由：libvisio 只读且输出有损扁平 IR，
  无法保真回写；`.vsdx` 是 OOXML/ZIP，可直接读写。
- **ADR-2**：**恢复**查看器已删除的纯 Dart 栈（`0fcaf66^`, MIT）作为起点，而非从零重写。理由：
  约 50 个成熟文件覆盖 model/parser/render，省时且经过验证。
- **ADR-3**：引擎作为独立包 `packages/vsdx`（纯 Dart，无 Flutter），便于无 Flutter 单测与复用。
- **ADR-4**：Writer 采用 **load-preserve-patch** 为主、emit-from-scratch 为辅，最大化往返保真。

---

## 进度日志

- 2026-07-10 — E0 启动：`git init`（main）；改 macOS 品牌名；克隆 vsdx/libvisio/drawio 到
  third_party 并记录；建 `packages/vsdx` 骨架与依赖，`flutter pub get` 通过；迁入格式文档，
  编写 PLAN/ARCHITECTURE/VSDX_WRITE/REUSE_MAP。
- 2026-07-10 — E1 完成：从 `0fcaf66^` 恢复 core/utils/model(18)/parser(21) 到 `packages/vsdx`，
  render(10) 到 `lib/render`；`dart analyze` 干净，`dart test` 4/4 通过（OPC 打开 / 非空文档 /
  矩形+线几何 / 连接器）。
- 2026-07-10 — E2 完成：新增 `lib/editor/{editor_controller,page_canvas}.dart` 与
  `lib/io/document_io.dart`，重写 `lib/main.dart` 为编辑器外壳（打开/拖放/多页/空态）；
  `flutter analyze` 零问题、`flutter test` 通过、`flutter build macos --debug` 成功。
- 2026-07-10 — E3 启动：着手模型 `copyWith` 与选择/变换/命令栈。
- 2026-07-10 — E3 核心完成：模型 `copyWith`/`updateShapeById`/`replacePage`；`EditorController`
  选择+事务式撤销/重做+移动；`PageCanvas` 改手动视图变换（点选/拖动移动/拖空白平移/滚轮缩放平移）
  与选择叠加层；工具栏撤销/重做与脏标记；引擎编辑单测 4/4，`flutter analyze` 零问题。
  缩放/旋转手柄交互留待 Slice-0 后补。
- 2026-07-10 — **E4 完成 / Slice-0 达成**：新增 `packages/vsdx/.../writer/vsdx_writer.dart`
  （load-preserve-patch）；`units.dart` 加 `fromInches`/`fromRadians`；`EditorController`
  `exportToBytes`/`markSaved`，`document_io` 保存对话框，`main` 工具栏 Save/Save As。
  Writer 单测 3/3（编辑往返、未编辑无损、no-op 保留全部 part），引擎共 11/11；
  `flutter analyze` 零问题、`flutter test` 通过。LibreOffice 交叉验证待装 soffice。
- 2026-07-10 — **E5 完成（核心）**：`shape_factory` + 页增删/新 ID；Writer 扩展新增/删除 Shape
  与样式/文本补丁；`VsdxFill/VsdxLine.copyWith`；`EditorController` 工具/创建/删除/样式/文本；
  `PageCanvas` 工具创建拖拽+预览、双击文本、Delete/Esc 键；`main` 工具条 + 属性面板 + 文本对话框。
  引擎单测 14/14，`flutter analyze` 零问题、macOS 构建成功。连接器 glue 与新建文档留后续。
- 2026-07-10 — E6 启动：着手新建文档、复制/粘贴、键盘快捷键、CHANGELOG/NOTICE、打包。
- 2026-07-10 — **E3b 缩放完成**：`scalePathCommand`（几何按比例缩放）+ `VsdxShape.resizeTo`；
  `PageCanvas` 8 向缩放手柄（单选、非旋转、非 1D），精确包围盒绘制与命中；引擎单测 15/15。
  旋转手柄留待后续。
- 2026-07-10 — **E6 关键项完成**：键盘快捷键（Cmd+S/Z/Shift+Z/D、Delete、Esc）、复制选中、
  `docs/CHANGELOG.md`、根 `NOTICE`。`flutter analyze` 零问题、`flutter test` 通过、
  `flutter build macos` 成功。
- 2026-07-10 — **v0.1+ 增补**：新建空文档（`VsdxWriter.emptyDocument` + `newDocument`，Cmd+N）、
  旋转手柄（`rotateShape` + Writer `Angle` 补丁）、复制/粘贴（Cmd+C/V）。引擎单测 17/17
  （新增空文档 emit + 旋转往返），`flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **导出**：从查看器历史恢复 `svg_serializer`（纯模型 → `packages/vsdx/.../export/`）；
  新增 `lib/io/image_export.dart`（`VsdxPainter` 光栅化 PNG）；菜单 Export as SVG/PNG。
  引擎单测 19/19（+SVG），`flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **编辑 UX**：网格 + 吸附（创建/缩放对齐 0.25in，可切换）、未保存关闭/新建/打开拦截、
  最近文件（`lib/io/recent_files.dart` + shared_preferences，AppBar 历史菜单）。
  `flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **连接器 glue**：连接器工具（拖两形状间）、端点吸附到形状中心、`<Connect>` 行；
  `VsdxShape.reshapeAsLine` + `VsdxPage.rerouteConnectors`（移动/缩放/旋转后自动重路由）；
  Writer 同步 `<Connects>`。引擎单测 21/21（+重路由 +Connects 往返），macOS 构建成功。
- 2026-07-10 — **首次提交基线**（`168660a`）。随后：将参考 `vsdx`(BSD) 的 20 个示例复制到
  `packages/vsdx/test/fixtures/`（README 注明来源/许可），并把 6 个作为可打开的内置资源放到
  `assets/examples/`（pubspec 登记）。
- 2026-07-10 — **多文件 Tab（工作区）**：新增 `lib/editor/editor_workspace.dart`（多 `EditorController`
  + 活动标签，转发子通知）；`main.dart` 重构为顶部文件标签栏（脏标记+关闭、Cmd+W）、动作路由到
  活动文档、空态示例快捷打开、多文件拖放各开一个标签、Cmd+N/O/W 快捷键。`flutter analyze` 零问题、
  `flutter test` 通过、macOS 构建成功。
- 2026-07-10 — **多选 + 对齐/分布**：Shift 点选切换、空白拖拽框选（Space+拖拽平移）；控制器
  `setSelection` 与 `alignLeft/CenterH/Right/Top/Middle/Bottom` + `distributeHorizontally/Vertically`
  （含旋转形状 AABB、对齐后重路由连接器）；属性面板 Align 区（选中≥2 显示，≥3 显示分布）。
  macOS 构建成功。
- 2026-07-10 — **PDF 导出**：新增 `pdf` 依赖与 `lib/io/pdf_export.dart`（逐页光栅化嵌入、按英寸
  尺寸排版）；菜单 Export as PDF。`flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **图层面板**：控制器 `toggleLayerVisibility`/`hasLayers`；Writer 扩展为补丁
  `pages.xml` 的 PageSheet `Section N="Layer"` 的 Visible/Lock/Print（保真持久化）；AppBar 图层
  按钮 + 对话框开关。引擎单测 22/22（+图层往返），macOS 构建成功。
- 2026-07-10 — **连接器 L 形路由 + 几何写回修复**：`VsdxShape.reshapeAsPolyline`；`rerouteConnectors`
  用正交 elbow 路由；**Writer 新增几何补丁**——现有形状几何变化（缩放/连接器改形）时重写
  `Section N="Geometry"`（可表示的命令），修复重开后几何走样。引擎单测 24/24（+elbow +缩放几何往返），
  macOS 构建成功。
- 2026-07-10 — **文本格式化**：富文本模型 copyWith；控制器 `setTextSizeInches/setBold/setItalic/
  setTextColor/setTextAlign`（作用于选中形状全部 run，空 run 时从 text 合成）；Writer 写回
  `Character`(Size/Style/Color) 与 `Paragraph`(HorzAlign)，缺节则创建；属性面板 Text 区（字号下拉、
  B/I、色板、对齐）。引擎单测 25/25（+文本格式化往返），macOS 构建成功。
- 2026-07-10 — **方向键微调**：选中后方向键按网格步长移动（一次一步撤销，重路由连接器）。
- 2026-07-10 — **模具/形状库面板**：`VsdxShapeFactory.polygon`（单位多边形）；`lib/editor/stencils.dart`
  内置 8 个流程图形状；控制器 `addShapeFromBuilder`（落到页面中心并选中）；AppBar 形状面板开关 +
  左侧 `_StencilPanel`。引擎单测 26/26（+多边形往返），macOS 构建成功。
- 2026-07-10 — **Z 顺序**：`VsdxPage.bringToFront/sendToBack`；控制器 `bringSelectionToFront/
  sendSelectionToBack`；Writer 按模型顺序重排 `<Shape>` 元素（往返）；属性面板置顶/置底按钮。
  引擎单测 27/27（+Z 顺序往返），macOS 构建成功。
- 2026-07-10 — **连接器边缘吸附**：`rerouteConnectors` 端点吸到形状包围盒边缘（朝对端方向的射线
  交点，`_edgePoint`），而非中心；连接线不再插入形状，观感更接近 Visio。引擎单测 27/27，macOS 构建成功。
- 2026-07-10 — **页重命名**：控制器 `renamePageAt`；Writer `_patchPageNames` 写回 `<Page NameU/Name>`；
  页标签双击弹出重命名对话框。引擎单测 28/28（+页重命名往返），macOS 构建成功。
- 2026-07-10 — **多页管理（新增/复制/删除）**：Writer 重构为**按页 ID 匹配**（不再按索引），支持
  删除页（移除 `<Page>`/relationship/`<Override>`/pageN.xml 部件）、新增页（生成新部件 + 关系 +
  内容类型 + `<Page>`）、按编辑顺序重排 `<Page>`；`_rezip` 支持新增/删除部件。模型 `nextPageId/
  insertPage/removePageAt`；控制器 `addPage/duplicateCurrentPage/deleteCurrentPage`；页栏常显 + 新增/
  复制/删除按钮。引擎单测 30/30（+新增页往返 +删除页往返），`flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **macOS 产品集成（E6 收尾，先整体）**：(1) `.vsdx` 文件关联——`Info.plist` 增
  `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`（`com.microsoft.visio.drawing`，6 个扩展）；
  (2) 启动即打开——`AppDelegate.application(_:open:)` + `FileOpenBridge`（同文件定义，免改 pbxproj；
  冷启动缓冲、Dart `ready` 后刷新）+ `MainFlutterWindow` 建 `MethodChannel('visioeditor/files')`，
  `main.dart` 监听 `openFiles`→`_openPath`（仅 macOS，`defaultTargetPlatform` 守卫）；
  (3) **应用图标**——`tool/gen_app_icon.dart`（`image` 包高分辨率渲染 + 平均降采样抗锯齿）替换默认
  Flutter logo（7 尺寸）。`flutter analyze` 零问题、`flutter test` 通过、`flutter build macos` 成功；
  `lsregister -dump` 确认 claimed UTI/Editor 角色/6 扩展绑定生效。
- 2026-07-10 — **编辑器 UX 细节**：浮动缩放控件显示缩放百分比（点击=适应窗口）；底部状态栏
  （页面尺寸 / 第 N 页共 M 页 / 未保存标记 / 选中数）。`flutter analyze` 零问题、macOS 构建成功。
- 2026-07-10 — **就地文本编辑 + v0.1 发布说明（先整体后细节）**：(1) **整体**——新增
  `docs/RELEASE_NOTES.md`（亮点/运行/快捷键/已知限制/验证），补齐 E6 发布说明项；README 文档
  导航加 RELEASE_NOTES/CHANGELOG；确认当前状态 `flutter build macos` 端到端通过。(2) **细节**——
  `PageCanvas` 把双击文本编辑从模态对话框改为**画布上叠加编辑器**（按形状框定位/缩放、
  Enter 换行、Cmd/Ctrl+Enter 或点击别处提交、Esc 取消、失焦即提交），移除 `onRequestTextEdit`
  与 `main._editText`；`EditorController.setShapeText` 同步 richText run 文本，使渲染（优先
  richText）即时 WYSIWYG 且无变更时不产生撤销步。App 组件测试新增就地编辑往返用例（含双击/
  提交/取消）。`flutter analyze` 零问题、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-10 — **对齐 drawio 交互（批次一）**：(1) **智能对齐辅助线**——新增纯函数
  `lib/editor/snap_guides.dart`（`computeSnap`：移动包围盒的边/中心对齐邻近形状，阈值内吸附并
  给出洋红辅助线），`PageCanvas` 移动拖拽改走 `_applyMove`（按起始包围盒 + 累计位移计算吸附增量，
  `_SelectionPainter` 画辅助线）；纯单测 5 例。(2) **右键上下文菜单**——`onSecondaryTapUp` →
  `showMenu`：剪切/复制/粘贴/复制副本/删除、置顶/置底、复制样式/粘贴样式、编辑文本；空白处
  粘贴/全选/适应窗口。(3) **复制/粘贴样式**——`EditorController.copyStyle/pasteStyle`（填充/线条/
  文本 run 样式，单撤销步）。(4) **快捷键对齐**——Cmd+A 全选、Cmd+X 剪切、Cmd+Shift+F/B 置顶置底、
  Cmd+Alt+C/V 复制/粘贴样式；画布内键盘缩放（Cmd +/- 、Home=100%、Cmd+Shift+H=适应）。App 测试
  加右键菜单用例（共组件 3 + snap 单测 5）。`dart analyze` 零问题、`flutter test`（--no-pub）通过、
  `flutter build macos` 成功。
- 2026-07-10 — **对齐 drawio 交互（批次二）——分组 / 取消分组**：引擎 `VsdxPage.group/ungroup`
  （成员转为组局部坐标 / 提升回页面绝对坐标，含旋转/翻转折算）+ Writer 支持“改父”（重建
  `<Shape>` 子树，按最高变化层插入）+ 往返单测；`EditorController.groupSelection/ungroupSelection`
  与 `canGroup/canUngroup`；UI 接线——Cmd+G / Cmd+Shift+U、右键菜单 Group/Ungroup、属性面板
  分组/取消分组按钮。控制器单测（分组往返 / 分组撤销 / 复制粘贴样式）。引擎 31/31、App 组件+单测
  11/11、`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次三）——格式面板 + 移动约束**：模型/渲染/解析器本就支持
  线条虚线（`LinePattern`）、箭头（`BeginArrow`/`EndArrow`）、不透明度（`FillForegndTrans`/
  `LineColorTrans`），本批补齐 **Writer 补丁**（新增 `_patchRatio` 写 0..1 比值，去 F/E）、
  **控制器** `setLinePattern/setLineArrows/setFillOpacity/setLineOpacity`（不透明度支持事务=单撤销步）
  与 `selectedLine/selectedFill`、**属性面板**（虚线下拉 / 起止箭头开关 / 填充·线条不透明度滑块）。
  画布移动拖拽按住 Shift 锁定主轴（`_applyMove`）。测试：引擎线型往返 1 例（共 32/32）、控制器线型
  设置 1 例（App 共 12/12）。`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次四）——连接器直线/正交路由 + 拖拽复制**：模型加
  `VsdxShape.straightRoute`（默认 false=正交肘形，保持既有默认）；`VsdxPage.rerouteConnectors`
  依据该标记选直线或肘形，新增 `setConnectorStyle/isConnectorStraight`；`EditorController`
  `hasConnectorSelected/selectedConnectorStraight/setConnectorStyle`；属性面板“Connector”区
  （Straight/Orthogonal 选择）。画布拖拽复制后续已校正为 draw.io 的 Ctrl/Cmd 拖拽；
  Alt/Option 用于临时绕过吸附。控制器单测（切换直/正交并经重路由保持）。
  `dart analyze` 干净、引擎 32/32、App 13/13、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次五）——连接器可拖拽折点（waypoints）**：模型加
  `VsdxShape.waypoints`（页面英寸，默认空）；`VsdxPage.connectorRoute`（begin→waypoints→end 或
  直线/肘形）+ `setConnectorWaypoints`（重建几何 + 重路由，胶合端点由 reroute 重算）；reroute 优先
  经折点；`EditorController` `connectorWaypoints/addWaypoint/moveWaypoint/removeWaypoint`（`_translated`
  同步平移折点）。画布：选中连接器画折点（实心）/中点（空心）手柄，`_tryStartWaypointDrag`（拖中点=
  新增并促成显式折点、拖折点=移动、双击=删除），新增 `_DragMode.moveWaypoint`。控制器单测（增/移/删
  折点并经胶合形状移动保持）。`dart analyze` 干净、引擎 32/32、App 14/14、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次六）——文本 Format 面板补全 + 阴影**：模型加
  `VsdxTextBlock.copyWith`；Writer 补 `Font`（字体族）、`VerticalAlign`（垂直对齐）、`ShadowPattern`
  （投影开关）补丁，`_richTextEqual` 纳入 fontFamily（下划线位本已写）；`EditorController`
  `setUnderline/setFontFamily/setTextVerticalAlign/setShadow` 与 `selectedVerticalAlign/selectedHasShadow`；
  属性面板：Text 区加下划线按钮、字体下拉、垂直对齐三键，另加 Shadow 开关。测试：引擎往返 1 例
  （字体/下划线/垂直对齐/投影，共 33/33）、控制器 1 例（App 共 15/15）。`dart analyze` 干净、
  `flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次七）——Arrange 面板（数值几何 + 翻转 + 旋转 90° + 单步 Z 序）**：
  模型 `VsdxPage.bringForward/sendBackward`（单步交换 Z 序，往返用既有 `_reorderShapes`）；
  `EditorController` `bringSelectionForward/sendSelectionBackward`、`singleSelected/selectedGeometry`
  （X/Y/W/H 以左上角+Y-down 呈现）、`setSelectedX/Y/Width/Height`（W/H 走 `resizeTo` 保左/上边）、
  `setSelectedAngleDegrees`、`rotateSelection90({clockwise})`（Visio CCW，Cmd+R/Cmd+Shift+R）、
  `flipHorizontal/flipVertical`（切 `flipX/flipY`，Writer 本已补 FlipX/FlipY，画笔已渲染）。UI：属性面板
  新增 Arrange 区（翻转/旋转按钮 + `_NumField` 数值字段，随模型同步、失焦/回车提交），顶部动作行加单步
  前/后移，动作行改 `Wrap` 防溢出；右键菜单加 Bring Forward/Send Backward。测试：控制器 2 例（翻转/旋转90/
  数值几何、单步 Z 序）、引擎 2 例（翻转往返、单步 Z 序往返，共 35/35）；widget 测试改用限定于 PageCanvas
  的内联编辑器 finder（避开 Arrange 数值框）。`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次八）——查找（Cmd+F）+ 定位/缩放到选区**：`EditorController`
  查找态（`updateFind/findNext/findPrevious/clearFind`、`findMatchCount/findCurrentOrdinal`，按当前页
  形状文本/名匹配，选中并定位每个命中）与 reveal 机制（`revealSerial/revealShapeId`、`revealShape/
  revealSelection`，切页/重置时清查找态）；`PageCanvas` 监听 `revealSerial`，`_handleReveal`+`_revealContent`
  居中命中形状、或缩放适配整选区（`buildShapeBounds`→content-px）。UI：浮动 `_FindBar`（搜索框+计数+上一/
  下一+关闭，Enter/Shift+Enter 循环、Esc 关闭），Cmd+F 打开，More 菜单加 Find/Zoom to Selection。测试：
  控制器 1 例（匹配/选中/循环/清除，App 共 18/18）。`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 交互（批次九）——箭头类型选择器**：`EditorController` `setBeginArrow/setEndArrow`
  （委托 `setLineArrows`）；属性面板把起/止箭头开关换成**类型下拉**（无/实心/开口/细/隐形/菱形/圆等，
  含 `_ArrowPreview` 小预览，用 `arrow_library` 的 `arrowDescriptor` 绘制；未知 id 动态并入列表）。往返走
  既有 `BeginArrow/EndArrow` 整数补丁。测试：控制器 1 例（起/止箭头类型设置，App 共 19/19）。`dart analyze`
  干净、`flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 画布（批次十）——悬停连线（HoverIcons）+ 连接目标高亮**：`PageCanvas` 加
  `MouseRegion` 悬停跟踪（`_onHover/_topLevelAt`），选择工具下把光标停在形状上时在其包围盒四周画方向连接
  箭头（`_connectArrows`，画布内 content-px 绘制、随缩放定尺寸），从箭头拖出即以该形状为起点新建连接器
  （新 `_DragMode.connect`，落到另一形状则两端胶合、落到空白则终点为落点），拖动中高亮光标下的目标形状；
  连接器工具拖动时同样高亮落点目标。渲染在 `_SelectionPainter` 加 `hoverBox/hoverArrowGap/connectTargetRect`。
  底层复用既有 `createConnector(beginTarget,endTarget)` 胶合与 `<Connects>` 往返。`dart analyze` 干净、
  `flutter build macos` 成功。
- 2026-07-11 — **对齐 drawio 画布（批次十一）——拖拽细化**：移动拖拽在无邻居对齐轴上**吸附到网格**
  （`_applyMove` 增网格回退，尊重 `snapToGrid`）；缩放手柄 **Shift 锁定长宽比**（角手柄，按拖动角的对角
  锚定或按中心）、**Alt 从中心缩放**（`_applyResize` 以拖拽起始快照 `_resizeStartShape` 计算，保持全程稳定）；
  **Esc 取消进行中的拖拽**（`EditorController.cancelTransaction` 回退到手势前快照、不记历史；画布
  `_cancelActiveDrag` 复位所有拖拽态）。测试：控制器 1 例（cancelTransaction 回退且不产生撤销步，App 共
  20/20）。`dart analyze` 干净、引擎 35/35、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十二）——默认样式继承（currentVertexStyle）**：`EditorController`
  记忆最近应用的填充/线条（`_memoFill/_memoLine`，样式 setter 与 pasteStyle 经 `_updateSelectedShapes(...,
  rememberStyle: true)` 更新），新建形状（`createShapeByDrag`/`addShapeFromBuilder`）经 `_withMemoStyle`
  继承之（线/连接器仅取描边、不加填充）；记忆随文档重置（`_resetHistory`）。测试：控制器 1 例（新矩形继承
  填充+线条、新线仅继承描边，App 共 21/21）。`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十三）——圆角矩形（弧线往返）**：`VsdxShapeFactory.roundedRectGeometry/
  roundedRectangle`（四角 `EllipticalArcTo` 四分圆，控制点取 45° 弧中点）；**Writer 支持 `EllipticalArcTo`**
  （`_buildRow` 写 X/Y/A/B/C/D、`_canRebuild` 放行），解析器本已读 `EllipticalArcTo`、渲染以二次贝塞尔近似，
  故往返安全；`EditorController` `_isRectangleLike`（仅直线段+角弧、轴对齐，排除菱形/三角）、`selectedCornerRadius`、
  `setCornerRadius`（重生几何，0=方角）；属性面板加 **Corner radius 滑块**（单选矩形时显示，事务=单撤销步），
  形状面板加 **Rounded 模具**。测试：引擎 1 例（圆角矩形 4 弧往返，共 36/36）、控制器 1 例（加圆角/复位方角，
  App 共 22/22）。`dart analyze` 干净、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十四）——文本工具 + 边标签 + 连接器默认箭头**：引擎
  `VsdxShapeFactory.textBox`（无填充/无描边、仅绘制文字的矩形盒，保留几何以便后续可加背景/边框）+
  `VsdxPage.connectorMidpoint`（路由弧长中点，边标签定位单一真源）；`EditorController` 新增
  `EditorTool.text`（`createShapeByDrag` 文本分支，不继承记忆样式）、`createConnector` 默认末端箭头
  （`endArrow:4`，描边取记忆样式）、`deleteShapeById`/`isBlankTextBox`（空文本盒清理）；`PageCanvas`
  文本工具点击/拖拽创建后即内联编辑（`_startEditingNewTextBox`），空提交/取消自动删除，内联编辑器对连接器
  定位到路由中点，文本光标；`VsdxPainter` 连接器文字绘制于路由中点 + 页色底衬，且不再把 `Sheet.N`/1-D
  形状名当标签渲染。UI 加文本工具按钮、去除重复 Rounded 模具。测试：引擎 `connectorMidpoint` +
  文本盒往返（共 38/38），控制器文本工具/连接器箭头/`deleteShapeById`（App 共 25/25）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十五）——页面格式面板（"Diagram" 标签页）**：`EditorController`
  `setPageSize`（钳制 1..400in，改 `PageWidth/PageHeight`）、`setPageLandscape`（交换宽高保持纸张尺寸）、
  `setBackgroundColor`（改 `PageColor`）与 `pageSize/pageIsLandscape/pageBackgroundColor` 读取器（均走
  `updateCurrentPage`＝单撤销步）；**Writer** 新增 `_patchPageProperties`（差异时补丁 PageSheet 的
  `PageWidth`/`PageHeight`（尊重原单位）/`PageColor`，`_ensurePageSheet`/`_ensurePageSheetCell` 保证元素顺序），
  `_buildPageIndexElement` 新增页也带 `PageColor`；解析器本就从 PageSheet 读这三项，故完整往返。**UI** 把右侧
  Format 面板改为常驻——有选中显示 `_PropertyPanel`，无选中显示新的 `_PageFormatPanel`（网格/吸附开关、背景色板、
  纸张尺寸下拉 + Portrait/Landscape 分段 + W/H 数值字段）；`_SwatchButton` 加选中高亮。测试：引擎 1 例（页面尺寸+
  背景色往返，共 39/39）、控制器 1 例（尺寸/方向/背景 + 撤销，App 共 26/26）。`dart analyze` 干净（app + 引擎）、
  `flutter test` 通过、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十六）——Edit Data（形状数据 / Cmd+M）**：模型 `VsdxUserProperty` 加
  `copyWith`/`==`/`hashCode`；`EditorController` `setShapeProperties`（去空名+去重，单撤销步）、`selectedProperties`、
  `singleSelectedId`；**Writer** `_patchUserProperties`（`<Section N="Property">` 就地补丁：按 `N` 名匹配现有行、
  保留未建模 Cell、仅改 Value/Label/Prompt/Format/Type，新增/删除行、清空移除整节）+ `_buildPropertySection`
  （新建形状发射）+ `_maxRowIx`/`_userPropsEqual`。UI：新增 `lib/editor/edit_data_dialog.dart`（名/值行 + 增删 +
  Apply），入口＝Cmd+M、右键菜单 "Edit Data…"、More 菜单、属性面板新增 **Data 区**（属性读出 + 按钮）。测试：
  引擎 1 例（形状数据创建/改值/新增/删除往返，共 40/40）、控制器 1 例（设值/去重/撤销，App 共 27/27）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十七）——曲线连接器（Curved edges）**：连接器路由样式扩为三态
  （Straight/Orthogonal/Curved）。模型 `VsdxShape.curved`（会话级，同 `straightRoute`）+ copyWith；
  `VsdxPage.curveThrough`（Catmull-Rom 样条穿过路由控制点，`segmentsPerSpan` 采样密度，端点精确、<3 点原样返回）
  + `_catmullRom`；`rerouteConnectors`/`setConnectorWaypoints`/`setConnectorStyle`（`setConnectorStyle` 加 `curved`
  形参并尊重 waypoints）在 curved 时把控制点折线**烘焙为平滑折线几何**——`MoveTo`/`LineTo` 采样点，故
  **渲染层（path_builder/vsdx_painter）与 Writer 零改动**，曲线**视觉往返一致**（几何即曲线采样点，`_canRebuild`
  已放行）；`isConnectorCurved`。控制器 `ConnectorRouteStyle{straight,orthogonal,curved}` 枚举 +
  `selectedConnectorRouteStyle`/`setConnectorRouteStyle`（保留旧二态 `setConnectorStyle(straight:)`/
  `selectedConnectorStraight` 兼容）；`main.dart` 属性面板连接器区改**三选一** ChoiceChip。测试：引擎 2 例
  （`curveThrough` 采样穿过控制点/端点精确/点数、曲线连接器烘焙折线且经重路由保持）+ Writer 1 例（曲线连接器
  几何真实 `.vsdx` 往返，共 43/43）、控制器 1 例（三态切换 + 曲线密度 + 重路由保持，App 共 28）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十八）——超链接（Edit Link / Cmd+K）**：编辑形状超链接（Visio
  `<Section N="Hyperlink">`），解析器早已能读，本批补齐编辑与完整往返。模型 `VsdxHyperlink` 加
  `copyWith`/`==`/`hashCode`；**Writer** `_patchHyperlinks`（按行 `IX` 就地补丁标准 Cell、保留未建模 Cell、增删行、
  清空移除整节）+ `_buildHyperlinkSection`（新形状发射）+ `_hyperlinksEqual`，并补齐缺失的 `../model/hyperlink.dart`
  导入（修复引擎编译错误）；控制器 `selectedHyperlinks`/`selectedLink`/`setShapeHyperlinks`（单撤销步）；新增
  `lib/editor/edit_link_dialog.dart`（Link 字段——`#` 前缀＝页内锚点、否则外部地址、可选 Label、Apply/Remove/Cancel），
  入口＝Cmd+K、右键菜单、⋯ More 菜单、属性面板 **Link 区**（读出当前链接 + 按钮）。测试：引擎 1 例（超链接
  创建/改址/移除往返，共 44/44）、控制器 1 例（设/清/撤销，App 共 29）。`dart analyze` 干净（app + 引擎）、
  `flutter test` 通过、`flutter build macos` 成功。
- 2026-07-12 — **对齐 drawio（批次十九）——Outline 缩略图导航面板**：补齐 drawio 三大面板（Shapes + Format +
  **Outline**）。新增 `lib/editor/canvas_camera.dart`（`CanvasCamera` ChangeNotifier：PageCanvas 单向发布
  scale/offset/viewport/content，变化才通知；`visibleContentRect` 反推可见 content-px 矩形）；PageCanvas 加可选
  `camera` 参数、build 后发布变换、`_handleReveal` 支持任意页点定位；控制器 `revealPagePoint(x,y)`（`Offset2D`
  存点，复用 reveal 机制、不改选择，`revealShape/revealSelection` 清除待定点）；新增 `lib/editor/outline_panel.dart`
  （复用 `VsdxPainter` 画整页缩略图 + 视口框，点击/拖拽 → `revealPagePoint`）；`main.dart` 拥有 `CanvasCamera`、
  AppBar 加 Outline 开关（`Icons.map_outlined`）、画布包进 `Stack` 右下角叠加 `OutlinePanel`。测试：`CanvasCamera`
  3 例（视口矩形映射、变化才通知、未布局为空）+ 控制器 1 例（`revealPagePoint` 居中不改选择、被 shape reveal 清除，
  App 共 33）。`flutter analyze` 干净、`flutter test` 通过、`flutter build macos` 成功。纯 UI 特性（无引擎往返改动）。
- 2026-07-12 — **对齐 drawio（批次二十）——标尺（Rulers）**：画布顶部/左侧英寸标尺，复用上批 `CanvasCamera`
  随平移/缩放实时更新，并高亮选区范围。新增 `lib/editor/ruler.dart`：纯函数 `niceRulerStepInches`（按屏幕每英寸
  像素从"nice"梯度选步长）+ `rulerTicksInches`（对齐原点生成刻度、封顶）、`RulerOverlay`（`IgnorePointer` 不拦截
  手势，读 camera + `buildShapeBounds` 算选区 content-px AABB）+ `_RulerPainter`（带/刻度/次刻度/标签/选区高亮/角，
  垂直标签旋转 90°）；`main.dart` 加 `_showRulers`（默认开）、AppBar 开关（`Icons.straighten`）、画布 `Stack` 叠加
  （置于 Outline 之下）。测试：纯函数 7 例（`niceRulerStepInches` 4 + `rulerTicksInches` 3，App 共 40）。`flutter analyze`
  干净、`flutter test` 通过、`flutter build macos` 成功。纯 UI 特性（无引擎往返改动）。
- 2026-07-12 — **对齐 drawio（批次二十一）——锁定/解锁形状（Lock/Unlock，Cmd+L）**：模型 `VsdxShape.locked`
  （copyWith，默认 false）；解析器读 `LockMoveX` 代表位（含 master 继承）→ locked；**Writer** `_patchLock`
  （locked 翻转时批量补丁 `LockMoveX/LockMoveY/LockWidth/LockHeight/LockAspect/LockRotate/LockDelete/
  LockTextEdit` 为 1/0，仅在标记变化时写）+ `_buildShapeElement` 新形状按需发射这组保护 Cell。控制器
  `selectionLocked`/`toggleLock`/`setSelectionLocked`，并把**移动/删除/旋转/翻转**改为逐形状跳过 locked
  （`moveSelectionBy`/`deleteSelection`/`deleteShapeById`/`rotateSelection90`/`flipHorizontal/Vertical`，无变化
  时返回原页不记历史）。画布：`_resizableSelection`/`_rotatableSelection` 对 locked 返回 null（隐藏缩放/旋转手柄）、
  `_beginTextEdit` 拒绝 locked、hover-connect（`_onHover`/`_onPanStart`）跳过 locked、选中框在全 locked 时画**红色**
  （`0xFFE53935`，对齐 drawio）。UI：Cmd+L 快捷键、右键菜单 Lock/Unlock、⋯ More 菜单项、属性面板 Arrange 区
  `lock`/`lock_open` 切换按钮（locked 时隐藏翻转/旋转/数值几何字段）。测试：引擎 2 例（lock/unlock 往返、新 locked
  形状发射保护 Cell，共 46/46）、控制器 2 例（锁定拒绝移动/旋转/删除 + 撤销、混合选择仍移动未锁成员，App 共 42）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-13 — **对齐 drawio（批次二十二）——插入图片（Insert > Image）**：模型 `ImageRegistry.withImage`
  （不可变追加）+ `VsdxImage.mimeForExtension` + `VsdxShapeFactory.picture`（无描边/填充、仅 `imagePartName` 的
  XForm 盒）；**Writer** 新增图片嵌入——`write` 前置读 `[Content_Types]`，对每页新图片形状经 `_prepareImageParts`
  嵌入 media 部件字节（`pkg.readPartBytes==null` 判新）、在页 rels 加 `/image` 关系（`_relsPartFor`，缺部件则建，
  Target=`../media/imageN.ext`）、补扩展名 `<Default>` 内容类型，返回 `{part→rId}` 经 **`imageRels` 参数**透传
  `_patchPage`/`_buildPageContentsXml`→`_buildShapeElement`（保持 `const VsdxWriter`、无实例状态）；新增
  `_buildPictureElement` 发射 `<Shape Type="Foreign">`＋`<ForeignData ForeignType="Bitmap"><Rel r:id/></ForeignData>`
  （解析器 `_resolveForeignDataPart` 早已能读，往返一致）。**渲染**：`PageCanvas` 接入 `VsdxImageCache`（`super(repaint:)`
  末端解码即重绘），并按控制器新增的 **`documentEpoch`**（仅 open/new/close 自增）在换文档时清缓存，避免复用 `imageN`
  串图；此前图片仅占位框，现真实显示。**控制器** `insertImage`（跨 undo 单调递增会话计数分配部件名、按页缩放适配、
  单撤销步、选中并回选择工具）；`document_io.pickImageFile`（file_picker 过滤栅格图）；`main` 工具栏图片按钮 + ⋯ More
  菜单 "Insert Image…"，`dart:ui` 解码取像素尺寸。测试：引擎 2 例（现有页插图 media+ForeignData 往返·no-op 保留、
  空文档插图建页 rels，共 48/48）、控制器 3 例（嵌字节+撤销、重插新部件名、导出重开往返，App 共 45）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-13 — **对齐 drawio（批次二十三）——连接器端点重连/分离 + 清除折点**：drawio 最核心的边编辑手势。
  引擎 `VsdxPage.setConnectorEndpoint(id, begin, targetShapeId, x, y)`（重建 connects：删该端旧 `<Connect>` 行、
  胶合时补整形状行；按 waypoints/straight/elbow 重建几何种子；`rerouteConnectors` 精修胶合端到 `_edgePoint`、浮动端
  用种子点）+ `clearConnectorWaypoints`（＝`setConnectorWaypoints(id, [])`）；**往返零改动**——复用既有
  `<Connects>`（`_writeConnects` 整块重写）+ `BeginX/BeginY/EndX/EndY` + 几何补丁。控制器 `reconnectEndpoint`
  （transient 拖拽 + 提交单撤销步）、`clearSelectedConnectorWaypoints`（仅对有折点的选中连接器、单步、无则空操作）、
  `canClearWaypoints`。画布：新增 `_DragMode.moveEndpoint`（`_tryStartEndpointDrag` 命中起/终点手柄，优先于折点与
  命中测试）、拖动时 `_endpointTargetAt`（排除自身/连接器/1-D）设 `_connectTargetId` 高亮、`reconnectEndpoint(transient)`
  实时更新，`onPanEnd` 提交、Esc 取消；`_SelectionPainter.endpointHandles`（绿色端点，白环）；右键菜单
  "Clear Waypoints"（`canClearWaypoints` 时）。测试：引擎 1 例（端点重连 b→c 保留 begin、分离 end 移除行且端点落到
  落点，共 49/49）、控制器 2 例（重连/分离 + 撤销、清除折点 + 撤销，App 共 47）。`dart analyze` 干净（app + 引擎）、
  `flutter test` 通过、`flutter build macos` 成功。
- 2026-07-13 — **对齐 drawio（批次二十四）——固定连接点（Fixed connection points）**：连接器端点可钉到目标形状的
  固定连接点（drawio 蓝色叉），而非仅整形状边缘吸附。模型 `VsdxShape.connectionPoints`（局部英寸，origin 左下 + copyWith）；
  **解析器** `_readConnectionPoints` 读 `<Section N="Connection">` X/Y 行（含 master 继承）；`VsdxPage` 加 `localToPage`
  （局部→页面，含旋转/翻转）、`connectionPointPage`、`effectiveConnectionPoints`、`defaultConnectionPoints`（标准 5 点：
  上/右/下/左/中）、`fixedConnectionIndex`（`ToPart≥100→索引`）；`rerouteConnectors` 对固定点连接把端点定位到点的页面坐标、
  否则边缘吸附；`setConnectorEndpoint` 加 `connectionPointIndex`（物化标准点集、写 `ToCell/ToPart`）。**Writer**
  `_buildShapeElement` 发射 Connection 节 + `_patchConnectionPoints`（现有形状物化时补节、保留未建模 Cell）+ `_pointsEqual`。
  **控制器** `reconnectEndpoint`/`createConnector` 加固定点参数；**画布** 拖端点/连线时显示目标连接点（蓝叉）、就近吸附
  （`_connSnapIndex` 半径 13px）+ 高亮，落点即钉固定点（`_SelectionPainter.connectionPoints/snappedConnectionPoint`）。
  测试：引擎 1 例（固定点物化 + 补节 + 路由往返，共 50/50）、控制器 1 例（钉端点 + 物化 + toPart，App 共 48）。
  `dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。
- 2026-07-13 — **对齐 drawio（批次二十五）——形状库拖放 + 光标处粘贴**：drawio 高频放置交互。控制器
  `addShapeFromBuilderAt(build, cx, cy)`（落点放置 + 网格吸附 + 记忆样式 + 选中，`addShapeFromBuilder` 复用之落中心）、
  `pasteAt({cx, cy})`（有坐标则把剪贴板包围盒中心对齐到光标，否则原 +0.25/-0.25 偏移；`paste` 复用之）。UI：形状库面板
  模具改 `Draggable<Stencil>`（`pointerDragAnchorStrategy` + 拖动预览 + `childWhenDragging` 淡化，点击仍落中心），
  `PageCanvas` 用 `DragTarget<Stencil>` 包裹返回、`ClipRect` 挂 `_canvasBoxKey`（`globalToLocal` 落点转画布坐标）→
  `_onStencilDropped`；右键空白菜单加 "Paste Here"（`_onSecondaryTapUp` 传页面坐标）。测试：控制器 2 例（落点放置、
  pasteAt 居中，App 共 50）。`dart analyze` 干净（app + 引擎）、`flutter test` 通过、`flutter build macos` 成功。纯交互特性
  （无引擎往返改动）。
- 2026-07-13 — **修复：悬停连线三角箭头过早消失**：`_onHover` 里"停在箭头上保持 hover"原先只用箭头精确命中圈
  （中心距边缘 22px、半径 15px），形状边缘到命中圈之间有约 7px **死区**——光标一离开形状本体、尚未进入箭头命中圈，
  `_hoverShapeId` 即被清空，箭头（drawio HoverIcons）随之消失，无法移动到箭头上拖出连线。改为新增 `_withinConnectAffordance`
  （形状屏幕框外扩 `gap+hit+8` 的**悬停光环**），光标在形状到箭头的整段路径上都保持 hover，消除死区（仅当光标不在任何
  形状上时用于维持，故不覆盖真实形状 hover；实际连线仍需点/拖到箭头精确命中圈）。纯 UI 交互修复（无引擎/模型改动）。
  `flutter analyze` 干净、`flutter test` 通过（47）、`flutter build macos` 成功。
- 2026-07-13 — **对齐 drawio（批次二十六）——圆角连接器（Rounded edges）**：连接器路由拐角可圆角化，补齐 drawio
  边的"Rounded"选项（此前仅 Straight/Orthogonal/Curved 三态路由，拐角恒为尖角）。模型 `VsdxShape.rounded`（会话级，
  同 `curved` + copyWith + 文档）；引擎 `VsdxPage.roundCorners(control, radius, segmentsPerCorner)`（每个内部拐角沿
  相邻两段各回退 `min(radius, 较短邻段/2)`、以拐点为控制点采样二次贝塞尔 `_quadBezier`，端点精确、<3 点原样返回）；
  抽出单一烘焙助手 `_bakeRoute`（curved→rounded→原样）替换四处 `curved ? curveThrough : control` 烘焙点
  （`rerouteConnectors`/`setConnectorStyle`（保留形状 `rounded`）/`setConnectorWaypoints`/`setConnectorEndpoint`）；新增
  `setConnectorRounded(ids, bool)`（保留路由样式、从当前 begin/end/waypoints 重算烘焙）+ `isConnectorRounded`。与
  `curved` 同构：**渲染层与 Writer 零改动**（仍 `MoveTo`/`LineTo`）、圆角完整往返、随重路由/移动保持；端点/折点手柄仍落逻辑
  控制点（`connectorRoute`），curved 时圆角无意义。控制器 `selectedConnectorRounded`/`setConnectorRounded`（单撤销步）；
  `main.dart` 属性面板 Connector 区在三选一下加 **Rounded 开关**（curved 时 `onChanged:null` 禁用）。测试：引擎 2 例
  （`roundCorners` 端点精确+拐点回退+象限内、圆角连接器烘焙折线且经重路由保持）+ Writer 1 例（圆角连接器几何真实
  `.vsdx` 往返，引擎共 54）、控制器 1 例（圆角开关 + 重路由保持 + 撤销，App 共 52）。`dart analyze`/`flutter analyze`
  干净、`dart test`（54）+ `flutter test`（52）通过。
- 2026-07-13 — **对齐 drawio（批次二十七）——形状库扩充 + 统一形状入口**：把形状面板从 9 个流程图形状
  扩到 **~40 个**、按 drawio 分组，并把"更多形状"入口从顶部 AppBar 挪到左侧工具条，统一在左侧。引擎
  `VsdxShapeFactory` 新增 **cylinder/document/cube/predefinedProcess/internalStorage/delay** 六个复合几何
  构造器——全部只用白名单命令（`MoveTo`/`LineTo`/`EllipseCmd`/`EllipticalArcTo`），其中 cube/预定义流程/
  内部存储用**双 geometry**（第二段 `NoFill` 画内部棱线/竖线），cylinder/document/delay 用椭圆弧（控制点＝弧
  中点），故**渲染与 Writer 零改动、完整往返**（Writer 早已支持多 geometry section + `NoFill`，parser 早已读回）。
  `stencils.dart` 重写为 `StencilGroup` 分组（**General / Flowchart / Arrows**，矩形/圆角/文本/椭圆/方/圆/菱形/
  平行四边形/三角/直角三角/五~八边形/梯形/十字/星/圆柱/立方体/文档/卡片/标注/step；流程图 process/decision/
  terminator/data/预定义流程/内部存储/手动输入/手动操作/准备/delay/off-page；箭头 右/左/上/下/双向）+ flatten
  `kStencils`。`main.dart`：`_StencilPanel` 改 StatefulWidget（**搜索框** + **可折叠分组** + **真实几何缩略图**——
  `_StencilThumbPainter` 复用 `buildPath`，把 shape-local（左下原点/Y-up）Y 翻转映射进缩略图框，逐 geometry 尊重
  `NoFill`/`NoShow`，预览即所得）；`_ToolStrip` 底部加 **"More shapes"** 切换按钮（AppBar 移除 `category_outlined`）。
  测试：引擎 1 例（cube 双 geometry + 第二段 `noFill`、cylinder/delay 椭圆弧往返,共 55/55）；`dart analyze`（app +
  引擎）干净、`flutter test`（52）通过、`flutter build macos` 成功。纯新增/UI，无破坏性改动。
- 2026-07-13 — **对齐 drawio（批次二十八）——图形种类再扩充（Cloud + UML）+ 连接能力（悬停连接点 + begin 固定点）**：
  两方面推进。**图形**：`VsdxShapeFactory` 新增 **cloud**（沿边界锚点逐段外凸 `EllipticalArcTo` 组成闭合"泡泡"轮廓）、
  **umlActor**（头 `EllipseCmd` + 身体/手臂/双腿 `NoFill` 线，双 geometry 火柴人）、**umlClass**（矩形 + 两条 `NoFill`
  分隔线＝标题/属性/方法三格）、**umlPackage**（左上 tab + body 的文件夹单多边形）、**note**（切角矩形 + `NoFill`
  折角线）——仍全部只用白名单命令（`MoveTo`/`LineTo`/`EllipseCmd`/`EllipticalArcTo`），往返安全；`stencils.dart`
  General 加 **Cloud**、新增 **UML 组**（Actor / Use Case / Class / Package / Note / Node），形状总数升到 ~50。
  **连接**：`EditorController.createConnector` 加 `beginConnectionPointIndex`——begin 端经 `setConnectorEndpoint(begin:true,
  connectionPointIndex:)` 物化/胶合到目标**固定连接点**（对称既有 end，`<Connect> ToPart=100+k`、`fromPart=9`）；
  `PageCanvas` 两处对齐 drawio：(1) **悬停 select 模式的形状即显示其 `effectiveConnectionPoints`**（drawio 蓝叉，
  此前仅拖动/连线时显示），(2) 从悬停方向箭头拖出连线时把 **begin 端 glue 到该方向对应的固定连接点**（箭头 dir 0/1/2/3
  ↔ 默认点 top/right/bottom/left 索引，仅当形状用默认点集时启用、否则回退整形状 glue，避免自定义点越界）；新增
  `_connectSourceConnIndex` 会话态并在 panEnd/取消时复位。测试：引擎 2 例（UML/cloud 往返＝umlClass 双 geometry+第二段
  `noFill`、cloud ≥6 段弧、note 双 geometry+`noFill`；连接器 begin 端胶合固定点往返＝物化标准 5 点 + `ToPart=101` +
  begin 端定位到右中点，共 57/57）；`dart analyze`/`flutter analyze` 干净、`flutter test`（52）通过、`flutter build macos` 成功。
- 2026-07-14 — **对齐 drawio（批次二十九）——图形种类再扩充 + 连接能力（Line jumps 线跳）**：两方面继续推进。
  **图形**：`VsdxShapeFactory` 新增 **display**（左尖 + 右半圆弧）、**orGate**（圆 + 全宽十字，双 geometry）、
  **summingJunction**（圆 + 45°X，双 geometry）、**sort**（菱形 + 中横线，双 geometry）、**heart**（四段椭圆弧心形）——
  仍全白名单命令、往返安全；`stencils.dart` Flowchart 加 **Display / Merge / Collate / Or / Summing Junction / Sort /
  Loop Limit**、General 加 **Lightning / Heart**（Merge/Collate/Loop Limit/Lightning 为多边形），形状总数升到 ~60。
  **连接**：实现 drawio 标志性的 **Line jumps（线跳）**——连接器与另一连接器交叉处画小半圆弧"跳过"而非形成歧义的
  "+"。新增纯函数 `lib/render/line_jumps.dart`（`segmentIntersection` 仅取严格内部真交叉、`polylineCrossings`、
  `polylineWithJumps` 沿每段在与下层连接器的交叉参数处插入半圆弧、含重叠/近端点保护）；`VsdxPainter` 加
  `drawLineJumps`/`lineJumpRadiusInches` 参数——`paint` 前预算所有连接器的**页面折线（z 序）**（`_computeConnectorRoutes`／
  `_connectorPagePolyline`／`_polylineLocalPoints`／`_localToPageOffset`），`_paintGeometries` 对 1-D stroke 把与**更低 z**
  连接器的交叉处（经 `_pageToLocal` 转当前连接器局部坐标求交）烘成跳线；**纯渲染层、零碰几何/往返/Writer**。控制器
  `showLineJumps`/`toggleLineJumps`（默认开），画布传参，`main.dart` ⋯ More 菜单加 **"Line jumps"** 勾选项。测试：引擎
  1 例（Or/Sort 双 geometry+第二段 `noFill`、Display/Heart 椭圆弧往返，共 58/58）、App 4 例（`line_jumps` 纯函数：真交叉点、
  拒绝平行/端点相接、交叉计数、跳线弧使轮廓变长，共 56）；`dart analyze`/`flutter analyze` 干净、`flutter test` 通过、
  `flutter build macos` 成功。
- 2026-07-15 — **对齐 drawio（批次三十）——形状库按类别归类 + 宽屏默认展开常用图形**：参考 drawio / Visio /
  万兴图示 的形状库分区，把形状面板从 4 组（General 混装 25 个 / Flowchart / Arrows / UML）重整为 **6 个语义清晰的
  类别**——**General**（14 个基础几何：矩形/圆角矩形/文本/方/椭圆/圆/三角/直角三角/菱形/平行四边形/梯形/五~八边形）、
  **Flowchart**（21 个流程图符号，Step/Card/Off-Page 归入）、**Arrows**（右/左/上/下/双向 5 箭头）、**Containers**
  （圆柱/立方体/云/文档/标注）、**Decorative**（星/十字/心形/闪电）、**UML**（Actor/Use Case/Class/Package/Note/Node）；
  所有形状构造器保留、仅重新分配（Document 同时列入 Flowchart 与 Containers，属合理复用）。`StencilGroup` 加
  **`defaultExpanded`** 标记常用库（General/Flowchart/Arrows）。`_StencilPanel` 改**响应式默认折叠态**——
  `didChangeDependencies` 按窗口宽度（`MediaQuery.sizeOf`，阈值 `_wideBreakpoint=900`px）种子化 `_collapsed`：
  **宽屏展开常用 3 组、其余折叠；窄屏全部折叠**，用户手动展开/折叠即置 `_userAdjusted` 停止再种子化（选择随窗口缩放/
  重建保持）；搜索框下加**快捷工具条**（类别数 + 全部展开/全部折叠按钮，`_setAllCollapsed`），分组标题显示**图形数量**
  便于快速扫读。纯 UI/数据重组——渲染 / Writer / 往返零改动，`kStencils` 扁平视图不变。`flutter analyze` 干净
  （改动文件零问题）、**每个内置模具几何往返测试通过**。（注：`roundtrip_flowchart_test` 另有 6 例既有失败——
  文本 run 颜色/字体默认往返漂移 `null→ff000000/Arial`——经 `git stash` 核验属**本批之前既有**、与本改动无关。）
- 2026-07-15 — **修复：文本 Character Color/Font 往返漂移**：根因是近期为兼容万兴图示的两处默认值物化——
  (1) Writer `_charCells` 在 `color==null` 时仍强制写出 `Color=#000000`；(2) Parser `_readCharRow` 在 Character
  行缺 `Font`/`Color` cell 时，用 document DefaultTextStyle（Arial / 黑）填进模型。编辑器新建标签常为
  `color:null`/`fontFamily:null`（继承样式表），save→reopen 即漂移为 `ff000000`/`Arial`。修复：Writer **仅在
  模型显式设色时写 Color**（缺省交给 DefaultTextStyle/StyleSheets，画笔本就以 `Colors.black87` 回退）；Parser
  **缺省 Font/Color cell 保持 null**、不再物化 stylesheet（Size 等度量仍继承）。`roundtrip_flowchart_test` 15/15、
  引擎 307、App 81、analyze 干净。
- 2026-07-15 — **对齐 drawio（批次三十一）——默认形状库全量覆盖（按分类）**：对照 drawio `Sidebar.js`
  `defaultEntries = general;uml;er;bpmn;flowchart;basic;arrows2`，把形状面板扩到 **7 组 / ~117 个模具入口**
  （含跨组合理复用）：**General**（31，含 Cylinder/Cloud/Document/Note/Actor/And/Or/Data Storage/Double Rect·Ellipse/
  Corner/Tee）、**Flowchart**（33，补 Tape/Database/Multi-Document/Stored·Direct·Sequential Data/Annotation/
  Parallel Mode/On-Page/Extract/Transfer/Start…）、**Arrows**（11，Chevron/Notched/Signal In/Quad/Triad/
  Double Vertical）、**Basic**（15，多角星/Half Circle/Wave/Banner/Pyramid/Moon/Donut/Frame/No Symbol/
  Cylinder Stack）、**Containers**（7）、**UML**（12，+Component/Object/Interface/Start/End/Fork）、**BPMN**
  （8，Task/Gateway/Events/Data Object·Store/Annotation）。引擎新增 `tape/storedData/annotation/parallelMode/
  multiDocument/doubleRectangle/doubleEllipse/andGate/halfCircle/wave/frame/donut/noSymbol/umlComponent/
  bpmnEvent/bpmnGateway/bpmnTask/cylinderStack`（全白名单命令、往返安全）。宽屏分档展开阈值不变
  （900/1100/1280）。测试：全模具几何往返 + 新 drawio-parity Writer 例；引擎 308、App 81、analyze 干净。
  （ER 专用库、完整 UML 2.5 / BPMN 事件变体 / 泳道池留后续。）
- 2026-07-15 — **对齐 drawio（批次三十二）——补齐 defaultEntries 全部分类 + 常用变体**：在批次三十一基础上继续
  对齐 arrows2 / basic / uml / er / bpmn，形状面板扩到 **9 组 / ~169 个模具入口**：**Arrows**（18，+Slender/
  Sharp/Tailed/Striped/Bend/U-Turn/Callout Arrow）、**Basic**（32，+Cone/Drop/Pointed Oval/Pie/Smiley/Sun/
  Tick/X/Plaque/8-Star/Oval·Loud·Cloud Callout/Layered Rect/Acute·Obtuse Triangle…）、**UML**（15，+Boundary/
  Control/Entity）、新增 **ER**（12，Entity/Weak Entity/Attribute 变体/Relationship/Identifying/Associative）、
  **BPMN**（12，+Parallel·Inclusive Gateway/Pool/Conversation）、新增 **Advanced**（8，Ellipse Divider/
  Switch/Double Rect·Ellipse…）。引擎新增 `cone/drop/pointedOval/pie/smiley/umlBoundary/umlControl/
  associativeEntity/weakEntity/identifyingRelationship/bpmnParallelGateway/bpmnInclusiveGateway/bpmnPool/
  bpmnConversation/ellipseDividerH·V/layeredRectangle`。完整 BPMN 事件矩阵（~169）与 UML 2.5 / 泳道表格式
  容器仍留后续。
- 2026-07-15 — **对齐 drawio（批次三十三）——defaultEntries 缺口收口**：对照 arrows2(27)/basic(63)/uml/
  er(13)/bpmn.xml，把面板扩到 **9 组 / ~230+ 入口**：**Arrows** 对齐 arrows2 全套（+Notched Signal-In/
  Slender Two Way/Stylised/Bend Double/Callout Double·Quad/Jump-In/Tailed Notch…）、**Basic** 补 Partial
  Rect/Diagonal Snip/Button/Arc/Message/Tag/Bang/Neutral·Sad Smiley/Frame Corner/Isometric Cube…、
  **General** +Container、**UML** +Module/Lifeline/Activation/Destruction/Frame/Provided·Required Interface、
  **ER** +Weak Key Attribute、**BPMN** 扩到 Task 变体 + Exclusive/Complex/Event-Based Gateway + Message/
  Timer/Terminate 事件 + Lane。引擎新增对应工厂（全白名单几何）。  仍刻意未收：BPMN 2.0 全事件矩阵图标细节、
  Basic 填充图案矩形（pattern 渲染 M6）、真正可折叠泳道容器。
- 2026-07-15 — **对齐 drawio（批次三十四）——defaultEntries 缺口清零**：Basic 补齐填充矩形（diag/vert/hor/
  grid 线影近似）、Diagonal/Corner/Three-corner Rounded、Rounded/Plaque Frame、Button(shaded)；UML 补齐
  Actor/Boundary/Entity/Control Lifeline；BPMN.xml 补齐 Ad Hoc / Compensation / Cancel·Link·Multiple·Rule
  Intermediate / Loop Marker / Multiple Instances。面板 **9 组 / ~251 入口**；对照 arrows2/basic/er/
  flowchart/general/uml/bpmn.xml 的标题缺口为 **0**。真正 BPMN 2.0 事件全矩阵与可折叠泳道仍留后续。
- 2026-07-15 — **对齐 drawio（批次三十五）——general 包 Misc/Advanced**：drawio `configuration` 中
  `general` = `general+misc+advanced`。新增 **Misc** 组（Curly Bracket / Backbone / Crossbar / Zigzag /
  Waypoint / Lists / Isometric Square…）并按 Advanced 全表扩充 **Advanced**（Double Rounded/Square/Circle、
  Tape Data、User、Sum、Process Bar、List Item、Ellipse dividers…）。面板 **10 组 / ~297 入口**。仍刻意未收：
  HTML Table / Sketch 风格 / Image·Icon 占位、可折叠 List 泳道、BPMN 2.0 全事件矩阵。
- 2026-07-15 — **对齐 drawio（批次三十六）——系统剪贴板 + 完整图层**：重要编辑 UX。
  (1) **系统剪贴板**：`ShapeClipboardCodec` 把选中形状打成迷你 `.vsdx` 信封写入系统剪贴板；
  `pasteFromSystem` 先读系统剪贴板（信封 → 形状；纯文本 → 文本框），跨实例 Cmd+V / Paste Here 可用；
  应用内 `_clipboard` 仍保留（含图片）。(2) **图层面板**：始终可开；支持新建/重命名/删除、Visible/
  Locked/Print、把选区 Assign 到图层；锁定图层上的形状不可移动/删除。测试：`shape_clipboard_test` 3 例。
  仍优先后续：连接器避障路由、富文本选区、真正容器/泳道。
- 2026-07-15 — **对齐 drawio（批次三十七）——连接器避障正交路由**：`ObstacleRouter`（Hanan 网格 +
  Dijkstra）在自动正交路由时绕开其它 2-D 形状（含 clearance）；接入 `rerouteConnectors` /
  `setConnectorStyle`；`connectorRoute` 从烘焙几何恢复折线以便标签/弯点手柄一致；绘制侧
  `ConnectorRouter` 同步避障。用户 waypoints / 直线路由不受影响。测试：`obstacle_router_test` 5 例。
  仍优先后续：富文本选区编辑、真正容器/泳道、主题 UI。
- 2026-07-15 — **对齐 drawio（批次三十八）——真正容器拖入/拖出**：draw.io 式父子容纳。
  (1) 引擎：`pageToLocal`、`findParentId`、`reparentShape`、`findDropContainerAt`、
  `translateShape`（honour `dontMoveChildren`）；Container / BPMN Pool 打 `shapeKind`。
  (2) 编辑器：拖动时高亮 drop 容器；松手 `applyDropContainmentAt` 挂入或弹出；与拖动同属一步 undo。
  测试：`containment_test` 8 例。仍优先后续：富文本选区、主题 UI、可折叠泳道。
- 2026-07-15 — **对齐 drawio（批次三十九）——富文本选区格式化**：
  (1) 引擎 `rich_text_edit`：`applyCharStyleToRange` / `applyParaStyleToRange` /
  `replacePlainText`（前缀/后缀保样式）/ `charStyleAt`。(2) `setShapeText` 不再压扁多 run；
  内联编辑同步 `textEditSelection`；工具栏 Bold/Italic/Size/Color 对选区只改该段；失焦延迟一帧
  提交以便工具栏先吃到选区。测试：`rich_text_edit_test` 6 例。仍优先后续：主题 UI、可折叠泳道、
  内联编辑器混排预览。
- 2026-07-15 — **对齐 drawio（批次四十）——主题 UI**：
  (1) 内置 Office/Blue/Green/Orange/Monochrome 调色板；Diagram 面板可切换文档主题。
  (2) Format 的 Fill/Line/Text 下增加 Theme 色条，绑定 `theme*Index`（清显式色），渲染走
  `THEMEVAL`；无主题时自动装 Office。(3) `withSolid*` / `withTheme*` 辅助 API。
  测试：`theme_ui_test` 4 例。仍优先后续：可折叠泳道、内联混排预览、theme XML 写出。
- 2026-07-15 — **对齐 drawio（批次四十一）——可折叠容器/泳道**：
  (1) `User.veCollapsed` + `withCollapsed` / `collapsed`；折叠时跳过子树绘制与命中，障碍路由
  也不再计入子形状。(2) 标题栏/泳道条 chevron 绘制与点击 `toggleCollapsed`（undo 友好，折叠时
  清除子形状选中）。(3) `localToPageDeep` 支持嵌套容器 chevron 命中。测试：`collapse_container_test`
  4 例。仍优先后续：折叠时收起高度、内联混排预览、theme XML 写出。
- 2026-07-15 — **对齐 drawio（批次四十二）——折叠收高 + 内联混排预览**：
  (1) `fold`/`unfold`：折叠把高度收到标题带并记下 `veExpandedHeight`，顶边固定；展开恢复。
  (2) 内联编辑用 `Text.rich` 按 run 预览粗体/颜色/字号（`replacePlainText` 跟踪输入），TextField
  近乎透明叠在上面以保留光标与选区。测试：`collapse_container_test` 增补 fold 高度用例。
  仍优先后续：theme XML 写出、公式重算、矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十三）——主题 XML 持久化**：
  (1) `ThemeSerializer.emit` / `patchClrScheme`：写出完整 DrawingML theme，或仅改
  `<a:clrScheme>`（保留 font/fmt）。(2) Writer `_prepareThemePart`：主题变更时创建
  `visio/theme/theme1.xml` + document.xml.rels + Content_Types，未变更则字节透传。
  (3) `ThemeParser.slotForName` 公开。测试：`theme_writer_test` 4 例。仍优先后续：
  公式重算引擎、矢量 PDF、LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次四十四）——查找替换 + 页面标签重排**：
  (1) Find 条可展开 Replace：`replaceFind` / `replaceAllFind`（大小写不敏感，只改标签不改
  名称；Replace All 单撤销步）；Cmd+H / 菜单 Find and Replace。(2) 页栏
  `ReorderableListView` + `VsdxDocument.movePage` / `EditorController.movePage`（按页 id
  保持当前页）；Writer 原有 `_reorderPages` 保序写回。测试：控制器 2 例（replace + movePage）。
  仍优先后续：多泳道池、HTML Table、公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十五）——多泳道池插入/增删**：
  (1) `SwimlaneOps`：`assemblePool` / `lane` / `layoutLanes` / `addLane` / `removeLane`；
  `User.vePool` / `veLane` / `veLaneHorizontal`；横泳道左标题条、竖泳道顶标题条。
  (2) Stencil：Pool（默认 2 道）、Vertical Pool、H/V Lane；右键 Add/Remove Lane；
  拖入 pool 时自动 reflow；chevron 随方向定位。(3) 控制器 `addLaneToSelectedPool` /
  `removeSelectedLane`。测试：`swimlane_test` 5 例 + 控制器 1 例。仍优先后续：HTML Table、
  公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十六）——HTML Table（网格表）**：
  (1) `TableOps`：`assembleTable` / `layoutCells` / `addRow`/`addColumn` /
  `removeRow`/`removeColumn`；`User.veTable`/`veCell`/`veRow`/`veCol`；单元格为可编辑
  矩形子形状（双击改文本）。(2) General Stencil：Table（3×3）、Table 2×2；右键 Add/Delete
  Row|Column。(3) 控制器 `selectedTableId` + 增删 API。测试：`table_test` 4 例 + 控制器 1 例。
  仍优先后续：合并单元格/列宽拖拽、公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十七）——表格合并 + 列宽/行高拖拽**：
  (1) `veColWidths`/`veRowHeights` 比例；`resizeColumnBoundary`/`resizeRowBoundary`；选中表时
  显示分隔线，拖拽调宽高。(2) `veRowSpan`/`veColSpan`/`veCovered` 合并：多选矩形单元格 →
  Merge；Unmerge 还原；覆盖格不绘制/不命中。(3) 右键 Merge/Unmerge Cells。测试：`table_test`
  6 例 + 控制器 merge 1 例。仍优先后续：公式重算 / 矢量 PDF。
- 2026-07-15 — **修复：更多图形面板滚动条/滑块跟手**：根因是每次文档 `notifyListeners` 整页
  `setState`，连带重建约 300 个模具缩略图，滚动条与属性滑块滞后。改为 `ListenableBuilder` +
  图形库作 `child`（编辑不重建）；`ListView.builder` + 几何缓存 + 显式 `Scrollbar`；Opacity/
  Corners 滑块本地拖拽值跟光标。仍优先后续：公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十八）——图片拖放落点 + 替换**：
  (1) `insertImage` 支持 `cx/cy` 落点（网格吸附）；桌面拖入 PNG/JPEG/GIF/BMP/WEBP 落到光标处。
  (2) 拖到已有图片上 / 右键 / Format「Replace Image…」→ `replaceImage`（新 media part，保持
  位置尺寸，单撤销步）。(3) `pictureShapeAt` 命中顶层图片。测试：控制器 2 例（落点 + replace）。
  仍优先后续：手绘 / 永久辅助线 / 公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次四十九）——Freehand 手绘**：
  (1) `EditorTool.freehand` + 工具条；拖拽采样 content-px → 页英寸折线，实时墨迹预览。
  (2) `VsdxShapeFactory.freehand` / `createFreehand`：1-D ink（`ObjType=1`，非连接器），简化近点，
  继承线条记忆样式；单击不创建。(3) Writer 以 MoveTo/LineTo 往返。测试：工厂 1 + Writer 1 +
  控制器 2。仍优先后续：永久辅助线 / 公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次五十）——标尺永久辅助线（Guides）**：
  (1) 从上/左标尺拖出垂直/水平 `PageGuide`（按页会话级，不写回 `.vsdx`）；标尺三角标记 +
  青色全页线；拖回标尺删除；空白右键 Clear Guides。(2) `computeSnap` 吸附永久辅助线；移动形状
  时与邻居对齐竞争。(3) 控制器 `add/move/remove/clearPageGuide`。测试：snap 2 例 + 控制器 1 例。
  仍优先后续：背景页 / 连接点编辑 / 公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次五十一）——背景页（BackPage）**：
  (1) 画布 `VsdxPainter.underlayPage`：前景页下先绘制 Visio `BackPage` 形状（裁剪到前景页框）。
  (2) Diagram 面板：开关「Background page」+「Use background」下拉；页签对背景页显示图层图标。
  (3) 控制器 `setPageIsBackground` / `setBackgroundPage`（指定时同步把目标标为 `Background="1"`）/
  `resolvedBackgroundPage`。(4) Writer 往返 `Background` / `BackPage` 属性。测试：Writer 1 + 控制器 1。
  仍优先后续：连接点编辑 / 公式重算 / 矢量 PDF。
- 2026-07-15 — **对齐 drawio（批次五十二）——编辑连接点（Edit Connection Points）**：
  (1) 引擎：`connectionPointAt` / `materializeConnectionPoints` / `add`/`move`/`removeConnectionPoint`
  （删点时重映射 `ToPart=100+k` 胶合）。(2) Writer `_patchConnectionPoints` 支持缩短删行 / 清空删节。
  (3) 控制器编辑模式 + 画布：右键 / More「Edit Connection Points…」；拖移蓝叉、点击形状加点、
  Delete 删点、Esc 退出；编辑时隐藏缩放/旋转手柄。(4) 测试：Writer 1 + 控制器 1。
  仍优先后续：公式重算 / 矢量 PDF / LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次五十三）——矢量 PDF + 导出保真 + 快捷键**：
  (1) PDF 改为 SVG 路径 → `pw.SvgImage` 矢量写出（可缩放）；背景页作 underlay、跳过独立 Background
  页；图层尊重 `Print`。(2) SVG/PNG 导出同步 underlay + Print 过滤；`printableLayerIds` /
  `document.backgroundFor`。(3) 快捷键：Cmd+B/I/U、Cmd+E 选连接线、Cmd+Shift+I 选顶点、
  Cmd+Shift+A 取消选中、Tab/Shift+Tab 循环选中。测试：export 2 + PDF 2 + 控制器 1。
  仍优先后续：公式重算 / Find 跨页 / 渐变填充 UI / LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次五十四）——Find 跨页 + Match case + 渐变填充 UI**：
  (1) Find 匹配改为 `(pageIndex, shapeId)` 扫全文档；Find 切页保留 query；计数显示页码。
  (2) Find 栏 `Aa` 开关 Match case；Replace / Replace All 尊重大小写；Replace All 跨页单撤销。
  (3) Format Fill：None/Linear/Radial + Start/End 色 + 线性角度；`setFillGradient`；实心色板清除渐变；
  `VsdxFill.withGradient` / `copyWith` 可清 null。测试：控制器 2 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次五十五）——连接点磁吸 + Align to page + Whole word**：
  (1) 移动形状时 `computeSnap` 吸附邻居连接点（`SnapMagnet`），与边/中心/永久辅助线竞争。
  (2) 单选对齐相对页面（左/右/上/下/水平/垂直居中）；多选仍相对选区。
  (3) Find 栏 `W` 整词匹配；Replace 同步。测试：snap 2 + 控制器 2。
  仍优先后续：公式重算 / LibreOffice 交叉验证 / 线渐变·阴影细节 UI。
- 2026-07-15 — **对齐 drawio（批次五十六）——线渐变 + 阴影细节 Format UI**：
  (1) Format Line：None/Linear/Radial + Start/End 色 + 线性角度；`setLineGradient`；
  实心色板 / No line 清除线渐变；`VsdxLine.withGradient` / `copyWith` 可清 null。
  (2) Format Shadow：开关外加颜色色板、Offset X/Y、Blur、Opacity；`updateShadow` /
  `selectedShadow`；`VsdxShadow.copyWith` 支持清色。测试：控制器 2 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证 / Glow·Reflection UI。
- 2026-07-15 — **对齐 drawio（批次五十七）——Glow + Reflection Format UI**：
  (1) Format Glow：开关 + 颜色 / Size / Opacity；`setGlow` / `updateGlow` / `selectedGlow`；
  `VsdxGlow.copyWith`。
  (2) Format Reflection：开关 + Size / Dist / Blur / Opacity；`setReflection` /
  `updateReflection` / `selectedReflection`；`VsdxReflection.copyWith`。
  引擎渲染与 Writer 往返此前已具备。测试：控制器 1 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次五十八）——箭头大小 + 填充图案 + Match size + Z 序键**：
  (1) Format Line 箭头 1–7 档 Size；`setBeginArrowSize` / `setEndArrowSize`。
  (2) Format Fill 图案条（Solid + 常用 hatch）；`setFillPattern`（hatch 清渐变）。
  (3) Arrange Same width/height/size（相对首个选中）；`matchSelection*`。
  (4) Cmd+] / Cmd+[ 逐层前移/后移。测试：控制器 1 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证 / Soft Edges / 图层侧栏。
- 2026-07-15 — **对齐 drawio（批次五十九）——Soft Edges + 行距 + 图层面板 + Jump 半径**：
  (1) Soft Edges：Painter 模糊羽化 fill/stroke；Format 开关+Size；`setSoftEdges` /
  `updateSoftEdges`（模型/Writer 已有）。
  (2) Format Text 行距 1×/1.15×/1.5×/2×；`setLineSpacing` / `selectedParaStyle`。
  (3) Layers 改为可钉住浮动面板（仿 Outline），替换模态对话框。
  (4) Diagram 面板 Line jumps 开关 + Jump 半径滑块（会话级）。测试：控制器 1 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证。
- 2026-07-15 — **对齐 drawio（批次六十）——复合线 + 段前段后 + 删除线**：
  (1) Format Line CompoundType（Single/Double/Thick-thin/Thin-thick）；Painter
  同心描边+clear 空隙；`setCompoundType`。
  (2) 富文本按 `\n` 分段布局，应用 SpBefore/SpAfter；Format Text Space before/after
  预设；`setSpaceBeforeInches` / `setSpaceAfterInches`。
  (3) Format 删除线开关；`setStrikethrough`（绘制此前已有）。测试：控制器 1 例。
  仍优先后续：公式重算 / LibreOffice 交叉验证 / 项目符号。
- 2026-07-15 — **设置页：语言 / 暗黑模式 / 主题色**：
  `AppSettings`（SharedPreferences）持久化 themeMode、seedColor、locale；
  `SettingsPage` + AppBar/More 入口；`AppLocalizations`（en/zh）覆盖设置与主界面
  chrome。测试：`app_settings_test` + `widget_test` 设置流程。
- 2026-07-15 — **复核修复（批次 56–60 + 设置页）**：全量 `flutter analyze` 无错误、
  app 127 例 + vsdx 348 例全绿。修两处：(1) 富文本渲染仅当存在段前/段后间距时才走
  分段布局，无间距文本回退原单 `TextPainter` 路径，消除对常规标签的回归风险（并删除
  未使用的 `maxParaW`）。(2) 复合线（CompoundType）改为统一干净双线近似，移除
  thick-thin/thin-thick 两次 `saveLayer` 叠加产生的 4 线错乱；模型值仍照常往返。
- 2026-07-17 — **对齐 drawio（批次六十一）——补齐默认库缺失预制图形（杂项优先）**：
  对照 draw.io `Sidebar.js`（`addGeneralPalette` / `addMiscPalette` / `createAdvancedShapes`）
  与 `stencils/basic.xml` 逐一比对，补齐仍缺的默认库图形。(1) 新增几何工厂
  `parallelepiped`（斜三维盒，含顶/右面内棱）、`roundedRectangularCallout`（圆角气泡+
  左下指向尾，复用按钮式 `EllipticalArcTo` 圆角）、`list`（标题栏+三行分隔的列表容器，
  文字可空）、`imagePlaceholder`（相框+山峦+太阳字形）。(2) `partialRectangle` 增加
  `top/right/bottom/left` 开边参数（默认仍为历史 ∪，字节不变），Misc 补上下轨/左右轨两个变体。
  (3) Stencil 接入：General +Parallelepiped/List，Basic +Parallelepiped/Rounded Rectangular
  Callout，Misc +Vertical List/Image/两个 Partial Rectangle 变体，Advanced +List。
  (4) l10n：5 个新名（Parallelepiped / Rounded Rectangular Callout / List / Vertical List /
  Image）补入全部 37 个语言表并翻译主要语言；`editor_l10n_audit` 计数 246→251。
  测试：`writer_test` 新增 misc 往返 1 例（几何数/弧线/开边段数/文字往返）；既有
  `roundtrip_flowchart` 全 stencil 往返自动覆盖新条目。全量 `flutter analyze` 无错误、
  app 150 例 + vsdx 374 例全绿。仍优先后续：Curved Text（文本走弧）/ 公式重算 / LibreOffice 交叉验证。
- 2026-07-17 — **对齐 drawio（批次六十二）——新增 Network 图形库（`mxgraph.networks`）**：
  默认 7 大库（general/uml/er/bpmn/flowchart/basic/arrows2）已齐全后，开始补 draw.io 的常用
  可选库。本批新增通用网络设备类别。(1) 新增 8 个几何工厂（以几何系统绘制干净可辨的图标，
  轮廓对齐 draw.io 网络库）：`networkServer`（机箱+插槽+LED）、`networkFirewall`（错缝砖墙，
  循环生成砖缝）、`networkMobile`（圆角机身+屏幕+听筒+home 键，按钮式圆角弧）、`networkMonitor`
  （屏+颈+底座）、`networkLaptop`（屏+梯形键盘底）、`networkPrinter`（机身+进纸+出纸盘）、
  `networkWireless`（发射点+三段同心弧，弧顶高度≈半宽以近半圆）、`networkRouter`（扁盒+双天线+端口）。
  (2) 新增 `Network` 分组（`expandAtWidth: 1280`）：8 新图形 + 复用 Cloud/Database/User 共 11 项。
  (3) l10n：8 个新名（Server/Router/Firewall/Monitor/Laptop/Mobile/Printer/Wireless）+ 组名
  `sg_Network` 补入全部 37 个语言表并翻译；`editor_l10n_audit` 计数 251→259。
  (4) 全部 8 图形经渲染快照人工核验（砖墙/笔记本/打印机/无线尤其清晰）。测试：`writer_test`
  新增 network 往返 1 例（几何数/砖缝段数/圆角弧/无线三弧）；`roundtrip_flowchart` 全 stencil 往返
  自动覆盖。全量 `flutter analyze` 无错误、app 150 例 + vsdx 375 例全绿。仍优先后续：Network 补
  Switch/Hub/PC 等、Mockup/Electrical 库、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次六十三）——Network 补齐 + Mockup / Electrical / Signs 起步库**：
  (1) Network 补 `networkSwitch`（机箱+6 口）、`networkHub`（圆体+放射端口）、`networkPc`（塔机+显示器）。
  (2) 新增 Mockup 组（`mxgraph.mockup`）：Checkbox / Radio / Text Field / Combo Box / Window /
  Progress Bar / Slider / Tab Bar / Menu Bar / Toggle（+ 复用 Button）。
  (3) 新增 Electrical 组（`mxgraph.electrical`）：Resistor / Capacitor / Inductor / Diode / LED /
  Ground / Battery / Transformer / AC Source / Electrical Switch（IEEE 风格线框符号）。
  (4) 新增 Signs 组（`mxGraph.signs`）：Warning / No Entry / Mandatory / Exit / Radiation /
  First Aid / High Voltage / Fragile。
  (5) l10n：30 个新 st_ + 3 个 sg_（Mockup/Electrical/Signs）补入 37 语言；审计计数 259→289。
  测试：`writer_test` 新增综合往返 1 例。仍优先后续：各库扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次六十四）——Network/Mockup/Electrical/Signs 扩容**：
  在起步库上继续补常用预制项（几何可辨、可往返）。(1) Network +Tablet/Phone/Modem/Storage/
  Load Balancer/Security Camera。(2) Mockup +Search Box/Star Rating/Help Icon/Information Icon/
  Loading Circle/Horizontal Splitter/Dropdown Menu。(3) Electrical +Fuse/DC Source/Inverter/
  Potentiometer/Circuit Breaker/Crystal/Lamp。(4) Signs +No Smoking/Biohazard/Pedestrian Crossing/
  Keep Dry/Slip Hazard/Fire Extinguisher。(5) l10n 26 个新 st_ 补入 37 语言；审计 289→315。
  测试：`writer_test` 新增扩容往返 1 例。仍优先后续：AWS/Cisco 等专业库、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次六十五）——IEEE 逻辑门 + Floorplan 起步库**：
  (1) Electrical +AND/OR/NAND/NOR/XOR/XNOR Gate、Buffer（IEEE 门符号，与流程图 Or/And 区分）。
  (2) 新增 Floorplan 组：Wall / Door / Window Opening / Table / Chair / Desk / Bed / Sofa /
  Sink / Toilet / Stairs / Elevator / Plant / Refrigerator（俯视家具与开口）。
  (3) l10n：20 个新 st_（Table 复用已有键）+ `sg_Floorplan` 补入 37 语言；审计 315→335。
  测试：`writer_test` 新增 gates+floorplan 往返 1 例。仍优先后续：Floorplan/EIP/云厂商库扩容、
  Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次六十六）——Floorplan 扩容**：
  Floorplan +Double Door / Sliding Door / Bathtub / Shower / Closet / Bookshelf /
  Fireplace / Kitchen Island / Parking Space / TV Stand / File Cabinet / Column /
  Escalator / Copier（14 项俯视家具与开口）。l10n 14 个新 st_ 补入 37 语言；审计 335→349。
  测试：`writer_test` 新增 floorplan 扩容往返 1 例。仍优先后续：EIP/云厂商库、Curved Text、
  公式重算。
- 2026-07-17 — **对齐 drawio（批次六十七）——EIP 起步库**：
  新增 EIP 组（`mxgraph.eip`）：Message Channel / Dead Letter Channel、Aggregator /
  Splitter / Content Based Router / Message Filter / Message Translator /
  Content Enricher / Messaging Gateway / Channel Adapter / Wire Tap /
  Recipient List / Competing Consumers / Event Driven Consumer / Messaging Bridge /
  Process Manager（+ 复用 Message）。几何对齐 Hohpe/Woolf 经典图标（盒体+消息方块+箭头/
  漏斗/管道）。l10n：16 个新 st_ + `sg_EIP` 补入 37 语言；审计 349→365。
  测试：`writer_test` 新增 EIP 往返 1 例。仍优先后续：EIP 扩容、AWS/Cisco 等云厂商库、
  Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次六十八）——EIP 扩容**：
  EIP +Claim Check / Resequencer / Composed Message Processor / Content Filter /
  Control Bus / Detour / Durable Subscriber / Dynamic Router / Envelope Wrapper /
  Message Dispatcher / Message Store / Normalizer / Polling Consumer /
  Routing Slip / Selective Consumer / Service Activator（16 项）。l10n 16 个新 st_
  补入 37 语言；审计 365→381。测试：`writer_test` 新增扩容往返 1 例。仍优先后续：
  剩余 EIP（Smart Proxy/Transactional Client 等）、AWS/Cisco 云厂商库、Curved Text、
  公式重算。
- 2026-07-17 — **对齐 drawio（批次六十九）——EIP 收尾 + AWS 起步库**：
  (1) EIP 补齐 Smart Proxy / Transactional Client / Channel Purger / Test Message /
  Datatype Channel / Invalid Message Channel（XML + Sidebar 管道变体）。
  (2) 新增 AWS 组（`mxgraph.aws4` 几何起步，非商标复刻）：EC2 / S3 / Lambda / VPC /
  RDS / DynamoDB / SQS / SNS / CloudFront / API Gateway。
  (3) l10n：16 个新 st_ + `sg_AWS` 补入 37 语言；审计 381→397。
  测试：`writer_test` 新增 EIP 收尾 + AWS 往返 1 例。仍优先后续：AWS/Azure/GCP/Cisco
  扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十）——AWS 扩容**：
  AWS +IAM / ELB / ECS / EKS / Step Functions / CloudWatch / Kinesis /
  ElastiCache / Redshift / EventBridge / Cognito / Route 53 / EFS / Aurora
  （14 项几何架构图标）。l10n 14 个新 st_ 补入 37 语言；审计 397→411。
  测试：`writer_test` 新增 AWS 扩容往返 1 例。仍优先后续：Azure/GCP/Cisco 起步库、
  AWS 继续扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十一）——Azure 起步库**：
  新增 Azure 组（`azure` / `azure2` 几何起步，非商标复刻）：Virtual Machine /
  App Service / Azure Functions / Blob Storage / SQL Database / Cosmos DB /
  AKS / Virtual Network / Application Gateway / Azure AD / Key Vault /
  Service Bus / Event Hubs / Azure Monitor。l10n：14 个新 st_ + `sg_Azure`
  补入 37 语言；审计 411→425。测试：`writer_test` 新增 Azure 往返 1 例。
  仍优先后续：GCP/Cisco 起步、Azure/AWS 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十二）——GCP 起步库**：
  新增 GCP 组（`gcp2` 几何起步，非商标复刻）：Compute Engine / App Engine /
  Cloud Functions / Cloud Storage / Cloud SQL / BigQuery / GKE / VPC Network /
  Cloud Load Balancing / Cloud IAM / Pub/Sub / Cloud Spanner / Cloud Run /
  Cloud Monitoring。l10n：14 个新 st_ + `sg_GCP` 补入 37 语言；审计 425→439。
  测试：`writer_test` 新增 GCP 往返 1 例。仍优先后续：Cisco 起步、Azure/AWS/GCP
  扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十三）——Cisco 起步库**：
  新增 Cisco 组（几何起步，非商标复刻；显示名避开与 Network 组冲突）：
  Cisco Router / Cisco Switch / ASA Firewall / Access Point / Nexus Switch /
  Catalyst Switch / IP Phone / Call Manager / Layer 3 Switch / WAN Router /
  Voice Gateway / UCS / Fabric Interconnect / Content Engine。
  l10n：14 个新 st_ + `sg_Cisco` 补入 37 语言；审计 439→453。
  测试：`writer_test` 新增 Cisco 往返 1 例。仍优先后续：Azure/AWS/GCP/Cisco
  扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十四）——Azure 扩容**：
  Azure +Container Instances / Container Registry / Redis Cache / Front Door /
  API Management / Logic Apps / Data Factory / Synapse Analytics / IoT Hub /
  Event Grid / Azure Firewall / Bastion / Azure DNS / Azure DevOps（14 项）。
  l10n 14 个新 st_ 补入 37 语言；审计 453→467。测试：`writer_test` 新增 Azure
  扩容往返 1 例。仍优先后续：GCP/Cisco/AWS 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十五）——GCP 扩容**：
  GCP +Bigtable / Dataflow / Dataproc / Cloud Composer / Cloud Armor /
  Cloud CDN / Memorystore / Cloud Build / Artifact Registry / Cloud Scheduler /
  Cloud Tasks / Firestore / Secret Manager / Vertex AI（14 项）。
  l10n 14 个新 st_ 补入 37 语言；审计 467→481。测试：`writer_test` 新增 GCP
  扩容往返 1 例。仍优先后续：Cisco/AWS 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十六）——Cisco 扩容**：
  Cisco +Wireless Controller / PIX Firewall / ATM Switch / Workgroup Switch /
  Content Switch / VPN Concentrator / Wireless Bridge / Meraki AP / Cisco ISE /
  DNA Center / Telepresence / Expressway / Core Switch / Branch Router（14 项）。
  l10n 14 个新 st_ 补入 37 语言；审计 481→495。测试：`writer_test` 新增 Cisco
  扩容往返 1 例。仍优先后续：AWS 续扩、其他厂商库、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十七）——AWS 续扩**：
  AWS +Fargate / ECR / Glue / Athena / EMR / SageMaker / CloudTrail /
  Secrets Manager / CodePipeline / CodeBuild / WAF / Transit Gateway /
  Direct Connect / OpenSearch（14 项）。l10n 14 个新 st_ 补入 37 语言；
  审计 495→509。测试：`writer_test` 新增 AWS 续扩往返 1 例。仍优先后续：
  其他厂商库（Alibaba/IBM 等）、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十八）——Alibaba Cloud 起步库**：
  新增 Alibaba 组（几何起步，非商标复刻）：Alibaba ECS / OSS / SLB / ACK /
  Function Compute / PolarDB / TableStore / MaxCompute / RocketMQ / RAM /
  CEN / SLS / NAS / AnalyticDB。l10n：14 个新 st_ + `sg_Alibaba` 补入 37 语言；
  审计 509→523。测试：`writer_test` 新增 Alibaba 往返 1 例。仍优先后续：
  IBM/Oracle 等厂商库、Alibaba 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次七十九）——IBM Cloud 起步库**：
  新增 IBM 组（几何起步，非商标复刻）：IBM VPC / Cloud Object Storage / IKS /
  ROKS / Db2 / Cloudant / Event Streams / IBM MQ / watsonx / Code Engine /
  API Connect / App ID / Key Protect / Direct Link。l10n：14 个新 st_ +
  `sg_IBM` 补入 37 语言；审计 523→537。测试：`writer_test` 新增 IBM 往返 1 例。
  仍优先后续：Oracle 起步、Alibaba/IBM 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次八十）——Oracle Cloud 起步库**：
  新增 Oracle 组（OCI 几何起步，非商标复刻）：Compute Instance /
  Autonomous Database / Object Storage / Block Volume / OKE /
  Oracle Functions / VCN / Oracle Load Balancer / Streaming / Oracle Vault /
  Exadata / MySQL HeatWave / GoldenGate / Analytics Cloud。
  l10n：14 个新 st_ + `sg_Oracle` 补入 37 语言；审计 537→551。
  测试：`writer_test` 新增 Oracle 往返 1 例。仍优先后续：各云厂商扩容、
  Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次八十一）——Alibaba 扩容**：
  Alibaba +CDN / Aliyun WAF / DataWorks / Hologres / Flink / MSE / ASM /
  ACR / EIP / NAT Gateway / KMS / ARMS / Lindorm / DTS（14 项）。
  l10n 14 个新 st_ 补入 37 语言；审计 551→565。测试：`writer_test` 新增
  Alibaba 扩容往返 1 例。仍优先后续：IBM/Oracle 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次八十二）——IBM 扩容**：
  IBM +Activity Tracker / Log Analysis / Schematics / Satellite / Power VS /
  Bare Metal / Block Storage / File Storage / CIS / Internet Services /
  Aspera / Certificate Manager / Toolchain / Security Advisor（14 项；跳过
  已占用名 container_registry / secrets_manager / transit_gateway）。
  l10n 14 个新 st_ 补入 37 语言；审计 565→579。测试：`writer_test` 新增
  IBM 扩容往返 1 例。仍优先后续：Oracle 扩容、Curved Text、公式重算。
- 2026-07-17 — **对齐 drawio（批次八十三）——Oracle 扩容**：
  Oracle +OCI API Gateway / Service Connector / OCI Notifications /
  OCI Events / Data Science / Data Flow / Data Catalog / FastConnect /
  OCI File Storage / OCI Bastion / Network Load Balancer / Cloud Guard /
  Resource Manager / DevOps（14 项；前缀 OCI 避开跨组冲突）。
  l10n 14 个新 st_ 补入 37 语言；审计 579→593。测试：`writer_test` 新增
  Oracle 扩容往返 1 例。仍优先后续：Curved Text、公式重算、或其他厂商续扩。
- 2026-07-17 — **对齐 drawio（批次八十四）——Curved Text（文本走弧）**：
  补齐已接线但未实现的弧形标签。(1) `VsdxShape.curvedText` /
  `withCurvedText` 经 `User.veCurvedText` 往返。(2) `VsdxPainter._paintCurvedText`
  将字形沿二次贝塞尔弧放置（块内上拱）。(3) 属性面板开关与控制器
  `setCurvedText` 已可用。测试：`curved_text_test` 3 例。仍优先后续：
  公式重算引擎、LibreOffice 交叉验证、项目符号。
- 2026-07-17 — **公式重算（批次八十五）——本地 ShapeSheet 切片**：
  (1) `evaluateFormula` 支持 `locals` 绑定 Width/Height/Pin*/Begin*/End* 等。
  (2) `VsdxShape.recalculateLocalFormulas` 重算 Connection / LocPin /
  Scratch / Controls / User 的本地算术公式缓存 `V`，保留 `F=`；求不出
  （SETATREF / 跨 sheet / Scratch.Xn）则不动。(3) `resizeTo` 末尾接入。
  测试：`formula_recalc_test`。仍优先后续：跨 shape 依赖图、SETATREF 语义、
  Geometry↔Scratch 拓扑、LibreOffice 交叉验证、项目符号。
- 2026-07-17 — **公式重算（批次八十六）——Geometry↔Scratch 本地拓扑**：
  (1) Scratch 求值后绑定 `Scratch.X1`…（按 IX 与 1-based 序）并做最多两轮
  回填。(2) `applyPathCommandFormulas` 按行 `F=` 重写 MoveTo/LineTo/弧/
  贝塞尔/椭圆等绝对几何缓存 `V`。(3) 仍挂在 `resizeTo`→
  `recalculateLocalFormulas`。测试：`formula_recalc_test` 增补 Geometry+Scratch
  例。仍优先后续：跨 shape 依赖图、SETATREF 语义、LibreOffice 交叉验证、
  项目符号。
- 2026-07-17 — **对齐 drawio（批次八十七）——项目符号绘制 / 段落缩进**：
  (1) `VsdxPainter` 段落布局识别 Bullet / IndLeft / IndFirst / IndRight /
  多段换行，绘制字形（`BulletStr` 或默认 •○■…）与悬挂缩进。
  (2) 控制器 `setBullet` / `selectedHasBullet`；属性面板开关。
  (3) l10n `bulletList` 补入 37 语言。测试：`bullet_list_test`。
  仍优先后续：跨 shape 公式依赖、SETATREF、LibreOffice 交叉验证。
- 2026-07-17 — **公式重算（批次八十八）——SETATREF(Controls) + soffice 脚手架**：
  (1) `parseSetAtRefControl` 解析本地 `SETATREF(Controls.Name[.X|.Y])`。
  (2) `syncSetAtRefFromControls` / `pushSetAtRefToControls`：TxtPin ↔
  Controls 双向缓存同步；挂在 `recalculateLocalFormulas` 末尾（resize 后
  文本手柄跟随 Width* 控制点）。(3) `libreoffice_crosscheck_test`：本机无
  soffice 时 skip，安装后或设 `SOFFICE` 可跑 headless 往返。
  测试：`formula_recalc_test` 增补 SETATREF 例。仍优先后续：跨 shape
  `Sheet.n!` 依赖图、完整 SETATREFEVAL、CI 装 LibreOffice。
- 2026-07-17 — **公式重算（批次八十九）——跨 shape `Sheet.n!` 切片**：
  (1) `evaluateFormula` 可选 `sheetLookup`，预处理 `Sheet.n!Cell`。
  (2) `VsdxShape.lookupSheetCell` / `formulaSources` / `referencesAnySheet`。
  (3) `VsdxPage.recalculateFormulas({changedShapeIds})`：多轮重算依赖方；
  可解 PinX/Y、Width/Height、Angle、LocPin*、Begin*/End*。
  (4) 编辑器 move / resize / rotate / align 后接入页面级重算。
  测试：`formula_recalc_test` 增补 Sheet.n! 例。仍优先后续：完整
  SETATREFEVAL、CI 装 LibreOffice。
- 2026-07-17 — **公式重算（批次九十）——SETATREFEVAL / SETATREFEXPR 切片**：
  (1) `parseSetAtRefCall` / `computeSetAtRefRedirect`：输入路径把
  `SETATREFEXPR` 换成入值，求 `SETATREFEVAL`，写入 Controls/User/Prop。
  (2) `expandSetAtRefForRecalc`：重算时剥离 SETATREF/EXPR/EVAL（ignore_eval→0）。
  (3) `lookupLocalRef` / `writeLocalRef` / `applySetAtRefInputs`；
  `pushSetAtRefToControls` 改走通用重定向；`syncSetAtRefFromControls`
  支持 sole `SETATREF(User.*)`。
  测试：`formula_recalc_test` 增补 SETATREFEVAL 例。仍优先后续：CI 装
  LibreOffice、SETATREF 链式/复合公式更全覆盖。
- 2026-07-17 — **交叉验证（批次九十一）——CI 装 LibreOffice**：
  (1) `.github/workflows/ci.yml`：vsdx / Flutter / `libreoffice-crosscheck`
  三 job；后者 apt 安装 Draw nogui（失败则回退 libreoffice-draw）。
  (2) `libreoffice_crosscheck_test`：`REQUIRE_SOFFICE=1` 时缺 soffice 失败；
  headless 转 PDF（UserInstallation + svp），断言非空 `in.pdf`。
  本机无 LO 仍 skip。仍优先后续：SETATREF 链式/复合更全、平台打包签名。
- 2026-07-17 — **公式重算（批次九十二）——SETATREF 链式 / 复合公式**：
  (1) `computeSetAtRefRedirect` 经 `formulaOfRef` 跟随最多 10 跳链，
  写入叶 cell；环检测。(2) `formulaOfLocalRef`；`applySetAtRefInputs`
  接入链式重定向。(3) `syncSetAtRefFromControls` 对复合
  `SETATREF(…)+算术` 用 `evaluateFormula` 求 TxtPin。
  测试：`formula_recalc_test` 增补链/复合例。仍优先后续：平台打包签名；
  `.vsd` VSD6 / 图片 / masters（VSD11 导入已落地）。
- 2026-07-17 — **`.vsd` 导入打磨**：PageProps `pageScale/drawingScale` 缩放（平面图
  从 528″ 归一到信纸尺寸）；ForeignData 光栅（PNG/JPEG/GIF/BMP）嵌入；PolylineTo
  端点回退；导入→移形→另存 `.vsdx`→再开单测。导出仍为 `.vsdx`（不写二进制 `.vsd`）。
- 2026-07-17 — **`.vsd` VSD5 导入**：对照 libvisio `VSD5Parser` 补齐 Visio 5
  指针 / chunk header / list 子记录 / Line·Fill 索引色 / Shape 字段宽度；
  libvisio 全部 `.vsd` 样例可解析；另存仍为合成 `.vsdx`。
- 2026-07-17 — **`.vsd` ForeignData 位图**：按 `foreignType/format` 识别 JPEG/PNG/GIF，
  并对 DIB（无 BM 头）重建 BITMAPFILEHEADER（对照 libvisio `_handleForeignData`）；
  `bitmaps.vsd` 20 张图入库且合成 vsdx 往返保留。EMF/WMF/OLE 仍跳过。
- 2026-07-17 — **`.vsd` 协议对齐加深**：InfiniteLine / SplineStart·Knot / NURBSTo /
  ShapeData 折线·NURBS / TextField 数值占位展开；空 GeomList 不再挡住图片框
  矩形兜底；`parseVisio` 编辑模型改用二进制解析结果（合成 vsdx 仅作 Writer 基线），
  避免 write→reparse 丢掉字段文本与图片框几何。
- 2026-07-17 — **`.vsd`→vsdx 合成保真**：`_buildPictureElement` 写出 Foreign 时一并
  写入 Geometry（修复 bitmaps 另存后丢框）；Misc `HideText` 导入。
- 2026-07-17 — **`.vsd` Name / TextXForm / Font**：Name2+NameIDX 页名（如
  `Zeichenblatt-1`）、形状 Name、TxtXForm→textBlock、FontFace→CharIX
  fontFamily；字符串 TextField 经 Name 表展开；纯数字伪页名回退 `Page-N`。
- 2026-07-17 — **`.vsd` FontIX / TextBlock / ParaIX**：VSD6 FontList+FontIX
  （`getUInt` codePage + ANSI 名）正确解析为 Liberation Sans 等；TextBlock
  页边距/垂直对齐/背景；ParaIX 水平对齐/缩进/行距/项目符号写入富文本；
  CharIX 补 underline/smallCaps。另存仍为合成 `.vsdx`。
- 2026-07-17 — **`.vsd` Name ANSI / 样式链 / Layer**：VSD5/6 Name·Name2 按
  ANSI（非 UTF-16）解码，修复 `esc(5)` / `80,00 sq. ft.` 乱码；StyleSheet
  父链 + CharIX/ParaIX/TextBlock 样式继承（TextFields 字体）；Layer /
  LayerMem 导入。另存仍为合成 `.vsdx`。
- 2026-07-17 — **`.vsd` TextField 日期格式**：解析 format 块（`0x80/0xc2`）与
  `CELL_TYPE_Date`→MsoDateShort；Visio 序列日转日历（如 `43652.139`→`7/6/2019`）；
  常用数值精度/单位后缀。自定义 `{{…}}` 与甘特 Number 序列仍按 libvisio 同等限制。
- 2026-07-17 — **`.vsd` TextField 单位/角度/货币**：对齐 libvisio `convertNumber`
  （英寸→mm/cm/…、弧度→度）；`CELL_TYPE_AngleUnits` + Degrees/Radians/DMS；
  format 块 `0x60` 自定义 UTF-16 格式（如 `<,$>U #,##0.00`→`$1.00`）。libvisio
  仅认 `0x62`+`0x80/0xc2`，`0x60` 为本项目增强。面积 Multidimensional 已于后续条目补齐。
  `{{…}}` 自定义串仍有限。
- 2026-07-17 — **`.vsd` 多 run CharIX/ParaIX + TabsData**：按 `charCount` 拆分
  富文本 runs（对照 libvisio `m_charList`/`m_paraList` 文本遍历）；解析
  TabsData（`0x88`/`0x96`/`0x97`/`0xb5`）写入 `VsdxTabSet`；字段占位在拆分后再
  展开以免 charCount 错位。另存仍为合成 `.vsdx`（Writer 已支持 Tabs / multi-run）。
  CharList/ParaList trailer 重排已落地（见同日后续条目）。
- 2026-07-17 — **`.vsd` Gantt Number 序列日**：`CELL_TYPE_Number` 且无 format 块时，
  将落在 20000–60000 的 Visio 序列日格式化为日历（libvisio 此处返回空串）；并识别
  format 块类型 `0x70`（样例中的备用 format id）。`tdf76829-datetime-format` 的
  raw `37xxx` 已清零。
- 2026-07-17 — **`.vsd` CharIX 扩展 + EMF/WMF 入库**：对齐 libvisio `readCharIX`
  的 Case/Pos/Strike/FontScale（allcaps/initcaps/super/sub/双下划线/删除线/
  `scaleWidth/10000`）；ForeignData `type` 0/4 按签名识别 EMF/WMF 写入 media
  （`EnhMetaFile`/`MetaFile`）供另存 vsdx 往返；画布侧后续对嵌入 DIB 的 EMF
  做了提取绘制。OLE / Multidimensional 面积见下一条。
- 2026-07-17 — **`.vsd` ShapeList z-order + 字符串字段大小写**：应用页面/组
  ShapeList trailer 顺序组装根与子形状（此前只收集未使用）；字符串 TextField
  识别 format 37/38/39（StrNormal/Lower/Upper，libvisio 仍为 TODO）→
  `TheDoc`/`THEDOC`/`thedoc`。
- 2026-07-17 — **`.vsd` Multidimensional 面积 + OLE + 缺字体 + EMF 画布**：
  TextField `CELL_TYPE_Multidimensional`(233) 解析尾部 `0x46 <sqIn F64> <unit> 0x02`
  （平方英寸→acres/ha/cm²/…，超出 libvisio TODO）；`oleList`/`oleData` +
  `foreignType==2` → media `object/ole` / `ForeignType=Object`；无 CharIX 时
  `fontFamily` 回退 `Arial`；画布对含嵌入 DIB 的 EMF 提取位图绘制，其余
  EMF/WMF/OLE 显示对角占位。**二进制 `.vsd` 写回仍按产品决策延后**（仅另存 `.vsdx`）。
- 2026-07-17 — **`.vsd` Name 字段表 + VSD5 TextField 格式**：`readName` 对齐 libvisio
  写入 shape-local 名字表（`esc(N)` / 字符串字段），不再污染 `VsdxShape.name`；
  VSD5 文本流 `0x1E`+空格+`(formatId+0x20)` 解码格式并去掉编码字节（超出
  libvisio VSD5 `format=Unknown`），Visio5/6 TextFieldsWithUnits 单位输出对齐。
  CharList trailer 重排 / Connect 导入 / 图层真名仍后续。
- 2026-07-17 — **`.vsd` CharList/ParaList/FieldList/TabsDataList trailer 重排**：
  VSD6/11 读 list trailer 子 id 序列并对齐 libvisio `setElementsOrder`，在构建
  rich text 前重排 CharIX / ParaIX / TextField / TabsData；VSD5 仍走
  `_handleChunkRecords`（无独立 trailer 消费）。Connect / 图层真名仍后续。
- 2026-07-17 — **`.vsd` DrawingUnits/PageUnits + stencil FieldList**：PageProps
  `drawingScaleUnit` → `VsdxPageSheet.drawingScaleUnit`；TextField cell 63/64
  按页面默认单位格式化（对齐 libvisio `m_defaultDrawingUnit`）；实例 FieldList
  继承 master 的 format（`format=Unknown` 时）。`tdf154379` → `180.0 cm x 394.0 cm`。
  Connect / 图层真名 / FeetAndInches(10,13–18) 仍后续（后者 libvisio 亦 TODO）。
- 2026-07-17 — **`.vsd` OLE 元数据 + TextBkgnd 透明 + MsoDateShort**：读
  `\x05SummaryInformation` → `title`/`creator`，`synthesizeVsdx` 写入
  `docProps/core.xml`；TextBlock `bgIdx` 0/0xff 显式透明覆盖 master/style 白底；
  MsoDateShort 对齐 libvisio `%m/%d/%Y`（`07/06/2019`）。Connect / 图层真名仍后续。
- 2026-07-17 — **`.vsd` → `.vsdx` 万兴图示填充对齐**：无 Fill 块时默认实心白
  （`FillForegnd=#FFFFFF` + `FillPattern=1`），Writer 在 `pattern≠0` 且无前景色时
  亦补写 `FillForegnd`，避免万兴图示将「有 Pattern 无 Foregnd」渲染为空心。
  libvisio 样例批量导出结构检查全 `ok`；本机万兴图示可打开 FormatLine / Plan /
  bitmaps / DrawingUnits / TextFields 等。Connect / 图层真名仍后续。
- 2026-07-17 — **`.vsd` 1D 负宽高保真**：`_toShape` 不再把 1D 的 `Width`/`Height`
  （`End−Begin`，可为负）钳成 `1.0`；避免 LocPin 与合成 `.vsdx` 在万兴图示中错位。
  **二进制 `.vsd` 写回**：libvisio 亦无 Writer（仅 parse）；产品线仍为导入 → 另存
  `.vsdx`（OLE2/CFB ShapeSheet 序列化无参考实现，短期不做）。Connect / 图层真名仍后续。
- 2026-07-17 — **`.vsd` FeetAndInches / 分数格式**：实现 format 10/13/14（`20'-6"` /
  `# #/#` / `# #/##`）与 15–18 分数，超出 libvisio `VSDFieldList` TODO；
  `Visio11PlanWithDimensions` 的 Geometry Height 由 `20.5` → `20'-6"`。
  Connect / 图层真名仍后续；另存仍为 `.vsdx`。
- 2026-07-17 — **`.vsd` NameIDX 形状/图层显示名**：页面作用域吸收 NameIDX（跳过
  style/stencil/属性字段表），绑定 `VsdxShape.name` 与匹配的 Layer 名（如
  `Wall`、`"L" Room`、`Dimension line`）；Name 块仍只作字段表。超出 libvisio
 （其 IR 不保留显示名）。ConnectList 仍后续；另存仍为 `.vsdx`。
- 2026-07-17 — **`.vsd` Connection Points**：解析 `0x99`/`0xba`（X/Y[/DirX/DirY]/Type），
  继承 master、按页面 scale 缩放、去重后写入合成 `.vsdx` 的 `<Section N="Connection">`
  （万兴图示胶合目标）。libvisio 仅有常量无 Reader。ConnectList `0x72` 胶合边仍后续；
  另存仍为 `.vsdx`。
- 2026-07-17 — **`.vsd` Control / Shape Data**：解析 Control `0xaa`/`0xa2`
  （X/Y/XDyn/YDyn + XCon/YCon/CanGlue）与 Custom Props `0xb6`（Value/Type +
  Prompt/Label/Format 字符串；实例 Value 与 master Label 按 id 合并），写入合成
  `.vsdx` 的 `<Section N="Control">` / `<Section N="Property">`。libvisio 仅有
  常量无 Reader；样例中无 ConnectList `0x72` 数据。另存仍为 `.vsdx`（不做二进制
  `.vsd` 写回）。
- 2026-07-18 — **`.vsd` Scratch / User / Actions**：解析 Scratch `0x9e`
  （X/Y/A/B/C/D）、User `0xb4`（Value + 名称/Prompt）、ActId `0xa9`（Menu/Tag），
  写入合成 `.vsdx` 对应 Section。libvisio 仅有常量无 Reader。ConnectList `0x72`
  / Hyperlink `0xc4` 仍后续（样例中无或极少）；另存仍为 `.vsdx`。
- 2026-07-18 — **`.vsd` Protection / Group**：解析 Protection `0xa0`（LockMoveX/Y →
  `locked`）与 Group `0xbe`（SelectMode/DisplayMode/DontMoveChildren/
  IsTextEditTarget），写入合成 `.vsdx` 保护位与 Group 行为 Cell。libvisio 仅有
  常量无 Reader。ConnectList / Hyperlink / Event 公式仍后续；另存仍为 `.vsdx`。
- 2026-07-18 — **`.vsd` Hyperlink `0xc4` / ConnectList `0x72`**：用 Apache POI
  样例（`visio_with_embeded.vsd`、`44594*.vsd`）补齐。Hyperlink：flags@39
  （NewWindow/Default）+ `0x60` UTF-16 串（Description/Address/SubAddress…）→
  `VsdxHyperlink` / `<Section N="Hyperlink">`（HyperLnkList `0x73` 排序）。
  ConnectList：仅见空 list 头（`childrenListLength=0`），安全跳过、不臆造
  Connect 边；非空胶合样例与 Event 公式仍后续。另存仍为 `.vsdx`。
- 2026-07-18 — **`.vsd` Event `0x84` 公式**：解析公式块（`u32 len + cellRef`；
  2=EventDblClick / 3=EventXFMod / 4=EventDrop），识别 `OPENTEXTWIN()`（`80 4c`）
  与 `RUNADDONW("…","/CMD=…")`（UTF-16 `0x60` 串），写入 `formulas` 并合成
  `.vsdx` Event 单元格。libvisio 仅有常量无 Reader。非空 ConnectList 仍后续。
- 2026-07-18 — **格式能力澄清（产品）**：打开 `.vsdx` + 旧版 `.vsd`；编辑共用
  `VsdxDocument`；**保存 / 另存仅为 `.vsdx`**（load-preserve-patch）。**不做**
  二进制 `.vsd` 写回。空态文案已写明可开 `.vsd`、保存为 `.vsdx`；导入 `.vsd`
  后清空 `filePath`，避免 OPC 字节覆盖源文件；`tool/edraw_roundtrip_check.dart`
  批量校验 vsdx 往返与 vsd→vsdx（配合万兴图示打开）。
- 2026-07-18 — **导出 `.vsdx` 互操作**：Save 时愈合缺失的 `docProps/core.xml`；
  对本地有 `<Text>` 但无 Character 的形状（含仅有 `<pp>`、Master 本地文本）补
  Character/Paragraph；Foreign 图片 caption 同步写出样式段。纯矢量 EMF/WMF
  画布占位仍后续。
- 2026-07-18 — **画布 metafile 保真**：WMF/EMF 矢量回放（polygon/polyline/text/
  pen/brush）+ OLE `\x02OlePres000` 提取 EMF 预览；`VsdxImageCache` 先试嵌入
  DIB，再光栅化矢量显示列表。LibreOffice 平面图 `.wmf` 与 `visio_with_embeded`
  OLE 预览可画。
- 2026-07-28 — **对齐 draw.io 吸附编辑**：`computeSnap` 新增页面水平/垂直中心吸附
  （橙色全页线）和三形状等距间隔吸附（紫色间隔线），保留蓝色边/中心/连接点对齐；
  Diagram / More 增加独立 Guides 开关。修饰键校正为 Ctrl/Cmd 拖拽复制，Alt/Option
  临时绕过网格、动态/永久参考线、连接点胶合和容器落入；覆盖形状移动/缩放、连接器端点/
  路径点与标尺参考线。新增纯函数、控制器和画布组件回归。
- 2026-07-28 — **对齐 draw.io 选择与精调编辑**：命中测试保留局部 z 序，Alt 点击可在
  重叠对象间向下轮选；Shift/Ctrl/Cmd 点击切换多选。框选默认只取完整包含的顶层对象，
  Alt 框选改取相交对象并可选嵌套子形状，修饰键框选支持反选。Space 从对象/手柄上起拖
  也强制平移；Alt 滚轮缩放、Shift 滚轮横移。补 Ctrl/Cmd+Shift+方向键增减宽高和
  Alt+Shift+R 清除连接器折点，并确保文本输入聚焦时这些快捷键不会修改图形。
- 2026-07-28 — **对齐 draw.io 快速搭图与层级遍历**：双击画布空白处复用 QuickAdd
  常用图形选择器，选中后在点击位置按网格落图并继承当前样式；Alt+Shift+方向键优先
  连接对应方向已有邻居，否则克隆当前形状并自动胶合，整体单步撤销。Tab/Shift+Tab
  改为按绘制顺序进入展开容器的可见子对象，Alt+Tab 选择直接父容器；文本输入聚焦时
  保留系统光标/选区快捷键。新增控制器、快捷键、选择器与画布组件回归。
- 2026-07-28 — **对齐 draw.io Arrange 进阶操作**：新增 Swap Shapes，按页面空间中心
  交换两个不同尺寸或不同父级形状的位置；新增会话级 Copy Size / Paste Size，复用分组、
  泳道与表格的保真缩放并保持目标左上角；新增连接线 Reverse，完整交换起止胶合目标、
  固定连接点、折点、箭头及 Beg/End trigger 公式，整体单步撤销。Format 面板同步提供入口，
  并新增三个控制器及一个模型回归测试。
- 2026-07-28 — **对齐 draw.io 形状自适应与替换编辑**：新增 Autosize 与
  Cmd/Ctrl+Shift+Y，按当前宽度测量富文本换行高度并保持页面空间左上角，多选合并为单步
  撤销；普通组在 Ctrl/Cmd 拖动缩放手柄时只改变外框，子形状尺寸与局部位置保持不变，
  泳道和表格继续使用结构化重排；图形库支持 Shift 点击替换所有可替换的已选原子形状，
  保留 ID、位置尺寸、旋转、文本、样式、数据、链接与连接线胶合，并支持单步撤销。新增
  控制器与应用级快捷键回归测试。
- 2026-07-28 — **对齐 draw.io 文字与标签编辑**：选中形状或连接线后直接输入首字符即
  进入内联编辑并覆盖原标签；Enter 保存，Shift/Alt+Enter 明确插入换行，避免平台键盘
  行为差异。Format / Text 增加标签左、上、居中、下、右五向定位及竖排文字开关；定位
  使用 Visio `TxtPin*` / `TxtLocPin*` / `TxtWidth` / `TxtHeight`，同步段落靠边方式并清除
  会覆盖新位置的旧公式，`TextDirection` 控制竖排。补充画布键盘交互、单步撤销、多选及
  VSDX 导出回读回归测试。
- 2026-07-28 — **对齐 draw.io 高级修饰键拖拽**：Alt+Shift 从画布空白处拖拽可远程移动
  当前选择，保留自由双轴位移并绕过吸附；Alt+Ctrl/Cmd+Shift 从空白处拖拽以起点为切线，
  分别移动完整位于水平/垂直拖拽侧的顶层图形，交叉象限对象同时沿双轴移动，并显示橙色
  起止参考线；Alt+Shift 从图形上强制框选并只从当前选择中减去相交对象。区域位移跳过
  锁定图形/图层，自动重算公式与连接线路由；远程移动连接线时解除未随动目标的胶合，
  与连接线共同移动的目标则保持胶合。所有模型拖拽均合并为单步撤销。
- 2026-07-29 — **对齐 draw.io 移出组合**：为普通组合的已选子项增加 Format / Arrange
  面板与右键菜单 `Remove from Group`，复用父子重挂载并保持页面空间位置、公式和连接线
  路由，支持单步撤销；补齐把子项直接拖出组合边界的画布回归。命令显式排除表格、泳道池
  和图表等结构化父项，并遵守形状、父组合及图层锁定状态，避免误拆内部结构。
- 2026-07-29 — **对齐 draw.io 容器折叠命令**：补齐 Ctrl/Cmd+Home 折叠选区与
  Ctrl/Cmd+End 展开选区，并在所选可折叠容器的右键菜单动态显示 Collapse / Expand。
  多选容器批处理合并成一个撤销步，跳过普通图形、锁定容器和锁定图层；折叠时继续复用
  现有高度收缩、子树隐藏、胶合暂存及展开恢复逻辑。新增控制器、应用快捷键和画布菜单回归。
- 2026-07-29 — **对齐 draw.io 辅助鼠标键平移**：编辑模式下按住鼠标右键或中键拖动可
  临时切换为手形平移，无需先选 Pan 工具；从已选图形上起拖也只移动视口，不改变图形位置
  或撤销历史。原始指针链区分辅助键拖动与静止右击，保证右键单击仍打开上下文菜单，拖动
  结束则不会误弹菜单；平移期间同步抓取光标和 Outline camera，并补画布组件回归。
- 2026-07-29 — **对齐 draw.io 表格行复制能力**：选中单元格或同一行的多个单元格后可
  深拷贝整行到其下方，保留单元格样式、文字、嵌套内容及完全位于行内的连接关系；跨目标行
  的合并块先展开以维持合法网格。整行与整表复制统一 fresh ids、公式/胶合重写、选中新副本
  与单步撤销，并确保文本输入聚焦时 Enter 类快捷键仍交由编辑器处理。快捷键的 draw.io
  精确映射见同日后续“Enter / Ctrl+Enter 精确语义”条目。
- 2026-07-29 — **对齐 draw.io 表格删除快捷键**：Delete/Backspace 选中单格或同行多格时
  删除整行，选中某列全部可见单元格时删除整列，统一复用结构化重排、连接清理、公式重算与
  单步撤销；稀疏/混合选择、锁定表格、最后一行或一列均不允许退化为直接删除子单元格。
  `deleteSelection`、直接按 ID 删除和 Cut 三条入口均增加结构保护，并补控制器与应用级
  快捷键回归。
- 2026-07-29 — **对齐 draw.io Enter / Ctrl+Enter 精确语义**：按 draw.io 30.3.6
  `keyPressEnter` / `ctrlEnter` 源码校正快捷键：普通 Enter 请求画布打开单选图形的内联
  标签编辑；Ctrl/Cmd+Enter 复制当前普通单选或多选，表格单元格（或同行单元格多选）提升
  为整行复制，只有直接选择表格根时才复制整表。新增控制器到画布的单调序号编辑请求通道，
  保持工具栏失焦后的快捷键可用，并确保任意 TextField 聚焦时两种 Enter 均不劫持输入。
  补普通多选、表格单元格/表格根、内联编辑打开与文本输入保护回归。
- 2026-07-29 — **对齐 draw.io 删除修饰键**：按同版键位表补
  Ctrl/Cmd+Delete/Backspace 删除选区及未锁定关联连接线，复用既有连接清理并保持单步撤销；
  Shift+Delete/Backspace 仅清空选中图形标签，多选统一为一个历史记录。应用级快捷键与画布
  Focus 本地处理保持一致，普通与内联 TextField 聚焦时继续让系统处理按词/选区删除。
  新增普通多选标签、关联连接线、画布焦点和文本输入保护回归。
- 2026-07-29 — **对齐 draw.io 视图与导航快捷键**：补 F2 编辑标签、Home 恢复
  100% 并居中、Ctrl/Cmd+J 适配当前页、Ctrl/Cmd+Shift+G 切换网格、
  Ctrl/Cmd+Shift+O 切换 Outline、Ctrl/Cmd+Shift+L 切换图层面板。新增控制器到画布的
  单调序号重置视图请求，保证工具栏失焦时仍能驱动画布；同时把 Home/End 纳入文本输入
  焦点保护，避免抢占行首/行尾导航。补应用快捷键、面板显隐和 camera 变换回归。
- 2026-07-29 — **对齐 draw.io 上标/下标与清除文字格式**：Format / Text 增加
  上标、下标和 Remove Formatting；控制器以 `VsdxTextPosition` 写入 Visio `Char.Pos`，
  支持整标签或内联 UTF-16 选区、再次切换恢复普通基线，并复用现有解析、画布/SVG 渲染和
  Writer 往返。内联编辑补 Ctrl/Cmd+. 上标、Ctrl/Cmd+, 下标，非编辑状态不抢占系统
  Cmd+,；清除格式只重置字符样式，保留文字和段落布局。补选区拆分、撤销及画布快捷键回归。
- 2026-07-29 — **对齐 draw.io Select Connections / Clear Anchors**：形状右键菜单可把
  当前选区的可见关联连接线追加进选择；固定锚点清除同时覆盖直接选择的连接线与所选形状的
  关联连接线，把 `ToPart≥100` / `Connections.Xn` 恢复为 `ToPart=3` / `PinX` 自动边界
  胶合，保留两端目标、刷新路由并合并为单步撤销。命令跳过锁定连接线和锁定图层，复用现有
  Connect 与 Writer 往返。补控制器选择/锚点/撤销及画布右键菜单回归。
- 2026-07-29 — **对齐 draw.io Turn / Reverse 与 Copy/Paste Data**：
  `Cmd/Ctrl+R` 对普通形状执行 90° 旋转、对连接线执行端点/固定连接点/路径/箭头语义反向，
  混合选择合并为单步撤销，并在右键菜单按选择显示 Turn / Reverse。Shape Data 剪贴板完整
  保留 Property 行的 label/prompt/format/type/formula 等元数据；右键 Paste Data 保留目标
  标签，`Alt+Shift+B/E` 按 draw.io 的 Shift 语义同时粘贴源标签，多选批量应用并跳过锁定
  形状/图层。补控制器、应用级快捷键和画布菜单回归。
- 2026-07-29 — **对齐 draw.io 缩放菜单与页面宽度适配**：画布实时百分比改为缩放下拉，
  对齐 25%–400% 九档预设、Fit Window、Fit Page Width 与 Custom Zoom；自定义输入校验后
  以视口中心为焦点缩放。Fit Page Width 仅按可用宽度计算比例，水平居中并保留当前垂直
  阅读位置，同时接入控制器请求通道、紧凑工具栏和空白画布右键菜单。复用 draw.io 资源为
  37 种界面语言补齐文案，并增加 camera 变换、菜单交互和本地化完整性回归。
- 2026-07-29 — **对齐 draw.io Copy as Text / Open Link**：首个选中图形可将纯标签文本
  写入系统剪贴板，并通过串行写入避免被尚未完成的图形剪贴板任务覆盖；右键菜单、紧凑更多
  菜单和 Format / Link 面板接入 Open Link。`#Page-X`、页面名及常见页内后缀直接在应用内
  定位页面，外部地址经安全协议白名单交给系统打开。两项操作补齐 37 种界面语言，并覆盖
  内外部链接、失败路径及剪贴板竞态回归。
- 2026-07-29 — **对齐 draw.io Copy/Paste Text Style**：增加独立于图形样式剪贴板的文字
  样式剪贴板，Copy 按 `Alt+Shift+C` 捕获字体、字号、颜色、强调、段落对齐、文字边距、背景、
  垂直对齐和文字方向；保留目标标签、填充、线条、效果及文字框位置。命令接入 Text 面板、
  更多菜单与右键菜单，组合粘贴覆盖后代并跳过锁定部件，单步撤销；文案直接对齐 draw.io
  的 37 种语言资源，并补控制器、快捷键、本地化与窄布局回归。
- 2026-07-29 — **对齐 draw.io 关系树选择与多页键盘操作**：新增 Select Children /
  Subtree / Parent / Siblings，优先按连接线 Begin→End 方向遍历流程树，无连线关系时
  回退普通组/容器层级；循环图去重、折叠子树和隐藏图层不进入选择。右键菜单及上下文
  `Alt+Shift+X/T/P/S` 接入，`Alt+Shift+C` 保留给 Copy Text Style。
  无图形选择时 Ctrl/Cmd+方向键选择相邻/首尾页，Shift+方向键重排当前页，
  Ctrl/Cmd+Shift+PageUp/PageDown 切换相邻页；有 2-D 选区时 Ctrl/Cmd+方向键按 1pt
  精调尺寸，保留 Ctrl/Cmd+Shift+方向键按网格调整。新增控制器、应用快捷键、画布菜单、
  37 语言与撤销回归。
- 2026-07-29 — **对齐 draw.io 高级快捷键有效映射**：直接核对 `Actions.js`、
  `EditorUi.js` 与 Trees 插件，补 `Cmd/Ctrl+Shift+S` Save As、
  `Cmd/Ctrl+Shift+H` Fit Window、`Cmd/Ctrl+Shift+E` Select Edges、
  `Cmd/Ctrl+{/}` 整标签字号、`Alt+Shift+F/V` Copy/Paste Size、
  `Alt+Shift+L` Edit Link 与 `Alt+Shift+Q` Edit Connection Points；同步将关系树键位
  校正为 `Alt+Shift+X/T/P/S`，Select Subtree 同插件包含根节点、后代与遍历连接线，
  使 `Alt+Shift+C` 不再被树命令抢占。补应用级快捷键、
  编辑聚焦隔离、连接点模式与尺寸粘贴回归。
- 2026-07-29 — **对齐 draw.io Connection Arrows / Connection Points 开关**：
  新增会话级独立状态与 More 菜单复选项，接入源码定义的 `Alt+Shift+A/O`。关闭 Arrows
  同时移除四向快速新增/连线图标、点击和拖拽命中区，避免不可见热点；关闭 Points 后隐藏
  蓝色固定点，禁止从固定点/轮廓起线及固定点吸附，但连接器工具仍可使用普通浮动边界胶合，
  显式 Edit Connection Points 模式不受影响。补控制器快捷键、本地化、画布关闭态与胶合
  语义回归。
- 2026-07-29 — **对齐 draw.io Extras 与精确 Z 序键位**：新增 Copy on Connect 和
  Collapse/Expand Controls 会话开关。前者让箭头拖线或连接器工具落到空白处时复制源图形、
  自动胶合并合并为单次撤销；后者统一控制折叠箭头绘制、命中及 Ctrl/Cmd+Home/End 命令，
  关闭时保留文档既有折叠状态。补源码定义的 `Cmd/Ctrl+Alt+Shift+F/B` 单层前移/后移，
  并覆盖状态、本地化、真实画布拖拽与两平台快捷键回归。
- 2026-07-29 — **对齐 draw.io Smart Fit 与全局缩放键**：无选区 Enter 按源码语义在
  100% 居中和 Fit Window 间智能切换；将 `Cmd/Ctrl+0` 从旧的静默重置校正为打开已验证的
  Custom Zoom 百分比对话框，100% 重置继续由 Home 承担。`Cmd/Ctrl +/-` 通过控制器请求
  提升为应用级快捷键，工具栏/侧栏取得焦点后仍可缩放，同时保留画布聚焦时的直接响应。
  补控制器信号、画布双态判定、真实对话框与跨焦点快捷键回归。
- 2026-07-29 — **对齐 draw.io Edit Tooltip 与 Tooltips 开关**：More 与图形右键菜单
  增加多行 Tooltip 编辑/清空入口，控制器以单步撤销写入 `User.veTooltip`，通用 User
  Section writer 保证 `.vsdx` 往返；画布在指针停留 500ms 后显示跟随式提示，Extras
  Tooltips 开关可会话级隐藏而不删除文档内容。上游基础动作与 Trees 插件都占用
  `Alt+Shift+T`，本应用保留已对齐的 Select Subtree 有效键位，避免 Tooltip 覆盖关系树
  导航。补模型保留、换行往返、对话框、撤销、悬停延迟、关闭态及中英文回归。
- 2026-07-29 — **对齐 draw.io Snap Selection to Grid / Select None**：按
  `Graph.snapCellsToGrid` 增加一次性选区网格校正，将普通图形左下位置与宽高、连接器显式
  折点分别取整到当前网格；锁定图形/图层不参与，混合选区合并为单次撤销。命令接入 More、
  图形右键菜单与 Arrange，且与只控制后续拖拽的 Snap to Grid 开关明确分离。More 同步
  补 Select None，并覆盖 draw.io 的 `Cmd/Ctrl+Shift+A` 应用级键位、中英文文案、
  控制器几何/撤销和真实菜单点击回归。
- 2026-07-30 — **对齐 draw.io Distribute / Distribute Spacing 精确语义**：
  对照 `Graph.distributeCells(horizontal, cells, spacing)` 将原有水平/垂直分布校正为等分
  图形中心，并新增水平/垂直等间距命令，以可见 AABB 边缘计算不等尺寸图形间隙。两套命令
  接入 More 与 Arrange，只在三个以上非连接线选区根可用，保留两端锚点、锁定过滤和单步
  撤销；补不等宽/不等高差异、连接线计数、嵌套根及既有锁定行为回归。
- 2026-07-28 — **应用内 AI 对话闭环**：新增可持久配置的 OpenAI-compatible /
  Anthropic / Gemini / Ollama 引擎（接口、模型、API Key）和多轮对话工具；统一系统提示让
  模型输出完整 Diagram Spec v0，兼容提取 Mermaid，校验节点唯一性与连接边引用后复用
  `DiagramSpec.build()` 自动布局并在新标签页创建可编辑 `.vsdx`。设置页增加 AI 引擎入口
  和应用内帮助，覆盖旧有 Agent live preview、MCP、CLI、Agent Skill 的启用与使用方式；
  新增独立 `docs/AI_INTEGRATION.md`。macOS 增加 outbound network entitlement，并补四类
  协议封装、响应解析、错误脱敏、配置持久化、对话建图与窄屏布局回归。
