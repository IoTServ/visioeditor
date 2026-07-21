# QA 验收记录（操作 / 属性 / 显示 / 往返）

进度标记：`TODO` → `DOING` → `DONE` / `BLOCKED` / `LATER`。

范围（本轮已确认）：macOS 编辑器操作、图形属性与渲染、VSD/VSDX 导入、VSDX/SVG/PNG/PDF 导出；自动化结构/模型/像素校验即可。不纳入 Agent/MCP/跨平台打包。`tmp/` 不提交。

---

## 总进度

| 域 | 状态 | 备注 |
| --- | --- | --- |
| 静态分析 | DONE | `flutter analyze` / `dart analyze packages/vsdx` 无告警（本轮验证前已绿） |
| 单元/集成测试 | DONE | vsdx `1030` 通过；Flutter test / macOS debug 构建通过 |
| 画布手势 | DONE | `DragStartBehavior.down`；移动/缩放/旋转/Esc；框选多选 |
| Master 文本继承 | DONE | Character 字号优先链 + 无本地 Text 时继承 Master 富文本 |
| 连接器 Pin | DONE | 仅 Begin/End 公式时规范化；字面量 Pin 不被中点公式覆盖 |
| Ranking 图标签 | DONE | 排序后补标签；空 values 兜底 |
| VSDX equal-path 填充 | DONE | 叶子缺 `FillForegnd` 注入；Group 不误注入 `FillPattern=1` |
| Edraw 往返探针 | DONE | fixtures（含中文样例）均为 `[ok]` |
| LibreOffice 交叉打开 | BLOCKED | 本机无 `soffice`；CI `libreoffice-crosscheck` 覆盖（见 fixtures.md） |
| 架构/fixture 文档 | DONE | `ARCHITECTURE.md` / `references/fixtures.md` 已与仓库对齐 |
| SVG→VSDX | LATER | 无此路径 |
| 二进制 `.vsd` 写回 | LATER | 仅 VSD→VSDX |

---

## 编辑器操作

| 项 | 状态 | 进度 / 证据 |
| --- | --- | --- |
| 选择 / 多选 | DONE | Controller + canvas 测试 |
| 移动 | DONE | `page_canvas_test`（`DragStartBehavior.down`） |
| 缩放手柄 | DONE | 同上 |
| 旋转手柄 | DONE | 同上 |
| Esc 取消拖动 | DONE | 同上 |
| 框选多选 | DONE | `page_canvas_test` marquee |
| 撤销 / 重做 | DONE | 既有 Controller 测试 |
| 锁定 / 图层 | DONE | 既有测试；Color-by-Layer 视图已接 |
| 组合 / 取消组合 | DONE | `page.group` 无填充容器；往返不污染 Group Fill |
| 连接器路由 / 粘附 | DONE | Pin 往返回归（`connector_preserve` / Writer） |
| 表格 / 泳道 | DONE | 既有模型测试（本轮未新发现 P0） |

---

## 图形属性与显示

| 项 | 状态 | 进度 / 证据 |
| --- | --- | --- |
| 几何 Pin/Size/Angle/Flip | DONE | Parser/Writer/画布 |
| 填充色 / Pattern | DONE | 叶子 `FillForegnd` 愈合；Group 省略空 Fill* |
| 线条色 / 线宽 / 箭头 | DONE | equal-path ensure + 既有往返 |
| 文字 / Character / Master | DONE | Master 字号与文本继承修复 |
| 主题色 THEMEVAL | DONE | 既有 theme roundtrip |
| 阴影 / 发光 / 渐变 | DONE | equal-path scrub；细项见 LATER |
| 图片 / ForeignData | DONE | PNG 导出图像测试 |
| 双圆角（Rounding vs setCornerRadius） | DONE | UI 写入 `Line.Rounding`；弧烘焙圆角会被展平 |
| 页阴影斜切 | DONE | Canvas/SVG 应用 PageSheet scale+oblique |
| 图层色参与绘制 | DONE | Color-by-Layer 会话开关；Canvas/SVG 共用 `layerColorSource` |
| FontScale / 虚线近似 | DONE | 虚线按线宽缩放；FontScale 用 0.55×字号 tracking + 宽度估算乘 scale |

