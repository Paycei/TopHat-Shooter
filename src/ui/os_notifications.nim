## OS-Style Notification System
## Provides toast notifications, system alerts, and command feedback

import raylib, ../types, math, ../localization

type
  OSToastType* = enum
    ottInfo,        # Blue - informational messages
    ottSuccess,     # Green - positive events  
    ottWarning,     # Yellow - warnings
    ottError,       # Red - errors
    ottCritical,    # Dark red - critical system issues
    ottAchievement, # Gold - achievements/milestones
    ottCommand      # Cyan - command execution feedback
    
  OSToast* = object
    message*: string
    toastType*: OSToastType
    lifetime*: float32
    maxLifetime*: float32
    yOffset*: float32  # For stacking multiple toasts
    
  OSToastManager* = object
    toasts*: seq[OSToast]
    nextYOffset*: float32

const
  TOAST_WIDTH = 400
  TOAST_HEIGHT = 50
  TOAST_MARGIN = 10
  TOAST_DURATION = 3.5  # seconds

proc newOSToastManager*(): OSToastManager =
  result = OSToastManager(
    toasts: @[],
    nextYOffset: 0
  )

proc addToast*(manager: var OSToastManager, message: string, toastType: OSToastType = ottInfo, duration: float32 = TOAST_DURATION) =
  ## Add a new toast notification
  let toast = OSToast(
    message: message,
    toastType: toastType,
    lifetime: 0.0,
    maxLifetime: duration,
    yOffset: manager.nextYOffset
  )
  manager.toasts.add(toast)
  manager.nextYOffset += TOAST_HEIGHT + TOAST_MARGIN

proc updateOSToasts*(manager: var OSToastManager, dt: float32) =
  ## Update all active toasts
  var i = 0
  var removedCount = 0
  
  while i < manager.toasts.len:
    manager.toasts[i].lifetime += dt
    
    # Remove expired toasts
    if manager.toasts[i].lifetime >= manager.toasts[i].maxLifetime:
      manager.toasts.delete(i)
      removedCount += 1
    else:
      i += 1
  
  # Recalculate yOffsets after removals
  if removedCount > 0:
    manager.nextYOffset = 0
    for i in 0..<manager.toasts.len:
      manager.toasts[i].yOffset = manager.nextYOffset
      manager.nextYOffset += TOAST_HEIGHT + TOAST_MARGIN

