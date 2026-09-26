# ConEmu 上游 ANSI 转义相关缺陷清单（仅 open issue，已排除 GUI 设置类）

供 `src\c\conemu\`（把 ConEmu 的解析/宽度/颜色栅格模型改造成 JNI 给 dbcli 调用）参考。
每一条都是**上游至今仍未关闭**的 issue，也就是说：**这些行为缺陷不会被 ConEmu 自己修**（repo 最后一次 push 是 2025-04-07，
最新发行版仍是 23.07.24）。我们要么照抄它现有的错误行为以换取和真实 ConEmu 一致，要么自己修对——
所以下面每条都给了「处置」建议。

## 0 抓取口径与已知限制

| 项 | 值 |
|---|---|
| 数据源 | `https://github.com/ConEmu/ConEmu`（`api.github.com/repos/ConEmu/ConEmu/issues`） |
| 快照时间 | 2026-09-22 |
| open issue 总数 | 1061（`is:issue is:open`，已剔除 PR） |
| 上游标签分布 | `ansi` 35 · `drawing` 32 · `drawing-cjk` 11 · `input-selection` 18 |
| 本文入选 | 正文详列 **76 条**（正文 183 条候选 + `ansi` 标签全量交叉核对），§9 另列被排除的 44 条编号 |
| 明确排除 | Settings GUI/配色面板/字体面板/tab 与任务栏外观/透明度/installer/翻译/图标（见 §9） |
| 原始数据 | `D:\dbcli\cache\conemu-ansi\raw\`（`open_*.json`、`cmt_*.json`）；脚本 `dump_open.py` `q.py` `cmt.py` |
| 自检 | `cache\conemu-ansi\verify.py` 把文中全部 **120 个引用编号**回查了快照：全部确为 open、无 PR、无杜撰编号 |

**限制（必须说明，别当成已核实）**：GitHub 未认证 API 每小时 60 次已用尽，所以只有 **6 条讨论串读到了评论**
（#407、#2404、#739、#1330、#1501，以及 #1873 的前几条）；其余条目**只读了 issue 正文**。
正文足够判断症状和复现步骤，但「维护者怎么定性」「后来是否悄悄修了」这类信息缺失——
§2–§7 里凡是没标 `[评论]` 的判断，都是从正文推出的，标 ⭘ 的条目建议主任务在需要时单独复取评论（每条 1 次调用，
`python cache\conemu-ansi\cmt.py <编号>` 会自动缓存）。

另一个坑：**open ≠ 未修复**。#2404、#1501 的评论里报告者已确认修复（且给出了修复 build 号），
但 issue 一直没关闭；#739 上游的态度是"有选项可用"。反过来，正文写着"latest build 仍有"的，
也可能只针对报告者当时那个 build。本文对这类情况都写明了出处。

## 1 结论速览：最值得主任务立刻关注的 8 条

| # | 一句话症状 | 处置 | 为什么重要 |
|---|---|---|---|
| [#2404](https://github.com/ConEmu/ConEmu/issues/2404) | 写满一行后**再写 1 个字符**不换行，字符回写在行尾 | 【修】 | 上游唯一一条有源码级根因的定位：延迟换行(deferred wrap)状态在"只写 1 个字符"时判错 |
| [#2636](https://github.com/ConEmu/ConEmu/issues/2636) | Python 打印长 CJK 串，结尾 `End` 回到行首覆盖 | 【修】 | 2026-03 新报，23.07.24 仍复现；CMD 和 Node 同窗口都正常 ⇒ 宽度×换行交叉缺陷 |
| [#1330](https://github.com/ConEmu/ConEmu/issues/1330) | `➜` 光标走 2 格、字形只画约 1.2 格 | 【修】 | 栅格模型的 cell 数与 paint 的字形 advance **不一致**——正是"解析宽度≠绘制宽度"这一类缺陷 |
| [#852](https://github.com/ConEmu/ConEmu/issues/852) | 游标处是全角时，一次退格**吃掉 2 个字符**，能删穿提示符 | 【修】 | 推断：把"格"数当成了"字符"数；和我们已处理的 U+FFFF 退格缺陷同源 |
| [#1900](https://github.com/ConEmu/ConEmu/issues/1900) | vim `term=xterm` 下退格插入 `Îx` | 【修】 | DEL(0x7F) 被当成可打印字符编码出去了 |
| [#2246](https://github.com/ConEmu/ConEmu/issues/2246) | 进程在 xterm mode 下被终止后，`CSI ? 1 h` 永久失效 | 【修】 | 模式位状态**跨进程残留**，且有 C 语言独立复现程序 |
| [#227](https://github.com/ConEmu/ConEmu/issues/227) | 256/24-bit 颜色只在"底部区域"有效，视图变化后着色错乱 | 【复刻或修，要先定】 | 涉及"属性要不要跟着进 scrollback"，决定我们的 cell 布局 |
| [#687](https://github.com/ConEmu/ConEmu/issues/687) | `ESC ] 9 ; 7 ; prog ST` 可以**从输出里启动程序** | 【安全：默认关】 | 我们若实现 ConEmu 私有 OSC，必须默认禁用 + 显式开关，否则任何外部输出都是 RCE |

## 2 A 组：右缘换行 / 延迟换行（deferred wrap）

这一组是 ConEmu 缺陷密度最高、也最贴近我们要重写的东西。核心机制是：ConEmu（通过 ConEmuHk）**总是关掉**
`ENABLE_WRAP_AT_EOL_OUTPUT`，自己在"游标到达右缘"时决定要不要折行——于是这个自制的延迟换行状态机就成了缺陷温床。

**#2404 Pasting long lines does not wrap the text correctly**（2021-12-10，28 评论，标签 other-cmder/other-clink）
`[评论]` Clink 作者 chrisant996 做了完整定位，是本文里唯一一条给出源码行的：

- 现象：粘贴/打印到行尾时，**只写 1 个字符**的情形下 ConEmu 不折行，游标停住并把字符覆盖在最后一格。
- 触发条件（他逐条验证过）：① 必须开着 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`；② 必须让 ConEmu 把该进程**当作 shell** 来跑；
  ③ Win11 才稳定复现——他认为是 microsoft/terminal#3943 改了 conhost 行为，**暴露了 ConEmu 里原有的潜在缺陷**，不是新 bug。
