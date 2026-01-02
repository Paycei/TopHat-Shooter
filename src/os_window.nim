## OS Window Framework
## Base system for all OS-style windows (Settings, Stats, Help)

import raylib

type
  OSWindowType* = enum
    owtSettings
    owtStatistics
    owtHelp
  
  OSWindow* = ref object
    x*, y*: int
    width*, height*: int
    title*: string
    iconColor*: Color
    windowType*: OSWindowType
    visible*: bool
    minimized*: bool
    focused*: bool
    dragging*: bool
    dragOffsetX*, dragOffsetY*: int
    time*: float32
    
    # Resizing
    resizing*: bool
    resizeEdge*: int  # 0=none, 1=right, 2=bottom, 3=corner

const
  TITLE_BAR_HEIGHT* = 30
  WINDOW_BORDER* = 2
  WINDOW_PADDING* = 10
  MIN_WINDOW_WIDTH* = 400
  MIN_WINDOW_HEIGHT* = 300

proc newOSWindow*(title: string, x, y, width, height: int, 
                 iconColor: Color, windowType: OSWindowType): OSWindow =
  result = OSWindow(
    x: x,
    y: y,
    width: width,
    height: height,
    title: title,
    iconColor: iconColor,
    windowType: windowType,
    visible: false,
    minimized: false,
    focused: true,
    dragging: false,
    resizing: false,
    time: 0
  )

proc updateOSWindow*(window: OSWindow, dt: float32) =
  window.time += dt

proc isPointInTitleBar*(window: OSWindow, mouseX, mouseY: float32): bool =
  if not window.visible:
    return false
  
  # If minimized, check against mini title bar
  if window.minimized:
    let miniWidth = 200
    result = mouseX >= window.x.float32 and 
             mouseX <= (window.x + miniWidth).float32 and
             mouseY >= window.y.float32 and 
             mouseY <= (window.y + TITLE_BAR_HEIGHT).float32
  else:
    result = mouseX >= window.x.float32 and 
             mouseX <= (window.x + window.width).float32 and
             mouseY >= window.y.float32 and 
             mouseY <= (window.y + TITLE_BAR_HEIGHT).float32

proc isPointInWindow*(window: OSWindow, mouseX, mouseY: float32): bool =
  if not window.visible or window.minimized:
    return false
  
  result = mouseX >= window.x.float32 and 
           mouseX <= (window.x + window.width).float32 and
           mouseY >= window.y.float32 and 
           mouseY <= (window.y + window.height).float32

proc isPointInCloseButton*(window: OSWindow, mouseX, mouseY: float32): bool =
  if not window.visible or window.minimized:
    return false
  
  let buttonX = window.x + window.width - 25
  let buttonY = window.y + 5
  let buttonSize = 20
  
  result = mouseX >= buttonX.float32 and 
           mouseX <= (buttonX + buttonSize).float32 and
           mouseY >= buttonY.float32 and 
           mouseY <= (buttonY + buttonSize).float32

proc isPointInMinimizeButton*(window: OSWindow, mouseX, mouseY: float32): bool =
  if not window.visible:
    return false
  
  # If minimized, check for restore button (in mini title bar)
  if window.minimized:
    let miniWidth = 200
    let buttonX = window.x + miniWidth - 25
    let buttonY = window.y + 5
    let buttonSize = 20
    
    result = mouseX >= buttonX.float32 and 
             mouseX <= (buttonX + buttonSize).float32 and
             mouseY >= buttonY.float32 and 
             mouseY <= (buttonY + buttonSize).float32
  else:
    let buttonX = window.x + window.width - 50
    let buttonY = window.y + 5
    let buttonSize = 20
    
    result = mouseX >= buttonX.float32 and 
             mouseX <= (buttonX + buttonSize).float32 and
             mouseY >= buttonY.float32 and 
             mouseY <= (buttonY + buttonSize).float32

