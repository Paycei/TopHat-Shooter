/* Lua's package library (vendor/lua/loadlib.c, unmodified) without native
   modules: luaconf.h turns on DLL loading for every Windows build, so it is
   switched off here before loadlib.c sees it. package.loadlib and the C
   searchers then answer "dynamic libraries not enabled", and a mod can only
   ever load Lua, which runs the same on every platform. The Lua searcher's
   file probes go through the mod file sandbox (lua_files.h), so package.path
   only finds files in the running mod's folders. Compiled by lua_c.nim. */
#include "lua_files.h"
#include "../../vendor/lua/luaconf.h"
#undef LUA_DL_DLL
#undef LUA_USE_DLOPEN
#include "../../vendor/lua/loadlib.c"