- 定位：`src/ConEmuHk/ExtConsole.cpp:1104` 的 `ExtWriteText()` 关掉自动换行，随后另一处 `ExtWriteText()` 决定不折行；
  "游标到右缘就把游标回退一格"的逻辑，在**折行被推迟之后只写了 1 个字符**时不成立。
- 过程：维护者先判"是 Clink 的问题""是 conhost 的问题"，chrisant996 两次给出独立复现程序（`github.com/chrisant996/conemu2404`、
  `ReproConEmu2404.zip`）并明确"这不是 OS bug"；最终在 **build 220308** 修、**220418** 重做（"Fix was reworked"），
  两位报告者回帖确认可用。**issue 至今仍是 open。**

> 对我们的动作：把"到右缘后下一个字符"做成显式状态（pending-wrap flag），并且**单独测一次"只写 1 个字符"这条路径**。
> 这类"批量写对了、单字符写错了"的分支，是栅格解析器最典型的漏检点。

**#407 Line wraps onto same line**（2015-11-03，32 评论）`[评论]` 症状同上（换行折回同一行覆盖）。
讨论串里有价值的两点：① 维护者的第一反应是"应用只写了 `\r`"——**判据**：先确认不是应用侧把不可见字符算进了行长；
② 多条 WSL/zsh 报告最后是被 PS1 里非打印序列**没有用 `\[` `\]` 包起来**解释掉的（readline 自己算错列），
③ 也有人改成多行提示符就不复现。→ 结论：**同一症状有"终端错"和"应用算错"两个来源**，回归脚本要用我们自己可控的输出
（例如定长 ASCII + 定长 CJK）来判定，不要拿 shell 提示符当神谕。

其余同族（⭘ 未读评论，仅正文）：
#1873 Backspace moves cursor to new line（2019-03-21，40 评论，标签 `ansi`：长行上退格→游标跑到新行）、
#1535 Cygwin zsh w/ Connector wraps lines above（2018-04-28：打字到换行时**往上折**，输入内容被吃掉）、
#2149 Wrong right prompt position with powerlevel10k（2020-07-08：右提示符跨了两行）、
#317 "Change prompt text cursor" fails on long lines with Clink（2015-09-12：**软换行**产生的"行"和栅格行不是一回事，
点击只能命中最后一行 → 我们若要做选择/点击映射，必须能区分硬换行与软换行）、
#2116 Incorect output of gradle wrapper（2020-05-23，标签 `ansi`：`TERM=xterm-256color` 下 CR 处理不对，输出覆盖上面的行）。

> **本轮处置（2026-09-23，栅格证人）**：本组"改成 pending wrap"的动作**不做**。`MSFT_TERMINAL_REFERENCE` §2.2
> 那四条能区分立即/延迟换行的输入（满行后 `\r`+`Y`、`\b`+`Y`、`\e[K`、`\e[A`+`Y`）已建进
> `Render.java:1577-1580`，200 列缓冲区上**四条 legs 全部相同** ⇒ 与兜底腿本就一致，改成延迟只会造出新分叉。
> #317 那条"软换行 ≠ 栅格行"是**真需求**，但它的正确解不是换行时机，而是**每行一个位记下这行是被迫断的**：
> 已按上游 `_wrapForced`/`_doubleBytePadded` 做成 `rowWrap[]`（DESIGN I20），做选择/复制映射时直接读它。

## 3 B 组：宽字符、单元格宽度与复制

这一组和 `src\c\luauf8\ansi_width.c`（本项目的宽度神谕）、`Paint.cpp` 直接相关。

**#1330 Some character width not showing correctly**（2017-11-23，14 评论）`[评论]` `➜`(U+279C) 这类字符
"游标移动 2 格、文本只移动约 1.2 格"。报告者的判据非常干净：*"要么画和游标都按 1 格，要么都按 2 格"*。
维护者回复"字体画多宽你能怎样"——**这正是缺陷本身**：栅格按一个宽度表分配格子，绘制按字体 advance 摆放，
两者没有强制对齐。191012 build 仍复现（另一位 2020 年回帖）。后续又有人用 tmux 分屏放大该现象。

