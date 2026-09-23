## Roguelite Window ("Deep Recovery" setup)
## Wraps the roguelite setup panel inside an OS-style desktop window: pick a
## boot profile and a Heat you have earned, then launch. Nothing here is for
## sale any more -- all three boot profiles and every power family are free,
## and Heat N+1 unlocks by winning a run at Heat N.

import raylib, math
import os_window, ../roguelite, ../types, ../localization, ../render_context, os_roguelite, icon_drawing, ../sound, ../utils

const HeatUnlockCelebrationDuration = 1.35'f32

type
  RogueliteWindowResult* = object
    shouldClose*: bool  ## True if window should be hidden
    launchGame*: bool   ## True if user pressed Start (load screen + enter game)

  RogueliteWindow* = ref object
    window*: OSWindow
    celebrationTimer*: float32
    celebrationHeat*: int
    knownHeat: int      ## Highest Heat this window has shown (-1 = not yet seen)

proc newRogueliteWindow*(screenWidth, screenHeight: int, profile: RogueliteProfile = nil): RogueliteWindow =
  let windowWidth = RoguelitePanelW + 20
  let windowHeight = TITLE_BAR_HEIGHT + RoguelitePanelH + 20
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  let osWin = newOSWindow(t("roguelite_setup_title"), windowX, windowY, windowWidth, windowHeight,
                          Color(r: 0, g: 220, b: 255, a: 255), owtSettings, resizable = false)
  osWin.visible = false
  result = RogueliteWindow(window: osWin, celebrationTimer: 0.0,
                           celebrationHeat: RogueliteMinHeat, knownHeat: -1)

