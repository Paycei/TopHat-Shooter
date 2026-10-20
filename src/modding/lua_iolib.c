/* Lua's io library (vendor/lua/liolib.c, unmodified) inside the mod file
   sandbox (lua_files.h): io.open, io.lines, io.input and io.output only open
   files in the running mod's folders. Compiled by lua_c.nim. */
#include <ctype.h>
#include <locale.h>
#include "lua_files.h"
#include "../../vendor/lua/liolib.c"