proc getResizeEdge*(window: OSWindow, mouseX, mouseY: float32): int =
  ## Returns which edge is being hovered for resizing
  ## 0=none, 1=right, 2=bottom, 3=corner
  if not window.visible or window.minimized:
    return 0
  
  let edgeThreshold = 8
  let rightEdge = window.x + window.width
  let bottomEdge = window.y + window.height
  
  let onRightEdge = abs(mouseX - rightEdge.float32) < edgeThreshold.float32
  let onBottomEdge = abs(mouseY - bottomEdge.float32) < edgeThreshold.float32
  
  if onRightEdge and onBottomEdge:
    return 3  # Corner
  elif onRightEdge:
    return 1  # Right edge
  elif onBottomEdge:
    return 2  # Bottom edge
  else:
    return 0  # No edge

proc handleOSWindowInput*(window: OSWindow, screenWidth, screenHeight: int): bool =
  ## Returns true if window should close
  if not window.visible:
    return false
  
  let mousePos = getMousePosition()
  
  # Handle dragging
  if window.dragging:
    if isMouseButtonDown(Left):
      window.x = int(mousePos.x) - window.dragOffsetX
      window.y = int(mousePos.y) - window.dragOffsetY
      
      # Keep window in bounds
      window.x = max(0, min(window.x, screenWidth - window.width))
      window.y = max(0, min(window.y, screenHeight - 100))
    else:
      window.dragging = false
    return false
  
  # Handle resizing
  if window.resizing:
    if isMouseButtonDown(Left):
      case window.resizeEdge
      of 1:  # Right edge
        let newWidth = int(mousePos.x) - window.x
        window.width = max(MIN_WINDOW_WIDTH, newWidth)
      of 2:  # Bottom edge
        let newHeight = int(mousePos.y) - window.y
        window.height = max(MIN_WINDOW_HEIGHT, newHeight)
      of 3:  # Corner
        let newWidth = int(mousePos.x) - window.x
        let newHeight = int(mousePos.y) - window.y
        window.width = max(MIN_WINDOW_WIDTH, newWidth)
        window.height = max(MIN_WINDOW_HEIGHT, newHeight)
      else:
        discard
    else:
      window.resizing = false
      window.resizeEdge = 0
    return false
  
  # Check for new interactions
  if isMouseButtonPressed(Left):
    # Check close button
    if isPointInCloseButton(window, mousePos.x, mousePos.y):
      return true
    
    # Check minimize button
    if isPointInMinimizeButton(window, mousePos.x, mousePos.y):
      # Only toggle minimize if not currently resizing or dragging
      if not window.resizing and not window.dragging:
        window.minimized = not window.minimized
        # Reset any drag or resize state when minimizing/unminimizing
        window.dragging = false
        window.resizing = false
        window.resizeEdge = 0
      return false
    
    # Check resize edges
    let edge = getResizeEdge(window, mousePos.x, mousePos.y)
    if edge > 0:
      window.resizing = true
      window.resizeEdge = edge
      return false
    
    # Check title bar for dragging
    if isPointInTitleBar(window, mousePos.x, mousePos.y):
      window.dragging = true
      window.dragOffsetX = int(mousePos.x) - window.x
      window.dragOffsetY = int(mousePos.y) - window.y
      return false
  
  return false

