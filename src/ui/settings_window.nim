## OS-Themed Settings Control Panel
## Tabbed settings interface matching the OS visual language

import raylib, strutils, ../sound, ../save_system, os_window, ../settings, ../localization

type
  SettingsTab* = enum
    stGraphics
    stAudio
    stControls
    stGameplay
  
  SettingsWindow* = ref object
    window*: OSWindow
    currentTab*: SettingsTab
    settings*: Settings
    
    # UI state
    hoveredControl*: int  # -1 for none
    editingFPS*: bool
    editingVolume*: bool
    editingMusicVolume*: bool
    
    # Slider state
    draggingVolume*: bool
    draggingMusic*: bool

proc newSettingsWindow*(screenWidth, screenHeight: int, settings: Settings): SettingsWindow =
  let windowWidth = 700
  let windowHeight = 500
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2
  
  let osWin = newOSWindow(
    "Settings - System Control Panel",
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
    hoveredControl: -1,
    editingFPS: false,
    editingVolume: false,
    editingMusicVolume: false,
    draggingVolume: false,
    draggingMusic: false
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
  
  let textWidth = measureText(tabName, 16)
  let textX = x + (width - textWidth) div 2
  let textY = y + (height - 16) div 2
  
  let textColor = if isActive: Gold else: White
  drawText(tabName, textX.int32, textY.int32, 16, textColor)

proc drawCheckbox*(x, y, size: int, checked: bool, hovered: bool) =
  let bgColor = if hovered:
    Color(r: 80, g: 80, b: 100, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)
  
  drawRectangle(x.int32, y.int32, size.int32, size.int32, bgColor)
  drawRectangleLines(Rectangle(x: x.float32, y: y.float32,
                                width: size.float32, height: size.float32),
                    1, Color(r: 120, g: 120, b: 140, a: 255))
  
  if checked:
    drawLine(Vector2(x: (x + 5).float32, y: (y + size div 2).float32),
            Vector2(x: (x + size div 2 - 2).float32, y: (y + size - 5).float32),
            3, Green)
    drawLine(Vector2(x: (x + size div 2 - 2).float32, y: (y + size - 5).float32),
            Vector2(x: (x + size - 3).float32, y: (y + 3).float32),
            3, Green)

proc drawSlider*(x, y, width, height: int, value: float32, hovered: bool, 
                showTicks: bool = false, tickValues: seq[int] = @[]) =
  # Background
  drawRectangle(x.int32, y.int32, width.int32, height.int32,
               Color(r: 40, g: 40, b: 50, a: 255))
  
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
  drawRectangle((handleX).int32, (y - 3).int32, 10, (height + 6).int32,
               if hovered: Gold else: White)

proc drawSectionHeader*(x, y, width: int, title: string, iconChar: char, color: Color) =
  ## Draw a section divider with icon
  # Horizontal line
  drawRectangle(x.int32, (y + 10).int32, width.int32, 2,
               Color(r: 0, g: 200, b: 255, a: 100))
  
  # Icon circle
  drawCircle(Vector2(x: (x + 15).float32, y: (y + 11).float32), 10, color)
  drawText($iconChar, (x + 10).int32, (y + 3).int32, 16, Black)
  
  # Title text
  drawText(title, (x + 35).int32, (y + 2).int32, 18,
          Color(r: 0, g: 220, b: 255, a: 255))

proc drawGraphicsTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15
  
  # Section: Display
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionDisplay), '@',
                   Color(r: 100, g: 200, b: 255, a: 255))
  yPos += 35
  
  # Fullscreen toggle
  drawText(t(tkSettingsFullscreen), (contentX + 40).int32, yPos.int32, 18, White)
  let fsCheckX = contentX + 320
  let mousePos = getMousePosition()
  let fsHovered = mousePos.x >= fsCheckX.float32 and 
                  mousePos.x <= (fsCheckX + 25).float32 and
                  mousePos.y >= yPos.float32 and 
                  mousePos.y <= (yPos + 25).float32
  drawCheckbox(fsCheckX, yPos, 25, settingsWin.settings.fullscreen, fsHovered)
  drawText(t(tkSettingsFullscreenToggle), (fsCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
  yPos += 35
  
  # FPS Limit
  drawText(t(tkSettingsFpsLimit), (contentX + 40).int32, yPos.int32, 18, White)
  
  let boxX = contentX + 320
  let boxY = yPos - 5
  let boxWidth = 120
  let boxHeight = 30
  
  let boxColor = if settingsWin.editingFPS:
    Color(r: 100, g: 100, b: 150, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)
  
  drawRectangle(boxX.int32, boxY.int32, boxWidth.int32, boxHeight.int32, boxColor)
  drawRectangleLines(Rectangle(x: boxX.float32, y: boxY.float32,
                                width: boxWidth.float32, height: boxHeight.float32),
                    if settingsWin.editingFPS: 2 else: 1,
                    if settingsWin.editingFPS: Gold else: Gray)
  
  let displayText = if settingsWin.editingFPS:
    settingsWin.settings.inputBuffer & "_"
  else:
    $settingsWin.settings.fpsLimit
  
  let textWidth = measureText(displayText, 20)
  drawText(displayText, (boxX + (boxWidth - textWidth) div 2).int32, 
          (boxY + 5).int32, 20, White)
  yPos += 40
  
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

proc drawAudioTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15
  
  # Section: Volume Control
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionVolumeControl), '~',
                   Color(r: 255, g: 200, b: 100, a: 255))
  yPos += 40
  
  let mousePos = getMousePosition()
  
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
  yPos += 45
  
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

