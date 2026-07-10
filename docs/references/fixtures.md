# 测试样本（Fixtures）

> 测试 fixture 是验证解析与渲染的基石。本文档记录每个样本的**来源、特性、合规性**，
> 以及如何生成新的样本。

样本统一放在：`test/fixtures/<feature>_<variant>.vsdx`（合成）或 `assets/examples/dave-howard-vsdx/`（真实 Visio 样例，随应用发布）

---

## 1. 现有 fixture（M0 完成后补全）

| 文件名 | 来源 | 许可证 | 测试目标 |
|---|---|---|---|
| `empty_minimal.vsdx` | LibreOffice Draw 导出 | 自有 ✅ | OPC 结构最小合法 |
| `geometry_rect_basic.vsdx` | 同上 | 自有 ✅ | 单矩形 + 默认填充 |
| `geometry_arc_basic.vsdx` | 同上 | 自有 ✅ | ArcTo / EllipticalArcTo |
| `text_singleline.vsdx` | 同上 | 自有 ✅ | 单行文本 + 字符格式 |
| `text_multiline_richtext.vsdx` | 同上 | 自有 ✅ | 多段 `<cp>` 富文本 |
| `master_inheritance_basic.vsdx` | 同上 | 自有 ✅ | Master 继承 + 多实例 |
| `connector_straight.vsdx` | 同上 | 自有 ✅ | 1D 形状 + `<Connect>` |
| `theme_office_default.vsdx` | 同上 | 自有 ✅ | 默认主题色映射 |
| `image_embed_png.vsdx` | 同上 | 自有 ✅ | 嵌入 PNG |
| `image_embed_emf.vsdx` | 同上 | 自有 ✅ | 嵌入 EMF（占位回退） |
| `flowchart_classic.vsdx` | 同上 | 自有 ✅ | 端到端：流程图典型 |

> 上述 fixture 在 M0 任务 [M0-09](../PLAN.md#3-m0--项目脚手架bootstrap) 中创建。

---

## 2. 制作流程

### 2.1 使用 LibreOffice Draw（推荐）

```bash
# Linux/macOS：命令行批量另存
soffice --headless --convert-to vsdx my_drawing.odg

# 或在 Draw 中：文件 → 另存为 → Visio 2013 (.vsdx)
```

LibreOffice 的 .vsdx 输出已被 libvisio 验证可被 Microsoft Visio 打开，结构干净。

### 2.2 使用 Microsoft Visio Trial

- 30 天试用 → <https://www.microsoft.com/microsoft-365/visio/>
- 只用来**生成自己绘制的图形**，不分发 Microsoft 自带模板
- 注意：把 `Backstage → 文档属性` 中的作者信息清空，避免泄露隐私

### 2.3 使用 Python `vsdx` 库程序化生成

```python
# 仅做 fixture 生成，不打包进项目运行时
from vsdx import VisioFile
with VisioFile('template.vsdx') as v:
    page = v.pages[0]
    shape = page.find_shape_by_text('Hello')
    shape.text = 'New text'
    v.save_vsdx('test/fixtures/text_modified.vsdx')
```

### 2.4 程序化构造（最终）

未来当我们实现 SVG ↔ VSDX 互转后，可用 `bin/svg2vsdx.dart` 生成定制 fixture。

---

## 3. fixture 的 README 模板

每个 fixture 在 `test/fixtures/README.md` 中登记：

```markdown
### geometry_arc_basic.vsdx

- 制作工具：LibreOffice Draw 24.8.4 (Linux)
- 创建日期：2026-05-22
- 描述：一个椭圆 + 一段椭圆弧，验证 EllipticalArcTo 的 6 参数解析
- 期望渲染：见 test/golden/geometry_arc_basic.png
- 关联用例：test/parser/geometry_parser_test.dart::testArcBasic
- 许可：项目自有（MIT）
```

---

## 4. 合规检查清单

新增 fixture 前自查：

- [ ] 是否包含他人著作权图形（如 Visio 自带的 "Network Shapes" 模具）？→ ❌ 删除
- [ ] 是否包含个人 / 公司隐私（作者名、文件路径、注释）？→ ❌ 清理
- [ ] 是否能在 LibreOffice 与 Visio 中都正常打开？→ ✅ 必须
- [ ] 是否提供期望渲染基线（golden PNG）？→ ✅ 必须

---

## 5. 大型 / 复杂样本（M8 性能基准用）

| 文件名 | 规模 | 来源 |
|---|---|---|
| `perf_100pages_simple.vsdx` | 100 页 × 5 形状 | 程序化生成 |
| `perf_1000shapes_singlepage.vsdx` | 1 页 × 1000 形状 | 程序化生成 |
| `perf_50mb_realistic.vsdx` | 真实流程图 | LibreOffice 拼接 |

> 大文件不入 git，放 `test/fixtures/large/` 并加入 `.gitignore`；由 CI 从 release 下载。
