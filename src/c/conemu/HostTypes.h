#ifndef ANSIRENDER_HOSTTYPES_H
#define ANSIRENDER_HOSTTYPES_H

#ifdef _WIN32
#include <windows.h>
#else
#include <stdint.h>
typedef uint16_t WORD;
typedef uint8_t  BYTE;
typedef uint32_t DWORD;
typedef uint32_t COLORREF;
typedef int      BOOL;
#ifndef FALSE
#define FALSE 0
#define TRUE  1
#endif
#endif

#endif
