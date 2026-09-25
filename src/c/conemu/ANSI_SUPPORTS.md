# ANSI_SUPPORTS — C 端（render.dll）ANSI 转义支持矩阵

快照 2026-09-25。事实来源是**代码本身**：`Render.cpp`（解析 + 栅格模型）、`Render.h`（状态与计数器）、
`Paint.cpp`（把模型落成控制台调用）、`RenderJni.cpp`（JNI 落笔、标题、查询应答）。
上游对照是 ConEmu `Ansi.cpp`（逐条在注释里标了行号）；OSC 133 以 ghostty 与 MSFT terminal 为参照实现。
不支持的特性**从不静默**：一律消费掉、按族计数（I19），只有"本 switch 无 case 的 final 字节"才会把帧标为
`modelSuspect`、让 painter 对控制台重收养一次（自愈）。

解析单位是 **UTF-16 code unit**；`rc_feed()`（Render.cpp:1707）是可续接状态机，跨 chunk 断开的序列下轮接着解析，
不存在 ConEmu `gsPrevAnsiPart` 那个 512 字节 reparse 截断窗（偏离 #2）。

---

## 1 结构性能力（解析框架）

| 能力 | 行为 |
|---|---|
| 状态机 | `RC_GROUND / RC_ESC / RC_ESC_INTERIM / RC_CSI / RC_OSC / RC_OSC_ESC`（Render.h:370） |
| CSI 字节分类 | 参数 `0x30..0x3F`（含 `;` 与私钥 `? > < = / :`）、中间字节 `0x20..0x2F`（DECSCUSR 的空格、DECSTR 的 `!`；累积成集合，见 §2.6）、final `0x40..0x7E` |
| 参数个数 | 上限 `RC_CSI_ARGS 16`，超出的参数**丢弃不拒绝**（与 ConEmu ArgV 同） |
| 参数数值 | 数字累加**饱和在 65535**（偏离 #3：上游是 int 溢出）；`;` 空参数补 0；结尾空参数**不**当 0 下发 |
| `arg()` 语义 | 参数缺省或为 0 时取默认值（如 `CSI 0 A` = `CSI A`） |
| OSC/DCS 载荷 | `BEL` 或 `ST(ESC \)` 终止；被 `ESC`/`CAN`/`SUB` 遗弃时**计数、不生效**；收集上限 `RC_OSC_MAX 32768` 个单元，超出后**标题截断到 `RC_TITLE_MAX 256` 并计数，OSC 52 整条拒绝**（一个被腰斩的 base64 不是一条消息），序列本身照常消费 |
| OSC 码读取 | 按前导数字串精确匹配（`"0133"` 不匹配 `"133"`），超界饱和，防 `]0133;A`/`]1334;A` 误命中 |
| CAN/SUB | 在 CSI 或 OSC 内到达时中止序列回 ground，被中止的半个序列不计任何账 |
| 未知序列 | 消费 + 按族计数（见 §6 census）；`RC_UN_SUP` 且来自 `default:` 臂时置 `modelSuspect` |

---

## 2 支持的特性

### 2.1 C0 控制字符（`control()`，Render.cpp:1323）

| 码 | 行为 |
|---|---|
| `BEL 0x07` | 不占格、不响铃 |
| `BS 0x08` | 左移不擦除；落在宽字形尾半格上时再退一格（`step_back_col`，Render.cpp:904，对应上游 `Row::_adjustBackward`；这正是 #852 族的正确侧） |
| `HT 0x09` | 固定 **8 列** 制表，钳到行尾；制表位不可配置（见 §3） |
| `LF 0x0A` | 换行**并折到第 0 列**（conhost 行为，实测 WriteConsoleW 语义）；`IND`/`RI` 保持列 |
| `CR 0x0D` | 回第 0 列 |
| 其余 C0 与 `DEL 0x7F` | 忽略，**永不渲染成字形**（#1900/#2158 族的答案） |
| C1 `0x80..0x9F` | **不解释为控制字符**，按普通码点走宽度表（Cf 类判 0 格，落不到屏上） |

### 2.2 ESC 序列（`esc_dispatch()`，Render.cpp:1254）

| 序列 | 名称 | 行为 |
|---|---|---|
| `ESC 7` / `ESC 8` | DECSC/DECRC | 只存取光标坐标，**属性不保存**（上游一致，Ansi.cpp:2719） |
| `ESC c` | RIS | 全复位（见 `full_reset()`，Render.cpp:882：退出备屏、SGR 复位、清滚动区与光标形状、把视口内容上滚进历史、光标归位） |
| `ESC D` | IND | 下移一行；列不动。本模型让它**感知滚动区**（上游 ForwardLF 反而不看区域——为一致性保留的偏离） |
| `ESC E` | NEL | CR + IND |
| `ESC M` | RI | 反向换行；在视口顶或滚动区顶时**插入空行**（上游 LinesInsert 语义）；区外光标只移动 |
| `ESC ( 0` | SCACS | 激活 G0 制表符替换（`G0_DRAWING` 31 项，仅 `0x60..0x7E` 重映射，宽度按原字母算，边框每字母仍 1 格）；`ESC ( B` 及任何其他设计符恢复默认 |
| `ESC N` / `ESC O` | SS2/SS3 | 只吞引导符，**下一个字节按普通文本打印**（不吞字，不丢列） |
| `ESC g` / `ESC H` / `ESC =` / `ESC >` | 视觉铃/HTS/keypad | 计数（`RC_UN_MODE`），不动格、不换输入侧 |
| `ESC ) c`、`ESC % G` | G1 / UTF-8 选择 | 计数（`RC_UN_SUP`）；G1 不可达、UTF-8 旗标从不设置（输入本就是 UTF-16）——与上游 default 臂一致 |

