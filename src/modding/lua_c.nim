## Raw bindings to the vendored Lua 5.5 (src/modding/lua, see its LICENSE).
##
## The C sources are compiled straight into the executable (no DLL), so every
## build target (MSVC, the WSL Linux build, the Android NDK) gets the same Lua.
## Only what lua_bridge.nim uses is declared here; the macros of lua.h are
## re-expressed as templates. Everything else in the mod system goes through
## lua_bridge, never through these directly.

# Lua's number semantics (NaN keys are errors, exact integer/float
# conversions) need IEEE math: the release tasks' /fp:fast and -ffast-math are
# undone for these files only.
when defined(vcc):
  const LuaCFlags = "/fp:precise"
else:
  const LuaCFlags = "-fno-fast-math"

{.compile("lua/lapi.c", LuaCFlags).}
{.compile("lua/lcode.c", LuaCFlags).}
{.compile("lua/lctype.c", LuaCFlags).}
{.compile("lua/ldebug.c", LuaCFlags).}
{.compile("lua/ldo.c", LuaCFlags).}
{.compile("lua/ldump.c", LuaCFlags).}
{.compile("lua/lfunc.c", LuaCFlags).}
{.compile("lua/lgc.c", LuaCFlags).}
{.compile("lua/llex.c", LuaCFlags).}
{.compile("lua/lmem.c", LuaCFlags).}
{.compile("lua/lobject.c", LuaCFlags).}
{.compile("lua/lopcodes.c", LuaCFlags).}
{.compile("lua/lparser.c", LuaCFlags).}
{.compile("lua/lstate.c", LuaCFlags).}
{.compile("lua/lstring.c", LuaCFlags).}
{.compile("lua/ltable.c", LuaCFlags).}
{.compile("lua/ltm.c", LuaCFlags).}
{.compile("lua/lundump.c", LuaCFlags).}
{.compile("lua/lvm.c", LuaCFlags).}
{.compile("lua/lzio.c", LuaCFlags).}
{.compile("lua/lauxlib.c", LuaCFlags).}
{.compile("lua/lbaselib.c", LuaCFlags).}
{.compile("lua/lcorolib.c", LuaCFlags).}
{.compile("lua/lmathlib.c", LuaCFlags).}
{.compile("lua/lstrlib.c", LuaCFlags).}
{.compile("lua/ltablib.c", LuaCFlags).}
{.compile("lua/lutf8lib.c", LuaCFlags).}

type
  LuaState* = distinct pointer
  LuaNumber* = float64
  LuaInteger* = int64
  LuaCFunction* = proc (L: LuaState): cint {.cdecl.}
  LuaHook* = proc (L: LuaState, ar: pointer) {.cdecl.}
  LuaAlloc* = proc (ud, p: pointer, osize, nsize: csize_t): pointer {.cdecl.}

const
  LUA_OK* = 0.cint
  LUA_MULTRET* = -1.cint
  LUA_REGISTRYINDEX* = cint(-(int32.high div 2 + 1000))

  LUA_TNONE* = -1.cint
  LUA_TNIL* = 0.cint
  LUA_TBOOLEAN* = 1.cint
  LUA_TLIGHTUSERDATA* = 2.cint
  LUA_TNUMBER* = 3.cint
  LUA_TSTRING* = 4.cint
  LUA_TTABLE* = 5.cint
  LUA_TFUNCTION* = 6.cint
  LUA_TUSERDATA* = 7.cint
  LUA_TTHREAD* = 8.cint

  LUA_RIDX_GLOBALS* = 2
  LUA_NOREF* = -2.cint
  LUA_REFNIL* = -1.cint

  LUA_MASKCOUNT* = cint(1 shl 3)

  LUA_GCCOLLECT* = 2.cint
  LUA_GCCOUNT* = 3.cint

{.push importc, cdecl.}
proc lua_newstate*(f: LuaAlloc, ud: pointer, seed: cuint): LuaState
proc lua_close*(L: LuaState)
proc lua_atpanic*(L: LuaState, panicf: LuaCFunction): LuaCFunction

proc lua_absindex*(L: LuaState, idx: cint): cint
proc lua_gettop*(L: LuaState): cint
proc lua_settop*(L: LuaState, idx: cint)
proc lua_pushvalue*(L: LuaState, idx: cint)
proc lua_rotate*(L: LuaState, idx, n: cint)
proc lua_checkstack*(L: LuaState, n: cint): cint

