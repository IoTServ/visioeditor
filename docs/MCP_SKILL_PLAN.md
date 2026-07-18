# MCP 与 Skill 开发规划（Agent 接口）—— Roadmap & Tracker

> 本文件是 **visioeditor 的「AI Agent 接口」子系统**（MCP 服务器 + Agent Skill +
> 无头 CLI + 应用实时预览桥）的主开发规划与进度跟踪表。风格对齐主
> [`PLAN.md`](./PLAN.md)。配套文档：
> [`ARCHITECTURE.md`](./ARCHITECTURE.md) · [`VSDX_WRITE.md`](./VSDX_WRITE.md) ·
> [`references/`](./references/)。
>
> 参考项目（克隆于 `third_party/`，不入库）：
> - **`Agents365-ai/drawio-skill`**（MIT，v1.34.0）—— 纯 `SKILL.md` + 31 个 Python 脚本，
>   自然语言 → `.drawio` → 导出 PNG/SVG/PDF，含自检回路、导入器、样式预设。
> - **`jgraph/drawio-mcp`**（Apache-2.0，`@drawio/mcp` v1.4.1）—— 官方 MCP：
>   `mcp-tool-server`（浏览器打开）/ `mcp-app-server`（聊天内联渲染）/ Claude Code 插件 /
>   `shape-search`（1 万+形状索引）/ `shared`（xml/style/mermaid 参考）。

状态标记：`TODO` 未开始 · `DOING` 进行中 · `DONE` 完成 · `LATER` 后续里程碑

---

## 1. 目标与非目标

### 1.1 目标

为 visioeditor 提供一套与 drawio-skill / drawio-mcp **对等且更强**的 AI Agent 接口，
让 Cursor / Claude Code / Codex 等任意 Agent 能：

1. **自然语言 → `.vsdx`**：描述需求（流程图/组织架构/网络拓扑/架构图/ERD/UML…）即生成
   保真、可再编辑的 `.vsdx`（而非有损图片）。
2. **改现有 `.vsdx`**：以结构化编辑操作增删改形状/连接器/样式/文本/页面，**往返保真**
   （复用 Writer 的 load-preserve-patch，只改动过的 Cell，其余原样透传）。
3. **实时预览（本规划重点）**：在**正在运行的 visioeditor 桌面应用**里即时看到 Agent 的每一步
   改动——打开、重载、应用补丁、选中、快照回传，做到「边说边画、所见即所得」。
4. **自检回路**：Agent 用视觉能力读回渲染图（PNG），自动修正重叠/裁切/连线穿越等问题
   （对齐 drawio-skill Step 5），最多 N 轮。
5. **导入器**：把代码依赖图 / IaC / SQL DDL / Mermaid / OpenAPI / 现有 `.vsd`·`.vsdx`
   转成自动布局的图（对齐 drawio-skill 的 importers，复用本仓已有的 `.vsd` 解析与
   `ObstacleRouter` 避障路由）。

### 1.2 非目标（本子系统不做）

- 不重写引擎：**一切都复用 `package:vsdx`**（parser/writer/model/formula/export）与
  `EditorController` 的既有能力，Agent 接口只是「薄壳 + 编排」。
- 不做二进制 `.vsd` 写回（沿用主线产品决策：导入 → 另存 `.vsdx`）。
- 不引入云端服务；实时预览一律走 **loopback（127.0.0.1）**，默认对外不可见。

---

## 2. 参考项目要点提炼

| 维度 | drawio-skill（skill） | drawio-mcp（MCP） | visioeditor 的对应做法 |
| --- | --- | --- | --- |
| 生成载体 | `.drawio` XML（文本） | 同左 | **`.vsdx`（OPC/ZIP）**，经 `VsdxWriter` 往返保真 |
| 渲染/导出 | shell 出 `draw.io` 桌面 CLI（Electron，慢、沙箱易崩） | diagrams.net URL / 内联 SVG | **纯 Dart 无头**：`VsdxToSvgSerializer`（SVG）+ 应用光栅化（PNG）——无 Electron、无显示依赖 |
| 形状词汇 | 1 万+ 官方 `shape=` 检索 | `shape-search` 索引 | 本仓已有 **~300 个 stencil 工厂**（全白名单几何、往返安全），加检索即可 |
| 自动布局 | Graphviz `dot` + ELK/`libavoid` | libavoid pass | 复用本仓 **`ObstacleRouter`（Hanan 网格 + Dijkstra 避障）** + 新增节点摆放 |
| 自检 | 读 PNG 视觉纠错（≤2 轮） | 无 | 复用之（渲染 PNG 由应用桥或无头光栅提供） |
| 实时预览 | 无（生成后 `open`） | app-server 聊天内联 / URL 打开 | **应用内 loopback 控制通道 + 文件监听重载 + 直接驱动 `EditorController`（三级）** |
| 交付形态 | 单 `SKILL.md` + `scripts/` + `references/` | tool-server / app-server / plugin | **三合一**：无头 CLI + MCP + Skill，且 Skill 可零配置独立工作 |
| 分发 | `npx skills add …` / 插件市场 / git clone | `npx -y @drawio/mcp` / 插件 | Skill 走 clone/插件；MCP 走 `dart compile exe` 单文件二进制或 `npx` 薄壳 |

**核心差异化优势**：drawio-skill 依赖笨重的 Electron CLI 做导出，而 visioeditor 的引擎本就是
**纯 Dart、可无头运行**——我们能提供更快、更稳、且**与桌面应用实时联动**的体验（这是 drawio
方案没有的）。

---

## 3. 总体架构

四个组件，自底向上；箭头表示依赖/调用方向。

