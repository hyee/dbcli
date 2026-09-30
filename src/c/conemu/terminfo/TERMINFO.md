# TERMINFO — the terminfo side of the contract (`windows-conemu`)

This directory holds the terminal-definition half of the renderer's contract. The renderer paints whatever
bytes an application produces; **the entry is what the application produces them from**, so an entry that
over-claims makes the library a liar and one that under-claims makes features invisible. Both halves of that
judgement belong on the record, and until now the record was one long line inside a jline resource file plus a
harness in `cache/`.

| File | What it is | Authoritative for |
|---|---|---|
| `terminfo/windows-conemu.caps` | **mirror** of `org/jline/utils/windows-conemu.caps` — the file jline actually loads at run time (its copy lives in `terminal/src/main/resources/...` in the source tree and inside `lib/JLine3.jar`) | nothing; it exists so the three copies can be compared in one place. The master is jline's, and editing that master is a jline change (`JLINE_CHANGES.md`) |
| `terminfo/windows-conemu.ti` | the same capability set in **strict terminfo source**, which `tic` accepts and the `.caps` spelling does not | nothing; it is derived, and `terminfo_check.sh` refuses the build if it has drifted |
| `terminfo/infocmp-windows-conemu.txt` | `infocmp -x -1 -I` output of the compiled `.ti`, checked in | nothing; regenerate with `--refresh` |
| `terminfo/terminfo_check.sh` | the gate over all of the above | see below |

## Why a second spelling exists

