## Standalone invariant test for the SpatialGrid in src/enemy_helpers.nim.
##
## The grid acceleration in game.nim is only behaviour-preserving if every query
## returns a *superset* of the enemies genuinely within range -- i.e. it never
## drops an enemy the old full scan would have hit/considered. This brute-forces
## that property over thousands of random layouts + queries. Run:
##
##   nim r --mm:orc tests/test_spatial_grid.nim
##
## Query points are kept on-screen and radii bounded (matching real usage: bullets
## and enemies query around their own on-screen position), so far off-grid enemies
## that clamp into edge cells are never within range and so are never required.

import std/random
import "../src/types"
import "../src/enemy_helpers"  # SpatialGrid was integrated here (was: spatial_grid.nim)

proc main() =
  randomize(20260613)
  var trials = 0
  var checkedInRange = 0
  var misses = 0

  const
    ScreenW = 1920.0'f32
    ScreenH = 1080.0'f32
    Margin  = 200.0'f32
    Cell    = 96.0'f32

  for trial in 0 ..< 5000:
    inc trials
    let n = rand(0 .. 80)
    var enemies: seq[Enemy] = @[]
    for _ in 0 ..< n:
      let e = Enemy()
      # Spawn across the play area incl. just off-screen (still inside the grid
      # margin), so clamping is exercised but stays out of on-screen query range.
      e.pos = newVector2f(rand(-150.0 .. ScreenW.float + 150.0).float32,
                          rand(-150.0 .. ScreenH.float + 150.0).float32)
      e.radius = rand(8.0 .. 40.0).float32
      enemies.add(e)

    var grid: SpatialGrid
    grid.rebuild(enemies, Cell, -Margin, -Margin, ScreenW + Margin, ScreenH + Margin)

    # A handful of random on-screen queries per layout.
    for _ in 0 ..< 8:
      let qp = newVector2f(rand(0.0 .. ScreenW.float).float32,
                           rand(0.0 .. ScreenH.float).float32)
      let qr = rand(4.0 .. 160.0).float32

      var found = newSeq[bool](n)
      for idx in grid.nearby(qp, qr):
        doAssert idx >= 0 and idx < n, "grid yielded out-of-range index " & $idx
        found[idx] = true

      # Every enemy within Euclidean qr must be among the grid's candidates.
      for i in 0 ..< n:
        if distance(enemies[i].pos, qp) <= qr:
          inc checkedInRange
          if not found[i]:
            inc misses
            echo "MISS trial=", trial, " i=", i,
                 " dist=", distance(enemies[i].pos, qp), " qr=", qr,
                 " epos=(", enemies[i].pos.x, ",", enemies[i].pos.y, ")"

  echo "trials=", trials, " in-range checks=", checkedInRange, " misses=", misses
  doAssert misses == 0, "spatial grid dropped in-range enemies -- NOT a superset!"
  echo "PASS: spatial_grid.nearby is a non-lossy superset"

main()
