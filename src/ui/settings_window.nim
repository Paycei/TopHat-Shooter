## OS-Themed Settings Control Panel
## Tabbed settings interface matching the OS visual language

import raylib, strutils
import ../sound, ../save_system, os_window, ../localization, ../render_context, ../statistics, ../run_statistics, ../advancement, ../roguelite, ../types

type
  SettingsTab* = enum
    stGraphics
    stAudio
    stControls
    stGameplay

  SettingsResetAction* = enum
    sraNone
    sraAllData
    sraAdvancements
    sraRogueliteData

  SettingsWindow* = ref object
    window*: OSWindow
    currentTab*: SettingsTab
    settings*: Settings
    stats*: Statistics
    advancementProfile*: AdvancementProfile
    rogueliteProfile*: RogueliteProfile

    # UI state
    hoveredControl*: int  # -1 for none
    editingFPS*: bool
    editingVolume*: bool
    editingMusicVolume*: bool

    # Slider state
    draggingVolume*: bool
    draggingMusic*: bool

    # Set when the user clicks "Replay Intro"; consumed by the window manager
    replayIntroRequested*: bool

    # Set when the user clicks "Replay Ending" (only offered once the game is won)
    replayEndingRequested*: bool

    # Destructive reset confirmation state
    pendingReset*: SettingsResetAction
    resetConfirmTimer*: float32
    resetStatus*: string
    resetStatusTimer*: float32

    # Keybind rebinding state (-1 = not rebinding, else = KeyAction ordinal being captured)
    rebindingAction*: int

proc newSettingsWindow*(screenWidth, screenHeight: int, settings: Settings,
                        stats: Statistics = nil,
                        advancementProfile: AdvancementProfile = nil,
                        rogueliteProfile: RogueliteProfile = nil): SettingsWindow =
  let windowWidth = 700
  let windowHeight = 500
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    t(tkSettingsTitle),
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 200, g: 100, b: 255, a: 255),  # Purple
    owtSettings,
    resizable = false
  )

  result = SettingsWindow(
    window: osWin,
    currentTab: stGraphics,
    settings: settings,
    stats: stats,
    advancementProfile: advancementProfile,
    rogueliteProfile: rogueliteProfile,
    hoveredControl: -1,
    editingFPS: false,
    editingVolume: false,
    editingMusicVolume: false,
    draggingVolume: false,
    draggingMusic: false,
    replayIntroRequested: false,
    replayEndingRequested: false,
    pendingReset: sraNone,
    resetConfirmTimer: 0.0,
    resetStatus: "",
    resetStatusTimer: 0.0,
    rebindingAction: -1
  )

proc drawTab*(tabName: string, x, y, width, height: int, isActive: bool, isHovered: bool) =
  let bgColor = if isActive:
    Color(r: 0, g: 60, b: 80, a: 255)
  elif isHovered:
    Color(r: 50, g: 50, b: 60, a: 255)
  else:
    Color(r: 40, g: 40, b: 50, a: 255)

  drawRectangle(x.int32, y.int32, width.int32, height.int32, bgColor)

  let borderColor = if isActive:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, borderColor)

  if isActive:
    drawRectangle(x.int32, (y + height - 3).int32, width.int32, 3,
                 Color(r: 0, g: 200, b: 255, a: 255))

  let textWidth = measureText(tabName, 16)
  let textX = x + (width - textWidth) div 2
  let textY = y + (height - 16) div 2

  let textColor = if isActive: Gold else: White
  drawText(tabName, textX.int32, textY.int32, 16, textColor)

proc drawCheckbox*(x, y, size: int, checked: bool, hovered: bool) =
  let bgColor = if checked:
    Color(r: 15, g: 75, b: 30, a: 255)
  elif hovered:
    Color(r: 70, g: 70, b: 95, a: 255)
  else:
    Color(r: 50, g: 50, b: 70, a: 255)

  drawRectangle(x.int32, y.int32, size.int32, size.int32, bgColor)

  let borderColor = if checked:
    Color(r: 60, g: 220, b: 90, a: 255)
  elif hovered:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 100, g: 100, b: 120, a: 255)
  let borderThick: float32 = if checked or hovered: 2.0 else: 1.0

  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: size.float32, height: size.float32),
                    borderThick, borderColor)

  if checked:
    let checkColor = Color(r: 100, g: 255, b: 130, a: 255)
    drawLine(Vector2(x: (x + 4).float32, y: (y + size div 2).float32),
            Vector2(x: (x + size div 2 - 2).float32, y: (y + size - 5).float32),
            3, checkColor)
    drawLine(Vector2(x: (x + size div 2 - 2).float32, y: (y + size - 5).float32),
            Vector2(x: (x + size - 3).float32, y: (y + 3).float32),
            3, checkColor)

proc drawSlider*(x, y, width, height: int, value: float32, hovered: bool,
                showTicks: bool = false, tickValues: seq[int] = @[]) =
  # Background
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 30, g: 30, b: 42, a: 255))

  # Center groove for depth
  drawRectangle(x.int32, (y + height div 2 - 1).int32, width.int32, 2,
               Color(r: 15, g: 15, b: 22, a: 255))

  # Draw tick marks if enabled
  if showTicks and tickValues.len > 0:
    for tickVal in tickValues:
      let tickPos = x + int(float32(tickVal) / 100.0 * width.float32)
      drawRectangle(tickPos.int32, (y - 4).int32, 2, (height + 8).int32,
                   Color(r: 80, g: 80, b: 100, a: 255))

  # Fill
  let fillWidth = int(width.float32 * value)
  let fillColor = if hovered:
    Color(r: 255, g: 220, b: 100, a: 255)
  else:
    Color(r: 255, g: 200, b: 50, a: 255)
  drawRectangle(x.int32, y.int32, fillWidth.int32, height.int32, fillColor)

  # Border
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: width.float32, height: height.float32),
                    1, Color(r: 100, g: 100, b: 120, a: 255))

  # Handle with glow
  let handleX = x + fillWidth - 5
  if hovered:
    # Glow effect
    drawRectangle((handleX - 2).int32, (y - 5).int32, 14, (height + 10).int32,
                 Color(r: 255, g: 220, b: 100, a: 80))
  drawRectangle(handleX.int32, (y - 3).int32, 10, (height + 6).int32,
               if hovered: Gold else: Color(r: 200, g: 200, b: 220, a: 255))
  drawRectangle(handleX.int32, (y - 3).int32, 10, 2,
               Color(r: 255, g: 255, b: 255, a: 90))

proc drawSectionHeader*(x, y, width: int, title: string, iconChar: char, color: Color) =
  ## Draw a section divider with colored icon square
  # Colored icon square
  drawRectangle(x.int32, y.int32, 20, 22, color)
  let charW = measureText($iconChar, 13)
  drawText($iconChar, (x + (20 - charW) div 2).int32, (y + 4).int32, 13,
          Color(r: 0, g: 0, b: 0, a: 220))

  # Horizontal separator line
  drawRectangle((x + 20).int32, (y + 10).int32, (width - 20).int32, 1,
               Color(r: 0, g: 200, b: 255, a: 60))

  # Title text
  drawText(title, (x + 26).int32, (y + 3).int32, 16,
          Color(r: 0, g: 220, b: 255, a: 255))