`tic` cannot read the `.caps` file. Terminfo's first line is a `|`-separated names field, and everything after
the first newline is capability fields separated by commas — so the prose this project wrote into that first
line ("Kept out and why: hts and tbc … the boundary is which parser receives this name, not whether a reader
exists …") is parsed as capabilities and
rejected, field by field:

```
"windows-conemu.caps", line 1, col 622, terminal 'windows-conemu': Illegal character - ' '
"windows-conemu.caps", line 1, col 622, terminal 'windows-conemu': unknown capability 'hts'
"windows-conemu.caps", line 1, col 626, terminal 'windows-conemu': unknown capability 'and'
```

That is a property of the file, not a defect in it: jline runs its own parser and never asks ncurses. But it
means **no standard terminfo tool can be pointed at the entry the application uses**, and the entry this project
keeps asserting is "the terminfo entry for windows-conemu" is therefore unverifiable by the tools whose name it
borrows. `windows-conemu.ti` closes that gap, and `terminfo_check.sh` is what keeps the two spellings from
drifting apart silently — which is the only way a derived copy is ever allowed to exist.

## The gate

```sh
# From Git Bash; tic/infocmp live in WSL. The command this file printed until 2026-09-28 could not run, twice
# over: an `A=b cmd` prefix binds to the command it precedes, so with `JLINE_CAPS=... JAR=... tr -d ... | bash -s`
# the two assignments went to `tr` and the script that reads them saw an empty environment; and the script
# derived its root from `dirname "$0"`, which on the piped road is `bash`, so it walked up from the caller's cwd,
# fell off the top of the filesystem and died on `no //src/c/conemu/terminfo/windows-conemu.ti`.
# The root is now found by a marker file (src/c/conemu/terminfo/windows-conemu.ti), so the plain form runs:
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc \
  'tr -d "\r" < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
# the tr is not decoration: core.autocrlf=true with no .gitattributes means a checkout hands bash a CRLF script
# spell that as backslash-r: the version this file carried held a RAW carriage-return byte inside those quotes,
# which does work, and is invisible to every reader and every review of the diff
# add a flag after the pipe (`| bash -s -- --refresh`) to rewrite infocmp-windows-conemu.txt from the compile;
# --allow-no-jar opts out of the shipped-copy leg on a tree without one; DBCLI_ROOT, JAR and JLINE_CAPS point
# the gate at another tree or another jar, and they have to be EXPORTED, not written in front of the `tr`.
```

Four legs. Three were seen to fail on a deliberate mistake when they were written; the fourth had only been *assumed* able to, and had in fact been comparing nothing -- see leg 4.

All four ran green on 2026-09-28 and two arms were re-seen red rather than trusted from the last round: dropping `ech` from the mirror turns leg 2 red with the token printed on both sides, and running the script from a directory that holds no marker file refuses with the candidates it tried (`FAIL no dbcli root: nothing under[ cwd-up=/tmp]`) instead of inventing a root and then reporting a missing input file. `--refresh` is now idempotent: the dump used to carry the run's own `mktemp` directory in infocmp's header line, so every refresh dirtied the checkout on a line that means nothing, and real drift hid in that noise.

1. `tic -x` compiles the `.ti` with **no complaint at all** — a note counts, because ncurses' notes are how an
   unrecognised capability announces itself. (Red arm: an extra `kguom` line.)
2. The `.ti` and the mirrored `.caps` hold the **same 91 capabilities, spelled alike**. (Red arm: drop `ech`.)
3. `tic → infocmp` round-trips the same **capability names**. Names only, deliberately: `infocmp` writes values
   back in its own notation (`colors#0x100` for `colors#256`), so a value compare would fail on any entry ever
   compiled — while a capability that `tic` dropped or folded would show here. (Red arm: an `extended names`
   line that `tic` refuses.)
4. Three copies of the running entry agree **byte for byte**: the mirror, jline's source tree, and the copy
   inside `lib/JLine3.jar`. A green audit of a stale jar copy is DESIGN.md §6 rule 10 in another costume.

   **This leg compared nothing from the day it was written until 2026-09-26,** and the sentence above (and the
   claim under this heading that every leg was seen red) was inherited from the round that added it, never
   re-run. `JAR` was assigned in the shell and never `export`ed, so the python block that reads the jar saw an
   empty environment, printed `note JAR unset or missing` -- a note, not a failure -- and the script said
   `TERMINFO CHECK: ok` with one file compared against itself. It now exports `JAR` and `JLINE_CAPS` (with the
   source copy discovered from known candidates rather than guessed), prints `arm 3 compared N copies of the
   entry`, and **fails** when the shipped copy was not compared unless `--allow-no-jar` is passed explicitly.
   Two arms seen red the same day: editing the mirror's line 0 in a scratch tree turns both comparisons red
   (`89dea0736281 vs 4a3374c6838b`), and `JAR=/nonexistent` refuses with the reason rather than a note. The
   general rule is DESIGN §6's, and this is its fourth instance: **a comparing gate must assert that it
   compared**, because the failure mode of a comparison is not a wrong answer, it is no work at all.

```
     root resolved to: /mnt/d/dbcli
ok   tic -x compiles windows-conemu.ti with no complaint
ok   the .ti and the mirrored .caps hold the same 91 capabilities, spelled alike
ok   tic -> infocmp round-trips the same 91 capability names
     the shipped entry compared: /mnt/d/dbcli/lib/JLine3.jar
     arm 3 compared 3 copies of the entry
ok   the jline copy is byte-identical to the mirror (9454e34c5e67)
ok   the jar copy is byte-identical to the mirror (9454e34c5e67)
TERMINFO CHECK: ok
```

That block is the run, including the two information lines leg 4 prints to prove it compared something. It is
not the block this file carried, which said 90 capabilities, 84 round-tripped names and md5 `89dea0736281`:
the source leg counts comma-separated TOKENS and the round-trip leg counts NAMES, so the two only part
company when a name is spelled twice, and the entry's text has since moved (#90's citations, then this round's
de-rotting of the renderer anchors -- the md5 is a content hash of a file whose only changed half is prose).

## Who checks the bytes

`terminfo_check.sh` proves the **set**. The **meaning** of each string — what `cup(5,10)` or `csr(0,0)` turns
into on the wire after `%i` and the parameter packing — is asserted by the caps harness,
`src/c/conemu/CapsDump.java`, driven by `src/c/conemu/caps_check.ps1` -- twice, against the tree's
file and against the copy inside the jar, byte-compared. Its own census line carries the total, and the
total is 84 expectations on this entry -- not the 87 this file quoted, nor the 81 `caps_check.ps1`'s
header quoted. Neither number was a count of assertions: 87 was `expect(` occurrences in the source,
which includes the method's own definition, and 81 was whatever a previous round had copied into a
comment. One more assertion is printed by a bespoke line (the `rep` pin, which has no want= column to
fill), so the ok-lines outnumber the census by one: the census counts expectations, the screen counts lines.
It is the leg that caught `rep`'s parameter having to
reach `Curses.tputs` as an **int** (`toInteger()` parses a `Character` as a String and throws) and the leg that
named `change_scroll_region`'s `%i` as the reason `Status.reset()` arrives as `CSI 1;1r` rather than as a reset —
which is a capability fact with a behaviour attached, and the only reason the entry's `csr` is tolerable at all.