### 2.3 CSI 光标移动（`csi_dispatch()`，Render.cpp:913）

| 序列 | 名称 | 行为 |
|---|---|---|
| `CSI A` / `CSI B` | CUU/CUD | 垂直移动，`move_row()` 按**滚动区**裁剪（区外光标交给视口边界） |
| `CSI C` / `CSI D` | CUF/CUB | 水平移动；`D` 落在宽字形尾半格上时再退一格（同 BS） |
| `CSI E` / `CSI F` | CNL/CPL | 垂直移动 + 第 0 列 |
| `CSI G` | CHA | 绝对列（1 基） |
| `CSI H` / `CSI f` | CUP | 行列定位，**视口相对**（永不落进 scrollback gutter），双向钳制 |
| `CSI d` | VPA | 绝对行（视口相对） |
| `CSI a` | HPR | 相对**列**移动，**视口**钳制、不受滚动区约束（MSFT `adaptDispatch.cpp:427` "Unlike CUF/CUD, this is not constrained by margin settings"）；缺参/0 参按 1 |
| `CSI e` | VPR | 相对**行**移动，同上：走 `clxy`（视口）不走 `move_row`（区域），故能从钉住的滚动区底走出去；列保持不变，这是它与 `CSI B` 唯一的行为差别 |
| `CSI s` / `CSI u` | 保存/恢复光标 | `u` 只在**无私钥**时恢复（`CSI ?u` 是 kitty 的能力查询，上游无私钥门，属缺陷：探测批每轮把光标瞬移到 DECSC 位） |
| `CSI ?1048 h/l` | 存/取光标 | 与 DECSC/DECRC 同槽 |

### 2.4 CSI 编辑 / 擦除 / 滚动

| 序列 | 名称 | 行为 |
|---|---|---|
| `CSI J` 0/1/2 | ED | 擦屏，**止于视口**（scrollback 不动）；2 号顺带把光标归到视口左上（上游 2J 归位行为） |
| `CSI K` 0/1/2 | EL | 擦行，整行=整条**缓冲区行**（cols 即 buffer 宽，I7）；擦到行尾会清掉该行的折行声明 |
| `CSI L` / `CSI M` | IL/DL | 有滚动区时区内平移、区外光标**拒绝**；无区时视口内平移；`n` 超出按跨度钳制（上游会写越区底，属缺陷不抄） |
| `CSI @` / `CSI P` | ICH/DCH | 行内开槽/收拢，LEADING/TRAILING 半格整体随移（与上游对同一对的做法一致），文本推过行尾不可回捞 |
| `CSI X` | ECH | 擦 n 格，**可跨到后续行**（ConEmu 语义），但钳制量修正为"真实剩余格数"且止于视口底（上游公式差一格，偏离）；`CSI 0 X` 擦 0 格 |
| `CSI b` | REP | 重放 `lastUnit`：按文本走（可折行、吃当前属性与字符集重映射、宽字形占 2 格）；重复的是**重映射前**的码点（`ESC ( 0` 后 repeat 出线框字形而非字母）；`CSI 0 b` 不重复；私钥形式拒绝并计数 |
| `CSI S` / `CSI T` | SU/SD | 滚动区上/下移；无区（或区=视口）时 SU 走整模型滚动（带动 gutter 与控制台滚动），SD 不动光标 |
| `CSI r` | DECSTBM | 建滚动区。**缺省参数取视口边缘**：`CSI 3r` = 3..末行、`CSI ;4r` = 1..4（两家参照一致：MSFT `adaptDispatch.cpp:2243-2257`，注释 :2239 明写 `[3;r -> 3,h`）；**反序参数被忽略而不是清区**（`3;2r` 保持原区，MSFT :2242 "an illegal combo … is ignored"）——清区与忽略不是同一个动作，清区会把下一条 LF 交给整个视口，正是 #47/#48 那类故障的另一个触发器。这两条都是 2026-09-25 复核"上游也不做"式理由时改掉的：上游 `Ansi.cpp:3142` 要求 `ArgC>=2`，否则 `SetScrollRegion(false)`。仍与上游一致、且与 MSFT 有意分歧的是**钳制**：底参越界拉回视口末行（MSFT :2260 直接拒绝）、`Pt==Pb` 接受为一行区（`Status.reset()` 到这里就是 `CSI 1;1r`，拒了会把状态行的区卡住）。另外：0 号参数钳到视口首行；设区**不归位光标**；`CSI ?r` 也接受；区恰为全视口时归一成"无区"（MSFT 为 `apt` 同样归一，:2262-2270）；参数视口相对，一次性钳死后不再重算（geometry 变更走重开，重开即无区） |

### 2.5 DEC 私有模式（`CSI ? Pm h/l`）

只读 `args[0]`（上游只看 ArgV[0]，`?1;2004h` 只作用于 1）：

