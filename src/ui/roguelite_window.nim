## Roguelite Window
## Wrap the existing roguelite panel inside an OS-style desktop window

import raylib, os_window, ../roguelite, ../types, ../localization, ../render_context, os_roguelite, icon_drawing

type
  RogueliteWindowResult* = object
    shouldClose*: bool  ## True if window should be hidden
    launchGame*: bool   ## True if user pressed Start (load screen + enter game)

  RogueliteWindow* = ref object
    window*: OSWindow
    showUnlocks*: bool
    unlockCategory*: int
    unlockItem*: int

proc newRogueliteWindow*(screenWidth, screenHeight: int, profile: RogueliteProfile = nil): RogueliteWindow =
  let windowWidth = RoguelitePanelW + 20
  let windowHeight = TITLE_BAR_HEIGHT + RoguelitePanelH + 20
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  let osWin = newOSWindow(t("roguelite_setup_title"), windowX, windowY, windowWidth, windowHeight,
                          Color(r: 0, g: 220, b: 255, a: 255), owtSettings, resizable = false)
  osWin.visible = false
  result = RogueliteWindow(window: osWin, showUnlocks: false, unlockCategory: 0, unlockItem: 0)

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
  # If the unlocks/shop sub-view is open, intercept ESC before handleOSWindowInput
  # so it goes back to the setup view instead of closing the whole window.
  if rw.showUnlocks and isKeyPressed(Escape):
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

  # ── UNLOCKS VIEW ──────────────────────────────────────────────────────────
  if rw.showUnlocks:
    let currentCat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
    let currentCount = unlockCount(currentCat)

    if isKeyPressed(Tab) or isKeyPressed(Right) or isKeyPressed(D):
      rw.unlockCategory = (rw.unlockCategory + 1) mod 4
      rw.unlockItem = 0
    if isKeyPressed(Left) or isKeyPressed(A):
      rw.unlockCategory = (rw.unlockCategory - 1 + 4) mod 4
      rw.unlockItem = 0
    if isKeyPressed(Down) or isKeyPressed(S):
      rw.unlockItem = (rw.unlockItem + 1) mod max(1, currentCount)
    if isKeyPressed(Up) or isKeyPressed(W):
      rw.unlockItem = (rw.unlockItem - 1 + max(1, currentCount)) mod max(1, currentCount)
    if isKeyPressed(Enter) or isKeyPressed(E):
      if purchaseRogueliteUnlock(profile, currentCat, rw.unlockItem):
        game.rogueliteProfile = profile
    if isKeyPressed(Escape) or isKeyPressed(U) or isKeyPressed(Q):
      rw.showUnlocks = false

    if isMouseButtonPressed(Left):
      let mousePos = getVirtualMousePosition()
      let panelX = contentX.int32
      let panelY = contentY.int32
      let navX = panelX + 30
      let navW: int32 = 184
      let listX = panelX + 232
      let listW: int32 = 340
      let detailsX = panelX + 594
      let detailsW: int32 = 296
      let contentYi = panelY + 130
      let sectionH: int32 = 378
      const NavRowStartY = 44
      const NavRowStep = 72
      const NavRowHeight = 58
      const ListHeaderHeight = 80
      const ListRowStep = 33
      const ListRowHeight = 28
      var clickHandled = false

      # Category nav clicks
      for idx in 0..3:
        let rowY = contentYi + NavRowStartY + idx.int32 * NavRowStep
        let rowRect = Rectangle(x: (navX + 12).float32, y: rowY.float32,
                                width: (navW - 24).float32, height: NavRowHeight.float32)
        if checkCollisionPointRec(mousePos, rowRect):
          if rw.unlockCategory != idx:
            rw.unlockCategory = idx
            rw.unlockItem = 0
          clickHandled = true
          break

      # List item clicks
      if not clickHandled:
        let cat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
        let listStartY = contentYi + ListHeaderHeight
        for idx in 0..<unlockCount(cat):
          let rowY = listStartY + idx.int32 * ListRowStep
          let rowRect = Rectangle(x: (listX + 12).float32, y: rowY.float32,
                                  width: (listW - 24).float32, height: ListRowHeight.float32)
          if checkCollisionPointRec(mousePos, rowRect):
            rw.unlockItem = idx
            clickHandled = true
            break

      # Buy button
      if not clickHandled:
        let buyRect = Rectangle(x: (detailsX + detailsW - 220 - 24).float32,
                                y: (contentYi + sectionH - 58).float32,
                                width: 220, height: 38)
        if checkCollisionPointRec(mousePos, buyRect):
          let cat = RogueliteUnlockCategory(clamp(rw.unlockCategory, 0, 3))
          if purchaseRogueliteUnlock(profile, cat, rw.unlockItem):
            game.rogueliteProfile = profile

      # Back button (bottom control bar) – click anywhere outside nav/list/details goes back
      let backBarRect = Rectangle(x: (panelX + 42).float32,
                                  y: (panelY + RoguelitePanelH - 72).float32,
                                  width: (RoguelitePanelW - 84).float32, height: 32)
      if not clickHandled and checkCollisionPointRec(mousePos, backBarRect):
        rw.showUnlocks = false

    return  # Don't process setup input while in unlocks view

  # ── SETUP VIEW ────────────────────────────────────────────────────────────
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

  if isMouseButtonPressed(Left):
    let mousePos = getVirtualMousePosition()
    let panelX = contentX
    let panelY = contentY
    let startX = panelX + 45
    let cardY = panelY + 122
    let btnY = panelY + RoguelitePanelH - 82
    var clickHandled = false

    # Card clicks
    for i in 0..2:
      let rect = Rectangle(x: (startX + i * (RogueliteCardW + RogueliteCardGap)).float32,
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
    let unlockRect = Rectangle(x: (panelX + 60).float32, y: btnY.float32, width: 180, height: 42)
    let startRect  = Rectangle(x: (panelX + 370).float32, y: btnY.float32, width: 180, height: 42)
    let backRect   = Rectangle(x: (panelX + 680).float32, y: btnY.float32, width: 180, height: 42)

    if not clickHandled and checkCollisionPointRec(mousePos, unlockRect):
      rw.showUnlocks = true
      rw.unlockCategory = 0
      rw.unlockItem = 0
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
  let title = if rw.showUnlocks: t("roguelite_unlocks_title") else: t("roguelite_setup_title")
  let panelAccent = if rw.showUnlocks: Color(r: 255, g: 215, b: 0, a: 255)
                    else: Color(r: 0, g: 220, b: 255, a: 255)
  drawPanel(panelX, panelY, RoguelitePanelW, RoguelitePanelH, title, panelAccent, false, true)

  if rw.showUnlocks:
    # ── Unlocks tab ──
    drawUnlocksContent(game, panelX, panelY, rw.unlockCategory, rw.unlockItem)
    # Note: drawUnlocksContent already draws the full control bar (roguelite_unlock_shop_controls)
    # at the panel bottom — no additional hint drawn here to avoid overlap.
  else:
    # ── Setup tab ──
    let profile = game.rogueliteProfile
    let shards = if profile.isNil: 0 else: profile.dataShards
    let overheatCores = if profile.isNil: 0 else: profile.overheatCores
    let singularityCores = if profile.isNil: 0 else: profile.singularityCores
    let maxHeat = if profile.isNil: RogueliteMinHeat else: profile.highestHeat
    let bossTier = if profile.isNil: 1 else: profile.unlockedBossTier
    drawStatChip(panelX + 26, panelY + 58, 164, 48, t("roguelite_data_shards"), $shards, Gold, ciDataShards)
    drawStatChip(panelX + 202, panelY + 58, 164, 48, t("roguelite_overheat_cores"), $overheatCores,
                 Color(r: 255, g: 130, b: 80, a: 255), ciOverheatCore)
    drawStatChip(panelX + 378, panelY + 58, 164, 48, t("roguelite_singularity_cores"), $singularityCores,
                 Color(r: 170, g: 110, b: 255, a: 255), ciSingularityCore)
    drawStatChip(panelX + 554, panelY + 58, 150, 48, t("roguelite_heat"), $maxHeat & " / " & $RogueliteMaxHeat,
                 Color(r: 255, g: 150, b: 80, a: 255), ciHeat)
    drawStatChip(panelX + 716, panelY + 58, 178, 48, t("roguelite_boss_tier"), $bossTier,
                 Color(r: 255, g: 120, b: 95, a: 255))

    let startX = contentX + 45
    let cardY = contentY + 122
    let canHover = game.mouseMovedRecently and not game.keyboardUsedRecently
    let mousePos = if canHover: getVirtualMousePosition() else: Vector2()
    for idx, kit in [rskOperator, rskBulwark, rskArcanist].pairs:
      let unlocked = profile.isNil or kit in profile.unlockedStarterKits
      let cardX = (startX + idx * (RogueliteCardW + RogueliteCardGap)).int32
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
    drawSmallButton(panelX + 60, btnY.int32, 180, 42, t("roguelite_unlocks"), false,
                    Color(r: 120, g: 200, b: 255, a: 255),
                    canHover and checkCollisionPointRec(mousePos, Rectangle(x: (panelX + 60).float32, y: btnY.float32, width: 180, height: 42)))
    drawSmallButton(panelX + 370, btnY.int32, 180, 42, startLabel,
                    selectedUnlocked or selectedCanBuy, Color(r: 0, g: 240, b: 160, a: 255),
                    canHover and checkCollisionPointRec(mousePos, Rectangle(x: (panelX + 370).float32, y: btnY.float32, width: 180, height: 42)))
    drawSmallButton(panelX + 680, btnY.int32, 180, 42, t("roguelite_back"), false,
                    Color(r: 255, g: 120, b: 120, a: 255),
                    canHover and checkCollisionPointRec(mousePos, Rectangle(x: (panelX + 680).float32, y: btnY.float32, width: 180, height: 42)))
    drawCenteredTextFit(t("roguelite_setup_controls"), panelX + 180, panelY + RoguelitePanelH - 30,
                        RoguelitePanelW - 360, 14, LightGray)
