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
line ("Kept out and why: cbt and hts/tbc — there is no tab-stop state anywhere…") is parsed as capabilities and
rejected, field by field:

```
"windows-conemu.caps", line 1, col 420: Illegal character - ' '
"windows-conemu.caps", line 1, col 424: unknown capability 'and'
```

That is a property of the file, not a defect in it: jline runs its own parser and never asks ncurses. But it
means **no standard terminfo tool can be pointed at the entry the application uses**, and the entry this project
keeps asserting is "the terminfo entry for windows-conemu" is therefore unverifiable by the tools whose name it
borrows. `windows-conemu.ti` closes that gap, and `terminfo_check.sh` is what keeps the two spellings from
drifting apart silently — which is the only way a derived copy is ever allowed to exist.

## The gate

```sh
# from Git Bash (tic/infocmp live in WSL)
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc \
  'JLINE_CAPS=/mnt/d/JavaProjects/jline3.29/terminal/src/main/resources/org/jline/utils/windows-conemu.caps \
   JAR=/mnt/d/dbcli/lib/JLine3.jar tr -d '' < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
# the tr is not decoration: core.autocrlf=true with no .gitattributes means a checkout hands bash a CRLF script
# add --refresh after changing the entry, to rewrite infocmp-windows-conemu.txt
```

Four legs, and each was seen to fail on a deliberate mistake rather than assumed to work:

1. `tic -x` compiles the `.ti` with **no complaint at all** — a note counts, because ncurses' notes are how an
   unrecognised capability announces itself. (Red arm: an extra `kguom` line.)
2. The `.ti` and the mirrored `.caps` hold the **same 90 capabilities, spelled alike**. (Red arm: drop `ech`.)
3. `tic → infocmp` round-trips the same **capability names**. Names only, deliberately: `infocmp` writes values
   back in its own notation (`colors#0x100` for `colors#256`), so a value compare would fail on any entry ever
   compiled — while a capability that `tic` dropped or folded would show here. (Red arm: an `extended names`
   line that `tic` refuses.)
4. Three copies of the running entry agree **byte for byte**: the mirror, jline's source tree, and the copy
   inside `lib/JLine3.jar`. A green audit of a stale jar copy is DESIGN.md §6 rule 10 in another costume. (Red arm:
   flip one byte in a copy of the jar.)

```
ok   tic -x compiles windows-conemu.ti with no complaint
ok   the .ti and the mirrored .caps hold the same 90 capabilities, spelled alike
ok   tic -> infocmp round-trips the same 84 capability names
ok   the jline copy is byte-identical to the mirror (89dea0736281)
ok   the jar copy is byte-identical to the mirror (89dea0736281)
TERMINFO CHECK: ok
```

## Who checks the bytes

`terminfo_check.sh` proves the **set**. The **meaning** of each string — what `cup(5,10)` or `csr(0,0)` turns
into on the wire after `%i` and the parameter packing — is asserted by the caps harness, currently
`cache/caps-audit/CapsDump.java` (81 assertions), driven twice: against the source file and against the copy
inside the jar, byte-compared. It is the leg that caught `rep`'s parameter having to reach `Curses.tputs` as an
**int** (`toInteger()` parses a `Character` as a String and throws) and the leg that named
`change_scroll_region`'s `%i` as the reason `Status.reset()` arrives as `CSI 1;1r` rather than as a reset —
which is a capability fact with a behaviour attached, and the only reason the entry's `csr` is tolerable at all.
Promoting that harness into this directory is worth doing and has not been done; until then this table is the
pointer, and "the docs say cache/" is the honest answer to "where is the byte check".

## What the renderer does with each group

Disposition of every declared capability; the citations are `ANSI_SUPPORTS.md` sections and the invariants
are `DESIGN.md` §3. Nothing here restates a rule that lives there.

