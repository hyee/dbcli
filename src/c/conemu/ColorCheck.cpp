
#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <cstring>

#ifdef __linux__
#include <stdbool.h>
typedef uint16_t WORD;
typedef uint8_t  BYTE;
typedef uint32_t DWORD;
typedef uint32_t COLORREF;
typedef int      BOOL;
#define FALSE 0
#define TRUE  1
#else
#include <windows.h>
#endif

#include "vendor/ConEmuColors3.h"

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

static void emit_fold(int n, COLORREF c, int direct)
{
  WORD fg = 0, a7 = 7, as = 7;
  if (direct)
  {
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
