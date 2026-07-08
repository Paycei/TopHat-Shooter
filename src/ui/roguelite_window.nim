## Roguelite Window
## Wrap the existing roguelite panel inside an OS-style desktop window

import raylib, math
import os_window, ../roguelite, ../types, ../localization, ../render_context, os_roguelite, icon_drawing, ../sound, ../utils

const HeatPurchaseCelebrationDuration = 1.35'f32

type
  RogueliteWindowResult* = object
    shouldClose*: bool  ## True if window should be hidden
    launchGame*: bool   ## True if user pressed Start (load screen + enter game)

  RogueliteWindow* = ref object
    window*: OSWindow
    showUnlocks*: bool
    unlockCategory*: int
    unlockItem*: int
    # Card-grid scroll state for the unlocks view
    unlockScrollOffset*: float32
    unlockScrollVelocity*: float32
    unlockMaxScrollOffset*: float32
    purchaseCelebrationTimer*: float32
    purchaseCelebrationHeat*: int

proc newRogueliteWindow*(screenWidth, screenHeight: int, profile: RogueliteProfile = nil): RogueliteWindow =
  let windowWidth = RoguelitePanelW + 20
  let windowHeight = TITLE_BAR_HEIGHT + RoguelitePanelH + 20
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  let osWin = newOSWindow(t("roguelite_setup_title"), windowX, windowY, windowWidth, windowHeight,
                          Color(r: 0, g: 220, b: 255, a: 255), owtSettings, resizable = false)
  osWin.visible = false
  result = RogueliteWindow(window: osWin, showUnlocks: false, unlockCategory: 0, unlockItem: 0,
                           unlockScrollOffset: 0.0, unlockScrollVelocity: 0.0, unlockMaxScrollOffset: 0.0,
                           purchaseCelebrationTimer: 0.0, purchaseCelebrationHeat: RogueliteMinHeat)

proc triggerUnlockPurchaseFeedback(rw: RogueliteWindow, game: Game, profile: RogueliteProfile,
                                   category: RogueliteUnlockCategory, index: int) =
  let isHeatPurchase = category == rucChallengeTiers and index == 0
  playSound(stBuy, if isHeatPurchase: 1.0 else: 0.78)

  if isHeatPurchase and not profile.isNil and not game.isNil:
    playSound(stPowerUp, 0.55)
    rw.purchaseCelebrationTimer = HeatPurchaseCelebrationDuration
    rw.purchaseCelebrationHeat = profile.highestHeat
    rw.showUnlocks = false
    game.selectedRogueliteHeat = profile.highestHeat
    game.rogueliteHeatPulseTimer = HeatPurchaseCelebrationDuration
    game.rogueliteHeatPulseDirection = 1

