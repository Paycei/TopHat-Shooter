## OS-Themed Splash Screen Module
## Displays a boot-like splash screen when the game starts

import raylib, strutils, math, ../localization

type
  BootPhase* = enum
    bpBIOS       # Initial BIOS check
    bpLoader     # Bootloader
    bpKernel     # Kernel loading
    bpServices   # Starting services
    bpComplete   # Boot complete

  SplashScreen* = ref object
    phase*: BootPhase
    timer*: float32
    bootMessages*: seq[string]
    currentMessage*: int
    messageTimer*: float32
    progress*: float32
    complete*: bool
    glitchTimer*: float32
    scanlineOffset*: float32

proc newSplashScreen*(): SplashScreen =
  result = SplashScreen(
    phase: bpBIOS,
    timer: 0,
    bootMessages: @[
      "BIOS v5.1.0 - TopHat Systems",
      "CPU: ElementalCore i9-9900K @ 3.60GHz",
      "Memory: 16384 MB OK",
      "Detecting hardware...",
      "",
      "Loading bootloader...",
      "TSOB version 2.04",
      "",
      "Loading kernel: shooteros-5",
      "Initializing game engine...",
      "Starting graphics subsystem...",
      "Loading audio drivers...",
      "Mounting file systems...",
      "",
      "Starting game services:",
      "[ OK ] Player Management Service",
      "[ OK ] Enemy Spawner Daemon",
      "[ OK ] Physics Engine",
      "[ OK ] Particle System",
      "[ OK ] Power-Up Manager",
      "[ OK ] Statistics Tracker",
      "[ OK ] Discord Integration",
      "[ OK ] Customization System",
      "",
      "TopHat-ShooterOS [v5.1 Edition]",
      "Ready to play.",
      ""
    ],
    currentMessage: 0,
    messageTimer: 0,
    progress: 0,
    complete: false,
    glitchTimer: 0,
    scanlineOffset: 0
  )

proc updateSplashScreen*(splash: SplashScreen, dt: float32) =
  if splash.complete:
    return
  
  splash.timer += dt
  splash.messageTimer += dt
  splash.glitchTimer += dt
  splash.scanlineOffset += dt * 120.0
  
  # Progress through boot messages
  if splash.messageTimer > 0.08:  # Fast scrolling terminal
    splash.messageTimer = 0
    if splash.currentMessage < splash.bootMessages.len:
      splash.currentMessage += 1
      splash.progress = splash.currentMessage.float32 / splash.bootMessages.len.float32
  
  # Mark complete when all messages shown + delay
  if splash.currentMessage >= splash.bootMessages.len and splash.timer > 3.5:
    splash.complete = true

proc drawSplashScreen*(splash: SplashScreen, screenWidth, screenHeight: int) =
  # Black background with subtle grid
  clearBackground(Color(r: 5, g: 5, b: 8, a: 255))
  
  # Draw scanlines for CRT effect
  let scanlineCount = screenHeight div 4
  for i in 0..<scanlineCount:
    let y = ((i.float32 * 4 + splash.scanlineOffset) mod screenHeight.float32).int32
    drawRectangle(0, y, screenWidth.int32, 2, 
                 Color(r: 0, g: 20, b: 30, a: 20))
  
  # Terminal window
  let termX = 50
  let termY = 50
  let termW = screenWidth - 100
  let termH = screenHeight - 100
  
  # Terminal border with glow
  drawRectangle(termX.int32, termY.int32, termW.int32, termH.int32, 
               Color(r: 0, g: 0, b: 0, a: 200))
  drawRectangleLines(Rectangle(x: termX.float32, y: termY.float32, 
                                width: termW.float32, height: termH.float32), 2,
                    Color(r: 0, g: 200, b: 200, a: 255))
  
  # Terminal header bar
  drawRectangle(termX.int32, termY.int32, termW.int32, 30, 
               Color(r: 0, g: 40, b: 40, a: 255))
  drawText("root@tophat-shooteros:~$", (termX + 10).int32, (termY + 5).int32, 20, 
          Color(r: 0, g: 255, b: 255, a: 255))
  
  # Draw boot messages (terminal style)
  var yPos = termY + 45
  let messageStart = max(0, splash.currentMessage - 25)  # Show last 25 lines
  
  for i in messageStart..<splash.currentMessage:
    if i < splash.bootMessages.len:
      let msg = splash.bootMessages[i]
      
      # Color coding for different message types
      var color = Color(r: 0, g: 220, b: 220, a: 255)  # Cyan default
      if msg.contains("[ OK ]"):
        color = Color(r: 50, g: 255, b: 50, a: 255)  # Green
      elif msg.contains("BIOS") or msg.contains("GRUB"):
        color = Color(r: 255, g: 200, b: 50, a: 255)  # Yellow
      elif msg.contains("TopHat-ShooterOS"):
        color = Color(r: 255, g: 100, b: 255, a: 255)  # Magenta
      elif msg.len == 0:
        yPos += 8
        continue
      
      drawText(msg, (termX + 15).int32, yPos.int32, 16, color)
      yPos += 20
  
  # Cursor blink
  if splash.currentMessage < splash.bootMessages.len:
    let cursorBlink = (splash.timer * 2.0).int mod 2
    if cursorBlink == 0:
      drawRectangle((termX + 15).int32, yPos.int32, 10, 16, 
                   Color(r: 0, g: 255, b: 255, a: 255))
  
  # Progress bar at bottom
  let barX = termX + 20
  let barY = termY + termH - 50
  let barW = termW - 40
  let barH = 20
  
  # Progress bar background
  drawRectangle(barX.int32, barY.int32, barW.int32, barH.int32, 
               Color(r: 20, g: 20, b: 30, a: 255))
  
  # Progress bar fill with gradient
  let fillW = (barW.float32 * splash.progress).int32
  for i in 0..<fillW:
    let ratio = i.float32 / barW.float32
    let r = uint8(50 + ratio * 150)
    let g = uint8(200 - ratio * 100)
    drawRectangle(barX.int32 + i, barY.int32, 1, barH.int32,
                 Color(r: r, g: g, b: 255, a: 255))
  
  # Progress percentage
  let progressText = $((splash.progress * 100).int) & "%"
  let textW = measureText(progressText, 16)
  drawText(progressText, 
          (barX + barW div 2 - textW div 2).int32, 
          (barY + 2).int32, 16, White)
  
  # Glitch effect occasionally
  if splash.glitchTimer > 0.5 and (splash.timer * 10).int mod 7 == 0:
    let glitchY = ((splash.timer * 100).int mod (screenHeight - 100) + 50).int32
    let glitchH = 30.int32
    drawRectangle(0, glitchY, screenWidth.int32, glitchH, 
                 Color(r: 0, g: 255, b: 255, a: 30))
    splash.glitchTimer = 0
  
  # "Press almost any key" when complete
  if splash.timer > 3.0:
    let pulse = (sin(splash.timer * 4.0) * 0.5 + 0.5)
    let alpha = uint8(150 + pulse * 105)
    drawText(t(tkSystemPressAnyKey), 
            (screenWidth div 2 - 180).int32, 
            (screenHeight - 30).int32, 20, 
            Color(r: 255, g: 255, b: 100, a: alpha))
