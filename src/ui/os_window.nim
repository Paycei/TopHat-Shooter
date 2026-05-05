## OS Window Framework
## Base system for all OS-style windows (Settings, Stats, Help)

import raylib, math, ../render_context

type
  WindowAnimation* = enum
    waNone,         # No animation
    waSlideIn,      # Sliding in from off-screen
    waSlideOut,     # Sliding out off-screen
    waMinimizing,   # Animating to minimized state
    waRestoring     # Animating from minimized to full
  
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
    zOrder*: int  # Z-order for window stacking (higher = on top)
    handledClickThisFrame*: bool  # TRUE if this window handled a click this frame
    
    # Resizing
    resizable*: bool  # Whether this window can be resized
    resizing*: bool
    resizeEdge*: int  # 0=none, 1=right, 2=bottom, 3=corner
    
    # Panel-like animations
    animation*: WindowAnimation
    animationTimer*: float32
    animationDuration*: float32
    targetX*, targetY*: int
    startX*, startY*: int
    savedWidth*, savedHeight*: int  # For minimize/restore

const
  TITLE_BAR_HEIGHT* = 30
  WINDOW_BORDER* = 2
  WINDOW_PADDING* = 10
  MIN_WINDOW_WIDTH* = 400
  MIN_WINDOW_HEIGHT* = 300

proc newOSWindow*(title: string, x, y, width, height: int,
                 iconColor: Color, windowType: OSWindowType, resizable: bool = true): OSWindow =
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
    resizable: resizable,
    resizing: false,
    handledClickThisFrame: false,
    time: 0,
    zOrder: 0,
    animation: waNone,
    animationTimer: 0.0,
    animationDuration: 0.3,
    targetX: x,
    targetY: y,
    startX: x,
    startY: y,
    savedWidth: width,
    savedHeight: height
  )

proc startSlideInAnimation*(window: OSWindow, screenWidth, screenHeight: int) =
  ## Start slide-in animation from bottom
  window.animation = waSlideIn
  window.animationTimer = 0.0
  window.startY = screenHeight
  window.targetY = window.y
  window.y = window.startY

proc startSlideOutAnimation*(window: OSWindow, screenHeight: int) =
  ## Start slide-out animation to bottom
  window.animation = waSlideOut
  window.animationTimer = 0.0
  window.startY = window.y
  window.targetY = screenHeight

proc startMinimizeAnimation*(window: OSWindow) =
  ## Instantly minimize - no animation
  window.minimized = true
  window.animation = waNone
  window.savedWidth = window.width
  window.savedHeight = window.height

proc startRestoreAnimation*(window: OSWindow) =
  ## Instantly restore - no animation
  window.minimized = false
  window.animation = waNone

proc bringWindowToFront*(window: OSWindow, allWindows: openArray[OSWindow]) =
  ## Bring this window to the front of all other windows
  ## Updates z-order so this window is drawn on top
  if window.isNil or not window.visible:
    return
  
  # Find the highest z-order among all windows
  var maxZOrder = 0
  for w in allWindows:
    if not w.isNil and w.visible and w.zOrder > maxZOrder:
      maxZOrder = w.zOrder
  
  # Always bring this window to front by setting it higher than the max
  # This ensures even newly opened windows (with zOrder=0) come to front
  if window.zOrder <= maxZOrder:
    window.zOrder = maxZOrder + 1
  
  # Set focus
  window.focused = true
  
  # Unfocus all other windows
  for w in allWindows:
    if not w.isNil and w != window:
      w.focused = false

proc updateOSWindow*(window: OSWindow, dt: float32) =
  window.time += dt

proc isPointInTitleBar*(window: OSWindow, mouseX, mouseY: float32): bool =
  if not window.visible:
    return false
  
  # If minimized, check against full-width title bar
  if window.minimized:
    result = mouseX >= window.x.float32 and
             mouseX <= (window.x + window.savedWidth).float32 and
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

proc isWindowTopmostAtPoint*(window: OSWindow, mouseX, mouseY: float32, allWindows: openArray[OSWindow]): bool =
  ## Check if this window is the topmost window at the given point
  if not window.visible:
    return false
  
  # Check if point is in this window's clickable area
  # For minimized windows, only the title bar counts
  # For normal windows, the entire window counts
  let pointInThisWindow = if window.minimized:
    isPointInTitleBar(window, mouseX, mouseY)
  else:
    isPointInWindow(window, mouseX, mouseY)
  
  if not pointInThisWindow:
    return false
  
  # Check if any other window is on top at this point
  # Minimized windows title bars should also block clicks to windows behind them
  for otherWindow in allWindows:
    if otherWindow != window and not otherWindow.isNil and otherWindow.visible:
      if otherWindow.zOrder > window.zOrder:
        # Check if the other window covers this point
        # For minimized windows, only the title bar counts
        # For normal windows, the entire window counts
        let otherWindowCoversPoint = if otherWindow.minimized:
          isPointInTitleBar(otherWindow, mouseX, mouseY)
        else:
          isPointInWindow(otherWindow, mouseX, mouseY)
        
        if otherWindowCoversPoint:
          return false
  
  return true

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
  
  # If minimized, check for restore button (in full-width title bar)
  if window.minimized:
    let buttonX = window.x + window.savedWidth - 25
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
  if not window.visible or window.minimized or not window.resizable:
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

