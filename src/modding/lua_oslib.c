/* Lua's os library (vendor/lua/loslib.c, unmodified) with the same os.date
   formats on every platform: C99's one-letter conversions, which both the
   Windows UCRT and glibc implement (Lua's own list differs per platform, so
   "%F" would work on Linux and fail on Windows), and inside the mod file
   sandbox (lua_files.h): os.remove and os.rename only touch the running mod's
   mod.dataDir(), and os.tmpname, which names a file outside it, always fails.
   Compiled by lua_c.nim. */
#include <locale.h>
#include <time.h>
#include "lua_files.h"
#define lua_tmpnam(b,e) { (b)[0] = '\0'; e = 1; }
#define LUA_TMPNAMBUFSIZE 1
#define LUA_STRFTIMEOPTIONS "aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ%"
#include "../../vendor/lua/loslib.c"
