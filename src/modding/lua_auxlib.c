/* Lua's auxiliary library (vendor/lua/lauxlib.c, unmodified) inside the mod
   file sandbox (lua_files.h): luaL_loadfilex, behind loadfile and dofile,
   only reads files in the running mod's folders. The game itself never loads
   a chunk from a file name (lua_bridge loads buffers). Compiled by lua_c.nim. */
#include <stdarg.h>
#include "lua_files.h"
#include "../../vendor/lua/lauxlib.c"
