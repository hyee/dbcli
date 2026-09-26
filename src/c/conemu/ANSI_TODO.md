# ANSI_TODO — render.dll 作为第三方类库的补充路线

快照 2026-09-25。上游参照：**jline4**（`D:\JavaProjects\jline4`，这是dbcli将会更新的第三方库，render.dll 的真实调用方）+ **Windows Terminal**（本地克隆 `cache/msfterm`，行号坐标沿用 `MSFT_TERMINAL_REFERENCE.md` 的已核清单）+ **ghostty**。
姊妹文档：`ANSI_SUPPORTS.md`（现状支持矩阵）、`CONEMU_ANSI_DEFECTS.md`（上游缺陷清单）、`MSFT_TERMINAL_REFERENCE.md`（WT 参照）。

**定调**：补充清单不从"新终端有什么"出发，从**jline4 实际打到 render.dll 的字节**出发——caps 驱动的路径（I26）已经全部建模，剩下的差距全在 jline4 的直发字面量里。下表是逐树 grep 过的主源码清单（测试与 demo 排除）。

---

## 1 jline4 真实发射清单（消费契约）

| 序列 | 发射点 | render.dll 现状 |
|---|---|---|
| **探测批**：`CSI ?u` + `CSI ?2026$p` + `CSI ?2027$p` + `CSI ?2048$p` + `CSI c` | `AbstractTerminal.probeModes()`（AbstractTerminal.java:620-631，`CSI_DEC="\033[?"`:113）；任何 `isModeSupported()` 首调触发，reader 开 `Option.KITTY_KEYBOARD` 即走（LineReaderImpl.java:703→704） | `?u` **误执行成 DECRC（P0）**；`$p` 忽略+计数；`c` 有应答 |
| `CSI ?2026h/l`（BSU/ESU） | `Display` 全屏更新（Display.java:134-135/495/846，byte 模式 `rawEsc`）+ `Terminal.begin/endSynchronizedUpdate`（Terminal.java:1505/1529） | 计数 `RC_UN_MODE` 丢弃 ⇒ 同步输出未生效（P1） |
| `CSI ?2004h/l` | LineReaderImpl.java:707-711（`Option.BRACKETED_PASTE`） | 计数 `RC_UN_DECBP`；输入侧，忽略正确 |
| `CSI 9999E` | LineReaderImpl.java:6623（ConEmu activate hack，仅 `TYPE_WINDOWS_CONEMU`） | 已支持（`E` 臂钳制）✓ |
| `CSI ?1004h/l`、鼠标 `?1000…` | Windows 腿 `trackFocus/trackMouse` 覆写为**只置内存标志**（AbstractWindowsTerminal.java:501/717），不发字节 | 不在电线上 ✓ |
| caps 驱动（csr/sc/rc/cup/el/ed/il/dl/ich/dch/ech/indn/rin/1049/u6/u7…） | `Status.java`、`Display.java`、reader | 全部已建模（I26）✓ |
| OSC（title/hyperlink/133…） | jline4 主干 **0 处直发**；133 是 dbcli 自己发的（I23 已建模） | — |
| 图形（Sixel/iTerm2/Kitty） | `SixelGraphics` 等存在，由探测结果门控（见 §4 的 SIXEL 误报） | DCS 载荷丢弃+`RC_UN_DCS` 计数 |

---

## 2 P0 —— `CSI ?u` 加 priv 门（真 bug，不是缺特性）

**现象**：jline4 的探测批以 `CSI ?u`（kitty 键盘查询）开头；`Render.cpp` `case 'u'`（约 :1117）不查 `priv`，直接 `clxy(saveY, saveX)`——**jline4 每做一轮模式探测，光标就瞬移到上次 DECSC 位置**。reader 只要开过 `KITTY_KEYBOARD` 选项就会发生。

**为什么现在才成立**："restore is unconditional upstream" 是 ConEmu 的行为（Ansi.cpp:4194）；参照对象换成 WT/ghostty 后不再成立——两者的 CSI 分发都把带 private marker 的 final 路由为查询/忽略，不执行 DECRC。

**修法**（约 2 行）：

```
case 'u': if (g->priv) { ignored(g, RC_UN_MODE); break; } clxy(g, g->saveY, g->saveX); break;
```

