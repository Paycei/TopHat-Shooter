## Cosmetic randomness: particles, damage-number sprays, screen shake and the
## other pure-presentation jitter draw from their own generator, never from
## std/random's global one. Gameplay rolls (spawns, crits, drafts, drops) keep
## the global stream to themselves, so how many particles a frame happens to
## spawn (a setting, a refactor, a co-op client replaying the host's effects)
## can never shift what the simulation rolls next.
##
## The modules that use it import this instead of std/random: the overloads
## below mirror std/random's global `rand` forms, so their call sites are
## unchanged.

import std/random as stdrandom

var fxRng = initRand()

proc seedFxRand*(seed: int64) =
  ## Fixed cosmetic stream (tests and replays); the game seeds it from the clock.
  fxRng = initRand(seed)

proc rand*(max: int): int = fxRng.rand(max)
proc rand*(max: float): float = fxRng.rand(max)
proc rand*[T: Ordinal or SomeFloat](x: HSlice[T, T]): T = fxRng.rand(x)
