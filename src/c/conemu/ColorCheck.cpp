// Portability + determinism check for the one ConEmu header the native writer would vendor verbatim.
//
// Built twice:
//   * cross (i686/x86_64-w64-mingw32) -> proves ConEmuColors3.h compiles for the real target
//     against the real windows.h;
//   * host (Linux g++)                -> lets us actually RUN the folding here, because there is
//     no wine on this box. The typedefs below are the whole price of that.
//
// Emits, for every 256-colour index and for the truecolour cube, the console index ConEmu would
// pick. Stage 1 diffs this table against the folding that shipped in the Java rectangle writer,
// BulkCellWriter, before it was retired on 2026-09-23 (the §12.4 / §14.1 fixes) - a full-domain
// cross-check instead of the 32 samples those rounds used.

#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <cstring>   // strcmp: mingw's windows.h pulled it in, a host clang does not

#ifdef __linux__
#include <stdbool.h>
typedef uint16_t WORD;
typedef uint8_t  BYTE;
typedef uint32_t DWORD;
typedef uint32_t COLORREF;   // 0x00BBGGRR, same convention as on Windows
typedef int      BOOL;       // ConEmuColors3.h needs this one too (Color2BgIndex)
#define FALSE 0
#define TRUE  1
#else
#include <windows.h>
#endif

#include "vendor/ConEmuColors3.h"   // verbatim copy of ConEmu's src/common header, BSD-3 notice intact

// ConEmu's RgbMap[0..15] is ClrMap[n&7] | (n>=8 ? 8 : 0), i.e. already console bit order - it is NOT
// a COLORREF, and that is why a low index skips Far3Color entirely (Ansi.cpp:777,780: the 24-bit flag
// is only set when the xterm index is > 15). RgbMap[16..255] is the xterm 6x6x6 cube plus greyscale
// ramp, as 0x00BBGGRR.
static COLORREF rgb_map(int n)
{
  if (n < 16)
  {
    static const int clr_map[8] = {0, 4, 2, 6, 1, 5, 3, 7};
    return (COLORREF)(clr_map[n & 7] | (n >= 8 ? 8 : 0));
  }
  int i = n - 16;
  if (i < 216)
  {
    static const int levels[6] = {0, 95, 135, 175, 215, 255};
    int r = levels[i / 36], g = levels[(i / 6) % 6], b = levels[i % 6];
    return (COLORREF)((b << 16) | (g << 8) | r);
  }
  int grey = 8 + (i - 216) * 10;
  return (COLORREF)((grey << 16) | (grey << 8) | grey);
}

// One comparable line per 256-colour index. Columns:
//   FOLD <n> <entry> <fg> <attrOnDefault7> <attrOnSameFg> <D|F>
// <entry> is ConEmu's RgbMap[n] itself: a console attribute when <D>, a 0x00BBGGRR COLORREF when <F>.
// The two attr columns are the whole attribute ExtPrepareColor would paint (fg nibble | bg nibble<<4)
// for this index used as the *background*, against the two foregrounds that matter:
//   attrOnDefault7  the default prompt colour (0x07), which is what "set a background only" collides
//                   with - \e[48;5;145m folds to 7 on top of a 7 foreground;
//   attrOnSameFg    the same colour used as the foreground too (\e[38;5;Nm\e[48;5;Nm).
// Both go through Color2BgIndex only when the entry is a COLORREF; a direct entry is shifted into
// place with no fold and no correction (ExtConsole.cpp:309-333). The correction itself is
// ConEmuColors3.h:152-158, and note its `BOOL Equal` argument is dead upstream - the bump is decided
// by Index==Con, not by the caller - so there is no "bg equals fg" column any more.
static void emit_fold(int n, COLORREF c, int direct)
{
  WORD fg = 0, a7 = 7, as = 7;
  if (direct)
  {
    // no fold, no correction: ExtPrepareColor shifts a direct entry into the background nibble over
    // whatever foreground it was given. Both columns still have to be built from their own seed.
    fg = (WORD)(c & 0xF);
    a7 = (WORD)(7 | ((WORD)c << 4));
    as = (WORD)(fg | ((WORD)c << 4));
  }
  else
  {
    Far3Color::Color2FgIndex(c, fg);
    a7 = 7;
    Far3Color::Color2BgIndex(c, FALSE, a7);
    as = fg;
    Far3Color::Color2BgIndex(c, FALSE, as);
  }
  printf("FOLD %d %u %u %u %u %c\n", n, (unsigned)c, (unsigned)(fg & 0xF), (unsigned)a7,
         (unsigned)as, direct ? 'D' : 'F');
}