```
┌───────────────────────────────────────────────────────────────────────┐
│  Agent（Cursor / Claude Code / Codex …）                                │
│    · 读 SKILL.md 指令，规划图形，产出 Diagram Spec / Edit Ops           │
│    · 视觉自检（读回 PNG）                                                │
└───────────────┬───────────────────────────────────┬───────────────────┘
                │ 调 MCP 工具（stdio）              │ 直接调 CLI（skill 脚本）
┌───────────────▼───────────────────────────────────▼───────────────────┐
│  ② MCP 服务器（visioeditor-mcp）                                         │
│     create_diagram / add_shape / add_connector / set_style / export /   │
│     render_preview / open_in_app / apply_ops / validate / explain …     │
│     — 无状态编排层：文件类操作调 CLI；实时预览类操作调 ③ 应用桥          │
└───────────────┬───────────────────────────────────┬───────────────────┘
                │ 进程调用/库调用                    │ WebSocket(loopback)
┌───────────────▼─────────────────────┐   ┌─────────▼───────────────────┐
│  ① vsdx 无头 CLI（package:vsdx/bin） │   │  ③ 应用实时预览桥            │
│     build / patch / render / layout  │   │  （运行中的 Flutter 桌面应用）│
│     validate / explain / shapes /    │   │   loopback 控制服务器：       │
│     import-*                         │   │   open/reload/applyOps/       │
│     —— 复用 parser/writer/serializer │   │   snapshot/select/getState    │
│        /shape_factory/obstacle_router│   │   —— 驱动 EditorController     │
└──────────────────────────────────────┘   └──────────────────────────────┘
                \___________________________________/
                        都建立在 package:vsdx（纯 Dart 引擎）之上
```

- **① 无头 CLI**：drawio-skill 里「31 个 Python 脚本 + draw.io CLI」的合并等价物，但用 Dart
  实现、直接调本仓引擎。**Skill 的后端**、**MCP 文件类工具的后端**。
- **② MCP 服务器**：drawio-mcp `mcp-tool-server` 的等价物。标准 stdio MCP，工具即「命令」。
- **③ 应用实时预览桥**：drawio-mcp `mcp-app-server`「内联预览」的**升级版**——不是聊天里贴图，
  而是**真·桌面应用里的活文档**。本规划的重点。
- **Skill**：drawio-skill `SKILL.md` 的等价物，编排 ①（可选 ②）完成端到端。

---

## 4. 关键设计决策（ADR）

- **ADR-1｜复用而非重写**：Agent 接口的所有「引擎能力」（解析/写回/渲染/形状/布局/公式）
  一律复用 `package:vsdx` 与 `lib/`，接口层不含图形算法。理由：本仓引擎已极成熟（308 引擎
  单测、~300 形状、往返保真、避障路由、公式重算）。
- **ADR-2｜后端首选 Dart CLI**：无头 CLI 用 `dart compile exe` 产出**单文件二进制**
  （`vsdxtool`），零运行时依赖、启动快、跨平台。理由：与代码库同源、免第二套工具链、
  比 Electron CLI 快一个量级。
- **ADR-3｜MCP 薄壳、双实现可选**：
  - **首选**：MCP 服务器直接用 **Dart**（`package:mcp_dart` 或自写 stdio JSON-RPC），
    与 CLI/引擎同进程库调用，最简。
  - **备选**：Node/TS 薄壳（对齐 drawio-mcp，`npx` 分发面广），通过子进程调 `vsdxtool`。
  - 规划按「Dart 优先」推进，保留 Node 壳作为分发可选项（M5）。
- **ADR-4｜实时预览分三级、渐进落地**（详见 §5.3）：L1 文件监听重载 → L2 loopback 控制通道 →
  L3 直接驱动 `EditorController` 协同编辑。先交付 L1（最快见效），再 L2（真·实时），后 L3。
- **ADR-5｜编辑走 Edit Ops + load-preserve-patch**：改图统一表达为结构化 **Edit Ops**（JSON），
  由 Writer 补丁式写回，**严禁**全量重序列化（会丢公式/未知结构）。理由：保真是本项目立身之本。
- **ADR-6｜Spec 与引擎解耦**：对外暴露稳定的 **Diagram Spec / Edit Ops JSON schema**（§7），
  内部映射到 `VsdxShapeFactory` / `EditorController`。schema 版本化，向后兼容。
- **ADR-7｜安全默认**：控制通道仅绑定 `127.0.0.1`、随机端口 + 一次性 token（写入用户目录
  `~/.visioeditor/agent-bridge.json`，`0600`）；Agent 与应用通过该文件握手。默认关闭，
  需用户在应用内开启「Agent 预览」开关。

---

## 5. 组件详解

### 5.1 ① `vsdx` 无头 CLI（`packages/vsdx/bin/vsdxtool.dart`）

一个 `ArgParser` 多子命令 CLI（对标 drawio-skill 的 scripts 全家桶 + draw.io CLI）。

| 子命令 | 作用 | 复用的引擎能力 |
| --- | --- | --- |
| `build <spec.json> -o out.vsdx` | Diagram Spec → `.vsdx`（自动布局 + 建形状 + 连线） | `VsdxShapeFactory`、`VsdxWriter.emptyDocument`、`ObstacleRouter` |
| `patch <in.vsdx> <ops.json> -o out.vsdx` | 应用 Edit Ops，往返保真写回 | `DocumentParser` + `VsdxWriter`（load-preserve-patch） |
| `render <in.vsdx> -o out.svg` | 无头渲染 SVG（自检 & 预览） | `VsdxToSvgSerializer` |
| `render <in.vsdx> -o out.png --width N` | 无头渲染 PNG（自检需位图） | SVG→PNG（见 §5.5 光栅化方案） |
| `layout <graph.json> -o out.vsdx` | 图（节点/边）→ 自动布局 `.vsdx` | 摆放算法 + `ObstacleRouter` |
| `validate <in.vsdx> [--strict]` | 结构 lint（悬空连线/重复 id/重叠/越界） | 遍历 model |
| `explain <in.vsdx> -o out.md` | 反向：`.vsdx` → 结构化 Markdown 描述 | 遍历 model |
| `shapes search "<kw>" [--limit N]` | 检索 ~300 stencil 目录，返回工厂名/预览 | `lib/editor/stencils.dart` 目录 |
| `import-mermaid <in.mmd> -o out.vsdx` | Mermaid → `.vsdx`（标准类型） | 解析 + `build` |
| `import-sql <schema.sql> -o out.vsdx` | SQL DDL → ERD | 解析 + `build` |
| `import-code <dir> --lang X -o out.vsdx` | 代码依赖图 → 架构图 | 解析 + `layout` |
| `convert <in.vsd> -o out.vsdx` | 旧 `.vsd` → `.vsdx`（已具备） | `parseVisio` + `VsdxWriter` |

> 注：`shapes`/`stencils` 目录目前在 `lib/`（依赖 Flutter 命名但数据本身纯 Dart），
> M1 需把 stencil **元数据目录**（名称/分组/工厂引用/关键词）下沉到 `packages/vsdx`，
> 使 CLI 无 Flutter 也能检索（渲染缩略图仍留在应用侧）。