proc handleOSWindowInput*(window: OSWindow, screenWidth, screenHeight: int, allWindows: openArray[OSWindow]): bool =
  ## Returns true if window should close
  if not window.visible:
    return false
  
  # Check ESC key to close window when focused
  if window.focused and isKeyPressed(KeyboardKey.Escape):
    return true
  
  let mousePos = getVirtualMousePosition()
  
  # Handle dragging
  if window.dragging:
    if isMouseButtonDown(Left):
      window.x = int(mousePos.x) - window.dragOffsetX
      window.y = int(mousePos.y) - window.dragOffsetY
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
        window.width = max(MIN_WINDOW_WIDTH, int(mousePos.x) - window.x)
      of 2:  # Bottom edge
        window.height = max(MIN_WINDOW_HEIGHT, int(mousePos.y) - window.y)
      of 3:  # Corner
        window.width = max(MIN_WINDOW_WIDTH, int(mousePos.x) - window.x)
        window.height = max(MIN_WINDOW_HEIGHT, int(mousePos.y) - window.y)
      else:
        discard
    else:
      window.resizing = false
      window.resizeEdge = 0
    return false
  
  if isMouseButtonPressed(Left):
    let clickOnThisWindowArea = if window.minimized:
      isPointInTitleBar(window, mousePos.x, mousePos.y)
    else:
      isPointInWindow(window, mousePos.x, mousePos.y)
    
    if not clickOnThisWindowArea:
      return false  # Click is not on this window at all
    
    # Step 2: Find which window should handle this click (highest z-order at this point)
    var windowThatShouldHandle: OSWindow = nil
    var highestZ = -1
    
    for w in allWindows:
      if w.isNil or not w.visible:
        continue
      
      # Check if this window covers the click point
      let windowCoversClick = if w.minimized:
        isPointInTitleBar(w, mousePos.x, mousePos.y)
      else:
        isPointInWindow(w, mousePos.x, mousePos.y)
      
      if windowCoversClick and w.zOrder > highestZ:
        highestZ = w.zOrder
        windowThatShouldHandle = w
    
    # Step 3: Only handle if WE are the topmost window at this click
    if windowThatShouldHandle != window:
      return false  # Another window should handle this
    
    # WE handled this click - bring window to front immediately
    window.handledClickThisFrame = true
    
    # Bring to front if not already focused
    if not window.focused:
      bringWindowToFront(window, allWindows)
    
    # Handle close button
    if isPointInCloseButton(window, mousePos.x, mousePos.y):
      return true
    
    # Handle minimize/restore button
    if isPointInMinimizeButton(window, mousePos.x, mousePos.y):
      if window.minimized:
        startRestoreAnimation(window)
      else:
        startMinimizeAnimation(window)
      window.dragging = false
      window.resizing = false
      window.resizeEdge = 0
      return false
    
    # Handle resize edges
    let edge = getResizeEdge(window, mousePos.x, mousePos.y)
    if edge > 0:
      window.resizing = true
      window.resizeEdge = edge
      return false
    
    # Handle title bar dragging
    if isPointInTitleBar(window, mousePos.x, mousePos.y):
      window.dragging = true
      window.dragOffsetX = int(mousePos.x) - window.x
      window.dragOffsetY = int(mousePos.y) - window.y
      return false
  
  return false

proc drawWindowChrome*(window: OSWindow) =
  if not window.visible:
    return
  
  # If minimized, only draw full-width title bar (handled here)
  if window.minimized:
    let miniHeight = TITLE_BAR_HEIGHT
    
    # Draw minimized window as full-width title bar
    drawRectangle(window.x.int32, window.y.int32,
                 window.savedWidth.int32, miniHeight.int32,
                 Color(r: 40, g: 40, b: 50, a: 240))
    
    let borderColor = if window.focused:
      Color(r: 0, g: 200, b: 255, a: 255)
    else:
      Color(r: 80, g: 80, b: 100, a: 255)
    
    drawRectangleLines(Rectangle(x: window.x.float32, y: window.y.float32,
                                  width: window.savedWidth.float32, height: miniHeight.float32),
                      WINDOW_BORDER, borderColor)
    
    # Icon
    let iconSize = 16
    let iconX = window.x + 8
    let iconY = window.y + 7
    drawRectangle(iconX.int32, iconY.int32, iconSize.int32, iconSize.int32, window.iconColor)
    
    # Title text
    drawText(window.title, (window.x + 32).int32, (window.y + 6).int32, 18,
            Color(r: 0, g: 200, b: 255, a: 255))
    
    # Restore button
    let buttonSize = 20
    let buttonY = window.y + 5
    let restoreX = window.x + window.savedWidth - 25
    
    let mousePos = getVirtualMousePosition()
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
  
  # Draw full window (not minimized)
  # Enhanced shadow
  drawRectangle((window.x + 3).int32, (window.y + 3).int32,
               window.width.int32, window.height.int32,
               Color(r: 0, g: 0, b: 0, a: 100))
  
  # Panel glow effect when focused
  if window.focused:
    let glowPulse = sin(window.time * 3.0) * 0.3 + 0.7
    let glowSize = 6
    for i in 1..glowSize:
      let glowAlpha = uint8((30.0 / i.float32) * glowPulse)
      drawRectangleLines(Rectangle(
        x: (window.x - i).float32,
        y: (window.y - i).float32,
        width: (window.width + i * 2).float32,
        height: (window.height + i * 2).float32
      ), 1, Color(r: 0, g: 200, b: 255, a: glowAlpha))
  
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
  let mousePos = getVirtualMousePosition()
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
  
  let mousePos = getVirtualMousePosition()
  let edge = getResizeEdge(window, mousePos.x, mousePos.y)
  
  if window.resizable and (edge > 0 or window.resizing):
    # Draw resize grip in bottom-right corner
    let gripX = window.x + window.width - 12
    let gripY = window.y + window.height - 12
    
    for i in 0..<3:
      let offset = i * 4
      drawLine(Vector2(x: (gripX + offset).float32, y: (gripY + 8).float32),
              Vector2(x: (gripX + 8).float32, y: (gripY + offset).float32),
              2, Color(r: 100, g: 100, b: 120, a: 255))
