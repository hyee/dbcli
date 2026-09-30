#!/usr/bin/env bash
#
# gen_x11colors.sh -- build X11ColorNames.h for ticket #84 out of local copies of X11's
#                     rgb.txt, under three independent cross-checks.
#
# Why a generator and not a hand-written table
# --------------------------------------------
# #84 lets an OSC 4/10/11 colour spec be a *name*. The result is 676 rows of numbers nobody
# will re-read, so a mis-transcription is invisible until somebody's prompt comes out the wrong
# colour. build.sh:39-43 states the precedent this copies (gen_rgbmap.sh + extract_rgbmap.py):
#
#   "Two independent extractions ... reading one source is the point: RenderCheck's 'RgbMap
#    identity' assertion fails if either parser misreads the table."
#
# Three legs, because one is not enough
# -------------------------------------
#  L1 PARSER x SOURCE independence.  Four cells, one answer:
#       fixed-column byte slicing  -- ghostty's own rule  (src/terminal/x11_color.zig:45-48)
#       whitespace field splitting -- wezterm's own rule  (color-types/src/lib.rs:393-403)
#     each applied to BOTH vendored copies (ghostty's and wezterm's rgb.txt). The two files are
#     byte-different (CRLF vs LF, and 97 lines re-pad a numeric column with a TAB where the other
#     uses a space), so agreement is a fact about the data rather than a shared input buffer.
#     This is the gen_rgbmap shape, with one extra dimension.
#
#  L2 THIRD DISTRIBUTION CHANNEL.  The OS-packaged /etc/X11/rgb.txt, pulled out of WSL into
#     wsl_rgb.txt next to this script (Debian/Ubuntu xorg, dated 2020-10-09, older upstream). It
#     may differ only by the names freedesktop added afterwards -- each one allowlisted by hand --
#     and must never differ on the RGB of a name the two vintages share.
#
#  L3 DERIVATION independence. msfterm's colorTable.cpp is not a copy of rgb.txt at all -- it is
#     somebody else's curated re-derivation (C++ literals plus a *computed* gray ramp). It must
#     disagree with X11 only inside ALLOWED_MSFT.
#
# What L1 is really guarding
# --------------------------
# ghostty's rule is positional and wezterm's is not, and the two vendored files are
# byte-different: wezterm's is CRLF and re-pads 97 numeric columns with a TAB where ghostty's
# uses a space ("139 121  94" vs "139 121\t 94"). All four readings return one identical set of
# 676 (name,r,g,b) tuples, so the reflow is cosmetic for both rules -- but that is only known
# because both were run over both. A vendor refresh that pushed a digit past column 11 would
# move a component by a factor of 16 without changing any row count: invisible to a check that
# reads one file with one parser, and loud here. That, not the current agreement, is the reason
# the four cells are asserted.
#
# Usage
#   bash src/c/conemu/gen_x11colors.sh              write vendor/X11ColorNames.h
#   bash src/c/conemu/gen_x11colors.sh --check      fail if the header is stale (build.sh runs this)
#   bash src/c/conemu/gen_x11colors.sh --report     print the three legs, write nothing

# Ticket #84. Sources are four local reads of X11's rgb.txt -- ghostty's and wezterm's vendored
# copies, the OS-packaged copy, and msfterm's independent re-derivation -- so every path below is
# overridable: GHOSTTY_DIR, WEZTERM_DIR, MSFTERM_DIR, WSL_RGB, X11_DATA_DIR.
#
# Environment overrides: GHOSTTY_DIR, WEZTERM_DIR, MSFTERM_DIR, WSL_RGB (path to a cached copy
# of the system rgb.txt; empty string disables L2's third copy).
# Exit: 0 ok, 1 a leg failed or a source moved, 2 a required source is missing.

set -u
set -o pipefail
LC_ALL=C
export LC_ALL

SELF=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) || SELF=.
# The generated header ships beside the other vendored tables; the cross-check artefacts (the two
# tsv tables, report.txt, the cached system rgb.txt) stay in the ticket work area -- they are
# evidence and inputs to the check, not something Render.cpp includes.
DATA=${X11_DATA_DIR:-/d/dbcli/cache/audit90/x11}

GHOSTTY=${GHOSTTY_DIR:-/d/Green/github/ghostty}
WEZTERM=${WEZTERM_DIR:-/d/Green/Github/wezterm}
MSFT=${MSFTERM_DIR:-/d/dbcli/cache/msfterm}
WSL_RGB=${WSL_RGB-$DATA/wsl_rgb.txt}

SRC_A="$GHOSTTY/src/terminal/res/rgb.txt"
SRC_B="$WEZTERM/color-types/src/rgb.txt"
SRC_D="$MSFT/src/types/colorTable.cpp"
OUT="$SELF/vendor/X11ColorNames.h"