| 模式 | 行为 |
|---|---|
| `?25 h/l` | 光标显隐 → painter 的 `SetConsoleCursorInfo`，仅真实变化时调用 |
| `?47` / `?1047` / `?1049` | 备用屏，**三种同一行为**（对齐 MSFT `ASB_AlternateScreenBuffer`）：进入时快照主视口行（含折行与 FTCS 标记）、清视口；离开时还原并恢复光标；没进入就离开是安全的；备屏无 scrollback，滚出顶部的行即消失、滚动不花控制台滚动；唯一拒绝是快照 malloc 失败（计数 `RC_UN_ALTBUF`） |
| `?1048 h/l` | 只存/取光标 |
| `?2026 h/l` | **同步输出**（BSU/ESU）。区域内在屏计划全部推迟：`flush()` 解析照做、模型照更新，但不碰控制台，脏格保持到区域结束，收尾那一次刷出**整个联合**（每行一个矩形，一帧到位）。第一个带内容的 chunk 也推迟——应用写 BSU 时通常已经把新屏顶部一起写出来了。三个出口：ESU（正常）、**100 ms 时钟**（`RC_SYNC_TIMEOUT_MS`，MSFT `renderer.cpp:542` 同值；到点这一帧照画并**清模式**，泄漏 BSU 的应用不能把整场会话一帧一帧吞掉）、**scrollback gutter 满**（`pendingScrolls` 到达 `rc_scroll_room`，此时这一帧必须落地否则历史被逐掉，但**区域保持打开**）。空计划（纯状态/纯光标移动）不算推迟；查询应答**照发**（CPR/DA 是关于读端的事实，等 ESU 会把发问的程序挂住）；`RIS`/`DECSTR` 清位。计数族见 §6：engages/nested/held/timeout/overflow/declined |
| 其余一切 | 计数 `RC_UN_MODE`（鼠标族 9/1000/1002..1015 与括号粘贴 2004 有**专属**计数器，见 §3/§6） |

私有的 `CSI ?7 h/l`（DECAWM）**已经作用**，见 §2.3 的换行模型与 I35（#61，build -22）；非私有的 `CSI 7 h/l` 是 GATM，仍然计数 `RC_UN_MODE`。剩下两条非私有模式的独立理由（"上游也没 case"不构成理由，见 #60 的复核）：**LNM(20)** 是**打印回显**——它改变的是"键入的字符何时进屏幕"，而本库不拥有输入句柄，也没有回显可管；**IRM(4)** 只改变后续 `CSI @`/`CSI P` 的语义，而我们与两家参照一样把 ICH/DCH 当**显式序列**（插入/删除永远照做），所以 IRM 在本模型里没有能改变行为的实体——这与"上游不做"不同：这里缺的是能力（一个有主的插入模式），不是意愿。DECAWM 曾经用同一个句式被拒，理由是"caps 声明了 `am`"；复核之后发现那是两件事：**caps 的 `am` 说的是宿主终端换不换行，而本模型的右缘是我们自己画的**，所以 `?7` 可以做而 `smam`/`rmam` 仍然不进 caps（那条 entry 同时描述 ConEmu 自己解析的会话，那边 `?7` 是被忽略的——I26）。

### 2.6 DECSCUSR 与 DECSTR

| 序列 | 行为 |
|---|---|
| `CSI Ps SP q` | DECSCUSR，1..6 存进 `cursorShape`；缺参/越界 = 0（上游"默认"，即不主动改高度）。painter 映射（`Paint.cpp:55`）：1/2 → 块状（高度 100），0 与 3..6 → 细条（高度 15）——Win7 可达的控制台 API 只有两档，条形折到下划线形与上游一致；**从未发过 `CSI q` 的会话不碰用户的光标高度**（-1 哨兵）。判据是**中间字节集合恰好等于那一个字节**：`CSI ? SP q`、`CSI ! SP q`、一长串空格后接 `q` 都不是 DECSCUSR，计数走 SUP |
| `CSI !p`（无参、无私有字节） | DECSTR = `full_reset()`（上游 FullReset 同一函数，是**硬**复位，比 VT 的软复位更狠）；带参的 `!p`、带 `?` 的 `?!p` 与其他 `p` 拼法计数 |
| 中间字节本身 | 累积成集合（`interims[RC_INTERIM_MAX]` + `nInterims`，超界丢弃），消费方按**整串精确比较**（`interim_is()` 要求长度 1）。上游就是这么做的：`Ansi.cpp:1788` 把 `0x20..0x2F` 与 `0x30..0x3F` 追加进同一个 `Pvt` 缓冲，`:3645`/`:3657` 都写成 `PvtLen == 1 && Pvt[0] == X`。单槽"最后一个赢"会让 `! SP q` 冒充真 DECSCUSR |

### 2.7 SGR（`sgr_apply()`，Render.cpp:646）

| 码 | 行为 |
|---|---|
| `0` | 全复位到**冻结的**默认属性（含 SGR 39/49 的默认色） |
| `1` | 粗体：只作为**提亮**参与 `rc_attr()`（`bold && !brightBack` 时给前景 nibble 补亮位）——xterm 家族的 bold→bright 语义，#1896 平价 |
| `2` / `22` | 取消粗体 |
| `4` / `24` | 下划线开/关 → 真落到 `RC_LVB_UNDERSCORE`，绘得出来 |
| `5` `6` / `25` | 闪烁：**无任何状态**（上游 Ansi.cpp:3530 同样无状态） |
| `7` / `27` | 反显开/关 → 真落到 `RC_LVB_REVERSE` |
| `3` / `23`、`9` / `29` | 斜体、删除线：**模型里存着**（`RcSgr.italic/crossed`），但传统控制台属性没有对应位，`rc_attr()` 不输出——不绘制（与 #677/#856 的上游缺口同形状，见 §3） |
| `39` / `49` | 默认前景/背景（4bit 空间、来自冻结默认） |
| `30..37` / `40..47` | 标准 16 色 |
| `90..97` / `100..107` | 亮色 |
| `38;5;n` / `48;5;n` | 256 色，`n & 0xFF` 掩码不查范围（上游同） |
| `38;2;r;g;b` / `48;2;r;g;b` | 真彩，`0x00BBGGRR` COLORREF 序 |

