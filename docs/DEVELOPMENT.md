# v0.3 开发与更新

Godot 4.5.1 Standard / Compatibility。直接导入 project.godot，无插件。源码目标仍为中文离线单机。

## 文件职责

| 文件 | 职责 |
|---|---|
| data/tickets.json | 稳定 ID、规则 ID、面额、奖档、基础概率、每张骷髅率、解锁门槛、视觉主题 |
| data/progression.json | 境界、技能、活动、资产、天赋、费用和效率曲线 |
| core/ticket_rules.gd | 原三种规则，旧版规则的只读迁移兼容，分派数学规则 |
| core/mystic_rules.gd | 五种数学票的生成、精确整数求值、组合计数、图遍历 |
| core/economy.gd | 注入 RNG 的奖级选择，按实际 board 计算奖金 |
| core/game_state.gd | 所有经济事务、境界、风险、自动化、轮回与元进度 |
| core/save_store.gd | schema 验证、v1/v2→v3 迁移、原子存档与有效备份 |
| ui/scratch_card.gd | 银层空间覆盖、八种票面图形和计算反馈 |
| ui/main.gd | 操作路由、模态界面、天赋树、动画、运行验收入口 |
| tests/*.gd | 事务回归、规则生成校验、多轮完整生涯模拟 |

## 扩展规则

1. 新票使用新稳定 ID；不按显示名称保存，不重排既有 ID 的语义。
2. 实现 `make_board(catalog, grade, rng)`，负 grade 是未中奖，0–5 是目标奖档。
3. 实现纯 `evaluate(board) -> {units, hits, detail}`。最终奖金只能从票面符号重算，不能信任缓存 payout。
4. 在 `SaveStore.board_valid` 注册严格形状和数字范围，在 `ScratchCard` 注册布局。检查暗牌图形不能提前泄漏未揭示数值。
5. 为每档和空奖做生成测试、JSON 往返测试，以及独立手工例子；不要只比较生成器与自身拷贝。

数学票不执行动态表达式。积分只处理分段常数矩形；极限用正整数系数和 1–3 次幂做符号判断；路径枚举合法八步路径；阵法用双向连接 BFS；组合票用倒序子集和 DP。C(6,3)=20 等测试用独立已知结果检验。

## 事务约束

- Gameplay RNG 只能由核心使用；像素、粒子、合成音效使用独立 RNG。
- 购票时确定 board、所有购票加成、skull_index、risk_chance 和 RNG 后续状态，并立即保存。
- 精神没有被动恢复；asset/breakthrough 只增上限，不填充精神。
- 第一处银层损坏即标记 started，之后不允许望气、改命、倍化、替劫。
- 骷髅是每张最多一个的附加图案，字段与 board 分离；改命不能重抽。揭示一次只计一次。
- 达到 skull_limit，先结束本世，致命票不支付，余格不再响应，自动化关闭。
- 结算道行只在 `_end_run` 中执行，先设置 run_over 并保存奖励，之后才发 UI 信号。
- 元进度只可在 run_over 时购买；`begin_next_run` 清理 run 字段并保留 talents/meta_points/meta_total/run_number。
- `reset` 是全档清空，必须保留 UI 的二次确认；普通轮回不要调用它。
- 自动化沿用普通事务；已付代刮费的 pending ticket 在读档后不能再次收费；菜单、动画暂停；每帧最多揭一格，不补离线收益。

## 存档 schema 3

延用系统目录 `福运人生/progress.json`（不因界面标题改名迁走）。Windows 通常位于 `%APPDATA%/Godot/app_userdata/福运人生/`。写 `.tmp`，flush 后 rename；旧主文件有效才替换 `.bak`。加载时先验证主档，失败读有效备份。游戏过程中自动保存，关闭/失焦时也保存。导出包不会包含个人存档。

新增 run 字段：realm、skulls、wards_used、debt_stage、run_over、rest_cooldown。新增永久字段：talents、meta_points、meta_total、run_number、last_run。当前票新增 skull_index（-1 无图案）、skull_seen、skull_blocked、risk_chance、forfeited（致命作废，允许全揭示但未兑奖）。last_run 保存一次性结算报告和当时的容错上限。

v0.1 旧索引映射、legacy 金额票兼容保留。v0.2 的 collect/lines/sum/pairs/vault 仍能读、画、兑，不会换成新规则；旧票不追加骷髅。按历史 earned/scratched/owned 推导已达境界，免补交突破费；旧已解锁票种写入 unlocked_ids，保留解锁。已完成旧版的存档保持通关，进入轮回界面；本次迁移不重复赠送结算道行。普通旧存档从当前财富继续新剧情，债契未偿。

旧版已购票只允许原有的倍化与望气，不允许新规则改命重造。未来删票请保留兼容 evaluator 或增加显式迁移，不能仅移除目录条目。

## 调数值与发布

编辑 JSON 后更新对应说明/摘要，尤其天赋 per_level 与中文说明要一致。运行：

```bash
godot --headless --path . --editor --import
godot --headless --path . --script tests/run_tests.gd -- --test
godot --headless --path . --script tests/simulate.gd -- --test
# 图形环境（包括 Linux Xvfb 软件渲染）
godot --path . -- --smoke
mkdir -p builds/windows builds/linux builds/web
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Linux"
```

100 种子模拟自动写 docs/balance-report.json；`--seeds=5` 用于快速排查，不更新正式报告。模拟是积极购买升级、恢复精神、使用技能和防御天赋的固定策略，不等同真人体验，也不证明每一种玩法都能在三轮通关。

Windows 导出嵌入 PCK，需与 `licenses/`、字体 OFL、THIRD_PARTY_LICENSES.md 一同压缩。不要提交 .godot、builds 或个人存档。自动化导出工作流已更新 v0.3 命名，远端是否执行须另查，不能把工作流文件存在当成 CI 通过。