static void emit_truecolour_probes()
{
  // the truecolour pairs a terminal application emits, painted the way ExtPrepareColor paints
  // them: the foreground nibble first, then the background through Color2BgIndex
  const COLORREF tc[] = {0x00808080, 0x00c0c0c0, 0x000000a0, 0x00ffd700, 0x001e90ff, 0x00000000,
                         0x00ffffff, 0x000000ff, 0x00ff0000, 0x00d7af5f};
  printf("# truecolour probes: TC <rgb> <attr both> <attr on default fg 7>\n");
  for (unsigned i = 0; i < sizeof(tc) / sizeof(tc[0]); i++)
  {
    WORD fg = 0;
    Far3Color::Color2FgIndex(tc[i], fg);
    WORD both = fg;
    Far3Color::Color2BgIndex(tc[i], FALSE, both);
    WORD on7 = 7;
    Far3Color::Color2BgIndex(tc[i], FALSE, on7);
    printf("TC %u %u %u\n", (unsigned)tc[i], (unsigned)both, (unsigned)on7);
  }
}

/** ConEmu's own RgbMap[256], extracted from src/ConEmuHk/Ansi.cpp by cache/conemu-stage1. */
static int load_table(const char* path, COLORREF* into)
{
  FILE* f = fopen(path, "r");
  if (!f)
  {
    printf("# cannot open table %s\n", path);
    return -1;
  }
  int n = 0, got = 0;
  unsigned v = 0;
  while (n < 256 && fscanf(f, "%d %u", &n, &v) == 2)
  {
    if (n >= 0 && n < 256)
    {
      into[n] = (COLORREF)v;
      got++;
    }
    n = (int)(n + 1);
  }
  fclose(f);
  if (got != 256)
    printf("# table incomplete: %d of 256 entries (refusing to compare)\n", got);
  return (got == 256) ? 0 : -1;
}

int main(int argc, char** argv)
{
  const int use_table = (argc > 2 && strcmp(argv[1], "--table") == 0);
  COLORREF table[256];
  if (use_table && load_table(argv[2], table) != 0)
    return 1;

  printf("# mode=%s\n", use_table ? "conemu-table" : "replica");
  printf("# FOLD index entry fg attrOnDefault7 attrOnSameFg directFlag\n");
  unsigned long checksum = 0;
  int replica_matches = 0;
  for (int n = 0; n < 256; n++)
  {
    COLORREF c = use_table ? table[n] : rgb_map(n);
    const int direct = (n < 16);
    if (use_table && rgb_map(n) == c)
      replica_matches++;
    WORD fg = 0, a7 = 7;
    if (direct)
    {
      fg = (WORD)(c & 0xF);
      a7 = (WORD)(7 | ((WORD)c << 4));
    }
    else
    {
      Far3Color::Color2FgIndex(c, fg);
      Far3Color::Color2BgIndex(c, FALSE, a7);
    }
    checksum = checksum * 1315423911u + (unsigned long)((fg << 8) | a7 | (n << 16));
    emit_fold(n, c, direct);
  }
  if (use_table)
    printf("# replica-vs-conemu table over all 256 entries: %d identical\n", replica_matches);
  emit_truecolour_probes();
  printf("# checksum %08lX\n", checksum);
  return 0;
}