**门禁**：`RenderCheck` 加"priv 'u' 不动光标 + 计一票"与"裸 `CSI u` 照旧恢复"两条；live 侧复放 jline4 探测批，断言光标只被 `CSI c` 的应答路径触碰。

---

## 3 P1 —— DECSET 2026 同步输出（收益最大）

**现状**：`Display` 每次全屏更新都发 BSU/ESU，注释明说"不支持的终端静默忽略"——现在确实是静默忽略，于是全屏表格/状态栏重绘照旧逐 chunk 上屏，**2026 要治的闪烁一点没治**。dbcli 的全屏重绘正是 flicker 大户。

**实现**（模型一位 + paint 门）：

1. `RcGrid` 加 `uint8_t sync;`；`?2026 h/l`（`'h'/'l'` 臂）置/清，`full_reset` 清。
2. painter 在 `sync` 期间**暂存计划不落屏**——挂点就是现有 `onFlush`/`pendingScrolls` 那套：置位时让 flush 改为积累，`?2026 l` 到达时一次刷出。
3. **超时必须一起抄**（防应用漏发 ESU 永久冻结画面）：参照 WT/conhost 的带超时同步输出；ghostty 是渲染端帧门（`Mode.synchronized_output`）。超时到期按普通 flush 放行并把这一次记进 census。
4. 深度：jline4 不嵌套；若收到嵌套 BSU，按 xterm 惯例第二次是 no-op（计数）。

**门禁**：BSU→写→ESU ⇒ 一次 flush；BSU→写→超时 ⇒ 放行且计数；BSU 后 alt 屏切换/查询应答（I29 的应答**不**被 sync 扣住——它属于 reader 不是屏）。

---

## 4 P1 —— DECRQM/DECRPM 应答（`CSI ? <mode> $ p` → `CSI ? <mode> ; <status> $ y`）—— 已落地，见 DESIGN #51

**原状**：`$`（0x24）与 DECSCUSR 的空格共用单 `interim` 槽，`'p'` 臂只认 `'!'` ⇒ `$p` 全部落计数、无应答；槽位问题先由 #59（interim 升级为集合）解决。

**jline4 侧的容忍度**（这一条决定应答表可以有多小）：`probeModes` 一次写出 `CSI ?u` + `?2026$p` + `?2027$p` + `?2048$p` + `CSI c`，之后 `parseDecrpm`（AbstractTerminal.java:675-690）**按模式号回查**，不是按位置读 ⇒ 少答一个 id 不会错位后面的答案；查不到的号它直接给 `NOT_SUPPORTED`，与答 `4` 同效。

**应答表**（`mode_status`，Render.cpp:1146）——只答模型真持有的状态，只用 1/2 两个数：

| 模式 | 应答 |
|---|---|
| 25 | `cursorVisible` → 2（set）/ 1（reset） |
| 47 / 1047 / 1049 | `g->alt`（三种拼法同一个位，答案不能互相矛盾） |
| 2026 | `g->sync` → 置位 2，否则 1（jline4 把 1 和 2 都读成 SUPPORTED，:685） |
| 2027 / 2048 / 其余 | **不应答**，计 `RC_UN_MODE` |

**为什么 3/4 一个都不发**：VT500 的 3 = permanently reset、4 = permanently set，而 jline4 的注释把两者反过来写（:663-667）——同一个字节在两个读者眼里意思相反。于是对“本 build 没有状态可报”的模式发任一永久值，必对其中一方说谎；2048 尤其致命，答“永久置位”等于宣称窗口尺寸变化会进数据流，信了的程序连 `?2048h` 都不发也等不到通知。沉默则两边都不骗：对 jline4 是 `NOT_SUPPORTED`（正确结论），对其他读者是“这台终端没回答”。与 `CSI ? 6 n` 的裁决同形（Render.cpp:1565 起：宁可不答，也不给一个没被问到的答案）。

**1048 也不答**：xterm 把 1048 列为 "alternating cursor position"，本 build 的 `?1048h/l` 正是存/取光标——那是**事件**，不是能被报告的状态；真在问光标状态的调用者要的是 25。WORK_ORDER T4 建议的“25/1048 → `cursorVisible`”据此有意偏离。