EXPECT_N=676                       # folded rows; a deliberate edit if upstream really changes
ALLOWED_MSFT='^(gray|grey)(50|90)$'   # msfterm computes the ramp, X11 spells it out -- VERIFY.md
ALLOWED_MSFT_ONLY='0$'                # msfterm invents "<family>0" as an alias of the base colour

# Names in the 2020 system copy's successor that the OS-packaged /etc/X11/rgb.txt predates.
# These are the CSS4 keywords plus the web*/x11* disambiguators freedesktop added later.
NEWER_THAN_SYSTEM='aqua
crimson
fuchsia
indigo
lime
olive
rebeccapurple
silver
teal
webgray
webgreen
webgrey
webmaroon
webpurple
x11gray
x11green
x11grey
x11maroon
x11purple'
# Debian patches one colour of its own into the packaged file.
SYSTEM_ONLY='debianred'

CHECK=""
REPORT=""
DUMP=""
for a in "$@"; do
  case $a in
    --check)  CHECK=1 ;;
    --report) REPORT=1 ;;
    --dump-table) DUMP=1 ;;     # write the verified extraction as name<TAB>r<TAB>g<TAB>b
    *) printf 'usage: %s [--check|--report|--dump-table]\n' "$0" >&2; exit 2 ;;
  esac
done

for f in "$SRC_A" "$SRC_B" "$SRC_D"; do
  [ -f "$f" ] || { printf 'source not found: %s\n' "$f" >&2; exit 2; }
done

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT

# ----------------------------------------------------------------------------------------
# parser 1 -- ghostty's fixed-column rule.
#   Zig: trim(line[0..3]) trim(line[4..7]) trim(line[8..11])  name = trim(line[12..])
#   awk counts from 1, so those four fields are substr(,1,3) substr(,5,3) substr(,9,3) substr(,13)
# A line that is not "three 0..255 integers in columns 1-11 plus a name" is a hard error, never
# a silent skip -- a silently skipped line is how a table quietly loses rows.
# ----------------------------------------------------------------------------------------
p_fixed() {
  awk '
    { sub(/\r$/, "") }
    $0 == "" { next }
    substr($0, 1, 1) == "!" { next }
    {
      rf = substr($0, 1, 3); gf = substr($0, 5, 3); bf = substr($0, 9, 3); nm = substr($0, 13)
      if (length(nm) == 0) { printf "reject(empty name): %s\n", $0 > "/dev/stderr"; exit 1 }
      gsub(/^[ \t]+/, "", nm); gsub(/[ \t]+$/, "", nm)
      if (nm == "") { printf "reject(blank name): %s\n", $0 > "/dev/stderr"; exit 1 }
      if (rf !~ /^ *[0-9]+ *$/ || gf !~ /^ *[0-9]+ *$/ || bf !~ /^ *[0-9]+ *$/) {
        printf "reject(columns 1-11 are not three space-padded integers): %s\n", $0 > "/dev/stderr"; exit 1
      }
      r = rf + 0; g = gf + 0; b = bf + 0
      if (r > 255 || g > 255 || b > 255) { printf "reject(range): %s\n", $0 > "/dev/stderr"; exit 1 }
      key = tolower(nm); gsub(/ /, "", key)
      if (key !~ /^[a-z0-9]+$/) {
        printf "reject(name outside [a-z0-9] after folding): %s\n", $0 > "/dev/stderr"; exit 1
      }
      printf "%s\t%d\t%d\t%d\n", key, r, g, b
    }
  ' "$1"
}

# ----------------------------------------------------------------------------------------
# parser 2 -- wezterm's whitespace rule.
#   Rust: split_ascii_whitespace(); [0][1][2] are the components; name = [3..].join(" ")
#         .to_ascii_lowercase()                                     (color-types/src/lib.rs:393-403)
# Carries no column assumption at all, which is what makes it an independent second opinion
# of parser 1 rather than a restatement of it.
# ----------------------------------------------------------------------------------------
p_wssplit() {
  awk '
    { sub(/\r$/, "") }
    $0 == "" { next }
    substr($0, 1, 1) == "!" { next }
    {
      if (NF < 4) { printf "reject(fewer than 4 fields): %s\n", $0 > "/dev/stderr"; exit 1 }
      for (i = 1; i <= 3; i++)
        if ($i !~ /^[0-9]+$/) { printf "reject(not a number): %s\n", $0 > "/dev/stderr"; exit 1 }
      r = $1 + 0; g = $2 + 0; b = $3 + 0
      if (r > 255 || g > 255 || b > 255) { printf "reject(range): %s\n", $0 > "/dev/stderr"; exit 1 }
      nm = ""
      for (i = 4; i <= NF; i++) nm = nm (i > 4 ? " " : "") $i
      key = tolower(nm); gsub(/ /, "", key)
      printf "%s\t%d\t%d\t%d\n", key, r, g, b
    }
  ' "$1"
}