配套规则：

- **无参 `CSI m` = 复位**（按上游惯例记为假设，非实测平价）。
- **私钥前缀整条丢弃**（`?31m` 什么都不上色，计数 `RC_UN_MODE`）——上游 Ansi.cpp:3494 同样丢弃整条 SGR。
- **未知参数跳过后循环继续**：`\e[53;31m` 仍上红；截断的 `38/48`（`5`/`2` 后参数不足）不上色、剩余参数继续当普通 SGR 读。
- 参数上限 16、数值饱和 65535（偏离 #3）。
- **颜色管线**（I15）：`ReSetDisplayParm → ExtPrepareColor → Far3Color 折叠`，折叠表 `vendor/ConEmuRgbMap.h`（RgbMap[256]、ClrMap[8]）与 `vendor/ConEmuColors3.h` 从上游逐字提取、构建期断言条数；**fg==bg 避让**只在背景真走了 COLORREF 折叠（index>15）时挂上（633 样本测出的开关条件）。

### 2.8 OSC（`osc_finish()` 查 `rc_osc_families[]`，Render.cpp:2337）

分派是一张表而不是一条 `if` 链：每族 `{名字, owns(码), apply(...)}`，表的顺序即优先级，而"互不重叠"这件事现在由 `geo_osc_families` 扫 0..4096 证明——表能改成什么样，取决于有没有门禁在问它。链做不到的正是这条：说不出"没有哪个码被两族同时认领"。

| 码 | 行为 |
|---|---|
| `0` / `1` / `2` | **窗口标题真落地**：上游守卫逐字复刻（数字后必须紧跟 `;`，载荷非空，`]10;foo` 不是标题）；剥一层成对双引号（空串仍是标题）；painter `SetConsoleTitleW` 下发；超 `RC_TITLE_MAX 256` 截断并计数，**不丢序列**；未终止的标题计数不生效 |
| `133`（FTCS） | **一等公民**（`ftcs_apply()`，Render.cpp:1498）：`A`/`N` 起新提示行（需要时先换行——全族唯一动光标处）；`P` 定提示不动行；`L` 纯换行且**不允许带选项**；`B`/`I` 标输入起点（`I` 的输入止于行尾）；`C` 标输出起点并回收 fish 式续行标记；`D` 携退出码（第二字段，非数字按 MSFT 记为错误而非成功），向上搜索最近一个带标记的行盖 SUCCESS/ERROR 戳。`k=c`/`k=s` 选项识别续行（ghostty 规则）；LF/折行本身会把非输出内容所在行补成 CONTINUATION。行标记是**模型私有**的，随每次垂直移动搬运，收养（adopt）后丢弃 |
| `9`（ConEmu 私有族，T7 已分治） | **安全子集存而不行**：`9;4` 存 `{state,progress}`（state>4 整条拒绝且不套用，progress>100 钳到 100，与 MSFT `adaptDispatch.cpp:3596-3605` 一致）、`9;9` 存路径（剥一对引号，非法字符＝整条拒绝，判据同 `til::is_legal_path`）、`9;12` 直接走 `ftcs_apply("B")`——即 `133;B` 那条码路，不留副本。两者只经 `NativeRenderer.taskbar()/workingDirectory()` **读出去**，本库不画任务栏（没有窗口）也不 `chdir`（输出流里的目录是数据不是命令）。**其余子命令一律计数 `RC_UN_OSC_PRIV`、永不执行**：`9;1` sleep、`9;2` MessageBox、`9;3` 改环境变量、`9;6` GuiMacro、`9;7` DoProcess——#687 的 RCE 保证不变。未终止的载荷在**被遗弃那一刻**计数（此前解析器还泡在里面，无从判定） |
| `4` / `10` / `11` / `104` / `110` / `111`（调色板，I34） | **真改控制台颜色**：语法照 MSFT（`OutputStateMachineEngine.cpp:955-1000`/`:1062-1092`）——`4` 是 `(索引;说明)*` 对、`?` 就地提问、`10/11` 每字段推进一个资源、`104` 无参清全表且**遇到第一个读不懂的索引就停**（MSFT:846 注明这是 xterm 而非 VTE 的选择）、`110/111` 只在空载荷时复位。说明形式 `#RGB`/`#RRGGBB`/`#RRRRGGGGBBBB`（宽度须三等分）与 `rgb:r/g/b`（各 1-4 位、宽度可不等），按位复制缩放到 8 位；**X11 颜色名不解析**，与任何读不懂的说明同样计 `RC_UN_OSC_OTHER`。索引 0..15 改的是**控制台属性色**（写回 `SetConsoleScreenBufferInfoEx`，见 §5 那一坑）并参与折叠；16..255 只改折叠目标。`10/11` 只能落成**索引**（4 位默认属性），所以查询答的是**生效色**而非请求色 |
| `52`（剪贴板，I36） | **默认关，且只有宿主能开**：`ANSI_CLIPBOARD=on\|1\|true\|yes` 在类初始化时读一次，或 `NativeRenderer.setClipboardPolicy(true)`；字节流里没有任何东西能触到这两个入口——这正是"关"意味着关的原因（census 分辨不出用户配过的终端和脚本配过的终端，策略因此不能由计数代替）。没有 ASK 档：本库没有窗口，也就没有可提问的地方。**读**（`52;c;?`）无论写的开关开着与否都拒绝——答复等于把用户最后复制的东西塞进控制台**输入流**，也就是下一行命令。选择字段只认 `c` 和空：这台机器只有一块剪贴板，ghostty 之所以能折叠 `p`/`s`/`q`/`0-7` 是因为 X11/macOS 真有那些寄存器（`stream_terminal.zig:678-682`）。base64 严格 RFC 4648：整条要么完全合法要么整条拒绝（绝不半个解码），载荷中间的空白是拒绝而非跳过，最后一组的闲置位必须为 0（`QR==` 那种"看着像 A 其实藏着字符"的尾巴被拒），解出 NUL 整条拒绝（`CF_UNICODETEXT` 以 NUL 结尾，存前缀等于给用户半截粘贴），UTF-8 用 `MB_ERR_INVALID_CHARS` 严校验后才转 UTF-16。**空载荷是"清空"这个动作**，不是"没有载荷"。拒绝分四类各自计数（解码/选择/读取/超长），`NativeRenderer` 的收尾行说得清是哪一类。`close()` **不**恢复剪贴板：在 open 时快照就等于读，而读正是被拒的那一半。**ConEmu 根本没有 OSC 52**（实测：`Ansi.cpp` 的 OSC 开关是 `switch (*Code.ArgSZ)`，只有 0/1/2/4/9… 没有 `case L'5'`）。**但两个参照终端都有，而且默认都是开的**：Windows Terminal 有 `OscActionCodes::SetClipboard = 52`（`OutputStateMachineEngine.hpp:222`→`.cpp:821-827`→`adaptDispatch.cpp:3302`），开关是 `compatibility.allowOSC52` / `AllowVtClipboardWrite`，**默认 true**（`ControlProperties.h:59`、`MTSMSettings.h:119`，读进 `Terminal.cpp:106`）；ghostty 的 `clipboard-write` 默认 `.allow`（`Config.zig:2459`）。所以本库的**默认关是有意偏离两个参照**，理由只能是自己的：那两家是**用户自己配置并对自己负责的终端**，配置项存在的前提就是有人打开过它；而一个嵌在别人 JVM 里的渲染库没有那份配置、也没有那个动作的同意方——沉默只能读成"没同意"，不能读成"同意"。能对齐的地方都对齐了：两家都**不答复读取**（WT 解析 `?` 后 `&& !queryClipboard` 直接丢掉，`.cpp:825`），ghostty 靠 `clipboard-read=.ask` 挡住，本库连挡带不答。**与 MSFT 的另一处有意分叉**：它把选择字段整个忽略（`:1097` 注释自陈 "Currently the first parameter `Pc` is ignored"），于是 `52;p;…` 也写剪贴板；本库照 ghostty 的语法表只认 `c` 与空，其余拒绝——折叠是在回答另一个问题，而 MSFT 自己的注释说那是没做完 |
| 其他一切（8/…） | 计数 `RC_UN_OSC_OTHER`——这条尾巴是不变量：**没有一族认领的码**才被它记账；被拒的 133 语法、未终止的 133、以及上面那些读不懂的说明也落在这里。52 已自立门户，它的拒绝记在 `RC_UN_OSC_CLIP` |

