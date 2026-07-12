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
- [ ] LibreOffice `soffice --headless` 交叉验证 —— 本机未安装 soffice，留待安装后或 CI 执行

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

已补：**对齐 drawio 交互** —— 智能对齐辅助线（拖拽吸附邻近形状边/中心 + 洋红辅助线，纯函数
`snap_guides.dart` 可单测）、右键上下文菜单、复制/粘贴样式、**分组/取消分组**（往返，Writer
重建 `<Shape>` 子树）、drawio 快捷键（全选/剪切/置顶置底/分组/复制粘贴样式）与画布键盘缩放。

已补：**格式面板对齐 drawio** —— 线条虚线样式（实线/虚线/点线/点划线）、箭头（起/止）、
填充/线条不透明度滑块；均往返（`LinePattern`/`BeginArrow`/`EndArrow`/`FillForegndTrans`/
`LineColorTrans`）。移动拖拽按住 Shift 锁定单轴。

已补：**连接器直线/正交路由**（每条连接器可选直线或正交肘形，`straightRoute` 标记随重路由保持）、
Alt 拖拽复制。

已补：**连接器可拖拽折点（waypoints）** —— 选中连接器显示折点（实心）与线段中点（空心）手柄：
拖中点新增折点、拖折点移动、双击折点删除；`VsdxShape.waypoints` + `VsdxPage.connectorRoute/
setConnectorWaypoints`，路由经折点且随重路由/移动保持（移动连接器时折点同步平移）。

已补：**文本 Format 面板补全 + 阴影** —— 字体族（下拉）、下划线、垂直对齐（上/中/下）、投影开关；
均往返（`Font`/`Style` 下划线位/`VerticalAlign`/`ShadowPattern`）。

已补：**Arrange 面板对齐 drawio** —— 数值位置/尺寸（X/Y/W/H）与旋转角输入、水平/垂直翻转、
旋转 90°（Cmd+R/Cmd+Shift+R）、单步 Bring Forward/Send Backward（补足既有置顶/置底）；均往返
（`PinX/PinY/Width/Height/Angle`、`FlipX/FlipY`、`<Shape>` 重排）。

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

剩余：
- macOS 代码签名 / 公证（notarization，需证书）；其他平台（Windows/Linux/Android/iOS）
- `.vsd` 老格式经 libvisio 导入
- 连接器避让路由；富文本"逐 run 选区"编辑；公式重算引擎；矢量 PDF；LibreOffice `soffice` 交叉验证

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
  Cmd+Alt+C/V 复制/粘贴样式；画布内键盘缩放（Cmd +/- 、Cmd+0=100%、Cmd+Shift+H=适应）。App 测试
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
- 2026-07-11 — **对齐 drawio 交互（批次四）——连接器直线/正交路由 + Alt 拖拽复制**：模型加
  `VsdxShape.straightRoute`（默认 false=正交肘形，保持既有默认）；`VsdxPage.rerouteConnectors`
  依据该标记选直线或肘形，新增 `setConnectorStyle/isConnectorStraight`；`EditorController`
  `hasConnectorSelected/selectedConnectorStraight/setConnectorStyle`；属性面板“Connector”区
  （Straight/Orthogonal 选择）。画布 Alt 拖拽=复制后拖动副本。控制器单测（切换直/正交并经重路由保持）。
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