### 5.2 ② MCP 服务器（`tools/mcp/` 或 `packages/vsdx_mcp/`）

标准 stdio MCP。工具命名对齐 drawio-mcp 习惯，但面向 `.vsdx`。分三类：

**A. 文件类（后端 = CLI，无需应用运行）**
- `create_diagram(spec, path?) → {path, preview_png}`：Spec 建图 + 返回预览。
- `apply_ops(path, ops[]) → {path, preview_png}`：对文件应用 Edit Ops（往返保真）。
- `export(path, format, out?) → {out}`：导出 svg/png/pdf。
- `validate(path) → {issues[]}`：结构 lint。
- `explain(path) → {markdown}`：反向描述。
- `search_shapes(query, limit?) → {stencils[]}`：形状检索（对齐 drawio `shape-search`）。
- `render_preview(path, page?, width?) → {image}`：返回 PNG 图像内容，供 Agent 视觉自检 /
  聊天内联（对齐 drawio-mcp `mcp-app-server` 的内联渲染）。

**B. 实时/应用类（后端 = 应用桥 §5.3，需应用运行）**
- `open_in_app(path) → {ok}`：在运行中的应用打开该文档。
- `live_apply_ops(ops[]) → {ok, selection}`：对**当前活动文档**实时应用 Edit Ops（每步一个
  undo 步），应用即时重绘。
- `snapshot(page?) → {image}`：让应用回传当前画布 PNG（真·所见）。
- `select(ids[]) / get_state() → {pages, selection, dirty}`：选中/读状态。

**C. 高层便捷类（= A/B 的组合，降低 Agent 编排负担）**
- `add_shape` / `add_connector` / `set_style` / `set_text` / `move_shape` /
  `resize_shape` / `delete_shape` / `add_page` …：单步语义工具，内部转 `apply_ops` 或
  `live_apply_ops`（依据是否连到应用）。

> **智能路由**：MCP 启动时探测应用桥握手文件；连上则「实时类」直达应用（真 · 实时预览），
> 否则「文件类」落盘 + `render_preview` 出图（无应用也可用）。对 Agent 透明。

### 5.3 ③ 应用实时预览桥（本规划重点）

在**运行中的 Flutter 桌面应用**内提供受控入口，让 Agent 的改动即时可见。分三级递进：

**L1 —— 文件监听 + 智能重载（最先落地，改动最小）**
- 应用监听「当前打开文档」的磁盘文件（`package:watcher` 或轮询 mtime）。
- CLI/MCP 写盘后，应用检测到变化 → 若无未保存编辑则**静默重载并保持视口/选中**；若有脏编辑
  则弹「重载 / 保留我的修改」提示。
- 复用现有打开管线（`EditorWorkspace` / `EditorController.openDocument`）。
- 价值：`vsdxtool patch` / `apply_ops` 落盘即在应用里刷新，已是「准实时」。

**L2 —— loopback 控制通道（真 · 实时预览）**
- 应用内起一个 **`HttpServer`/WebSocket，绑定 `127.0.0.1:随机端口`**（复用 Dart `dart:io`，
  无新原生代码）；把 `{port, token}` 写入 `~/.visioeditor/agent-bridge.json`（§4 ADR-7）。
- 协议（JSON-RPC over WS）：
  - Agent→App：`open(path)` · `reload` · `applyOps(ops[])` · `snapshot(page?)→pngBase64` ·
    `select(ids)` · `getState()` · `save()`。
  - App→Agent（事件推送）：`selectionChanged` · `documentChanged` · `dirtyChanged`。
- `applyOps` 直接改内存模型并重绘——**不落盘也能预览**，亚秒级，真正「边说边画」。
- `snapshot` 复用 `lib/io/image_export.dart` 的 `VsdxPainter` 光栅化，回传 Agent 做视觉自检。
- MCP 的「实时类」工具即调此通道。

**L3 —— 直接驱动 `EditorController` 协同编辑（最深集成）**
- Edit Ops 映射到 `EditorController` 既有的**撤销感知**编辑 API（`createShapeByDrag` /
  `addShapeFromBuilderAt` / `createConnector` / `setShape*` / `moveSelectionBy` /
  `setSelection` / `groupSelection` …，主线已实现数百个）。
- 效果：Agent 就像坐在用户旁边操作——每个 op 是一个 undo 步、参与吸附/避障/连接器重路由/
  主题继承，与人工编辑**完全同构**。用户可随时接管、撤销、继续。
- 这是 drawio 方案**做不到**的「人机同画布协同」。

| 级别 | 交付速度 | 实时性 | 原生改动 | 说明 |
| --- | --- | --- | --- | --- |
| L1 | 最快 | 准实时（写盘后刷新） | 无 | 先上线，立即可用 |
| L2 | 中 | 真实时（内存重绘） | 无（纯 Dart WS） | 「实时预览」达标线 |
| L3 | 中高 | 真实时 + 可协同 | 无 | 复用 controller，差异化亮点 |

### 5.4 ④ Skill（`skills/visioeditor-skill/`）

结构对齐 drawio-skill（单 `SKILL.md` + `references/` 按需读 + 薄 `scripts/`），但后端换成
`vsdxtool` / MCP。

```
skills/visioeditor-skill/
├── SKILL.md                    # frontmatter(name/description/触发词) + 工作流
├── references/
│   ├── spec-schema.md          # Diagram Spec / Edit Ops JSON schema（§7）
│   ├── shape-catalog.md        # ~300 stencil 分组速查 + shapes search 用法
│   ├── diagram-types.md        # 各图型预设（流程图/组织架构/网络/架构/ERD/UML/BPMN…）
│   ├── styling.md              # 语义配色 / 主题 / 连接器路由约定
│   ├── live-preview.md         # 如何连应用桥做实时预览（L1/L2/L3）
│   └── troubleshooting.md      # CLI/桥 常见问题
├── scripts/                    # 薄封装（调 vsdxtool；便于非 MCP 环境）
│   ├── build.(sh|dart)         # spec → vsdx（+ 可选 open_in_app）
│   ├── render.(sh|dart)        # vsdx → png（自检）
│   └── explain.(sh|dart)       # vsdx → md
└── styles/                     # 样式预设（default/corporate/dark…，schema 对齐 drawio）
```