84 expectations do not cover 91 capabilities, and the file stops pretending they do. The census is computed
from what the harness named, not from what it meant to: a capability counts as asserted when its own
spelling occurs in an expectation label, and on this entry that is 49 of the 91. The rule has one known
generosity -- a name that appears only in an *omission* label ("flash NOT advertised") counts as touched,
so declaring `flash` is caught by the omission assertion and not by the census. Both arms were seen the
day the census went in: declaring `u8`, which no label mentions either way, reached
`NOT ASSERTED AND NOT EXPLAINED: u8`; dropping `msgr` while the table still explained it reached
`THE SILENCE TABLE CARRIES A NAME THE ENTRY NO LONGER DECLARES: msgr`; both exited non-zero. The 42 it leaves alone
fall into three groups, and the table the harness carries gives each one its reason. The transcript below is
abridged in one place -- the harness spells all 22 input-key names out, and they are shown as a range here --

```
census expectations=84 declared=91 asserted=49 unasserted=42 unexplained=0
  [colors, cols, it, lines, msgr] << number or boolean: there is no string for tputs to decode
  [kcub1, kcud1, kcuf1, kcuu1, kdch1, kich1, kend, khome, knp, kpp, kf1..kf12] << input leg: those bytes
      come from a console record matched against a KeyMap prefix, never from a caps lookup
  [bold, rev, smso, smul, cvvis, home, cub, cub1, cud, cuf, cuf1, cuu, cuu1, il1, dl1] << single-arm
      string this leg only ever reaches inside a sibling expectation (sgr, or the cursor family)
```

The middle group is the same set the table below calls not this library's surface, so the gap is a ruling
and not an oversight; the last group is the honest limitation -- those 15 sequences are pinned *indirectly*,
inside an expectation about `sgr` or the cursor family, and nobody has yet written the one-by-one version.
A capability added to the entry without an expectation and without a reason in that table turns the run red,
and so does a reason whose name has left the entry, which is what keeps the table from rotting into a list
nobody maintains. That is DESIGN section 6's rule for a comparing gate, applied to a checking one.

The harness has a third section, added for #90, and it is a different kind of check: it builds jline's headless
`LineDisciplineTerminal` with terminal type `windows-conemu`, which loads the entry **off the classpath** exactly
as a real session does (`AbstractTerminal.parseInfoCmp` → `InfoCmp.getInfoCmp`, and on Windows that call never
shells out to `infocmp` — `:604` — but falls through to the bundled resource), then asks the reader's own `menu`
keymap what Shift-Tab binds to. Everything else in the file reads a text file; this asks the shipped jar whether
a capability reaches a widget. Run it against the pre-#90 jar and it answers `no cbt to look up`; run it against
the shipped one and it answers `reverse-menu-complete`. Two notes for whoever edits it next: the keymap is
registered under `LineReader.MENU`, whose value is the lowercase `"menu"`, and `InfoCmp.getLoadedInfoCmp` is
**null** on this road (only the `infocmp` subprocess writes that cache), so the text to print is
`getDefaultInfoCmp`.

## What the renderer does with each group

Disposition of every declared capability; the citations are `ANSI_SUPPORTS.md` sections and the invariants
are `DESIGN.md` §3. Nothing here restates a rule that lives there.

