import raylib, math
import ../localization, background_fx

const
  WaveBars = 44          # bars in the "audio compiler" visualizer
  BarSmoothing = 7.0'f32 # how fast the drawn fill catches up with the real one

type
  LoadingStage* = enum
    lsSfx,     # synthesising sound effects
    lsMusic,   # synthesising music tracks
    lsMemory   # handing the finished WAVs to the audio device

  LoadingScreen* = ref object
    progress*: float32        # real progress reported by the loader (0..1)
    displayProgress: float32  # smoothed value actually drawn
    message*: string
    stage*: LoadingStage
    assetsDone*: int
    assetsTotal*: int
    animTime*: float32
    levels: array[WaveBars, float32]

proc newLoadingScreen*(): LoadingScreen =
  result = LoadingScreen(
    progress: 0.0,
    displayProgress: 0.0,
    message: t(tkLoadingInitializing),
    stage: lsSfx,
    assetsDone: 0,
    assetsTotal: 0,
    animTime: 0.0
  )
  # Seed the visualizer so the strip is already "playing" on the first frame
  # instead of ramping up from a flat line.
  for i in 0..<WaveBars:
    result.levels[i] = 0.35'f32 + abs(sin(i.float32 * 0.7'f32)) * 0.45'f32

proc update*(screen: LoadingScreen, dt: float32) =
  screen.animTime += dt

  # Ease the bar toward the reported value. Generation finishes one whole asset
  # at a time, so the raw progress arrives in big jumps; without this the bar
  # teleports.
  let t = clamp(dt * BarSmoothing, 0.0'f32, 1.0'f32)
  screen.displayProgress += (screen.progress - screen.displayProgress) * t

  # Visualizer levels: a cheap layered-sine "signal" per bar, so the strip
  # keeps moving every frame and proves the app is alive even when one long
  # music track is being synthesised.
  for i in 0..<WaveBars:
    let f = i.float32
    let signal = sin(screen.animTime * 5.3 + f * 0.42) * 0.5 +
                 sin(screen.animTime * 2.1 + f * 0.17) * 0.32 +
                 sin(screen.animTime * 8.7 - f * 0.71) * 0.18
    let target = clamp(0.2'f32 + abs(signal) * 1.0'f32, 0.12, 1.0)
    screen.levels[i] += (target - screen.levels[i]) * clamp(dt * 12.0, 0.0'f32, 1.0'f32)

proc setProgress*(screen: LoadingScreen, progress: float32, message: string = "") =
  screen.progress = clamp(progress, 0.0, 1.0)
  if message.len > 0:
    screen.message = message

proc setStage*(screen: LoadingScreen, stage: LoadingStage) =
  screen.stage = stage

proc setAssetCounts*(screen: LoadingScreen, done, total: int) =
  screen.assetsDone = done
  screen.assetsTotal = total

proc drawStagePill(x, y: int32, label: string, state: int, animTime: float32): int32 =
  ## state: 0 = pending, 1 = active, 2 = done. Returns the pill width.
  const padX: int32 = 10
  let textW = measureText(label, 14)
  let w = textW + padX * 2 + 18
  const h: int32 = 22

  var bg = Color(r: 22, g: 26, b: 40, a: 235)
  var border = Color(r: 60, g: 78, b: 104, a: 255)
  var fg = Color(r: 110, g: 130, b: 158, a: 255)
  var marker = "-"

  case state
  of 2:
    bg = Color(r: 18, g: 44, b: 40, a: 235)
    border = Color(r: 60, g: 170, b: 140, a: 255)
    fg = Color(r: 130, g: 230, b: 195, a: 255)
    marker = "x"
  of 1:
    let pulse = uint8((sin(animTime * 6.0) * 0.25 + 0.75) * 255.0)
    bg = Color(r: 16, g: 40, b: 66, a: 235)
    border = Color(r: 0, g: 170, b: 255, a: pulse)
    fg = Color(r: 170, g: 220, b: 255, a: 255)
    marker = ">"
  else:
    discard

  drawRectangle(x, y, w, h, bg)
  drawRectangleLines(x, y, w, h, border)
  drawText(marker, x + padX, y + 4, 14, fg)
  drawText(label, x + padX + 14, y + 4, 14, fg)
  result = w