**工作流（对齐 drawio-skill Step 0–7，但融入实时预览）：**
0. 解析活动样式预设。
1. **探测能力**：`vsdxtool --version`；探测应用桥握手文件（决定走实时 or 文件模式）。
2. **规划**：选图型预设、识别形状/关系/布局方向/分层。
3. **生成**：产出 Diagram Spec → `vsdxtool build`（大图/依赖图走 `layout` 自动布局；标准类型
   可 `import-mermaid`）。**若应用桥在线：`open_in_app` 并后续用 `live_apply_ops` 增量构建，
   用户全程可见。**
4. **出草图**：`render`（或 `snapshot`）得 PNG。
5. **自检**：视觉读回 PNG，按清单（重叠/裁切/连线穿越/离散/叠边）自动修正，≤2 轮。
6. **评审回路**：给用户看图 → 收反馈 → 最小化 Edit Ops → 重渲染，≤5 轮安全阀。
7. **定稿**：导出所需格式；`open_in_app`（若未开）供人工精修。

### 5.5 PNG 光栅化方案（自检回路依赖）

引擎产 SVG 是无头纯 Dart，但视觉自检需**位图**。三选一（规划按优先级）：
1. **应用桥 `snapshot`（首选，L2 起可用）**：复用 `image_export.dart` 的 `VsdxPainter`
   光栅化，质量与应用一致。
2. **无头 Flutter 渲染**（`flutter test` 离屏 / `dart:ui` in `flutter` runner）：CI 友好。
3. **打包 `resvg` 单文件二进制**做 SVG→PNG：完全无 Flutter，CI/服务器可用（体积小）。

M2 先用（1）打通；M4 补（3）用于纯无头 CI。

---

## 6. 里程碑（Milestones）

执行原则同主线：**先整体后细节**——先打通最薄端到端切片（Slice：一句话 → CLI 生成 `.vsdx`
→ 应用 L1 自动刷新 → 看到图），再逐块加深到 L2/L3、导入器、自检、分发。

- **M0 规划与脚手架** — `DONE`
- **M1 无头 CLI（build/patch/render/validate/explain/shapes）** — `DONE`
- **M2 应用实时预览桥 L1+L2（监听重载 + loopback 通道 + snapshot）** — `DONE`
- **M3 MCP 服务器（文件类 + 实时类 + 便捷类工具）** — `DONE`
- **M4 Skill（SKILL.md + references + 自检回路 + 图型预设）** — `DONE`
- **M5 实时协同 L3 + 导入器（mermaid/sql/code）+ 分发打包** — `DOING`（import-mermaid 完成）
- **M6 打磨（安全/文档/示例/CI/跨平台）** — `LATER`

> **最薄端到端切片已打通（2026-07-18）**：`vsdxtool build spec.json → out.vsdx` →
> 应用开启「Agent live preview」→ `applyOps`/文件改动 → 应用亚秒级刷新。见进度日志。

---

### M0 —— 规划与脚手架  `DONE`

- [x] 本文档评审定稿；在根 `README.md` 文档导航登记；`third_party/README.md` 登记
      drawio-skill / drawio-mcp 两个新参考（commit/license）。
- [x] 冻结 **Diagram Spec / Edit Ops v0 schema**（§7）——已实现于 `diagram_spec.dart` /
      `edit_ops.dart`（`references/spec-schema.md` 随 M4 落地）。
- [x] 目录脚手架：`packages/vsdx/bin/`、`lib/agent_bridge/`（`skills/`、`tools/mcp/` 随 M3/M4）。
- [x] MCP 语言决策：**Dart 优先**（ADR-3，用户已确认）。

验收（已达成）：schema 落地、CLI/桥目录就位、参考登记齐全。

---

### M1 —— 无头 CLI  `DONE`

实现于 `packages/vsdx/bin/vsdxtool.dart` + `packages/vsdx/lib/agent.dart`
（`lib/src/agent/{diagram_spec,edit_ops,inspect,stencil_catalog,agent_style}.dart`）。

- [x] `packages/vsdx/bin/vsdxtool.dart`：`CommandRunner` 多子命令 + `version`。
- [x] `render`：`.vsdx` → SVG（直接调 `VsdxToSvgSerializer`）。
- [x] `build`：Diagram Spec → `.vsdx`（节点用 `VsdxShapeFactory`；边用连接器 + 胶合 +
      `rerouteConnectors`；缺坐标时走**分层自动布局** `layoutDiagram`，TB/LR）。
- [x] `patch`：Edit Ops（add_shape/add_connector/set_style/set_text/move/resize/delete）→
      往返保真写回（`DocumentParser` + `VsdxWriter`，只补丁改动 Cell）。
- [x] `validate`（重复 id/悬空连线/越界/重叠）/ `explain`（反向 Markdown）。
- [x] `shapes search`：curated core stencil 目录（`stencil_catalog.dart`，别名解析）。
- [x] `dart compile exe` 产出 `vsdxtool` 单文件二进制；纯 Dart 单测 10/10。

验收（已达成）：`vsdxtool build spec.json -o a.vsdx && vsdxtool render a.vsdx -o a.svg`
端到端通过；`patch` 往返保真；`dart test` 494/494（含新 `agent_test` 10 例）；全程无 Flutter。
> 后续：stencil 元数据目录仅覆盖核心集，全量 ~300 catalog 下沉留 M5。

---

### M2 —— 应用实时预览桥 L1+L2  `DONE`

实现于 `lib/agent_bridge/agent_bridge.dart`，经 More 菜单「Agent live preview」开关（默认关）。

- [x] **L1**：应用轮询当前文档磁盘 mtime → 未脏时智能重载（复用 `openBytes` 原地重载）；
      脏时推 `fileChangedOnDisk` 事件不覆盖用户编辑。
- [x] **L2**：应用内 `127.0.0.1` 随机端口 `HttpServer`/WebSocket；握手文件
      `~/.visioeditor/agent-bridge.json`（随机 token + `chmod 600`）；token 校验（无 token 拒连）。
- [x] 协议：`ping/getState/open/reload/applyOps/snapshot/save` + 事件推送
      （`documentChanged`/`fileChangedOnDisk`）。
- [x] `snapshot`：复用 `image_export.dart` 的 `renderPageToPng` 回传 PNG（base64）。
- [x] `applyOps`：**不落盘**（export→`applyOpsBytes`→`openBytes` 原地）改内存模型并重绘，
      支持 add_shape/add_connector/set_style/set_text/move/resize/delete。
- [x] 状态 `ValueNotifier`（端口/最近操作），`stop()` 清握手文件。
- [x] 集成测试 `test/agent_bridge_test.dart` 7 例（token 拒连 / ping / getState /
      applyOps 不落盘 / snapshot PNG / save / L1 自动重载）。