**#739 Not-locale characters clamping together**（2016-06-17，36 评论，标签 `drawing-cjk`）`[评论]`
本组信息量最大的一条：CJK 互相叠压/挤在一起。讨论串把 Windows 侧的两种"双宽实现"讲清了：

- DBCS 版 Windows + 双字节代码页（932 等）时，conhost 的内部缓冲里一个 CJK **物理占两格**，
  用 `CHAR_INFO` 的 `COMMON_LVB_LEADING_BYTE` / `COMMON_LVB_TRAILING_BYTE` 标记前后格；
- 非 DBCS 系统（ACP 1251 / OEMCP 866）没有这套前提，于是同一份输出表现不同；
- 维护者的立场：老版本（141221）是**裁掉超出格子的字形**，新版本改成"压缩长串以适应空间"
  （"Compress long strings to fit space"选项），并认为新版更好。报告者强烈反对（可读性更差），最终停在"各用各的"。

> 对我们的动作：明确我们的模型是"1 字位 = N 格 + 尾格标记"，并保证**绘制永远不越格**（越格就是 739/1330 的成因）。
> 另外这条提醒我们：宽度行为**依赖代码页/系统 locale** 的 ConEmu，在别的机器上表现不同——
> 我们的判定应当只依赖 `ansi_width_tables.h`，不读系统 locale。

**#2128 4 bytes unicode char are not handled properly**（2020-06-12，6 评论，标签 `drawing-cjk`）
辅助平面字符不仅显示不对，**从屏幕复制时剪贴板里是坏数据**；而"真实控制台"里虽然也显示不对，**复制却是对的**。
→ 结论：ConEmu 的栅格缓冲存不下（或存错）代理对，复制路径读的是缓冲而不是原始码点。
我们做 cell 存储时必须能存完整码点，且**复制/选择要还原成原码点**，不是还原成字形。

**#2158 Control characters (\x01 .. \x1F) are changed**（2020-07-21，11 评论，标签 drawing/input-selection）
`echo -e a\001b` 显示成 `a☺b`，**复制出来变成 U+263A**（而不是原始的 0x01）。
→ 控制字符被"渲染成字形"并写进了缓冲，污染了复制链路。我们的模型里控制字符应显式决定"占格且不伪造成可打印字符"。

同族（⭘ 仅正文）：
#2408 Cursor position bug when using double width character with WSL（2021-12-22：`あ` 后打字再退格，游标位置彻底错乱；
cmd/PowerShell + ConEmu 不复现，只在 WSL 下出现）；
#852 Backspace deletes more space than it should be on WSL-bash, CJK Full-width characters（2016-09-04：
游标处是全角时**一次删 2 个字符**，连续全角会连锁删穿提示符；附加到 cmd.exe 上不复现）；
#458 wrong cursor moving in vim for chinese（2015-12-08：vim 里 CJK 只走 1 格，真实控制台走 2 格）；
#447 incorrect block mode selection for cjk single+full mixed-width text（2015-11-30：混合宽度下块选择错位）；
#2458 trouble with "Fullwidth-aware rendering" option in FAR（2022-07-12，`drawing-cjk`：**开了全角感知反而字符翻倍**）；
#1501 Powerline prompt has extra space between prompt and cursor（2018-04-03，15 评论，`drawing-cjk`）`[评论]`
定位到回归区间是 build 170402 → 170517，维护者要求跑 `ConEmuC -CheckUnicode` 比对，最后发 `ConEmuCD.gh1501` 补丁，
报告者确认"looks good"（**已修但 issue 仍 open**）——`-CheckUnicode` 这个自带诊断工具值得抄（见 §8 第 11 条）；
#1555 powerline symbols of vim-airline 位置/颜色不对（2018-05-13，`drawing-cjk`+`other-wsl`）；
#2184 Powerline glyph not rendering correctly（2020-10-07：PUA 的 U+E0B2/U+E0B0 画错）；
#1613 Weird output of Chinese characters（2018-06-21：170910 → 180528 的回归）；
#813 chinese word repeat in bash on windows（2016-08-04：bash 里中文重复显示，cmd 不会）；
#808 ANSI characters used in building text tables are not displayed properly（2016-08-02，`drawing-cjk`：
制表符画不全，最右侧竖线丢失）；
#1674 Some glyphs are missed after ConEmu rendered the console（2018-08-07：字形"闪一下又没了"，
改字体/粘贴时会短暂出现 → 每格的 fallback 状态没稳定）；
#2525 Some emoji don't displayed（2023-04-04：U+1F40D 蛇形 emoji 打不出来，自带 `utf-8-test.cmd` 也不全）；
#1036 Проблемы с отображением символов（2017-02-08：切代码页后行尾颜色变黑、菜单左边界破损——**颜色与宽度串扰**）；
#1741 24bit true color render problem with chinese characters in vim（2018-10-26，10 评论：
**行里有中文时颜色就崩**——宽度缺陷与 SGR 属性耦合的典型样本，同时归在 §4）。

### 3.1 本轮量测结论：#852 那一族**在我们这里是兜底腿错**（2026-09-23，栅格证人）

