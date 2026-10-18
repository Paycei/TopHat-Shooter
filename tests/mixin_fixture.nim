# {.moddable.} procs of every shape the mixin layer must handle, for
# tests/test_mod_patch.nim (no game code: the shapes are what matters).

import ../src/modding/mod_patch_core

type
  Stats* = object
    damage*, rate*: float32
  Box* = ref object
    n*: int
  Kind* = enum kA, kB

var counter* = 0   ## how many times counted()'s original body ran

proc plain*(a: int, b = 2): int {.moddable.} = a * 10 + b

proc scale*(stats: var Stats, k: float32) {.moddable.} =
  stats.damage *= k

proc total*(xs: openArray[int]): int {.moddable.} =
  for x in xs: result += x

proc fact*(n: int): int {.moddable.} =
  if n <= 1: 1 else: n * fact(n - 1)

proc name*(k: Kind): string {.moddable.} = "k:" & $k
proc name*(s: string): string {.moddable.} = "s:" & s

proc makeStats*(d: float32): Stats {.moddable.} = Stats(damage: d, rate: 1)

proc boxed*(b: Box): int {.moddable.} = b.n

proc trio*(): array[3, Stats] {.moddable.} =
  for i in 0 ..< 3: result[i] = Stats(damage: float32(i), rate: 1)

proc raiser*(x: int): int {.moddable.} =
  if x < 0: raise newException(ValueError, "negative")
  x

proc counted*(): int {.moddable.} =
  inc counter
  counter

proc noArgs*(): int {.moddable.} = 7

proc setOf*(s: set[Kind] = {kA}): int {.moddable.} = card(s)

func pure*(a, b: int): int {.moddable.} = a + b

proc callback*(f: proc (x: int): int {.nimcall.}): int {.moddable.} = f(1)

proc notice*(msg: string) {.moddable.} =
  discard msg

proc helper*(x: int, k = 3): int =
  ## Not moddable: engine.call can call it, mixins cannot wrap it.
  x * k
