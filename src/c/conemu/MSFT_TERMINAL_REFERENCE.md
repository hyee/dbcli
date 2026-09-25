# microsoft/terminal 参照清单 —— 给 `src\c\conemu\`（native 渲染器）

数据源：`git clone --filter=blob:none` 到 `D:\dbcli\cache\msfterm`，`main` = `0b94a7ea`（2026-09-22），
全仓 5036 条提交（首条 2017-08-11），近 3 个月 97 条。上游按年活跃度：2019 760 / 2020 1000 / 2021 846 /
2022 692 / 2023 560 / 2024 524 / 2025 304 / 2026 252（到 9 月）。**结论：core/buffer/parser 仍在动，但重心已移
到 Settings UI 与 KKP/DRCS**，所以"等它修好我们再抄"只对少数条目成立。

**本文的限制（必须先读）**：
- 本文所有 `file:line` 都是**今天读到的真坐标**（已逐条 grep 复核），但**我没有跑任何东西**：没编译、没跑门禁、
  没碰真终端。凡标 ⚠ 的判断是"从代码读出、尚未执行验证"，落地前必须自己复跑。
- 我们对上游只借**语义与判据**，不搬代码结构：它是"自己拥有屏幕"的终端，我们是"把状态塞进别人的栅格"的插件。
  这条差异决定了 §11 那一整段"不该抄"。
- 上游 `AGENTS.md` 是 **AI 使用政策**（公开贡献需人类实质参与、禁止 AI 署名的 PR）⇒ **不要打算提 PR 回去**；
  代码是 MIT（每个文件头 `Licensed under the MIT license.`），抄改要保留版权行并注明 commit。

## 1 速览：建议动作（按性价比排序）

| # | 一句话 | 我们对着哪条 | 上游证据 | 代价 | 建议 |
|---|---|---|---|---|---|
| S1 | 退格/左移必须落在**字形边界**上，上游有现成原语 | `Render.cpp:580` 的 `g->cx--` | `Row.cpp:375`+`:1215`、`_stream.cpp:293` | 约 6 行 + 3 条门禁 | **做**（真缺陷） |
| S2 | 把"到右缘"做成**显式 pending wrap**，并被任何光标移动清除 | I7/I8、`geo_wrap` | `adaptDispatch.cpp:125/168/191`、`cursor.cpp:98-100`、`14993db1` | 中：改 4 处 + 4 条门禁 | **做**，但先按 §2.3 定平价方向 |
| S3 | 吞掉不认识的序列 ⇒ 立刻把模型标成"游标可疑"，别等下一帧几何对不上 | I19 `unsupported()` | `outputStream.cpp:27-39`（含 PowerShell 那段吐槽） | 1 个标志位 + resync 复用 | **做**，并把 `view_of` 的省法建立在它上面 |
| S4 | 行级**校验和**当 A/B 判据（含颜色），替代逐行文本 diff | §6 证人教义、§10 未收口 | `adaptDispatch.cpp:1281-1300`（DECRQCRA）、`Terminal.cpp:270` 默认关 | harness 侧，无产品码 | **做**：块画"一个 chunk"那条可能因此可测 |
| S5 | 每行一个 `wrapped` 位（软换行标记），复制/分页/导出才分得清硬换行 | 新能力（§4.1、ConEmu #317） | `Row.cpp:177`、`textBuffer.cpp:2401`、`_stream.cpp:176/323` | 256 B 数组 + 2 处赋值 | **做**（便宜，且是别的东西的前置） |
| S6 | 控制字符只在**出口**消毒，栅格里保留原码点 | §3 I13/I14 | `VtIo.cpp:399-424`、`_stream.cpp:237` | 我们栅格本来就存原码点 | **不改代码，改文档**：把这条写进 I14 |
| S7 | 未知 SGR 子参数"跳过而不是猜"，并把 16/32 的上限写明理由 | I19、`Render.h:38` | `stateMachine.cpp:505-533`、`stateMachine.hpp:27-38` | 无 | **已等价**，记档别再审（详见 §5.3） |
| S8 | 宽度模型：**不抄**图位簇；ambiguous 那半句**已作废**——按用户裁决改写成"Wcswidth 模式 + ambiguous 一律 2，减 206 个实测窄码位"（本表下方的 S8 条与 §4 为准，`render-2026-09-24-5` 起表已重新生成） | 宽度神谕 I14 | `CodepointWidthDetector.hpp:9-19`、`3b8c5606` | 无 | **记档**（§4），**且这行的原措辞别再引用** |

§13 单独回答"它哪些地方**实现得比我们好**"（B1–B7，含两条"看着更好但不该抄"的反面自查）。那里唯一值得排进本
轮的是 **B2：把脏与画的粒度从"整行"降到"真变过的列"** —— 与 S1/S2 不同，它是纯性能项，约 10 行（**这句估错了，
真实改动面 5 个文件**），直接打在 §5 成本模型最贵的那个形状上（宽缓冲区改一个字符）。**已落地**，见 §13.1.1。

### 1.1 本轮处置（2026-09-23，逐条量过；S 族那一批量完时 host `checks=1571 fails=0`、真控制台双腿 `checks=3706 failures=0`（21:0x 补上 `open()` 拒绝码一族后复跑）；**B2 落地后是 host `1984/0`、真控制台 `3733/0` 两档**，22:19，`outab\jni-b2stamp4-2219.txt`）

