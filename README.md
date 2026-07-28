# Editor for Visio Diagrams

原生、跨平台的 **Microsoft Visio (`.vsdx`) 编辑器**，基于 Flutter / Dart。

与只读查看器不同，本项目采用**原生 Dart 往返引擎**：直接把 `.vsdx`（OPC/ZIP + XML）
解析为强类型可编辑模型，在画布上编辑，并**保真回写 `.vsdx`**（只改动用户编辑过的
Cell，其余结构/公式/主题原样透传）。

> 首发范围：**核心编辑器 + macOS 桌面优先**。老格式 `.vsd` 导入、其他平台、模具库、
> 自动路由、导出等见 [`docs/PLAN.md`](docs/PLAN.md) 的后续里程碑。

## 项目状态

**v0.1 开发中** —— 见 [`docs/PLAN.md`](docs/PLAN.md)（主开发规划与状态跟踪表）。

## 文档导航

- [`docs/PLAN.md`](docs/PLAN.md) — 开发规划与状态跟踪（里程碑 E0–E6、任务、验收）
- [`docs/MCP_SKILL_PLAN.md`](docs/MCP_SKILL_PLAN.md) — AI Agent 接口规划（MCP + Skill + 无头 CLI + 应用实时预览桥）
- [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md) — v0.1 发布说明（亮点 / 运行 / 快捷键 / 已知限制）
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — 变更日志（Keep a Changelog）
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 分层架构、数据流、目录结构、决策
- [`docs/VSDX_WRITE.md`](docs/VSDX_WRITE.md) — 写回器（往返保存）详细设计
- [`docs/REUSE_MAP.md`](docs/REUSE_MAP.md) — 从查看器 git 历史恢复的代码映射
- [`docs/VSDX_FORMAT.md`](docs/VSDX_FORMAT.md) — VSDX 格式速查（OPC/ShapeSheet/几何/公式）
- [`docs/references/`](docs/references/) — 规范与开源参考清单
- [`third_party/README.md`](third_party/README.md) — 参考克隆（vsdx/libvisio/drawio，不入库）

## 架构一览

```
lib/            Flutter：editor(画布/工具/属性面板) · render(模型→Canvas) · commands · app · io
packages/vsdx/  纯 Dart 引擎：model · parser(OPC→模型) · writer(模型→.vsdx) · formula
```

## 本地开发

```bash
flutter --version        # Flutter stable（Dart 3.12+）
flutter pub get
flutter run -d macos     # v0.1 桌面优先
flutter test
flutter analyze
```

## AI Agent 接口（MCP / Skill）

本仓内置 **AI 代理接口**：无头 CLI `vsdxtool`、MCP 服务器 `vsdxtool-mcp`、Agent Skill
（`skills/visioeditor-skill/`），以及运行中应用的**实时预览桥**。自然语言 / Mermaid /
SQL DDL / 代码依赖图 → 可编辑保真 `.vsdx`，并可在桌面应用里**实时预览与协同编辑**。

- **应用内 AI 对话**：首页「通过 AI 创建」或工具栏 AI 按钮；可配置 OpenAI-compatible、
  Anthropic、Gemini、Ollama 的接口地址 / 模型 / API Key，对话生成 Diagram Spec /
  Mermaid 后一键在新标签页创建可编辑流程图。
- **Cursor 一键可用**：仓库已附 [`.cursor/mcp.json`](.cursor/mcp.json)（`dart run` 启动、免编译）。
  打开本仓即可调用 `create_diagram` / `import_mermaid` / `import_sql` / `import_code` /
  `apply_ops` / `to_mermaid` / `snapshot` 等工具。
- **编译原生二进制**（更快启动）：`bash packages/vsdx/tool/build_agent_binaries.sh`
  → `packages/vsdx/vsdxtool(-mcp)`。
- 实时预览：应用 More（⋯）菜单勾选 **Agent live preview**（默认关，loopback + token）。
- 设计与里程碑见 [`docs/MCP_SKILL_PLAN.md`](docs/MCP_SKILL_PLAN.md)；用法见
  [`docs/AI_INTEGRATION.md`](docs/AI_INTEGRATION.md) 和
  [`skills/visioeditor-skill/SKILL.md`](skills/visioeditor-skill/SKILL.md)。

## License

- 主仓：**MIT**（见 `LICENSE`）。引擎/渲染层部分代码恢复自同为 MIT 的
  `visiovsdxviewer`（见 [`docs/REUSE_MAP.md`](docs/REUSE_MAP.md)）。
- 依赖与被参考项目的 attribution 见 `NOTICE`（E6 完善）。
