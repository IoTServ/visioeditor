# third_party — 开源参考克隆（Reference Clones）

本目录存放**仅供阅读参考**的上游开源项目。它们**不随本仓库提交**（见根
`.gitignore`），需要时按下表命令重新克隆。参考策略与许可证分级见
[`docs/references/projects.md`](../docs/references/projects.md)。

> 许可证分级：
> - 可参考代码：MIT / BSD / Apache-2.0 / MPL-2.0
> - 谨慎参考（看文档、重写算法，不复制）：LGPL / GPL / AGPL

---

## 记录（Pinned Clones）

### vsdx （dave-howard） — BSD-3-Clause ✅ 关键 Writer 参考
- URL: <https://github.com/dave-howard/vsdx>
- commit: `6703e6c2c906bea4051f43525ec9af9dcf735c13`（2026-01-04，`--depth 1`）
- 用途：VSDX（OPC）文件的读/改/写操作、Master 继承、jinja 模板；干净的 OPC 解包与
  shape 增删改逻辑，是本项目 `packages/vsdx/writer/` 的**主要代码参考**。
- 许可：`vsdx/LICENSE`（保留版权头后可参考代码）

### libvisio （LibreOffice） — MPL-2.0 + LGPLv2.1+ ⚠️ 仅读文档/重写算法
- URL: <https://github.com/LibreOffice/libvisio>
- commit: `f793b99ae50f9dc8cc14683eac0fdca619b13eaa`（2026-05-26，`--depth 1`）
- 用途：工业级 `.vsd`/`.vsdx` 解析实现，参考 record 类型表、几何(NURBS/Arc)离散化思路、
  文档级测试集设计。**仅阅读，不复制源码**；后续 `.vsd` 老格式导入亦以此为算法参考。
- 许可：`libvisio/COPYING.MPL`

### drawio （jgraph） — Apache-2.0 ✅
- URL: <https://github.com/jgraph/drawio>
- commit: `43c1dfa7db49cca465312c00e9ed8b85b4195a7c`（2026-07-09，`--depth 1 --filter=blob:limit=1m`）
- 用途：内置 `.vsdx` 导入/导出（`VsdxImport`/`VsdxExport`），形状库映射、Arc→Bezier
  转换等，可读性高，供几何与形状映射参考。
- 许可：`drawio/LICENSE`

### drawio-skill （Agents365-ai） — MIT ✅ AI Skill 参考
- URL: <https://github.com/Agents365-ai/drawio-skill>
- commit: `6f33563adce24450003d1cb61111ebbcc5579f28`（2026-07-17，`--depth 1`）
- 用途：纯 `SKILL.md` + 31 个 Python 脚本，自然语言 → `.drawio` → 导出，含自检回路、
  importers、样式预设。是本项目 [`docs/MCP_SKILL_PLAN.md`](../docs/MCP_SKILL_PLAN.md)
  **Skill 与工作流**的主要参考。
- 许可：`drawio-skill/LICENSE`

### drawio-mcp （jgraph） — Apache-2.0 ✅ MCP 参考
- URL: <https://github.com/jgraph/drawio-mcp>
- commit: `e26f034ef2aae81bbb3c5d92c9b9bb470c8a1e6a`（2026-07-17，`--depth 1`）
- 用途：官方 MCP —— `mcp-tool-server`（浏览器打开）/ `mcp-app-server`（聊天内联渲染）/
  Claude Code 插件 / `shape-search`（1 万+形状索引）/ `shared`（xml/style/mermaid 参考）。
  是本项目 **MCP 服务器与工具接口设计**的主要参考。
- 许可：`drawio-mcp/LICENSE`

---

## 重新克隆命令

```bash
cd third_party
git clone --depth 1 https://github.com/dave-howard/vsdx.git vsdx
git clone --depth 1 https://github.com/LibreOffice/libvisio.git libvisio
git clone --depth 1 --filter=blob:limit=1m https://github.com/jgraph/drawio.git drawio
git clone --depth 1 https://github.com/Agents365-ai/drawio-skill.git drawio-skill
git clone --depth 1 https://github.com/jgraph/drawio-mcp.git drawio-mcp
```