proc drawWindowChrome*(window: OSWindow) =
  if not window.visible:
    return
  
  # If minimized, only draw a small title bar representation
  if window.minimized:
    let miniWidth = 200
    let miniHeight = TITLE_BAR_HEIGHT
    
    # Draw minimized window as small title bar at original position
    drawRectangle(window.x.int32, window.y.int32, 
                 miniWidth.int32, miniHeight.int32,
                 Color(r: 40, g: 40, b: 50, a: 240))
    
    let borderColor = if window.focused:
      Color(r: 0, g: 200, b: 255, a: 255)
    else:
      Color(r: 80, g: 80, b: 100, a: 255)
    
    drawRectangleLines(Rectangle(x: window.x.float32, y: window.y.float32,
                                  width: miniWidth.float32, height: miniHeight.float32),
                      WINDOW_BORDER, borderColor)
    
    # Icon
    let iconSize = 16
    let iconX = window.x + 8
    let iconY = window.y + 7
    drawRectangle(iconX.int32, iconY.int32, iconSize.int32, iconSize.int32, window.iconColor)
    
    # Title text (truncated)
    drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18,
            Color(r: 0, g: 200, b: 255, a: 255))
    
    # Restore button (using maximize icon)
    let buttonSize = 20
    let buttonY = window.y + 5
    let restoreX = window.x + miniWidth - 25
    
    let mousePos = getMousePosition()
    let hoverRestore = mousePos.x >= restoreX.float32 and 
                       mousePos.x <= (restoreX + buttonSize).float32 and
                       mousePos.y >= buttonY.float32 and 
                       mousePos.y <= (buttonY + buttonSize).float32
    
    drawRectangle(restoreX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
                 if hoverRestore: Color(r: 100, g: 200, b: 100, a: 255)
                 else: Color(r: 60, g: 60, b: 70, a: 255))
    drawRectangle((restoreX + 5).int32, (buttonY + 5).int32, 10, 10,
                 Color(r: 200, g: 200, b: 200, a: 255))
    drawRectangleLines(Rectangle(x: (restoreX + 5).float32, y: (buttonY + 5).float32,
                                  width: 10.0, height: 10.0),
                      1, White)
    
    return
  
  # Shadow
  drawRectangle((window.x + 3).int32, (window.y + 3).int32, 
               window.width.int32, window.height.int32,
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Main window background
  drawRectangle(window.x.int32, window.y.int32, 
               window.width.int32, window.height.int32,
               Color(r: 20, g: 20, b: 30, a: 240))
  
  # Border with glow if focused
  let borderColor = if window.focused:
    Color(r: 0, g: 200, b: 255, a: 255)
  else:
    Color(r: 80, g: 80, b: 100, a: 255)
  
  drawRectangleLines(Rectangle(x: window.x.float32, y: window.y.float32,
                                width: window.width.float32, height: window.height.float32),
                    WINDOW_BORDER, borderColor)
  
  # Title bar
  drawRectangle(window.x.int32, window.y.int32, 
               window.width.int32, TITLE_BAR_HEIGHT.int32,
               Color(r: 40, g: 40, b: 50, a: 255))
  
  # Icon
  let iconSize = 16
  let iconX = window.x + 8
  let iconY = window.y + 7
  drawRectangle(iconX.int32, iconY.int32, iconSize.int32, iconSize.int32, window.iconColor)
  
  # Title text
  drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18,
          Color(r: 0, g: 200, b: 255, a: 255))
  
  # Window buttons
  let buttonSize = 20
  let buttonY = window.y + 5
  
  # Close button
  let closeX = window.x + window.width - 25
  let mousePos = getMousePosition()
  let hoverClose = isPointInCloseButton(window, mousePos.x, mousePos.y)
  
  drawRectangle(closeX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
               if hoverClose: Color(r: 255, g: 80, b: 80, a: 255)
               else: Color(r: 60, g: 60, b: 70, a: 255))
  drawText("X", (closeX + 6).int32, (buttonY + 2).int32, 16, White)
  
  # Minimize button
  let minX = window.x + window.width - 50
  let hoverMin = isPointInMinimizeButton(window, mousePos.x, mousePos.y)
  
  drawRectangle(minX.int32, buttonY.int32, buttonSize.int32, buttonSize.int32,
               if hoverMin: Color(r: 100, g: 150, b: 200, a: 255)
               else: Color(r: 60, g: 60, b: 70, a: 255))
  drawRectangle((minX + 5).int32, (buttonY + 14).int32, 10, 2, White)

proc drawResizeIndicator*(window: OSWindow) =
  ## Draw resize indicators on edges
  if not window.visible or window.minimized:
    return
  
  let mousePos = getMousePosition()
  let edge = getResizeEdge(window, mousePos.x, mousePos.y)
  
  if edge > 0 or window.resizing:
    # Draw resize grip in bottom-right corner
    let gripX = window.x + window.width - 12
    let gripY = window.y + window.height - 12
    
    for i in 0..<3:
      let offset = i * 4
      drawLine(Vector2(x: (gripX + offset).float32, y: (gripY + 8).float32),
              Vector2(x: (gripX + 8).float32, y: (gripY + offset).float32),
              2, Color(r: 100, g: 100, b: 120, a: 255))
