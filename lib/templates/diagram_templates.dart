/// Catalog of starter diagram templates shown in "New from template".
///
/// Assets under `assets/examples/` are produced by
/// `dart run tool/gen_example_templates.dart`. Titles/descriptions are
/// bilingual (en/zh); other locales fall back to English.
library;

import 'package:flutter/material.dart';

/// High-level grouping in the template picker.
enum TemplateCategory {
  blank,
  flowchart,
  business,
  planning,
  analysis,
  technical,
}

extension TemplateCategoryLabel on TemplateCategory {
  (String en, String zh) get labels => switch (this) {
        TemplateCategory.blank => ('Blank', '空白'),
        TemplateCategory.flowchart => ('Flowcharts', '流程图'),
        TemplateCategory.business => ('Business', '商务'),
        TemplateCategory.planning => ('Planning', '规划'),
        TemplateCategory.analysis => ('Analysis', '分析'),
        TemplateCategory.technical => ('Technical', '技术'),
      };

  IconData get icon => switch (this) {
        TemplateCategory.blank => Icons.crop_portrait_outlined,
        TemplateCategory.flowchart => Icons.account_tree_outlined,
        TemplateCategory.business => Icons.business_center_outlined,
        TemplateCategory.planning => Icons.view_timeline_outlined,
        TemplateCategory.analysis => Icons.analytics_outlined,
        TemplateCategory.technical => Icons.hub_outlined,
      };
}

@immutable
class DiagramTemplate {
  const DiagramTemplate({
    required this.id,
    required this.category,
    required this.assetName,
    required this.titleEn,
    required this.titleZh,
    required this.descEn,
    required this.descZh,
    required this.accent,
    required this.icon,
  });

  final String id;

  /// `null` asset ⇒ blank document (no file to load).
  final String? assetName;
  final TemplateCategory category;
  final String titleEn;
  final String titleZh;
  final String descEn;
  final String descZh;
  final Color accent;
  final IconData icon;

  String titleFor(Locale locale) =>
      locale.languageCode == 'zh' ? titleZh : titleEn;

  String descFor(Locale locale) =>
      locale.languageCode == 'zh' ? descZh : descEn;

  bool get isBlank => assetName == null;
}