proc drawOSToasts*(manager: OSToastManager, screenWidth, screenHeight: int32) =
  ## Draw all active toast notifications (bottom-right corner)
  let baseX = screenWidth - TOAST_WIDTH - 20
  let baseY = screenHeight - 80  # Start from bottom
  
  for i in countdown(manager.toasts.high, 0):
    let toast = manager.toasts[i]
    
    # Calculate fade in/out
    let fadeInTime = 0.3
    let fadeOutTime = 0.5
    let alpha = if toast.lifetime < fadeInTime:
      (toast.lifetime / fadeInTime)
    elif toast.lifetime > toast.maxLifetime - fadeOutTime:
      ((toast.maxLifetime - toast.lifetime) / fadeOutTime)
    else:
      1.0
    
    let yPos = baseY - toast.yOffset.int32
    
    # Get colors based on type
    let (bgColor, borderColor, iconText, textColor) = case toast.toastType
      of ottInfo:
        (Color(r: 20, g: 40, b: 70, a: uint8(200 * alpha)),
         Color(r: 50, g: 150, b: 255, a: uint8(255 * alpha)),
         "[INFO]",
         Color(r: 150, g: 200, b: 255, a: uint8(255 * alpha)))
      of ottSuccess:
        (Color(r: 20, g: 60, b: 20, a: uint8(200 * alpha)),
         Color(r: 50, g: 255, b: 50, a: uint8(255 * alpha)),
         "[OK]",
         Color(r: 150, g: 255, b: 150, a: uint8(255 * alpha)))
      of ottWarning:
        (Color(r: 70, g: 60, b: 20, a: uint8(200 * alpha)),
         Color(r: 255, g: 200, b: 50, a: uint8(255 * alpha)),
         "[WARN]",
         Color(r: 255, g: 220, b: 100, a: uint8(255 * alpha)))
      of ottError:
        (Color(r: 70, g: 20, b: 20, a: uint8(200 * alpha)),
         Color(r: 255, g: 80, b: 80, a: uint8(255 * alpha)),
         "[ERR]",
         Color(r: 255, g: 150, b: 150, a: uint8(255 * alpha)))
      of ottCritical:
        (Color(r: 90, g: 10, b: 10, a: uint8(220 * alpha)),
         Color(r: 255, g: 30, b: 30, a: uint8(255 * alpha)),
         "[CRITICAL]",
         Color(r: 255, g: 100, b: 100, a: uint8(255 * alpha)))
      of ottAchievement:
        (Color(r: 60, g: 50, b: 20, a: uint8(200 * alpha)),
         Color(r: 255, g: 215, b: 0, a: uint8(255 * alpha)),
         "[ACHIEVEMENT]",
         Color(r: 255, g: 230, b: 100, a: uint8(255 * alpha)))
      of ottCommand:
        (Color(r: 15, g: 30, b: 35, a: uint8(200 * alpha)),
         Color(r: 0, g: 255, b: 255, a: uint8(255 * alpha)),
         ">",
         Color(r: 100, g: 255, b: 255, a: uint8(255 * alpha)))
    
    # Background
    drawRectangle(baseX, yPos, TOAST_WIDTH, TOAST_HEIGHT, bgColor)
    
    # Border (2px thick)
    drawRectangleLines(Rectangle(x: baseX.float32, y: yPos.float32,
                                  width: TOAST_WIDTH.float32, height: TOAST_HEIGHT.float32),
                      2, borderColor)
    
    # Icon/prefix
    drawText(iconText, baseX + 10, yPos + 15, 16, borderColor)
    
    # Message
    let messageX = baseX + 100
    let messageWidth = TOAST_WIDTH - 110
    
    # Truncate message if too long
    var displayMessage = toast.message
    let textWidth = measureText(displayMessage, 14)
    if textWidth > messageWidth:
      while measureText(displayMessage & "...", 14) > messageWidth and displayMessage.len > 0:
        displayMessage = displayMessage[0..^2]
      displayMessage &= "..."
    
    drawText(displayMessage, messageX, yPos + 17, 14, textColor)

# Helper procs for common game events
proc notifyWaveStart*(manager: var OSToastManager, wave: int) =
  manager.addToast(t(tkNotifWaveInitiated), ottCommand)

proc notifyWaveComplete*(manager: var OSToastManager, wave: int) =
  manager.addToast(t(tkNotifWaveCleared), ottSuccess)

proc notifyBossSpawn*(manager: var OSToastManager) =
  manager.addToast(t(tkNotifBossDetected), ottCritical, 4.0)

proc notifyBossDefeated*(manager: var OSToastManager) =
  manager.addToast(t(tkNotifBossTerminated), ottAchievement, 4.0)

proc notifyPowerUpCollected*(manager: var OSToastManager, name: string) =
  manager.addToast(t(tkNotifInstalled) & \" \" & name & \".exe\", ottSuccess)

proc notifyDamageTaken*(manager: var OSToastManager, damage: int) =
  manager.addToast(t(tkNotifIntegrityCompromised) & "-" & $damage & " HP", ottError, 2.0)

proc notifyHealthRestored*(manager: var OSToastManager, amount: int) =
  manager.addToast(t(tkNotifIntegrityRestored) & "+" & $amount & " HP", ottSuccess, 2.0)

proc notifyCoinCollected*(manager: var OSToastManager, amount: int) =
  manager.addToast(t(tkNotifResourceAcquired) & "+" & $amount & " credits", ottInfo, 2.0)

proc notifyAbilityActivated*(manager: var OSToastManager, abilityName: string) =
  manager.addToast(t(tkNotifExecute) & abilityName & ".exe", ottCommand, 2.5)

proc notifyAbilityCooldown*(manager: var OSToastManager, abilityName: string, cooldown: float32) =
  manager.addToast(abilityName & " " & t(tkNotifCooldown) & " " & $cooldown.int & "s", ottWarning, 2.0)

proc notifyEnemyKilled*(manager: var OSToastManager, enemyName: string, count: int = 1) =
  if count == 1:
    manager.addToast(t(tkNotifProcessTerminated) & ": " & enemyName, ottInfo, 1.5)
  else:
    manager.addToast(t(tkNotifProcessesTerminated) & ": " & enemyName & " (x" & $count & ")", ottInfo, 2.0)