| Group | Caps | render.dll |
|---|---|---|
| Booleans | `am` `bce` `msgr` | `am` is measured, not assumed: margin wrap is immediate, which is also why `xenl` is **absent** (§2.10, DESIGN I8/I35). `bce` is real: every erase fills with the **live** attribute (`fill_span`, §2.4), and `ech` inherits it. `msgr` is honoured by keeping moves and writes independent |
| Numbers | `colors#256` `cols#80` `it#8` `lines#24` `pairs#64` | 256-colour and 24-bit are supported **through the console's own fold** (§2.7); `it#8` is the **default** interval since #70, not the whole tab story: the table behind it is state, and `CSI 3g` clears it with the interval and `CSI 5g` puts both back (I38); `cols`/`lines` are geometry the painter reads from the console rather than from here (I7) |
| Cursor | `cup` `hpa` `vpa` `cuu``+1` `cud``+1` `cuf``+1` `cub``+1` `home` `sc` `rc` | §2.3. `%i`'s one-based spelling is why `hpa(0)` is `CSI 1G`; `sc`/`rc` are the model's two saved coordinates (§2.2), and DECSTR clears them (#67) |
| Erase | `clear` `el` `el1` `ed` `ech` | `clear` is `\E[H\E[2J` — ED **stops at the viewport**, so scrollback survives (§2.4). `ech` erases on its own row and nowhere else (#65). EL erases the whole *buffer* row, because a model row is a buffer row (I7) |
| Insert / delete / scroll | `ich` `ich1` `dch` `dch1` `il` `il1` `dl` `dl1` `ind` `indn` `rin` `ri` `nel` `csr` | §2.4. `il`/`dl` home the column afterwards (#64). `ich`/`dch` move a wide glyph as one unit and heal a pair the shift split (#66). `ind`/`ri`/`nel` agree about which rows scroll, where ConEmu's `ForwardLF` did not (§4 item 6). `csr` is the region (§2.4's long row) |
| Attributes | `sgr` `sgr0` `bold` `rev` `smul` `rmul` `smso` `rmso` `op` `setaf` `setab` | §2.7. `sgr0` is `\E(B\E[0m`, and the charset arm of it is honoured; `smso`/`rmso` land on `RC_LVB_REVERSE` like `rev`, so "standout" is reverse video here and nowhere else |
| Alt screen | `smcup` `rmcup` | `?1049` is one behaviour for all three spellings (§2.5), snapshots the main viewport's rows including wrap claims and FTCS marks, and has no scrollback (I24) |
| Repeat | `rep` | §2.4's REP row: it is *text*, so it wraps, takes the pen and the charset remap, and repeats only a unit with width (#69) |
| Charset | `smacs` `rmacs` `acsc` | `ESC ( 0` is modelled and `acsc` is what makes box drawing survive a session that never asked for Unicode (§2.2's charset row, pinned by `geo_jline_stream`) |
| Queries | `u6` `u7` | the only place this library writes back into the input stream (§2.9). `u6` is a **pattern** the reader compiles, not a string the host sends, and the private `CSI ? 6 n` stays refused on purpose. `DECRPM` (`CSI ? N $ p`, answered since #93 as 1=set / 2=reset and nothing else) has no terminfo name at all, so the entry says nothing about it and nothing here should be added to make it look covered |
| Input keys | `kbs` `kcbt` `kcuu1` `kcub1` `kcud1` `kcuf1` `khome` `kend` `kpp` `knp` `kdch1` `kich1` `kf1`–`kf12` | **not this library's surface**: keys arrive as console records, not as caps lookups. They are declared for jline's input leg, and every judgement about them (why `kbs=^H` stays, why `kf13`+ stay out) is in `DESIGN.md` §4 |

## The seven the upstream entry has and this one does not

`D:\Green\Github\jline4` ships a *different* `windows-conemu.caps`: 80 capabilities, of which this entry
declares 73, plus 18 this one adds and 8 spelled with different values. Someone reading the two side by side
will ask whether the seven are a gap, so the answer is per-capability and it names the consumer, because
"nobody in this tree reads it" is exactly the sentence that goes stale.

| Cap | jline4's reader | Verdict |
|---|---|---|
| `kmous` (`key_mouse`) | `MouseSupport.java:85` — `getStringCapability(key_mouse) != null` **is** the answer to "does this terminal do mouse events"; `AbstractTerminal.java:421/426` read reports through it. **This tree reads it too**, at the matching places: `MouseSupport.java:78` (the predicate), `:116` (the gate on writing `?1000h`/`?1005h`/`?1006h`), `AbstractTerminal.java:280/285` (the decoder) and `MouseSupport.keys()` `:619`, which folds the capability's own bytes into the prefixes a `KeyMap` matches | **Correctly absent -- and the reason this row carried was overtaken.** It said the mouse modes were *counted and not implemented* (`?9`, `?1000`–`?1006`, `ANSI_SUPPORTS.md` §3): since #81 they are stored (one bit per number), answered number by number through `?N$p` (#81, with #93 correcting the 1/2 vocabulary those answers use) and carried across a rebuild, and since #95 the console's own `ENABLE_MOUSE_INPUT` bit is borrowed and returned, so three of those four words are now false. The clause that carries the verdict is the one still standing: **this library never writes a mouse report** -- `RenderJni.cpp`'s reply leg has arms for DSR, CPR, DECRPM, WINOP, OSC, DA and DA2 and no arm for a report, and the census row says so out loud. Two facts a reader will otherwise get wrong next time: jline's Windows input leg does not need `kmous` to arm anything (`AbstractWindowsTerminal.trackMouse` sets the console bit itself, `:246-251`), and dbcli's own `WinSysTerminal` turns a `MOUSE_EVENT` record into `ESC [ M` bytes without consulting caps (`:480`, `:528`) -- so declaring `kmous` does not switch mouse support on, it makes the entry name bytes whose sender is somebody else, which is I26. ~~`ANSI_TODO.md` #95 owns the remainder: who owns the `CONIN$` read, then the reports, then this name~~ —— **那一半已经裁完了：#108 于 2026-09-28 选 ①**（读输入流的那一层拥有报告，本库永不编码），所以 `kmous` 不是"等实现落地再说"，是**永久不进本条目**；本轮还量到对面那条腿今天就在发 `ESC [ M`（`WinSysTerminal.java:526` 模板、`:559-561` 填满后 `slaveInputPipe.write(mouse)`），焦点同族在 `:517`/`:519-523`，只缺一个 `trackFocus(true)` 的调用者（整棵树 0 处）。见 `ANSI_TODO.md` 的 #95/#108/#116 三行 |
| `mir`, `ncv`, `blink`, `invis`, `rmpch`, `mc5i` | none — zero `Capability.<name>` readers anywhere in the jline4 tree; they survive only in `InfoCmp.java`'s name table | **Correctly absent.** `mir` would claim an insert mode that neither parser gives a body to; `blink`/`invis` claim SGR arms that hold no state on either leg (and `sgr` here deliberately drops those arms, unlike upstream's ten-parameter spelling); `ncv#3` is a claim about which attributes cannot coexist with colour, and the console's answer is carried by the fold in `rc_attr()` instead; `rmpch` is the PC alternate-font path this entry does not take (`rmacs=\E(B`, not `\E[10m`); `mc5i` is a printer |

The one that moved is worth more than the seven that did not, so it is stated at full length rather than as a row. **declared since #90**, and the reason the other seven are not: this one has a reader. `LineReaderImpl.java:6420` (in *this* tree — `:6992` is jline4's line, and the row that cited it here was citing the other tree) binds `REVERSE_MENU_COMPLETE` to `key(Capability.back_tab)`; `KeyMap.key` is `Curses.tputs` of `getStringCapability` (`:342`), and `KeyMap.bind` (`:589`) drops a null key sequence without a word. So the omission was never a refusal to claim something ConEmu's parser cannot honour — the value is read as the **name of the Shift-Tab key**, never written, and the bytes were already arriving from `kcbt` through `AbstractWindowsTerminal.java:368`, decoded at `:441`. Omitting it silently unbound a working key. The one sentence in this file that is now known to have been false: dbcli was said not to lose the key because `Console.java:295` binds `^[Z`; jline's key syntax reads `^[` as one ESC, so that binding is ESC+Z — two bytes, a different chord, and no cover for `ESC [ Z`. Witness: the harness's reader leg (§ "Who checks the bytes") reads `reverse-menu-complete` against the shipped jar and `no cbt to look up` against the pre-#90 one |

The 18 this entry adds are the renderer's own surface, and each has a section that owes it an explanation:
`bce` (erases fill with the live attribute), `csr` (the region, and the `%i` trap that makes `Status.reset()`
arrive as `CSI 1;1r`), `ich`/`ich1`/`dch`/`dch1`, `indn`/`rin`/`ri`/`nel`, `ht`, `smacs`/`acsc`, `vpa`,
`cnorm`, `rep`, and the query pair `u6`/`u7`. That enumeration is 18, and it used to read as 23: `ech`,
`il`/`dl` and their `1` forms were in the list, and diffing the two files on 2026-09-28 showed upstream
declares all five with the same value we use. A name shared with upstream is not an addition, however
much this build has had to learn what it does -- `il`/`dl` homing the column afterwards is #64 and `ech`
erasing on its own row is #65, and both belong to the group table above, not to this count.

Eight more are the *same* capability with a different value, and every one of those differences is a
decision: `clear` is `\E[H\E[2J` because ED must not eat scrollback, `setaf`/`setab` are the 256-colour
forms because the console fold is what we actually support, `sgr`/`sgr0` shed the arms that hold no state
and take the charset exit that does, `rmso`/`rmul` are `\E[27m`/`\E[24m` where upstream writes `\E[m` for
both -- a reset that also clears colour, bold and everything else the caller did not ask to clear, which
a model that tracks each attribute separately has no business doing -- and `rmacs` is `\E(B`, the
designation path, where upstream writes `\E[10m`, the font-selection path this entry does not take (the
same reason `rmpch` stays out).

## The omissions, and the rule behind them

The `.caps` first line lists what is *not* declared; that list is the record and this is the shape of it:
capabilities fall into three kinds of absence. **A claim about the *other* parser** — `hts`/`tbc` (moved out of
the "no reader" kind on 2026-09-28 by #113, which measured it instead of citing it: in a real ConEmu window
`cache/p113/tabprobe.py`, `ESC H` is not honoured -- a stop set at column 5 loses to the default interval, tab
still lands on 9 -- and neither `CSI Z` nor `CSI I` walks a stop table (they come back one column apart and at
column 0 respectively), while the *same* probe in a classic conhost with VTP on shows `ESC H`, `CSI 0g`, `CSI 3g`,
`CSI Z` and `CSI I` all behaving. This library models all five (`geo_tabs` is the leg: `ESC H` sets and does not
move the cursor, `0g`/`3g`/`5g` clear and restore, `CSI Z` walks back), so the names are true of one parser of
this name and false of the other -- and the entry is named after the one that drops them. Declaring them would
promise a tab stop that evaporates for a CEAnsi session (DESIGN I26). The honest way to say "we do have tab
stops" is a second entry that describes this library and nothing else; that is **#117**, still open, with the
work list attached there); `u8`/`u9` (`CursorSupport` reads `user6`/`user7` and nothing reads `user8`/`user9`, so a value would be invented --
and #86 found two harder reasons behind that one: ncurses spells `u8` as `\E[?%[;0123456789]c`, a **pattern**, while
this stack's DA1 is a fixed reply string, so "declared equals transmitted" can never hold for it
(spelled whole in `RenderJni.cpp`'s `reply_text`; no byte count is quoted in either file, because the
count this sentence carried -- 33 -- had already silently become 36 when the sixel term joined the
identification); `u9` is
`\E[c`, the DA **request**, so filing a DA2 answer there would lie to the other parser; and `%[` throws in our own
`Curses.tputs` (`Curses.java:425`)),
**A claim about the *other* parser** — `smam`/`rmam` (DECAWM is modelled here, `#61`, and ConEmu's own `?7` arm leaves `SetConsoleMode`
commented out), `initc`/`ccc` (OSC 4/10/11 now change the palette, `#55`, under this library and not under
ConEmu's parser). `smir`/`rmir`/`mir` belong to this kind, not the first: IRM **has** a body in this renderer since #77
(I40 -- one bit for both `CSI 4 h/l` and `CSI ?4 h/l`, reportable through `?4$p`, cleared by `RIS` and
by `DECSTR`, and a glyph written under it opens room for itself), so the sentence "IRM has no body, so `CSI @` always inserts" became false the day #77 landed and sat in two files until
2026-09-28. The pair stays out for the other parser's sake: CEAnsi files `CSI 4 h/l` as
recognised-and-ignored (`Ansi.cpp:3323-3329`), and the entry describes sessions that parser reads.
`kmous` joined this list the same day and is now named in the entry's own kept-out prose for the first
time -- the modes are modelled, the reports are not, and `ANSI_SUPPORTS.md` carries the disposition. This
is DESIGN I26 and it is the reason "we implement it now" is not by itself a reason to declare it: the
entry describes the session, and in a ConEmu-hosted session someone else may be reading the same bytes.
**#108 closed that "someone else" question on 2026-09-28 in favour of option ①**, so `kmous` is not on a
roadmap: the reader that owns the console records is in this very product (`WinSysTerminal.java:480` routes
`MOUSE_EVENT`, `:526` is the `ESC [ M` template, `:559-561` writes it into the slave input pipe), and a
capability naming bytes that second writer would send is a claim about a sender this entry is not. **No consumer** — `mc5p`, `flash`, the `sgr10`/`sgr11` font arms, `u8`/`u9` (both answered, and no
code in jline reads either), `blink`/`invis`/`ncv`.

The third kind is where a future reader should be careful in one direction only: *no consumer* is a claim about
this tree, and it goes stale the day someone writes a consumer. `caps`-adjacent decisions in
`../ANSI_TODO.md` are the place a claim gets re-opened; `terminfo_check.sh`'s capability set is where a
**change** becomes visible.