proc lua_isinteger*(L: LuaState, idx: cint): cint
proc lua_type*(L: LuaState, idx: cint): cint
proc lua_tonumberx*(L: LuaState, idx: cint, isnum: ptr cint): LuaNumber
proc lua_tointegerx*(L: LuaState, idx: cint, isnum: ptr cint): LuaInteger
proc lua_toboolean*(L: LuaState, idx: cint): cint
proc lua_tolstring*(L: LuaState, idx: cint, len: ptr csize_t): cstring
proc lua_rawlen*(L: LuaState, idx: cint): uint64
proc lua_touserdata*(L: LuaState, idx: cint): pointer
proc lua_topointer*(L: LuaState, idx: cint): pointer
proc lua_rawequal*(L: LuaState, idx1, idx2: cint): cint

proc lua_pushnil*(L: LuaState)
proc lua_pushnumber*(L: LuaState, n: LuaNumber)
proc lua_pushinteger*(L: LuaState, n: LuaInteger)
proc lua_pushlstring*(L: LuaState, s: cstring, len: csize_t): cstring
proc lua_pushstring*(L: LuaState, s: cstring): cstring
proc lua_pushcclosure*(L: LuaState, fn: LuaCFunction, n: cint)
proc lua_pushboolean*(L: LuaState, b: cint)
proc lua_pushlightuserdata*(L: LuaState, p: pointer)

proc lua_rawget*(L: LuaState, idx: cint): cint
proc lua_rawgeti*(L: LuaState, idx: cint, n: LuaInteger): cint
proc lua_rawgetp*(L: LuaState, idx: cint, p: pointer): cint
proc lua_createtable*(L: LuaState, narr, nrec: cint)
proc lua_newuserdatauv*(L: LuaState, sz: csize_t, nuvalue: cint): pointer
proc lua_getmetatable*(L: LuaState, objindex: cint): cint

proc lua_rawset*(L: LuaState, idx: cint)
proc lua_rawseti*(L: LuaState, idx: cint, n: LuaInteger)
proc lua_rawsetp*(L: LuaState, idx: cint, p: pointer)
proc lua_setmetatable*(L: LuaState, objindex: cint): cint

proc lua_pcallk*(L: LuaState, nargs, nresults, errfunc: cint, ctx: int, k: pointer): cint
proc lua_callk*(L: LuaState, nargs, nresults: cint, ctx: int, k: pointer)
proc lua_error*(L: LuaState): cint
proc lua_next*(L: LuaState, idx: cint): cint
proc lua_gc*(L: LuaState, what: cint): cint {.varargs.}
proc lua_sethook*(L: LuaState, fn: LuaHook, mask, count: cint)
proc lua_setupvalue*(L: LuaState, funcindex, n: cint): cstring

proc luaL_ref*(L: LuaState, t: cint): cint
proc luaL_unref*(L: LuaState, t, r: cint)
proc luaL_loadbufferx*(L: LuaState, buff: cstring, sz: csize_t, name, mode: cstring): cint
proc luaL_traceback*(L, L1: LuaState, msg: cstring, level: cint)
proc luaL_where*(L: LuaState, lvl: cint)
proc luaL_requiref*(L: LuaState, modname: cstring, openf: LuaCFunction, glb: cint)

proc luaopen_base*(L: LuaState): cint
proc luaopen_coroutine*(L: LuaState): cint
proc luaopen_table*(L: LuaState): cint
proc luaopen_string*(L: LuaState): cint
proc luaopen_math*(L: LuaState): cint
proc luaopen_utf8*(L: LuaState): cint
{.pop.}

proc isNil*(L: LuaState): bool {.inline.} = pointer(L).isNil

template lua_upvalueindex*(i: int): cint = LUA_REGISTRYINDEX - cint(i)
template lua_pop*(L: LuaState, n: int) = lua_settop(L, cint(-n - 1))
template lua_pcall*(L: LuaState, nargs, nresults, errfunc: cint): cint =
  lua_pcallk(L, nargs, nresults, errfunc, 0, nil)
template lua_insert*(L: LuaState, idx: cint) = lua_rotate(L, idx, 1)
template lua_newtable*(L: LuaState) = lua_createtable(L, 0, 0)