**门禁**：宿主侧每模式应答文本、快照语义（同一 chunk 内 `?2026h ?2026$p ?2026l` 仍答 2）、队列 FIFO 保序、不应答组的 `RC_UN_MODE` 计数；真终端侧原样重放探测批并断言精确字节流 `\e[?2026;<st>$y` + DA1 fence（Render.java:1246）。

---

## 5 P2 —— SIXEL 误报（已修，2026-09-25，修在 jline4 家族层；render.dll 不动）

**机制更正**（本节初版说"conhost 的 4 是 132 列模式"——**错**，已按 WT 源码核正）：conhost 的 DA1 注释明确
`4 = Sixel Graphics`（microsoft/terminal `terminal/adapter/adaptDispatch.cpp` `DeviceAttributes()`，本仓库克隆
`cache/msfterm` :1441），且现代 conhost 的 GDI 渲染器真的画 sixel（`src/renderer/gdi/state.cpp` 的 StretchBlt 配置）。
jline4 的 `parseSixelFromDa1`（AbstractTerminal.java:736-741，`contains(";4;")`）作为**解析**没有病，解析器不改。

真问题是**声明 ≠ 家族可保证的渲染能力**：老版 inbox conhost 声明这个位多年却没有 sixel 渲染器；dbcli 的
render.dll 在写通路上把 DCS 整体丢弃（`RC_UN_DCS` 计数）；最新 conhost/WT 才真画——同一个位在三种宿主上
真假不一，jline4 无从分辨。信了它，`SixelGraphics` 就会发出一段静默消失的 DCS 载荷。

**修复（Information Expert：家族层否决）**：`AbstractWindowsTerminal.isModeSupported(Mode.SIXEL)` 覆写返回
`false`——Windows 控制台家族的写通路不能保证画得出图，就不声明该能力。效果：`SixelGraphics.isSixelSupported`
的探测链（override > DA1 探测 > 静态表）第二层直接落空，静态层里 windows-* 类型不在 sixel 表 ⇒ 净效果
SIXEL=false；`setSixelSupportOverride` 逃生门保留；SIXEL 单独提问不再触发探测批（顺带不再发出 `CSI ?u`
等探测字节）。能证明写通路可达 sixel 渲染器的子类可再覆写。已验证：单文件 javac --release 8 编译通过
（`cache/jline4-sixel-fix/`，未打包、未发布到 `lib` —— `lib/Jline3.jar` 是 3.29 产物，不携带本覆写；它随 jline4 树发布才生效）。
**记账**：这条改的是 `D:\JavaProjects\jline4` 里的 `AbstractWindowsTerminal.java`，属于"动了依赖"，已按硬约定登记进
`JLINE_CHANGES.md`（含四问与"上游报告待人工提交"的出口 `cache/p52/jline4-sixel-report.md`）。
**机制口径更正**：`4` 在 DA1 里就是 Sixel（MSFT 自己的注释 `adaptDispatch.cpp:1441`），不是 132 列（132 列在 xterm 的表里是 `1`）；
本仓库早期笔记与本台账 #52 标题的"132 列"说法是错的，已改。DA1 应答文本与 `render.dll` 一个字节都不动（注释级修改，重建后 md5 与部署件逐字节相同＝对照证据）。

---

## 6 P2（可选，非 jline4 需求，是 dbcli 自身利益）

jline4 不发这些，做了对它没收益；单列是因为 classic 控制台上**可行**：