proc drawControlsTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15
  
  # Section: Input Method
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionInputMethod), '>',
                   Color(r: 200, g: 100, b: 255, a: 255))
  yPos += 35
  
  let mousePos = getMousePosition()
  
  # Mouse Support
  drawText(t(tkSettingsMouseSupport), (contentX + 40).int32, yPos.int32, 18, White)
  let mouseCheckX = contentX + 320
  let mouseHovered = mousePos.x >= mouseCheckX.float32 and 
                     mousePos.x <= (mouseCheckX + 25).float32 and
                     mousePos.y >= yPos.float32 and 
                     mousePos.y <= (yPos + 25).float32
  drawCheckbox(mouseCheckX, yPos, 25, settingsWin.settings.mouseSupport, mouseHovered)
  drawText(t(tkSettingsMouseSupportDesc), (mouseCheckX + 35).int32, 
          (yPos + 3).int32, 14, LightGray)
  yPos += 40
  
  # Show Cursor in Menus
  if not settingsWin.settings.mouseSupport:
    drawText(t(tkSettingsShowCursor), (contentX + 40).int32, yPos.int32, 18, 
            Color(r: 180, g: 180, b: 180, a: 255))
    let cursorCheckX = contentX + 320
    let cursorHovered = mousePos.x >= cursorCheckX.float32 and 
                       mousePos.x <= (cursorCheckX + 25).float32 and
                       mousePos.y >= yPos.float32 and 
                       mousePos.y <= (yPos + 25).float32
    drawCheckbox(cursorCheckX, yPos, 25, settingsWin.settings.showCursorInMenus, cursorHovered)
    drawText(t(tkSettingsShowCursorDesc), (cursorCheckX + 35).int32, (yPos + 3).int32, 14, LightGray)
    yPos += 40
  
  # Keyboard Shortcuts section
  yPos += 10
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionKeyboardShortcuts), '#',
                   Color(r: 100, g: 255, b: 200, a: 255))
  yPos += 35
  
  # Display key bindings
  let shortcuts = [
    (t(tkSettingsKeyboardWASD), t(tkSettingsKeyboardMovement)),
    (t(tkSettingsKeyboardMouseSpace), t(tkSettingsKeyboardShoot)),
    (t(tkSettingsKeyboardF), t(tkSettingsKeyboardToggleAutoShoot)),
    (t(tkSettingsKeyboardE), t(tkSettingsKeyboardPlaceWall)),
    (t(tkSettingsKeyboardQ), t(tkSettingsKeyboardLegendaryAbilities)),
    (t(tkSettingsKeyboardESC), t(tkSettingsKeyboardPauseMenu)),
    (t(tkSettingsKeyboardF11), t(tkSettingsKeyboardToggleFullscreen)),
  ]
  
  for binding in shortcuts:
    drawText(binding[0], (contentX + 50).int32, yPos.int32, 16, Gold)
    drawText(binding[1], (contentX + 250).int32, yPos.int32, 16, White)
    yPos += 22

proc drawGameplayTab*(settingsWin: SettingsWindow, contentX, contentY, contentW, contentH: int) =
  var yPos = contentY + 15
  
  # Section: Assistance
  drawSectionHeader(contentX + 20, yPos, contentW - 40, t(tkSettingsSectionAssistance), '?',
                   Color(r: 100, g: 255, b: 100, a: 255))
  yPos += 35
  
  let mousePos = getMousePosition()
  
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