proc resetButtonRect(action: SettingsResetAction, contentX, contentY: int): Rectangle =
  const
    ButtonWidth = 180
    ButtonHeight = 34
    ButtonGap = 16
  let idx = case action
    of sraAllData: 0
    of sraAdvancements: 1
    of sraRogueliteData: 2
    else: 0
  Rectangle(
    x: (contentX + 40 + idx * (ButtonWidth + ButtonGap)).float32,
    y: (contentY + 335).float32,
    width: ButtonWidth.float32,
    height: ButtonHeight.float32
  )

proc replayIntroButtonRect(contentX, contentY: int): Rectangle =
  Rectangle(
    x: (contentX + 40).float32,
    y: (contentY + 250).float32,
    width: 200.float32,
    height: 32.float32
  )

proc replayEndingButtonRect(contentX, contentY: int): Rectangle =
  ## Sits beside "Replay Intro"; only shown once the game has been beaten.
  Rectangle(
    x: (contentX + 40 + 210).float32,
    y: (contentY + 250).float32,
    width: 200.float32,
    height: 32.float32
  )

proc resetActionLabel(action: SettingsResetAction): string =
  case action
  of sraAllData: t(tkSettingsResetAllData)
  of sraAdvancements: t(tkSettingsResetAdvancements)
  of sraRogueliteData: t(tkSettingsResetRogueliteData)
  else: ""

proc drawSettingsButton(rect: Rectangle, label: string, hovered: bool, danger: bool,
                        confirming: bool = false) =
  let bg =
    if confirming:
      Color(r: 135, g: 64, b: 22, a: 255)
    elif danger and hovered:
      Color(r: 120, g: 38, b: 50, a: 255)
    elif danger:
      Color(r: 82, g: 34, b: 45, a: 255)
    elif hovered:
      Color(r: 80, g: 80, b: 100, a: 255)
    else:
      Color(r: 60, g: 60, b: 80, a: 255)
  let border =
    if confirming:
      Gold
    elif danger:
      Color(r: 255, g: 95, b: 105, a: 255)
    elif hovered:
      Gold
    else:
      Color(r: 100, g: 100, b: 120, a: 255)

  drawRectangle(rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, bg)
  drawRectangleLines(rect, 1, border)
  let fontSize: int32 = 14
  let textWidth = measureText(label, fontSize)
  drawText(label,
           rect.x.int32 + (rect.width.int32 - textWidth) div 2,
           rect.y.int32 + (rect.height.int32 - fontSize) div 2,
           fontSize, White)

proc resetLifetimeProgress(settingsWin: SettingsWindow): bool =
  result = true
  if not settingsWin.stats.isNil:
    resetStatistics(settingsWin.stats)
    result = saveStatistics(settingsWin.stats) and result
  clearLastCompletedRun()
  result = deleteLastRunStats() and result

proc resetRogueliteLastRunProgress(): bool =
  let memoryRun = getLastRunStats()
  let diskRun = if memoryRun.isNil: loadLastRunStats() else: memoryRun
  if not diskRun.isNil and diskRun.gameMode == gmRoguelite:
    clearLastCompletedRun()
    return deleteLastRunStats()
  true

proc performResetAction(settingsWin: SettingsWindow, action: SettingsResetAction): bool =
  result = true
  case action
  of sraAllData:
    result = settingsWin.resetLifetimeProgress() and result
    if not settingsWin.advancementProfile.isNil:
      result = resetAdvancements(settingsWin.advancementProfile) and result
    if not settingsWin.rogueliteProfile.isNil:
      result = resetRogueliteProfile(settingsWin.rogueliteProfile) and result
  of sraAdvancements:
    if not settingsWin.advancementProfile.isNil:
      result = resetAdvancements(settingsWin.advancementProfile) and result
    else:
      result = false
  of sraRogueliteData:
    if not settingsWin.rogueliteProfile.isNil:
      result = resetRogueliteProfile(settingsWin.rogueliteProfile) and result
      result = resetRogueliteLastRunProgress() and result
      if not settingsWin.advancementProfile.isNil:
        result = resetAdvancementCategory(settingsWin.advancementProfile, acRoguelite) and result
    else:
      result = false
  of sraNone:
    result = false
  if result and action in {sraAllData, sraRogueliteData} and not settingsWin.rogueliteProfile.isNil:
    if sanitizeEquippedCosmetics(settingsWin.settings, settingsWin.rogueliteProfile):
      discard saveSettings(settingsWin.settings)

proc requestResetAction(settingsWin: SettingsWindow, action: SettingsResetAction) =
  if settingsWin.pendingReset == action and settingsWin.resetConfirmTimer > 0.0:
    let ok = settingsWin.performResetAction(action)
    settingsWin.pendingReset = sraNone
    settingsWin.resetConfirmTimer = 0.0
    settingsWin.resetStatus = if ok: t(tkSettingsResetComplete) else: t(tkSettingsResetFailed)
    settingsWin.resetStatusTimer = 3.0
    playSound(if ok: stMenuSelect else: stMenuNav)
  else:
    settingsWin.pendingReset = action
    settingsWin.resetConfirmTimer = 4.0
    settingsWin.resetStatus = ""
    settingsWin.resetStatusTimer = 0.0
    playSound(stMenuNav)

proc getMouseBondingModeLabel(mode: MouseBondingMode): string =
  case mode
  of mbmOff: t(tkSettingsMouseBondingOff)
  of mbmWhileShooting: t(tkSettingsMouseBondingWhileShooting)
  of mbmAlwaysInGame: t(tkSettingsMouseBondingAlwaysInGame)
  of mbmAlways: t(tkSettingsMouseBondingAlways)

proc nextMouseBondingMode(mode: MouseBondingMode): MouseBondingMode =
  case mode
  of mbmOff: mbmWhileShooting
  of mbmWhileShooting: mbmAlwaysInGame
  of mbmAlwaysInGame: mbmAlways
  of mbmAlways: mbmOff

proc getRenderResolutionModeLabel(mode: RenderResolutionMode): string =
  case mode
  of rrmDisabled: t(tkSettingsRenderResolutionDisabled)
  of rrmEnabled: t(tkSettingsRenderResolutionEnabled)
  of rrmFullscreenOnly: t(tkSettingsRenderResolutionFullscreenOnly)

proc nextRenderResolutionMode(mode: RenderResolutionMode): RenderResolutionMode =
  case mode
  of rrmDisabled: rrmEnabled
  of rrmEnabled: rrmFullscreenOnly
  of rrmFullscreenOnly: rrmDisabled