| # | 处置 | 落点（当前行号） | 证人 |
|---|---|---|---|
| S1 | **做了，但结论与本文的预料相反：改对的是我们，错的是兜底腿** | `Render.cpp:491` `step_back_col`，`case 'D'` :523 与 BS :653 共用 | 栅格证人：S1 之前 4 条 BS 分叉，之后只剩 1 条 —— `native [3042L 3042T 005F]` vs `hk [0020 005F 0061]`，游标 native (3,10) / hk (2,14)。那条是 ConEmuHk 把宽字形按 **1 列**计数 ⇒ BS 少退一格 ⇒ 写进尾格时 conhost 清掉前导格（#852 家族）。所以**不抄回来**，钉成一条"期望不同"的门禁（DESIGN §4.2 第 1 条）。本文 §3 说"我们对着 `g->cx--` 有确定缺陷"——缺陷是真的，但它不是分叉的原因 |
| S2 | **不做**。本文标"做"，被证人否掉 | 模型保持立即换行，`put_cell`/`put_pair` 一行没动 | §2.2 的四条判别式已建进 `Render.java:430-433`，200 列缓冲区 / 100 列窗口上**四条全部 legs agree**（`full row then CR then Y` / `then BS then Y` / `then EL` / `then CUU then Y`）。⇒ 这一族我们与兜底腿本就一致，改成延迟换行只会**造出**分叉；§2.2 第三行担心的"EL 多擦一行"在我们的负载形状上量不出来（DESIGN §4.2 末段）。§2.3 那个"平价对象是谁"的问题就是靠这个证人回答的：兜底腿站在立即换行这一侧 |
| S3 | **做了**（含本文建议的 resync） | `unsupported()` :447、置位票 :459（只 `SUP`/`DECSTBM`/`ALTBUF`/`MODE`）；`RenderJni.cpp:516` flush 成功后判断并 `align_grid` | `gm_wrap_suspect` + `Render.java caseSuspectAlign`：`"one adopt per chunk"`（`aligns=1`）、`"two swallowed regions, one adopt"`（`aligns=1` 而非 2）、`"and buys no repaint"`（鼠标 `aligns=0`）。**拒绝腿不自愈**（兜底腿要用同一批字节重放），这条写在 `RenderJni.cpp:516` 上方的注释里 |
| S4 | **不做，且本文给它的理由站不住** | — | 本文写"做：块画'一个 chunk'那条可能因此可测"——**校验和看不见 chunk**：它是同一帧栅格的有损投影，而 chunk 之争恰恰是"同帧栅格两种写法长得一样"（DESIGN §10），所以任何只对栅格求和的判据都判不了它，要判得抓字节流（AnsiLog `-new_console:L:` 或 writer 记录挂点）。在能判的范围内它又是**降级**：现有 A/B 是逐格比字符 + 属性段（`A[,ax111]`），校验和只能回答"相同/不同"，不同时还要退回逐格 diff 才知道差在哪。⇒ 上游有它是因为远端比对读不回整帧（`adaptDispatch.cpp:1281-1300`），我们没有这个约束。§9 其余做法未动 |
| S5 | **做了**，但本文低估了工作量："2 处赋值"真数是**四处置位 + 一处清零 + 三处搬运** | `Render.h:131` `rowWrap[]` + `enum RcRowWrap`；`Render.cpp` `put_cell`/`put_pair` 的写前（PAD）与写后（FORCED）两条出口、`fill_span` 触缘清成 NONE、`scroll_up` 平移并给新行 NONE、IL/DL 各自搬运；`rc_forget_wrap` :180 | `gm_wrap_suspect`（约 47 断言：forced/pad 各判其位、擦到右缘清零、差一格擦除不清零、滚动与 IL/DL 带位）。⚠ 这个位**不可能有真控制台门禁**：`ReadConsoleOutputW` 读不回它（§5 的契约），所以它只在模型内生效——正因此收养时必须清空，留旧主张比没主张更坏（`RenderJni.cpp:600`） |
| S6 | **只改文档**（本文的建议原样成立，栅格存原码点是现状） | DESIGN I14 + §8 第 1/3 条判据（出口消毒、尾巴含 C0 时按"没人解释就别发控制码"那档处理） | 不需要证人 |
| S7 | **确认等价，记档** | `arg()` 的越界返回默认值 = 上游"跳过而不是猜"；参数上限注释在 `Render.h` | 复核过 §5.3：未知子参数不参与着色，与 `stateMachine.cpp:505-533` 同判据。⇒ 再审清单里划掉 |
| S8 | **记档，且本轮按用户裁决改写了后半句**：我们的宽度神谕 = 上游 **`Wcswidth` 模式 + ambiguous 一律按宽（206 个实测窄码位例外）+ 无 VS16 升级** | `ansi_width` 表（唯一神谕）与 `rc_width` :37；例外表是生成器里的 `AMBIGUOUS_NARROW`，规则与裁决记在 DESIGN I14 与 §7 | `check_widths` 全表比对（20 个钉住的类别，两半裁决各钉一半）；本轮新增的 astral 用例（DESIGN §4.2 第 2 条：native `[D83DL D83DT]` vs hk `[FFFDL FFFDT]`）顺带证实了 §5 那条契约——一个遗留 16 位格装不下 astral 码点，尾格被 conhost 重复成前导 WCHAR。上游那条 `_ambiguousWidth` 开关（§2 末）等价于我们的 `cjkWidth` 证人：xterm 372 开 `-cjk_width` 后与本文表 7,117/7,324 相同，差的 207 个正好是那 206 条例外加软连字符（`ansi_width.md` §6） |
| §13.2 / B5 | **做了两件事**：colon 单独计一票 + 语气从"缺口"改成"已定性偏离 + 上游行号" | `RC_UN_COLON`（`Render.h`，附理由）；`csi_start` 清、参数分支置 `g->csiColon`、`csi_dispatch` 后那一票；`'m'` 分支改成 `else if (!g->csiColon)`（colon 不再冒充"未知模式"）；`CONEMU_ANSI_DEFECTS.md` §4 新增该行 | `caseSuspectAlign`：`"the colon form has its own counter"`（`colon=1`）+ `"and buys no repaint"`（`aligns=0`，即不置 `modelSuspect`——colon 不改格）+ 模式计数不被 colon 污染 |
| B1–B7 | **B2 已落地**（用户复述裁决"I7不收窄，继续"之后）；B1/B3/B4/B5 已在上表处置；B6 随 B2 自然成立（区间是数据，行宽仍是 `cols`）；B7 仍**明确不抄** | I22（DESIGN §4）：`Render.cpp` `mark_dirty(row,from,to)` :154 + `dirtyLo/dirtyHi`（`Render.h:132`）、`Paint.h` `RcRun.lo/hi`、`RenderJni.cpp` `build_row`/`write_rect` 按矩形发；**模型行一寸未收**（I7 原样） | host `checks=1984 fails=0`（`geo_damage` 列区间段 + `plan_damage_range` + `check_damage_bounds` 124 语料 × 2 形状）；真控制台 `checks=3733 failures=0` 两档（`caseNarrowRepaint`、`caseWideBuffer`）；三腿活体 A/B 两条绿 + 2000 列缓冲区活体腿 0 行不同。**"约 10 行"是本文的低估**：真实改动面是 5 个文件，见 §13.1 末段 |

## 2 延迟换行：上游有一整套，且是刚修过的

### 2.1 状态放在**光标**上，不是行上

`AdaptDispatch::_WriteToBuffer`（`terminal/adapter/adaptDispatch.cpp:100-195`）是权威写法，四条规则：

1. 写到越过右缘时，**游标回夹到 `columnLimit - 1`**（`:168`），并只置一个标志 `cursor.DelayEOLWrap()`
   （`:191`；实现 `buffer/out/cursor.cpp:190`，存的是**当时的坐标** `_coordDelayedAt`，不是布尔）。
2. 下一个字符进来时，先消费这个标志再做别的事（`:125`）；**只有当前游标仍等于当初标记处的坐标才真的换行**
   ——中间任何移动都把它作废。
3. 消费动作 = 一次 `_DoLineFeed(page, true, true)`，若它推动了视口还要重算 margins/行宽（`:133-145`）。
4. **防死锁守卫**（`:173-188`）：如果"想换行但一个字符都没写进去"（字形比整行还宽，或 DECAWM 关掉且宽字形
   放不进最后一格），就 `state.text = state.text.substr(GraphemeNext(state.text, 0))` —— **丢掉这个字形**，
   因为不推进迭代器会死循环。注释明写 "there's no good way to detect this, so we check whether the begin
   column is the left margin"。

清除点全部集中在 `Cursor` 里，共 7 个方法各调一次 `ResetDelayEOLWrap()`（`cursor.cpp:101/111/121/131/141/151/161`），
并且 `:98-100` 的注释就是最好的一条用例：

> `// The VT code assumes that moving the cursor implicitly resets the delayed EOL wrap, so we call
> // ResetDelayEOLWrap() independent of _cPosition != cPosition. You can see the effect of this with
> // "\x1b[1;9999H\x1b[1;9999Hb", which should print just "b".`

**注意"移动 = 清除"包括原地不动的移动**（同一个坐标也算）。而保存/恢复游标（DECSC/DECRC）**带上**这个位：
`adaptDispatch.cpp:480` 存 `IsDelayedEOLWrap`，`:509` 恢复时重新 `DelayEOLWrap()`。

### 2.2 与我们的差别，以及能被看见的四种形状

我们现在是**立即换行**：`put_cell` 写完 `g->cx += w; if (g->cx >= g->cols) { g->cx = 0; line_down(g); }`
（`Render.cpp:274-279`），`case 0x0D: g->cx = 0;`（`:583`）**无法撤销**那次 `line_down`。
`geo_wrap`（`RenderCheck.cpp:545-583`）验的是"填满一行后写下一个字符"，那一例**两种模型结果相同**
（延迟模型会先补换行再写），所以现在没有门禁能区分。⚠ 以下四种能区分，全部未跑：

| 输入（行宽 N） | 立即换行（我们） | 延迟换行（上游/VT） |
|---|---|---|
| `N 个字符` + `\r` + `Y` | `Y` 落在 (r+1, 0) | `Y` 覆盖在 (r, 0)，第 r 行保持完整 |
| `N 个字符` + `\b` + `Y` | `Y` 落在 (r+1, N-1) | `Y` 覆盖 (r, N-1) |
| `N 个字符` + `\x1b[K` | 擦掉**下一整行** | 只擦 (r, N-1) 一格 |
| `N 个字符` + `\x1b[nA/B` 之后再写 | 相对移动全部从 r+1 起算 | 从 r 起算 |