### 2.9 查询与应答（I29）

| 查询 | 应答（`reply_text()`，RenderJni.cpp:465） |
|---|---|
| `CSI 5 n` | `ESC [ 0 n`（ready） |
| `CSI 6 n` | `ESC [ row ; col R`，1 基、**按窗口顶**计（与 painter 同一套算术），答复的是**读到查询那一刻**的光标（队列条目快照，`printf '\e[6n\e[2;3H'` 报的是第 1 行） |
| `CSI c` / `CSI 0 c` | `ESC [ ?61;4;6;7;14;21;22;23;24;28;32;42c` —— **conhost 的身份串**（去掉了 `;52` 剪贴板位），不是 ConEmu 的 `?1;2c`：被拒的 chunk 会原样给 conhost 自己应答，一个会话不能见两个身份 |
| `CSI > c` / `CSI > 0 c` | `ESC [ >0;10;1c`（conhost 的 DA2） |
| `OSC 4;<i>;?` / `OSC 10;?` / `OSC 11;?` | `OSC 4;<i>;rgb:RRRR/GGGG/BBBB`（或无索引的 `10;rgb:…`），16 位分量＝字节 ×0x0101，ST 收尾——与 MSFT `adaptDispatch.cpp:3338`/`:3417` 同形。**答的是生效色**：默认色只有 4 位，所以报回来的是折叠后那个索引的颜色 |
| `CSI ? <mode> $ p` | `ESC [ ? <mode> ; <status> $ y`（DECRPM），**只答模型真持有的状态**：25 → `cursorVisible`、47/1047/1049 → `alt`（三种拼法同一个位，答案不能互相矛盾）、2026 → `sync`；状态只用 1（reset）与 2（set）。快照语义同 CPR（入队时定死：同一块里 `?2026h ?2026$p ?2026l` 仍答"当时是开的"）。上游没有这条应答（`Ansi.cpp:3650-3653` 把认不出的 `p` 全送 DumpUnknownEscape），做的理由是 jline4 的探测批——它按**模式号回查**应答（`parseDecrpm`，AbstractTerminal.java:675-690），不按位置读 |

机制：查询在解析时**入队**（FIFO，上限 `RC_REPORT_MAX 8`，满时拒绝并计数、不挤占旧条目）；painter 在**成功的 flush 末尾**把应答逐字符写成 `KEY_EVENT` 对写进 `CONIN$`（conhost 自己输出腿的同款合成方式），空 flush 也会写；**被拒（declined）的 chunk 不应答**（字节已回放给 conhost，二次应答就是脏输入）。

### 2.10 宽度、字形与折行

