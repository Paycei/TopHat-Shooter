import raylib, strutils, sound

type
  Settings* = ref object
    fpsLimit*: int32
    volume*: float32
    musicVolume*: float32
    inputBuffer*: string
    editingFPS*: bool

var globalSettings*: Settings

proc initSettings*(): Settings =
  result = Settings(
    fpsLimit: 60,
    volume: 0.5,
    musicVolume: 0.5,
    inputBuffer: "60",
    editingFPS: false
  )
  globalSettings = result

proc drawSettings*(settings: Settings, screenWidth, screenHeight: int32) =
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Title
  drawText("SETTINGS", screenWidth div 2 - 100, 60, 40, Yellow)
  
  # FPS Limit Setting
  let fpsY: int32 = 180
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
  
  # Volume Setting
  let volumeY: int32 = 280
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
  let musicVolumeY: int32 = 350
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
  
  # Back instruction
  drawText("Press ESC to return to menu", screenWidth div 2 - 180, 
          screenHeight - 80, 20, LightGray)
  
  # Draw custom cursor (same as menu cursor)
  let mousePos = getMousePosition()
  
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
  let boxY: int32 = 175
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
          if newFps >= 30 and newFps <= 300:
            settings.fpsLimit = newFps.int32
            setTargetFPS(settings.fpsLimit)
            playSound(stMenuSelect)
          else:
            playSound(stMenuNav, 0.3)  # Error sound
        except:
          playSound(stMenuNav, 0.3)  # Error sound
      settings.editingFPS = false
  
  # Handle volume slider
  if isMouseButtonDown(Left):
    let sliderX: int32 = 400
    let sliderY: int32 = 285
    let sliderWidth: int32 = 300
    let musicSliderY: int32 = 355
    
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

proc applySettings*(settings: Settings) =
  setTargetFPS(settings.fpsLimit)