第三行是我们最该担心的：进度条/覆盖式输出打满一整行再发 EL 是现实形状，而后果是**多擦一行**（看得见）。

ConEmu #2404 的报告人 chrisant996 判"是 conhost 行为变了才暴露的"，那条变更就是
`microsoft/terminal#3943` = **PR「Add support for VT100 Auto Wrap Mode (DECAWM)」，2019-12-13 提出，2020-02-04 合并**
（我用 API 复核过：`state: closed`、标题即答案）。而**同一个状态机在 2025-05-13 又被修了一次过紧的提前换行**：
`14993db1` "Fix overeager pre-delayed-EOL wrapping in AdaptDispatch (#18899)" —— 删掉的就是"只要填满最后一格
就把行标成 wrapped"那 7 行，提交说明写着 "We never removed it because it broke the old VT rendering-based
ConPTY implementation. Now that VtEngine is gone, so can be this code"，并 "hopefully the last of our exact
line length write wrap issues. tmux users can finally rejoice"（Closes #8976 #15602）。
**这条对我们有用**：它证明"填满即算换行"是**错的**（连上游自己都刚删掉），也证明这一类缺陷只在
"行宽恰好等于 N"时出现 —— 我们的 `rc_reset(&g, 10, ...)` 用例全是整 10 的整数倍，正好是最容易踩的形状。

### 2.3 落地前必须回答的一个问题（平价对象是谁）

S2 不能直接改，因为硬约束是"和兜底腿 `WriteProcessed3`→ConEmuHk 输出平价"。上游的选择是**延迟**，
ConEmu 自己的选择**未知且已知有缺陷**（#2404/#407/#1873/#2116 全在这一族）。所以顺序应该是：

1. 先用现成的三腿 harness 拿证人：`cache\jnatest\native-ab.ps1`（语料造"整行 N 个字符 + `\r` + `Y`"和
   "`N` + `\x1b[K`"两条），读 off/on/bug 三栏栅格。**先测 ConEmuHk 究竟怎么画**，再决定跟谁。
2. 门禁侧照抄 §2.1 的四条判别式（`geo_wrap` 旁边加 `geo_wrap_pending`），再加它那条"原地移动也清除"的用例。
3. 若决定跟 VT：模型要加 `pendingWrapAt`（一个 `int`，-1 = 无），在 `put_cell`/`put_pair` 越缘时改成
   "夹住 + 置位"，并在 `control()` 的 BS/CR、`csi` 的 CUP/CUU/CUD/CUF/`G`/`d`、`esc_dispatch` 的 `7`(DECSC/DECRC)
   处清除。**别忘 I8**：夹在 `winR` 的规则与"夹在 `cols-1`"是两处不同的夹，别合并。

## 3 退格与字形边界：一处确定的缺陷

上游把"上一格/下一格"做成 ROW 的原语，语义写在函数名上（`buffer/out/Row.cpp`）：

```
:375  NavigateToPrevious(col) = _adjustBackward(clamped(col-1))
:382  NavigateToNext(col)     = _adjustForward(clampedInclusive(col+1))
:392  AdjustToGlyphStart(col) / :404 AdjustToGlyphEnd(col)
:1215 _adjustBackward: for (; _uncheckedIsTrailer(column); --column) {}   // 一路退到不是 trailer 的列
```

`CharOffsetsTrailer` 是**每列一个标志位**，所以退格天然不会停在一个宽字形的中间；`_stream.cpp:293`（BS 的处理）
和 cooked read 都走 `NavigateToPrevious`。

我们：`case 0x08: if (g->cx > 0) g->cx--;`（`Render.cpp:580`）—— 一格一步，**不认识 LEADING/TRAILING**。
如果左边那格是宽字形的尾半，游标就停进字形肚子里：下一次 `put_cell` 从中间写，留下一个孤儿 TRAILING
（正是 I13 花力气避免的那类幽灵格）。⚠ 未跑，但读码即可判定；同一问题适用于 `CUF`/`CUB`（`csi` 的 `D`/`C`/`E`/`F`
里凡是手改 `g->cx` 的点）。

**建议**：加一个 `static int rc_step_back(RcGrid*, int col)`，规则照 `_adjustBackward`（落在 TRAILING 就再退一步），
BS 与 CUB 都走它；`RenderCheck` 补三例：宽字形后 BS、宽字形后 CUB 1、"宽 宽 窄"混排里 BS 连续 3 次。
ConEmu #852（游标处是全角时一次删 2 个字符）是**同一个洞的另一半**：它删多了，我们停在中间。

## 4 宽度与字位：它没有推翻我们，反而给了我们一个名字

`types/inc/CodepointWidthDetector.hpp:9-19` 明确摆着**三种可切换的测量模式**：

| 模式 | 它的定义（注释原文摘要） | 对应我们 |
|---|---|---|
| `Graphemes` | "very similar to the official UAX #29 Extended Grapheme Cluster algorithm"，`width` 只可能 0 或 2 | ✗ 我们不用 |
| `Wcswidth` | "any zero-width character as a **continuation of a preceding non-zero-width character**" | **≈ 我们**（`put_cell` 的 `if (w <= 0) return;`） |
| `Console` | "the old conhost algorithm is UCS-2 based and assigns a **minimum width of 1** to all codepoints" | ✗ |

也就是说我们的"一次一个码点、零宽不占格"不是野路子，是它的一个已命名模式。
`ansi_width.md:39` 写的"ambiguous 一律 1、不给 opt-in"，与 `3b8c5606`（2026-02-28 `compatibility.ambiguousWidth`，
默认 narrow，Closes #153 #370 Refs #2928 #2066 #2375…）**同方向**；提交说明里有两句要抄进我们的文档：

> Width detection is currently process-wide (`CodepointWidthDetector` singleton)… **Some client applications
> (for example PSReadLine/readline-based apps) may still compute character widths independently. In such cases
> cursor movement or Backspace behavior can differ from visual cell width even when terminal-side policy is
> consistent.**

这正是 dbcli 的位置（**我们就是那个自己算宽度的 app**），而且是上游官方承认无解的权衡 —— 宽度神谕只需自洽，
不必与字体 advance 一致（ConEmu #1330 的抱怨即"栅格与 advance 不一致"）。

真正的**分歧点只有一个**：它的 `Graphemes` 模式里 `ucdToCharacterWidth()` 返回 3（ambiguous）时替换为
`_ambiguousWidth`（`CodepointWidthDetector.cpp:1036`），且 VS16 之类的后随码点会把已测宽度改掉
（`GraphemeState` 的注释举了 "narrow emoji + FE0F ⇒ 前一格宽 1、后一格宽 2、**总宽取 2 而不是 1+2**"）。
我们 `U+26A0 + U+FE0F` 恒为 1 格（`ansi_width.md` §4.8 已记档为有意偏离）。
**原建议"不改模型"已被用户裁决推翻一半**（2026-09-24）：ambiguous 现在**按宽**计，只留下 206 个
"在任何一款控制台字体里都实测一格"的码位作例外（框线、方块元素、带音标的拉丁字母）。当年那句"写进
`Render.h` 的 I14 注释"其实没落地——`Render.h` 里从来没有 I14 注释，只有 :13-15 那行"宽度神谕 =
`ansi_width.c cp_width()` + 它的 Unicode 15 表"；规则与代价写在 **DESIGN I14 + §7**，要动宽度去读那两处。两条独立佐证值得记在这里：一是 xterm 372
把这条裁决做成了开关（`-cjk_width`），开它跑 7,324 点与本文表 **7,117 相同**，差的 207 就是那 206 条例外
加软连字符（`ansi_width.md` §6）；二是上游自己的 `unicode_width_overrides.xml` 把 `2500-259F` 强制成 H，
理由 "box-drawing and block elements **require 1-cell alignment**" ——**正是我们例外表的存在理由**，
只是它作用在"宽"这个默认之上，我们作用在"窄"这个默认之上，两半合起来才是同一张表。