---

## 导入 / 导出往返

| 路径 | 状态 | 进度 / 证据 |
| --- | --- | --- |
| 打开 `.vsdx` → 保存 → 重开 | DONE | Writer 测试 + Edraw 探针 |
| 打开 `.vsd` → 另存 `.vsdx` | DONE | `edraw_roundtrip_check` VSD 段全 `[ok]` |
| 导出 SVG | DONE | 结构序列化 + 既有测试 |
| 导出 PNG | DONE | `png_export_image_test` |
| 导出 PDF | DONE | 依赖 Flutter 打印链路；自动化覆盖有限 → 记为 DONE（结构）/ 外部像素 LATER |
| Edraw 结构探针 | DONE | `tool/edraw_roundtrip_check.dart`；中文样例 `fill-no-Foregnd` 已清零 |
| Visio / LibreOffice 打开 | BLOCKED | 无本机 soffice；进度：待 CI 或装 LibreOffice 后重跑 |

### 本轮关键并修复的往返缺陷

1. **Master 文本被 stylesheet 盖成 12pt / 丢标签** — `page_parser.dart`
2. **连接器字面量 Pin 被中点公式覆盖** — `page_parser.dart` + `vsdx_writer.dart`
3. **画布手柄 touch slop** — `page_canvas.dart`
4. **Ranking 缺标签** — `chart_shapes.dart`
5. **叶子缺 FillForegnd → Edraw 空心** — Writer equal-path 注入
6. **裸 Group 被注入 FillPattern=1 无 Foregnd** — equal-path 对 Group 跳过缺失 `FillPattern` 的 ensure（`人才招聘冰山模型` / `数据治理`）

---

## 验证命令（提交前）

```bash
# packages/vsdx
cd packages/vsdx && dart analyze && dart test

# 应用
cd ../.. && flutter analyze && flutter test
flutter build macos --debug

# Edraw 往返（可选）
HOME=/tmp/visioeditor-qa-home dart run packages/vsdx/tool/edraw_roundtrip_check.dart
```

| 命令 | 状态 |
| --- | --- |
| `dart analyze` (vsdx) | DONE |
| `dart test` (vsdx writer 相关) | DONE |
| `dart test` (vsdx 全量) | DONE (`+1030 ~3`) |
| `flutter analyze` / `flutter test` | DONE |
| `flutter build macos --debug` | DONE |
| Edraw 探针（含中文） | DONE |

---

## LATER / BLOCKED 清单（旁注进度位）

| ID | 问题 | 标记 | 下次动作 |
| --- | --- | --- | --- |
| QA-01 | LibreOffice/Visio 实机打开导出文件 | BLOCKED | 本机无 soffice；CI `libreoffice-crosscheck`（`REQUIRE_SOFFICE=1`）覆盖；进度：本地仍待装 LO |
| QA-02 | 双圆角属性语义 | DONE | `setCornerRadius` → `Rounding`；弧圆角展平 |
| QA-03a | 页阴影斜切 / 缩放 | DONE | Canvas + SVG `_pageShadowTransform` |
| QA-03b | 图层色绘制 | DONE | Color-by-Layer 开关；填充/描边/文字染色 |
| QA-04 | FontScale、虚线样式近似 | DONE | 共享 `dash_pattern.dart`（按 LineWeight）；FontScale tracking 对齐布局 |
| QA-05 | SVG→VSDX、二进制 VSD 写回 | LATER | 产品范围外 |
| QA-06 | Agent ops 覆盖面 < UI | LATER | 非本轮范围 |
| QA-07 | ARCHITECTURE / fixtures 文档漂移 | DONE | 目录与真实 fixture 清单已纠正 |
