# v0.3 资料与改编说明

核对日期：2026-10-16。以下均为开发者、发行彩票机构、作者论文或大学课程来源。只借鉴抽象机制，票面、图形、程序和文案由本项目重新制作，没有复制其美术或长段文字。

## 彩票和增量循环

- **Scritchy Scratchy，开发者 Steam 商店页**：https://store.steampowered.com/app/3948120/Scritchy_Scratchy/ 。官方介绍独立规则票种、自动刮票、提高概率/奖金、风险与 Prestige。用于核对“票种差异—自动化—永久升级”的方向，本作增加了境界、精神活动与债契。
- **California Lottery，Mystery Crossword (1743)**：https://www.calottery.com/en/scratchers/$10/mystery-crossword-1743 。核对以隐藏字母、多个谜题和倍率框组成的兑奖结构。得到的设计启发是“揭示的是规则输入，奖项由完整结构决定”，不把每个刮区直接当一笔钱；新阵法采用完整连通结构兑奖，不是复刻该票。
- **Massachusetts Lottery，Power Play Cashword (2023)**：https://www.masslottery.com/games/power-play-cashword-2023 。核对字母区与词谜区的匹配方式，作为可见规则输入与奖表分离的参考。网页正文抓取有限，因此未借此宣称具体赔率或复制票面。

## 数学论文

1. Rui Duarte、António Guedes de Oliveira，**Generating functions of lattice paths**，2024，https://arxiv.org/pdf/2401.07840 。阅读第 1 节的上下步路径、生成函数乘积与系数卷积，以及后续路径分类。本作把“不越界并归位”做成踏云问道，把乘积中目标幂的系数做成万象衍天；使用的是简化后的有限模型，不实现论文的全部 Riordan 数组理论。
2. Jong Hyun Kim，**Redundant generating functions in lattice path enumeration**，2012 修订版，https://arxiv.org/html/1107.3870v2 。阅读 ballot 问题的边界条件与路径递推。本作采用显式边界检查：路径最后回到原点也不能抵消中途跌入地面的失败。原文部分路径使用不同坐标方向，本作以高度不小于零表达等价的直观约束。
3. Theo van Uem，**Stopping strategies and gambler's ruin problem**，2013，https://arxiv.org/pdf/1302.7247 。阅读导言的吸收边界、停止策略与到达边界概念，帮助区分“继续收益”与“本世终止”。本作骷髅是逐票 Bernoulli 风险与计数阈值，**不是**该论文的同一随机过程；概率曲线来自本作实际事务模拟，没有宣称论文能证明游戏好玩或通关率。

## 微积分参考与游戏规则

MIT OCW **18.01SC: The Definite Integral and its Applications**：https://ocw.mit.edu/courses/18-01sc-single-variable-calculus-fall-2010/pages/unit-3-the-definite-integral-and-its-applications/ 。参考有符号定积分的几何解释。丹炉积灵使用分段常数 f(x)，每格显示宽 w 与高 h，净面积是 Σw·h；负值扣除。

两仪归一使用 `(a n^p + 1)/(b n^q + 1)`，a、b 正整数且 p、q ≥1。n→∞ 时，p<q 得 0，p=q 得 a/b，p>q 发散。游戏选择让 0 和发散均空奖，只对有限指定极限兑奖；“发散过载”是本项目的虚构规则，不是数学上的负面价值判断。

## 实际组合

| 新票 | 可验证机制 | 与其他票的区别 |
|---|---|---|
| 丹炉积灵 | 有符号面积求和 | 有正负贡献和面积图，不寻找相同数字 |
| 踏云问道 | 边界合法性 + 路径面积 | 先验证整条路径，面积高但越界仍失败 |
| 两仪归一 | 次数比较 + 有限比值 | 数字很大也可能趋零或发散，系统显示符号结论 |
| 周天剑阵 | 双向邻接图可达性 | 空间连接决定阵眼能否通电，可同时兑多个出口 |
| 万象衍天 | ∏(1+x^a) 的目标系数 | 六枚可选灵石的 64 种子集选择，数量越多档次越高 |

程序生成目标奖档后构造合法票面，但结算必须重新评估实际图案；保存 JSON 再加载也不能改变结果。规则测试包含每种七类结果（空奖及六档）、有符号抵消、路径中途越界、C(6,3)、断路以及同阶/低阶/高阶极限的独立例子。玩家无需输入数学答案。