顺带两条可直接抄的小东西：
- `src/types/unicode_width_overrides.xml` 全文只有 **3 条覆盖**，其中 `2500-259F → H`，注释理由
  "box-drawing and block elements **require 1-cell alignment**"、`4DC0-4DFF` "hexagrams are historically narrow"、
  `FE20-FE2F` 窄组合连字。我们的表（`ansi_width_tables.h` 头注释）也有 measured overrides（软连字符、
  Prepended_Concatenation_Marks、Hangul jamo、Yijing→**2**）。**注意第 2 条正好相反**：它 Yijing=窄、我们 Yijing=2。
  两边都是"实测覆盖"，不必统一，但要记一句"与上游有意不同，因为 dbcli 输出里 Yijing 出现在宽字符列对齐场景"⚠（后半句是推测，需要一条真实输出佐证再落）。
- `Row.cpp:1215` 那种"一个标志位 + 一个 while 循环"的小原语，比我们复制 `ch` 到尾格的方案更耐擦除。
  不能照搬（我们必须写 CHAR_INFO），但它提醒：**尾格的 `ch` 是不可信数据**（见 §5）。

## 5 CHAR_INFO 契约被上游**主动改过**，这条直接砸在我们的证人和 `align()` 上

`8a26f141`（2022-07-23）"**Introduce breaking changes to ReadConsoleOutput** (#13321)"，为图位簇存储铺路，
提交说明给出可执行的判据（原文摘要）：

- `ReadConsoleOutputW` **现在把前导码点重复两次，忽略尾部那一个**；例：写 `0x3044 0xabcd` 再读回 ⇒
  `0x3044 0x3044`（以前能把 `0xabcd` "走私"回来）。
- `ReadConsoleOutputA` 永远**清零 `UnicodeChar` 高字节**，转换失败时清零 `AsciiChar` —— 明写
  "This prevents users from storing 'additional' data in the terminal buffer"。
- 讨论过"给 `WriteConsoleOutputA/W` 写的数据打标记以便将来还原"，**决定不做**（"everything that touches the
  buffer's text would have to handle these marks"）。

对我们的三处影响（都⚠未跑）：
1. `align()`（`RenderJni.cpp:527/697` 的 `ReadConsoleOutputW`）**收养**屏幕时拿到的尾格 `ch` 是前导码点的副本，
   不是原始低代理对 ⇒ 我们栅格里"宽字形的尾格"在收养后与写入后不一致（写入侧我们存 `hi/lo`，`Render.cpp:299-301`）。
   影响 repaint 与 diff，不影响 A/B（两条腿同样读法）。
2. `Render.h:67` 的 `RcCell.ch` 是 `uint16_t`，一个 CHAR_INFO 一个 WCHAR —— 与上游旧模型同构，
   而**上游已宣布这个模型是错的**（#8000）。我们的 `put_pair` 注释里那句 "not something I will assert from
   reading"，现在有了可读的权威：**在新 conhost 上代理对不被保证还原**。
3. `Row.cpp:494-503` 是我们矩形写的**风险说明书**：只有当**第一个** `CHAR_INFO` 是 trailer 时才特殊处理
   （`ReplaceCharacters(currentIndex-1, 2, ...)`），"in general, in the rest of conhost, we're throwing away the
   trailing half of all CHAR_INFOs"。**我们目前每帧从列 0 起整行写，所以永远不会命中这个分支** —— 这是
   §8.1"把 run 横向裁短"这个念头唯一的、会静默改变内容的代价。谁要做横向裁剪，必须先读这段。

**建议动作**：`Probe.java`/`Probe.cpp` 加一条 astral 往返用例（写 `U+1F600` → `ReadConsoleOutputW` → 报告两格
各是什么），在 Win11 conhost、Win7（如果有机器）、ConEmu 三种后端各跑一次，把结果写进 I13/I14 旁边。
这是唯一能替 `Render.cpp:287` 那段"我不从读码断言"收尾的实验。

## 6 SGR / 属性（C 组）：可抄的是"形状"，不是折叠

- **命名枚举 + 一一对偶**：`_ApplyGraphicsOption`（`adaptDispatchGraphics.cpp`）用
  `Underline/NoUnderline`、`Overline/NoOverline`、`ForegroundBlack…BrightBackgroundWhite`、
  `ForegroundExtended/BackgroundExtended/UnderlineColor` 这类**具名项**，`case No*: attr.SetXXX(false)`。
  ConEmu #484（有 5 没 25、"背景/下划线共用一个桩函数"）在它那里结构上不可能发生。
  我们的 `sgr_apply` 已是 if-chain，**建议只抄判据**：`RenderCheck` 里加"每个 on 码配一个 off 码"的成对表驱动用例
  （CONEMU_ANSI_DEFECTS §8 第 5 条已经写了这条，但没钉"表驱动"这个做法：枚举一张 `{on,off}` 数组循环断言，
  新增属性时漏配对就红）。
- **SGR 保存/恢复栈**：`PushGraphicsRendition`/`PopGraphicsRendition`（`adaptDispatchGraphics.cpp:464-480`，
  `_sgrStack`）—— 我们完全没这两条序列（属 I19 计数项）。**若真会话里 `nUnsupported` 报出它们**，再实现；
  它们对 I11 的 echo 有额外要求（echo 必须把栈操作也重放给 ConEmuHk）。
- **未知参数"best effort"**：`:129-133` 注释 "if we don't recognise the parameter substring (parameter and its
  sub parameters) then we should just skip over them"。**关键在"连同子参数一起跳过"** —— 只跳一个数字会让后面的
  子参数错位的解析器（有些终端确实如此）产生假颜色。我们 `push_arg` 是扁平数组 + `RC_CSI_ARGS 16`
  （`Render.h:38`，理由写明是对齐 ConEmu 的 `ArgV`），语义上没有"substring"概念，所以 `48;2;...` 之类靠 `g->interim`
  链式判定 —— ⚠ 值得专门喂一条 `\x1b[58;2;1;2;3m`（我们大概率不认识 58）验证它不会把 `2;3` 当成两个普通参数画错背景。
- **参数上限/饱和**：`stateMachine.hpp:27/32/35` = `MAX_PARAMETER_VALUE 65535`、`MAX_PARAMETER_COUNT 32`、
  `MAX_SUBPARAMETER_COUNT 6`；越界行为 = **忽略后续参数**（`stateMachine.cpp:505-533` 的 `_parameterLimitOverflowed`），
  空参数也计数（"`\x1b[0;;m` 是三个参数"，:520）。我们 `Render.cpp:685` 的饱和钳位是 **65535**（与上游同值）、
  `:703` 的 `if (g->digit) push_arg(...)` 正是"空参数不当零"的同一条规则，`:593` 注释一致。
  **⇒ 这一项我们已与上游等价，记档，别再审。**
- **擦除用什么属性 = 一个模式位**：`DECECM_EraseColorMode = DECPrivateMode(117)`
  （`DispatchTypes.hpp:537`，`adaptDispatch.cpp:1849/1999`）。我们 I13 断言"擦除是整体覆盖 ⇒ 尾格必被销毁"；
  上游把"擦除用默认色还是当前色"做成可选。对我们：ConEmu 走哪种**未知**，⚠ 但这条**不该跟随**——
  我们的栅格 diff 需要"擦除=当前属性"才自洽（I13 的门禁 `geo_erase` 就是钉这个的）。记成"已知分歧"。
- **闪烁移到渲染层**：`2e78665e`（2025-11-11）"Move all blink handling into Renderer (#19330)"；
  我们只有 `SGR 5` 的位，画不出来（ConEmu #484 的另一半）。**结论：维持现状**，把 SGR 5 当"存位不画"，
  与 `fg==bg` 避让一样写进 I15 的注释里。