proc draw*(screen: LoadingScreen, screenWidth, screenHeight: int32) =
  drawSharedBackdrop(screenWidth, screenHeight, screen.animTime * 0.7,
                     Color(r: 9, g: 12, b: 24, a: 255),
                     Color(r: 18, g: 20, b: 34, a: 255),
                     Color(r: 28, g: 36, b: 58, a: 40),
                     Color(r: 74, g: 104, b: 160, a: 74),
                     Color(r: 0, g: 170, b: 235, a: 56),
                     0.8, 0.8)

  let centerX = screenWidth div 2
  let centerY = screenHeight div 2

  # OS "installer window"
  let panelW: int32 = min(660'i32, screenWidth - 80'i32)
  const panelH: int32 = 230
  const titleBarH: int32 = 26
  let panelX = centerX - panelW div 2
  let panelY = centerY - panelH div 2 + 40

  drawSoftGlow(centerX.float32, (panelY + panelH div 2).float32, 300.0,
               Color(r: 0, g: 170, b: 255, a: 26), 0.9)

  # Branding above the window
  let titleText = t(tkLoadingTitle)
  const titleSize: int32 = 44
  let titleWidth = measureText(titleText, titleSize)
  drawText(titleText, centerX - titleWidth div 2, panelY - 118, titleSize,
           Color(r: 180, g: 220, b: 255, a: 255))

  let subtitleText = t(tkLoadingSubtitle)
  const subtitleSize: int32 = 20
  let subtitleWidth = measureText(subtitleText, subtitleSize)
  drawText(subtitleText, centerX - subtitleWidth div 2, panelY - 66, subtitleSize,
           Color(r: 140, g: 180, b: 220, a: 200))

  # Window body + chrome
  drawRectangle(panelX + 4, panelY + 6, panelW, panelH, Color(r: 0, g: 0, b: 0, a: 110))
  drawRectangle(panelX, panelY, panelW, panelH, Color(r: 14, g: 17, b: 28, a: 242))
  drawRectangleLines(panelX, panelY, panelW, panelH, Color(r: 70, g: 105, b: 150, a: 255))
  drawRectangle(panelX, panelY, panelW, titleBarH, Color(r: 26, g: 40, b: 66, a: 255))
  drawRectangle(panelX, panelY + titleBarH - 1, panelW, 1, Color(r: 70, g: 105, b: 150, a: 255))
  drawText("audio_setup.exe", panelX + 10, panelY + 6, 14,
           Color(r: 190, g: 220, b: 250, a: 255))

  # Decorative (inert) window buttons
  var btnX = panelX + panelW - 22
  for label in ["x", "o", "-"]:
    drawRectangleLines(btnX, panelY + 5, 16, 16, Color(r: 80, g: 110, b: 150, a: 200))
    drawText(label, btnX + 5, panelY + 6, 14, Color(r: 150, g: 180, b: 210, a: 220))
    btnX -= 20

  let contentX = panelX + 18
  let contentW = panelW - 36
  var y = panelY + titleBarH + 14

  # Stage pills + asset counter
  var pillX = contentX
  let stageOrd = screen.stage.ord
  for i, label in [t(tkLoadingStageSfx), t(tkLoadingStageMusic), t(tkLoadingStageMemory)]:
    let state = if i < stageOrd: 2 elif i == stageOrd: 1 else: 0
    pillX += drawStagePill(pillX, y, label, state, screen.animTime) + 8

  if screen.assetsTotal > 0:
    let counter = $screen.assetsDone & " / " & $screen.assetsTotal & " " & t(tkLoadingAssets)
    let counterW = measureText(counter, 14)
    drawText(counter, contentX + contentW - counterW, y + 4, 14,
             Color(r: 130, g: 160, b: 190, a: 255))
  y += 36

  # Current task line, with the classic animated dots
  let msgSize: int32 = 16
  drawText(screen.message, contentX, y, msgSize,
           Color(r: 205, g: 220, b: 240, a: 255))
  let msgWidth = measureText(screen.message, msgSize)
  var dotStr = ""
  for _ in 0..<(int(screen.animTime * 2.0) mod 4):
    dotStr.add(".")
  drawText(dotStr, contentX + msgWidth + 4, y, msgSize,
           Color(r: 205, g: 220, b: 240, a: 255))
  y += 30

  # Progress bar
  const barHeight: int32 = 26
  let barX = contentX
  let barY = y
  let barWidth = contentW
  drawRectangle(barX, barY, barWidth, barHeight, Color(r: 8, g: 10, b: 18, a: 255))
  drawRectangleLines(barX - 1, barY - 1, barWidth + 2, barHeight + 2,
                     Color(r: 90, g: 130, b: 175, a: 255))

  let fillWidth = int32(barWidth.float32 * screen.displayProgress)
  if fillWidth > 0:
    let pulse = sin(screen.animTime * 3.0) * 0.12 + 0.88
    drawRectangle(barX, barY, fillWidth, barHeight,
                  Color(r: uint8(60.0 * pulse), g: uint8(150.0 * pulse),
                        b: uint8(230.0 * pulse), a: 255))
    drawRectangle(barX, barY, fillWidth, barHeight div 3,
                  Color(r: 120, g: 200, b: 255, a: 90))
    # Leading edge highlight
    drawRectangle(barX + fillWidth - 2, barY, 2, barHeight,
                  Color(r: 190, g: 235, b: 255, a: 220))

    # Marquee shine sweeping across the filled part, so the bar keeps moving
    # even while a single long track is being generated.
    let sweep = (screen.animTime * 0.55) mod 1.0
    let shineX = barX + int32(fillWidth.float32 * sweep)
    let shineW = max(1'i32, fillWidth div 8)
    if shineW > 1:
      beginScissorMode(barX, barY, fillWidth, barHeight)
      drawRectangle(shineX, barY, shineW, barHeight,
                    Color(r: 255, g: 255, b: 255, a: 26))
      endScissorMode()

  # Segment ticks over the whole bar for that "installer" texture
  var tick: int32 = 1
  while tick < 10:
    let tx = barX + int32(barWidth.float32 * (tick.float32 / 10.0))
    drawRectangle(tx, barY, 1, barHeight, Color(r: 0, g: 0, b: 0, a: 70))
    inc tick

  let percentText = $(int(screen.displayProgress * 100.0)) & "%"
  let percentWidth = measureText(percentText, 16)
  drawText(percentText, barX + barWidth div 2 - percentWidth div 2, barY + 5, 16, White)
  y += barHeight + 16

  # Audio "compiler" visualizer: bars behind the playhead are lit, ahead dim.
  const stripH: int32 = 38
  drawRectangle(barX, y, barWidth, stripH, Color(r: 8, g: 10, b: 18, a: 200))
  let slot = barWidth.float32 / WaveBars.float32
  let playhead = screen.displayProgress * WaveBars.float32
  for i in 0..<WaveBars:
    let h = max(2'i32, int32(screen.levels[i] * (stripH - 6).float32))
    let bx = barX + int32(i.float32 * slot) + 1
    let bw = max(1'i32, int32(slot) - 2)
    let lit = i.float32 < playhead
    let col = if lit: Color(r: 90, g: 200, b: 255, a: 235)
              else: Color(r: 46, g: 62, b: 88, a: 200)
    drawRectangle(bx, y + (stripH - h) div 2, bw, h, col)
  drawRectangleLines(barX, y, barWidth, stripH, Color(r: 50, g: 74, b: 105, a: 255))
  y += stripH + 12

  # Cache note: explains why the first launch is the slow one.
  let note = t(tkLoadingCacheNote)
  drawText(note, contentX, y, 14, Color(r: 120, g: 150, b: 180, a: 220))

  # Bottom hint text - animated
  let alpha = uint8((sin(screen.animTime * 2.0) * 0.3 + 0.7) * 255.0)
  let hintText = t(tkLoadingHint)
  const hintSize: int32 = 14
  let hintWidth = measureText(hintText, hintSize)
  drawText(hintText, centerX - hintWidth div 2, screenHeight - 60, hintSize,
           Color(r: 120, g: 150, b: 180, a: alpha))