验收（已达成）：外部 WS 客户端 `applyOps` → 内存模型即时更新（不落盘）；`vsdxtool patch`
写盘 → L1 亚秒级自动重载；`snapshot` 回传合法 PNG；无 token 拒连、默认关闭；
`flutter test` 554/554 无回归。
> **L3 已于 M5 落地**：`applyOps` 经 `EditorController.applyEdit` 提交为单步可撤销编辑。
> 后续：`select` 工具、「Agent 预览」并入设置页 + l10n（当前菜单文案为英文占位）。

---

### M3 —— MCP 服务器  `DONE`

自写最小 MCP（**无第三方依赖**，ADR-3 备选路径），实现于
`packages/vsdx/lib/src/agent/{mcp_server,mcp_tools,bridge_client}.dart` +
`bin/vsdxtool_mcp.dart`。

- [x] MCP stdio 服务骨架（`McpServer`：`initialize`/`notifications`/`ping`/
      `tools/list`/`tools/call`，newline-delimited JSON-RPC 2.0）。
- [x] 文件类工具：`create_diagram/import_*/apply_ops/export/validate/explain/list_shapes/search_shapes`
      （后端调 agent 库；`list_shapes` 双模式，返回结构化 id/text/坐标供 Agent 定位）。
- [x] 实时类工具：`open_in_app/live_apply_ops/snapshot/get_app_state`（`BridgeClient` 连应用桥）。
- [x] 便捷路由：`create_diagram`/`import_*` 带 `open:true` 时探测握手文件并在应用打开。
- [x] `snapshot` 返回 MCP image content（Agent 内联视觉自检）。
- [x] 配置样例（Cursor `.cursor/mcp.json` / Claude）写入 `skills/.../references/live-preview.md`。
- [x] **便捷单步工具**：`add_shape`/`add_connector`/`set_style`/`set_text`/`move_shape`/`delete_shape`
      ——**双模式**（给 `path` 走文件、省略走运行中应用），内部转单条 Edit Op；单测 4 例。
- [x] 协议 + 工具单测 `mcp_server_test` 13 例；`dart run bin/vsdxtool_mcp.dart` stdio 冒烟。

验收（已达成）：`initialize`/`tools/list` 经真实 stdio 返回 serverInfo + **23 个工具**（13 文件/导入 +
6 便捷编辑 + 4 实时）；文件类端到端建图/校验/描述/导出/列举；实时类经 `BridgeClient` 驱动应用。

### M4 —— Skill  `DONE`

实现于 `skills/visioeditor-skill/`（`SKILL.md` + `references/`）。

- [x] `SKILL.md`：frontmatter（name/description 触发词/兼容性/平台）+ §5.4 工作流
      （check→plan→spec→build→preview→self-check→iterate→deliver）+ Spec/Ops 速查。
- [x] `references/`：`spec-schema` / `shape-catalog` / `diagram-types` / `styling` /
      `live-preview`（含 MCP 配置）/ `troubleshooting`。
- [x] 图型预设：flowchart / org chart / architecture / network / ERD / UML / BPMN / swimlane
      （`diagram-types.md`，语义配色表）。
- [x] 自检回路（≤2 轮，用 `snapshot` 视觉纠错）+ 评审回路（≤5 轮）落到 `SKILL.md`。

验收（已达成）：skill 指引 Agent 用 `vsdxtool`/MCP 端到端出 `.vsdx` 并可在应用实时预览。
> 后续：样式预设 `styles/` 与薄 `scripts/` 封装（当前直接调 CLI/MCP，已够用）；l10n 菜单文案。

---

### M4 —— Skill  `TODO`

- [ ] `SKILL.md`：frontmatter（name/description/触发词/兼容性/平台）+ §5.4 工作流。
- [ ] `references/`：spec-schema / shape-catalog / diagram-types / styling / live-preview /
      troubleshooting。
- [ ] 图型预设：流程图 / 组织架构 / 网络拓扑 / 架构 / ERD / UML 类图·时序 / BPMN / 泳道
      （复用主线已有 stencil 与容器/泳道/表格能力）。
- [ ] 自检回路（Step 5，≤2 轮）+ 评审回路（Step 6，≤5 轮）落到 SKILL.md。
- [ ] 样式预设机制（`styles/`，schema 对齐 drawio-skill）。
- [ ] `scripts/` 薄封装（无 MCP 环境也能跑）。

验收：在 Cursor/Claude Code 装此 skill，`"画一张订单微服务架构图并在应用里打开"` 端到端完成
（生成 → 自检 → 应用实时可见 → 定稿导出）。

---

### M5 —— 实时协同 L3 + 导入器 + 分发  `DOING`

- [x] 导入器：**`import-mermaid`**（flowchart/graph 子集 → Diagram Spec → `.vsdx`）——
      `lib/src/agent/mermaid_import.dart`，CLI `import-mermaid` + MCP `import_mermaid`；
      支持方向/节点形状（`[] () ([]) [()] {} {{}} [//] (())`）/边操作符/管道与内联标签/边链；
      单测 `mermaid_import_test` 6 例。
- [x] 导入器：**`import-sql`**（SQL DDL → ERD）—— `lib/src/agent/sql_import.dart`，
      CLI `import-sql` + MCP `import_sql`；解析 CREATE TABLE 表名/列/类型、PK（行内+表级）、
      FK（行内 REFERENCES + 表级/CONSTRAINT FOREIGN KEY），每表一框（列 + PK/FK 标记）+ 外键边；
      单测 `sql_import_test` 4 例。
- [x] 导入器：**`import-code`**（代码依赖图）—— `lib/src/agent/code_import.dart`，
      CLI `import-code` + MCP `import_code`；支持 **Dart / Python / JS-TS / Go / Rust**
      （自动侦测语言；Go 为包级图，经 `go.mod` 模块前缀识别项目内包依赖；Rust 为模块图，
      `mod` / `use crate|super|self`，`foo/mod.rs` 折叠为模块 `foo`），
      扫描项目、提取 import/from/require/export-from、解析为**仅项目内**模块依赖边
      （Dart `package:`→lib/、Python 相对导入 + `__init__` 包、JS 相对 + `index` 解析），
      每模块一框 + 依赖边；单测 `code_import_test`（提取器 + 各语言临时目录集成）。
