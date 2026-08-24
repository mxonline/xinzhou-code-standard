# Z-Blog 插件发布文档规范 v1.0

本规范属于《Z-Blog 插件完整开发流程 v2.0》的正式发布门槛。插件只有在发布文档与真实代码状态一致时，才允许进入 Tag / GitHub Release。

## 1. 必备发布文档

每个正式版本默认检查并维护以下文档：

- `plugin.xml`：插件 ID、名称、版本号、兼容 PHP/Z-Blog 信息、发布日期等插件元信息。
- `README.md`：当前正式版本、功能概览、安装方式、后台入口、使用说明、注意事项与文档索引。
- `docs/CHANGELOG.md`：按版本记录新增、优化、修复、兼容性变化和测试结论。
- `docs/VERSION.md`：当前版本状态、版本路线、已发布版本与下一版本方向。
- `docs/RELEASE_NOTES_vX.Y.Z.md`：本次正式版本发布说明。

如果仓库目录结构不同，可使用等价文件，但必须保证上述信息完整且可追溯。

## 2. Release Notes 最低内容

`docs/RELEASE_NOTES_vX.Y.Z.md` 至少包括：

- 版本号与发布日期
- 本版定位
- 新增功能
- 重要优化
- Bug 修复
- 数据库 / Hook / 配置变化
- 向后兼容说明
- 升级注意事项
- 已知限制
- 测试与 CI 结论
- 安装包文件名
- 对应 Tag / GitHub Release

没有真实执行证据的测试不得写成“已通过”。

## 3. 条件性文档

以下情况自动增加对应说明：

- 数据库结构或迁移发生变化：增加升级 / 迁移说明，可使用 `docs/UPGRADE_vX.Y.Z.md`。
- 存在不兼容变化：必须增加 Breaking Changes 与回退方案。
- 新增复杂配置项：README 或独立配置文档中增加配置说明与默认值。
- 安装 / 卸载行为变化：说明数据保留、删除策略与风险。
- 安全修复：说明影响范围和升级建议，但不得泄露可直接利用的攻击细节。

## 4. 发布文档一致性检查

发布 Dry Run 必须核对：

- `plugin.xml`、README、VERSION、CHANGELOG、Release Notes 的版本号一致。
- 发布日期一致或符合仓库约定。
- README 所称“当前正式版”与实际 Tag / Release 状态一致。
- CHANGELOG 中本版本状态与实际发布状态一致。
- Release Notes 中列出的功能与真实 Diff / PR 一致。
- 数据库、Hook、配置变化已写明。
- 升级要求、兼容范围和已知限制没有遗漏。
- 安装包名称与版本一致。

任一关键版本信息冲突，Dry Run 直接判定为“不可发布”。

## 5. GitHub Release 文案

GitHub Release 默认使用 Release Notes 的精简版，至少包含：

- 版本主题
- 主要新增 / 优化 / 修复
- 升级注意事项
- 兼容性说明
- ZIP 安装包
- CHANGELOG / 完整 Release Notes 链接

禁止只写“update”“fix bugs”等无法说明版本价值的空泛文案。

## 6. 发布后的文档回写

GitHub Release 真正创建成功后，自动回写：

- README：当前正式版本
- VERSION：版本状态改为已发布
- CHANGELOG：本版本状态改为正式发布
- Release Notes：补充最终 Tag / Release / 包名
- Notion：记录版本号、Tag、Release、Commit、CI、发布日期和发布包状态

如果 Release 未真正创建，以上状态不得写成“已发布”。

## 7. 正式发布闭环

```text
代码与测试完成
→ 更新发布文档
→ 文档一致性检查
→ 发布 Dry Run
→ 合并主分支
→ 创建 Tag
→ 创建 GitHub Release
→ 附加正式 ZIP
→ 回写 README / VERSION / CHANGELOG / Release Notes
→ 同步 Notion
→ 标记已发布
```

本规范不包含上传 Z-Blog 应用中心；除非用户另行明确要求，否则“正式发布”默认指 GitHub Release + 正式 ZIP 包 + 发布文档同步。