# ----------------------------------------------------------------------------------------
# parser 3 -- msfterm's derivation, a structurally different artifact:
#   xorgAppVariantColorTable  colorTable.cpp:49    family + index 0..4  -> family0 .. family4
#   xorgAppColorTable         colorTable.cpp:130   plain names
#   gray0..99 / grey0..99     colorTable.cpp:346-355  computed: ((i*255)+50)/100
#   fold rule                 colorTable.cpp:296-334  ASCII lowercase, spaces dropped
# ----------------------------------------------------------------------------------------
p_msft() {
  awk '
    function trim(s) { gsub(/^ +/, "", s); gsub(/ +$/, "", s); return s }
    function emit(stem, frag,   v, k, i) {
      gsub(/[^0-9, ]/, "", frag); frag = trim(frag)
      k = split(frag, v, /,+/)
      if (k != 3) return
      for (i = 1; i <= 3; i++) v[i] = trim(v[i])
      printf "%s\t%s\t%s\t%s\n", stem, v[1], v[2], v[3]
    }
    /std::array<til::color, 5>/ {
      stem = $0; sub(/.*std::pair\{ "/, "", stem); sub(/".*/, "", stem)
      rest = $0
      i = 0
      while (match(rest, /til::color\{ [0-9]+, [0-9]+, [0-9]+ \}/)) {
        emit(stem i, substr(rest, RSTART, RLENGTH))
        rest = substr(rest, RSTART + RLENGTH); i++
      }
      next
    }
    /std::pair\{ "[a-z]+"sv, til::color\{ [0-9]+, [0-9]+, [0-9]+ \}/ {
      stem = $0; sub(/.*std::pair\{ "/, "", stem); sub(/".*/, "", stem)
      frag = $0; sub(/.*til::color\{ /, "", frag); sub(/ \}.*$/, "", frag)
      emit(stem, frag); next
    }
    END {
      for (i = 0; i < 100; i++) {
        c = int((i * 255 + 50) / 100)
        printf "gray%d\t%d\t%d\t%d\n", i, c, c, c
        printf "grey%d\t%d\t%d\t%d\n", i, c, c, c
      }
    }
  ' "$1" | sort -u
}

# ----------------------------------------------------------------------------------------
# L1 -- two parsers x two vendored copies: all four readings must return one identical set.
# ----------------------------------------------------------------------------------------
A1="$WORK/a1"; A2="$WORK/a2"; B2="$WORK/b2"; C2="$WORK/c2"; D3="$WORK/d3"
p_fixed   "$SRC_A" > "$A1" || { printf 'L1: parser 1 choked on %s -- the file moved out from under the fixed-column rule; look before regenerating\n' "$SRC_A" >&2; exit 1; }
p_wssplit "$SRC_A" > "$A2" || { printf 'L1: parser 2 choked on %s\n' "$SRC_A" >&2; exit 1; }
p_wssplit "$SRC_B" > "$B2" || { printf 'L2: parser 2 choked on %s\n' "$SRC_B" >&2; exit 1; }
p_msft    "$SRC_D" > "$D3" || { printf 'L3: parser 3 choked on %s\n' "$SRC_D" >&2; exit 1; }

sort -u "$A1" > "$WORK/a1s"; sort -u "$A2" > "$WORK/a2s"
N_A1=$(wc -l < "$WORK/a1s" | tr -d ' '); N_A2=$(wc -l < "$WORK/a2s" | tr -d ' ')

# A folded name reaching two different RGBs is the failure this script exists to catch.
CONFLICT=$(cat "$WORK/a1s" "$WORK/a2s" | cut -f1 | uniq -d)
if [ -n "$CONFLICT" ]; then
  printf 'L1 FAILED: the two parsers give one name two different colours:\n' >&2
  while IFS= read -r k; do
    printf '  %s:\n' "$k" >&2
    grep -h "^$k"$'\t' "$WORK/a1s" "$WORK/a2s" | sed 's/^/      /' >&2
  done <<EOF2
$CONFLICT
EOF2
  exit 1
fi
if ! cmp -s "$WORK/a1s" "$WORK/a2s"; then
  printf 'L1 FAILED: parser1 and parser2 disagree on %s (%s vs %s rows)\n' "$SRC_A" "$N_A1" "$N_A2" >&2
  comm -3 "$WORK/a1s" "$WORK/a2s" | head -20 >&2
  exit 1
fi
TAB="$WORK/a1s"
N=$N_A1

# All four cells of {parser 1, parser 2} x {copy A, copy B} must be one identical set. Running B
# through parser 1 as well is the point: A and B are byte-different artifacts, so this is four
# readings of two things, not one reading of two files.
sort -u "$B2" > "$WORK/b2s"
N_B2=$(wc -l < "$WORK/b2s" | tr -d ' ')
if p_fixed "$SRC_B" > "$WORK/b1" 2>"$WORK/b1.err"; then
  sort -u "$WORK/b1" > "$WORK/b1s"
else
  printf 'L1 FAILED: ghostty'"'"'s fixed-column rule cannot read %s at all -- that copy has been\n' "$SRC_B" >&2
  printf 'reflowed past column 11, so it is no longer the file the rule was written for:\n' >&2
  head -3 "$WORK/b1.err" >&2
  exit 1
fi
N_B1=$(wc -l < "$WORK/b1s" | tr -d ' ')
for cell in "$WORK/b2s" "$WORK/b1s"; do
  cmp -s "$cell" "$WORK/a1s" || {
    printf 'L1 FAILED: %s and %s do not return the same set (%s rows vs %s).\n' \
           "$SRC_A" "$SRC_B" "$(wc -l < "$cell" | tr -d ' ')" "$N_A1" >&2
    printf 'first 20 differing rows:\n' >&2
    comm -3 "$cell" "$WORK/a1s" | head -20 >&2
    exit 1
  }
done

# Independence, checked rather than claimed. If the two "copies" were the same bytes, L1 would be
# two parsers over one artifact and the source dimension would be empty -- worth knowing, because
# both files descend from the same freedesktop upstream.
MD_A=$(cksum "$SRC_A" | awk '{print $1 "/" $2}')
MD_B=$(cksum "$SRC_B" | awk '{print $1 "/" $2}')
if [ "$MD_A" = "$MD_B" ]; then
  SOURCES_DISTINCT=no
  printf '! %s and %s are byte-identical: the source half of the cross-check is empty\n' "$SRC_A" "$SRC_B" >&2
else
  SOURCES_DISTINCT=yes
fi
A_CRS=$(tr -dc '\r' < "$SRC_A" | wc -c | tr -d ' ')
B_CRS=$(tr -dc '\r' < "$SRC_B" | wc -c | tr -d ' ')
REFLOW=$(diff <(tr -d '\r' < "$SRC_A") <(tr -d '\r' < "$SRC_B") | grep -c '^<' || true)
ROWS_A=$(awk '{ sub(/\r$/, "") } $0 != "" && substr($0, 1, 1) != "!" { n++ } END { print n }' "$SRC_A")

# ----------------------------------------------------------------------------------------
# L2 -- the third, OS-packaged copy (Debian/Ubuntu xorg's /etc/X11/rgb.txt, 2020 vintage).
# ----------------------------------------------------------------------------------------
L2C=skipped
N_C=0
if [ -n "$WSL_RGB" ] && [ -f "$WSL_RGB" ]; then
  p_wssplit "$WSL_RGB" > "$C2" || { printf 'L2: parser 2 choked on %s\n' "$WSL_RGB" >&2; exit 1; }
  sort -u "$C2" > "$WORK/c2s"; N_C=$(wc -l < "$WORK/c2s" | tr -d ' ')
  # values on shared names must agree absolutely -- a rename is not a redefinition
  CDIFF=$(awk -F'\t' 'NR==FNR{x[$1]=$2"/"$3"/"$4;next} ($1 in x) && x[$1]!=$2"/"$3"/"$4 \
    { printf "  SHARED-NAME VALUE DIFF %s system=%s current=%s\n", $1, x[$1], $2"/"$3"/"$4 }' \
      "$WORK/c2s" "$WORK/a1s")
  [ -n "$CDIFF" ] && { printf 'L2 FAILED (system copy):\n%s\n' "$CDIFF" >&2; exit 1; }
  C_ONLY=$(comm -23 <(cut -f1 "$WORK/c2s") <(cut -f1 "$WORK/a1s"))
  A_ONLY=$(comm -13 <(cut -f1 "$WORK/c2s") <(cut -f1 "$WORK/a1s"))
  BAD_C_ONLY=$(printf '%s\n' "$C_ONLY" | grep -vxF "$SYSTEM_ONLY" || true)
  BAD_A_ONLY=$(printf '%s\n' "$A_ONLY" | grep -vxF "$NEWER_THAN_SYSTEM" || true)
  { [ -n "$BAD_C_ONLY" ] || [ -n "$BAD_A_ONLY" ]; } && {
    printf 'L2 FAILED (system copy): names outside the allowlist.\n' >&2
    [ -n "$BAD_C_ONLY" ] && printf '  only in the system copy: %s\n' "$BAD_C_ONLY" >&2
    [ -n "$BAD_A_ONLY" ] && printf '  only in the current copies: %s\n' "$BAD_A_ONLY" >&2
    exit 1; }
  L2C=ok
fi

# ----------------------------------------------------------------------------------------
# L3 -- msfterm's derivation.
# ----------------------------------------------------------------------------------------
N_D=$(wc -l < "$D3" | tr -d ' ')
MSFT_BAD=$(awk -F'\t' -v ok="$ALLOWED_MSFT" '
  NR == FNR { d[$1] = $2 "/" $3 "/" $4; next }
  { x[$1] = $2 "/" $3 "/" $4 }
  END {
    for (k in d) {
      if (!(k in x) || x[k] == d[k]) continue
      if (k ~ ok) continue
      printf "  UNEXPLAINED %s x11=%s msft=%s\n", k, x[k], d[k]
    }
  }' "$D3" "$WORK/a1s")
[ -n "$MSFT_BAD" ] && { printf 'L3 FAILED: msfterm disagrees outside the allowlist (%s):\n%s\n' "$ALLOWED_MSFT" "$MSFT_BAD" >&2; exit 1; }
MSFT_AGREE=$(awk -F'\t' 'NR==FNR{x[$1]=$2"/"$3"/"$4;next} ($1 in x) && x[$1]==$2"/"$3"/"$4 {n++} END{print n+0}' "$D3" "$WORK/a1s")
MSFT_DIFF=$(awk -F'\t' -v ok="$ALLOWED_MSFT" 'NR==FNR{d[$1]=$2"/"$3"/"$4;next} ($1 in d) && d[$1]!=$2"/"$3"/"$4 && $1 ~ ok {n++} END{print n+0}' "$D3" "$WORK/a1s")
MSFT_ONLY=$(comm -23 <(cut -f1 "$D3" | sort -u) <(cut -f1 "$WORK/a1s"))
MSFT_ONLY_N=$(printf '%s\n' "$MSFT_ONLY" | grep -c . || true)
MSFT_ONLY_BAD=$(printf '%s\n' "$MSFT_ONLY" | grep -v "$ALLOWED_MSFT_ONLY" || true)
[ -n "$MSFT_ONLY_BAD" ] && { printf 'L3 FAILED: msfterm names with no rgb.txt row, outside <%s>0:\n%s\n' 'family' "$MSFT_ONLY_BAD" >&2; exit 1; }

[ -n "$REPORT" ] && {
  printf 'sources\n'
  printf '  A  ghostty   %s\n' "$SRC_A"
  printf '  B  wezterm   %s\n' "$SRC_B"
  printf '  C  system    %s\n' "${WSL_RGB:-<disabled>}"
  printf '  D  msfterm   %s\n\n' "$SRC_D"
  printf 'L1  two parsers x two vendored copies, all four cells must be one identical set\n'
  printf '      parser1 fixed-column     A rows=%s  B rows=%s\n' "$N_A1" "$N_B1"
  printf '      parser2 whitespace-split A rows=%s  B rows=%s\n' "$N_A2" "$N_B2"
  printf '      folded table           = %s   four-way equal=yes (checked above, not printed)\n\n' "$N"
  printf '      the two copies are byte-different=%s  cksum A=%s B=%s  CR bytes A=%s B=%s\n\n' \
         "$SOURCES_DISTINCT" "$MD_A" "$MD_B" "$A_CRS" "$B_CRS"
  printf 'L2  the OS-packaged copy (%s vintage, third distribution channel)\n' "2020-10-09"
  printf '      C=%s rows  status=%s  only in A=%s (all newer upstream additions)  only in C=%s (debianred)\n' \
         "$N_C" "$L2C" \
         "$([ "$L2C" = ok ] && printf '%s' "$(printf '%s\n' "$A_ONLY" | grep -c . || true)" || printf '-')" \
         "$([ "$L2C" = ok ] && printf '%s' "$(printf '%s\n' "$C_ONLY" | grep -c . || true)" || printf '-')"
  printf '      shared-name value disagreements = 0 (a rename is not a redefinition)\n'
  printf '\nL3  msfterm'"'"'s own derivation (%s expanded keys)\n' "$N_D"
  printf '      agreed=%s  allowed-diff=%s  msfterm-only=%s (all "<family>0")\n' "$MSFT_AGREE" "$MSFT_DIFF" "$MSFT_ONLY_N"
  exit 0
}

[ "$N" = "$EXPECT_N" ] || { printf 'unexpected table size %s (expected %s). If upstream really changed, edit EXPECT_N deliberately and re-read VERIFY.md.\n' "$N" "$EXPECT_N" >&2; exit 1; }

# ----------------------------------------------------------------------------------------
# Anchors. A table that parses cleanly and still gets red wrong is worse than no table. Every
# line below is a claim a reference implementation makes about itself, not our arithmetic.
# ----------------------------------------------------------------------------------------
anchor() {
  local want=$1 name=$2 rgb
  rgb=$(awk -F'\t' -v k="$name" '$1 == k { print $2 "/" $3 "/" $4; exit }' "$TAB")
  [ "$rgb" = "$want" ] || { printf 'anchor failed: %s is %s, expected %s\n' "$name" "${rgb:-<absent>}" "$want" >&2; exit 1; }
}
# ghostty src/terminal/x11_color.zig:83-95 -- its own test block
anchor 255/255/255 white
anchor   0/250/154 mediumspringgreen
anchor  34/139/34  forestgreen
anchor   0/0/0     black
anchor 255/0/0     red
anchor   0/255/0   green
anchor   0/0/255   blue
anchor 124/252/0   lawngreen
# the spellings #84 names in its acceptance text
anchor 127/127/127 gray50
anchor 127/127/127 grey50
anchor 173/216/230 lightblue
anchor 188/143/143 rosybrown
anchor 102/51/153  rebeccapurple
# the X11-vs-CSS pairs that share a word and must not be averaged: rgb.txt spells the X11 value
# with the bare word and the web value under web*/x11* (ghostty's copy lines 58/218/240).
anchor 190/190/190 gray
anchor 128/128/128 webgray
anchor 190/190/190 x11gray
anchor 160/32/240  purple
anchor 128/0/128   webpurple
anchor 176/48/96   maroon
anchor 128/0/0     webmaroon
anchor 0/255/255   aqua
anchor 127/255/212 aquamarine
# numbered rows are data here, not arithmetic: msfterm computes these and gets two wrong
anchor 127/255/212 aquamarine1
anchor 118/238/198 aquamarine2
anchor 102/205/170 aquamarine3
anchor  69/139/116 aquamarine4
# every numbered gray, both spellings, no gaps (202 rows)
for i in $(seq 0 100); do
  for s in gray grey; do
    awk -F'\t' -v k="$s$i" '$1 == k { found = 1 } END { exit !found }' "$TAB" \
      || { printf 'missing %s%s\n' "$s" "$i" >&2; exit 1; }
  done
done
# No key may be confusable with a hex spec. This is the fact that makes "parse the spec first,
# fall back to the name" safe regardless of which order a caller picks, so it is asserted rather
# than observed once: 0 keys start with a digit, and none starts with "rgb".
DIGIT_INITIAL=$(cut -f1 "$TAB" | grep -c '^[0-9]' || true)
[ "$DIGIT_INITIAL" = 0 ] || { printf '%s keys start with a digit, so a name could shadow a spec\n' "$DIGIT_INITIAL" >&2; exit 1; }
RGB_PREFIX=$(cut -f1 "$TAB" | grep -c '^rgb' || true)
[ "$RGB_PREFIX" = 0 ] || { printf '%s keys start with "rgb", so rgb:... would be ambiguous\n' "$RGB_PREFIX" >&2; exit 1; }

# wezterm synthesises transparent/none/clear as alpha 0 and rgb.txt has none of them; a palette
# entry has no alpha to carry, so they must stay absent.
for k in transparent none clear; do
  ! awk -F'\t' -v k="$k" '$1 == k { found = 1 } END { exit !found }' "$TAB" \
    || { printf '%s must not be in the table (no rgb.txt row; wezterm-only, alpha 0)\n' "$k" >&2; exit 1; }
done

# --dump-table: the verified extraction, one name<TAB>r<TAB>g<TAB>b row per entry, plus msfterm's
# own derivation beside it. x11_selftest.cpp reads these to check the header name-for-name --
# the L1 four-cell test compares two SETS built from the same pipeline and so cannot see a row
# that the emitter drops or duplicates. This closes that hole with a reader in a third language.
if [ -n "$DUMP" ]; then
  cp "$TAB" "$DATA/x11colors.table.tsv" || exit 1
  cp "$D3"  "$DATA/msfterm.table.tsv"  || exit 1
  printf 'wrote %s (%s rows) and %s (%s rows)\n' \
         "$DATA/x11colors.table.tsv" "$N" "$DATA/msfterm.table.tsv" "$N_D"
  exit 0
fi

TMP=$(mktemp)
{
  printf '/*\n'
  printf ' * GENERATED by cache/audit90/x11/gen_x11colors.sh -- DO NOT EDIT BY HAND.\n'
  printf ' *\n'
  printf ' * X11 colour names for OSC 4/10/11 (ticket #84), %s entries.\n' "$N"
  printf ' *\n'
  printf ' * Sources, all local:\n'
  printf ' *   A  %s\n' "$SRC_A"
  printf ' *   B  %s\n' "$SRC_B"
  printf ' *   C  %s   (2020-10-09 xorg package, status %s)\n' "${WSL_RGB:-<disabled>}" "$L2C"
  printf ' *   D  %s\n' "$SRC_D"
  printf ' *\n'
  printf ' * A and B are read by TWO different parsers -- ghostty'"'"'s fixed-column slicing\n'
  printf ' * (x11_color.zig:45-48) and wezterm'"'"'s whitespace splitting (color-types/src/lib.rs:393-403)\n'
  printf ' * -- and both must return one identical set. D is a third, independently derived table.\n'
  printf ' *\n'
  printf ' * The two vendored copies are NOT byte-identical, which is what makes agreeing worth anything:\n'
  printf ' * B is CRLF (%s CR bytes vs A'"'"'s %s) and %s of its lines re-pad a numeric column with a TAB\n' "$B_CRS" "$A_CRS" "$REFLOW"
  printf ' * where A uses a space, so "139 121  94" is "139 121\\t 94" in B. ghostty'"'"'s positional rule\n'
  printf ' * tolerates that only because it trims each 3-column field and no digit moved past column 11;\n'
  printf ' * all four readings return one identical set of %s tuples. The assertion is there for the\n' "$N"
  printf ' * refresh that does move one -- it would shift a component by a factor of 16 without changing\n'
  printf ' * any row count, which is invisible to a check that reads one file with one parser.\n'
  printf ' *\n'
  printf ' * Keys are folded the way msfterm folds a query (colorTable.cpp:296-334): ASCII lowercase,\n'
  printf ' * spaces dropped. rgb.txt spells every multi-word name twice -- "medium spring green" and\n'
  printf ' * "MediumSpringGreen" -- and folding the %s source rows together is collision-free, which\n' "$ROWS_A"
  printf ' * is what lets %s entries accept every upstream spelling.\n' "$N"
  printf ' *\n'
  printf ' * Where the references disagree, X11 wins and it is recorded, not dropped:\n'
  printf ' *   gray50/grey50  X11 127 127 127  vs MSFT ((50*255)+50)/100 = 128   colorTable.cpp:353\n'
  printf ' *   gray90/grey90  X11 229 229 229  vs MSFT ((90*255)+50)/100 = 230   colorTable.cpp:353\n'
  printf ' * X11 has no "<family>0" row (msfterm invents one per variant family) and no\n'
  printf ' * "transparent"/"none"/"clear" (wezterm invents those three, as alpha 0). A palette entry\n'
  printf ' * has no alpha to carry, so none of the four names appear below.\n'
  printf ' */\n\n'
  printf '#ifndef DBCLI_CONEMU_X11COLORNAMES_H\n#define DBCLI_CONEMU_X11COLORNAMES_H\n\n'
  printf '#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n\n'
  printf '#ifdef __cplusplus\nextern "C" {\n#endif\n\n'
  printf 'typedef struct X11ColorEntry\n'
  printf '{\n'
  printf '  const char *name;   /* folded key: ASCII lowercase, no spaces, NUL terminated */\n'
  printf '  uint8_t r, g, b;    /* 8 bits per component, straight from rgb.txt columns 1-11 */\n'
  printf '} X11ColorEntry;\n\n'
  printf '/* Sorted by name in C byte order over [a-z0-9] -- that is what makes the binary search\n'
  printf '   below legal, and what lets --check diff this file line by line. */\n'
  printf 'static const X11ColorEntry X11ColorTable[] =\n'
  printf '{\n'
  awk -F'\t' '{ printf "  { \"%s\", %3d, %3d, %3d },\n", $1, $2, $3, $4 }' "$TAB"
  printf '};\n'
  printf '#define X11_COLOR_COUNT ((int)(sizeof X11ColorTable / sizeof X11ColorTable[0]))\n\n'
  printf '/* Fold a wire name into a table key: ASCII lowercase, every byte <= space dropped, anything\n'
  printf '   above 0x7F refused. Returns the folded length, or -1 when the input cannot be a name.\n'
  printf "   This is msfterm's loop (colorTable.cpp:302-334) minus its variant-index split, because\n"
  printf '   this table spells gray50 and aquamarine1 out as rows instead of computing them. */\n'
  printf 'static inline int x11_color_fold(const uint16_t *p, int n, char *out, int cap)\n'
  printf '{\n'
  printf '  int k = 0;\n'
  printf '  if (n < 1 || n > 31) return -1;                /* the longest key here is 20 */\n'
  printf '  for (int i = 0; i < n; i++)\n'
  printf '  {\n'
  printf '    uint16_t u = p[i];\n'
  printf '    if (u <= 0x20) continue;                     /* space and tab, and the other C0 gaps */\n'
  printf "    if (u > 127) return -1;                      /* \"X11 guarantees Latin1\" -- colorTable.cpp:306 */\n"
  printf "    if (u >= (uint16_t)'A' && u <= (uint16_t)'Z') u = (uint16_t)(u + 32);\n"
  printf '    if (k >= cap - 1) return -1;\n'
  printf '    out[k++] = (char)u;\n'
  printf '  }\n'
  printf '  out[k] = 0;\n'
  printf '  return k;\n'
  printf '}\n\n'
  printf '/* Binary search a folded key. Returns 0x00BBGGRR -- the COLORREF order color_spec_of\n'
  printf '   already produces (Render.cpp:2556) -- or -1 for an unknown name. */\n'
  printf 'static inline int x11_color_lookup(const char *key)\n'
  printf '{\n'
  printf '  int lo = 0, hi = X11_COLOR_COUNT - 1;\n'
  printf '  while (lo <= hi)\n'
  printf '  {\n'
  printf '    const int mid = lo + ((hi - lo) >> 1);\n'
  printf '    const int c = strcmp(X11ColorTable[mid].name, key);\n'
  printf '    if (c == 0)\n'
  printf '      return (X11ColorTable[mid].b << 16) | (X11ColorTable[mid].g << 8) | X11ColorTable[mid].r;\n'
  printf '    if (c < 0) lo = mid + 1; else hi = mid - 1;\n'
  printf '  }\n'
  printf '  return -1;\n'
  printf '}\n\n'
  printf '/* The wire shapes this build accepts, from the same r/g/b. Each round-trips exactly\n'
  printf '   through comp_of (Render.cpp:2509-2521), which is why the table stores 8 bits per\n'
  printf '   component instead of pre-formatted strings -- a stored string can drift from the\n'
  printf '   number beside it and nothing downstream would notice:\n'
  printf '     rgb:rr/gg/bb   2 digits per component  n==2 -> v                   the byte\n'
  printf '     #rrggbb        2 digits per component  n==2 -> v                   the byte\n'
  printf '     #rrrgggbbb     3 digits per component  n==3 -> v >> 4              (byte<<4)>>4\n'
  printf '     #rrrrggggbbbb  4 digits per component  n==4 -> v >> 8              (byte*0x101)>>8\n'
  printf '   The last width is the one the query reply already emits (RenderJni.cpp:733-738).\n'
  printf '   #RGB is the single shape that cannot say every entry: n==1 scales by 0x11, so it\n'
  printf '   reaches only the 16 replicated nibbles and gray50 (0x7F) is not one of them. That is\n'
  printf '   a limit of the shape, not of the table, and it is why the gate pins red through all\n'
  printf '   four and gray50 through the three that can express it. */\n'
  printf '#define X11_COLOR_SHAPE_CAP 32\n'
  printf 'static inline int x11_color_format(char *buf, int cap, const char *shape, uint8_t r, uint8_t g, uint8_t b)\n'
  printf '{\n'
  printf '  int n;\n'
  printf '  if (!strcmp(shape, "rgb2"))\n'
  printf '    n = snprintf(buf, cap, "rgb:%%02x/%%02x/%%02x", r, g, b);\n'
  printf '  else if (!strcmp(shape, "hash6"))\n'
  printf '    n = snprintf(buf, cap, "#%%02x%%02x%%02x", r, g, b);\n'
  printf '  else if (!strcmp(shape, "hash9"))\n'
  printf '    n = snprintf(buf, cap, "#%%03x%%03x%%03x", (unsigned)r << 4, (unsigned)g << 4, (unsigned)b << 4);\n'
  printf '  else if (!strcmp(shape, "hash12"))\n'
  printf '    n = snprintf(buf, cap, "#%%04x%%04x%%04x", r * 0x0101u, g * 0x0101u, b * 0x0101u);\n'
  printf '  else return -1;\n'
  printf '  return (n > 0 && n < cap) ? n : -1;\n'
  printf '}\n\n'
  printf '#ifdef __cplusplus\n}\n#endif\n\n'
  printf '#endif /* DBCLI_CONEMU_X11COLORNAMES_H */\n'
} > "$TMP" || { printf 'header emission failed\n' >&2; rm -f "$TMP"; exit 1; }

# Emission self-check: every C format string here goes through bash printf, which silently eats a
# bare %02x and turns it into 00 -- the header then still compiles and answers #000000 for
# everything. This exact bug happened once; the guard is the reason it cannot happen quietly again.
grep -qF 'snprintf(buf, cap, "rgb:%02x/%02x/%02x", r, g, b)' "$TMP" \
  || { printf 'emission mangled the C format strings (unescaped %% in this script)\n' >&2; rm -f "$TMP"; exit 1; }
grep -qF 'snprintf(buf, cap, "#%04x%04x%04x"' "$TMP" \
  || { printf 'emission mangled the hash12 format string\n' >&2; rm -f "$TMP"; exit 1; }

if [ -n "$CHECK" ]; then
  if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
    printf 'X11ColorNames.h: up to date OK (%s entries)\n' "$N"; rm -f "$TMP"; exit 0
  fi
  printf 'X11ColorNames.h: STALE (rerun gen_x11colors.sh) or missing\n'; rm -f "$TMP"; exit 1
fi

mv "$TMP" "$OUT"
printf 'wrote %s (%s entries, %s bytes)\n' "$OUT" "$N" "$(wc -c < "$OUT" | tr -d ' ')"