/// Full catalog — blank first, then curated starters.
const List<DiagramTemplate> kDiagramTemplates = <DiagramTemplate>[
  DiagramTemplate(
    id: 'blank',
    category: TemplateCategory.blank,
    assetName: null,
    titleEn: 'Blank drawing',
    titleZh: '空白绘图',
    descEn: 'Start with an empty page.',
    descZh: '从空白页开始创作。',
    accent: Color(0xFF64748B),
    icon: Icons.note_add_outlined,
  ),
  DiagramTemplate(
    id: 'process_flow',
    category: TemplateCategory.flowchart,
    assetName: 'Process Flow.vsdx',
    titleEn: 'Process flow',
    titleZh: '流程图',
    descEn: 'Start → decide → build → done.',
    descZh: '开始 → 决策 → 构建 → 完成。',
    accent: Color(0xFF2563EB),
    icon: Icons.account_tree_outlined,
  ),
  DiagramTemplate(
    id: 'cycle',
    category: TemplateCategory.flowchart,
    assetName: 'Cycle Process.vsdx',
    titleEn: 'PDCA cycle',
    titleZh: 'PDCA 循环',
    descEn: 'Plan → Do → Check → Act loop.',
    descZh: '计划 → 执行 → 检查 → 改进。',
    accent: Color(0xFF7C3AED),
    icon: Icons.autorenew,
  ),
  DiagramTemplate(
    id: 'workflow',
    category: TemplateCategory.flowchart,
    assetName: 'workflow.vsdx',
    titleEn: 'Workflow demo',
    titleZh: '工作流示例',
    descEn: 'Built-in multi-step workflow sample.',
    descZh: '内置多步骤工作流示例。',
    accent: Color(0xFF0EA5E9),
    icon: Icons.alt_route,
  ),
  DiagramTemplate(
    id: 'org',
    category: TemplateCategory.business,
    assetName: 'Org Chart.vsdx',
    titleEn: 'Org chart',
    titleZh: '组织架构',
    descEn: 'Leadership and team hierarchy.',
    descZh: '领导层与团队层级结构。',
    accent: Color(0xFF0284C7),
    icon: Icons.groups_outlined,
  ),
  DiagramTemplate(
    id: 'funnel',
    category: TemplateCategory.business,
    assetName: 'Sales Funnel.vsdx',
    titleEn: 'Sales funnel',
    titleZh: '销售漏斗',
    descEn: 'Awareness to purchase stages.',
    descZh: '从认知到成交的阶段漏斗。',
    accent: Color(0xFFDB2777),
    icon: Icons.filter_alt_outlined,
  ),
  DiagramTemplate(
    id: 'meeting',
    category: TemplateCategory.business,
    assetName: 'Meeting Agenda.vsdx',
    titleEn: 'Meeting agenda',
    titleZh: '会议议程',
    descEn: 'Timed agenda blocks for a sync.',
    descZh: '带时长的周会/同步议程。',
    accent: Color(0xFF4F46E5),
    icon: Icons.event_note_outlined,
  ),
  DiagramTemplate(
    id: 'okr',
    category: TemplateCategory.business,
    assetName: 'OKR Cascade.vsdx',
    titleEn: 'OKR cascade',
    titleZh: 'OKR 分解',
    descEn: 'Objective with key results below.',
    descZh: '目标向下分解为关键结果。',
    accent: Color(0xFF0891B2),
    icon: Icons.flag_outlined,
  ),
  DiagramTemplate(
    id: 'roadmap',
    category: TemplateCategory.planning,
    assetName: 'Project Roadmap.vsdx',
    titleEn: 'Project roadmap',
    titleZh: '项目路线图',
    descEn: 'Discover → design → build → launch.',
    descZh: '探索 → 设计 → 构建 → 发布。',
    accent: Color(0xFFCA8A04),
    icon: Icons.map_outlined,
  ),
  DiagramTemplate(
    id: 'timeline',
    category: TemplateCategory.planning,
    assetName: 'Timeline.vsdx',
    titleEn: 'Timeline',
    titleZh: '时间线',
    descEn: 'Milestones along a horizontal rail.',
    descZh: '水平时间轴上的关键里程碑。',
    accent: Color(0xFFEA580C),
    icon: Icons.view_timeline_outlined,
  ),
  DiagramTemplate(
    id: 'kanban',
    category: TemplateCategory.planning,
    assetName: 'Kanban Board.vsdx',
    titleEn: 'Kanban board',
    titleZh: '看板',
    descEn: 'Backlog / Doing / Done columns.',
    descZh: '待办 / 进行中 / 完成 三列看板。',
    accent: Color(0xFF16A34A),
    icon: Icons.view_column_outlined,
  ),
  DiagramTemplate(
    id: 'journey',
    category: TemplateCategory.planning,
    assetName: 'User Journey.vsdx',
    titleEn: 'User journey',
    titleZh: '用户旅程',
    descEn: 'Stages with mood and touchpoints.',
    descZh: '阶段、情绪与触点地图。',
    accent: Color(0xFFD946EF),
    icon: Icons.hiking,
  ),
  DiagramTemplate(
    id: 'swot',
    category: TemplateCategory.analysis,
    assetName: 'SWOT Matrix.vsdx',
    titleEn: 'SWOT matrix',
    titleZh: 'SWOT 矩阵',
    descEn: 'Strengths, weaknesses, opportunities, threats.',
    descZh: '优势、劣势、机会与威胁。',
    accent: Color(0xFF059669),
    icon: Icons.grid_view_outlined,
  ),
  DiagramTemplate(
    id: 'mindmap',
    category: TemplateCategory.analysis,
    assetName: 'Mind Map.vsdx',
    titleEn: 'Mind map',
    titleZh: '思维导图',
    descEn: 'Central idea with radiating branches.',
    descZh: '中心主题向四周发散分支。',
    accent: Color(0xFF8B5CF6),
    icon: Icons.bubble_chart_outlined,
  ),
  DiagramTemplate(
    id: 'fishbone',
    category: TemplateCategory.analysis,
    assetName: 'Fishbone.vsdx',
    titleEn: 'Fishbone',
    titleZh: '鱼骨图',
    descEn: 'Cause-and-effect categories.',
    descZh: '因果分析（石川图）分类。',
    accent: Color(0xFFDC2626),
    icon: Icons.polyline_outlined,
  ),
  DiagramTemplate(
    id: 'venn',
    category: TemplateCategory.analysis,
    assetName: 'Venn Diagram.vsdx',
    titleEn: 'Venn diagram',
    titleZh: '维恩图',
    descEn: 'Two overlapping sets.',
    descZh: '两组集合的重叠关系。',
    accent: Color(0xFFEC4899),
    icon: Icons.join_inner,
  ),
  DiagramTemplate(
    id: 'architecture',
    category: TemplateCategory.technical,
    assetName: 'System Architecture.vsdx',
    titleEn: 'System architecture',
    titleZh: '系统架构',
    descEn: 'Clients, gateway, services, data.',
    descZh: '客户端、网关、服务与数据。',
    accent: Color(0xFF4338CA),
    icon: Icons.layers_outlined,
  ),
  DiagramTemplate(
    id: 'network',
    category: TemplateCategory.technical,
    assetName: 'Network Topology.vsdx',
    titleEn: 'Network topology',
    titleZh: '网络拓扑',
    descEn: 'Core hub with edge nodes.',
    descZh: '核心节点与边缘设备拓扑。',
    accent: Color(0xFF0F766E),
    icon: Icons.device_hub_outlined,
  ),
];

List<DiagramTemplate> templatesFor(TemplateCategory category) =>
    kDiagramTemplates.where((t) => t.category == category).toList();