| 项 | 落法 | 参照 |
|---|---|---|
| HPR `CSI a` / VPR `CSI e` | 解析后按 CUF/CUD 同款相对移动（视口钳制），~2 行、零新状态。jline4 实测不发送（caps 无 hpr/vpr，直发字面量零命中——`CSI Z` 在 jline4 只作输入键），属**兼容性储备**：从 Unix 移植的程序会发 | WT adaptDispatch.cpp:427/:437（VPR 注释明言"unlike CUD not constrained by margin"）；ghostty stream.zig:1863/:1942 |
| OSC 4/10/11 调色板 | `SetConsoleScreenBufferInfoEx` 真改 16 色表 + 同步改模型 `RgbMap[0..15]` 与 `defAttr` 相关折叠；`?` 查询回当前值 | ghostty OSC 4/10/11；WT `SetPaletteColor` |
| OSC 8 超链接 | 学 `rowWrap` 的行级元数据存 URL 区间（不进 `CHAR_INFO`，收养丢弃）；显示面画下划线；宿主查询 API 给 dbcli 做"打开选中链接" | ghostty `hyperlink.zig`；WT `SetHyperlink`/TextBuffer |
| OSC 52 剪贴板 | ✅ **已落地**（build -24，I36）。默认**关**，只有宿主能开（`ANSI_CLIPBOARD` 或 `NativeRenderer.setClipboardPolicy`），读永远拒；详见 ANSI_SUPPORTS §2.8 | ghostty `clipboard-read/write` 策略（`stream_terminal.zig:678-682`/`:820-826`）；WT **有**：`SetClipboard=52`（`OutputStateMachineEngine.cpp:821`）+ `compatibility.allowOSC52` **默认 true**；ghostty **有**：`clipboard-write=.allow`（默认开）；ConEmu 无（实测 `Ansi.cpp` 无 `case L'5'`）⇒ 本库默认关是**偏离两家参照**、须自证的决定（理由在 I36） |
| 括号粘贴 `?2004`（宿主协作版） | **DLL 侧**：模式位存进模式表 + DECRPM 应答（2/1）+ 暴露给宿主（DECCKM 同款"计数+存位+暴露"），几乎免费。**宿主侧**（dbcli 输入泵，DLL 之外）：对按键记录流做突发启发式，内存里包 `200~/201~` 喂 reader——`KEY_EVENT_RECORD` 无粘贴标志位，速率启发有误判两面（漏标=现状，误标=键序打散），默认保守。**DLL 永不读 CONIN$**（与应用 pump 抢队列会偷键盘事件；peek-then-inject 无法保证标记先于粘贴字节） | jline4 消费端已就绪（`LineReaderImpl` BEGIN_PASTE 绑定 ：7088）；Windows 腿现无任何合成（AbstractWindowsTerminal 零命中，已验证）；WT/conhost 均不产标记 |

---

## 7 明确不做（记录防重开）

| 项 | 理由 |
|---|---|
| 鼠标 `?9/?1000-1015`、焦点 `?1004`、DECCKM `?1`、kitty 键盘模式位 | Windows 腿的输入来自控制台记录，`track*` 只置内存标志（AbstractWindowsTerminal.java:501/717），模式位无从生效 |
| 括号粘贴的 **DLL 侧标记合成** | 标记必须先于粘贴字节入流；粘贴字节由 conhost 整串注入，DLL 读 CONIN$ 会与应用 pump 抢队列（偷键盘事件），peek-then-inject 无时序保证。可行路径见 §6"宿主协作版"：DLL 只存位+应答+暴露，打标在宿主泵 |
| 延迟换行 | **显示面就是 conhost 本身**：四条判别式双腿一致已定案（ANSI_SUPPORTS §2.10），改成立即换行只会和 conhost 分叉 |
| 图形协议（Sixel/kitty/iTerm2） | DCS/OSC 丢弃+计数已正确；物理显示面画不出 |
| 斜体/删除线/下划线色的**绘制** | `CHAR_INFO` 16 位属性没有对应位（0x0400..0x2000 是 conhost IME 网格位）；模型侧照旧存储不绘 |
| DECSCUSR 条形 5/6 | `SetConsoleCursorInfo` 只有块/细条两档；若确认 `SetConsoleCursorShape`（Win10 18297+）可用再单独立项 |
| OSC 9 的 ConEmu **危险子命令**（`9;1` sleep、`9;2` MessageBox、`9;3` 改环境变量、`9;7` DoProcess 等） | 永不执行（#687 RCE，I21 已定案）。**安全子集已立项 T7**（判据 = WT `DoConEmuAction` adaptDispatch.cpp:3558——WT 实现的就是 ConEmu 方言的安全面：`9;4` 进度、`9;9` CWD、`9;12` ≡ 133;B；其余 `_api.UnknownSequence()`），DLL 侧存模+暴露（进度给宿主状态栏/CWD 存模），不做任务栏跨进程操作，`SetCurrentDirectory` 这类进程副作用永不从输出流触发 |
| OSC 8 超链接（#56） | **2026-09-26 用户定案不做**（"osc 8不做"）。技术账不变：链接是**区间**不是 cell，只能住在 `rowWrap[]` 旁边并继承 I20 那条"读不回来"的债；只存 URL 不画下划线、也没有宿主查询，序列本身买不到用户看得见的一件事。要重开得先回答"谁消费它"，而不是"别的终端有" |