proc drawGraphicsTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15

  # Section: Display
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionDisplay), '@',
                   Color(r: 100, g: 200, b: 255, a: 255))
  yPos += 35

  # Fullscreen toggle
  drawText(t(tkSettingsFullscreen), (contentX + 40).int32, yPos.int32, 18, White)
  let fsCheckX = contentX + 320
  let mousePos = getVirtualMousePosition()
  let fsHovered = mousePos.x >= fsCheckX.float32 and
                  mousePos.x <= (fsCheckX + 25).float32 and
                  mousePos.y >= yPos.float32 and
                  mousePos.y <= (yPos + 25).float32
  drawCheckbox(fsCheckX, yPos, 25, settingsWin.settings.fullscreen, fsHovered)
  drawText(t(tkSettingsFullscreenToggle), (fsCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 40

  drawText(t(tkSettingsRenderResolution), (contentX + 40).int32, yPos.int32, 18, White)
  let renderModeButtonX = contentX + 320
  let renderModeButtonY = yPos - 5
  let renderModeButtonWidth = 220
  let renderModeButtonHeight = 35
  let renderModeHovered = mousePos.x >= renderModeButtonX.float32 and
                          mousePos.x <= (renderModeButtonX + renderModeButtonWidth).float32 and
                          mousePos.y >= renderModeButtonY.float32 and
                          mousePos.y <= (renderModeButtonY + renderModeButtonHeight).float32

  let renderModeBgColor = if renderModeHovered:
    Color(r: 80, g: 80, b: 100, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)

  drawRectangle(renderModeButtonX.int32, renderModeButtonY.int32,
                renderModeButtonWidth.int32, renderModeButtonHeight.int32, renderModeBgColor)
  drawRectangleLines(Rectangle(x: renderModeButtonX.float32, y: renderModeButtonY.float32,
                                width: renderModeButtonWidth.float32, height: renderModeButtonHeight.float32),
                    1, if renderModeHovered: Gold else: Color(r: 100, g: 100, b: 120, a: 255))

  let renderModeText = getRenderResolutionModeLabel(settingsWin.settings.renderResolutionMode)
  let renderModeTextWidth = measureText(renderModeText, 16)
  drawText("<", renderModeButtonX.int32 + 10, yPos.int32, 18, LightGray)
  drawText(renderModeText,
          (renderModeButtonX + (renderModeButtonWidth - renderModeTextWidth) div 2).int32,
          yPos.int32, 16, White)
  drawText(">", (renderModeButtonX + renderModeButtonWidth - 25).int32, yPos.int32, 18, LightGray)

  yPos += 35
  drawText(t(tkSettingsRenderResolutionDesc), renderModeButtonX.int32, yPos.int32, 14, LightGray)
  yPos += 25

  # FPS Limit — text input for custom values
  drawText(t(tkSettingsFpsLimit), (contentX + 40).int32, yPos.int32, 18, White)
  let boxX = contentX + 320
  let boxY = yPos - 5
  let boxWidth = 110
  let boxHeight = 35
  drawRectangle(boxX.int32, boxY.int32, boxWidth.int32, boxHeight.int32,
               if settingsWin.editingFPS: Color(r: 100, g: 100, b: 150, a: 255)
               else: Color(r: 60, g: 60, b: 80, a: 255))
  drawRectangleLines(Rectangle(x: boxX.float32, y: boxY.float32,
                                width: boxWidth.float32, height: boxHeight.float32),
                    if settingsWin.editingFPS: 2.0'f32 else: 1.0'f32,
                    if settingsWin.editingFPS: Gold else: Color(r: 100, g: 100, b: 120, a: 255))
  let displayText = if settingsWin.editingFPS:
    settingsWin.settings.inputBuffer & "_"
  else:
    $settingsWin.settings.fpsLimit
  let textWidth = measureText(displayText, 16)
  drawText(displayText, (boxX + (boxWidth - textWidth) div 2).int32,
          (boxY + (boxHeight - 16) div 2).int32, 16, White)

  yPos += 40

  # VSync
  drawText(t(tkSettingsVSync), (contentX + 40).int32, yPos.int32, 18, White)
  let vsyncCheckX = contentX + 320
  let vsyncHovered = mousePos.x >= vsyncCheckX.float32 and
                     mousePos.x <= (vsyncCheckX + 25).float32 and
                     mousePos.y >= yPos.float32 and
                     mousePos.y <= (yPos + 25).float32
  drawCheckbox(vsyncCheckX, yPos, 25, settingsWin.settings.vsyncEnabled, vsyncHovered)
  drawText(t(tkSettingsVSyncDesc), (vsyncCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35

  # Show FPS Counter
  drawText(t(tkSettingsShowFps), (contentX + 40).int32, yPos.int32, 18, White)
  let fpsCheckX = contentX + 320
  let fpsCheckHovered = mousePos.x >= fpsCheckX.float32 and
                        mousePos.x <= (fpsCheckX + 25).float32 and
                        mousePos.y >= yPos.float32 and
                        mousePos.y <= (yPos + 25).float32
  drawCheckbox(fpsCheckX, yPos, 25, settingsWin.settings.showFPS, fpsCheckHovered)
  yPos += 35

  # Debug Panel
  drawText(t(tkSettingsDebugPanel), (contentX + 40).int32, yPos.int32, 18, White)
  let debugCheckX = contentX + 320
  let debugHovered = mousePos.x >= debugCheckX.float32 and
                     mousePos.x <= (debugCheckX + 25).float32 and
                     mousePos.y >= yPos.float32 and
                     mousePos.y <= (yPos + 25).float32
  drawCheckbox(debugCheckX, yPos, 25, settingsWin.settings.showDebugStats, debugHovered)
  drawText(t(tkSettingsDebugPanelDesc), (debugCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35

  # Arena vignette
  drawText(t(tkSettingsArenaVignette), (contentX + 40).int32, yPos.int32, 18, White)
  let arenaVignetteCheckX = contentX + 320
  let arenaVignetteHovered = mousePos.x >= arenaVignetteCheckX.float32 and
                             mousePos.x <= (arenaVignetteCheckX + 25).float32 and
                             mousePos.y >= yPos.float32 and
                             mousePos.y <= (yPos + 25).float32
  drawCheckbox(arenaVignetteCheckX, yPos, 25, settingsWin.settings.showArenaVignette, arenaVignetteHovered)
  drawText(t(tkSettingsArenaVignetteDesc), (arenaVignetteCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35

  # Low HP vignette
  drawText(t(tkSettingsLowHealthVignette), (contentX + 40).int32, yPos.int32, 18, White)
  let lowHpVignetteCheckX = contentX + 320
  let lowHpVignetteHovered = mousePos.x >= lowHpVignetteCheckX.float32 and
                             mousePos.x <= (lowHpVignetteCheckX + 25).float32 and
                             mousePos.y >= yPos.float32 and
                             mousePos.y <= (yPos + 25).float32
  drawCheckbox(lowHpVignetteCheckX, yPos, 25, settingsWin.settings.showLowHealthVignette, lowHpVignetteHovered)
  drawText(t(tkSettingsLowHealthVignetteDesc), (lowHpVignetteCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)

proc drawAudioTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15

  # Section: Volume Control
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionVolumeControl), '~',
                   Color(r: 255, g: 200, b: 100, a: 255))
  yPos += 40

  let mousePos = getVirtualMousePosition()

  # Sound Effects Volume
  drawText(t(tkSettingsSoundEffects), (contentX + 40).int32, yPos.int32, 18, White)
  let volumeSliderX = contentX + 250
  let volumeSliderY = yPos + 5
  let sliderWidth = 300
  let sliderHeight = 20

  let volumeHovered = mousePos.x >= volumeSliderX.float32 and
                      mousePos.x <= (volumeSliderX + sliderWidth).float32 and
                      mousePos.y >= volumeSliderY.float32 and
                      mousePos.y <= (volumeSliderY + sliderHeight).float32

  drawSlider(volumeSliderX, volumeSliderY, sliderWidth, sliderHeight,
            settingsWin.settings.volume, volumeHovered or settingsWin.draggingVolume)

  let volPercent = int(settingsWin.settings.volume * 100)
  drawText($volPercent & "%", (volumeSliderX + sliderWidth + 15).int32, yPos.int32, 18, White)
  drawText(t(tkSettingsSoundEffectsDesc), (contentX + 40).int32,
          (volumeSliderY + sliderHeight + 4).int32, 12, Color(r: 120, g: 120, b: 150, a: 255))
  yPos += 55

  # Music Volume
  drawText(t(tkSettingsMusic), (contentX + 40).int32, yPos.int32, 18, White)
  let musicSliderX = contentX + 250
  let musicSliderY = yPos + 5

  let musicHovered = mousePos.x >= musicSliderX.float32 and
                     mousePos.x <= (musicSliderX + sliderWidth).float32 and
                     mousePos.y >= musicSliderY.float32 and
                     mousePos.y <= (musicSliderY + sliderHeight).float32

  drawSlider(musicSliderX, musicSliderY, sliderWidth, sliderHeight,
            settingsWin.settings.musicVolume, musicHovered or settingsWin.draggingMusic)

  let musicPercent = int(settingsWin.settings.musicVolume * 100)
  drawText($musicPercent & "%", (musicSliderX + sliderWidth + 15).int32, yPos.int32, 18, White)
  drawText(t(tkSettingsMusicDesc), (contentX + 40).int32,
          (musicSliderY + sliderHeight + 4).int32, 12, Color(r: 120, g: 120, b: 150, a: 255))

proc drawControlsTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15

  # Section: Input Method
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionInputMethod), '>',
                   Color(r: 200, g: 100, b: 255, a: 255))
  yPos += 35

  let mousePos = getVirtualMousePosition()

  # Mouse Bonding
  drawText(t(tkSettingsMouseBonding), (contentX + 40).int32, yPos.int32, 18, White)
  let bondingButtonX = contentX + 320
  let bondingButtonY = yPos - 5
  let bondingButtonWidth = 220
  let bondingButtonHeight = 35
  let bondingHovered = mousePos.x >= bondingButtonX.float32 and
                       mousePos.x <= (bondingButtonX + bondingButtonWidth).float32 and
                       mousePos.y >= bondingButtonY.float32 and
                       mousePos.y <= (bondingButtonY + bondingButtonHeight).float32

  let bondingBgColor = if bondingHovered:
    Color(r: 80, g: 80, b: 100, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)

  drawRectangle(bondingButtonX.int32, bondingButtonY.int32,
                bondingButtonWidth.int32, bondingButtonHeight.int32, bondingBgColor)
  drawRectangleLines(Rectangle(x: bondingButtonX.float32, y: bondingButtonY.float32,
                                width: bondingButtonWidth.float32, height: bondingButtonHeight.float32),
                    1, if bondingHovered: Gold else: Color(r: 100, g: 100, b: 120, a: 255))

  let bondingModeText = getMouseBondingModeLabel(settingsWin.settings.mouseBondingMode)
  let bondingTextWidth = measureText(bondingModeText, 16)
  drawText("<", bondingButtonX.int32 + 10, yPos.int32, 18, LightGray)
  drawText(bondingModeText,
          (bondingButtonX + (bondingButtonWidth - bondingTextWidth) div 2).int32,
          yPos.int32, 16, White)
  drawText(">", (bondingButtonX + bondingButtonWidth - 25).int32, yPos.int32, 18, LightGray)

  yPos += 35
  drawText(t(tkSettingsMouseBondingDesc), bondingButtonX.int32, yPos.int32, 14, LightGray)
  yPos += 25

  # Keybindings section
  yPos += 10
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionKeybindings), '#',
                   Color(r: 100, g: 255, b: 200, a: 255))
  yPos += 35

  let kbBtnW = 120
  let kbBtnH = 22
  let kbBtnX = contentX + contentW - kbBtnW - 20
  let kbActions = [
    (t(tkKeybindMoveUp),    kaMoveUp),
    (t(tkKeybindMoveDown),  kaMoveDown),
    (t(tkKeybindMoveLeft),  kaMoveLeft),
    (t(tkKeybindMoveRight), kaMoveRight),
    (t(tkKeybindShoot),     kaShoot),
    (t(tkKeybindPlaceWall), kaPlaceWall),
    (t(tkKeybindLegendary), kaLegendary),
  ]

  for (label, action) in kbActions:
    let isRebinding = settingsWin.rebindingAction == action.ord
    let btnY = yPos
    let btnHovered = not isRebinding and
                     mousePos.x >= kbBtnX.float32 and mousePos.x <= (kbBtnX + kbBtnW).float32 and
                     mousePos.y >= btnY.float32 and mousePos.y <= (btnY + kbBtnH).float32

    let btnBg     = if isRebinding: Color(r: 180, g: 100, b: 0, a: 255)
                    elif btnHovered: Color(r: 80, g: 80, b: 100, a: 255)
                    else: Color(r: 45, g: 45, b: 65, a: 255)
    let btnBorder = if isRebinding: Color(r: 255, g: 180, b: 0, a: 255)
                    elif btnHovered: Gold
                    else: Color(r: 100, g: 100, b: 120, a: 255)

    drawText(label, (contentX + 30).int32, (yPos + 4).int32, 14, LightGray)
    drawRectangle(kbBtnX.int32, btnY.int32, kbBtnW.int32, kbBtnH.int32, btnBg)
    drawRectangleLines(Rectangle(x: kbBtnX.float32, y: btnY.float32,
                                  width: kbBtnW.float32, height: kbBtnH.float32), 1, btnBorder)
    let keyText  = if isRebinding: t(tkKeybindPressAnyKey)
                   else: $settingsWin.settings.keybinds[action]
    let keyFg    = if isRebinding: Color(r: 255, g: 220, b: 100, a: 255) else: White
    let keyTextW = measureText(keyText, 13)
    drawText(keyText, (kbBtnX + (kbBtnW - keyTextW) div 2).int32, (yPos + 4).int32, 13, keyFg)
    yPos += 24

  # Reset to defaults button
  yPos += 6
  let resetBtnX = contentX + 20
  let resetBtnW = 160
  let resetBtnH = 26
  let resetHovered = mousePos.x >= resetBtnX.float32 and
                     mousePos.x <= (resetBtnX + resetBtnW).float32 and
                     mousePos.y >= yPos.float32 and
                     mousePos.y <= (yPos + resetBtnH).float32
  let resetBg = if resetHovered: Color(r: 80, g: 80, b: 100, a: 255)
                else: Color(r: 50, g: 50, b: 70, a: 255)
  drawRectangle(resetBtnX.int32, yPos.int32, resetBtnW.int32, resetBtnH.int32, resetBg)
  drawRectangleLines(Rectangle(x: resetBtnX.float32, y: yPos.float32,
                                width: resetBtnW.float32, height: resetBtnH.float32),
                    1, if resetHovered: Gold else: Color(r: 100, g: 100, b: 120, a: 255))
  let resetText  = t(tkKeybindResetDefaults)
  let resetTextW = measureText(resetText, 14)
  drawText(resetText, (resetBtnX + (resetBtnW - resetTextW) div 2).int32, (yPos + 5).int32, 14, White)
  yPos += 32

  # Fixed-key note
  drawText(t(tkKeybindNonRebindableNote), (contentX + 20).int32, yPos.int32, 12,
           Color(r: 130, g: 130, b: 160, a: 255))

proc drawGameplayTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15

  # Section: Assistance
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionAssistance), '?',
                   Color(r: 100, g: 255, b: 100, a: 255))
  yPos += 35

  let mousePos = getVirtualMousePosition()

  # Show Hints
  drawText(t(tkSettingsShowHints), (contentX + 40).int32, yPos.int32, 18, White)
  let hintsCheckX = contentX + 320
  let hintsHovered = mousePos.x >= hintsCheckX.float32 and
                     mousePos.x <= (hintsCheckX + 25).float32 and
                     mousePos.y >= yPos.float32 and
                     mousePos.y <= (yPos + 25).float32
  drawCheckbox(hintsCheckX, yPos, 25, settingsWin.settings.showHints, hintsHovered)
  drawText(t(tkSettingsShowHintsDesc), (hintsCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35

  # Show Enemy Labels
  drawText(t(tkSettingsShowEnemyLabels), (contentX + 40).int32, yPos.int32, 18, White)
  let labelsCheckX = contentX + 320
  let labelsHovered = mousePos.x >= labelsCheckX.float32 and
                      mousePos.x <= (labelsCheckX + 25).float32 and
                      mousePos.y >= yPos.float32 and
                      mousePos.y <= (yPos + 25).float32
  drawCheckbox(labelsCheckX, yPos, 25, settingsWin.settings.showEnemyLabels, labelsHovered)
  drawText(t(tkSettingsShowEnemyLabelsDesc), (labelsCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35

  # Exit Confirm Dialogs
  drawText(t(tkSettingsExitConfirm), (contentX + 40).int32, yPos.int32, 18, White)
  let exitConfirmCheckX = contentX + 320
  let exitConfirmHovered = mousePos.x >= exitConfirmCheckX.float32 and
                           mousePos.x <= (exitConfirmCheckX + 25).float32 and
                           mousePos.y >= yPos.float32 and
                           mousePos.y <= (yPos + 25).float32
  drawCheckbox(exitConfirmCheckX, yPos, 25, settingsWin.settings.exitConfirmEnabled, exitConfirmHovered)
  drawText(t(tkSettingsExitConfirmDesc), (exitConfirmCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 50

  # Section: Localization
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionLocalization), 'L',
                   Color(r: 255, g: 200, b: 100, a: 255))
  yPos += 35

  # Language selector
  drawText(t(tkSettingsLanguage), (contentX + 40).int32, yPos.int32, 18, White)
  let langButtonX = contentX + 320
  let langButtonY = yPos - 5
  let langButtonWidth = 200
  let langButtonHeight = 35

  let langHovered = mousePos.x >= langButtonX.float32 and
                   mousePos.x <= (langButtonX + langButtonWidth).float32 and
                   mousePos.y >= langButtonY.float32 and
                   mousePos.y <= (langButtonY + langButtonHeight).float32

  let langBgColor = if langHovered:
    Color(r: 80, g: 80, b: 100, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)

  drawRectangle(langButtonX.int32, langButtonY.int32, langButtonWidth.int32, langButtonHeight.int32, langBgColor)
  drawRectangleLines(Rectangle(x: langButtonX.float32, y: langButtonY.float32,
                                width: langButtonWidth.float32, height: langButtonHeight.float32),
                    1, if langHovered: Gold else: Color(r: 100, g: 100, b: 120, a: 255))

  # Display current language with arrows
  let currentLang = try: parseEnum[Language](settingsWin.settings.language) except: English
  let langDisplayText = getLanguageName(currentLang)
  let langTextWidth = measureText(langDisplayText, 18)
  drawText("<", langButtonX.int32 + 10, yPos.int32, 18, LightGray)
  drawText(langDisplayText, (langButtonX + (langButtonWidth - langTextWidth) div 2).int32, yPos.int32, 18, White)
  drawText(">", (langButtonX + langButtonWidth - 25).int32, yPos.int32, 18, LightGray)

  yPos += 45

  # Replay the opening story cinematic
  block:
    let rect = replayIntroButtonRect(contentX, contentY)
    let hovered = checkCollisionPointRec(mousePos, rect)
    drawSettingsButton(rect, t(tkSettingsReplayIntro), hovered, false)
    # Replay the endgame cinematic, only offered once the game has been beaten.
    if settingsWin.settings != nil and settingsWin.settings.hasSeenEnding:
      let endRect = replayEndingButtonRect(contentX, contentY)
      let endHovered = checkCollisionPointRec(mousePos, endRect)
      drawSettingsButton(endRect, t(tkSettingsReplayEnding), endHovered, false)
  yPos += 42

  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionDataManagement), '!',
                   Color(r: 255, g: 95, b: 105, a: 255))
  yPos += 35

  for action in [sraAllData, sraAdvancements, sraRogueliteData]:
    let rect = resetButtonRect(action, contentX, contentY)
    let hovered = checkCollisionPointRec(mousePos, rect)
    let confirming = settingsWin.pendingReset == action and settingsWin.resetConfirmTimer > 0.0
    let label = if confirming: t(tkSettingsConfirmReset) else: resetActionLabel(action)
    drawSettingsButton(rect, label, hovered, true, confirming)

  if settingsWin.resetStatusTimer > 0.0 and settingsWin.resetStatus.len > 0:
    let statusWidth = measureText(settingsWin.resetStatus, 14)
    drawText(settingsWin.resetStatus,
             (contentX + (contentW - statusWidth) div 2).int32,
             (contentY + 344).int32, 14, LightGray)

proc updateSettingsWindow*(settingsWin: SettingsWindow, dt: float32,
                          screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): tuple[shouldClose: bool, fullscreenToggle: bool] =
  ## Returns (shouldClose, fullscreenToggleRequested)
  updateOSWindow(settingsWin.window, dt)

  if not settingsWin.window.visible:
    return (false, false)

  if settingsWin.resetConfirmTimer > 0.0:
    settingsWin.resetConfirmTimer = max(0.0'f32, settingsWin.resetConfirmTimer - dt)
    if settingsWin.resetConfirmTimer <= 0.0:
      settingsWin.pendingReset = sraNone

  if settingsWin.resetStatusTimer > 0.0:
    settingsWin.resetStatusTimer = max(0.0'f32, settingsWin.resetStatusTimer - dt)

  # Check if window should close
  let shouldClose = handleOSWindowInput(settingsWin.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    settingsWin.window.visible = false
    return (true, false)

  let mousePos = getVirtualMousePosition()
  let contentX = settingsWin.window.x + WINDOW_PADDING
  let contentY = settingsWin.window.y + TITLE_BAR_HEIGHT + 60

  # Only handle content interactions if this window is topmost at mouse position
  let isTopmost = isWindowTopmostAtPoint(settingsWin.window, mousePos.x, mousePos.y, allWindows)

  # Tab switching with mouse (only if THIS window handled the click)
  if not settingsWin.window.minimized and settingsWin.window.handledClickThisFrame and isTopmost:
    let tabY = settingsWin.window.y + TITLE_BAR_HEIGHT + 10
    let tabHeight = 35
    let tabWidth = 140
    var tabX = contentX

    for tab in [stGraphics, stAudio, stControls, stGameplay]:
      if mousePos.x >= tabX.float32 and mousePos.x <= (tabX + tabWidth).float32 and
         mousePos.y >= tabY.float32 and mousePos.y <= (tabY + tabHeight).float32:
        settingsWin.currentTab = tab
        break
      tabX += tabWidth + 10

  # Tab switching with number keys (blocked while editing FPS or capturing a rebind)
  if not settingsWin.window.minimized and not settingsWin.editingFPS and settingsWin.rebindingAction < 0:
    if isKeyPressed(One): settingsWin.currentTab = stGraphics
    if isKeyPressed(Two): settingsWin.currentTab = stAudio
    if isKeyPressed(Three): settingsWin.currentTab = stControls
    if isKeyPressed(Four): settingsWin.currentTab = stGameplay

  var fullscreenToggle = false
  var settingsChanged = false

  # Handle Graphics tab interactions
  if settingsWin.currentTab == stGraphics and isTopmost:
    if settingsWin.window.handledClickThisFrame:
      let fsCheckX = contentX + 320
      let fsCheckY = contentY + 50

      # Fullscreen checkbox (25x25 hit area)
      if mousePos.x >= fsCheckX.float32 and mousePos.x <= (fsCheckX + 25).float32 and
         mousePos.y >= fsCheckY.float32 and mousePos.y <= (fsCheckY + 25).float32:
        settingsWin.settings.fullscreen = not settingsWin.settings.fullscreen
        fullscreenToggle = true
        settingsChanged = true

      let renderModeButtonX = contentX + 320
      let renderModeButtonY = contentY + 85
      let renderModeButtonWidth = 220
      let renderModeButtonHeight = 35
      if mousePos.x >= renderModeButtonX.float32 and mousePos.x <= (renderModeButtonX + renderModeButtonWidth).float32 and
         mousePos.y >= renderModeButtonY.float32 and mousePos.y <= (renderModeButtonY + renderModeButtonHeight).float32:
        settingsWin.settings.renderResolutionMode = nextRenderResolutionMode(settingsWin.settings.renderResolutionMode)
        playSound(stMenuSelect)
        settingsChanged = true

      # FPS text input box
      let boxX = contentX + 320
      let boxY = contentY + 145
      let boxWidth = 110
      let boxHeight = 35
      let boxHit = mousePos.x >= boxX.float32 and mousePos.x <= (boxX + boxWidth).float32 and
                   mousePos.y >= boxY.float32 and mousePos.y <= (boxY + boxHeight).float32
      if boxHit:
        if not settingsWin.editingFPS:
          settingsWin.editingFPS = true
          settingsWin.settings.inputBuffer = $settingsWin.settings.fpsLimit
      else:
        if settingsWin.editingFPS:
          if settingsWin.settings.inputBuffer.len > 0:
            try:
              let newFps = parseInt(settingsWin.settings.inputBuffer)
              if newFps >= 1 and newFps <= 9999:
                settingsWin.settings.fpsLimit = newFps.int32
                setTargetFPS(settingsWin.settings.fpsLimit)
                settingsChanged = true
            except:
              discard
          settingsWin.editingFPS = false

      # VSync checkbox
      let vsyncCheckX = contentX + 320
      let vsyncCheckY = contentY + 190
      if mousePos.x >= vsyncCheckX.float32 and mousePos.x <= (vsyncCheckX + 25).float32 and
         mousePos.y >= vsyncCheckY.float32 and mousePos.y <= (vsyncCheckY + 25).float32:
        settingsWin.settings.vsyncEnabled = not settingsWin.settings.vsyncEnabled
        if settingsWin.settings.vsyncEnabled:
          setWindowState(flags(VsyncHint))
        else:
          clearWindowState(flags(VsyncHint))
        settingsChanged = true

      # Show FPS checkbox (25x25 hit area)
      let fpsCheckX = contentX + 320
      let fpsCheckY = contentY + 225
      if mousePos.x >= fpsCheckX.float32 and mousePos.x <= (fpsCheckX + 25).float32 and
         mousePos.y >= fpsCheckY.float32 and mousePos.y <= (fpsCheckY + 25).float32:
        settingsWin.settings.showFPS = not settingsWin.settings.showFPS
        settingsChanged = true

      # Debug checkbox (25x25 hit area)
      let debugCheckX = contentX + 320
      let debugCheckY = contentY + 260
      if mousePos.x >= debugCheckX.float32 and mousePos.x <= (debugCheckX + 25).float32 and
         mousePos.y >= debugCheckY.float32 and mousePos.y <= (debugCheckY + 25).float32:
        settingsWin.settings.showDebugStats = not settingsWin.settings.showDebugStats
        settingsChanged = true

      let arenaVignetteCheckX = contentX + 320
      let arenaVignetteCheckY = contentY + 295
      if mousePos.x >= arenaVignetteCheckX.float32 and mousePos.x <= (arenaVignetteCheckX + 25).float32 and
         mousePos.y >= arenaVignetteCheckY.float32 and mousePos.y <= (arenaVignetteCheckY + 25).float32:
        settingsWin.settings.showArenaVignette = not settingsWin.settings.showArenaVignette
        settingsChanged = true

      let lowHpVignetteCheckX = contentX + 320
      let lowHpVignetteCheckY = contentY + 330
      if mousePos.x >= lowHpVignetteCheckX.float32 and mousePos.x <= (lowHpVignetteCheckX + 25).float32 and
         mousePos.y >= lowHpVignetteCheckY.float32 and mousePos.y <= (lowHpVignetteCheckY + 25).float32:
        settingsWin.settings.showLowHealthVignette = not settingsWin.settings.showLowHealthVignette
        settingsChanged = true

    # Keyboard input for FPS text box
    if settingsWin.editingFPS:
      let key = getCharPressed()
      if key > 0:
        let ch = char(key)
        if ch in '0'..'9' and settingsWin.settings.inputBuffer.len < 4:
          settingsWin.settings.inputBuffer.add(ch)
      if isKeyPressed(Backspace) and settingsWin.settings.inputBuffer.len > 0:
        settingsWin.settings.inputBuffer.setLen(settingsWin.settings.inputBuffer.len - 1)
      if isKeyPressed(Enter) and settingsWin.settings.inputBuffer.len > 0:
        try:
          let newFps = parseInt(settingsWin.settings.inputBuffer)
          if newFps >= 1 and newFps <= 9999:
            settingsWin.settings.fpsLimit = newFps.int32
            setTargetFPS(settingsWin.settings.fpsLimit)
            settingsChanged = true
        except:
          discard
        settingsWin.editingFPS = false

  # Handle Audio tab interactions
  if settingsWin.currentTab == stAudio and isTopmost:
    let volumeSliderX = contentX + 250
    let volumeSliderY = contentY + 55
    let sliderWidth = 300
    let sliderHeight = 20

    # Volume slider - check if mouse is over it first
    let volumeHovered = mousePos.x >= volumeSliderX.float32 and
                        mousePos.x <= (volumeSliderX + sliderWidth).float32 and
                        mousePos.y >= volumeSliderY.float32 and
                        mousePos.y <= (volumeSliderY + sliderHeight).float32

    # Start dragging on click
    if settingsWin.window.handledClickThisFrame and volumeHovered:
      settingsWin.draggingVolume = true

    # Continue dragging or handle click
    if settingsWin.draggingVolume or (isMouseButtonDown(Left) and volumeHovered):
      settingsWin.draggingVolume = true
      let relativeX = mousePos.x - volumeSliderX.float32
      settingsWin.settings.volume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
      setGameVolume(settingsWin.settings.volume)

    # Stop dragging on release
    if settingsWin.draggingVolume and not isMouseButtonDown(Left):
      settingsWin.draggingVolume = false
      settingsChanged = true  # Only save when slider is released

    # Music slider
    let musicSliderY = contentY + 110
    let musicHovered = mousePos.x >= volumeSliderX.float32 and
                       mousePos.x <= (volumeSliderX + sliderWidth).float32 and
                       mousePos.y >= musicSliderY.float32 and
                       mousePos.y <= (musicSliderY + sliderHeight).float32

    # Start dragging on click
    if settingsWin.window.handledClickThisFrame and musicHovered:
      settingsWin.draggingMusic = true

    # Continue dragging or handle click
    if settingsWin.draggingMusic or (isMouseButtonDown(Left) and musicHovered):
      settingsWin.draggingMusic = true
      let relativeX = mousePos.x - volumeSliderX.float32
      settingsWin.settings.musicVolume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
      setMusicVolume(settingsWin.settings.musicVolume)

    if settingsWin.draggingMusic and not isMouseButtonDown(Left):
      settingsWin.draggingMusic = false
      settingsChanged = true  # Only save when slider is released

    # Mouse wheel adjusts the slider under the cursor
    let wheelMove = getMouseWheelMove()
    if wheelMove != 0.0'f32:
      let hoverTol = 12.0'f32
      if mousePos.x >= volumeSliderX.float32 and mousePos.x <= (volumeSliderX + sliderWidth).float32 and
         mousePos.y >= (volumeSliderY.float32 - hoverTol) and mousePos.y <= (volumeSliderY.float32 + sliderHeight.float32 + hoverTol):
        settingsWin.settings.volume = clamp(settingsWin.settings.volume + wheelMove * 0.05'f32, 0.0, 1.0)
        setGameVolume(settingsWin.settings.volume)
        settingsChanged = true
      elif mousePos.x >= volumeSliderX.float32 and mousePos.x <= (volumeSliderX + sliderWidth).float32 and
           mousePos.y >= (musicSliderY.float32 - hoverTol) and mousePos.y <= (musicSliderY.float32 + sliderHeight.float32 + hoverTol):
        settingsWin.settings.musicVolume = clamp(settingsWin.settings.musicVolume + wheelMove * 0.05'f32, 0.0, 1.0)
        setMusicVolume(settingsWin.settings.musicVolume)
        settingsChanged = true

  # Handle Controls tab interactions
  if settingsWin.currentTab == stControls and isTopmost:
    if settingsWin.window.handledClickThisFrame:
      # Mouse bonding mode selector
      let bondingButtonX = contentX + 320
      let bondingButtonY = contentY + 45
      let bondingButtonWidth = 220
      let bondingButtonHeight = 35
      if mousePos.x >= bondingButtonX.float32 and mousePos.x <= (bondingButtonX + bondingButtonWidth).float32 and
         mousePos.y >= bondingButtonY.float32 and mousePos.y <= (bondingButtonY + bondingButtonHeight).float32:
        settingsWin.settings.mouseBondingMode = nextMouseBondingMode(settingsWin.settings.mouseBondingMode)
        playSound(stMenuSelect)
        settingsChanged = true

      # Keybind buttons — kbYBase mirrors drawControlsTab layout
      let kbYBase = contentY + 155
      let contentW = settingsWin.window.width - WINDOW_PADDING * 2
      let kbBtnW = 120
      let kbBtnH = 22
      let kbBtnX = contentX + contentW - kbBtnW - 20
      for action in KeyAction:
        let rowY = kbYBase + action.ord * 24
        if mousePos.x >= kbBtnX.float32 and mousePos.x <= (kbBtnX + kbBtnW).float32 and
           mousePos.y >= rowY.float32 and mousePos.y <= (rowY + kbBtnH).float32:
          settingsWin.rebindingAction = action.ord
          playSound(stMenuSelect)
          break

      # Reset keybinds to defaults button
      let resetBtnY = kbYBase + 7 * 24 + 6
      let resetBtnX = contentX + 20
      let resetBtnW = 160
      let resetBtnH = 26
      if mousePos.x >= resetBtnX.float32 and mousePos.x <= (resetBtnX + resetBtnW).float32 and
         mousePos.y >= resetBtnY.float32 and mousePos.y <= (resetBtnY + resetBtnH).float32:
        settingsWin.settings.keybinds = [
          kaMoveUp:    KeyboardKey.W,
          kaMoveDown:  KeyboardKey.S,
          kaMoveLeft:  KeyboardKey.A,
          kaMoveRight: KeyboardKey.D,
          kaShoot:     KeyboardKey.Space,
          kaPlaceWall: KeyboardKey.E,
          kaLegendary: KeyboardKey.Q
        ]
        settingsWin.rebindingAction = -1
        playSound(stMenuSelect)
        settingsChanged = true

  # Key capture for active rebind (runs every frame, gated so only the top window captures)
  if settingsWin.currentTab == stControls and settingsWin.rebindingAction >= 0 and isTopmost:
    let key = getKeyPressed()
    if key != KeyboardKey.Null:
      if key == KeyboardKey.Escape:
        settingsWin.rebindingAction = -1
      else:
        settingsWin.settings.keybinds[KeyAction(settingsWin.rebindingAction)] = key
        settingsWin.rebindingAction = -1
        settingsChanged = true

  # Handle Gameplay tab interactions
  if settingsWin.currentTab == stGameplay and isTopmost:
    if settingsWin.window.handledClickThisFrame:
      # Show hints checkbox (25x25 hit area)
      let hintsCheckX = contentX + 320
      let hintsCheckY = contentY + 50
      if mousePos.x >= hintsCheckX.float32 and mousePos.x <= (hintsCheckX + 25).float32 and
         mousePos.y >= hintsCheckY.float32 and mousePos.y <= (hintsCheckY + 25).float32:
        settingsWin.settings.showHints = not settingsWin.settings.showHints
        settingsChanged = true

      # Show enemy labels checkbox (25x25 hit area)
      let labelsCheckX = contentX + 320
      let labelsCheckY = contentY + 85
      if mousePos.x >= labelsCheckX.float32 and mousePos.x <= (labelsCheckX + 25).float32 and
         mousePos.y >= labelsCheckY.float32 and mousePos.y <= (labelsCheckY + 25).float32:
        settingsWin.settings.showEnemyLabels = not settingsWin.settings.showEnemyLabels
        settingsChanged = true

      # Exit confirm checkbox (25x25 hit area)
      let exitConfirmCheckX = contentX + 320
      let exitConfirmCheckY = contentY + 120
      if mousePos.x >= exitConfirmCheckX.float32 and mousePos.x <= (exitConfirmCheckX + 25).float32 and
         mousePos.y >= exitConfirmCheckY.float32 and mousePos.y <= (exitConfirmCheckY + 25).float32:
        settingsWin.settings.exitConfirmEnabled = not settingsWin.settings.exitConfirmEnabled
        settingsChanged = true

      # Language selector button
      let langButtonX = contentX + 320
      let langButtonY = contentY + 200
      let langButtonWidth = 200
      let langButtonHeight = 35
      if mousePos.x >= langButtonX.float32 and mousePos.x <= (langButtonX + langButtonWidth).float32 and
         mousePos.y >= langButtonY.float32 and mousePos.y <= (langButtonY + langButtonHeight).float32:
        # Cycle to next language
        let currentLang = try: parseEnum[Language](settingsWin.settings.language) except: English
        let nextLang = if currentLang == English: Spanish else: English
        settingsWin.settings.language = $nextLang
        setLanguage(nextLang)
        playSound(stMenuSelect)
        settingsChanged = true

      # Replay intro button
      if checkCollisionPointRec(mousePos, replayIntroButtonRect(contentX, contentY)):
        settingsWin.replayIntroRequested = true
        playSound(stMenuSelect)

      # Replay ending button (only active once the game has been beaten)
      if settingsWin.settings != nil and settingsWin.settings.hasSeenEnding and
         checkCollisionPointRec(mousePos, replayEndingButtonRect(contentX, contentY)):
        settingsWin.replayEndingRequested = true
        playSound(stMenuSelect)

      for action in [sraAllData, sraAdvancements, sraRogueliteData]:
        let rect = resetButtonRect(action, contentX, contentY)
        if checkCollisionPointRec(mousePos, rect):
          settingsWin.requestResetAction(action)
          break

  # Save settings if changed
  if settingsChanged:
    discard saveSettings(settingsWin.settings)

  return (false, fullscreenToggle)

proc drawSettingsWindow*(settingsWin: SettingsWindow) =
  if not settingsWin.window.visible:
    return

  # Draw window chrome
  drawWindowChrome(settingsWin.window)

  if settingsWin.window.minimized:
    return

  let contentX = settingsWin.window.x + WINDOW_PADDING
  let contentY = settingsWin.window.y + TITLE_BAR_HEIGHT + 10
  let contentW = settingsWin.window.width - WINDOW_PADDING * 2
  let contentH = settingsWin.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING

  # Draw tab headers
  let tabY = contentY
  let tabHeight = 35
  let tabWidth = 140
  let mousePos = getVirtualMousePosition()

  var tabX = contentX
  for tab in [stGraphics, stAudio, stControls, stGameplay]:
    let tabName = case tab
      of stGraphics: t(tkSettingsTabGraphics)
      of stAudio: t(tkSettingsTabAudio)
      of stControls: t(tkSettingsTabControls)
      of stGameplay: t(tkSettingsTabGameplay)

    let isActive = settingsWin.currentTab == tab
    let isHovered = mousePos.x >= tabX.float32 and
                   mousePos.x <= (tabX + tabWidth).float32 and
                   mousePos.y >= tabY.float32 and
                   mousePos.y <= (tabY + tabHeight).float32

    drawTab(tabName, tabX, tabY, tabWidth, tabHeight, isActive, isHovered)
    tabX += tabWidth + 10

  # Draw content area background
  let tabContentY = contentY + tabHeight + 10
  let tabContentH = contentH - tabHeight - 20

  drawRectangle(contentX.int32, tabContentY.int32, contentW.int32, tabContentH.int32,
               Color(r: 25, g: 25, b: 35, a: 255))
  drawRectangleLines(Rectangle(x: contentX.float32, y: tabContentY.float32,
                                width: contentW.float32, height: tabContentH.float32),
                    1, Color(r: 60, g: 60, b: 80, a: 255))

  # Draw active tab content
  case settingsWin.currentTab
  of stGraphics:
    drawGraphicsTab(settingsWin, contentX, tabContentY, contentW, tabContentH)
  of stAudio:
    drawAudioTab(settingsWin, contentX, tabContentY, contentW, tabContentH)
  of stControls:
    drawControlsTab(settingsWin, contentX, tabContentY, contentW, tabContentH)
  of stGameplay:
    drawGameplayTab(settingsWin, contentX, tabContentY, contentW, tabContentH)

  # Draw resize indicator
  drawResizeIndicator(settingsWin.window)