## 7 模式位、能力声明与"游标可疑"（D 组）—— 本文最值钱的一条

### 7.1 `UnknownSequence` ⇒ 标脏，而不是继续相信模型

`ConhostInternalGetSet::UnknownSequence()`（`host/outputStream.cpp:27-39`）全文值得抄进 DESIGN：

> `// VT sequences unknown to us may cause the cursor position to change in a way that we don't know about.
> // In this case, we need to mark the cursor position as "dirty". The worst offender is likely PowerShell.
> // It uses VT sequences but also calls GetConsoleScreenBufferInfoEx for *every single line of output* (!!!).
> // This prevents us from using a more conservative solution (e.g. always fetching the cursor position).`
> `if (gci.IsInVtIoMode()) … SetConptyCursorPositionMayBeWrong();`

而 `Terminal::UnknownSequence()`（`cascadia/TerminalCore/Terminal.cpp:1554`）是**空的**：只有"输出还要再交给
别人解释"的那一侧才需要标脏。**我们正是那一侧**（我们后面跟着 ConEmuHk / conhost）。

对照我们：`unsupported()`（`Render.cpp:411`，I19）只**计数**，不改变任何信任状态。今天靠"每次拒绝都会
`resync=true`，下一块先 `resyncNow()`"（R1 的描述）间接恢复；但"我们吞掉了一条会动游标的序列"（DECSTBM + 随后的
滚动、DECOM、备用屏…）与"我们画错了几何"不是同一件事：**前者不会触发 decline，也就永远不会 resync**。
**建议**：`unsupported()` 里顺手 `g->modelSuspect = 1`；`flush` 之后（或下一块开头）若 `modelSuspect` 则强制一次
`align()` 并清标志。这样才把 I19 从"统计"升级成"自愈"。而且它是 §8.2 想省 `view_of` 的**唯一正当依据**：
"平时不读真控制台，因为我们能证明模型没被怀疑"，而不是"平时也读，反正便宜"。

### 7.2 真相源分三层，不同步就报"不支持"

`AdaptDispatch::RequestMode`（DECRQM，`adaptDispatch.cpp:1934-1990`）逐个 case 显示模式位分别住在
`_modes`（终端级）、`_api.GetSystemMode(...)`（conhost OutputMode：AutoWrap / LineFeed）、
`_terminalInput.GetInputMode(...)`（输入级：CursorKey / Keypad / AutoRepeat / LineFeed）、
`_renderSettings.GetRenderMode(...)`、`_api.GetStateMachine().GetParserMode(...)`；
默认值是 `DECRPM_Unsupported`。最有教育意义的是 LNM 那条：

> `// VT apps expect that the system and input modes are the same, so if they become out of sync,
> // we just act as if LNM mode isn't supported.`

**这就是 ConEmu #1068/#1380/#2246/#2302「能力声明与谁在解析不同源」的处置范式**：宁可声明不支持，也不给一个
自己都不确定的答复。我们对应的东西是 `db_core.lua`/`Console` 的"是否解释 ANSI"（`DBCLI_NATIVE_RENDER`、
终端类型判定）与 I12 的 `defAttr` 冻结。建议：把"开关、终端类型、渲染器是否活着"三件事收敛成一个
`capabilities` 快照，在 `open()` 时一次算定，日志里打印，别在三个地方各读一次环境变量。

### 7.3 输出模式是**每缓冲区一份**，且模式切换有明确的交接动作

`ENABLE_WRAP_AT_EOL_OUTPUT` / `ENABLE_PROCESSED_OUTPUT` / `DISABLE_NEWLINE_AUTO_RETURN` 都在
`screenInfo.OutputMode` 上（`_stream.cpp:156/196/309`），不是全局变量；`readDataCooked.cpp:516` 同样
"processed mode 关掉时控制字符就只是普通字符"。而 `WriteCharsLegacy`（`_stream.cpp:204-222`）在入口专门处理
"有人先用 VT 写、现在切到非 VT 模式"：**先把延迟换行落地成真实的 CRLF，再把游标还给 Console API**
（"Since the Console APIs don't support delayed EOL wrapping, we need to first put the cursor back to a position
that the Console APIs expect"），并且**同时往 VT 流里补 `\r\n`** 让另一端也同步。

⇒ 这就是我们 I11（SGR 回声）的同类问题的一般解：**两个解释器交接时，把各自延迟/缓存的状态先落地，
再移交，而且要双向落地**（我们只回放了 SGR 给 ConEmuHk；游标的 pending 状态与"我们吞掉的会动游标的序列"
没有对等回放）。配合 §7.1 的标脏，就是完整的一套。

### 7.4 会碰外部系统的 OSC 走一张能力位图——但**默认值一条一个样**，剪贴板那条是开的

`ITermDispatch::OptionalFeature`（`terminal/adapter/ITermDispatch.hpp:28-33`）只有三项：
`ChecksumReport`、`ClipboardWrite`、`DesktopNotification`；由客户端逐个填
（`cascadia/TerminalCore/Terminal.cpp:270`：`features.set(ChecksumReport, settings.AllowVtChecksumReport())`，
`:271` 同款填 `ClipboardWrite`）。**这一层 §7.4 的原判断成立**：外部效果不是"一个开关"，而是
**一张只有几项的能力位图 + 在 DECDSR/DECRQM 里如实报"不支持"**，也正是 ConEmu #687（私有 OSC 可执行程序 = RCE）
与 #2624/#2627（OSC 52）的标准答案。

**但"默认全 false"这一半在 2026-09-26 被自己推翻**（为 I36 复核时打开设置表看到的，`file:line` 为证）：

| 能力 | 设置名 | 默认 | 坐标 |
|---|---|---|---|
| DECRQCRA 屏幕校验和 | `compatibility.allowDECRQCRA` | **false** | `MTSMSettings.h:118` |
| OSC 52 写剪贴板 | `compatibility.allowOSC52` / `AllowVtClipboardWrite` | **true** | `MTSMSettings.h:119`、`ControlProperties.h:59`、`Terminal.cpp:106` |
| OSC 9 桌面通知 | `AllowOscNotifications` | false | `ControlProperties.h:60` |
| kitty 键盘模式 | `AllowKittyKeyboardMode` | true | `ControlProperties.h:52` |

⇒ 上游把**剪贴板写**当成默认允许（那条设置的存在是为了**关**它），把**校验和报告**当成默认拒绝。⇒ 对我们真正的含义有两条：
① 参照的默认值不提供"我们也该默认关"的支持，也不提供"该默认开"的支持——**它是一次上游裁决的结果，不是判据**
（[[feedback-upstream-not-a-reason]] 的正反两面都在这里）；② WT 能默认开，是因为它面对的是**自己配置过的终端用户**；
render.dll 寄生在别人的 JVM 里，没有那份配置，所以 I36 的默认关是自证的分叉，写进 DESIGN 而不是抄来的。
另外 WT 的 OSC 52 **解析读取但从不作答**（`OutputStateMachineEngine.cpp:825` 的 `&& !queryClipboard`），
且**整个忽略选择字段 `Pc`**（`:1097` 注释自陈 "Currently the first parameter `Pc` is ignored"）——
前者我们与它一致（我们更严：连政策档都不给），后者我们不抄（折叠＝用另一个东西回答被问的那个问题）。

## 8 输出卫生：控制字符、CRLF、消毒

`VtIo`（ConPTY 的**产生端**，`host/VtIo.cpp`）有一组非常克制的出口函数，命名即语义：

