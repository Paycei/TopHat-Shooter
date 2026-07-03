## Sandbox Setup Window
## Pre-game loadout configuration shown as an OS-style desktop window.
## Lets the player edit every core stat, pick a preset, or pull the "average"
## build for any wave, then launch the sandbox.

import raylib, math, strutils
import os_window, os_shop, ../types, ../player, ../localization, ../render_context

const
  SETUP_STAT_COUNT = 8
  SETUP_PRESET_COUNT = 7
  # Hold-to-repeat acceleration: the longer a +/- button is held, the bigger the
  # step becomes (x1 -> x2 -> x4 ...), so reaching large values is quick.
  HOLD_INITIAL_DELAY = 0.35'f32
  HOLD_REPEAT_INTERVAL = 0.06'f32

# Stat index -> meaning:
#   0 Max HP  1 Damage  2 Fire Rate  3 Move Speed
#   4 Bullet Speed  5 Walls  6 Coins  7 Start Wave

type
  SandboxWindowResult* = object
    shouldClose*: bool   ## True if the window should be hidden
    launchGame*: bool    ## True if the user pressed Start (load screen + enter game)

  SandboxWindow* = ref object
    window*: OSWindow
    config*: SandboxConfig
    selectedPreset*: int   ## Index of the highlighted preset (-1 = custom edits)
    # Hold-to-repeat state for the +/- steppers.
    holdStat: int          ## stat index currently held, -1 = none
    holdDir: float32       ## +1 for "+", -1 for "-"
    holdTimer: float32     ## counts down to the next repeat
    holdRepeats: int       ## repeats applied so far this hold (drives acceleration)

# --- Config helpers -------------------------------------------------------

proc playerToSandboxConfig*(p: Player): SandboxConfig =
  SandboxConfig(maxHp: p.maxHp, damage: p.damage, fireRate: p.fireRate,
                speed: p.speed, bulletSpeed: p.bulletSpeed, walls: p.walls,
                coins: p.coins, startWave: 1)

proc baseSandboxConfig*(): SandboxConfig =
  ## Wave-1 baseline, read straight from a fresh Player so it never drifts
  ## out of sync with newPlayer's defaults.
  playerToSandboxConfig(newPlayer(0, 0))

proc sandboxPresetConfig(index: int): SandboxConfig =
  let base = baseSandboxConfig()
  case index
  of 0: result = base                                  # Fresh Start (wave 1)
  of 1: result = sandboxWaveAverageConfig(base, 5)     # Early Game
  of 2: result = sandboxWaveAverageConfig(base, 15)    # Mid Game
  of 3: result = sandboxWaveAverageConfig(base, 30)    # Late Game
  of 4: result = sandboxWaveAverageConfig(base, 60)    # End Game
  of 5:                                                # Glass Cannon
    result = sandboxWaveAverageConfig(base, 20)
    result.damage *= 2.5'f32
    result.fireRate = max(0.05'f32, result.fireRate * 0.5'f32)
    result.maxHp = 1.0'f32
    result.coins = 2000
  of 6:                                                # Juggernaut
    result = sandboxWaveAverageConfig(base, 20)
    result.maxHp *= 3.0'f32
    result.walls += 50
    result.speed *= 0.85'f32
    result.coins = 2000
  else: result = base

proc sandboxPresetNameKey(index: int): TranslationKey =
  case index
  of 0: tkSandboxPresetFresh
  of 1: tkSandboxPresetEarly
  of 2: tkSandboxPresetMid
  of 3: tkSandboxPresetLate
  of 4: tkSandboxPresetEnd
  of 5: tkSandboxPresetGlass
  of 6: tkSandboxPresetTank
  else: tkSandboxPresetFresh

proc sandboxStatLabelKey(statIdx: int): TranslationKey =
  case statIdx
  of 0: tkSandboxStatMaxHp
  of 1: tkSandboxStatDamage
  of 2: tkSandboxStatFireRate
  of 3: tkSandboxStatMoveSpeed
  of 4: tkSandboxStatBulletSpeed
  of 5: tkSandboxStatWalls
  of 6: tkSandboxStatCoins
  of 7: tkSandboxStatStartWave
  else: tkSandboxStatMaxHp