---

## 8 两条契约提醒（补充特性时别破坏）

1. **宽度的两个神谕并存**：2027 探测拿到 NOT_SUPPORTED 后，jline4 用自己的 `WCWidth`+图位簇分组算宽（WCWidth.java:749 起），render.dll 用 `ansi_width` 表——分歧已由用户裁定以 `ansi_width` 为唯一神谕，**别**因"jline4 也在算宽"做双向对齐。
2. **探测批的收口依赖 DA1**：jline4 靠"DA1 应答到达"结束探测等待（fence），而 render.dll 的应答只在**成功 flush 末尾**写入 CONIN$（I29）——这条时序别破坏，否则每次首探测白等 probeTimeout。§3 的 sync 门**不得**扣住 `flush_reports`（应答属于 reader，不属于屏）。

---

## 9 建议顺序

```
1. P0 `CSI ?u` priv 门            —— 半小时级，修真 bug，门禁两条
2. P1 DECSET 2026（含超时）        —— 闪烁收益直接给 dbcli 全屏重绘
3. P1 DECRQM 应答                  —— 让 jline4 的探测拿真答案
4. P2 SIXEL 误报 → ✅ **已落地**（2026-09-25，jline4 家族层覆写，见 §5）
5. P2 OSC 4/10/11 → ✅ -20（I34）；OSC 52 → ✅ -24（I36，默认关）；OSC 8 → ❌ 定案不做（§7）
```

每步落地的判据与门禁照 DESIGN §6 的既有风格：模型侧 `RenderCheck` 全覆盖，live 侧双腿（复放 jline4 探测批/全屏重绘字节流）+ census 计数可见。

## 10 "上游 ConEmu 没实现，所以我也没做" —— 2026-09-26 重论证与工单

**触发**：用户 2026-09-26 两条裁决 —— ①"不要管 ConEmu 了，我多次提到不要以 upstream 为准"；②"应该实现的特性就要实现，包括且不限于 cbt，因为你开发的是独立的第三方，应给调用方更多的特性支持，而不是因为 dbcli 不用就不做"。两条合起来把"可容许理由"收窄成三类（见 `DESIGN.md` §1 新增那行）：**没有承载面** / **声明或应答就是对同一会话里另一个解析器的谎（I26）** / **故意选的安全地板**。本节把 `Render.cpp` 里所有以"上游也不做/上游就是这么做的"收尾的拒绝逐条过一遍，按新标准重判，并给出可行性、代价与门禁。

工单编号接 `DESIGN.md` §10 台账（#77 起）。每条落地都要过 host + live 两档门禁，且**改出货字节才抬 stamp**。

