import raylib, strutils, sound, math, save_system, settings_types

export settings_types

var globalSettings*: Settings

proc initSettings*(): Settings =
  result = Settings(
    fpsLimit: 60,
    volume: 0.5,
    musicVolume: 0.5,
    inputBuffer: "60",
    editingFPS: false,
    fullscreen: false,
    showFPS: false,  # FPS counter disabled by default
    mouseSupport: true,  # Mouse support enabled by default
    showCursorInMenus: true,  # Show cursor in menus by default
    showDebugStats: false,  # Debug stats disabled by default
    showHints: true  # Hints enabled by default
  )
  globalSettings = result
  
  # Try to load saved settings
  discard loadSettings(result)

proc drawSettings*(settings: Settings, screenWidth, screenHeight: int32, time: float32) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title
  drawText("SETTINGS", screenWidth div 2 - 100, 40, 40, Yellow)
  
  # FPS Limit Setting
  let fpsY: int32 = 120
  drawText("FPS Limit:", 200'i32, fpsY, 24, White)
  
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
  drawText("Click to edit, Enter to confirm", 200'i32, fpsY + 35, 16, LightGray)
  
  # FPS Warning - Show if FPS is set higher than recommended (COMPACT)
  if settings.fpsLimit > 60:
    let warningY = fpsY + 58
    let warningColor = if settings.fpsLimit > 300: 
      Color(r: 255, g: 50, b: 50, a: 255)  # Red for very high FPS
    else: 
      Color(r: 255, g: 200, b: 0, a: 255)  # Orange for moderately high FPS
    
    if settings.fpsLimit > 300:
      drawText("WARNING: FPS > 300 may cause bugs! (60 recommended)", 200'i32, warningY, 15, warningColor)
    else:
      drawText("Note: 60 FPS recommended for stability", 200'i32, warningY, 15, warningColor)
  
  # Volume Setting
  let volumeY: int32 = 250
  drawText("Sound Effects:", 200'i32, volumeY, 24, White)
  
  # Volume slider
  let sliderX: int32 = 400
  let sliderY: int32 = volumeY + 5
  let sliderWidth: int32 = 300
  let sliderHeight: int32 = 20
  
  # Slider background
  drawRectangle(sliderX, sliderY, sliderWidth, sliderHeight, 
               Color(r: 60, g: 60, b: 80, a: 255))
  
  # Slider fill
  let fillWidth = int32(sliderWidth.float32 * settings.volume)
  drawRectangle(sliderX, sliderY, fillWidth, sliderHeight, Gold)
  
  # Slider border
  drawRectangleLines(sliderX, sliderY, sliderWidth, sliderHeight, Gray)
  
  # Volume percentage
  let volumePercent = int(settings.volume * 100)
  drawText($volumePercent & "%", sliderX + sliderWidth + 20, volumeY, 24, White)
  
  # Music Volume Setting
  let musicVolumeY: int32 = 310
  drawText("Music:", 200'i32, musicVolumeY, 24, White)
  
  # Music volume slider
  let musicSliderX: int32 = 400
  let musicSliderY: int32 = musicVolumeY + 5
  
  # Slider background
  drawRectangle(musicSliderX, musicSliderY, sliderWidth, sliderHeight, 
               Color(r: 60, g: 60, b: 80, a: 255))
  
  # Slider fill
  let musicFillWidth = int32(sliderWidth.float32 * settings.musicVolume)
  drawRectangle(musicSliderX, musicSliderY, musicFillWidth, sliderHeight, 
               Color(r: 100, g: 150, b: 255, a: 255))
  
  # Slider border
  drawRectangleLines(musicSliderX, musicSliderY, sliderWidth, sliderHeight, Gray)
  
  # Music volume percentage
  let musicVolumePercent = int(settings.musicVolume * 100)
  drawText($musicVolumePercent & "%", musicSliderX + sliderWidth + 20, musicVolumeY, 24, White)
  
  # Checkbox settings (compact layout)
  let checkboxSize: int32 = 25
  let checkboxColor = Color(r: 60, g: 60, b: 80, a: 255)
  let checkboxX: int32 = 400
  
  # Fullscreen Setting
  let fullscreenY: int32 = 370
  drawText("Fullscreen:", 200'i32, fullscreenY, 24, White)
  let fullscreenCheckY: int32 = fullscreenY + 5
  
  drawRectangle(checkboxX, fullscreenCheckY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, fullscreenCheckY, checkboxSize, checkboxSize, Gray)
  
  if settings.fullscreen:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (fullscreenCheckY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (fullscreenCheckY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (fullscreenCheckY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (fullscreenCheckY + 5).float32), 3, Green)
  
  drawText("(F11 to toggle)", checkboxX + checkboxSize + 20, fullscreenY, 20, LightGray)
  
  # Show FPS Setting
  let showFPSY: int32 = 425
  drawText("Show FPS:", 200'i32, showFPSY, 24, White)
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
  drawText("Mouse Support:", 200'i32, mouseSupportY, 24, White)
  let mouseCheckboxY: int32 = mouseSupportY + 5
  
  drawRectangle(checkboxX, mouseCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, mouseCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.mouseSupport:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (mouseCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (mouseCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (mouseCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (mouseCheckboxY + 5).float32), 3, Green)
  
  drawText("(menu navigation)", checkboxX + checkboxSize + 20, mouseSupportY, 20, LightGray)
  
  # Show Cursor in Menus Setting (only visible when mouseSupport is disabled)
  if not settings.mouseSupport:
    let showCursorY: int32 = 535
    drawText("Show Cursor:", 200'i32, showCursorY, 24, White)
    let cursorCheckboxY: int32 = showCursorY + 5
    
    drawRectangle(checkboxX, cursorCheckboxY, checkboxSize, checkboxSize, checkboxColor)
    drawRectangleLines(checkboxX, cursorCheckboxY, checkboxSize, checkboxSize, Gray)
    
    if settings.showCursorInMenus:
      drawLine(Vector2(x: (checkboxX + 5).float32, y: (cursorCheckboxY + 12).float32),
              Vector2(x: (checkboxX + 12).float32, y: (cursorCheckboxY + 20).float32), 3, Green)
      drawLine(Vector2(x: (checkboxX + 12).float32, y: (cursorCheckboxY + 20).float32),
              Vector2(x: (checkboxX + 22).float32, y: (cursorCheckboxY + 5).float32), 3, Green)
    
    drawText("(visual only)", checkboxX + checkboxSize + 20, showCursorY, 20, LightGray)
  
  # Show Debug Stats Setting - position changes based on whether Show Cursor is visible
  let showDebugStatsY: int32 = if not settings.mouseSupport: 590 else: 535
  drawText("Debug Panel:", 200'i32, showDebugStatsY, 24, White)
  let debugCheckboxY: int32 = showDebugStatsY + 5
  
  drawRectangle(checkboxX, debugCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, debugCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showDebugStats:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (debugCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (debugCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (debugCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (debugCheckboxY + 5).float32), 3, Green)
  
  drawText("(top-right stats)", checkboxX + checkboxSize + 20, showDebugStatsY, 20, LightGray)
  
  # Show Hints Setting - position changes based on whether Show Cursor is visible
  let showHintsY: int32 = if not settings.mouseSupport: 645 else: 590
  drawText("Show Hints:", 200'i32, showHintsY, 24, White)
  let hintsCheckboxY: int32 = showHintsY + 5
  
  drawRectangle(checkboxX, hintsCheckboxY, checkboxSize, checkboxSize, checkboxColor)
  drawRectangleLines(checkboxX, hintsCheckboxY, checkboxSize, checkboxSize, Gray)
  
  if settings.showHints:
    drawLine(Vector2(x: (checkboxX + 5).float32, y: (hintsCheckboxY + 12).float32),
            Vector2(x: (checkboxX + 12).float32, y: (hintsCheckboxY + 20).float32), 3, Green)
    drawLine(Vector2(x: (checkboxX + 12).float32, y: (hintsCheckboxY + 20).float32),
            Vector2(x: (checkboxX + 22).float32, y: (hintsCheckboxY + 5).float32), 3, Green)
  
  drawText("(E: Wall, ESC: Pause)", checkboxX + checkboxSize + 20, showHintsY, 20, LightGray)
  
  # Back instruction
  drawText("Press ESC to return to menu", screenWidth div 2 - 180, 
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

proc updateSettings*(settings: Settings) =
  # Handle FPS input box click
  let boxX: int32 = 400
  let boxY: int32 = 115
  let boxWidth: int32 = 150
  let boxHeight: int32 = 35
  
  if isMouseButtonPressed(Left):
    let mousePos = getMousePosition()
    if mousePos.x >= boxX.float32 and mousePos.x <= (boxX + boxWidth).float32 and
       mousePos.y >= boxY.float32 and mousePos.y <= (boxY + boxHeight).float32:
      settings.editingFPS = true
      settings.inputBuffer = ""
    else:
      settings.editingFPS = false
  
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
            settings.fpsLimit = newFps.int32
            setTargetFPS(settings.fpsLimit)
            playSound(stMenuSelect)
            discard saveSettings(settings)
          else:
            playSound(stMenuNav, 0.3)
        except:
          playSound(stMenuNav, 0.3)
      settings.editingFPS = false
  
  # Handle volume slider
  if isMouseButtonDown(Left):
    let sliderX: int32 = 400
    let sliderY: int32 = 255  # volumeY (250) + 5
    let sliderWidth: int32 = 300
    let musicSliderY: int32 = 315  # musicVolumeY (310) + 5
    
    let mousePos = getMousePosition()
    
    # Sound effects volume slider
    if mousePos.y >= sliderY.float32 and mousePos.y <= (sliderY + 20).float32:
      if mousePos.x >= sliderX.float32 and mousePos.x <= (sliderX + sliderWidth).float32:
        let relativeX = mousePos.x - sliderX.float32
        settings.volume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
    
    # Music volume slider
    if mousePos.y >= musicSliderY.float32 and mousePos.y <= (musicSliderY + 20).float32:
      if mousePos.x >= sliderX.float32 and mousePos.x <= (sliderX + sliderWidth).float32:
        let relativeX = mousePos.x - sliderX.float32
        settings.musicVolume = clamp(relativeX / sliderWidth.float32, 0.0, 1.0)
        setMusicVolume(settings.musicVolume)
  
  # Save settings when volume sliders are released
  if isMouseButtonReleased(Left):
    discard saveSettings(settings)
  
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
    
    # Fullscreen checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= fullscreenCheckY.float32 and mousePos.y <= (fullscreenCheckY + checkboxSize).float32:
      settings.fullscreen = not settings.fullscreen
      toggleFullscreen()
      playSound(stMenuNav)
      discard saveSettings(settings)
    
    # Show FPS checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= fpsCheckboxY.float32 and mousePos.y <= (fpsCheckboxY + checkboxSize).float32:
      settings.showFPS = not settings.showFPS
      playSound(stMenuNav)
      discard saveSettings(settings)
    
    # Mouse Support checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= mouseCheckboxY.float32 and mousePos.y <= (mouseCheckboxY + checkboxSize).float32:
      settings.mouseSupport = not settings.mouseSupport
      playSound(stMenuNav)
      discard saveSettings(settings)
    
    # Show Cursor in Menus checkbox (only when mouseSupport is disabled)
    if not settings.mouseSupport:
      if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
         mousePos.y >= cursorCheckboxY.float32 and mousePos.y <= (cursorCheckboxY + checkboxSize).float32:
        settings.showCursorInMenus = not settings.showCursorInMenus
        playSound(stMenuNav)
        discard saveSettings(settings)
    
    # Show Debug Stats checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= debugCheckboxY.float32 and mousePos.y <= (debugCheckboxY + checkboxSize).float32:
      settings.showDebugStats = not settings.showDebugStats
      playSound(stMenuNav)
      discard saveSettings(settings)
    
    # Show Hints checkbox
    if mousePos.x >= checkboxX.float32 and mousePos.x <= (checkboxX + checkboxSize).float32 and
       mousePos.y >= hintsCheckboxY.float32 and mousePos.y <= (hintsCheckboxY + checkboxSize).float32:
      settings.showHints = not settings.showHints
      playSound(stMenuNav)
      discard saveSettings(settings)

proc applySettings*(settings: Settings) =
  setTargetFPS(settings.fpsLimit)
