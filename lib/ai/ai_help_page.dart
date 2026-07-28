import 'package:flutter/material.dart';

class AiIntegrationHelpPage extends StatelessWidget {
  const AiIntegrationHelpPage({super.key});

  bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  @override
  Widget build(BuildContext context) {
    final zh = _zh(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? 'AI 接入与自动绘图' : 'AI integrations and diagramming'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _HelpSection(
            icon: Icons.chat_bubble_outline,
            title: zh ? '内置 AI 对话' : 'Built-in AI chat',
            body: zh
                ? '打开工具栏的 AI 图标，先配置引擎、模型、接口地址和 API Key。'
                      '描述流程、参与者、判断条件和期望方向；AI 回复中出现有效的 Diagram Spec '
                      '后，点击“创建图表”即可在新标签页得到可编辑的 .vsdx。继续对话时可要求'
                      '增加步骤、改成横向、调整文案或更换样式。'
                : 'Open the AI tool, configure a provider, model, endpoint and '
                      'API key, then describe the process, actors, decisions and '
                      'layout. When the reply contains a valid Diagram Spec, use '
                      'Create diagram to open an editable .vsdx in a new tab. '
                      'Continue the conversation to revise the full diagram.',
          ),
          _HelpSection(
            icon: Icons.security_outlined,
            title: zh ? '数据与密钥' : 'Data and credentials',
            body: zh
                ? '对话历史会发送到你配置的接口；应用不会把对话转发到其他服务。API Key '
                      '保存在本机应用首选项中。共享设备请使用受限密钥，或选择无需密钥的本机 '
                      'Ollama。自定义兼容网关可选择 OpenAI compatible 并填写网关地址。'
                : 'Conversation history is sent only to the endpoint you '
                      'configure. API keys are stored in local app preferences. '
                      'Use a restricted key on shared machines, or local Ollama '
                      'without a key. Choose OpenAI compatible for custom gateways.',
          ),
          _HelpSection(
            icon: Icons.visibility_outlined,
            title: zh ? 'Agent 实时预览桥' : 'Agent live preview bridge',
            body: zh
                ? '外部 Codex、Claude Code、Cursor 等 Agent 要直接操作当前应用时，在含文档'
                      '的页面打开 More（⋯），勾选 Agent live preview。应用只监听 '
                      '127.0.0.1，并使用随机令牌握手；关闭开关即停止服务。Agent 可读取页面、'
                      '应用编辑操作、选择图形、截图和保存，所有内存编辑仍进入应用撤销历史。'
                : 'For an external Codex, Claude Code or Cursor agent, open '
                      'More (…) in a document and enable Agent live preview. The '
                      'bridge listens only on 127.0.0.1 with a random token. It '
                      'supports state, edit operations, selection, snapshots and '
                      'save; in-memory edits remain undoable in the app.',
          ),
          _HelpSection(
            icon: Icons.hub_outlined,
            title: zh ? 'MCP：让外部 AI 调用绘图工具' : 'MCP for external AI tools',
            body: zh
                ? '源码仓库已经包含 MCP 配置和服务器。Cursor 打开仓库即可读取 '
                      '.cursor/mcp.json；其他 MCP 客户端可使用下方命令。需要修改当前应用'
                      '中的图时，请先开启 Agent live preview。'
                : 'The source repository includes an MCP server and Cursor '
                      'configuration. Cursor reads .cursor/mcp.json automatically; '
                      'other MCP clients can use the command below. Enable Agent '
                      'live preview before editing the running app.',
            code: '''
dart run packages/vsdx/bin/vsdxtool_mcp.dart

{
  "mcpServers": {
    "visioeditor": {
      "command": "dart",
      "args": ["run", "packages/vsdx/bin/vsdxtool_mcp.dart"]
    }
  }
}''',
          ),
          _HelpSection(
            icon: Icons.terminal_outlined,
            title: zh ? 'CLI 与 Agent Skill' : 'CLI and Agent Skill',
            body: zh
                ? '不启动应用也可以通过 Diagram Spec、Mermaid、SQL DDL、OpenAPI、IaC '
                      '或代码依赖生成 .vsdx。Agent 的完整工作流位于 '
                      'skills/visioeditor-skill/SKILL.md。常用命令：'
                : 'Without launching the app, generate .vsdx from Diagram Spec, '
                      'Mermaid, SQL DDL, OpenAPI, IaC or source dependencies. The '
                      'agent workflow is in skills/visioeditor-skill/SKILL.md.',
            code: '''
dart run packages/vsdx/bin/vsdxtool.dart build spec.json -o flow.vsdx
dart run packages/vsdx/bin/vsdxtool.dart import-mermaid flow.mmd -o flow.vsdx
dart run packages/vsdx/bin/vsdxtool.dart validate flow.vsdx
bash packages/vsdx/tool/build_agent_binaries.sh''',
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.body,
    this.code,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body),
            if (code case final value?) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  value,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
