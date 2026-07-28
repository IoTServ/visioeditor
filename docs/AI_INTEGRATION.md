# AI 接入使用指南

visioeditor 提供两类互补的 AI 接入：

1. **应用内 AI 对话**：普通用户直接描述流程，在应用里生成可编辑流程图。
2. **Agent 工具链**：Codex、Claude Code、Cursor 等外部 Agent 通过 MCP、CLI、Skill
   和实时预览桥批量生成或精细编辑 `.vsdx`。

## 应用内 AI 对话

在空白首页点击「通过 AI 创建」，或在编辑器工具栏 / More（⋯）菜单打开
「AI 流程图助手」。

首次使用时配置：

- **接口类型**：OpenAI compatible、Anthropic、Google Gemini 或 Ollama。
- **接口地址**：可使用默认官方地址，也可填写企业网关或本机服务地址。
- **模型**：填写该接口实际提供的模型标识。
- **API Key**：Ollama 可留空；其他接口通常必填。

对话时建议说明：

- 流程的开始、结束、处理步骤和判断条件；
- 分支文字，例如「通过 / 驳回」；
- 期望从上到下（TB）还是从左到右（LR）；
- 希望采用默认、corporate 或 dark 样式。

AI 回复包含有效 Diagram Spec 或 Mermaid 时，消息下方会出现「创建图表」按钮。点击后，
应用调用与 CLI/MCP 相同的 Diagram Spec 引擎，自动布局并在新标签页创建可编辑 `.vsdx`。
继续对话可以要求增加步骤、修改标签、更换方向或样式；AI 会返回完整修订版。

> 对话历史只发送到用户配置的接口。API Key 保存在本机应用首选项中；共享设备请使用
> 权限受限的专用密钥，或使用无需密钥的本机 Ollama。

## Agent live preview

外部 Agent 要操作正在运行的应用时：

1. 打开任意文档。
2. 在 More（⋯）菜单勾选 **Agent live preview**。
3. 保持应用运行，让 MCP/CLI 客户端自动读取握手文件。

桥仅监听 `127.0.0.1`，使用随机令牌鉴权。它支持读取状态和图形、选择页面/图层/图形、
应用 Edit Ops、截图、保存等操作。经 `applyOps` 进入内存模型的编辑仍是应用内单步撤销。
关闭菜单开关会停止服务并删除握手文件。

## MCP

仓库内的 Cursor 配置位于 `.cursor/mcp.json`。其他 MCP 客户端可使用同样的 stdio
启动方式：

```json
{
  "mcpServers": {
    "visioeditor": {
      "command": "dart",
      "args": ["run", "packages/vsdx/bin/vsdxtool_mcp.dart"]
    }
  }
}
```

常用工具包括 `create_diagram`、`import_mermaid`、`import_sql`、`import_code`、
`apply_ops`、`list_shapes`、`select`、`snapshot` 和 `to_mermaid`。实时类工具需要先开启
Agent live preview；文件类工具可独立运行。

## CLI 与 Skill

不启动 Flutter 应用也可生成、检查和渲染图表：

```bash
dart run packages/vsdx/bin/vsdxtool.dart build spec.json -o flow.vsdx
dart run packages/vsdx/bin/vsdxtool.dart import-mermaid flow.mmd -o flow.vsdx
dart run packages/vsdx/bin/vsdxtool.dart validate flow.vsdx
bash packages/vsdx/tool/build_agent_binaries.sh
```

Agent 的推荐工作流、Schema、形状目录、样式和排错说明位于
`skills/visioeditor-skill/SKILL.md` 及其 `references/` 目录。完整设计与进度记录见
`docs/MCP_SKILL_PLAN.md`。
