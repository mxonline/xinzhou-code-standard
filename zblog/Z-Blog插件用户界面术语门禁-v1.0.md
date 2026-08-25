# Z-Blog 插件用户界面术语门禁 v1.0

本规范是 `Z-Blog插件完整开发流程-v2.0.md` 与 `Z-Blog插件UI产品化验收规范-v1.0.md` 的强制补充门禁，适用于所有存在后台页面、前台设置页、弹窗、Drawer、图表、表格、筛选器、提示信息或其它用户可见 UI 的 Z-Blog PHP 插件。

目标：在代码进入正式发布前，自动阻止数据库字段名、内部变量、分页实现、统计学内部指标、英文枚举、开发占位词和 AI/工程化说明直接进入用户界面。

## 一、门禁名称

统一名称：

```text
UI Terminology Gate
```

它与以下门禁并列：

```text
Functional Product Gate
UI Product Gate
UI Terminology Gate
Local Runtime
GitHub CI
Release Gate
```

任何一项 `BLOCKED`，Release Gate 必须为 `BLOCKED`，禁止 Tag / GitHub Release / 正式 ZIP。

## 二、执行位置

### T3：UI 实现阶段

后台 UI 初步完成后立即执行术语扫描，避免将开发语言继续扩散到更多页面。

### T5：最终验收阶段

重新扫描全部正式用户界面；T3 的 PASS 不能替代 T5 的最终扫描。

### GitHub CI

包含 UI 的插件必须将扫描脚本接入 CI。CI 中术语门禁失败时，整个质量检查失败，不得使用 `continue-on-error`。

## 三、禁止直接暴露的术语

以下内容默认不得作为普通用户界面的主标题、表格列名、按钮、筛选项、空状态、提示或详情字段名：

- `字段 1 / 字段 2 / 字段 N`
- `DurationMs`
- `PathKey`
- `Keyset`
- `OFFSET`
- `cursor`
- `migration`
- `backfill`
- `Referer`
- `Browser`
- `Device`
- `Campaign`
- `AI crawler`
- `规范化 Path`
- `下钻`
- 数据库字段名、PHP/JS内部变量名、函数名、状态机内部值
- `direct/search/social/external/internal/desktop/mobile/tablet` 等内部枚举原值

这些词可以存在于源码、数据库、API、测试、日志和开发文档中，但不得未经产品化转换直接出现在普通 UI。

## 四、允许保留但必须有中文上下文的术语

以下行业缩写可以保留，但普通界面必须先给中文业务含义：

- PV / UV / IP / UTM
- RUM
- LCP / INP / CLS / TTFB / FCP
- Beacon
- CIDR / Header（仅高级设置或帮助说明）

示例：

```text
页面加载体验（RUM）
主要内容显示速度（LCP）
页面操作响应速度（INP）
页面稳定性（CLS）
首字节响应时间（TTFB）
首屏内容出现时间（FCP）
```

## 五、统计学术语

`P50 / P75 / P95` 默认不得直接作为普通站长主界面标题或表格列名。

主界面应优先给出可理解结果，例如：

```text
大多数页面响应约 320～430ms
较慢的少数请求约 700ms
超过 1 秒的请求 0 次
```

如确实需要保留 P50/P75/P95，只允许出现在帮助说明、高级详情或悬浮解释中，并说明含义。

## 六、推荐映射

| 内部/技术词 | 普通用户界面建议 |
|---|---|
| DurationMs | 服务器响应耗时 |
| Path | 页面路径 |
| Referer | 来源地址 |
| Browser | 浏览器 |
| Device | 设备类型 |
| Campaign | 推广活动 |
| RUM | 页面加载体验 |
| LCP | 主要内容显示速度 |
| INP | 页面操作响应速度 |
| CLS | 页面稳定性 |
| TTFB | 首字节响应时间 |
| FCP | 首屏内容出现时间 |
| 下钻 | 查看详情 / 查看访问记录 / 查看来源 |
| Keyset/cursor/OFFSET | 不向普通用户展示 |
| migration/backfill | 数据升级 / 补全历史统计（仅维护页需要时） |
| desktop | 桌面设备 |
| mobile | 手机 |
| tablet | 平板 |
| direct | 直接访问 |
| search | 搜索引擎 |
| social | 社交媒体 |
| external | 外部网站 |
| internal | 站内访问 |

## 七、自动扫描机制

每个带 UI 的插件应提供：

```text
tools/check-ui-terminology.php
config/ui-terminology.json   （可选，项目需要扩展时）
```

扫描重点是“用户可见字符串”，不是粗暴扫描整个源码。

至少覆盖：

- PHP 模板中的 HTML 文本；
- PHP 输出到 UI 的固定字符串；
- JS 中写入 DOM 的固定文案；
- HTML 模板；
- 用户可见 CSV 表头（项目若把 CSV 视为用户产品界面）。

默认排除：

- vendor / node_modules；
- 测试代码；
- migrations；
- 数据库字段定义；
- API schema；
- 技术文档；
- 日志文本。

若某个术语确实需要在高级帮助中保留，必须使用项目约定的显式 allow 机制并说明原因，禁止靠扩大全局忽略范围绕过门禁。

## 八、CI 门禁

推荐工作流步骤：

```yaml
- name: UI Terminology Gate
  run: php tools/check-ui-terminology.php
```

失败示例：

```text
UI Terminology Gate: BLOCKED
main.php:412 发现用户可见术语 "DurationMs"
main.php:587 发现用户可见术语 "游标分页"
```

CI 必须返回非 0。

## 九、真人审查仍然必须存在

自动扫描只能拦截已知术语，不能替代 UI Product Gate。

T5 仍必须由以下三种视角逐页实机复核：

- 产品经理；
- 前端/交互；
- 普通 Z-Blog 站长。

自动扫描 PASS + 实机 UI PASS 才能判定 UI 相关门禁通过。

## 十、完成判定

正式发布前必须明确：

```text
Functional Product Gate   PASS / BLOCKED
UI Product Gate           PASS / BLOCKED
UI Terminology Gate       PASS / BLOCKED
```

UI Terminology Gate PASS 至少需要：

1. 自动扫描真实运行；
2. 扫描范围覆盖正式用户界面；
3. 无未解释的 blocking term；
4. CI 中同一检查 PASS；
5. T5 人工/实机复核未发现同类遗漏。

没有真实扫描输出或 CI Evidence，不得写 PASS。