proc drawHeatPurchaseCelebration(rw: RogueliteWindow, panelX, panelY: int32) =
  if rw.purchaseCelebrationTimer <= 0:
    return

  let heatPanelX = panelX + RogueliteHeatPanelXOffset
  let heatPanelY = panelY + RogueliteHeatPanelYOffset
  let heatPanelW: int32 = RogueliteHeatPanelW
  let heatPanelH: int32 = RogueliteHeatPanelH
  let remaining = clamp(rw.purchaseCelebrationTimer / HeatPurchaseCelebrationDuration, 0.0'f32, 1.0'f32)
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

  let heatIdx = clamp(rw.purchaseCelebrationHeat, RogueliteMinHeat, RogueliteMaxHeat) - RogueliteMinHeat
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
  let label = t("roguelite_heat") & " " & $rw.purchaseCelebrationHeat & " " & t("roguelite_unlocked")
  var labelFont: int32 = 20
  while labelFont > 12 and measureText(label, labelFont) > bannerW - 76:
    dec labelFont
  drawText(label, bannerX + 58, bannerY + (bannerH - labelFont) div 2, labelFont, withAlpha(gold, alpha))

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
  rw.purchaseCelebrationTimer = max(0.0'f32, rw.purchaseCelebrationTimer - dt)
  # If the unlocks/shop sub-view is open, intercept ESC before handleOSWindowInput
  # so it goes back to the setup view instead of closing the whole window.
  if rw.showUnlocks and rw.window.focused and isKeyPressed(Escape):
    rw.showUnlocks = false
    return
  let shouldClose = handleOSWindowInput(rw.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    rw.window.visible = false
    result.shouldClose = true
    return
  if rw.window.minimized:
    return

  # Keep roguelite profile up to date
  var profile: RogueliteProfile = nil
  if not game.isNil:
    profile = game.rogueliteProfile
    if not profile.isNil:
      refreshRogueliteUnlocks(profile)
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    game.selectedRogueliteHeat = clamp(game.selectedRogueliteHeat, RogueliteMinHeat, maxHeat)
    game.rogueliteHeatPulseTimer = max(0.0'f32, game.rogueliteHeatPulseTimer - dt)

  let contentX = rw.window.x + 10
  let contentY = rw.window.y + TITLE_BAR_HEIGHT + 10

  # UNLOCKS VIEW
  if rw.showUnlocks:
    let currentCat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
    let currentCount = unlockCount(currentCat)

    # Compute grid geometry (must match drawUnlocksContent layout)
    let panelX = contentX.int32
    let panelY = contentY.int32
    let cardTotalW = UnlockCardW + UnlockCardPad
    let columns = max(1, RoguelitePanelW div cardTotalW)
    let infoPanelH: int32 = 65
    let ctrlBarFootH: int32 = 72
    let gridY = panelY + 170
    let gridH: int32 = RoguelitePanelH - 170 - infoPanelH - ctrlBarFootH
    let totalRows = if currentCount == 0: 0 else: (currentCount + columns - 1) div columns
    let totalContentH = totalRows * (UnlockCardH + UnlockCardPad) + 10
    rw.unlockMaxScrollOffset = max(0.0'f32, totalContentH.float32 - gridH.float32)

    # Keyboard navigation
    var keyboardMovedFocus = false
    if rw.window.focused:
      # Category switching: Tab/Shift+Tab cycle, A/D cycle, 1-4 jump directly
      let shiftHeld = isKeyDown(LeftShift) or isKeyDown(RightShift)
      if isKeyPressed(Tab):
        if shiftHeld:
          rw.unlockCategory = (rw.unlockCategory - 1 + 4) mod 4
        else:
          rw.unlockCategory = (rw.unlockCategory + 1) mod 4
        rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0
        rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(A):
        rw.unlockCategory = (rw.unlockCategory - 1 + 4) mod 4
        rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0
        rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(D):
        rw.unlockCategory = (rw.unlockCategory + 1) mod 4
        rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0
        rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(One):
        rw.unlockCategory = 0; rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0; rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(Two):
        rw.unlockCategory = 1; rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0; rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(Three):
        rw.unlockCategory = 2; rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0; rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      if isKeyPressed(Four):
        rw.unlockCategory = 3; rw.unlockItem = 0
        rw.unlockScrollOffset = 0.0; rw.unlockScrollVelocity = 0.0
        keyboardMovedFocus = true
      # Item navigation within the current category
      if isKeyPressed(Left):
        let prev = rw.unlockItem
        rw.unlockItem = max(0, rw.unlockItem - 1)
        keyboardMovedFocus = keyboardMovedFocus or rw.unlockItem != prev
      if isKeyPressed(Right):
        let prev = rw.unlockItem
        rw.unlockItem = min(currentCount - 1, rw.unlockItem + 1)
        keyboardMovedFocus = keyboardMovedFocus or rw.unlockItem != prev
      if isKeyPressed(Up):
        let prev = rw.unlockItem
        rw.unlockItem = max(0, rw.unlockItem - columns)
        keyboardMovedFocus = keyboardMovedFocus or rw.unlockItem != prev
      if isKeyPressed(Down):
        let prev = rw.unlockItem
        rw.unlockItem = min(currentCount - 1, rw.unlockItem + columns)
        keyboardMovedFocus = keyboardMovedFocus or rw.unlockItem != prev
      if isKeyPressed(Enter) or isKeyPressed(E):
        if purchaseRogueliteUnlock(profile, currentCat, rw.unlockItem):
          triggerUnlockPurchaseFeedback(rw, game, profile, currentCat, rw.unlockItem)
          game.rogueliteProfile = profile
      if isKeyPressed(Escape) or isKeyPressed(Q):
        rw.showUnlocks = false
        return

    # Auto-scroll focused card into view
    if keyboardMovedFocus and currentCount > 0:
      let selRow = rw.unlockItem div columns
      let cardTop = float32(5 + selRow * (UnlockCardH + UnlockCardPad))
      let cardBot = cardTop + UnlockCardH.float32
      if cardTop < rw.unlockScrollOffset:
        rw.unlockScrollOffset = cardTop
        rw.unlockScrollVelocity = 0.0
      elif cardBot > rw.unlockScrollOffset + gridH.float32:
        rw.unlockScrollOffset = cardBot - gridH.float32
        rw.unlockScrollVelocity = 0.0
      rw.unlockScrollOffset = clamp(rw.unlockScrollOffset, 0.0'f32, rw.unlockMaxScrollOffset)

    # Mouse wheel scroll
    let mousePos = getVirtualMousePosition()
    let inGridArea = mousePos.x >= contentX.float32 and
                     mousePos.x < (contentX + RoguelitePanelW).float32 and
                     mousePos.y >= gridY.float32 and
                     mousePos.y < (gridY + gridH).float32
    if inGridArea and not rw.window.dragging:
      let wheelMove = getPointerWheelMove()
      if wheelMove != 0:
        rw.unlockScrollVelocity += -wheelMove * 400.0'f32

    # Apply inertial scroll
    if abs(rw.unlockScrollVelocity) > 0.001'f32:
      rw.unlockScrollOffset += rw.unlockScrollVelocity * dt
      rw.unlockScrollOffset = clamp(rw.unlockScrollOffset, 0.0'f32, rw.unlockMaxScrollOffset)
      if rw.unlockScrollOffset <= 0.0'f32 or rw.unlockScrollOffset >= rw.unlockMaxScrollOffset:
        rw.unlockScrollVelocity = 0.0'f32
      else:
        rw.unlockScrollVelocity *= clamp(1.0'f32 - dt * 8.0'f32, 0.0'f32, 1.0'f32)

    # Mouse clicks
    if isPointerPressed():
      let scrollInt = int(round(rw.unlockScrollOffset))
      let gridLeft = panelX + (RoguelitePanelW - (columns * UnlockCardW + (columns - 1) * UnlockCardPad)) div 2

      # Tab bar clicks
      let tabAreaY = panelY + 130
      if mousePos.y >= tabAreaY.float32 and mousePos.y < (tabAreaY + UnlockTabH).float32:
        let tabW = RoguelitePanelW div 4
        let tabIdx = int((mousePos.x - panelX.float32) / tabW.float32)
        if tabIdx >= 0 and tabIdx < 4:
          if rw.unlockCategory != tabIdx:
            rw.unlockCategory = tabIdx
            rw.unlockItem = 0
            rw.unlockScrollOffset = 0.0
            rw.unlockScrollVelocity = 0.0
      # Card grid clicks
      elif mousePos.y >= gridY.float32 and mousePos.y < (gridY + gridH).float32:
        let cat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
        for idx in 0..<unlockCount(cat):
          let col = idx mod columns
          let row = idx div columns
          let cx = (gridLeft + col * cardTotalW).float32
          let cy = float32(gridY + 5 + row * (UnlockCardH + UnlockCardPad) - scrollInt)
          let cardRect = Rectangle(x: cx, y: cy,
                                   width: UnlockCardW.float32, height: UnlockCardH.float32)
          if checkCollisionPointRec(mousePos, cardRect):
            rw.unlockItem = idx
            if purchaseRogueliteUnlock(profile, cat, idx):
              triggerUnlockPurchaseFeedback(rw, game, profile, cat, idx)
              game.rogueliteProfile = profile
            break

      # Buy button in info panel
      let infoPanelY = gridY + gridH
      let btnW: int32 = 210
      let btnH: int32 = 40
      let btnX = (panelX + RoguelitePanelW - btnW - 16).float32
      let btnY = (infoPanelY + (65 - btnH) div 2).float32
      let buyRect = Rectangle(x: btnX, y: btnY, width: btnW.float32, height: btnH.float32)
      if checkCollisionPointRec(mousePos, buyRect):
        let cat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
        if purchaseRogueliteUnlock(profile, cat, rw.unlockItem):
          triggerUnlockPurchaseFeedback(rw, game, profile, cat, rw.unlockItem)
          game.rogueliteProfile = profile

      # Control bar / back button
      let ctrlBarY = panelY + RoguelitePanelH - 72
      let backRect = Rectangle(x: (panelX + 42).float32, y: ctrlBarY.float32,
                               width: (RoguelitePanelW - 84).float32, height: 32)
      if checkCollisionPointRec(mousePos, backRect):
        rw.showUnlocks = false

    return  # Don't process setup input while in unlocks view

  # SETUP VIEW
  let starterKits = @[rskOperator, rskBulwark, rskArcanist]

  if isKeyPressed(Left) or isKeyPressed(A):
    game.selectedRogueliteStarter = (game.selectedRogueliteStarter - 1 + starterKits.len) mod starterKits.len
  if isKeyPressed(Right) or isKeyPressed(D):
    game.selectedRogueliteStarter = (game.selectedRogueliteStarter + 1) mod starterKits.len
  if isKeyPressed(Up) or isKeyPressed(W):
    let prev = game.selectedRogueliteHeat
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    let next = clamp(prev + 1, RogueliteMinHeat, maxHeat)
    if next != prev:
      game.selectedRogueliteHeat = next
      game.rogueliteHeatPulseTimer = 0.45
      game.rogueliteHeatPulseDirection = 1
  if isKeyPressed(Down) or isKeyPressed(S):
    let prev = game.selectedRogueliteHeat
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    let next = clamp(prev - 1, RogueliteMinHeat, maxHeat)
    if next != prev:
      game.selectedRogueliteHeat = next
      game.rogueliteHeatPulseTimer = 0.45
      game.rogueliteHeatPulseDirection = -1
  if isKeyPressed(U):
    rw.showUnlocks = true
    rw.unlockCategory = 0
    rw.unlockItem = 0
    rw.unlockScrollOffset = 0.0
    rw.unlockScrollVelocity = 0.0
    markAffordableUnlocksSeen(profile)
  if rw.window.focused and (isKeyPressed(Escape) or isKeyPressed(Q)):
    rw.window.visible = false
    game.state = gsMenu
    result.shouldClose = true
    return

  proc tryLaunch(): bool =
    let selectedStarterIndex = clamp(game.selectedRogueliteStarter, 0, 2)
    let kit = starterKits[selectedStarterIndex]
    let unlocked = profile.isNil or kit in profile.unlockedStarterKits
    if unlocked:
      return true
    elif not profile.isNil and purchaseRogueliteUnlock(profile, rucStarterKits, selectedStarterIndex):
      triggerUnlockPurchaseFeedback(rw, game, profile, rucStarterKits, selectedStarterIndex)
      game.rogueliteProfile = profile
      return false
    else:
      return false

  if isKeyPressed(Enter) or isKeyPressed(E):
    if tryLaunch():
      rw.window.visible = false
      result.shouldClose = true
      result.launchGame = true
      return

  if isPointerPressed():
    let mousePos = getVirtualMousePosition()
    let panelX = contentX.int32
    let panelY = contentY.int32
    # Mirror the draw-side layout grid so hit-rects line up with what's rendered.
    let gridW: int32 = 3 * RogueliteCardW + 2 * RogueliteCardGap
    let gridLeft: int32 = panelX + (RoguelitePanelW - gridW) div 2
    let colStep: int32 = RogueliteCardW + RogueliteCardGap
    let startX = gridLeft
    let cardY = panelY + 122
    let btnY = panelY + RoguelitePanelH - 82
    var clickHandled = false

    # Card clicks
    for i in 0..2:
      let rect = Rectangle(x: (startX + i.int32 * colStep).float32,
                           y: cardY.float32,
                           width: RogueliteCardW.float32,
                           height: RogueliteCardH.float32)
      if checkCollisionPointRec(mousePos, rect):
        game.selectedRogueliteStarter = i
        clickHandled = true

    if not clickHandled:
      # Heat step buttons (now relative to window position)
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
        let prev = game.selectedRogueliteHeat
        let maxHeat2 = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
        let next = clamp(prev - 1, RogueliteMinHeat, maxHeat2)
        if next != prev:
          game.selectedRogueliteHeat = next
          game.rogueliteHeatPulseTimer = 0.45
          game.rogueliteHeatPulseDirection = -1
        clickHandled = true
      elif checkCollisionPointRec(mousePos, incRect):
        let prev = game.selectedRogueliteHeat
        let maxHeat2 = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
        let next = clamp(prev + 1, RogueliteMinHeat, maxHeat2)
        if next != prev:
          game.selectedRogueliteHeat = next
          game.rogueliteHeatPulseTimer = 0.45
          game.rogueliteHeatPulseDirection = 1
        clickHandled = true
      else:
        # Heat pips
        let pipStart = panelX + RogueliteHeatPanelXOffset + RogueliteHeatPipStartX
        let pipY = panelY + RogueliteHeatPanelYOffset + RogueliteHeatPipY
        for i in 0..<RogueliteMaxHeat:
          let heatLevel = RogueliteMinHeat + i
          let px = pipStart + i.int32 * (RogueliteHeatPipW + RogueliteHeatPipGap)
          let pipRect = Rectangle(x: px.float32, y: pipY.float32,
                                  width: RogueliteHeatPipW.float32, height: RogueliteHeatPipH.float32)
          if checkCollisionPointRec(mousePos, pipRect):
            let prev = game.selectedRogueliteHeat
            let maxHeat3 = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
            let clamped = clamp(heatLevel, RogueliteMinHeat, maxHeat3)
            if clamped != prev:
              game.selectedRogueliteHeat = clamped
              game.rogueliteHeatPulseTimer = 0.45
              game.rogueliteHeatPulseDirection = if clamped > prev: 1 else: -1
            clickHandled = true
            break

    # Bottom buttons
    let btnW: int32 = 220
    let btnH: int32 = 46
    let colInset: int32 = RogueliteCardW div 2 - btnW div 2
    let unlockRect = Rectangle(x: (gridLeft + colInset).float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)
    let startRect  = Rectangle(x: (gridLeft + colStep + colInset).float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)
    let backRect   = Rectangle(x: (gridLeft + 2 * colStep + colInset).float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)

    if not clickHandled and checkCollisionPointRec(mousePos, unlockRect):
      rw.showUnlocks = true
      rw.unlockCategory = 0
      rw.unlockItem = 0
      rw.unlockScrollOffset = 0.0
      rw.unlockScrollVelocity = 0.0
      markAffordableUnlocksSeen(profile)
    elif not clickHandled and checkCollisionPointRec(mousePos, startRect):
      if tryLaunch():
        rw.window.visible = false
        result.shouldClose = true
        result.launchGame = true
        return
    elif not clickHandled and checkCollisionPointRec(mousePos, backRect):
      rw.window.visible = false
      game.state = gsMenu
      result.shouldClose = true
      return

proc drawRogueliteWindow*(rw: RogueliteWindow, game: Game) =
  if rw.isNil or rw.window.isNil:
    return
  if not rw.window.visible:
    return

  # Update window title to match active tab
  rw.window.title = if rw.showUnlocks: t("roguelite_unlocks_title") else: t("roguelite_setup_title")

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

  # Panel header (replaces the full panel title-bar drawn by drawPanel)
  # The OS window chrome already shows the title at the top bar, so the inner
  # panel header repeating it read as redundant. For the setup view use that band
  # as a guidance subtitle instead; the unlocks view keeps its section title.
  let headerLabel = if rw.showUnlocks: t("roguelite_unlocks_title")
                    else: t("roguelite_setup_subtitle")
  let panelAccent = if rw.showUnlocks: Color(r: 255, g: 215, b: 0, a: 255)
                    else: Color(r: 0, g: 220, b: 255, a: 255)
  drawPanel(panelX, panelY, RoguelitePanelW, RoguelitePanelH, headerLabel, panelAccent, false, true)

  if rw.showUnlocks:
    # Unlocks tab
    drawUnlocksContent(game, panelX, panelY, rw.unlockCategory, rw.unlockItem, rw.unlockScrollOffset)
    # Note: drawUnlocksContent already draws the full control bar (roguelite_unlock_shop_controls)
    # at the panel bottom, no additional hint drawn here to avoid overlap.
  else:
    # Setup tab
    let profile = game.rogueliteProfile
    let shards = if profile.isNil: 0 else: profile.dataShards
    let cores = if profile.isNil: 0 else: profile.cores
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    let bossTier = if profile.isNil: 1 else: profile.unlockedBossTier
    # Shared layout grid: everything (chips, cards, buttons) aligns to the
    # centered three-card block so the columns line up vertically instead of each
    # row using its own ad-hoc margins.
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
    drawStatChip(gridLeft + 3 * chipStep, chipY, chipW, 48, t("roguelite_boss_tier"), $bossTier,
                 Color(r: 255, g: 120, b: 95, a: 255))

    let startX = gridLeft
    let cardY = contentY + 122
    let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
    let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
    for idx, kit in [rskOperator, rskBulwark, rskArcanist].pairs:
      let unlocked = profile.isNil or kit in profile.unlockedStarterKits
      let cardX = startX + idx.int32 * colStep
      let hovered = canHover and checkCollisionPointRec(mousePos,
        Rectangle(x: cardX.float32, y: cardY.float32,
                  width: RogueliteCardW.float32, height: RogueliteCardH.float32))
      drawKitCard(game, kit, cardX, cardY.int32, idx == game.selectedRogueliteStarter, unlocked, hovered)

    drawHeatPanel(game, panelX + RogueliteHeatPanelXOffset, panelY + RogueliteHeatPanelYOffset,
                  RogueliteHeatPanelW, RogueliteHeatPanelH)

    let btnY = contentY + RoguelitePanelH - 82
    let selectedStarterIndex = clamp(game.selectedRogueliteStarter, 0, 2)
    let selectedKit = starterByUnlockIndex(selectedStarterIndex)
    let selectedUnlocked = profile.isNil or selectedKit in profile.unlockedStarterKits
    let selectedCanBuy = not selectedUnlocked and
                         not profile.isNil and
                         canPurchaseUnlock(profile, rucStarterKits, selectedStarterIndex)
    let startLabel = if selectedUnlocked: t("roguelite_start")
                     elif selectedCanBuy: t("roguelite_buy_unlock")
                     else: t("roguelite_need_more_shards")
    let shopHasDeal = hasUnseenAffordableUnlock(profile)
    # Each button is centered under its card column so card->action reads as one
    # vertical lane (Shop·Operator, Start·Bulwark, Back·Arcanist).
    let btnW: int32 = 220
    let btnH: int32 = 46
    let colInset: int32 = RogueliteCardW div 2 - btnW div 2
    let shopX: int32 = gridLeft + colInset
    let startBtnX: int32 = gridLeft + colStep + colInset
    let backX: int32 = gridLeft + 2 * colStep + colInset
    drawShopButton(shopX, btnY.int32, btnW, btnH, t("roguelite_unlocks"), game.time,
                   shopHasDeal,
                   canHover and checkCollisionPointRec(mousePos, Rectangle(x: shopX.float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)))
    drawSmallButton(startBtnX, btnY.int32, btnW, btnH, startLabel,
                    selectedUnlocked or selectedCanBuy, Color(r: 0, g: 240, b: 160, a: 255),
                    canHover and checkCollisionPointRec(mousePos, Rectangle(x: startBtnX.float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)))
    drawSmallButton(backX, btnY.int32, btnW, btnH, t("roguelite_back"), false,
                    Color(r: 255, g: 120, b: 120, a: 255),
                    canHover and checkCollisionPointRec(mousePos, Rectangle(x: backX.float32, y: btnY.float32, width: btnW.float32, height: btnH.float32)))
    drawCenteredTextFit(t("roguelite_setup_controls"), gridLeft, panelY + RoguelitePanelH - 30,
                        gridW, 14, LightGray)

  drawHeatPurchaseCelebration(rw, panelX, panelY)