- [x] 导入器：**`import-openapi`**（OpenAPI 3 / Swagger 2，JSON+YAML）—— `lib/src/agent/openapi_import.dart`，
      CLI `import-openapi` + MCP `import_openapi`；操作按 HTTP 方法着色、schema 节点、`$ref` 引用边
      （operation→schema、schema→schema），支持 `components/schemas` 与 Swagger `definitions`；
      单测 `openapi_import_test` 3 例（YAML/JSON + 往返）。新增 `yaml` 依赖。
- [x] 导入器：**`import-iac`**（IaC → 架构图）—— `lib/src/agent/iac_import.dart`，
      CLI `import-iac` + MCP `import_iac`；自动侦测 **docker-compose**（services + depends_on/links
      边 + 具名 volumes 圆柱）与 **Kubernetes**（多文档 YAML，按 kind 着色/选形；Service→workload
      标签选择器、Ingress→Service backend、workload→ConfigMap/Secret/PVC 卷与 envFrom 边）；
      单测 `iac_import_test` 3 例。
- [x] 导入器：**Rust 依赖图**（`import-code --lang rust`）——见上。
- [ ] 导入器：Terraform（HCL）后续。
- [x] **L3 协同编辑**：应用桥 `applyOps` 改为经 `EditorController.applyEdit(next)` 提交——
      Agent 编辑成为**单步可撤销**、**保留用户 undo 历史与选中**（复用既有 `applyOps` 引擎逻辑，
      含 `rerouteConnectors`）；不落盘、即时重绘。桥测试新增 L3 撤销用例（共 8 例）。
- [x] 反向/衍生：**`vsdx→mermaid`**（`lib/src/agent/mermaid_export.dart`，结构化 flowchart，
      保边标签、可 `--fenced`），CLI `to-mermaid` + MCP `to_mermaid`；单测 `mermaid_export_test` 4 例
      （含 mermaid→vsdx→mermaid 往返）。交互式 HTML 查看器留后续。
- [x] 分发（本地一键可用）：仓库内置 `.cursor/mcp.json`（`dart run` 启动、免编译，工作区根
      即可被 Cursor 调用）；构建脚本 `packages/vsdx/tool/build_agent_binaries.sh` 产出
      `vsdxtool` / `vsdxtool-mcp` 原生二进制（`.gitignore` 忽略）；MCP `serve()` 端到端集成测试
      `mcp_stdio_test` 2 例（行分隔框校 + 通知无响应 + 工具落盘）。
- [ ] 分发（发布）：各平台二进制 release；可选 Node 薄壳 `npx` 包；skill 上架（clone / 插件）。

- [x] **全量 stencil 目录接入 Agent**：把 `lib/editor/stencils.dart`（纯 Dart，~600 图形/
      Stencil(name,build)）**下沉到 `packages/vsdx/lib/src/stencils.dart`** + barrel
      `package:vsdx/stencils.dart`，应用侧 `lib/editor/stencils.dart` 改为 re-export（调用点零改动）。
      Agent `resolveStencilShape`：核心（干净尺寸/填充）→ 全量目录（按名归一匹配、resize、仅显式时覆盖
      fill/line）→ 矩形兜底；`search_shapes` 检索全量（AWS/UML/BPMN/Cisco/Network…）。
      单测 `stencil_catalog_test` 8 例；狗粮：`shapes search aws`→EC2/S3/Lambda…、Actor/CloudFront/
      Cloud Storage 建图校验干净。应用 `flutter test` 555 无回归（下沉透明）。

**M5 导入/导出矩阵（现状）**：入 = Diagram Spec · Edit Ops · Mermaid · SQL DDL ·
Code（Dart/Py/JS-TS/Go/Rust）· OpenAPI/Swagger（JSON/YAML）· IaC（docker-compose / Kubernetes）；
出 = `.vsdx` · SVG · Mermaid · Markdown（explain）· PNG（应用 snapshot）。
**形状词汇**：全量 ~600 图形（core + 全部专业库）经 `resolveStencilShape` 对 Agent 可用。

### M6 —— 打磨  `LATER`

- [ ] 安全审计（loopback + token + 默认关 + 审批 UI）；沙箱/权限文档。
- [ ] 跨平台桥（Windows/Linux 的握手文件与端口约定）。
- [ ] 示例库（`assets/` 若干 spec → 图）、录屏、`docs/references` 更新。
- [ ] CI：CLI 单测 + `resvg` 无头渲染 + MCP 冒烟 + skill 脚本测试。

---

## 7. Diagram Spec / Edit Ops schema 草案（v0）

**Diagram Spec**（生成用，声明式；坐标可省略交给 `--layout`）：

```jsonc
{
  "version": 0,
  "page": { "size": "Letter", "landscape": false, "background": "#ffffff" },
  "layout": { "algorithm": "obstacle", "direction": "TB", "spacing": 0.6 },
  "nodes": [
    { "id": "api", "stencil": "process", "text": "API Gateway",
      "x": 2.0, "y": 3.0, "w": 1.6, "h": 0.8,
      "style": { "fill": "#DAE8FC", "line": "#6C8EBF", "text": { "bold": true } } },
    { "id": "db", "stencil": "cylinder", "text": "Order DB" }
  ],
  "edges": [
    { "from": "api", "to": "db", "label": "SQL",
      "route": "orthogonal", "endArrow": "solid" }
  ]
}
```

**Edit Ops**（改图用，命令式；映射 Writer 补丁 / L3 `EditorController`）：

```jsonc
{
  "version": 0,
  "ops": [
    { "op": "add_shape", "stencil": "decision", "text": "Approved?", "x": 4, "y": 5, "w": 1.4, "h": 1 },
    { "op": "add_connector", "from": "shape:12", "to": "shape:8", "label": "yes", "endArrow": "solid" },
    { "op": "set_style", "ids": ["shape:12"], "fill": "#D5E8D4", "line": "#82B366" },
    { "op": "set_text", "id": "shape:8", "text": "Ship order" },
    { "op": "move_shape", "id": "shape:8", "x": 6.0, "y": 5.0 },
    { "op": "delete_shape", "id": "shape:3" }
  ]
}
```

- `stencil` 取值 = `shapes search` / `shape-catalog.md` 里的工厂名（如 `process` / `decision` /
  `cylinder` / `cloud` / `umlClass` / `bpmnTask` …）。
- id 命名空间：生成时用 spec 的 `id`；改图/实时时用引擎的 `shape:<VsdxShape.id>`（`get_state`/
  `explain` 回传映射）。