```
Writer::WriteUTF16 / WriteUTF8            // 原样
Writer::WriteUTF16TranslateCRLF(:613)     // 只处理 \n→\r\n
Writer::WriteUTF16StripControlChars(:653) // 扫到控制字符就送进 SanitizeUCS2
Writer::SanitizeUCS2(:399)                // C0→CP437 图形、0x7F→⌂、C1→'?'、代理对半→U+FFFD
Writer::WriteCUP / WriteDECTCEM / WriteDECAWM / WriteASB / WriteDSRCPR / WriteAttributes …
Writer::Submit()                           // 一次性发出
```

三条给我们定规矩的注释：

1. `SanitizeUCS2`（`:401`）："If any of the values in the buffer are C0 or C1 controls, we need to convert them to
   printable codepoints; **otherwise, they'll end up being evaluated as control characters by the receiving
   terminal**" —— **消毒只发生在"要把文本交给另一个解释器"的那一刻**。
   我们的对应面：栅格里**永远存原码点**（现在就是这样），`spool`/`sql2csv`/`write_cache` 若将来从栅格取文本才需要
   同款映射。而 `WriteCharsLegacy:339` 的注释更直白："As a special favor to incompetent apps that attempt to
   display control chars, convert to corresponding OEM Glyph Chars" —— ConEmu #2158（`\x01` 画成 `☺`、复制出来变
   `U+263A`）在他们那里是**故意的**，但因为栅格存原码点 + `CharToColumnMapper` 按码点还原，复制不会坏。
   ⇒ 把这条写进 I14，作为"为什么我们不修 #2158"的正式答复。
2. `_stream.cpp:309-318`（LF）："If `DISABLE_NEWLINE_AUTO_RETURN` is not set, **any LF behaves like a CRLF**"，
   并且发 VT 时 `if (it == beg || it[-1] != '\r') { wch = 0; lastCharWrapped = true; }`
   —— **"我们不想发 CR CR LF"**。这两句是我们 `newline()`/块画那两条结论的权威版：
   裸 LF 折列（我们踩过）、`\r\n` 拼接时要看前一个字符是不是 CR。块画现在恒用 `"\r\n"` 拼（`Console.java:363`），
   如果哪天负载里出现以 `\r` 结尾的行尾，就会变成 `\r\r\n`。⚠ 未测。
3. `processed output` 关闭时（`:225-233`）"produce VT output but behave as if these control chars aren't
   control characters ⇒ **replace all control characters with whitespace**" —— 同一个"没人解释就别发控制码"的
   判断，落在不同分支上。它给我们的 `writeRaw(tail)` 兜底腿一个明确判据：**尾巴里若含 C0，先按这一档处理**。

## 9 门禁/证人可以抄的做法

1. **行级校验和当 A/B 判据**（S4）。`AdaptDispatch::RequestChecksumRectangularArea`
   （`adaptDispatch.cpp:1281+`）算 DEC 的矩形校验和，并且**把每格的颜色索引一起加进去**；默认色从 alias 表取，
   取不到 >15 就退回 "7 和 0"。我们现在全部活体判据是"逐行文本 diff + 数一下不同行数"（`native-ab.ps1`）。
   换成"每行 (Σch, Σattr) mod 2^16 + 行号"之后：① 敏感得多（颜色差异不再被 `GridDump` 的文字渲染吃掉）；
   ② 一屏一行日志；③ 可以直接回答"块画是不是一个 chunk 离开 JVM"以外的**另一半**——不，仍回答不了（那是
   传输层），但至少 `off/on/bug` 三腿的比较不再依赖肉眼读 `n=`（证人教义 §6.9a 那类假失败会消失）。
2. **测试夹具里成对翻转标志位**：`inc/test/CommonState.hpp:255` 的 `row.SetWrapForced(iRow & 1)` —— 一行真一行假，
   所有"软换行 vs 硬换行"的消费者立刻被压到。我们做 S5 的 `rowWrapped[]` 时用同一招。
3. **状态机自带 tracer**：`terminal/parser/tracing.hpp`（`ParserTracing::TraceStateChange/OnAction/OnExecute/
   OnEvent/CharInput`，`stateMachine.cpp` 里用 `_doTrace` 包裹状态转移），配套 `src/host/conhostv2_traceviewpp.tvpp`。
   我们要的"给定字符串→每字位格宽 vs 绘制宽度"（CONEMU_ANSI_DEFECTS §8 第 11 条）可以顺手做成同一形状：
   `DBCLI_RENDER_TRACE=<path>` 时把**每条被 dispatch 的序列 + 游标/属性前后值**写文件，而不是往屏幕上打。
   成本极低（只在 `csi_dispatch`/`esc_dispatch` 两个入口加 sink），收益是"字面 `[33m` 类缺陷"第一次有可查证据。
4. **fuzzing 目录是真的**：`terminal/parser/ft_fuzzer`、`ft_fuzzwrapper`、`runfuzz.bat`、`delfuzzpayload.bat` +
   `doc/fuzzing.md`；`host/ft_fuzzer` 另有一套。我们的 `check_resumable`（逐 UTF-16 unit 重喂全量语料）已经是
   它的穷人版；**下一步照它的做法**：把语料当 seed 做字节级随机插入/截断，断言只有两条不变量
   （不崩 + 每 chunk 的 `Σ(画出的格)` 与逐 unit 重喂一致）。不需要新工具，`RenderCheck` 里加一个带 PRNG 的用例即可。
5. `src/tools/vttests/{common,test-unicode,burrito}.py` —— 现成的转义语料生成器（`csi()/osc()/sgr_n()`；
   它自己会 `SetConsoleMode(ENABLE_VT_PROCESSING)` + 把 in/out CP 设成 65001）。
   我们的 `cache/pgcorpus` 只覆盖宽行/短行两形状；**可借它的用例目录**（尤其 emoji 族、方向键族）。⚠ 注意
   它**假设 VTP 可开**，我们的快路径故意不依赖 VTP，所以不能当神谕，只能当语料源。

## 10 性能：可抄的一个 + 可抄的三个反例

- **可抄**：`VtIo::Writer` 的形状 —— **一次 flush 一个 Writer，最后 `Submit()`**（`VtIo.hpp:19-58`）。
  我们目前是"每 chunk 三次 JNI + 每次 flush 一次 `view_of`（59 µs）"。上游的启示不是"攒字节"，而是
  §7.1 那条：**"要不要重读真控制台"应当由一个被维护的有效性标志决定**（它们宁可每行都
  `GetConsoleScreenBufferInfoEx` 的应用把"总是重读"逼成不可接受的开销，也不靠猜）。
  也就是说 §8.2 的正解是：**默认不读，除非 `modelSuspect`/形状未知/首帧**。这才是能真省掉 59 µs×帧数的做法，
  而不是"攒够 N 行再 flush"（那个直接和 I9 的 gutter 冲突）。
