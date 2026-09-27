# `geo_oracle_teeth` -- giving the grid oracle a falsification arm (2026-09-27)

This directory holds a **verification result and a staged patch**, not a build input. Nothing here is
compiled by `build.sh`; the leg is here so the finding cannot outlive the session that produced it.

## The finding

`rc_validate_grid` (`Render.cpp`) is the grid-integrity oracle added by task #72, and its ledger row says it
"runs at the end of every feed". Both halves are true and neither is a witness:

* it is called from exactly **one** place in the host gate (`RenderCheck.cpp::grid_ok`), which votes **only when
  it complains**;
* **no arm anywhere expects it to complain**, and the live gate's copy asks `gridRuns > 300 && gridBad == 0` --
  i.e. "how many times did we call it, and it reported nothing".

Measured consequence: replacing the oracle's body with "report every grid clean" leaves **both gates green**.
An oracle that can never be shown wrong is a counter, not an assertion.

## The leg

`leg_teeth.c.txt` is the missing arm, three assertions: a fresh legal grid must NOT be reported, and two
planted defects must come back **named** (`strstr` on the violation text, not just a non-empty message).
`teeth2.py` inserts it into an isolated copy of the tree, cross-builds there, and runs it twice:
once clean, once with the oracle blinded -- then reverts.

| run | result |
|---|---|
| tree + `geo_oracle_teeth` | `checks=6360 fails=0` / `RENDERCHECK: ok` |
| same leg + oracle blinded (M4) | `checks=6358 fails=2` / `RENDERCHECK: FAILED` |

The two failures name their own defect, which is the point:

```
FAIL oracle is silent on a cursor at column == cols (cx=6 cols=6)
FAIL oracle is silent on winRows(25) above rows(24)
```

M4 moved from "0 fails, green" to "red, by name". Two run notes worth keeping: the count drops by 2 in run B
because the "did it name it correctly" sub-assertions sit in the `else` branch and do not execute once the
outer arm fails -- that is correct sequencing, not lost coverage. And the legs plant defects **relatively**
(`g.cx = g.cols`, `g.winRows = g.rows + 1`), so they survive whatever clamping `rc_reset_hist` applies to the
constructor arguments.

## Landing it (the host tree was busy when this was measured)

* mount point is `static void geo_decrpm_silence()` -- **no `(void)`** -- at `RenderCheck.cpp:3191`, with its
  call at `:5616`; insert the function before it and call `geo_oracle_teeth();` after it.
* `RcGrid` is ~4 MB. Any local copy (`saved`) **must be `static`** or the process dies on stack exhaustion
  before printing a verdict -- a leg that crashes is not a red arm, it is a bug.
* expected after landing: `checks` rises by 5 over whatever trunk's current count is, and stays `fails=0`;
  re-running the blinding mutation must then produce exactly the two FAIL lines above.
* the ledger row (#72 in `DESIGN.md` §10) still claims the oracle's corpus-wide reach as task #66's; that
  attribution moved to `rc_validate_grid` when #72 landed and should be corrected when the row is next touched.

## Baseline drift, so nobody compares the wrong numbers

`checks=6287` was the `render-2026-09-26-35` host baseline. At measurement time trunk sat at **6355** (task
#82's `?2048` legs account for the difference), which is why run A reads 6360 = 6355 + 5 rather than
6287 + 5. Quote 6355+5, not 6287+5.