| 项 | 行为 |
|---|---|
| 宽度神谕 | `rc_width()`（Render.cpp:38）= `src/c/luauf8/ansi_width` 的 Unicode 15 表（jansi/JLine WCWidth 家族被明确排除）；控制字符 0、宽 2、普通 1 |
| EAW 裁决 | **Ambiguous 一律按宽**，减去 206 个六款字体实测一格的例外（`AMBIGUOUS_NARROW`：制表符/块元素/重音拉丁字母）；无 VS16 提升（`A\uFE0E` 与 `A` 同宽） |
| 零宽 | Mn/Me/Cf 不产生 cell、不占列（与 xterm/WT/glibc 一致；conhost 给组合符单独一格，**不从**） |
| 宽字形 | 占 2 格：前格 `LEADING` 后格 `TRAILING`，同码点；放不下时**整体折行**（`RC_WRAP_PAD`），不劈半 |
| 辅助平面 | 代理对还原成完整码点再定宽；落控制台是原码元对（不折成 U+FFFD）；chunk 边界的高代理由 `wantLow` 持有、下轮续接；孤立低代理写一格 U+FFFD |
| 折行 | **立即换行**（无延迟换行/pending-wrap）：四条判别式双腿实测一致（CONEMU_ANSI_DEFECTS §2 末，定案不做） |
| 软/硬换行区分 | 每行一位 `RC_WRAP_FORCED`（顶到右缘）/`RC_WRAP_PAD`（宽字形整体折）供复制/导出拼接用；不入 `CHAR_INFO`，收养后丢弃 |
| 擦除与属性 | 擦除**整格覆写**不合并，宽字形尾半格被擦即毁（I13，conhost 同） |

---

## 3 不支持的特性（均已消费 + 计数，见 §6）

### SGR / 颜色

| 项 | 行为 | 备注 |
|---|---|---|
| 闪烁 `5/6/25` | 无状态 | 上游同 |
| 斜体 `3/23`、删除线 `9/29` 的**绘制** | 状态存了，画不出来 | 传统属性无位；真要画需自绘（上游 #677/#856 缺口同源） |
| `8` 隐形、`53` 上划线、`21` 双下划线、`51/52` 边框、`58/59` 下划线颜色 | 落入"未知参数跳过" | 无对应模型状态 |
| **colon 子参数** `38:2::r:g:b`、`4:3` 等 | **整条序列丢弃**，计 `RC_UN_COLON` | `:` 在 ConEmu 属 Pvt 字节；这是 I10 平价决策（上游真解析它的是 Windows Terminal），计数是为了将来有应用真发 colon 形式时手里有数 |
| 256/24bit 色逐字节还原 | 支持，但**经 ConEmu 调色板折叠** | 与"真实色彩"有偏差是特性不是缺陷（#2516 复刻）；`48;2;…` 不退化为色号 8 |

### 定位与制表

| 项 | 行为 | 备注 |
|---|---|---|
| `CSI Z` CBT、`ESC H` HTS | 丢弃，计 `RC_UN_SUP` | **没有任何 tab-stop 状态**，所以 CBT 无处可退 |
| 制表位 | 仅 HT 固定 8 列，不可配置 | terminfo 侧相应不给 `cbt/hts/tbc` |
| 左右边距（DECLRMM/DECSLRM）、原点模式 DECOM | 计数 `RC_UN_MODE` | 未建模 |

### DEC/ANSI 模式

| 项 | 行为 | 备注 |
|---|---|---|
| `?1` DECCKM（应用光标键） | 计数 `RC_UN_MODE` | 只影响**输入侧**，本渲染器不碰输入编码 |
| 鼠标 `?9`、`?1000` `?1002` `?1003` `?1004` `?1005` `?1006` `?1015` | 计数 `RC_UN_MOUSE` | 不产生鼠标上报 |
| 括号粘贴 `?2004` | 计数 `RC_UN_DECBP`；无标记生产者（角色错位：粘贴执行者是 conhost QuickEdit，读取者是 jline 泵，DLL 是输出腿且**不得**读 CONIN$ 抢输入）| 可选升级：DLL 存位+DECRPM 应答+暴露，宿主输入泵做突发打标——见 ANSI_TODO §6 |
| 其余一切私有/ANSI 模式（含 `?6n` 之外的查询式、`?3`、`?12`、非私有的 `7` GATM、`4` IRM、`20` LNM） | 计数 `RC_UN_MODE` | 上游逐一核对过：要么无 case，要么 case 体为空/被注释；IRM 的真实替代是 `CSI @` 恒插入 |
| `CSI ? 6 n` 扩展 CPR | **故意不答**，计数 | 扩展问题答普通形式 = 报一个没问的位置；拒绝是不会错的选项 |
| `?2027$p` / `?2048$p` / `?1048$p` | **故意不答**，计数 `RC_UN_MODE` | 永久值 3/4 在 DEC/xterm 与 jline4 的文档里正好相反（`AbstractTerminal.java:663-667`），发哪一个都对一方说谎（2048 答"永久置位"＝宣称尺寸变化会进数据流）；1048 是存/取光标的**事件**，不是可报的状态。沉默对 jline4 就是 `NOT_SUPPORTED`，与 `?6n` 同一先例 |

### 报告与窗口

