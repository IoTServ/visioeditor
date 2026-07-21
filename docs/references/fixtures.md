# 测试样本（Fixtures）

> 以仓库内**实际文件**为准。早期 M0 规划名（如 `geometry_rect_basic.vsdx`）大多未落地；
> 勿按旧表查找。

---

## 1. 引擎包：`packages/vsdx/test/fixtures/`

权威说明见同目录 [`README.md`](../../packages/vsdx/test/fixtures/README.md)。

| 类别 | 文件 | 来源 / 用途 |
| --- | --- | --- |
| Dave Howard BSD 样例 | `test1.vsdx` … `test12_*.vsdx`、`test_jinja*.vsdx`、`test_master*.vsdx` | 解析 / Writer / 连接器 / Master |
| 应用镜像样例 | `workflow.vsdx` | 与 `assets/examples/workflow.vsdx` 对齐 |
| 中文 Edraw 样例 | `人才招聘冰山模型.vsdx`、`数据治理.vsdx` | Edraw 往返探针（填充愈合等） |
| 遗留 VSD | `vsd/`、`vsd/external/` | `.vsd` → `.vsdx` 导入与合成基线 |

运行 Edraw 结构往返：

```bash
cd packages/vsdx
HOME=/tmp/visioeditor-qa-home dart run tool/edraw_roundtrip_check.dart
```

---

## 2. 应用样例：`assets/examples/`

编辑器「打开示例」与部分 Flutter / stress 探针使用（约数十个 `.vsdx` 模板）。引擎
`stress_props_roundtrip_probe` 会对其中一部分做 identity rewrite。

---

## 3. LibreOffice 交叉验证

本机可选；CI 任务 `libreoffice-crosscheck`（`REQUIRE_SOFFICE=1`）安装 `soffice` 后执行：

```bash
cd packages/vsdx
REQUIRE_SOFFICE=1 dart test test/libreoffice_crosscheck_test.dart
```

无 `soffice` 时测试会 skip（不失败）。验收进度见 [`QA_AUDIT.md`](./QA_AUDIT.md) QA-01。

---

## 4. 制作新样本（可选）

```bash
# 需已安装 LibreOffice
soffice --headless --convert-to vsdx my_drawing.odg
```

或在 Microsoft Visio / 万兴图示中另存为 `.vsdx` 后放入
`packages/vsdx/test/fixtures/`（注明来源与许可证）。