判据不是推理，是同一段字节走两条腿以后 `ReadConsoleOutputW` 逐格对比（`src\c\conemu\Render.java` 的 `legs`）。

| 用例 | native（快路径） | hk（兜底腿 ConEmuHk） | 裁决 |
|---|---|---|---|
| `あa` + `\b` | 游标 (3,10)，行 `[3042L 3042T 005F]` | 游标 (2,14)，行 `[0020 005F 0061]` | **分叉，错在兜底腿**：Hk 把宽字形按 1 列计数 ⇒ BS 少退一格 ⇒ 下一次写落在尾格上，conhost 清掉前导格。这正是 #852 的形状，也正是本组上面那一串 issue 的根因家族 |
| `あa` + `\b\b` | (1,10) | (1,14) | **agree** ⇒ 分叉只在"一步且踩进尾格"这一格上，不是两条腿的宽度表不同 |

⇒ 模型的 `step_back_col`（`Render.cpp:1106`，落在 `TRAILING` 再退一步，照上游 `Row::_adjustBackward`）
是**对的那一侧**，不为平价而把它改回少退一格。门禁 `Render.java:caseAbWidechar` 族的
`legs("narrow after wide, then BS", ..., Boolean.FALSE)`——期望"不同"与期望"相同"一样是断言，
谁将来把它改成 agree，就是在把 #852 抄回来（DESIGN §4.2 第 1 条）。

顺带两条同族的量测否证，别再去重走：
**辅助平面**（😀）两腿都丢字，只有码元不同（native `[D83DL D83DT]` vs hk `[FFFDL FFFDT]`），根因是 conhost
对每个 2 列字形把前导 WCHAR 重复写进尾格——遗留 16 位格装不下 astral 码点（`MSFT_TERMINAL_REFERENCE` §5，
上游为此动过 `ReadConsoleOutput`：`8a26f141`/#13321）。⇒ 与 #2525"emoji 打不出来"同源，属**读回契约**而非我们的存储缺陷。
**延迟换行**（本组 #2404/#2636/#407/#1873/#2116 那一族）四条判别式全部 legs agree ⇒ 不实现，见 §2 末与 DESIGN §4.2。

## 4 C 组：SGR 颜色与字符属性

先记两条**上游行为事实**，因为它们决定"我们要不要跟随"：

1. ConEmu 的 256 色/真彩是**经过用户调色板折叠**的（本项目已有 `vendor\ConEmuColors3.h` + `ExtPrepareColor` 的
   fg==bg 避让实测）。→ #2516、#1380 都源于此。
2. 历史上 ConEmu 的 ANSI 属性只在"底部区域"生效（#227），且属性是否与 scrollback 一起保留是设计问题。

逐条：