| 项 | 行为 | 备注 |
|---|---|---|
| `CSI t` 窗口操作（含像素尺寸上报 `14t`、字符尺寸 `18t/19t`） | 计数 `RC_UN_REPORT`，不答 | 像素尺寸需要不属于本库的窗口矩形；`18/19` 能答但尚无真实使用方（规则：真实写手在发才建模） |
| 带参数的 DA（`CSI > 0 ; 1 c` 等） | 计数 `RC_UN_REPORT` | 上游无此应答拼法 |
| OSC 8（超链接） | 计数 `RC_UN_OSC_OTHER` | **不支持**（#56，用户 2026-09-26 定案不做）：链接是**区间**不是 cell，得住在 `rowWrap[]` 旁边并继承 I20 那条永远读不回来的债；只做序列本身换不到用户看得见的一件事。OSC 52 已于 I36 落地（§2.8），不在本行；调色板族 4/10/11/104/110/111 已于 I34 落地，也不在 |
| ConEmu 私有 OSC `9` 的**危险半区**（`9;1` sleep / `9;2` MessageBox / `9;3` 改环境变量 / `9;6` GuiMacro / `9;7` **DoProcess**） | 计数 `RC_UN_OSC_PRIV`，**永不执行** | #687 RCE：实现其语义的唯一底线是不实现语义。安全半区 `9;4`/`9;9`/`9;12` 见 §2.8——存下来给人读，不等于执行 |

### 字符集与图形

| 项 | 行为 | 备注 |
|---|---|---|
| `ESC ) c` G1、`ESC % G` UTF-8 选择 | 计数 `RC_UN_SUP` | 上游 default 臂同；输入已是 UTF-16 |
| `ESC P/X/^/_`（DCS/SOS/PM/APC） | 载荷按 OSC 同款框架消费后**整体丢弃**，计 `RC_UN_DCS` | 无 Sixel/kitty 图形、无 XTGETTCAP |
| SS2/SS3 移位 | 只吞引导符，后续字节照常打印 | 不吞字是刻意的（吞了就丢一列） |

### 换行模型

| 项 | 行为 | 备注 |
|---|---|---|
| 延迟换行（pending wrap/DECAWM 推迟） | **不实现** | 四条判别式（满行后 CR+Y、BS+Y、EL、CUA+Y）双腿全部一致；改成延迟只会造出新分叉（#2404 族上游的缺陷温床）。与 `?7` 无关：那条推迟的是"填满最后一格后游标先留在原地"，本模型立即进下一格，关窗时也一样 |
| DECAWM `CSI ?7 h/l`（**已实现**，I35，#61） | 开=右缘换行（原样）；**关=末格被反复覆盖**：游标停在右缘、那一行**不记** `RC_WRAP_FORCED`、下面不起新行、放不下的字形**整颗丢**（并把那格清成空格） | 包裹是本模型的行为而不是 `ENABLE_WRAP_AT_EOL` 的行为，所以能实现。丢整颗 = MSFT `Row.cpp:474-494`（"Ignore the character..."）+ 它的防死锁守卫；窄字覆盖宽字前随后清掉后半个是 conhost 的 cluster trim（I16 的"字对是一个单位"）；游标绝不留在宽字后半内（`step_back_col` 那条规矩）。`RIS`/`DECSTR` 复位；resize 重建**保持**当前值（一次改尺寸不是"重新开始换行"的请求）；DECRQM `?7$p` 答 1/2；`?7` 不再进 `RC_UN_MODE`。**caps 里仍然没有** `smam`/`rmam`，理由见 §2.5 |

---

## 4 有意偏离 ConEmu 的清单（全部记录在案）

1. **ESC 遇到未完的 CSI/OSC → 遗弃并重开**（`\e[3\e[31m` 上红色；ConEmu 把 ESC 停驻在 Pvt 里继续吞，打印出 `31m` 文本）——Render.h 偏离 #1。
2. **可续接状态机取代 512 字节 reparse 窗**（上游的 reparse 会静默丢超限字节）——偏离 #2。
3. **参数累加饱和 65535**，不复刻上游 int 溢出——偏离 #3，仅在荒谬输入上有差。
4. **ECH 钳制修正**：用真实剩余格数（上游公式每行差一格，最后一列幸存）；跨行止于视口底。
5. **IL/DL 越区钳制**：n 超出区高时只清区内（上游按 `dwSize.X * n` 从光标行起写，会冲掉区底以下内容）。
6. **IND 区域感知**：上游 ForwardLF 不看滚动区；本模型让 LF/IND/NEL/RI 对"哪几行滚动"给同一答案。
7. **`move_row` 的区裁剪用模型坐标**：上游拿绝对缓冲行比窗口相对光标，差一个窗口位置。
8. **应答身份用 conhost 串**（DA1 `?61;…`、DA2 `>0;10;1`），不用 ConEmu 的 `?1;2c` / `>0;136;0`：被拒 chunk 由 conhost 亲自应答，身份必须一致。
9. **辅助平面存原码元**（`put_pair`），`REP` 存完整码点（上游 WCHAR 只存半代理，重放两次半字）。
10. **IL/DL 的区守卫**：光标不在区内时不作用。这不是"上游能做我们不做"，而是**我们更贴 VT**——xterm 与 MSFT 都只在区内生效；上游 ConEmu 允许光标悬在区上沿时越顶拉行，那是它自己的宽松。
11. **DECSTBM 的两处不再镜像上游**（2026-09-25 复核"上游也不做"式理由的结果）：单参数按缺省补边缘、反序参数忽略而非清区，两条都与 MSFT/xterm 一致而与 `Ansi.cpp:3142-3150` 不同；钳制与 `Pt==Pb` 容忍仍与上游一致（理由见 §2.4 该行）。
12. **`SetConsoleScreenBufferInfoEx` 的往返会吃掉一行窗口**（2026-09-25 实测）：把 `Get` 读来的结构原样写回，`srWindow.Bottom` 从 29 变 28（30 行窗口变 29 行），下一帧规划器判定「控制台形状与模型不符」而**整帧拒绝**——设一个颜色就会缩用户的视口并从此不再作画；`close()` 里复位调色板时同样中招（24 行的那条腿读到 23 行）。对策是写回后用 `GetConsoleScreenBufferInfo` 比对，若动了就用 `SetConsoleScreenBufferSize`+`SetConsoleWindowInfo` 修回，两条路径共用同一个 `apply_palette`。**任何走 InfoEx 写路径的新特性都必须带这个修复。**

