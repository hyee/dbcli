/*
 * HostTypes.h -- the handful of typedefs ConEmu's headers need when compiled off-Windows.
 *
 * ConEmuColors3.h and the generated RgbMap excerpt are kept byte-faithful to upstream, so instead of
 * editing them we satisfy their dependencies here. That is the whole reason the colour and parser
 * core can be *executed* on a Linux host: there is no wine on this box, and a Windows binary that
 * cannot be run is worth much less as an oracle than one that can.
 */

#ifndef ANSIRENDER_HOSTTYPES_H
#define ANSIRENDER_HOSTTYPES_H

#ifdef _WIN32
#include <windows.h>
#else
#include <stdint.h>
typedef uint16_t WORD;
typedef uint8_t  BYTE;
typedef uint32_t DWORD;
typedef uint32_t COLORREF;   /* 0x00BBGGRR, the same convention as on Windows */
typedef int      BOOL;       /* ConEmuColors3.h needs this one (Color2BgIndex) */
#ifndef FALSE
#define FALSE 0
#define TRUE  1
#endif
#endif

#endif /* ANSIRENDER_HOSTTYPES_H */
