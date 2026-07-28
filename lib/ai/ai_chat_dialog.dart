import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'ai_engine.dart';
import 'ai_help_page.dart';

typedef AiDiagramCallback = Future<void> Function(AiDiagramDraft draft);

Future<void> showAiChatDialog(
  BuildContext context, {
  required AppSettings settings,
  required AiDiagramCallback onCreateDiagram,
  AiChatService? service,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierDismissible: false,
    builder: (_) => AiChatDialog(
      settings: settings,
      onCreateDiagram: onCreateDiagram,
      service: service,
    ),
  );
}

class AiChatDialog extends StatefulWidget {
  const AiChatDialog({
    required this.settings,
    required this.onCreateDiagram,
    this.service,
    super.key,
  });

  final AppSettings settings;
  final AiDiagramCallback onCreateDiagram;
  final AiChatService? service;

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<AiChatMessage> _history = <AiChatMessage>[];
  final List<_ChatEntry> _entries = <_ChatEntry>[];
  late final AiChatService _service = widget.service ?? AiChatService();
  bool _busy = false;
  bool _creating = false;
  bool _welcomeLocalized = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _entries.add(
      _ChatEntry(
        role: 'assistant',
        content:
            'Describe the flow you want to draw. I can ask questions, '
            'prepare a structured flowchart, and open it as an editable diagram.',
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_welcomeLocalized) return;
    _welcomeLocalized = true;
    if (_zh) {
      _entries[0] = const _ChatEntry(
        role: 'assistant',
        content:
            '请描述你要绘制的流程。我可以与你确认需求、整理结构化流程图，'
            '并将结果作为可编辑图表在新标签页中打开。',
      );
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || text.isEmpty) return;
    if (!widget.settings.aiEngine.isReady) {
      await showAiEngineDialog(context, settings: widget.settings);
      if (!mounted || !widget.settings.aiEngine.isReady) return;
    }
    _input.clear();
    final user = AiChatMessage(role: 'user', content: text);
    setState(() {
      _history.add(user);
      _entries.add(_ChatEntry(role: 'user', content: text));
      _busy = true;
    });
    _scrollToEnd();
    try {
      final response = await _service.complete(
        widget.settings.aiEngine,
        List<AiChatMessage>.unmodifiable(_history),
      );
      if (!mounted) return;
      final assistant = AiChatMessage(role: 'assistant', content: response);
      setState(() {
        _history.add(assistant);
        _entries.add(
          _ChatEntry(
            role: 'assistant',
            content: response,
            draft: AiChatService.extractDiagram(response),
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry(role: 'error', content: error.toString()));
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<void> _create(AiDiagramDraft draft) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await widget.onCreateDiagram(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _zh ? '已在新标签页创建可编辑图表' : 'Editable diagram opened in a new tab',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 700 || size.height < 620;
    final content = _buildContent(context);
    if (compact) return Dialog.fullscreen(child: content);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height: size.height.clamp(560, 760).toDouble(),
        child: content,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final engine = widget.settings.aiEngine;
    final showEngineLabel = MediaQuery.sizeOf(context).width >= 640;
    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _zh ? 'AI 流程图助手' : 'AI diagram assistant',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (showEngineLabel)
                  TextButton.icon(
                    key: const Key('ai-engine-button'),
                    onPressed: _configureEngine,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      '${engine.provider.label} · ${engine.model}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  IconButton(
                    key: const Key('ai-engine-button'),
                    tooltip: '${engine.provider.label} · ${engine.model}',
                    onPressed: _configureEngine,
                    icon: const Icon(Icons.tune),
                  ),
                IconButton(
                  tooltip: _zh ? 'AI 接入说明' : 'AI integration guide',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiIntegrationHelpPage(),
                    ),
                  ),
                  icon: const Icon(Icons.help_outline),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length + (_busy ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _entries.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _MessageBubble(
                  entry: _entries[index],
                  creating: _creating,
                  onCreate: _create,
                  zh: _zh,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('ai-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _zh
                          ? '例如：创建一个带审批判断的请假流程'
                          : 'Example: Create a leave approval flow',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('ai-chat-send'),
                  tooltip: _zh ? '发送' : 'Send',
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configureEngine() async {
    await showAiEngineDialog(context, settings: widget.settings);
    if (mounted) setState(() {});
  }
}

class _ChatEntry {
  const _ChatEntry({required this.role, required this.content, this.draft});

  final String role;
  final String content;
  final AiDiagramDraft? draft;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.entry,
    required this.creating,
    required this.onCreate,
    required this.zh,
  });

  final _ChatEntry entry;
  final bool creating;
  final Future<void> Function(AiDiagramDraft draft) onCreate;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = entry.role == 'user';
    final error = entry.role == 'error';
    final bg = error
        ? scheme.errorContainer
        : user
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final fg = error
        ? scheme.onErrorContainer
        : user
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(entry.content, style: TextStyle(color: fg)),
            if (entry.draft case final draft?) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('ai-create-diagram'),
                onPressed: creating ? null : () => onCreate(draft),
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(
                  zh
                      ? '创建图表 · ${draft.title}'
                      : 'Create diagram · ${draft.title}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showAiEngineDialog(
  BuildContext context, {
  required AppSettings settings,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AiEngineDialog(settings: settings),
  );
}

class _AiEngineDialog extends StatefulWidget {
  const _AiEngineDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_AiEngineDialog> createState() => _AiEngineDialogState();
}

class _AiEngineDialogState extends State<_AiEngineDialog> {
  late AiProvider _provider = widget.settings.aiEngine.provider;
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.settings.aiEngine.endpoint,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.settings.aiEngine.model,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.settings.aiEngine.apiKey,
  );
  bool _obscure = true;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _selectProvider(AiProvider? value) {
    if (value == null || value == _provider) return;
    final defaults = AiEngineConfig.defaultsFor(value);
    setState(() {
      _provider = value;
      _endpoint.text = defaults.endpoint;
      _model.text = defaults.model;
    });
  }

  Future<void> _save() async {
    final config = AiEngineConfig(
      provider: _provider,
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
      apiKey: _key.text.trim(),
    );
    if (!config.isReady) return;
    await widget.settings.setAiEngine(config);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ready = AiEngineConfig(
      provider: _provider,
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
      apiKey: _key.text.trim(),
    ).isReady;
    return AlertDialog(
      title: Text(_zh ? '配置 AI 引擎' : 'Configure AI engine'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AiProvider>(
                key: const Key('ai-provider'),
                initialValue: _provider,
                decoration: InputDecoration(
                  labelText: _zh ? '接口类型' : 'Provider protocol',
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<AiProvider>>[
                  for (final provider in AiProvider.values)
                    DropdownMenuItem<AiProvider>(
                      value: provider,
                      child: Text(provider.label),
                    ),
                ],
                onChanged: _selectProvider,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ai-endpoint'),
                controller: _endpoint,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _zh ? '接口地址' : 'Endpoint',
                  hintText: _provider.defaultEndpoint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ai-model'),
                controller: _model,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _zh ? '模型' : 'Model',
                  hintText: _provider.defaultModel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ai-api-key'),
                controller: _key,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _provider.requiresApiKey
                      ? 'API Key'
                      : (_zh ? 'API Key（可选）' : 'API key (optional)'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _zh
                    ? '兼容网关请选择 OpenAI compatible。配置保存在本机；完整对话会发送到该接口。'
                    : 'Use OpenAI compatible for custom gateways. Settings are '
                          'stored locally; the conversation is sent to this endpoint.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('ai-engine-save'),
          onPressed: ready ? _save : null,
          child: Text(_zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}