| # | 项 | 旧理由（原文摘要） | 新判定 | 可行性 / 代价 / 门禁 |
|---|---|---|---|---|
| 77 | **IRM `CSI ?4 h/l`（插入模式）** | "ConEmu 自己也是 'ignored for now'（`Ansi.cpp:3323-3329`），所以 `smir`/`rmir` 两条腿都守不住" | **要做**。参照两家都实现（MSFT `SetInsertMode`、ghostty `modes.insert`）；"上游没 body"不是理由，而"会改每条可打印字符的路径"才是代价 | 中。模型一位 + `put_cell` 走 ICH 语义（现成的 `case '@'` 逻辑可复用）；宽字对必须一起右移（#66 的 `heal_pairs` 正好兜底）。代价：**热路径**，必须加一条 `PaintBench`/host 计时腿证明没有回归。门禁：`?4h` 后写字符把后面的右移、`?4l` 覆盖、区/alt/resize 下的行为、DECRQM `?4$p` 答 1/2、caps 补 `smir`/`rmir`/`mir`（届时声明是真话） |
| 78 | **colon 子参数** `38:2::r:g:b`、`4:3`、`58:5::n` | "整条丢弃，ConEmu 把 `:` 当 Pvt 字节（I10 平价）" | **要做**。平价不是地板；MSFT 有 `_subParameterRanges`（`stateMachine.cpp:505-545`），xterm 也解析 | 中。参数模型要能表达"子参数区间"（现在只有 `args[]` + `priv` + interim 集合）；先做 SGR 一族，其余 final 遇到 `:` 仍计数。门禁：`38:2::1:2:3` 与 `38;2;1;2;3` 折叠到同一属性、`4:3`（curly）按"有状态无绘制"处理并计数、`RC_UN_COLON` 语义改成"解析了但某臂不支持"而不是"整条丢" |
| 79 | **`CSI Ps t` 窗口操作**：`18t`/`19t`（文本区行列）、`22t`/`23t`（标题栈）、`14t`/`16t`（像素） | "`18/19` 可以答但**没有消费者**（规则：只建模真实写手发的东西）" | **要做**（`18/19/22/23`）；`14t`/`16t` 视承载面而定 | 低。`18t`/`19t` 的答案就在模型里（`rows`/`cols` 与 `winRows`）；`22t`/`23t` 是**我们自己状态里的标题栈**（OSC 0/2 已有落地路径），push/pop 两级即可，与"不拥有窗口"无关。`14t`/`16t` 要像素 ⇒ 只能 `GetConsoleFontSize` × 格数估算，MSFT 是从渲染器拿真值——**我们不在那条腿上**，故这两条按"答近似值还是保持沉默"单独裁决，不许混在 18/19 里偷渡。门禁：应答字节精确、FIFO 队列、alt 屏下 `18t` 报的是 alt 的形状 |
| 80 | **DECOM `?48` + 左右边距（`?69` / `DECSLRM CSI s`）** | "not modelled" | **要做**。而且 #64 只做了半条：MSFT 原文是"IL/DL 把光标送到 **leftMargin**"，我们写死第 0 列，正因为没有边距概念 | 中高。新增 `leftMargin`/`rightMargin` + origin 位；影响 CUP/HVP 基准、`step_back_col` 的钳制、IL/DL 归位、ECH/EL 的行尾、DECAWM 的右缘、`heal_pairs` 的边界、alt 快照与 resize。门禁：每条"行尾/行首"语义在 `leftMargin>0` 与 `origin=1` 下各一例，并把 #64 的 `g->cx = 0` 改成 `g->cx = leftMargin`（红臂：留 0 不改 ⇒ 新用例红） |
| 81 | **鼠标族 `?9`/`?1000`/`?1002`/`?1003`/`?1006`/`?1015` + caps `kmous`** | "改变的是输入侧，本渲染器不碰输入编码" | **要做（部分）**。承载面存在：`SetConsoleMode(ENABLE_MOUSE_INPUT)`，VTP 下 conhost 自己把鼠标翻成 X10/SGR 写进输入流；jline4 拿 `kmous` 当"这台终端支持鼠标吗"的**唯一**答案（`MouseSupport.java:85`） | 中。存模式位 + 在 `open()`/`close()` 里**借还**控制台输入模式（关键风险：与应用自己的模式管理打架 ⇒ 必须"只在会话开始时读一次底、close 时写回那份底"，与 I34 调色板同一套归还纪律）；`?1006` 只是报告格式，选位后交给 conhost。`kmous` 进 caps 的时机 = 模式真生效之后。门禁：开关后 `GetConsoleMode` 确实变了、close 后原样还、DECRQM 对每个号答 1/2、census 从 `RC_UN_MOUSE` 迁出、live 侧断言"没抢到别人的输入模式" |
| 82 | **`?2048` in-band resize 报告** | "沉默，因为 3/4 会骗两个读者之一" | **要做**。2（"支持"）可以靠**真发报告**挣到，不必靠撒谎 | 中。几何变化今天走 `align_grid`/重建 ⇒ 在检测到窗口尺寸变化时经 CPR 那条已有通道写回 `\E[48;<rows>;<cols>t`；只在 `?2048h` 时发。风险：与 conhost 自己的 resize 记录重复 ⇒ 需要一条"只发一次"的断言。门禁：resize 后精确字节、`?2048l` 后不发、DECRQM `?2048$p` 从沉默变 2 |
| 83 | **括号粘贴 `?2004`** | "标记必须先于粘贴字节入流，粘贴字节由 conhost 整串注入，DLL 读 CONIN$ 会偷键" | **一半要做**：存位 + DECRQM 答 2 + 暴露 getter 给宿主；**标记合成仍不做**（那条理由属于"没有承载面"，不是"没人用"） | 低（存+答）。门禁：`?2048` 同族；census 仍计但不再"惰性"，报表要能说明"我们持有这个模式，不产生标记" |
| 84 | **X11 颜色名**（`OSC 4;1;red`、`OSC 10;palette:background`） | "130 行表，本树没人发过这个形状" | **要做**。后半句理由已作废；表可直接从参照抄（MSFT `ColorFromXOrgAppColorName`） | 低。纯解析 + 一张静态表 + 生成脚本（照 `gen_rgbmap.sh` 的做法从参照源码里抽，别手抄）。门禁：`red`/`gray50`/`#RGB` 三形一致折叠、未知名仍计 `RC_UN_OSC_OTHER` |
| 85 | **G1 字符集与 SO/SI**（`ESC ) c`、`ESC [`/`]` designator、`SI`/`SO` 0x0F/0x0E） | "本模型没有 GL/GR 换档通道；输入已是 UTF-16" | **要做**（换档是输出侧语义，与输入编码无关）。MSFT 有 `_charsets` + `DesignateG0..G3`，ghostty 有 `Charset`/`active_charset` | 中。四个 designator + 一个 shift 状态 + 每字符查表；`ESC ( 0` 那条现有路径要泛化。门禁：`ESC ) 0` + `SO` 后画线字符生效、`SI` 回普通、`ENQ`/`ESC . c` 仍计数、alt/resize 保留换档状态 |
| 86 | **`u8`/`u9` 等 caps 声明** | "两个序列都应答，但 jline 里没人读 user8/user9" | **理由作废，先查证再声明**。要先确定 ncurses 里 `user8`/`user9` 到底对应哪个形状（别照抄名字），再决定声明什么 | 低（查证）。门禁：`terminfo_check.sh` 的集合会变，`.ti`/`.caps`/jar 三处同步；声明必须与应答形状逐字节一致 |
| 87 | **DECRQM 的非私有拼法与更多模式号** | "`?` 缺失、两个 interim、`$p` 之外的写法 —— 上游都拒" | **逐条重判**：凡是模型真持有状态的号（`?4` 之后有 IRM、`?48` 之后有 DECOM、`?2048`、`?2004`）都该答；纯事件型（`?1048`）与无状态可报者继续沉默，但理由要写成"没有可报状态"，不是"上游不答" | 低。门禁：应答表逐号钉住，沉默集合也要有断言（否则"少答一个"看不见） |
| 88 | **DECSCUSR 条形 5/6** | "`SetConsoleCursorInfo` 只有块/细两档；等确认 `SetConsoleCursorShape` 再立项" | **仍属"没有承载面"，但 Win10 2004+ 有 API** ⇒ 变成运行时探测的可选增强（Win7 地板不变） | 低-中。`GetProcAddress` 探测 + 探测失败退回两档；门禁要有一条"探测不到时行为与今天完全一致"的控制臂 |
| — | **`?3`（132 列）** | "ConEmu 置 GUI 显示选项" | **暂不做，理由要换对**：真理由是"改列数只能靠 `SetConsoleScreenBufferSize`，那会移动用户自己的控制台窗口"，属"没有不伤害宿主的承载面" | 若要翻案：先证明能在不动用户窗口的前提下改宽（结论大概率是否），否则保持沉默并应答 1 |
| — | **延迟换行 / Sixel / 斜体绘制 / OSC 9 执行半边 / OSC 8** | 见 §7 | **不动**。这四条的理由都不属于"上游不做"或"没人用"：分别是"显示面就是 conhost 且四条判别式双腿一致"、"物理画不出"、"`CHAR_INFO` 没有位"、"RCE 安全地板"、"用户亲自定案" | — |

**判据（本节自身的教训）**：`grep` 找"上游也不做"是不够的，要找**句子里的主语是别人**的拒绝句 —— "ConEmu 也不做"、"jline 没人读"、"本树没人发"、"没有消费者"是同一句话的四种写法。工具：`cache/upstream-excuse/cand.py`（平价句式）+ `cache/p63/noconsumer.py`（消费者句式），两份输出合并去重才是完整清单。
