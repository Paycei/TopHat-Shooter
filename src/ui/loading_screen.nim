import raylib, math, ../localization, background_fx

type
  LoadingScreen* = ref object
    progress*: float32  # 0.0 to 1.0
    message*: string
    startTime*: float32
    animTime*: float32

proc newLoadingScreen*(): LoadingScreen =
  result = LoadingScreen(
    progress: 0.0,
    message: t(tkLoadingInitializing),
    startTime: 0.0,
    animTime: 0.0
  )

proc update*(screen: LoadingScreen, dt: float32) =
  screen.animTime += dt

proc setProgress*(screen: LoadingScreen, progress: float32, message: string = "") =
  screen.progress = clamp(progress, 0.0, 1.0)
  if message.len > 0:
    screen.message = message

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
  drawSoftGlow(centerX.float32, centerY.float32 - 10.0, 220.0,
               Color(r: 0, g: 170, b: 255, a: 28), 0.9)
  
  # Title
  let titleText = t(tkLoadingTitle)
  let titleSize: int32 = 48
  let titleWidth = measureText(titleText, titleSize)
  drawText(titleText, centerX - titleWidth div 2, centerY - 150, titleSize,
           Color(r: 180, g: 220, b: 255, a: 255))
  
  # Subtitle
  let subtitleText = t(tkLoadingSubtitle)
  let subtitleSize: int32 = 24
  let subtitleWidth = measureText(subtitleText, subtitleSize)
  drawText(subtitleText, centerX - subtitleWidth div 2, centerY - 100, subtitleSize,
           Color(r: 140, g: 180, b: 220, a: 200))
  
  # Progress bar background
  let barWidth: int32 = 500
  let barHeight: int32 = 30
  let barX: int32 = centerX - barWidth div 2
  let barY: int32 = centerY + 20
  
  # Outer border
  drawRectangleLines(barX - 2'i32, barY - 2'i32, barWidth + 4'i32, barHeight + 4'i32,
                     Color(r: 100, g: 150, b: 200, a: 255))
  
  # Background
  drawRectangle(barX, barY, barWidth, barHeight,
                Color(r: 30, g: 30, b: 45, a: 255))
  
  # Progress fill with gradient effect
  let fillWidth = int32(barWidth.float32 * screen.progress)
  if fillWidth > 0:
    # Create a pulsing effect
    let pulse = sin(screen.animTime * 3.0) * 0.15 + 0.85
    let r = uint8(80.0 * pulse)
    let g = uint8(160.0 * pulse)
    let b = uint8(240.0 * pulse)
    
    drawRectangle(barX, barY, fillWidth, barHeight,
                  Color(r: r, g: g, b: b, a: 255))
    
    # Add highlight on top
    drawRectangle(barX, barY, fillWidth, barHeight div 3,
                  Color(r: 120, g: 200, b: 255, a: 100))
  
  # Progress percentage
  let percentText = $(int(screen.progress * 100)) & "%"
  let percentSize: int32 = 20
  let percentWidth = measureText(percentText, percentSize)
  drawText(percentText, centerX - percentWidth div 2, barY + 5, percentSize, White)
  
  # Loading message
  let msgSize: int32 = 18
  let msgWidth = measureText(screen.message, msgSize)
  drawText(screen.message, centerX - msgWidth div 2, barY + 50, msgSize,
           Color(r: 200, g: 200, b: 220, a: 255))
  
  # Animated dots
  let dots = int(screen.animTime * 2.0) mod 4
  var dotStr = ""
  for i in 0..<dots:
    dotStr.add(".")
  drawText(dotStr, centerX + msgWidth div 2 + 5, barY + 50, msgSize,
           Color(r: 200, g: 200, b: 220, a: 255))
  
  # Bottom hint text - animated
  let alpha = uint8((sin(screen.animTime * 2.0) * 0.3 + 0.7) * 255.0)
  let hintText = t(tkLoadingHint)
  let hintSize: int32 = 14
  let hintWidth = measureText(hintText, hintSize)
  drawText(hintText, centerX - hintWidth div 2, screenHeight - 80, hintSize,
           Color(r: 120, g: 150, b: 180, a: alpha))