proc sandboxStatValueText(c: SandboxConfig, statIdx: int): string =
  case statIdx
  of 0: $int(c.maxHp.round)
  of 1: formatFloat(c.damage, ffDecimal, 1)
  of 2: formatFloat(1.0'f32 / c.fireRate, ffDecimal, 2) & "/s"  # show shots/sec, not cooldown
  of 3: $int(c.speed.round)
  of 4: $int(c.bulletSpeed.round)
  of 5: $c.walls
  of 6: $c.coins
  of 7: $c.startWave
  else: ""

proc adjustSandboxStat(c: var SandboxConfig, statIdx: int, dir, mult: float32) =
  ## dir is +1 for "+", -1 for "-". mult is the acceleration multiplier from
  ## holding the button. For Fire Rate a positive press means *more* fire rate,
  ## i.e. a lower cooldown.
  case statIdx
  of 0: c.maxHp = max(1.0'f32, c.maxHp + dir * 5.0'f32 * mult)
  of 1: c.damage = max(0.1'f32, c.damage + dir * 0.5'f32 * mult)
  of 2: c.fireRate = clamp(c.fireRate - dir * 0.02'f32 * mult, 0.05'f32, 2.0'f32)
  of 3: c.speed = max(20.0'f32, c.speed + dir * 10.0'f32 * mult)
  of 4: c.bulletSpeed = max(50.0'f32, c.bulletSpeed + dir * 25.0'f32 * mult)
  of 5: c.walls = max(0, c.walls + int(dir * 5.0'f32 * mult))
  of 6: c.coins = max(0, c.coins + int(dir * 100.0'f32 * mult))
  of 7: c.startWave = max(1, c.startWave + int(dir * mult))
  else: discard

proc holdStepMultiplier(repeats: int): float32 =
  ## x1 for the first few repeats, then doubles every 5 repeats, capped at x32.
  ## This is what makes a held "+" go 5 -> 10 -> 20 -> 40 ... per tick.
  let tier = repeats div 5
  result = float32(1 shl min(tier, 5))

proc applySandboxConfig*(game: Game) =
  ## Writes the chosen loadout through to the live player and starting wave.
  let c = game.sandboxConfig
  let p = game.player
  p.maxHp = c.maxHp
  p.hp = c.maxHp
  p.damage = c.damage
  p.fireRate = c.fireRate
  p.speed = c.speed
  p.baseSpeed = c.speed
  p.bulletSpeed = c.bulletSpeed
  p.walls = c.walls
  p.coins = c.coins
  game.currentWave = max(1, c.startWave)

# --- Window lifecycle -----------------------------------------------------

proc newSandboxWindow*(screenWidth, screenHeight: int): SandboxWindow =
  const windowWidth = 640
  const windowHeight = TITLE_BAR_HEIGHT + 540
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  let osWin = newOSWindow(t(tkSandboxSetupTitle), windowX, windowY,
                          windowWidth, windowHeight,
                          Color(r: 255, g: 210, b: 60, a: 255), owtSettings,
                          resizable = false)
  osWin.visible = false
  result = SandboxWindow(window: osWin, config: baseSandboxConfig(),
                         selectedPreset: 0, holdStat: -1, holdDir: 0,
                         holdTimer: 0, holdRepeats: 0)

proc resetSandboxWindow*(sw: SandboxWindow) =
  sw.config = baseSandboxConfig()
  sw.selectedPreset = 0
  sw.holdStat = -1
  sw.holdRepeats = 0
  sw.holdTimer = 0

# --- Layout (computed once, shared by draw + input) -----------------------

type
  SandboxLayout = object
    statRowY: array[SETUP_STAT_COUNT, int32]
    statMinus: array[SETUP_STAT_COUNT, Rectangle]
    statPlus: array[SETUP_STAT_COUNT, Rectangle]
    leftX, leftW, rightX, rightW: int32
    presets: array[SETUP_PRESET_COUNT, Rectangle]
    waveAvgBtn: Rectangle
    startBtn: Rectangle

proc rect(x, y, w, h: int32): Rectangle =
  Rectangle(x: x.float32, y: y.float32, width: w.float32, height: h.float32)

proc inRect(p: Vector2, r: Rectangle): bool =
  p.x >= r.x and p.x <= r.x + r.width and p.y >= r.y and p.y <= r.y + r.height

proc computeLayout(cx, cy, cw, ch: int32): SandboxLayout =
  result.leftX = cx + 20
  result.leftW = 360
  result.rightX = cx + 400
  result.rightW = cw - (result.rightX - cx) - 20

  let rowStartY = cy + 44
  const rowH = 46'i32
  for i in 0 ..< SETUP_STAT_COUNT:
    let rowY = rowStartY + int32(i) * rowH
    result.statRowY[i] = rowY
    result.statMinus[i] = rect(result.leftX + result.leftW - 150, rowY + 4, 34, 34)
    result.statPlus[i]  = rect(result.leftX + result.leftW - 40, rowY + 4, 34, 34)

  const presetH = 34'i32
  for i in 0 ..< SETUP_PRESET_COUNT:
    result.presets[i] = rect(result.rightX, rowStartY + int32(i) * (presetH + 6),
                             result.rightW, presetH)
  result.waveAvgBtn = rect(result.rightX,
                           rowStartY + SETUP_PRESET_COUNT * (presetH + 6) + 12,
                           result.rightW, 38)

  result.startBtn = rect(cx + cw - 240, cy + ch - 56, 220, 44)

# --- Input ----------------------------------------------------------------

proc beginHold(sw: SandboxWindow, statIdx: int, dir: float32) =
  ## Apply the first step immediately, then arm the repeat timer.
  adjustSandboxStat(sw.config, statIdx, dir, 1.0'f32)
  sw.selectedPreset = -1
  sw.holdStat = statIdx
  sw.holdDir = dir
  sw.holdTimer = HOLD_INITIAL_DELAY
  sw.holdRepeats = 0

proc updateHold(sw: SandboxWindow, dt: float32) =
  ## Continue an active hold: repeat the adjustment at an accelerating pace.
  if sw.holdStat < 0:
    return
  if not isPointerDown():
    sw.holdStat = -1
    return
  sw.holdTimer -= dt
  if sw.holdTimer <= 0:
    inc sw.holdRepeats
    adjustSandboxStat(sw.config, sw.holdStat, sw.holdDir,
                      holdStepMultiplier(sw.holdRepeats))
    sw.holdTimer = HOLD_REPEAT_INTERVAL

proc updateSandboxWindow*(sw: SandboxWindow, dt: float32,
                          allWindows: openArray[OSWindow],
                          screenWidth, screenHeight: int): SandboxWindowResult =
  result = SandboxWindowResult(shouldClose: false, launchGame: false)
  if sw.isNil or sw.window.isNil or not sw.window.visible:
    result.shouldClose = true
    return

  updateOSWindow(sw.window, dt)

  # Continue any in-progress hold before chrome handling so releasing the mouse
  # outside the button still stops it cleanly.
  updateHold(sw, dt)

  let shouldClose = handleOSWindowInput(sw.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    sw.window.visible = false
    result.shouldClose = true
    return
  if sw.window.minimized or not sw.window.focused:
    return

  let cx = (sw.window.x + WINDOW_BORDER).int32
  let cy = (sw.window.y + TITLE_BAR_HEIGHT + WINDOW_BORDER).int32
  let cw = (sw.window.width - WINDOW_BORDER * 2).int32
  let ch = (sw.window.height - TITLE_BAR_HEIGHT - WINDOW_BORDER * 2).int32
  let lay = computeLayout(cx, cy, cw, ch)

  if not isPointerPressed():
    return
  let mp = getVirtualMousePosition()

  # Stat steppers (start a hold; updateHold drives the acceleration).
  for i in 0 ..< SETUP_STAT_COUNT:
    if inRect(mp, lay.statMinus[i]):
      beginHold(sw, i, -1.0'f32)
      return
    if inRect(mp, lay.statPlus[i]):
      beginHold(sw, i, 1.0'f32)
      return

  # Presets
  for i in 0 ..< SETUP_PRESET_COUNT:
    if inRect(mp, lay.presets[i]):
      let wave = sw.config.startWave  # keep the user's chosen start wave
      sw.config = sandboxPresetConfig(i)
      if i >= 5:  # archetypes don't dictate a start wave; honor the picker
        sw.config.startWave = wave
      sw.selectedPreset = i
      return

  # Wave-average: rebuild stats from the current start wave.
  if inRect(mp, lay.waveAvgBtn):
    let wave = sw.config.startWave
    sw.config = sandboxWaveAverageConfig(baseSandboxConfig(), wave)
    sw.selectedPreset = -1
    return

  # Launch.
  if inRect(mp, lay.startBtn):
    sw.window.visible = false
    result.shouldClose = true
    result.launchGame = true
    return

# --- Drawing --------------------------------------------------------------

proc drawSetupButton(r: Rectangle, label: string, fill, border, text: Color,
                     fontSize: int32 = 16, hovered = false) =
  let bg = if hovered: Color(r: min(255, fill.r.int + 25).uint8,
                             g: min(255, fill.g.int + 25).uint8,
                             b: min(255, fill.b.int + 25).uint8, a: fill.a) else: fill
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, bg)
  drawRectangleLines(r, 1.5, border)
  let tw = measureText(label, fontSize)
  drawText(label, r.x.int32 + (r.width.int32 - tw) div 2,
           r.y.int32 + (r.height.int32 - fontSize) div 2, fontSize, text)

proc drawSandboxWindowContent*(sw: SandboxWindow, cx, cy, cw, ch: int32) =
  let lay = computeLayout(cx, cy, cw, ch)
  let mp = getVirtualMousePosition()

  drawText(t(tkSandboxSetupSubtitle), cx + 16, cy + 12, 12,
           Color(r: 170, g: 185, b: 200, a: 255))

  # --- Stat editors (left column) ---
  for i in 0 ..< SETUP_STAT_COUNT:
    let rowY = lay.statRowY[i]
    drawText(t(sandboxStatLabelKey(i)), lay.leftX, rowY + 12, 16, White)

    let minusR = lay.statMinus[i]
    let plusR = lay.statPlus[i]
    let minusActive = (sw.holdStat == i and sw.holdDir < 0)
    let plusActive = (sw.holdStat == i and sw.holdDir > 0)
    drawSetupButton(minusR, "-", Color(r: 70, g: 70, b: 90, a: 255),
                    Color(r: 120, g: 120, b: 150, a: 255), White, 22,
                    minusActive or inRect(mp, minusR))
    drawSetupButton(plusR, "+", Color(r: 70, g: 70, b: 90, a: 255),
                    Color(r: 120, g: 120, b: 150, a: 255), White, 22,
                    plusActive or inRect(mp, plusR))

    let valText = sandboxStatValueText(sw.config, i)
    let valCenterX = (minusR.x.int32 + minusR.width.int32 + plusR.x.int32) div 2
    let vw = measureText(valText, 16)
    drawText(valText, valCenterX - vw div 2, rowY + 12, 16,
             Color(r: 120, g: 220, b: 255, a: 255))

  # --- Presets (right column) ---
  drawText(t(tkSandboxPresets), lay.rightX, cy + 28, 14,
           Color(r: 200, g: 210, b: 225, a: 255))
  for i in 0 ..< SETUP_PRESET_COUNT:
    let r = lay.presets[i]
    let selected = (sw.selectedPreset == i)
    let fill = if selected: Color(r: 40, g: 95, b: 150, a: 255)
               else: Color(r: 45, g: 52, b: 66, a: 255)
    let border = if selected: Color(r: 90, g: 200, b: 255, a: 255)
                 else: Color(r: 90, g: 100, b: 120, a: 255)
    drawSetupButton(r, t(sandboxPresetNameKey(i)), fill, border, White, 14, inRect(mp, r))

  let waveLabel = t(tkSandboxApplyWaveAvg) & " (W" & $sw.config.startWave & ")"
  drawSetupButton(lay.waveAvgBtn, waveLabel, Color(r: 90, g: 70, b: 150, a: 255),
                  Color(r: 160, g: 130, b: 230, a: 255), White, 14, inRect(mp, lay.waveAvgBtn))

  if sw.selectedPreset < 0:
    drawText(t(tkSandboxCustomLoadout), lay.rightX, lay.waveAvgBtn.y.int32 + 48, 12,
             Color(r: 200, g: 180, b: 120, a: 255))

  # --- Launch ---
  drawSetupButton(lay.startBtn, t(tkSandboxStartRun), Color(r: 40, g: 130, b: 70, a: 255),
                  Color(r: 90, g: 220, b: 130, a: 255), White, 20, inRect(mp, lay.startBtn))

proc drawSandboxWindow*(sw: SandboxWindow) =
  if sw.isNil or sw.window.isNil or not sw.window.visible:
    return
  drawWindowChrome(sw.window)
  if sw.window.minimized:
    return
  let cx = (sw.window.x + WINDOW_BORDER).int32
  let cy = (sw.window.y + TITLE_BAR_HEIGHT + WINDOW_BORDER).int32
  let cw = (sw.window.width - WINDOW_BORDER * 2).int32
  let ch = (sw.window.height - TITLE_BAR_HEIGHT - WINDOW_BORDER * 2).int32
  drawSandboxWindowContent(sw, cx, cy, cw, ch)
