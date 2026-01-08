from save_system import Settings, saveSettings, loadSettings
import raylib, strutils, sound, math, localization
export Settings  # Re-export Settings type

var globalSettings*: Settings

proc initSettings*(): Settings =
  result = Settings(
    fpsLimit: 60,
    volume: 0.5,
    musicVolume: 0.5,
    inputBuffer: "60",
    editingFPS: false,
    editingVolume: false,
    editingMusicVolume: false,
    fullscreen: false,
    showFPS: false,  # FPS counter disabled by default
    mouseSupport: true,  # Mouse support enabled by default
    showCursorInMenus: true,  # Show cursor in menus by default
    showDebugStats: false,  # Debug stats disabled by default
    showHints: true,  # Hints enabled by default
    showEnemyLabels: true,  # Enemy labels enabled by default
    language: "english"  # Default language is English
  )
  globalSettings = result
  
  # Try to load saved settings
  discard loadSettings(result)
  
  # Apply loaded language setting
  try:
    setLanguage(parseEnum[Language](result.language))
  except:
    setLanguage(English)
    result.language = "english"

proc drawSettings*(settings: Settings, screenWidth, screenHeight: int32, time: float32) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title
  let titleText = t(tkSettingsTitle)
  let titleWidth = measureText(titleText, 40)
  drawText(titleText, screenWidth div 2 - titleWidth div 2, 40, 40, Yellow)
  
  # FPS Limit Setting
  let fpsY: int32 = 120
  drawText(t(tkSettingsFpsLimit), 200'i32, fpsY, 24, White)
  
  # FPS input box
  let boxX: int32 = 400
  let boxY: int32 = fpsY - 5
  let boxWidth: int32 = 150
  let boxHeight: int32 = 35
  
  let boxColor = if settings.editingFPS:
    Color(r: 100, g: 100, b: 150, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)
  
  drawRectangle(boxX, boxY, boxWidth, boxHeight, boxColor)
  drawRectangleLines(boxX, boxY, boxWidth, boxHeight, 
                    if settings.editingFPS: Gold else: Gray)
  
  # Display current value or input buffer
  let displayText = if settings.editingFPS:
    settings.inputBuffer & "_"
  else:
    $settings.fpsLimit
  
  let textWidth = measureText(displayText, 24)
  drawText(displayText, boxX + (boxWidth - textWidth) div 2, fpsY, 24, White)
  
  # Instructions
  drawText(t(tkSettingsClickEdit), 200'i32, fpsY + 35, 16, LightGray)
  
  # Volume Setting
  let volumeY: int32 = 250
  drawText(t(tkSettingsSoundEffects), 200'i32, volumeY, 24, White)
  
  # Volume slider
  let sliderX: int32 = 400
  let sliderY: int32 = volumeY + 5
  let sliderWidth: int32 = 200
  let sliderHeight: int32 = 20
  
  # Slider background
  drawRectangle(sliderX, sliderY, sliderWidth, sliderHeight, 
               Color(r: 60, g: 60, b: 80, a: 255))
  
  # Slider fill
  let fillWidth = int32(sliderWidth.float32 * settings.volume)
  drawRectangle(sliderX, sliderY, fillWidth, sliderHeight, Gold)
  
  # Slider border
  drawRectangleLines(sliderX, sliderY, sliderWidth, sliderHeight, Gray)
  
  # Volume input box
  let volumeInputX: int32 = sliderX + sliderWidth + 20
  let volumeInputY: int32 = volumeY - 5
  let volumeBoxWidth: int32 = 100
  let volumeBoxHeight: int32 = 35
  
  let volumeBoxColor = if settings.editingVolume:
    Color(r: 100, g: 100, b: 150, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)
  
  drawRectangle(volumeInputX, volumeInputY, volumeBoxWidth, volumeBoxHeight, volumeBoxColor)
  drawRectangleLines(volumeInputX, volumeInputY, volumeBoxWidth, volumeBoxHeight, 
                    if settings.editingVolume: Gold else: Gray)
  
  let volumePercent = int(settings.volume * 100)
  let volumeDisplayText = if settings.editingVolume:
    settings.inputBuffer & "%_"
  else:
    $volumePercent & "%"
  
  let volumeTextWidth = measureText(volumeDisplayText, 20)
  drawText(volumeDisplayText, volumeInputX + (volumeBoxWidth - volumeTextWidth) div 2, volumeInputY + 7, 20, White)
  
  # Music Volume Setting
  let musicVolumeY: int32 = 310
  drawText(t(tkSettingsMusic), 200'i32, musicVolumeY, 24, White)
  
  # Music volume slider
  let musicSliderX: int32 = 400
  let musicSliderY: int32 = musicVolumeY + 5
  let musicSliderWidth: int32 = 200
  
  # Slider background
  drawRectangle(musicSliderX, musicSliderY, musicSliderWidth, sliderHeight, 
               Color(r: 60, g: 60, b: 80, a: 255))
  
  # Slider fill
  let musicFillWidth = int32(musicSliderWidth.float32 * settings.musicVolume)
  drawRectangle(musicSliderX, musicSliderY, musicFillWidth, sliderHeight, 
               Color(r: 100, g: 150, b: 255, a: 255))
  
  # Slider border
  drawRectangleLines(musicSliderX, musicSliderY, musicSliderWidth, sliderHeight, Gray)
  
  # Music volume input box
  let musicInputX: int32 = musicSliderX + musicSliderWidth + 20
  let musicInputY: int32 = musicVolumeY - 5
  let musicBoxWidth: int32 = 100
  let musicBoxHeight: int32 = 35
  
  let musicBoxColor = if settings.editingMusicVolume:
    Color(r: 100, g: 100, b: 150, a: 255)
  else:
    Color(r: 60, g: 60, b: 80, a: 255)
  
  drawRectangle(musicInputX, musicInputY, musicBoxWidth, musicBoxHeight, musicBoxColor)
  drawRectangleLines(musicInputX, musicInputY, musicBoxWidth, musicBoxHeight, 
                    if settings.editingMusicVolume: Gold else: Gray)
  
  let musicPercent = int(settings.musicVolume * 100)
  let musicDisplayText = if settings.editingMusicVolume:
    settings.inputBuffer & "%_"
  else:
    $musicPercent & "%"
  
  let musicTextWidth = measureText(musicDisplayText, 20)
  drawText(musicDisplayText, musicInputX + (musicBoxWidth - musicTextWidth) div 2, musicInputY + 7, 20, White)
  
  # Checkbox settings (compact layout)
  let checkboxSize: int32 = 25
  let checkboxColor = Color(r: 60, g: 60, b: 80, a: 255)
  let checkboxX: int32 = 400
  
  # Fullscreen Setting
  let fullscreenY: int32 = 370
  drawText(t(tkSettingsFullscreen), 200'i32, fullscreenY, 24, White)
  let fullscreenCheckY: int32 = fullscreenY + 5
  
  drawRectangle(checkboxX, fullscreenCheckY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, fullscreenCheckY, checkboxSize, checkboxSize, Gray)
  
  if settings.fullscreen:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (fullscreenCheckY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (fullscreenCheckY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (fullscreenCheckY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (fullscreenCheckY + 5).float32), 3, Green)
  
  drawText(t(tkSettingsFullscreenToggle), checkboxX + checkboxSize + 20, fullscreenY, 20, LightGray)
  
  # Show FPS Setting
  let showFPSY: int32 = 425
  drawText(t(tkSettingsShowFps), 200'i32, showFPSY, 24, White)
  let fpsCheckboxY: int32 = showFPSY + 5
  
  drawRectangle(checkboxX, fpsCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, fpsCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showFPS:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (fpsCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (fpsCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (fpsCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (fpsCheckboxY + 5).float32), 3, Green)
  
  # Mouse Support Setting
  let mouseSupportY: int32 = 480
  drawText(t(tkSettingsMouseSupport), 200'i32, mouseSupportY, 24, White)
  let mouseCheckboxY: int32 = mouseSupportY + 5
  
  drawRectangle(checkboxX, mouseCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, mouseCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.mouseSupport:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (mouseCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (mouseCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (mouseCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (mouseCheckboxY + 5).float32), 3, Green)
  
  drawText(t(tkSettingsMouseSupportDesc), checkboxX + checkboxSize + 20, mouseSupportY, 20, LightGray)
  
  # Show Cursor in Menus Setting (only visible when mouseSupport is disabled)
  if not settings.mouseSupport:
    let showCursorY: int32 = 535
    drawText(t(tkSettingsShowCursor), 200'i32, showCursorY, 24, White)
    let cursorCheckboxY: int32 = showCursorY + 5
    
    drawRectangle(checkboxX, cursorCheckboxY, checkboxSize, checkboxSize, checkboxColor)
    drawRectangleLines(checkboxX, cursorCheckboxY, checkboxSize, checkboxSize, Gray)
    
    if settings.showCursorInMenus:
      drawLine(Vector2(x: (checkboxX + 5).float32, y: (cursorCheckboxY + 12).float32),
              Vector2(x: (checkboxX + 12).float32, y: (cursorCheckboxY + 20).float32), 3, Green)
      drawLine(Vector2(x: (checkboxX + 12).float32, y: (cursorCheckboxY + 20).float32),
              Vector2(x: (checkboxX + 22).float32, y: (cursorCheckboxY + 5).float32), 3, Green)
    
    drawText(t(tkSettingsShowCursorDesc), checkboxX + checkboxSize + 20, showCursorY, 20, LightGray)
  
  # Show Debug Stats Setting - position changes based on whether Show Cursor is visible
  let showDebugStatsY: int32 = if not settings.mouseSupport: 590 else: 535
  drawText(t(tkSettingsDebugPanel), 200'i32, showDebugStatsY, 24, White)
  let debugCheckboxY: int32 = showDebugStatsY + 5
  
  drawRectangle(checkboxX, debugCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, debugCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showDebugStats:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (debugCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (debugCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (debugCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (debugCheckboxY + 5).float32), 3, Green)
  
  drawText(t(tkSettingsDebugPanelDesc), checkboxX + checkboxSize + 20, showDebugStatsY, 20, LightGray)
  
  # Show Hints Setting - position changes based on whether Show Cursor is visible
  let showHintsY: int32 = if not settings.mouseSupport: 645 else: 590
  drawText(t(tkSettingsShowHints), 200'i32, showHintsY, 24, White)
  let hintsCheckboxY: int32 = showHintsY + 5
  
  drawRectangle(checkboxX, hintsCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, hintsCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showHints:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (hintsCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (hintsCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (hintsCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (hintsCheckboxY + 5).float32), 3, Green)
  
  drawText(t(tkSettingsShowHintsDesc), checkboxX + checkboxSize + 20, showHintsY, 20, LightGray)
  
  # Show Enemy Labels Setting - position changes based on whether Show Cursor is visible
  let showEnemyLabelsY: int32 = if not settings.mouseSupport: 700 else: 645
  drawText(t(tkSettingsShowEnemyLabels), 200'i32, showEnemyLabelsY, 24, White)
  let enemyLabelsCheckboxY: int32 = showEnemyLabelsY + 5
  
  drawRectangle(checkboxX, enemyLabelsCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, enemyLabelsCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showEnemyLabels:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (enemyLabelsCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (enemyLabelsCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (enemyLabelsCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (enemyLabelsCheckboxY + 5).float32), 3, Green)
  
  drawText(t(tkSettingsShowEnemyLabelsDesc), checkboxX + checkboxSize + 20, showEnemyLabelsY, 20, LightGray)
  
  # Language Setting - position changes based on whether Show Cursor is visible
  let languageY: int32 = if not settings.mouseSupport: 755 else: 700
  drawText(t(tkSettingsLanguage), 200'i32, languageY, 24, White)
  
  # Language dropdown/cycle button
  let langButtonX: int32 = checkboxX
  let langButtonY: int32 = languageY - 5
  let langButtonWidth: int32 = 200
  let langButtonHeight: int32 = 35
  
  drawRectangle(langButtonX, langButtonY, langButtonWidth, langButtonHeight, 
               Color(r: 60, g: 60, b: 80, a: 255))
  drawRectangleLines(langButtonX, langButtonY, langButtonWidth, langButtonHeight, Gold)
  
  # Display current language
  let currentLang = try: parseEnum[Language](settings.language) except: English
  let langDisplayText = getLanguageName(currentLang)
  let langTextWidth = measureText(langDisplayText, 24)
  drawText(langDisplayText, langButtonX + (langButtonWidth - langTextWidth) div 2, languageY, 24, White)
  
  # Draw arrows to indicate it's clickable
  drawText("<", langButtonX + 10, languageY, 24, LightGray)
  drawText(">", langButtonX + langButtonWidth - 25, languageY, 24, LightGray)
  
  # Back instruction
  let backText = t(tkSettingsBackToMenu)
  let backTextWidth = measureText(backText, 20)
  drawText(backText, screenWidth div 2 - backTextWidth div 2, 
          screenHeight - 50, 20, LightGray)
  
  # ALWAYS draw custom cursor (never show system cursor)
  let mousePos = getMousePosition()
  let cursorPulse = sin(time * 8.0) * 2 + 8
  
  # Outer rotating ring
  for i in 0..<8:
    let angle = time * 4.0 + i.float32 * PI / 4.0
    let x = mousePos.x + cos(angle) * cursorPulse
    let y = mousePos.y + sin(angle) * cursorPulse
    drawCircle(Vector2(x: x, y: y), 2, Color(r: 255'u8, g: 200'u8, b: 50'u8, a: 200'u8))
  
  # Crosshair lines
  drawLine(Vector2(x: mousePos.x - 8, y: mousePos.y), 
          Vector2(x: mousePos.x - 3, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x + 3, y: mousePos.y), 
          Vector2(x: mousePos.x + 8, y: mousePos.y), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y - 8), 
          Vector2(x: mousePos.x, y: mousePos.y - 3), 2, White)
  drawLine(Vector2(x: mousePos.x, y: mousePos.y + 3), 
          Vector2(x: mousePos.x, y: mousePos.y + 8), 2, White)
  
  # Center dot
  drawCircle(Vector2(x: mousePos.x, y: mousePos.y), 2, Gold)

proc updateSettings*(settings: Settings): bool =
  ## Returns true if fullscreen toggle was requested
  var settingsChanged = false
  var fullscreenToggleRequested = false
  
  # Handle FPS input box click
  let boxX: int32 = 400
  let boxY: int32 = 115
  let boxWidth: int32 = 150
  let boxHeight: int32 = 35
  
  # Handle Volume input boxes click
  let volumeInputX: int32 = 620
  let volumeInputY: int32 = 245
  let volumeBoxWidth: int32 = 100
  let volumeBoxHeight: int32 = 35
  
  let musicInputX: int32 = 620
  let musicInputY: int32 = 305
  let musicBoxWidth: int32 = 100
  let musicBoxHeight: int32 = 35
  
  if isMouseButtonPressed(Left):
    let mousePos = getMousePosition()
    
    # FPS input box click
    if mousePos.x >= boxX.float32 and mousePos.x <= (boxX + boxWidth).float32 and
       mousePos.y >= boxY.float32 and mousePos.y <= (boxY + boxHeight).float32:
      settings.editingFPS = true
      settings.editingVolume = false
      settings.editingMusicVolume = false
      settings.inputBuffer = ""
    # Volume input box click
    elif mousePos.x >= volumeInputX.float32 and mousePos.x <= (volumeInputX + volumeBoxWidth).float32 and
       mousePos.y >= volumeInputY.float32 and mousePos.y <= (volumeInputY + volumeBoxHeight).float32:
      settings.editingVolume = true
      settings.editingFPS = false
      settings.editingMusicVolume = false
      settings.inputBuffer = ""
    # Music input box click
    elif mousePos.x >= musicInputX.float32 and mousePos.x <= (musicInputX + musicBoxWidth).float32 and
       mousePos.y >= musicInputY.float32 and mousePos.y <= (musicInputY + musicBoxHeight).float32:
      settings.editingMusicVolume = true
      settings.editingFPS = false
      settings.editingVolume = false
      settings.inputBuffer = ""
    else:
      settings.editingFPS = false
      settings.editingVolume = false
      settings.editingMusicVolume = false
  
  # Handle FPS input
  if settings.editingFPS:
    # Get text input
    let key = getCharPressed()
    if key > 0:
      let ch = char(key)
      if ch in '0'..'9' and settings.inputBuffer.len < 4:
        settings.inputBuffer.add(ch)
    
    # Handle backspace
    if isKeyPressed(Backspace) and settings.inputBuffer.len > 0:
      settings.inputBuffer.setLen(settings.inputBuffer.len - 1)
    
    # Handle enter to confirm
    if isKeyPressed(Enter):
      if settings.inputBuffer.len > 0:
        try:
          let newFps = parseInt(settings.inputBuffer)
          if newFps >= 30 and newFps <= 9999:
            let oldFps = settings.fpsLimit
            settings.fpsLimit = newFps.int32
            setTargetFPS(settings.fpsLimit)
            playSound(stMenuSelect)
            if oldFps != settings.fpsLimit:
              settingsChanged = true
          else:
            playSound(stMenuNav, 0.3)
        except:
          playSound(stMenuNav, 0.3)
      settings.editingFPS = false
  
  # Handle Volume input
  if settings.editingVolume:
    # Get text input
    let key = getCharPressed()
    if key > 0:
      let ch = char(key)
      if ch in '0'..'9' and settings.inputBuffer.len < 3:
        settings.inputBuffer.add(ch)
    
    # Handle backspace
    if isKeyPressed(Backspace) and settings.inputBuffer.len > 0:
      settings.inputBuffer.setLen(settings.inputBuffer.len - 1)
    
    # Handle enter to confirm
    if isKeyPressed(Enter):
      if settings.inputBuffer.len > 0:
        try:
          let newVolume = parseInt(settings.inputBuffer)
          if newVolume >= 0 and newVolume <= 9999:
            let oldVolume = settings.volume
            settings.volume = (newVolume.float32 / 100.0)
            playSound(stMenuSelect)
            if oldVolume != settings.volume:
              settingsChanged = true
          else:
            playSound(stMenuNav, 0.3)
        except:
          playSound(stMenuNav, 0.3)
      settings.editingVolume = false
  
  # Handle Music Volume input
  if settings.editingMusicVolume:
    # Get text input
    let key = getCharPressed()
    if key > 0:
      let ch = char(key)
      if ch in '0'..'9' and settings.inputBuffer.len < 3:
        settings.inputBuffer.add(ch)
    
    # Handle backspace
    if isKeyPressed(Backspace) and settings.inputBuffer.len > 0:
      settings.inputBuffer.setLen(settings.inputBuffer.len - 1)
    
    # Handle enter to confirm
    if isKeyPressed(Enter):
      if settings.inputBuffer.len > 0:
        try:
          let newMusicVolume = parseInt(settings.inputBuffer)
          if newMusicVolume >= 0 and newMusicVolume <= 9999:
            let oldMusicVolume = settings.musicVolume
            settings.musicVolume = (newMusicVolume.float32 / 100.0)
            setMusicVolume(settings.musicVolume)
            playSound(stMenuSelect)
            if oldMusicVolume != settings.musicVolume:
              settingsChanged = true
          else:
            playSound(stMenuNav, 0.3)
        except:
          playSound(stMenuNav, 0.3)
      settings.editingMusicVolume = false
  
  # Handle volume slider (only when not editing manually)
  if isMouseButtonDown(Left) and not settings.editingVolume and not settings.editingMusicVolume:
    let sliderX: int32 = 400
    let sliderY: int32 = 255  # volumeY (250) + 5
    let sliderWidth: int32 = 200
    let musicSliderY: int32 = 315  # musicVolumeY (310) + 5
    
    let mousePos = getMousePosition()
    
    # Sound effects volume slider
    if mousePos.y >= sliderY.float32 and mousePos.y <= (sliderY + 20).float32:
      if mousePos.x >= sliderX.float32 and mousePos.x <= (sliderX + sliderWidth).float32:
        let relativeX = mousePos.x - sliderX.float32
        let oldVolume = settings.volume
        settings.volume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
        if oldVolume != settings.volume:
          settingsChanged = true  # Mark as changed immediately when dragging
    
    # Music volume slider
    if mousePos.y >= musicSliderY.float32 and mousePos.y <= (musicSliderY + 20).float32:
      if mousePos.x >= sliderX.float32 and mousePos.x <= (sliderX + sliderWidth).float32:
        let relativeX = mousePos.x - sliderX.float32
        let oldMusicVolume = settings.musicVolume
        settings.musicVolume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
        setMusicVolume(settings.musicVolume)
        if oldMusicVolume != settings.musicVolume:
          settingsChanged = true  # Mark as changed immediately when dragging
  
  # Handle checkbox clicks
  if isMouseButtonPressed(Left):
    let checkboxX: int32 = 400
    let checkboxSize: int32 = 25
    let fullscreenCheckY: int32 = 375  # fullscreenY (370) + 5
    let fpsCheckboxY: int32 = 430      # showFPSY (425) + 5
    let mouseCheckboxY: int32 = 485    # mouseSupportY (480) + 5
    let cursorCheckboxY: int32 = 540   # showCursorY (535) + 5
    let debugCheckboxY: int32 = if not settings.mouseSupport: 595 else: 540  # dynamic based on mouse support
    let hintsCheckboxY: int32 = if not settings.mouseSupport: 650 else: 595  # dynamic based on mouse support
    
    let mousePos = getMousePosition()
    
    # Fullscreen checkbox - just toggle the setting, F11 applies it
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= fullscreenCheckY.float32 and mousePos.y <= (fullscreenCheckY + checkboxSize).float32:
      settings.fullscreen = not settings.fullscreen
      playSound(stMenuNav)
      settingsChanged = true
      fullscreenToggleRequested = true  # Request window recreation
    
    # Show FPS checkbox
    elif mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= fpsCheckboxY.float32 and mousePos.y <= (fpsCheckboxY + checkboxSize).float32:
      settings.showFPS = not settings.showFPS
      playSound(stMenuNav)
      settingsChanged = true
    
    # Mouse Support checkbox
    elif mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= mouseCheckboxY.float32 and mousePos.y <= (mouseCheckboxY + checkboxSize).float32:
      settings.mouseSupport = not settings.mouseSupport
      playSound(stMenuNav)
      settingsChanged = true
    
    # Show Cursor in Menus checkbox (only when mouseSupport is disabled)
    elif not settings.mouseSupport:
      if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
         mousePos.y >= cursorCheckboxY.float32 and mousePos.y <= (cursorCheckboxY + checkboxSize).float32:
        settings.showCursorInMenus = not settings.showCursorInMenus
        playSound(stMenuNav)
        settingsChanged = true
    
    # Show Debug Stats checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= debugCheckboxY.float32 and mousePos.y <= (debugCheckboxY + checkboxSize).float32:
      settings.showDebugStats = not settings.showDebugStats
      playSound(stMenuNav)
      settingsChanged = true
    
    # Show Hints checkbox
    elif mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= hintsCheckboxY.float32 and mousePos.y <= (hintsCheckboxY + checkboxSize).float32:
      settings.showHints = not settings.showHints
      playSound(stMenuNav)
      settingsChanged = true
    
    # Show Enemy Labels checkbox
    let enemyLabelsCheckboxY: int32 = if not settings.mouseSupport: 705 else: 650  # Dynamic based on mouse support
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= enemyLabelsCheckboxY.float32 and mousePos.y <= (enemyLabelsCheckboxY + checkboxSize).float32:
      settings.showEnemyLabels = not settings.showEnemyLabels
      playSound(stMenuNav)
      settingsChanged = true
    
    # Language selector button
    let languageY: int32 = if not settings.mouseSupport: 755 else: 700
    let langButtonX: int32 = 400
    let langButtonY: int32 = languageY - 5
    let langButtonWidth: int32 = 200
    let langButtonHeight: int32 = 35
    
    if mousePos.x >= langButtonX.float32 and mousePos.x <= (langButtonX + langButtonWidth).float32 and
       mousePos.y >= langButtonY.float32 and mousePos.y <= (langButtonY + langButtonHeight).float32:
      # Cycle to next language
      let currentLang = try: parseEnum[Language](settings.language) except: English
      let nextLang = if currentLang == English: Spanish else: English
      settings.language = $nextLang
      setLanguage(nextLang)
      playSound(stMenuSelect)
      settingsChanged = true
  
  # Only save if settings actually changed
  if settingsChanged:
    discard saveSettings(settings)
  
  return fullscreenToggleRequested

proc applySettings*(settings: Settings) =
  setTargetFPS(settings.fpsLimit)
  # Apply volume settings to sound system
  setGameVolume(settings.volume)
  setMusicVolume(settings.musicVolume)
