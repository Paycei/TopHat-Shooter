## Shared animated background helpers used across menus and arenas.

import raylib, math
import ../utils
export utils  # propagate shared color/alpha helpers to importers of this module

const
  BACKDROP_STAR_LAYERS = 3
  BACKDROP_GRID_SIZE = 48

proc wrapCoord(value, limit: float32): float32 =
  if limit <= 0.0:
    return 0.0
  result = value - floor(value / limit).float32 * limit

proc fractCoord(value: float32): float32 =
  value - floor(value).float32

proc brightenChannel(value: uint8, delta: int): uint8 =
  uint8(clamp(value.int + delta, 0, 255))

proc drawSoftGlow*(centerX, centerY, radius: float32, color: Color, intensity: float32 = 1.0'f32) =
  if radius <= 0.0 or intensity <= 0.0:
    return

  var layer = 6
  while layer >= 1:
    let t = layer.float32 / 6.0
    let alpha = clampByteF(color.a.float32 * t * t * intensity)
    drawCircle(Vector2(x: centerX, y: centerY), radius * t, withAlpha(color, alpha))
    dec layer

proc drawParallaxStars(screenWidth, screenHeight: int32, time: float32,
                       accentColor: Color, alphaScale: float32) =
  var layer = 0
  while layer < BACKDROP_STAR_LAYERS:
    let starCount = 18 + layer * 12
    let speed = 4.0'f32 + layer.float32 * 7.5'f32
    let size = 1.0'f32 + layer.float32 * 0.55'f32
    let layerAlpha = (20.0'f32 + layer.float32 * 16.0'f32) * alphaScale

    var i = 0
    while i < starCount:
      let seed = i.float32 * 17.183'f32 + layer.float32 * 91.371'f32
      let baseX = fractCoord(sin(seed * 12.9898'f32) * 43758.5453'f32) * screenWidth.float32
      let baseY = fractCoord(sin((seed + 8.17'f32) * 78.233'f32) * 23421.631'f32) * screenHeight.float32
      let x = wrapCoord(baseX + time * speed, screenWidth.float32)
      let y = wrapCoord(
        baseY + sin(time * (0.28'f32 + layer.float32 * 0.07'f32) + seed) * (3.0'f32 + layer.float32 * 2.5'f32),
        screenHeight.float32
      )
      let twinkle =
        0.4'f32 +
        (sin(time * (1.8'f32 + layer.float32 * 0.45'f32) + seed * 2.8'f32) * 0.5'f32 + 0.5'f32) * 0.7'f32
      let starAlpha = clampByteF(layerAlpha * twinkle)
      let starColor =
        if layer == BACKDROP_STAR_LAYERS - 1:
          Color(
            r: brightenChannel(accentColor.r, 25),
            g: brightenChannel(accentColor.g, 20),
            b: brightenChannel(accentColor.b, 20),
            a: starAlpha
          )
        elif layer == 1:
          withAlpha(accentColor, starAlpha)
        else:
          Color(r: 180, g: 200, b: 235, a: starAlpha)

      drawCircle(Vector2(x: x, y: y), size, starColor)
      if layer == BACKDROP_STAR_LAYERS - 1 and i mod 7 == 0:
        drawLine(x.int32 - 6, y.int32, x.int32 + 6, y.int32, withAlpha(starColor, starAlpha div 3))
      inc i
    inc layer

proc drawDriftingGrid(screenWidth, screenHeight: int32, time: float32,
                      gridColor, nodeColor: Color) =
  let offsetX = wrapCoord(time * 9.0'f32, BACKDROP_GRID_SIZE.float32)
  let offsetY = wrapCoord(time * 4.0'f32, BACKDROP_GRID_SIZE.float32)

  var x = -BACKDROP_GRID_SIZE
  while x < screenWidth + BACKDROP_GRID_SIZE:
    let drawX = x.float32 + offsetX
    if drawX >= 0.0 and drawX <= screenWidth.float32:
      drawLine(drawX.int32, 0, drawX.int32, screenHeight, gridColor)
    x += BACKDROP_GRID_SIZE

  var y = -BACKDROP_GRID_SIZE
  while y < screenHeight + BACKDROP_GRID_SIZE:
    let drawY = y.float32 + offsetY
    if drawY >= 0.0 and drawY <= screenHeight.float32:
      drawLine(0, drawY.int32, screenWidth, drawY.int32, gridColor)
    y += BACKDROP_GRID_SIZE

  var gx = -BACKDROP_GRID_SIZE
  while gx < screenWidth + BACKDROP_GRID_SIZE:
    let drawX = gx.float32 + offsetX
    if drawX >= 0.0 and drawX <= screenWidth.float32:
      var gy = -BACKDROP_GRID_SIZE
      while gy < screenHeight + BACKDROP_GRID_SIZE:
        let drawY = gy.float32 + offsetY
        if drawY >= 0.0 and drawY <= screenHeight.float32:
          let cellX = gx div BACKDROP_GRID_SIZE
          let cellY = gy div BACKDROP_GRID_SIZE
          let pulse = sin(time * 1.25'f32 + (cellX + cellY).float32 * 0.45'f32) * 0.5'f32 + 0.5'f32
          let nodeRadius = if ((cellX + cellY) mod 4) == 0: 2.0'f32 else: 1.35'f32
          let nodeAlpha = clampByteF(nodeColor.a.float32 * (0.5'f32 + pulse * 0.5'f32))
          drawCircle(Vector2(x: drawX, y: drawY), nodeRadius, withAlpha(nodeColor, nodeAlpha))
        gy += BACKDROP_GRID_SIZE
    gx += BACKDROP_GRID_SIZE

proc drawSharedBackdrop*(screenWidth, screenHeight: int32, time: float32,
                         topColor, bottomColor: Color,
                         gridColor, nodeColor, accentColor: Color,
                         starAlphaScale: float32 = 1.0'f32,
                         sweepAlphaScale: float32 = 1.0'f32) =
  drawRectangleGradientV(0, 0, screenWidth, screenHeight, topColor, bottomColor)

  var band = 0
  while band < 12:
    let bandBase = band.float32 / 11.0'f32
    let driftY = wrapCoord(
      screenHeight.float32 * bandBase + time * (5.0'f32 + band.float32 * 0.45'f32),
      screenHeight.float32 + 140.0'f32
    ) - 70.0'f32
    let swayY = sin(time * (0.55'f32 + band.float32 * 0.04'f32) + band.float32 * 0.8'f32) * 20.0'f32
    let alpha = clampByteF((8.0'f32 + band.float32 * 0.8'f32) * sweepAlphaScale)
    drawLine(-40, (driftY + swayY).int32,
             screenWidth + 40, (driftY + 35.0'f32 + swayY * 0.4'f32).int32,
             withAlpha(accentColor, alpha))
    inc band

  drawParallaxStars(screenWidth, screenHeight, time, accentColor, starAlphaScale)
  drawDriftingGrid(screenWidth, screenHeight, time, gridColor, nodeColor)