proc updateSettingsWindow*(settingsWin: SettingsWindow, dt: float32, 
                          screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): tuple[shouldClose: bool, fullscreenToggle: bool] =
  ## Returns (shouldClose, fullscreenToggleRequested)
  updateOSWindow(settingsWin.window, dt)
  
  if not settingsWin.window.visible:
    return (false, false)
  
  # Check if window should close
  let shouldClose = handleOSWindowInput(settingsWin.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    settingsWin.window.visible = false
    return (true, false)
  
  let mousePos = getMousePosition()
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
  
  # Tab switching with number keys (only when not minimized and not editing FPS)
  if not settingsWin.window.minimized and not settingsWin.editingFPS:
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
      
      # FPS input box
      let boxX = contentX + 320
      let boxY = contentY + 80
      let boxWidth = 120
      let boxHeight = 30
      let boxHit = mousePos.x >= boxX.float32 and mousePos.x <= (boxX + boxWidth).float32 and
                   mousePos.y >= boxY.float32 and mousePos.y <= (boxY + boxHeight).float32
      if boxHit:
        if not settingsWin.editingFPS:
          settingsWin.editingFPS = true
          settingsWin.settings.inputBuffer = ""
      else:
        if settingsWin.editingFPS:
          # Commit FPS on clicking outside
          if settingsWin.settings.inputBuffer.len > 0:
            try:
              let newFps = parseInt(settingsWin.settings.inputBuffer)
              if newFps >= 30 and newFps <= 9999:
                settingsWin.settings.fpsLimit = newFps.int32
                setTargetFPS(settingsWin.settings.fpsLimit)
                settingsChanged = true
            except:
              discard
        settingsWin.editingFPS = false
      
      # Show FPS checkbox (25x25 hit area)
      let fpsCheckX = contentX + 320
      let fpsCheckY = contentY + 125
      if mousePos.x >= fpsCheckX.float32 and mousePos.x <= (fpsCheckX + 25).float32 and
         mousePos.y >= fpsCheckY.float32 and mousePos.y <= (fpsCheckY + 25).float32:
        settingsWin.settings.showFPS = not settingsWin.settings.showFPS
        settingsChanged = true
      
      # Debug checkbox (25x25 hit area)
      let debugCheckX = contentX + 320
      let debugCheckY = contentY + 160
      if mousePos.x >= debugCheckX.float32 and mousePos.x <= (debugCheckX + 25).float32 and
         mousePos.y >= debugCheckY.float32 and mousePos.y <= (debugCheckY + 25).float32:
        settingsWin.settings.showDebugStats = not settingsWin.settings.showDebugStats
        settingsChanged = true
    
    # Handle FPS text input
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
          if newFps >= 30 and newFps <= 9999:
            settingsWin.settings.fpsLimit = newFps.int32
            setTargetFPS(settingsWin.settings.fpsLimit)
            settingsChanged = true
        except:
          discard
        settingsWin.editingFPS = false
  
  # Handle Audio tab interactions
  if settingsWin.currentTab == stAudio and isTopmost:
    let volumeSliderX = contentX + 250
    let volumeSliderY = contentY + 45
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
    
    # Stop dragging on release
    if settingsWin.draggingVolume and not isMouseButtonDown(Left):
      settingsWin.draggingVolume = false
      settingsChanged = true  # Only save when slider is released
    
    # Music slider
    let musicSliderY = contentY + 90
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
  
  # Handle Controls tab interactions
  if settingsWin.currentTab == stControls and isTopmost:
    if settingsWin.window.handledClickThisFrame:
      # Mouse support checkbox (25x25 hit area)
      let mouseCheckX = contentX + 320
      let mouseCheckY = contentY + 50
      if mousePos.x >= mouseCheckX.float32 and mousePos.x <= (mouseCheckX + 25).float32 and
         mousePos.y >= mouseCheckY.float32 and mousePos.y <= (mouseCheckY + 25).float32:
        settingsWin.settings.mouseSupport = not settingsWin.settings.mouseSupport
        settingsChanged = true
      
      # Show cursor checkbox
      if not settingsWin.settings.mouseSupport:
        let cursorCheckX = contentX + 320
        let cursorCheckY = contentY + 90
        if mousePos.x >= cursorCheckX.float32 and mousePos.x <= (cursorCheckX + 25).float32 and
           mousePos.y >= cursorCheckY.float32 and mousePos.y <= (cursorCheckY + 25).float32:
          settingsWin.settings.showCursorInMenus = not settingsWin.settings.showCursorInMenus
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
      
      # Language selector button
      let langButtonX = contentX + 320
      let langButtonY = contentY + 165
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
  let mousePos = getMousePosition()
  
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
