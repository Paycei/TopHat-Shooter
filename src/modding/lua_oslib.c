/* Lua's os library (vendor/lua/loslib.c, unmodified) with the same os.date
   formats on every platform: C99's one-letter conversions, which both the
   Windows UCRT and glibc implement (Lua's own list differs per platform, so
   "%F" would work on Linux and fail on Windows). Compiled by lua_c.nim. */
#define LUA_STRFTIMEOPTIONS "aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ%"
#include "../../vendor/lua/loslib.c"