- schema 版本化（`version`），字段向后兼容；未知字段忽略而非报错。

---

## 8. 与本应用的复用清单（集成点）

| Agent 接口需求 | 复用的既有实现 | 位置 |
| --- | --- | --- |
| 解析 `.vsdx`/`.vsd` | `DocumentParser` / `parseVisio` | `packages/vsdx/lib/src/parser/` |
| 往返保真写回 | `VsdxWriter`（load-preserve-patch + emit-from-scratch） | `.../writer/vsdx_writer.dart` |
| 空文档/新页 | `VsdxWriter.emptyDocument` / `VsdxPage` 增删 | 同上 / `model/page.dart` |
| 建形状（~300 种） | `VsdxShapeFactory` + `lib/editor/stencils.dart` 目录 | `model/shape_factory.dart` |
| 无头 SVG | `VsdxToSvgSerializer` | `.../export/svg_serializer.dart` |
| PNG 光栅化 | `VsdxPainter` 光栅化导出 | `lib/io/image_export.dart` |
| 自动布局/避障 | `ObstacleRouter`（Hanan + Dijkstra） | `model/obstacle_router.dart` |
| 连接器胶合/重路由/折点 | `VsdxPage.createConnector/rerouteConnectors/…` | `model/page.dart` |
| 撤销感知编辑 API（L3） | `EditorController` 数百个方法 | `lib/editor/editor_controller.dart` |
| 「打开文档」入口 | `MethodChannel('visioeditor/files')` + `EditorWorkspace` | `macos/Runner/*` · `lib/main.dart` |
| 导出 SVG/PNG/PDF | `lib/io/{image_export,pdf_export}.dart` | `lib/io/` |
| 主题/样式/公式重算 | `theme_serializer` / `formula` / `stylesheet` | `packages/vsdx/lib/src/` |

结论：Agent 接口子系统**几乎不需要新引擎代码**，主要工作量在 ①CLI 编排、②MCP 壳、③应用桥
（纯 Dart WS + 复用 controller）、④SKILL.md 编写。

---

## 9. 风险登记（Risk Register）

- **往返保真回归**：Edit Ops 必须走 Writer 补丁，禁止全量重序列化 → 复用主线往返单测，
  每个 op 加往返用例。
- **stencil 目录耦合 Flutter**：`stencils.dart` 现在 `lib/`；需把**元数据**下沉纯 Dart，
  缩略图渲染留应用侧（M1 任务）。
- **PNG 自检依赖**：无头位图是短板 → 分级方案（应用桥 snapshot 优先，`resvg` 兜底，§5.5）。
- **实时预览安全**：loopback + token + 默认关 + 应用内可见/可断（ADR-7）；防止本机其他进程
  静默操控画布。
- **并发编辑冲突（L3）**：Agent 与人同改 → 以 controller 事务 + undo 栈为单一真源，Agent op
  失败即回报，不强插。
- **MCP 生态版本**：`package:mcp_dart` 若不成熟 → 退回自写 stdio JSON-RPC 或 Node 薄壳（ADR-3）。
- **范围蔓延**：严格分里程碑；L1→L2→L3、文件类→实时类渐进，先跑通最薄切片。

---

## 10. 新增目录结构（规划）

```
visioeditor/
├── packages/vsdx/
│   ├── bin/vsdxtool.dart            # ① 无头 CLI（多子命令）
│   └── lib/src/agent/               # spec/ops 解析、build/layout 编排（纯 Dart）
├── lib/agent_bridge/                # ③ 应用实时预览桥（WS 服务器 + controller 适配）
├── tools/mcp/                       # ② MCP 服务器（Dart 优先；可选 Node 薄壳）
├── skills/visioeditor-skill/        # ④ Skill（SKILL.md + references + scripts + styles）
└── docs/MCP_SKILL_PLAN.md           # 本文件
```

---

## 11. 后续（LATER）

- 更多导入器（IaC/Terraform/K8s/compose、CI、live infra），对齐 drawio-skill importers。
- 衍生产物：diff、heatmap、时间轴回放、buildup 动画、PPTX（视需求）。
- Web/移动端的实时预览通道（当前聚焦 macOS 桌面）。
- 与主线 `PLAN.md` 的形状库继续同步（新 stencil 自动进入 `shapes search`）。

---

## 进度日志

- 2026-07-18 — 规划启动：克隆 `Agents365-ai/drawio-skill`（v1.34.0）与 `jgraph/drawio-mcp`
  （`@drawio/mcp` v1.4.1）到 `third_party/`（不入库）作参考；对照本仓引擎能力（纯 Dart
  parser/writer/svg_serializer/~300 stencil/ObstacleRouter/EditorController/MethodChannel
  文件桥）产出本四层架构（CLI + MCP + 应用实时预览桥 + Skill）与 M0–M6 里程碑。
- 2026-07-18 — **M0/M1 完成（无头 CLI）**：新增 `packages/vsdx/lib/agent.dart` +
  `lib/src/agent/{diagram_spec,edit_ops,inspect,stencil_catalog,agent_style}.dart` 与
  `bin/vsdxtool.dart`（`build/patch/render/validate/explain/shapes/version`）；Diagram Spec /
  Edit Ops v0；分层自动布局（TB/LR）；curated stencil 目录。全部复用 `VsdxShapeFactory`/
  `VsdxWriter`/`DocumentParser`/`VsdxToSvgSerializer`/`rerouteConnectors`（模式对齐
  `tool/gen_example_templates.dart`），纯 Dart 无 Flutter。`args` 加入 vsdx 依赖。
  `agent_test` 10 例、`dart test` 494/494、`dart compile exe` 单文件二进制通过。
- 2026-07-18 — **M2 完成（应用实时预览桥 L1+L2）**：新增 `lib/agent_bridge/agent_bridge.dart`
  （loopback WebSocket + 握手文件 + token + 文件监听重载 + `applyOps` 内存内实时应用 +
  `snapshot` 光栅化回传 + `save`），`main.dart` More 菜单加「Agent live preview」开关并管理
  生命周期。集成测试 `test/agent_bridge_test.dart` 7 例、`flutter analyze` 干净、
  `flutter test` 554/554 无回归。**最薄端到端切片打通**：一句话 spec → CLI 生成 → 应用实时刷新。
