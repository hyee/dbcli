# Handoff — the 2026-09/10 render.dll feature batch: open defects, ranked

Scope: everything this batch shipped — the DECSTBM page feed (#123, -62), the
pseudo-console executor (`ptyMode`: real-LF scroll payment, -64), region
forwarding (`sync_region_host`, -65), the streaming scroll trigger
(`streamScrolls`, -66), and the full-screen takeover (`unpushed` + the bare
`\E[H` hook, -67) — plus the seams it touched (classification reversal in
`WinSysTerminal`, the `setPainting` export, the jline `Status`
`MovingCursorDisplay` override). Gates at shipping time: host `7914/0`, live
both arches `6311/0` + `STAGE0 ok`; ConPTY green legs and classic legs per
`.dsh/memory/logs/2026-10-01.md`. Every item below was re-derived from the
shipped source on 2026-10-01; anchors were opened, not quoted from memory.

Ranking: P1 = user-visible corruption reachable from normal product flows;
P2 = reachable from plausible third-party/edge flows, or a desync that
self-heals only by luck; P3 = debt/gap that will bite whoever inherits it.

---

## P1-1  Takeover with a live DECSTBM region: model and host desync

`Render.cpp:1815` — the takeover condition checks `!g->alt && nArgs==0 &&
unpushed && tr == gutter() && cy > tr` and then banks with
`scroll_up(g, cy - tr + 1)`, which rotates the **whole model** (`Render.cpp`
`scroll_up`: `rotate_span(g, 0, g->rows, n, 0)`). It never asks whether
`regSet` is live. If a dashboard homes while a region is set (a caller that
does not run `Status.close()` first — every dbcli top does, a third-party
caller need not), two things disagree:

- the model rotates all `rows` rows, pushing the bar's own pinned rows into
  the gutter as if they were history;
- the executor pays the charge by parking on the region's bottom row
  (`RenderJni.cpp:1304` block, `bot.Y = regBot - gut`), so conhost — which
  honours the *forwarded* region (`cache/ppty/probe3.py`) — scrolls only the
  region's rows, and rows below the margin never move.

Model and host end up on different contents; everything this flush and the
next paint is addressed to rows the host does not agree about.

Repro sketch (host leg): build a grid, set `CSI 1;4r` in a 6-row window,
print enough to scroll (arms `unpushed`), send bare `\E[H`, assert the rows
below the margin. Suggested directions: refuse the takeover while `regSet`
(bank nothing — the pre--67 in-place behaviour) **or** bank region-aware
(`shift_region` inside the region + a separate payment the executor can make
region-honouringly). Pick by reading MSFT `_DoLineFeed`'s pan branch
(`adaptDispatch.cpp:2461-2477`), which is the reference for "page feed with a
bottom band".

## P1-2  Page feed inside an alternate screen rotates the main screen's history

`Render.cpp:768-770` — `line_down`'s three-way dispatch has **no alt guard**.
Inside an alt screen with a region whose top is the viewport top (a TUI that
sets `CSI 1;Nr` to protect its own status line — common), a line feed at the
region bottom falls through to `line_down_page_scroll`, whose
`rotate_span(g, 0, bot + 1, ...)` rotates **from model row 0** — the gutter
rows above the viewport, which in alt hold the main screen's unpainted
scrollback. `scroll_up`'s alt branch exists precisely because a full-model
shift there "carries alt content into the rows the painter maps above the
window" (`Render.cpp`, the alt comment); `line_down_page_scroll` re-introduced
that hole, and it also charges `pendingScrolls` (`+1`), so under a
pseudo-console the executor pays real line feeds and the *host* scrolls while
showing alt content.

Repro sketch: feed `?1049h`, `CSI 1;4r`, some rows, a line feed at the bottom
margin; assert the gutter rows did not move and `pendingScrolls == 0`.
Fix direction: in `line_down`, when `g->alt`, route every region-bottom feed
to `shift_region` (the alt has no scrollback to gain — same principle
`scroll_up`'s alt branch already implements).

## P2-1  Same-chunk region change + scroll payment: payment runs before the region is forwarded

`sync_region_host` (`RenderJni.cpp:1945`) is called once per chunk, *after*
`rc_feed` returns. But the scroll payment executes inside `paint_flush`,
which `onFlush` (`streamScrolls`/gutter-full) can fire **during** `rc_feed` —
so a chunk that both sets a region and scrolls pays its line feeds while the
host terminal still holds the *previous* region: the executor parks on the new
`regBot` row, conhost scrolls according to the old one, and the delivered
scroll count can differ from the charged one. Narrow (same-chunk `csr` +
scroll), self-heals at the next flush, but it is a real ordering inversion.
Fix direction: call `sync_region_host` from the top of `paint_flush` (it is
idempotent on the serial) instead of only after the feed, or forward the
region from inside the `case 'r'` arm's flush.

## P2-2  A decline + rebuild silently disarms a pending takeover

`unpushed` lives in the grid, and a rebuild (`readopt` after a resize or a
decline) allocates a fresh zeroed grid. Output that scrolled (arming the
flag), then a resize racing the dashboard's first frame, then the bare `\E[H`:
the takeover does not fire and the frame overwrites the viewport the way
--67 was written to stop. Self-healing only in the sense that the content was
about to be repainted anyway — the banked-history promise is lost.
Fix direction: carry `unpushed` across `build_model` the way `keepWrap`/
`keepTabs` are carried (it is application-session state by the same rule).

## P2-3  kmous is not declared while the session really does send mouse reports — gap A1 is the blocker

Not new to this batch, but the batch's classification reversal makes every
product session a `windows-conemu` (renderer) session, which sharpens it: the
product's input pump synthesizes **X10** `ESC [ M` bytes
(`WinSysTerminal.java:489` routes, `:537` `processMouseEvent`, `:569-572`
fill and write) regardless of the negotiated format, while the renderer holds
a five-format encoder (`rc_mouse_report`) with **no production caller**. An
application that selects `?1006` SGR reports receives X10 bytes. That is a
wire-correctness defect against hard constraint 1, and it is what keeps
`kmous` out of the terminfo entry (DESIGN.md §4, rewritten 2026-10-01 to say
exactly this). Fix location is a decision the owner reserved (who reads
`CONIN$`): either the product honours the negotiated format at its call site,
or the reports move into the renderer's encoder and the pump hands over
records. `ANSI_SUPPORTS_1.md` §6 gaps A1/A2 track it.

## P3-1  `setPainting` has no witness

`RenderJni.cpp` (`Java_..._setPainting`) and `NativeRenderer.setPainting` ship
with zero legs exercising them — the -63 "no-paint" policy was withdrawn from
production, and nothing in either gate calls the export. A future edit that
breaks it compiles green. One host-side or live leg (flip the flag, assert
`RENDER_RAW` + replies still delivered + VTP handed back) closes it.

## P3-2  Alternate screen under the pseudo-console executor is untested

The alt path predates this batch, but the batch made it *reachable* in the
owner's environment (every product session now renders). Enter/exit were
never run on a pty leg: entering blanks the viewport (full repaint through
cell writes), scrolls inside alt must not pay line feeds (`scroll_up`'s alt
branch charges nothing — verify `line_down`'s dispatch cannot reach
`line_down_page_scroll` in alt, see P1-2), and exit must repaint the
snapshot through the host. One ConPTY leg with `?1049h`/rows/`?1049l` pins all
three.

## P3-3  jline4 merge debt: the `MovingCursorDisplay` override

The `moveVisualCursorTo(int)` override that made bar repaints zero-LF
(`Status.java`, committed `4be9d95e` in the jline3.29 repo) is **not** in the
jline4 tree; the 2026-09-28 merge table in `JLINE_CHANGES.md` predates it.
Whoever lands jline4 must port the override + `barRepaintMustNotFeedLineScrolls`
or the x9/27-blank-rows defect comes back on the upgraded stack.

## P3-4  Pre-existing, adjacent (do not re-diagnose, just know)

- Ctrl+C cannot stop a repeat `top` in harness legs (§25: `SIG_IGN` swallows
  it); the owner's real terminal can stop it. Green legs use a single
  `snap ... -top` instead (same initDisplay/display/exitDisplay path).
- One live-gate timer leg flaked once on x86 (`the window slid down with
  them`, 1 failure, green on two immediate re-runs) — treat single-run live
  reds as suspect until re-run.
- `deploy-4748.sh` ships **both** jars: its second `ship` swapped a tree-built
  `Console.class` into `lib/dbcli.jar` once already (rolled back from the
  timestamped backup). After any jar deploy, diff the CRC lists, not the md5.
- `open()` refuses windows taller than 255 rows (`OPEN_BIG`) — resource
  floor, documented at I3; a >255-row window degrades to the raw writer.

## What was checked and is NOT a defect

- The executor's `!h->ptyMode` slide guard is redundant (under a
  pseudo-console `free_slide` is always 0 because `bufH == winRows`), but
  harmless.
- Payment LFs written while VTP is claimed off still reach the host terminal
  and push real history (conhost's VtIo serialises the buffer change;
  `cache/ppty/probe2.py` measured the pushed rows byte for byte).
- conhost honours a forwarded DECSTBM in its *text pipeline* with VTP off
  (`probe3.py`: five LFs parked on the region's bottom scrolled exactly the
  region, bar rows never moved).
- The takeover on a session that never scrolled, on any upward jump that is
  not to the top row, and on an explicit `CSI 1;1 H`, does nothing — pinned by
  `geo_takeover`, mutation-proven (6 red with the hook disabled,
  `cache/p123x/lab`).