---

## 5 边界与上限

| 上限 | 值 | 越界行为 |
|---|---|---|
| `RC_MAX_COLS` | 4096 | `open()` 拒绝（OPEN_WIDE），调用方继续用旧 Java 写手 |
| `RC_MAX_ROWS` | 256 | 行数 ≥256 拒绝（OPEN_NO_GUTTER）；gutter 高度 = 行数 ≤128 时一整屏、129..255 递减 |
| `RC_CSI_ARGS` | 16 | 超出参数丢弃 |
| `RC_TITLE_MAX` | 256 | **套用**的标题长度：截断 + `nTitleTrunc` 计数，序列本身照常消费 |
| `RC_OSC_MAX` | 32768 | OSC/DCS 载荷**收集**上限（`nOsc` 单元）。越界后标题仍按 `RC_TITLE_MAX` 截断并计数；OSC 52 整条拒绝（`nClipBad`）——截断的 base64 不是消息 |
| `RC_CLIP_ENC_MAX` | 16384 | OSC 52 载荷的编码长度上限，超出即整条拒绝 |
| `RC_CLIP_MAX` | 12288 | 解码后的字节上限；`rc_clip_take` 的 cap 就是它，所以"装不下"在解析期就已判完 |
| `RC_REPORT_MAX` | 8 | 满队列**拒绝**新查询并计 `nReportFull`，不挤旧条目 |
| `RC_SGR_ECHO_MAX / RC_SGR_CAP_MAX` | 1024 / 64 | SGR 回显仅为证人存根，溢出计 `nSgrDrop`，不影响解析 |

---

## 6 计数器（census）一览（`RcUnsupported`，Render.h:78）

槽位序号是 JNI 侧**位置契约**，永不重编号。

| 计数器 | 触发 | 置 `modelSuspect`? |
|---|---|---|
| `RC_UN_SUP` | 本 switch 无 case 的 CSI/ESC final（`default:` 臂）⇒ **置疑**；以及已知惰性的 `Z/q 无空格/p 其他拼法`（走 `ignored()`）⇒ **不置疑** | 仅 default 臂 |
| `RC_UN_DECSTBM` | 死槽（`CSI r` 已建模），仅为位置契约保留 | 否 |
| `RC_UN_ALTBUF` | 备屏快照 malloc 失败 | 否（序列已消费、屏未动） |
| `RC_UN_MOUSE` | 鼠标模式族 | 否 |
| `RC_UN_MODE` | 私钥前缀 SGR、未建模的 DEC/ANSI 模式、ESC g/H/=/> 等 | 否 |
| `RC_UN_DECBP` | 括号粘贴 2004 | 否 |
| `RC_UN_OSC_PRIV` | ConEmu 私有 OSC 9（含未终止） | 否 |
| `RC_UN_OSC_OTHER` | 其他 OSC 码、未终止的标题、被拒/未终止的 133 | 否 |
| `RC_UN_DCS` | DCS/SOS/PM/APC | 否 |
| `RC_UN_REPORT` | 不答的查询（`CSI t`、带参 DA、`?6n`、非 5/6 的 DSR） | 否 |
| `RC_UN_COLON` | CSI 携带 `:`（每序列一票） | 否 |
| `RC_UN_OSC_CLIP` | OSC 52 被拒的四种理由之一：策略关、这台机器没有那块寄存器、载荷没通过严格解码、超出上限，或是一次**读取** | 否 |

配套动作：`modelSuspect` 置位后 painter 对控制台**重收养一次**再清位（自愈）；另有 `nTitleSet/nTitleTrunc`、`nClipSet/nClipBad/nClipSel/nClipRead`（+ painter 侧的 `g_clipCalls/g_clipFails`）、`nAltSwitch/nAltFail`、`nReportOk/nReportFail/nReportFull`、`nPromptMark` 等专项计数。第 12 个槽是 -24 加的，而 `STAT_TITLES = STAT_UNSUPPORTED + RC_UN_MAX`——所以**加一个槽会把后面每一族的偏移都挪一格**，`Render.java` 与 `NativeRenderer` 两张硬编码表必须同步 +1（真机门禁第一次跑出来的一片 0 就是这件事的收据）。

同步输出一族（`RcGrid`，不在 `RcUnsupported` 里：它们记的是"模式怎么用的"，不是"什么没建模"）：`nSyncEngages`（开过几个区域，是下面所有的分母）、`nSyncNested`（区域内的第二个 BSU）、`nSyncHeld`（被推迟的帧）、`nSyncTimeout`（时钟到点、顺带清模式）、`nSyncOverflow`（gutter 满、区域保留）、`nSyncDeclined`（chunk 被拒，区域结束并走重收养）。加上实时位 `sync`，共 7 个槽，`stats()` 尾部位置契约：`Render.java` 的 `S_SYNC*` 与 `NativeRenderer` 的 `SLOT_SYNC*` 必须与 `RenderJni.cpp` 的 `STAT_SYNC` 一起改，真控制台门禁有一条断言压着数组长度。