| # | 症状（正文摘录） | 属性/序列 | 处置 |
|---|---|---|---|
| [1688](https://github.com/ConEmu/ConEmu/issues/1688) | `term=xterm`+`termguicolors`，`hi Normal guibg=#272822`，`echo 3` 后命令行背景画成了**色号 8（#7c7c7c）**。附了 AnsiLog gist | `SGR 48;2;r;g;b` | 【修】真彩背景被折回索引色；和我们的 rgbmap 生成直接相关 |
| [1768](https://github.com/ConEmu/ConEmu/issues/1768) | 16 色里**第 5 个（索引 4，蓝）永远是黑**，换配色方案也没用，cmd 和 wsl 都一样 | 16 色表映射 | 【修】索引表错一格 |
| [1950](https://github.com/ConEmu/ConEmu/issues/1950) | vim `ctermbg=black` 时背景变成 ConEmu 默认底色而不是黑；`ctermbg=white` 正常 | `SGR 40` / `48;5;0` | 【修】"索引 0 = 默认背景"这个捷径是常见错法 |
| [2516](https://github.com/ConEmu/ConEmu/issues/2516) | ls/ncdu/nano/vim 自带的颜色被"和 ConEmu 配色方案混合"，换方案时窗口里**应用的颜色跟着变** | 调色板折叠 | 【复刻】但必须文档化；这正是 `fg==bg` 避让那一族 |
| [1380](https://github.com/ConEmu/ConEmu/issues/1380) | 关掉 inject、xterm、true color 三个开关后**仍然是 xterm 256 色**；且追问"为什么 ConEmu 总把自己说成 xterm" | 能力开关与转义处理**没接上** | 【修】开关只影响注入 hook，不影响转义解释 ⇒ 开关与解析器状态要一份真相 |
| [2301](https://github.com/ConEmu/ConEmu/issues/2301) | pwsh 直接作为 task 时提示符前出现**莫名色块**；从 `{cmd}` task 里跑 pwsh 就正常；Windows Terminal/Fluent Terminal 都正常 | 同上（是否被当作 shell） | 【存疑】先加"同一份字节流经/不经 shell 通道"的 A/B 用例 |
| [1896](https://github.com/ConEmu/ConEmu/issues/1896) | `\e[1m` 只会变亮，不会加粗；希望可选择"粗体 vs 提亮" | `SGR 1` | 【复刻 + 提供开关】这是 xterm 家族的经典分歧（bold→bright） |
| [677](https://github.com/ConEmu/ConEmu/issues/677) | 不支持删除线 | `SGR 9` / `29` | 【缺口】`SetConsoleTextAttribute` 没有对应位，需自绘 |
| [856](https://github.com/ConEmu/ConEmu/issues/856) | git 2.10 的 `strike`/`italic` 颜色属性无效 | `SGR 9`/`3` | 【缺口】同上 |
| [484](https://github.com/ConEmu/ConEmu/issues/484) | 支持 `SGR 5`（闪烁）但**没有 `SGR 25`（关闪烁）**；且"背景/下划线"是同一个桩函数 | `SGR 5`/`25` | 【修】每个开启位都必须有对应的关闭位；"一函数两用"是明确的设计缺陷 |
| [227](https://github.com/ConEmu/ConEmu/issues/227) | 256/24-bit 颜色**只在底部区域可用**，视图变化后着色错乱（REPL 作者报告） | 属性与区域耦合 | 【先定方向】要不要让属性进 scrollback，决定 cell 布局；别默认照抄 |
| [1818](https://github.com/ConEmu/ConEmu/issues/1818) | 请支持 vim `term=win32` 下的真彩（说"原生支持能消掉 #1741 #1688 那堆 glitch"） | 能力声明 | 【参考】作者自己承认这些缺陷同源 |
| [2466](https://github.com/ConEmu/ConEmu/issues/2466) | bash+nvim 主题颜色错乱、背景发粉 | 组合症状 | 【低优先】证据弱（只有截图） |
| [870](https://github.com/ConEmu/ConEmu/issues/870) | Terraform 输出**整段不显示**（疑似 ANSI 颜色库触发） | 转义吞输出 | 【存疑】值得拿它的字节流当解析用例 |
| [807](https://github.com/ConEmu/ConEmu/issues/807) / [2625](https://github.com/ConEmu/ConEmu/issues/2625) | Sixel / kitty graphics 协议 | 图形协议 | 【缺口】明确不做也要写进文档 |
| （不是上游 issue：`SGR 38:2::r:g:b`） | colon 子参数**整条不吃色** | `SGR 38/48` 的 `:` 形式 | 【已定性偏离，不修】不是缺口：`:` 落在 ConEmu 的 Pvt 字节范围里，按 I10 的平价规则"私有序列 ⇒ 丢弃"是**兜底腿的现有行为**（上游坐标 `Ansi.cpp:3494`；我们的判据在 `Render.cpp:1177`）。上游 Terminal 用 `_subParameterRanges` 正经解析它（`stateMachine.cpp:505-545`），那是**更对**的一侧，但它不对我们的平价对象。⇒ 唯一做的动作是"不再静默"：`RC_UN_COLON` 单独计一票（`Render.cpp:1177` 说、`:2624` 计），将来真有应用发 colon 形式时手里有数；且它**不**置 `modelSuspect`（不改格就不该逼模型重收养）。门禁 `Render.java caseSuspectAlign`：`"the colon form has its own counter"` + `"and buys no repaint"` |

## 5 D 组：模式位、光标与 xterm-mode 状态机

这一组是"解析器状态"而非"绘制"，但**状态跨进程/跨命令残留**是反复出现的模式，正好和我们的
SubProcess 生命周期（dbcli 会反复起 sqlplus/cmd 子进程）撞上。

**#2181 Application Cursor Keys (DECCKM) switching not supported**（2020-09-28，3 评论，标签 other-wsl/`ansi`）
`CSI ? 1 h` / `CSI ? 1 l` 完全没实现。复现程序干净到可以直接抄成用例：
`perl -e '<>; print "\e[?1h"; <>; print "\e[?1l"; <>'`，正确终端里第二行方向键回 `^[[O A/B/C/D`（SS3），
ConEmu 三行都回 `^[[A...`。

**#2246 Internal state is broken after terminating a process in xterm mode enabled**（2021-01-12，2 评论，标签 `ansi`）
⭘ 评论未读到，但正文极完整：附带一个 C 程序 `cechk.exe`，演示"进程在 xterm mode 下被终止后，
即使 `GetConsoleMode()` 报告仍是 xterm mode，`ESC[?1h` 也不再起作用"。cmd.exe 原生和 Windows Terminal 都不复现。
→ **状态位归属**：模式位是"控制台/会话"级还是"进程"级？进程退出时由谁恢复？这两问必须在我们这边定死。

**#2302 Terminal mode doesn't return to "Windows" after return to far**（2021-03-24，1 评论，标签 `ansi`）
在 Far 里跑一条 cygwin 命令 → 终端模式自动切到 XTerm（正确），命令结束回到 Far 后**不切回 Windows**，
于是 F1 发出 `ESC O P` 而不是 `P`。→ 自动识别 + 自动还原是一对，缺还原就出事。

**#1068 ConEmu leaves ConEmuANSI set to ON when a process spawns a child process in a new console**（2017-03-16，2 评论）
子进程进了新控制台、hook DLL 没注进去，但 `ConEmuANSI` 还是 `ON` ⇒ 应用以为能发转义，结果**屏幕上看到裸转义序列**。
→ 「能力声明」和「谁在解析」必须同源；我们的 JNI 侧要有一个明确的"是否解释 ANSI"开关，且随子进程变化。

**#1826 Colors not rendered properly with git-bash & msys2 connector**（2019-02-13，2 评论，标签 `ansi`）
同一症状的另一来源：任务配置不同 ⇒ **字面 ANSI 码被打印出来**。报告者最后靠显式塞进 ANSICON 绕过。
→ 对 dbcli：输出前先确定"这一路有人解析吗"，没有就自己裁掉/别生成。

**#2188 ANSI sequence for 'change text cursor shape' is not working**（2020-10-16，2 评论，标签 `ansi`）
`CSI 1..6 SP q`（DECSCUSR）不认；同一条报告里明确"清屏、游标显隐都正常"——**只有游标形状这一支没实现**。
**#1781**（2018-12-12，7 评论）问的是 ConEmu 自家私有序列 `\e[=1c`/`\e[=2c` 也不起作用。

**#2423 Setting console title using ANSI code does not work anymore**（2022-03-24，0 评论）
`echo -e '\033]2;whatever\007'` 曾经能改 tab 标题，**回归后失效**；把控制台 detach 出去就正常。
→ OSC 标题链路只在"被 ConEmu 托管"时坏，说明托管路径自己吞了 OSC。

**#2186 turn off bracketed paste mode permanently**（2020-10-13，11 评论，标签 other-vim）
ConEmu 自家的 BrPaste 关不干净：用户在设置里关掉后 **ConEmu 又把它打开**，于是 `^[[201~` 随机出现并把 vim 会话废掉
（报告者：粘贴后连 ctrl+z 都退出不了）。→ 任何"用户显式关掉的输入模式"都不能被我们自己重写回去。

**#2095 Postponed Script fail to interpret escape sequence correctly**（2020-04-12，1 评论，标签 guimacro/`type-bug`）
`ConEmuC64 /GUIMACRO Print("hello \\e tom")`：不推迟时正常，被推迟（`PostponedRCon`）后 `\e` 被吃掉，只剩 ` tom`。
→ **同一段文本走两条不同解析路径必须等价**——我们 Java/Lua/C 三侧交接时是同一类风险。

**#1900 Vim backspace in xterm**（2019-04-24，11 评论）：退格插入 `Îx`；
**#951 Backspace doesn't work in Perl debugger**（2016-11-11，2 评论）：退格打印 `♪` `◘` 之类控制字符图形；
**#1827 WSL shell starts with lots of backspace(?) `<-H` characters**（2019-02-13，7 评论，标签 `ansi`）：
一进 shell 就一堆 `<-H`（0x08 被当可打印字符画出来了）。这三条和 §3 的 #2158 一起构成
**"退格/控制字符"家族**——与本项目已修的 U+FFFF 退格缺陷是同一类问题：终端交付的码点 ≠ dbcli/ConEmu 认得的码点。
（`inoremap <Char-0x07F> <BS>` 这个 vim 侧 workaround 在 #1688、#1900 两个 issue 里都出现，可作为"0x7F 被当成 U+007F 可打印"的旁证。）

输入侧其余（⭘）：
#1092 方向键回 `^[OA`（SS3）而 bash 期望 `^[[A`（2017-04-05，4 评论）——和 #2181 是同一枚硬币的两面；
#1147 WSL tmux copy mode 下方向键随机吐出 `[A`（2017-05-21，8 评论）——**ESC 字节丢失**；
#1962 alt/shift+方向键约 40% 概率失败、吐出 `A`（2019-07-31，1 评论）——组合键转义序列被拆开；
#921 `Can't find termcap entry xterm-256color`（2016-10-20，2 评论，标签 other-cygwin/msys）——
ConEmu 声明自己是 xterm-256color，但 msys 侧没有对应 terminfo ⇒ **能力声明与环境供给不同源**。

## 6 E 组：OSC 扩展与未实现协议（含一条安全问题）

| # | 内容 | 处置 |
|---|---|---|
| [687](https://github.com/ConEmu/ConEmu/issues/687) | **RCE**：ConEmu 私有 OSC `ESC ] 9 ; 7 ; prog ST` 能执行外部程序；任何把不受信数据原样写进终端的应用都会中招。唯一缓解是关 inject | 【安全】若我们实现 ConEmu 私有 OSC，**默认禁用 + 显式开关 + 只允许白名单**；文档里写清楚 |
| [2078](https://github.com/ConEmu/ConEmu/issues/2078) | OSC 8 超链接（`\e]8;;URL\e\\text\e]8;;\e\\`）不支持 | 【缺口】注意 OSC 8 的 `ST` 有两种终止符（`\e\\` 与 `\a`） |
| [2624](https://github.com/ConEmu/ConEmu/issues/2624) / [2627](https://github.com/ConEmu/ConEmu/issues/2627) | OSC 52（远程剪贴板写入）不支持；far2l 团队要 | 【缺口】安全上同样要默认关 |
| [2628](https://github.com/ConEmu/ConEmu/issues/2628) | kitty keyboard protocol（只有链接，无正文） | 【缺口】 |
| [973](https://github.com/ConEmu/ConEmu/issues/973) | 请求一个"设置当前 tab 图标"的私有转义（标签 type-enhancement/`ansi`） | 【缺口】 |
| [2423](https://github.com/ConEmu/ConEmu/issues/2423) | OSC 2 标题**回归失效**（见 §5） | 【修】 |

> **本轮处置（2026-09-23）**：这一族**不再静默**——`OSC 0/1/2` 的标题真落地（`SetConsoleTitleW`），
> 其余每一族各计一票（私有 `9`、其它 OSC、DCS、未终止的标题、图标标题），
> 判据与门禁在 DESIGN I21。#687 的答复是**一句话**：这一族里我们永不执行任何东西——
> `9` 只有计数，`"\e]9;7;calc.exe\a"` 在门禁里被断言"计一票、不设标题、标题不变"。
> #2423 对我们不再成立：标题链路是渲染器自己 `SetConsoleTitleW`，不经 ConEmu 的托管路径，
> 所以"被 ConEmu 吞了"这个失效面不存在；读回用的是 `GetConsoleTitleW`（不是"发出去了"）。
> OSC 8 / 52 / kitty keyboard / #973 四条**仍是缺口**：本轮只保证"看见了并计下"，不保证实现了协议。
> 载荷超过 `RC_TITLE_MAX 256` 时**截断并计数**，不丢序列（门禁 `"with the model's own cap, not a dropped tail"`）。

## 7 F 组：tmux / ssh / connector 下的显示错乱群（同一根因家族，信息量较低但**用例价值高**）

这些 issue 大多没有分析，只有"某某程序在某某组合下花了"。它们的价值不在结论，
**在于给出可回放的真实字节流**（好几条附了 AnsiLog / 复现脚本）。按症状归类：

- **游标/行位置类**：#1960（Mosh+tmux 分屏，底部退格插入换行、整屏布局破）· #2110（ssh+tmux 底部状态栏位置错）
  · #2241（WSL tmux 竖分屏破）· #1511（emacs 里打字游标跑到错行、文字消失）· #1259（emacs 里 ctrl+f 游标经过的字符消失）
  · #1444（irssi in tmux，半页翻页时花了；25 评论，标签 `ansi`）
- **屏幕内容错乱/消失**：#2185（跑完 FZF 或 ssh 之后屏幕坏，接着 vim 游标也坏）· #1393（msys connector 下 git diff 乱）
  · #1557（CentOS nano 右方向键**删字**）· #1210（wsl 里 nano 编辑时文字跳行/消失，历史不见）· #2538（cygwin vim 起始屏 garbled + 插入更多控制字符，
  旧版 210816~221218 正常 ⇒ 明确回归）· #1861（升到 190310 后 vim 卡住）· #1853（WSL/ZSH 一堆显示问题）
  · #1649（Win32-OpenSSH 下 motd **重复输出**）· #1738（ssh 到 CentOS 的"合集式"抱怨，13 评论）
- **模式/退出/挂起**：#2042（cygwin 里退出 htop/nano/alsamixer 后控制台挂住）· #1646（connector + GNU screen）
  · #891（WSL 里 ANSI 序列；维护者"序列在 ConEmu 看到之前就被处理了"，报告者反编译 bash.exe 指出
  是 `ENABLE_VIRTUAL_TERMINAL_PROCESSING` 位，可以 hook `SetConsoleMode` 拿到 ⇒ **上游的"谁在解析"模型被质疑**）
  · #1955（Microsoft OpenSSH + `TERM=xterm` 时 glitch）· #2302（§5 已列）
- **性能类（不算 ANSI 缺陷但同源）**：#2138（WSL2 下 emacs/vi 起停明显慢；先在 cmd 里再起 bash 就正常）
  · #1240（`conemu-cyg-32.exe` 下 tty 检查失败 ⇒ 没颜色没进度）· #2232（connector 让状态栏显示的进程名变成自己）
  · #842（autosub 进度条不刷新，16 评论）· #1403（connector 下 unicode 输出**看不见**）

## 8 建议加进 `RenderCheck` 的回归用例（每条都对应上游一个真实缺陷）

以下都是**能在我们的栅格上断言**的判据，建议照现有 `RenderCheck.cpp` 的检查风格补进去：

> **2026-09-23 状态**：第 **1**（四条判别式在 `Render.java:1577-1580`，结论 legs agree ⇒ 见 §2 末"不做"）、
> 第 **2**（`geo_wrap` + 新的 `rowWrap` 位区分"整字提前折"与"被推断"，`gm_wrap_suspect`）、
> 第 **3**（`step_back_col` + §3.1 的双腿证人，含"期望不同"那条门禁）、
> 第 **7**（未知模式与 colon 分别计票、且不互相污染：`gm_wrap_suspect` + `caseSuspectAlign`）、
> 第 **10** 的**前置**（`rowWrap[]` 已存在，映射本身还没人读它）已处置。
> 第 4、5、6、8、9、11 本轮**未动**，仍是建议。
>
> **2026-09-26 追加（build -25，参照 commit history 反查，不是上游 issue）**：ECH 跨行擦、IL/DL 不回最左列、
> ICH/DCH/ECH/写入把宽字形切半格、DECSTR 走 full_reset、recycled 行漏清 `markCol`、`lastUnit` 记了零宽码点
> ——六条都已修，宿主门禁 `geo_lines`/`geo_edit`/`no_orphan`/`gm_state_reset`/`geo_ftcs`，真终端四腿
> `caseEditRows`/`caseEchClamp`/`caseHealPairs`/`caseSoftReset`（`Render.java`，两架构 `checks=5688 failures=0`）。
> 第 7 条 `\t` 的 tab stop 表**已批准、尚未做**（`ANSI_SUPPORTS.md` §3 那三行仍然成立）。
> 判据：这一族不是抄上游抄出来的错，是**没抄**参照的错——把 ConEmu 当神谕的那几年正好是这些错活着的几年
> （见 `DESIGN.md` §10 #64-#70 与 [[feedback-upstream-not-a-reason]]）。

1. **单字符触发的折行**（#2404）：填满一行 → 再单独写 1 个字符 → 断言游标到下一行行首、行尾字符未被覆盖。
   同时覆盖"批量写 2 个字符"与"写 1 个字符"两条分支（上游正是在后者上错）。
2. **全角触右缘**（#2636/#2408/#458）：一行末尾放一个双宽字符 → 断言它整体折到下一行（不许只占半格），
   且后续字符从下一行第 0 格开始。
3. **退格语义**（#852/#1900/#951/#1827/#2158）：`あ` + `\b` → 断言删掉 1 个字位（2 格）而不是 2 个字位；
   断言 0x08/0x7F/`\x01..\x1F` **永远不会变成可打印字形**出现在缓冲里。
4. **宽度一致性**（#1330/#739/#1501/#2184/#1674）：对同一串混合宽度文本，断言
   `Σ cell_width(cp) == 绘制占用的格数`，且每个字位的绘制不越出自己的格子（用 `ansi_width_tables.h` 做唯一神谕，不读 locale）。
5. **SGR 开/关成对**（#484）：每个有开启码的属性都要测对应关闭码（`5/25`、`9/29`、`1/22`、`4/24`、`7/27`、`39/49`、`0`）。
6. **真彩与索引不被折叠成同一个值**（#1688/#1950/#1768）：`48;2;39;40;34` 必须逐字节还原，
   不得退化为色号 8；`40`/`48;5;0` 必须是**真黑**而不是"默认背景"；16 色表逐格与 `gen_rgbmap.sh` 产物比对。
7. **模式位生命周期**（#2246/#2181/#2302/#2188）：`CSI ? 1 h` 生效与还原；子进程在 xterm mode 下退出后，
   下一个进程仍能用 `CSI ? 1 h`；`CSI 2 SP q` 之类的未知序列必须**被吃掉而不是漏成文字**。
8. **能力声明同源**（#1068/#1380/#1826/#2301）：同一段字节流走"解析开/解析关"两条路，
   断言"关"的时候不生成裸转义、"开"的时候行为与 shell 身份无关。
9. **属性进 scrollback**（#227）：先决定方向，再把决定写进注释与测试（当前上游是"底部区域"行为）。
10. **复制/选择还原**（#2128/#2158/#447/#317）：块选择跨混合宽度、跨软换行；复制结果按码点还原，辅助平面不成坏字符。
11. **诊断工具**：抄 ConEmu 的 `ConEmuC -CheckUnicode`（#1501 里靠它定位）做一个我们自己的
    "给定字符串 → 打印每字位的格宽与绘制宽度" 对照命令；两边不等就是 §3 那类缺陷的现成信号。

## 9 明确排除在外的（GUI/设置类，本次按要求不看）

`#2101`(focus lost 点击穿透) `#2519`(Skip Words 影响任务栏) `#2544`(终端模式热键) `#2370`(换行按钮)
`#2511` `#2513` `#2515` `#2568` `#2612` `#2616` `#2418` `#1661` `#1581` `#1619` `#1652` `#1414` `#1031` `#1001` `#980` `#1059`
（配色/字体面板类）`#2193` `#554` `#988` `#2054` `#2530` `#2623` `#2587` `#2525 的字体部分`
（外观/behavior 类）`#2610` `#1294` `#1521` `#1815` `#2164` `#1721` `#2225` `#2297`
（安装包/其它）`#2633` `#2467` `#2402` `#2273` `#1994` `#1943`。
其中 #2566/#2565（"下划线破坏背景调色板"）看着像 SGR 缺陷，但报告场景是**编辑配色的对话框**，按"GUI 设置"排除了；
若主任务后续做颜色面板，可回头翻。

## 10 复取数据的方法

```
D:\dbcli\cache\conemu-ansi\q.py list          # 183 条候选的排名与命中词
D:\dbcli\cache\conemu-ansi\q.py body 1688 …    # 看某条完整正文（BODY_MAX= 控制截断，默认 5000）
D:\dbcli\cache\conemu-ansi\cmt.py labels ansi  # 按上游标签交叉核对（本地，不耗 API）
D:\dbcli\cache\conemu-ansi\cmt.py 2246 2181 …  # 拉评论并缓存到 raw\cmt_<n>.json
```

未认证 API 限额 60 次/小时（`https://api.github.com/rate_limit` 的 `core` 窗口整点重置）。
本文引用到的评论文件已在 `raw\` 下，重复读不再需要网络。
