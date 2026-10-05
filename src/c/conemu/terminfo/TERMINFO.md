# The `windows-conemu` terminfo entry

A terminfo entry is what a terminal-handling library reads to decide what it may send. `windows-conemu` is
the entry for a Windows console running this project's native renderer, and it is part of the renderer's
contract: **whatever the entry advertises, the renderer must actually do**, and what the renderer does not do
must not be advertised. A program that trusts a wrong entry does not detect the lie; it complies with it.

## The files

| File | What it is |
|---|---|
| `windows-conemu.caps` | the entry in the spelling this library's reader parses. This is the one that matters at run time. |
| `windows-conemu.ti` | the same entry in the standard form, so `tic` and `infocmp` can be run against it. Its first line is a name and a description; the parser that reads the `.caps` file never looks at that line, which is why the entry's rationale lives there. |
| `infocmp-windows-conemu.txt` | what `infocmp` prints after compiling the `.ti`. A recorded round trip, refreshed by a flag, never hand-edited. |
| `terminfo_check.sh` | the gate. Four checks, described below. |

The same entry exists in three places that a reader can reach: this mirror, the source tree of the terminal
library, and the jar that ships inside the product. **All three have to be byte-identical**, and the gate
refuses the build when they are not. Auditing one copy while another one ships is the failure this rule
exists to prevent.

## What the entry says

Plainly: this terminal is a 256-colour, 64-pair console with eight-column tabs; margin wrap is immediate
(that is why `xenl` is absent rather than present); erasing fills with the colours currently on the pen, so a
cleared cell takes the background the program set, not the one the console started with; box-drawing
characters survive a session that never asked for Unicode, because the alternate character set is declared and
the renderer honours it letter for letter.

It also says the answers this terminal gives to questions are real. The cursor-position report and the
screen-size report are advertised because the renderer writes those replies back into the console's own input
stream, the same way the console host does, so a program that blocks waiting for an answer gets one. Mouse
reports are advertised for the same reason: the encoding of a report is the renderer's job, the records come
from the console, and a session that selects a different report encoding says so with its own mode rather than
with a different capability name.

Line editing is covered on the input side: the function keys, the Home/End/Page keys, backspace and
Shift-Tab are all named. Shift-Tab is named because something reads it -- a key binding is looked up by
capability name, and an entry that omits it silently unbinds the key.

## What is deliberately left out

Leaving a capability out is not the same as not having thought of it. Each of these has a reason a reader can
check, and the reason is about the session a program would actually get.

| Left out | Why |
|---|---|
| `smam` / `rmam` (autowrap on/off) | the renderer models it, but the entry also describes sessions read by ConEmu's own parser, which ignores the sequence. Declaring it would be a claim about a parser this library does not own. |
| `smir` / `rmir` / `mir` (insert mode) | same shape as autowrap: the mode works here, the other parser discards it. |
| `hts` / `tbc` (tab stops) | the tab *table* is modelled, but the same other-parser argument applies, and declaring a stop that the reader cannot rely on is worse than declaring the default interval alone -- which is what `it#8` does. |
| `initc` / `ccc` (colour initialisation) | the palette really changes here, but a program asking "can this terminal set colours?" gets an answer that also covers sessions where it cannot. |
| `smkx` / `rmkx` (keypad transmit mode) | an input-side mode, and input in this terminal arrives as console records, not as a mode a stream can switch. |
| `blink`, `invis`, `ncv` | the console attribute this library writes has no such bit. There is no way to draw it, so there is nothing to advertise. |
| `flash` | it would flash a window the renderer does not own. Leaving it out makes readers fall back to the bell, which is the right answer. |
| `rmp` and the font-switching arms of `sgr` | no alternate-font path exists. |
| `mc5p` | no printer. |
| `xenl` | measured absent on every writer path. Its absence is what makes `am` honest. |
| `kf13` and above, and the shifted arrow names | the input side builds those bytes itself without consulting the entry, and the entry can only name one of the modifier combinations. Naming it would advertise a key no widget receives. |
| `u8` / `u9` | both identification questions are answered, but `u8` is a *pattern* a reader compiles rather than a string this terminal sends, and `u9` is the request, not the answer. Either value would be invented. |

Two more omissions are decisions rather than gaps, and they are written down where the work is tracked: the
capability for setting a mode permanently, and the termcap-side queries a program could otherwise ask twice
against two different sources of truth.

## The gate

```sh
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc \
  'tr -d "\r" < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
```

Two things about that line are load-bearing. The `tr` is not decoration: the repository checks files out with
CRLF endings, and a shell script full of carriage returns fails in ways that look like a broken script rather
than a broken checkout. And anything you want the gate to see -- an alternative jar, a different tree, a flag
-- has to be **exported** in the shell before the command; written in front of the `tr` it binds to the `tr`
and the script that reads it sees an empty environment.

The gate finds the repository root from a marker file rather than from the path it was called with, so it can
be piped, copied or run from anywhere; when it cannot find a root it says which places it tried instead of
guessing.

| Check | What it proves |
|---|---|
| `tic -x` compiles the `.ti` with no complaint | nothing in the entry is a name the compiler does not know -- a typo or an invented capability shows up here |
| the `.ti` and the mirror hold the same capabilities, spelled alike | the two files describe one entry, not two |
| `tic` then `infocmp` round-trips the same names | the compiler dropped nothing and folded nothing |
| the mirror, the library's own source copy and the copy inside the shipped jar are byte-identical | the entry that was audited is the entry that ships |

The last one is the check that has bitten most often, because a comparison that quietly compares nothing looks
exactly like a pass: the jar copy was once skipped with a printed *note* while the script reported `ok`. The
rule the project follows from that is blunt -- **a gate that compares must assert that it compared**, and it
prints how many copies it actually read.

`--refresh` rewrites the recorded `infocmp` output from the compile; it is idempotent, so a refresh that
produces no change proves the record was already current. `--allow-no-jar` is for a tree that genuinely has no
shipped jar, and it has to be said out loud rather than inferred from silence.

## What the entry means on the wire

The gate above proves the *set*. The meaning of each string -- what a parameterised cursor move or a scroll-region
setting turns into after the notation is expanded -- is proved by a separate harness, which builds the entry
through the same reader a real session uses and compares the bytes it would send, twice: against the file in
the tree and against the copy extracted from the shipped jar. It prints its own totals, so a count claimed in
prose cannot disagree with a count the program produced, and it names every declared capability it did not
touch: a capability added without an expectation surfaces there rather than as a silent hole.

That harness is where two real facts were found: one capability's parameter has to reach the reader as a
number rather than a character, and the scroll-region string carries an increment that makes a "reset" call
produce a one-line region instead. Neither is visible by reading the entry; both are visible in the bytes.

## Changing the entry

1. Decide what the renderer really does, and check it against a running session rather than against this file.
2. Change the mirror and the `.ti` together -- the gate refuses a pair that has drifted.
3. Propagate to the library's source copy and rebuild the jar, so the shipped copy is the audited copy.
4. Run the gate with `--refresh`, then run the byte harness.
5. Add an expectation to the harness for anything new; a capability with no expectation is listed as unasserted
   and the harness fails until it is either asserted or deliberately allowed with a reason.

Nothing here is settled by this document. Every row above is a claim about today's build, and the checks that
back it are the ones printed by a run, not the ones quoted in prose.