- 2026-07-18 — **M3 完成（MCP 服务器）**：新增 `lib/src/agent/{mcp_server,mcp_tools,bridge_client}.dart`
  + `bin/vsdxtool_mcp.dart`（自写最小 MCP stdio，无第三方依赖）；10 工具（6 文件 + 4 实时）；
  `snapshot` 回图片内容；单测 `mcp_server_test` 9 例 + stdio 冒烟（`initialize`/`tools/list`）。
- 2026-07-18 — **M4 完成（Skill）**：新增 `skills/visioeditor-skill/SKILL.md` + 6 篇 references
  （spec-schema / shape-catalog / diagram-types / styling / live-preview / troubleshooting），
  对齐 drawio-skill 工作流（含自检/评审回路、图型预设、MCP 配置样例）。
- 2026-07-18 — **M5 起步（import-mermaid）**：新增 `lib/src/agent/mermaid_import.dart`
  （Mermaid flowchart/graph → Spec → `.vsdx`），CLI `import-mermaid` + MCP `import_mermaid`；
  单测 `mermaid_import_test` 6 例。
- 2026-07-18 — **M5 续（import-sql / ERD）**：新增 `lib/src/agent/sql_import.dart`
  （SQL DDL → ER 图：表/列/PK/FK + 外键边），CLI `import-sql` + MCP `import_sql`；
  单测 `sql_import_test` 4 例。
- 2026-07-18 — **M5 续（L3 协同编辑 + vsdx→mermaid）**：(1) 应用桥 `applyOps` 改走
  `EditorController.applyEdit`——Agent 编辑变为单步可撤销、保留用户历史/选中（真 L3），
  桥测试加 L3 撤销用例（8 例）。(2) 新增 `lib/src/agent/mermaid_export.dart`（`vsdx→mermaid`
  结构化 flowchart，保边标签），CLI `to-mermaid` + MCP `to_mermaid`，单测 `mermaid_export_test`
  4 例（含往返）。`dart test` **517**、`flutter test` **555** 全绿。
- 2026-07-18 — **M5 续（import-code / 代码依赖图）**：新增 `lib/src/agent/code_import.dart`
  （Dart/Python/JS-TS 项目 → 模块 import 图 → `.vsdx`，仅项目内边，自动侦测语言），
  CLI `import-code` + MCP `import_code`；单测 `code_import_test` 7 例（提取器 + 三语言临时目录）。
  狗粮：本仓 `lib/src/agent` → 12 模块/17 依赖，校验干净。`dart test` **524**、`flutter test` 555 全绿。
- 2026-07-18 — **M5 续（本地一键分发 + MCP stdio 测试）**：新增 `.cursor/mcp.json`
  （`dart run packages/vsdx/bin/vsdxtool_mcp.dart`，打开本仓即可在 Cursor 调用全部工具，免编译）、
  构建脚本 `packages/vsdx/tool/build_agent_binaries.sh`（编译 `vsdxtool`/`vsdxtool-mcp` 原生二进制，
  `.gitignore` 忽略）、README「AI Agent 接口」一节与 skill 配置说明；新增 `mcp_stdio_test` 2 例
  （`serve()` 真实流框校 + 通知无响应 + create_diagram 落盘）。`dart test` **526**、`flutter test` 555 全绿。
- 2026-07-18 — **M5 续（全量 stencil 目录接入 Agent）**：`lib/editor/stencils.dart`（~600 图形，纯 Dart）
  下沉到 `packages/vsdx/lib/src/stencils.dart` + barrel `package:vsdx/stencils.dart`，应用侧改 re-export；
  Agent `resolveStencilShape`（核心→全量目录 resize+可选覆盖样式→兜底）+ `search_shapes` 检索全量；
  `diagram_spec`/`edit_ops` 统一走解析。单测 `stencil_catalog_test` 8 例。`dart test` **534**、
  `flutter test` **555** 全绿（下沉对应用透明）。
- 2026-07-18 — **M5 续（import-openapi）**：新增 `lib/src/agent/openapi_import.dart`
  （OpenAPI 3 / Swagger 2，JSON+YAML → API 图：操作按方法着色 + schema 节点 + `$ref` 边），
  CLI `import-openapi` + MCP `import_openapi`，新增 `yaml` 依赖；单测 `openapi_import_test` 3 例。
  `dart test` **537**、`flutter test` 555 全绿。
- 2026-07-18 — **M5 续（import-iac / IaC 架构图）**：新增 `lib/src/agent/iac_import.dart`
  （docker-compose + Kubernetes 自动侦测；compose 服务/依赖/具名卷；k8s 按 kind 着色 +
  Service 选择器/Ingress backend/workload→CM·Secret·PVC 边），CLI `import-iac` + MCP `import_iac`；
  单测 `iac_import_test` 3 例。`dart test` **540**、`flutter test` 555 全绿。
- 2026-07-18 — **M3 收口（便捷单步工具）**：MCP 增 `add_shape`/`add_connector`/`set_style`/
  `set_text`/`move_shape`/`delete_shape`（双模式：`path`→文件、省略→运行中应用），内部转单条
  Edit Op；`mcp_server_test` 增 4 例（共 13）。工具总数 **22**。`dart test` **544**、`flutter test` 555 全绿。
- 2026-07-18 — **打磨（list_shapes 形状发现）**：`inspect.listShapes` 结构化列举（id/text/连接器/坐标）；
  MCP `list_shapes`（双模式：文件解析 / 桥 `listShapes`）+ 应用桥新增 `listShapes` 方法。工具总数 **23**。
  `mcp_server_test`+1、`agent_bridge_test`+1。`dart test` **545**、`flutter test` **556** 全绿。
- 2026-07-18 — **M5 续（import-code 增 Go）**：`code_import.dart` 增 Go 包级依赖图
  （`go.mod` 模块前缀→项目内包，包=目录，单/块 import + 别名），CLI `--lang go` + MCP enum 加 `go`；
  `code_import_test` +2（Go 提取器 + go.mod 临时工程）。`dart test` **547**、`flutter test` 556 全绿。
- 2026-07-18 — **M5 续（import-code 增 Rust）**：`code_import.dart` 增 Rust 模块依赖图
  （`mod` / `use crate|super|self`；`foo/mod.rs` 折叠；外部 crate 丢弃；自动侦测含 `.rs`），
  CLI `--lang rust` + MCP enum 加 `rust`；`code_import_test` +2。
  仍待：Terraform（HCL）、发布二进制/`npx`、l10n 菜单文案。