| Group | Caps | render.dll |
|---|---|---|
| Booleans | `am` `bce` `msgr` | `am` is measured, not assumed: margin wrap is immediate, which is also why `xenl` is **absent** (§2.10, DESIGN I8/I35). `bce` is real: every erase fills with the **live** attribute (`fill_span`, §2.4), and `ech` inherits it. `msgr` is honoured by keeping moves and writes independent |
| Numbers | `colors#256` `cols#80` `it#8` `lines#24` `pairs#64` | 256-colour and 24-bit are supported **through the console's own fold** (§2.7); `it#8` is the whole tab story until #70 lands a tab-stop table; `cols`/`lines` are geometry the painter reads from the console rather than from here (I7) |
| Cursor | `cup` `hpa` `vpa` `cuu``+1` `cud``+1` `cuf``+1` `cub``+1` `home` `sc` `rc` | §2.3. `%i`'s one-based spelling is why `hpa(0)` is `CSI 1G`; `sc`/`rc` are the model's two saved coordinates (§2.2), and DECSTR clears them (#67) |
| Erase | `clear` `el` `el1` `ed` `ech` | `clear` is `\E[H\E[2J` — ED **stops at the viewport**, so scrollback survives (§2.4). `ech` erases on its own row and nowhere else (#65). EL erases the whole *buffer* row, because a model row is a buffer row (I7) |
| Insert / delete / scroll | `ich` `ich1` `dch` `dch1` `il` `il1` `dl` `dl1` `ind` `indn` `rin` `ri` `nel` `csr` | §2.4. `il`/`dl` home the column afterwards (#64). `ich`/`dch` move a wide glyph as one unit and heal a pair the shift split (#66). `ind`/`ri`/`nel` agree about which rows scroll, where ConEmu's `ForwardLF` did not (§4 item 6). `csr` is the region (§2.4's long row) |
| Attributes | `sgr` `sgr0` `bold` `rev` `smul` `rmul` `smso` `rmso` `op` `setaf` `setab` | §2.7. `sgr0` is `\E(B\E[0m`, and the charset arm of it is honoured; `smso`/`rmso` land on `RC_LVB_REVERSE` like `rev`, so "standout" is reverse video here and nowhere else |
| Alt screen | `smcup` `rmcup` | `?1049` is one behaviour for all three spellings (§2.5), snapshots the main viewport's rows including wrap claims and FTCS marks, and has no scrollback (I24) |
| Repeat | `rep` | §2.4's REP row: it is *text*, so it wraps, takes the pen and the charset remap, and repeats only a unit with width (#69) |
| Charset | `smacs` `rmacs` `acsc` | `ESC ( 0` is modelled and `acsc` is what makes box drawing survive a session that never asked for Unicode (§2.2's charset row, pinned by `geo_jline_stream`) |
| Queries | `u6` `u7` | the only place this library writes back into the input stream (§2.9). `u6` is a **pattern** the reader compiles, not a string the host sends, and the private `CSI ? 6 n` stays refused on purpose |
| Input keys | `kbs` `kcbt` `kcuu1` `kcub1` `kcud1` `kcuf1` `khome` `kend` `kpp` `knp` `kdch1` `kich1` `kf1`–`kf12` | **not this library's surface**: keys arrive as console records, not as caps lookups. They are declared for jline's input leg, and every judgement about them (why `kbs=^H` stays, why `kf13`+ stay out) is in `DESIGN.md` §4 |

## The eight the upstream entry has and this one does not

`D:\Green\Github\jline4` ships a *different* `windows-conemu.caps`: 80 capabilities, of which this entry
declares 72, plus 18 this one adds and 8 spelled with different values. Someone reading the two side by side
will ask whether the eight are a gap, so the answer is per-capability and it names the consumer, because
"nobody in this tree reads it" is exactly the sentence that goes stale.

| Cap | jline4's reader | Verdict |
|---|---|---|
| `kmous` (`key_mouse`) | `MouseSupport.java:85` — `getStringCapability(key_mouse) != null` **is** the answer to "does this terminal do mouse events"; `AbstractTerminal.java:421/426` read reports through it | **Correctly absent, at a real price.** The mouse modes are counted and not implemented (`?9`, `?1000`–`?1006`, `ANSI_SUPPORTS.md` §3), so no X10 report will ever arrive in a session this library paints; declaring the key would claim reports the terminal will not send (I26). `supportsMouseEvents()` returning false here is the truth. Reopening it means implementing the modes, not adding a line |
| `cbt` (`back_tab`) | `LineReaderImpl.java:6992` binds `REVERSE_MENU_COMPLETE` to `key(Capability.back_tab)` | **A real cost, and half the old reason for it was wrong.** `cbt` is an *output* capability and, until #70, we did not model `CSI Z` — that half of the argument held, and #70 retired it: the table, `ESC H`, `CSI Ps g`, `CSI Ps I` and `CSI Ps Z` all exist now (DESIGN I38). But jline also uses the value as the **name of the Shift-Tab key**, so dropping it silently removes a reader binding. dbcli does not lose that key (its own `Console.java:295` binds `^[Z` to `undo` explicitly, without asking caps); a jline4 menu does. What is left is a line in this file and two in the entry, and it is **#90**: declaring them means editing all three copies at once (mirror, jline's source, the compiled copy in `lib/JLine3.jar`), and leg 4 exists to catch exactly the case where one moves alone. The jar is another agent's in-flight build, so the declaration waits for a batch where it can move with it |
| `mir`, `ncv`, `blink`, `invis`, `rmpch`, `mc5i` | none — zero `Capability.<name>` readers anywhere in the jline4 tree; they survive only in `InfoCmp.java`'s name table | **Correctly absent.** `mir` would claim an insert mode that neither parser gives a body to; `blink`/`invis` claim SGR arms that hold no state on either leg (and `sgr` here deliberately drops those arms, unlike upstream's ten-parameter spelling); `ncv#3` is a claim about which attributes cannot coexist with colour, and the console's answer is carried by the fold in `rc_attr()` instead; `rmpch` is the PC alternate-font path this entry does not take (`rmacs=\E(B`, not `\E[10m`); `mc5i` is a printer |

The 18 this entry adds are the renderer's own surface, and each has a section that owes it an explanation:
`bce` (erases fill with the live attribute), `csr` (the region, and the `%i` trap that makes `Status.reset()`
arrive as `CSI 1;1r`), `ich`/`ich1`/`dch`/`dch1`, `ech`, `il`/`dl` and their `1` forms, `indn`/`rin`/`ri`/`nel`,
`ht`, `smacs`/`acsc`, `vpa`, `cnorm`, `rep`, and the query pair `u6`/`u7`. Eight more are the *same* capability
with a different value, and every one of those differences is a decision: `clear` is `\E[H\E[2J` because ED
must not eat scrollback, `setaf`/`setab` are the 256-colour forms because the console fold is what we actually
support, `sgr`/`sgr0` shed the arms that hold no state and take the charset exit that does.

## The omissions, and the rule behind them

The `.caps` first line lists what is *not* declared; that list is the record and this is the shape of it:
capabilities fall into three kinds of absence. **No state to point at** — `cbt`/`hts`/`tbc` had no tab-stop table
until #70), `smir`/`rmir`/`mir` (IRM has no body, so `CSI @` always inserts). **A claim about the *other*
parser** — `smam`/`rmam` (DECAWM is modelled here, `#61`, and ConEmu's own `?7` arm leaves `SetConsoleMode`
commented out), `initc`/`ccc` (OSC 4/10/11 now change the palette, `#55`, under this library and not under
ConEmu's parser). This is DESIGN I26 and it is the reason "we implement it now" is not by itself a reason to
declare it: the entry describes the session, and in a ConEmu-hosted session someone else may be reading the
same bytes. **No consumer** — `mc5p`, `flash`, the `sgr10`/`sgr11` font arms, `u8`/`u9` (both answered, and no
code in jline reads either), `blink`/`invis`/`ncv`.

The third kind is where a future reader should be careful in one direction only: *no consumer* is a claim about
this tree, and it goes stale the day someone writes a consumer. `caps`-adjacent decisions in
`../ANSI_TODO.md` are the place a claim gets re-opened; `terminfo_check.sh`'s capability set is where a
**change** becomes visible.