- **反例 1**：`f20cd3a9` "Add an efficient text stream write function (#14821)" 和 `a01500f0` "Rewrite ROW to be
  Unicode capable (#13626)" 都在优化**它们的**存储层（每行动态字符存储 + 偏移表）。我们的 `memcpy`/`build_row`
  已实测 1 ns/格、比 conhost 便宜两个数量级，§8.4 判定不必优化 —— **这两条不要抄**。
- **反例 2**：`f8b4e19e`（2026-03-18）"avoid committing rows just to figure out rendition, blink and cursor
  (#19984)"、`ed5b59d2`（2026-02-12）"render: stop calculating lineWrapped for PaintBufferLine (#19858)" 都是
  "把 paint 期的重复计算去掉"。我们 paint 期没有行提交成本，但**同型的问题我们有**：`rc_plan_paint` 每帧重算
  行宽/夹游标；可以照它们的思路缓存"上一帧的 paint 计划"，不过 §5 显示瓶颈在 `WriteConsoleOutputW`
  的 43 ns/格，**先别做**。
- **反例 3**：`04c33f35` "15x faster reflow in debug builds (#17550)" 与 reflow 一整套（#15701 重写
  `TextBuffer::Reflow`）解决的是"窗口宽度变化时把行重排"。我们是**缓冲区宽模型**（I7：一行=缓冲区一行，
  `winL` 变化 ⇒ 下一帧 NOGEOM ⇒ 收养），从原理上没有 reflow 问题。⚠ 但 `winL` 一变全帧重画这个代价
  与它们的 reflow 是同一笔钱的不同形态，值得知道存在。

## 11 明确不要抄（以及为什么）

| 上游的东西 | 不抄的理由 |
|---|---|
| 图位簇存储（#16916 `cb48babe`、`Cluster.hpp`、`CharToColumnMapper`） | 我们的存储单位是 CHAR_INFO（每格 1 WCHAR + LVB 位），换不掉：`WriteConsoleOutputW` 是接口 |
| 自己画字形（AtlasEngine/DxEngine、`SetFallbackMethod` 问字体宽度） | 画格由 ConEmu/conhost 做；我们的宽度神谕**必须是表**（用户裁定，[[feedback-width-oracle]]） |
| 页模型 `PageManager`/VT paging（#16615）、备用屏、DECSTBM、鼠标上报、KKP、DRCS/sixel（#10011 #9307 #20409 #20607） | I19 现在只计数。要支持得先回答"ConEmuHk 会不会同时解析"，那是双解析器问题，不是工作量问题 |
| ConPTY 的"把缓冲重写成 VT 发出去"（`VtIo`、`e5182fb3` #4415、#5398） | 我们的输出目标是栅格不是 VT 流；**但 §8 那三条卫生规则和 §7.1 的标脏是从这里学的**，两者不冲突 |
| `WriteCharsLegacy` 的完整实现（tab/BS/LF/CP437/`SnapOnOutput`） | 它是"无 VTP 的 console API 世界"的路径，正是 ConEmuHk 干的活；我们抄它的**判据**（§2.3、§7.3、§8）而不是它的代码 |
| 它的 16 色 → COLORREF 折叠、`ColorAlias` 表 | I15 的折叠必须跟 ConEmu 的 `Far3Color` 一致（实测 633 样本已钉），上游没有这个约束 |

## 12 与 `CONEMU_ANSI_DEFECTS.md` 的增量对照（只列本文带来的新处置）

| 清单条目 | 原处置 | 看过上游之后 |
|---|---|---|
| #2404 / #407 / #1873 / #2116 | 【修】"把到右缘做成显式状态，单独测只写 1 个字符" | 现在有了**可直接抄的完整状态机**（§2.1）与**四条判别输入**（§2.2），并且诱因 PR 已确认 = 他们自己的 DECAWM #3943 |
| #852 / #1900 / #951 / #1827 / #2158 退格+控制字符家族 | 【修】 | 退格那一半：上游原语 `_adjustBackward`（§3）+ 我们自己的 `g->cx--` 缺陷；控制字符那一半：**栅格存原码点、出口消毒**（§8.1），#2158 从"待修"改成"文档化的正确行为" |
| #1330 / #739 / #2458 宽度≠advance | 【修】 | 上游立场：**这是无解的两侧计算不一致**（#19864 提交说明），我们要的是自洽 + 记档，不是与字体一致 |
| #227 属性进不进 scrollback | 【先定方向】 | 上游属性**每格一份、随 buffer 走**（`TextAttribute` 存在行里 + `1ce22a87` 把 legacy 与 extended 属性合并）⇒ 方向可定："属性随行保留"，但我们的**画**只到 `paintCols`，与它无关 |
| #1068 / #1380 / #2246 / #2302 能力/模式不同源 | 【修】 | 范式：**不同步就报不支持**（§7.2）+ 模式切换前**先落地延迟状态**（§7.3） |
| #687 OSC 可执行 / #2624 OSC 52 | 【安全：默认关】 | 具体形状：`OptionalFeature` 三项、默认 false、由客户端设置开（§7.4） |
| #317 软换行≠栅格行 | 【修·缺口】 | S5 的 `rowWrapped` 位就是它的前置；上游用法见 `textBuffer.cpp:2401`（复制时只有硬换行才加换行） |
| §8 第 11 条"抄一个 -CheckUnicode 诊断" | 【建议】 | 有更好的模板：`ParserTracing` + `.tvpp`（§9.3），并且我们缺的不只是宽度，还有"谁 dispatch 了什么" |

## 13 上游实现得**比我们好**的地方（B1–B7，交主任务逐条裁决）

用户 2026-09-23 追问的一句话清单："哪些地方它做得比我们好"。每条都给了**上游的真坐标**（今天 grep 复核）与
**我们对应的那一处**，并明确标出可抄 / 不可抄。**只有 B2 值得排进本轮**，理由在它的建议行里。

| # | 它更好在哪 | 上游证据 | 我们的现状 | 可抄？ |
|---|---|---|---|---|
| B1 | 一行 = 文本 / 偏移 / 属性**三份分离**，属性还是 RLE | `Row.hpp:20`、`:285-311`、`:309` | 稠密 4 B/格、属性每格一份（`Render.h:67`、DESIGN §5 的 4 MB/句柄） | 结构不能抄，效果（B2/B6）能 |
| **B2** | **脏与画的粒度是 run/矩形，不是整行** | `IRenderEngine.hpp:81/:92/:68/:73`、`gdi/invalidate.cpp:29-41` | ~~脏 = 一行，画 = 填满 `paintCols`~~ **已改**：脏 = 一行 + 一个列区间（`Render.h:132` `dirtyLo/dirtyHi`），画 = 发那个矩形（`RenderJni.cpp:160/:170`）；`paintCols` 降级成"几何判断与上界"，不再是每 run 的宽度 | **已抄**（= DESIGN I22，见 §13.1 末段的落地记录） |
| B3 | 字形边界退格是**具名原语** | `Row.cpp:373-376`（`NavigateToPrevious` → `_adjustBackward`） | BS 内联 `g->cx--`（`Render.cpp:580`） | 抄（= §1 的 S1） |
| B4 | 软换行是**行上的两个独立位** | `Row.hpp:313-317`（`_wrapForced` / `_doubleBytePadded`） | 只有 `rowDirty`，两条换行出口（`Render.cpp:255`、`:274-279`）事后不可辨 | 抄（= S5，顺手把两个来源分开） |
| B5 | 参数"缺席"与"0"在**类型层**区分（`optional`），子参数另有区间表 | `stateMachine.cpp:505-545`（`_parameterLimitOverflowed`、`_subParameterRanges`） | `g->digit` 已保住"trailing empty ≠ 0"（`Render.cpp:775`）；`:` 按 ConEmu 口径当 Pvt 整条丢（`Render.cpp:441,761`） | **不抄**，改成定性记档（见下） |
| B6 | 行宽是**数据**（`_columnCount`）不是常量 | `Row.hpp:309` | `cols = bufW - winL`，每行按它算（I7） | B2 落地后代价为 0，先不单独做 |
| B7 | （反面自查）**两条"看着更好"的**：问字体要宽度、resize 时 reflow | `IRenderEngine.hpp:94`、`TextBuffer::ReflowRows` | 我们画不了字形（抄了就是 #1330 的成因）、没有 scrollback 所有权（只能 `align()` 收养，I4） | **明确不抄**，列出来是防"见好就抄" |

### 13.1 B2 详述：唯一一条"更便宜 + 打在我们最贵的形状上"

现状链：`mark_dirty(g, row)` 连列号都不接（`Render.cpp:148-151`）→ `rowDirty[RC_MAX_ROWS]` 一个字节一行（`Render.h:114`）
→ `build_row`（`RenderJni.cpp:151-154`）按 `paintCols` 填满一整行 CHAR_INFO → `write_rect`（`:161-175`，
`size.X = p->paintCols` :166、`rect.Right = winL + paintCols - 1` :171）→ `WriteConsoleOutputW`（`:175`）。
于是**一行里改一个字符，代价与改满一行相同**。按 §5 自己测出来的 43 ns/格，默认 profile（2000 列缓冲区）上
一个字符 = 2000×43 ns ≈ **86 µs/行**；§5 那句"30 行 ≈ 2.7 ms"是同一件事的整屏版。上游的对应物是
`PaintBufferLine(span<const Cluster>, coord, fTrimLeft)`——一行递过去的是一串 run（外加"尾部空格可裁"这个提示），
脏区走 `GetDirtyArea` 的**矩形列表**，滚动则只把脏矩形平移（`invalidate.cpp:29-41`，`_szInvalidScroll` 累加 delta）。

最小实现：`rowDirty[]` 旁边加 `uint16_t dirtyLo[]` / `dirtyHi[]`，`mark_dirty` 接 `(col, w)` 并取 min/max，
`write_rect` 的矩形从 `[0, paintCols)` 变成 `[lo, hi]`。**四处必须一起改对**（漏一处就是画漏/画错，且只会以
"偶发残影"的形式出现，很难看）：

1. `scroll_up` 搬内容时也搬区间（`Render.cpp:217-218` 现在只搬 `rowDirty`）；
2. 新进视口的那几行是**未知**，区间必须置成整行（`Render.cpp:219-223`，`:221` 那一票）；
3. `fill_span`（擦除）按擦除区间标脏，不是"整行"（`Render.cpp:179`，它的 `from`/`to` 正是区间）；
4. `rc_mark_all_dirty`（`Render.cpp:160-165`）与 `rc_clear_dirty`（`:172-175`）保持整行语义。

另外注意 `Paint.cpp` 的 run 合并合的是**跨行**的竖带（`Paint.cpp:88-93` 把相邻脏行接成 `run[i].top/nrows`，
`:98-107` 超过 8 条退化成首末之间的一条带；`paintCols` 在 `:53` 定成 `bufW-winL`，`Paint.h:71` 的注释就是这条），
与这里的"每行一个列区间"是正交的两件事。所以真要做，得同时处理 `p->cells` 的预算口径（`Paint.cpp:114` 现在按
`nrows * paintCols` 数格子）和 `RenderJni.cpp:273-276` 那段 scratch 的 stride（现在钉在 `paintCols`）——
要么一条 run 内取"各行区间的并"当矩形左右界（简单、仍能砍掉大部分空白列），要么退化成每行一矩形（多花调用）。
别顺手只改 `write_rect`。

⚠ 未跑（**本条已作废，见下面"B2 落地记录"**）：以上只有行号是核过的，行为一条都没验。门禁侧要新增的不是"画对没有"，而是**"该画的都画了"**——
建议直接在 `RenderCheck` 里加"改一个字符 → 计划矩形恰好 1 格"与"改完再滚一行 → 计划矩形跟着平移"两条。

**这条不是 I7 的收窄**，模型仍按缓冲区宽存、仍能把 2000 列整行画出来，只是"没人碰过的列不再重写"。
但 I7 那句话是用户裁决出来的（§1 末），所以**动它之前请把这句判断原样读给裁决过的人听一遍**。

### 13.1.1 B2 落地记录（2026-09-23 22:0x，裁决复述"I7不收窄，继续"之后；DESIGN I22）

裁决读回通过之后开工。**那四处确实都改了，而且不止那四处** —— 真实改动面是 5 个文件，"约 10 行"是本文最大的
一处低估（同一句估算如果被当成工作量，会让人以为 `write_rect` 之外都不用想）：

1. `Render.h` —— `rowDirty[]` 旁边加 `dirtyLo[]/dirtyHi[]`，注释写明**这是画价规则、不是内存规则**（模型仍是整条
   缓冲区行，I7 一寸没收）。
2. `Render.cpp` —— `mark_dirty(g,row,from,to)`（夹到 `[0,cols-1]`，`from>to` 直接不算损伤）+ `mark_row_dirty`；
   `put_cell`/`put_pair` 交 `cx..cx+w-1`；`fill_span` 交它本来就有的 `from/to`；`scroll_up` **三个数组一起搬**、
   空出来的行说整行；`rc_mark_all_dirty` 从 gutter 起标整行（收养/复位不该被区间化）。
3. `Paint.h` —— `RcRun` 多 `{lo,hi}`，注释写明"合并取并集 ⇒ 只会画宽不会画漏"。
4. `Paint.cpp` —— 竖带合并同时取列并集；超过 8 条退化那条带也带**所有脏列的并**；`p->cells` 从 `nrows×paintCols`
   改成矩形真实面积（rollout 比的就是这个数）。
5. `RenderJni.cpp` —— `build_row`/`write_rect` 按 `lo..hi` 发，**scratch 的 stride 从此逐 run 变**（一条 run 内
   `w = hi-lo+1`）；分配量仍按 `paintCols × rows`，那是**上界**不是每帧用量。

两条本文没写、但落地时必须定的细节：① `write_rect` 的左界是 `v->winL + lo`，不是 `lo`——模型列 0 就是缓冲区列
`winL`（I7），窄矩形必须跟着这个平移，否则窗口一旦不在 0 列就整体画到左边去；② 建议的那两条门禁确实建了
（`plan_damage_range`：改一列 ⇒ `run[0].lo==hi==1500`、`cells==1`；平移 ⇒ 区间跟着行走），另加一条全量安全网
`check_damage_bounds`（124 语料 × 2 形状：每个 run 不出行、**每个脏行被它自己那档宽度里的某个 run 盖住**），
它测的正是本文说的"该画的都画了"。窄化的风险是**少画**（模型对、屏幕陈旧），而少画在别处不可见 ——
`grid_equal`（整喂 vs 续喂）现在也逐行比 `dirtyLo/dirtyHi`，这两条合起来才是这张网。
证人：host `checks=1984 fails=0`、真控制台 x86/x64 各 `checks=3733 failures=0`、三腿活体 A/B（lfbug + elbug）
与 2000 列缓冲区活体腿全绿，`lib\x86\x64\render.dll` 换到 `render-2026-09-23-4` 并按 hash 还原过。
控制腿按新主干重建后，elbug 那条的 host 失败数从 8 变 11 —— 多的 3 条正是新加的 EL 列区间断言，
这就是"门禁对这一处回退仍然敏感"的证据（总数 2000 > 主干 1984 也是同一件事：EMPTY 计划多计一票）。

### 13.2 B5 的处理方式：从"缺口"改成"有意的偏离"

`CSI … : …`（colon 子参数，`SGR 38:2::r:g:b`）我们**整条不吃色**——因为 `:` 落在 ConEmu 的 Pvt 字节范围里，
按平价规则等于"私有序列 ⇒ 丢弃"（`Render.cpp:441` 的注释已经把这条说明写死，`:761` 置 `g->priv`）。
上游用 `_subParameterRanges` 正经解析它。结论：**不抄**（单解析器 + ConEmu 平价是本项目的立身之本，I10），
但要做两件事：让 `unsupported()`（I19）把"带 `:` 的 CSI"单独计一票，这样将来真有应用发 colon 形式时我们手里
有数；并把这条从 `CONEMU_ANSI_DEFECTS.md` 的"缺口"语气改成"已定性偏离 + 上游行号"。

## 14 再取数据的命令

```sh
# 只读；克隆已在工作区里，不需要网络
cd /d/dbcli/cache/msfterm && git log --pretty="%ad %h %s" --date=short -i --grep="DECRQM" | head
git show 14993db1   # 提前换行的删除（#18899）
git show 8a26f141   # ReadConsoleOutput 破坏性变更（#13321）
git show 3b8c5606   # ambiguous 宽度策略（#19864）
grep -n "DelayEOLWrap" -r src | head
```

上游匿名 API 可用（`export CURL_CA_BUNDLE=/mingw64/ssl/certs/ca-bundle.crt`，限额 60/时）；
`gh` 未安装。仓库 130 MB（含 `.git` 与 blob）。**它是只读参照，不是依赖**：不要把它链进 `build.sh`，
也不要往 `src/c/conemu` 里 include 它的头。