proc drawHeatUnlockCelebration(rw: RogueliteWindow, panelX, panelY: int32) =
  ## Flourish over the Heat panel the first time the window shows a Heat that
  ## a win has just unlocked.
  if rw.celebrationTimer <= 0:
    return

  let heatPanelX = panelX + RogueliteHeatPanelXOffset
  let heatPanelY = panelY + RogueliteHeatPanelYOffset
  let heatPanelW: int32 = RogueliteHeatPanelW
  let heatPanelH: int32 = RogueliteHeatPanelH
  let remaining = clamp(rw.celebrationTimer / HeatUnlockCelebrationDuration, 0.0'f32, 1.0'f32)
  let progress = 1.0'f32 - remaining
  let peak = sin(progress * PI)
  let accent = Color(r: 255, g: 112, b: 64, a: 255)
  let gold = Color(r: 255, g: 222, b: 88, a: 255)
  let alpha = uint8(clamp(remaining * 230.0'f32, 0.0'f32, 230.0'f32))

  drawRectangle(heatPanelX - 8, heatPanelY - 8, heatPanelW + 16, heatPanelH + 16,
                Color(r: 255, g: 82, b: 40, a: uint8(22.0'f32 * peak)))
  for ring in 0..2:
    let grow = int32(progress * (16.0'f32 + ring.float32 * 10.0'f32))
    let ringAlpha = uint8(clamp(remaining * (170.0'f32 - ring.float32 * 34.0'f32), 0.0'f32, 170.0'f32))
    drawRectangleLines(Rectangle(
      x: (heatPanelX - 4 - grow).float32,
      y: (heatPanelY - 4 - grow).float32,
      width: (heatPanelW + 8 + grow * 2).float32,
      height: (heatPanelH + 8 + grow * 2).float32),
      2.0'f32, withAlpha((if ring == 0: gold else: accent), ringAlpha))

  let heatIdx = clamp(rw.celebrationHeat, RogueliteMinHeat, RogueliteMaxHeat) - RogueliteMinHeat
  let pipCenterX = heatPanelX + RogueliteHeatPipStartX +
                   heatIdx.int32 * (RogueliteHeatPipW + RogueliteHeatPipGap) +
                   RogueliteHeatPipW div 2
  let pipCenterY = heatPanelY + RogueliteHeatPipY + RogueliteHeatPipH div 2
  for ring in 0..3:
    let radius = 22.0'f32 + progress * (28.0'f32 + ring.float32 * 12.0'f32)
    let ringAlpha = uint8(clamp(remaining * (210.0'f32 - ring.float32 * 38.0'f32), 0.0'f32, 210.0'f32))
    drawCircleLines(pipCenterX, pipCenterY, radius, withAlpha((if ring mod 2 == 0: gold else: accent), ringAlpha))

  let bannerW: int32 = 330
  let bannerH: int32 = 54
  let bannerX = heatPanelX + (heatPanelW - bannerW) div 2
  let bannerY = heatPanelY - 24 - int32(10.0'f32 * peak)
  drawRectangle(bannerX + 4, bannerY + 4, bannerW, bannerH, Color(r: 0, g: 0, b: 0, a: uint8(alpha.float32 * 0.45)))
  drawRectangle(bannerX, bannerY, bannerW, bannerH, Color(r: 54, g: 28, b: 24, a: uint8(alpha.float32 * 0.88)))
  drawRectangleLines(Rectangle(x: bannerX.float32, y: bannerY.float32,
                               width: bannerW.float32, height: bannerH.float32),
                     2.5'f32, withAlpha(gold, alpha))
  drawCurrencyIcon(bannerX + 32, bannerY + bannerH div 2, 34, ciHeat, alpha)
  let label = t("roguelite_heat") & " " & $rw.celebrationHeat & " " & t("roguelite_heat_now_open")
  var labelFont: int32 = 20
  while labelFont > 12 and measureText(label, labelFont) > bannerW - 76:
    dec labelFont
  drawText(label, bannerX + 58, bannerY + (bannerH - labelFont) div 2, labelFont, withAlpha(gold, alpha))

proc buttonRects(panelX, panelY: int32): tuple[start, back: Rectangle] =
  ## Start and Back, centred as a pair under the boot-profile cards. Shared by
  ## the draw and the click hit-test so they can't disagree.
  const btnW: int32 = 240
  const btnH: int32 = 46
  const gap: int32 = 40
  let totalW = btnW * 2 + gap
  let bx = panelX + (RoguelitePanelW - totalW) div 2
  let by = panelY + RoguelitePanelH - 82
  result.start = Rectangle(x: bx.float32, y: by.float32, width: btnW.float32, height: btnH.float32)
  result.back = Rectangle(x: (bx + btnW + gap).float32, y: by.float32,
                          width: btnW.float32, height: btnH.float32)

proc stepHeat(game: Game, profile: RogueliteProfile, target: int) =
  let prev = game.selectedRogueliteHeat
  let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let next = clamp(target, RogueliteMinHeat, maxHeat)
  if next != prev:
    game.selectedRogueliteHeat = next
    game.rogueliteHeatPulseTimer = 0.45
    game.rogueliteHeatPulseDirection = if next > prev: 1 else: -1

proc updateRogueliteWindow*(rw: RogueliteWindow, dt: float32, allWindows: openArray[OSWindow],
                            screenWidth, screenHeight: int, game: Game): RogueliteWindowResult =
  ## Update roguelite window. Returns result indicating close and/or game launch.
  result = RogueliteWindowResult(shouldClose: false, launchGame: false)
  if rw.isNil or rw.window.isNil:
    result.shouldClose = true
    return
  if not rw.window.visible:
    result.shouldClose = true
    return

  updateOSWindow(rw.window, dt)
  rw.celebrationTimer = max(0.0'f32, rw.celebrationTimer - dt)
  let shouldClose = handleOSWindowInput(rw.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    rw.window.visible = false
    result.shouldClose = true
    return
  if rw.window.minimized:
    return

  var profile: RogueliteProfile = nil
  if not game.isNil:
    profile = game.rogueliteProfile
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    # A win unlocked a new Heat since this window last looked: celebrate it
    # once and pre-select it.
    if rw.knownHeat < 0:
      rw.knownHeat = maxHeat
    elif maxHeat > rw.knownHeat:
      rw.knownHeat = maxHeat
      rw.celebrationTimer = HeatUnlockCelebrationDuration
      rw.celebrationHeat = maxHeat
      game.selectedRogueliteHeat = maxHeat
      game.rogueliteHeatPulseTimer = HeatUnlockCelebrationDuration
      game.rogueliteHeatPulseDirection = 1
      playSound(stPowerUp, 0.6)
    game.selectedRogueliteHeat = clamp(game.selectedRogueliteHeat, RogueliteMinHeat, maxHeat)
    game.rogueliteHeatPulseTimer = max(0.0'f32, game.rogueliteHeatPulseTimer - dt)

  let panelX = (rw.window.x + 10).int32
  let panelY = (rw.window.y + TITLE_BAR_HEIGHT + 10).int32
  const starterCount = 3

  if isKeyPressed(Left) or isKeyPressed(A):
    game.selectedRogueliteStarter = (game.selectedRogueliteStarter - 1 + starterCount) mod starterCount
  if isKeyPressed(Right) or isKeyPressed(D):
    game.selectedRogueliteStarter = (game.selectedRogueliteStarter + 1) mod starterCount
  if isKeyPressed(Up) or isKeyPressed(W):
    stepHeat(game, profile, game.selectedRogueliteHeat + 1)
  if isKeyPressed(Down) or isKeyPressed(S):
    stepHeat(game, profile, game.selectedRogueliteHeat - 1)
  if rw.window.focused and (isKeyPressed(Escape) or isKeyPressed(Q)):
    rw.window.visible = false
    game.state = gsMenu
    result.shouldClose = true
    return

  if isKeyPressed(Enter) or isKeyPressed(E):
    rw.window.visible = false
    result.shouldClose = true
    result.launchGame = true
    return

  if isPointerPressed():
    let mousePos = getVirtualMousePosition()
    # Mirror the draw-side layout grid so hit-rects line up with what's rendered.
    let gridW: int32 = 3 * RogueliteCardW + 2 * RogueliteCardGap
    let gridLeft: int32 = panelX + (RoguelitePanelW - gridW) div 2
    let colStep: int32 = RogueliteCardW + RogueliteCardGap
    let cardY = panelY + 122
    var clickHandled = false

    # Card clicks
    for i in 0..2:
      let rect = Rectangle(x: (gridLeft + i.int32 * colStep).float32,
                           y: cardY.float32,
                           width: RogueliteCardW.float32,
                           height: RogueliteCardH.float32)
      if checkCollisionPointRec(mousePos, rect):
        game.selectedRogueliteStarter = i
        clickHandled = true

    if not clickHandled:
      # Heat step buttons (relative to the window position)
      let heatPanelX = panelX + RogueliteHeatPanelXOffset
      let heatPanelY = panelY + RogueliteHeatPanelYOffset
      let decRect = Rectangle(x: (heatPanelX + (RogueliteHeatPanelW - 112)).float32,
                              y: (heatPanelY + 44).float32,
                              width: RogueliteHeatStepButtonW.float32,
                              height: RogueliteHeatStepButtonH.float32)
      let incRect = Rectangle(x: (heatPanelX + (RogueliteHeatPanelW - 60)).float32,
                              y: (heatPanelY + 44).float32,
                              width: RogueliteHeatStepButtonW.float32,
                              height: RogueliteHeatStepButtonH.float32)
      if checkCollisionPointRec(mousePos, decRect):
        stepHeat(game, profile, game.selectedRogueliteHeat - 1)
        clickHandled = true
      elif checkCollisionPointRec(mousePos, incRect):
        stepHeat(game, profile, game.selectedRogueliteHeat + 1)
        clickHandled = true
      else:
        # Heat pips
        let pipStart = heatPanelX + RogueliteHeatPipStartX
        let pipY = heatPanelY + RogueliteHeatPipY
        for i in 0..<RogueliteMaxHeat:
          let px = pipStart + i.int32 * (RogueliteHeatPipW + RogueliteHeatPipGap)
          let pipRect = Rectangle(x: px.float32, y: pipY.float32,
                                  width: RogueliteHeatPipW.float32, height: RogueliteHeatPipH.float32)
          if checkCollisionPointRec(mousePos, pipRect):
            stepHeat(game, profile, RogueliteMinHeat + i)
            clickHandled = true
            break

    let buttons = buttonRects(panelX, panelY)
    if not clickHandled and checkCollisionPointRec(mousePos, buttons.start):
      rw.window.visible = false
      result.shouldClose = true
      result.launchGame = true
      return
    elif not clickHandled and checkCollisionPointRec(mousePos, buttons.back):
      rw.window.visible = false
      game.state = gsMenu
      result.shouldClose = true
      return

proc drawRogueliteWindow*(rw: RogueliteWindow, game: Game) =
  if rw.isNil or rw.window.isNil:
    return
  if not rw.window.visible:
    return

  rw.window.title = t("roguelite_setup_title")
  drawWindowChrome(rw.window)

  if rw.window.minimized:
    return

  let contentX = rw.window.x + 10
  let contentY = rw.window.y + TITLE_BAR_HEIGHT + 10
  let contentW = rw.window.width - 20
  let contentH = rw.window.height - TITLE_BAR_HEIGHT - 20
  drawRectangle(contentX.int32, contentY.int32, contentW.int32, contentH.int32,
                Color(r: 25, g: 25, b: 35, a: 255))

  let panelX = contentX.int32
  let panelY = contentY.int32

  # The OS window chrome already shows the title, so the panel's header band
  # carries a one-line guide instead.
  drawPanel(panelX, panelY, RoguelitePanelW, RoguelitePanelH, t("roguelite_setup_subtitle"),
            Color(r: 0, g: 220, b: 255, a: 255), false, true)

  let profile = game.rogueliteProfile
  let shards = if profile.isNil: 0 else: profile.dataShards
  let cores = if profile.isNil: 0 else: profile.cores
  let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
  let wins = if profile.isNil: 0 else: profile.wins
  # Shared layout grid: chips, cards and buttons align to the centered
  # three-card block so the columns line up vertically.
  let gridW: int32 = 3 * RogueliteCardW + 2 * RogueliteCardGap
  let gridLeft: int32 = panelX + (RoguelitePanelW - gridW) div 2
  let colStep: int32 = RogueliteCardW + RogueliteCardGap

  const ChipGap: int32 = 14
  let chipW: int32 = (gridW - 3 * ChipGap) div 4
  let chipStep: int32 = chipW + ChipGap
  let chipY: int32 = panelY + 58
  drawStatChip(gridLeft, chipY, chipW, 48, t("roguelite_data_shards"), $shards, Gold, ciDataShards)
  drawStatChip(gridLeft + chipStep, chipY, chipW, 48, t("roguelite_cores"), $cores,
               Color(r: 255, g: 130, b: 80, a: 255), ciCore)
  drawStatChip(gridLeft + 2 * chipStep, chipY, chipW, 48, t("roguelite_heat"),
               $maxHeat & " / " & $RogueliteMaxHeat,
               Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
  drawStatChip(gridLeft + 3 * chipStep, chipY, chipW, 48, t("roguelite_wins"), $wins,
               Color(r: 120, g: 255, b: 180, a: 255))

  let cardY = contentY + 122
  let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
  let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
  for idx, kit in [rskOperator, rskBulwark, rskArcanist].pairs:
    let cardX = gridLeft + idx.int32 * colStep
    let hovered = canHover and checkCollisionPointRec(mousePos,
      Rectangle(x: cardX.float32, y: cardY.float32,
                width: RogueliteCardW.float32, height: RogueliteCardH.float32))
    drawKitCard(game, kit, cardX, cardY.int32, idx == game.selectedRogueliteStarter, hovered)

  drawHeatPanel(game, panelX + RogueliteHeatPanelXOffset, panelY + RogueliteHeatPanelYOffset,
                RogueliteHeatPanelW, RogueliteHeatPanelH)

  let buttons = buttonRects(panelX, panelY)
  drawSmallButton(buttons.start.x.int32, buttons.start.y.int32, buttons.start.width.int32,
                  buttons.start.height.int32, t("roguelite_start"), true,
                  Color(r: 0, g: 240, b: 160, a: 255),
                  canHover and checkCollisionPointRec(mousePos, buttons.start))
  drawSmallButton(buttons.back.x.int32, buttons.back.y.int32, buttons.back.width.int32,
                  buttons.back.height.int32, t("roguelite_back"), false,
                  Color(r: 255, g: 120, b: 120, a: 255),
                  canHover and checkCollisionPointRec(mousePos, buttons.back))
  drawCenteredTextFit(t("roguelite_setup_controls"), gridLeft, panelY + RoguelitePanelH - 30,
                      gridW, 14, LightGray)

  drawHeatUnlockCelebration(rw, panelX, panelY)
