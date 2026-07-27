## Save-profile selection screen, shown right after the splash on every launch.
##
## One slot per difficulty (see MaxProfileSlots); each slot is an isolated save
## folder (see save_system.nim).
## Clicking an empty slot opens the difficulty picker and creates the profile;
## clicking an occupied slot selects it; the small delete button under an
## occupied slot needs a second confirming click.
##
## Like the language screen, this renders BEFORE the chosen profile's settings
## (and therefore its language) are loaded, so every label is hard-coded
## bilingual (English / Spanish, plain ASCII).

import raylib, math
import ../save_system, ../types, ../advancement
import ../gamepad_input

type
  ProfileSelectMode* = enum
    psmSlots,       # picking / deleting one of the save slots
    psmDifficulty   # choosing the difficulty for a slot being created

  ProfileSlotInfo* = object
    exists*: bool
    difficulty*: GameDifficulty
    completion*: float32            # unlocked advancements / total, 0..1

  ProfileSelectState* = ref object
    mode*: ProfileSelectMode
    targetSlot*: int                # slot being created while in psmDifficulty
    confirmDeleteSlot*: int         # 0 = none; slot the delete dialog is about
    confirmCooldown*: float32       # seconds until the dialog's DELETE unlocks
    slots*: array[1..MaxProfileSlots, ProfileSlotInfo]

const
  DeleteConfirmCooldown = 2.0'f32  # anti-accident window, like the quit dialog

proc refreshSlots*(state: ProfileSelectState) =
  for slot in 1..MaxProfileSlots:
    state.slots[slot].exists = profileExists(slot)
    if state.slots[slot].exists:
      state.slots[slot].difficulty = loadProfileDifficulty(slot)
      state.slots[slot].completion = loadAdvancementCompletionForSlot(slot)
    else:
      state.slots[slot].difficulty = gdMedium
      state.slots[slot].completion = 0.0

proc newProfileSelectState*(): ProfileSelectState =
  result = ProfileSelectState(mode: psmSlots)
  refreshSlots(result)

# --- Geometry (shared by input handling and drawing) ---

const
  # A four-card row has to fit the narrow (4:3, 1024-wide) virtual screen, so the
  # card/gap sizes are shared by both rows rather than tuned per screen.
  CardW = 220.0'f32
  CardGap = 24.0'f32

proc rowStartX(screenWidth: int32, count: int): float32 =
  ## Left edge of a horizontally centered row of `count` CardW-wide cards.
  let totalW = CardW * count.float32 + CardGap * (count - 1).float32
  (screenWidth.float32 - totalW) / 2.0'f32

proc slotCardRects(screenWidth, screenHeight: int32): array[1..MaxProfileSlots, Rectangle] =
  const cardH = 300.0'f32
  let startX = rowStartX(screenWidth, MaxProfileSlots)
  let y      = screenHeight.float32 / 2.0'f32 - cardH / 2.0'f32 + 30.0'f32
  for i in 1..MaxProfileSlots:
    result[i] = Rectangle(x: startX + (i - 1).float32 * (CardW + CardGap), y: y,
                          width: CardW, height: cardH)

proc deleteButtonRect(card: Rectangle): Rectangle =
  Rectangle(x: card.x + card.width * 0.18'f32,
            y: card.y + card.height - 44.0'f32,
            width: card.width * 0.64'f32, height: 30.0'f32)

proc confirmDialogRects(screenWidth, screenHeight: int32):
    tuple[dialog, noBtn, yesBtn: Rectangle] =
  ## Same footprint as the global quit-confirm dialog in main.nim.
  const
    DW = 460.0'f32
    DH = 210.0'f32
    BW = 170.0'f32
    BH = 42.0'f32
  let dx = (screenWidth.float32 - DW) / 2.0'f32
  let dy = (screenHeight.float32 - DH) / 2.0'f32
  result.dialog = Rectangle(x: dx, y: dy, width: DW, height: DH)
  let btnY = dy + DH - BH - 22.0'f32
  result.noBtn = Rectangle(x: dx + DW / 2.0'f32 - BW - 12.0'f32, y: btnY,
                           width: BW, height: BH)
  result.yesBtn = Rectangle(x: dx + DW / 2.0'f32 + 12.0'f32, y: btnY,
                            width: BW, height: BH)

proc difficultyCardRects(screenWidth, screenHeight: int32): array[GameDifficulty, Rectangle] =
  const cardH = 260.0'f32
  let startX = rowStartX(screenWidth, ord(high(GameDifficulty)) + 1)
  let y      = screenHeight.float32 / 2.0'f32 - cardH / 2.0'f32 + 30.0'f32
  for d in GameDifficulty:
    result[d] = Rectangle(x: startX + ord(d).float32 * (CardW + CardGap), y: y,
                          width: CardW, height: cardH)

# --- Shared label data ---

proc difficultyColor(d: GameDifficulty): Color =
  case d
  of gdEasy:   Color(r: 80, g: 205, b: 120, a: 255)
  of gdMedium: Color(r: 240, g: 190, b: 60, a: 255)
  of gdHard:   Color(r: 235, g: 80, b: 80, a: 255)
  of gdNightmare: Color(r: 190, g: 70, b: 245, a: 255)

proc difficultyLabel(d: GameDifficulty): string =
  # Bilingual where the words differ; "NORMAL"/"NIGHTMARE" read in both.
  case d
  of gdEasy:   "EASY / FACIL"
  of gdMedium: "NORMAL"
  of gdHard:   "HARD / DIFICIL"
  of gdNightmare: "NIGHTMARE"

# --- Input handling ---

proc updateProfileSelect*(state: ProfileSelectState, dt: float32,
                          mousePos: Vector2,
                          screenWidth, screenHeight: int32): int =
  ## Processes one frame of input. Creating/deleting profiles happens in here;
  ## returns the chosen slot (1..MaxProfileSlots) once the player picks a
  ## profile to play on, 0 otherwise.
  result = 0

  case state.mode
  of psmSlots:
    # Delete-confirmation dialog swallows all other input while open. Cancel
    # (button or ESC) is immediate; DELETE stays locked for the anti-accident
    # cooldown, exactly like the global quit-confirm dialog.
    if state.confirmDeleteSlot > 0:
      if state.confirmCooldown > 0:
        state.confirmCooldown -= dt
      let rects = confirmDialogRects(screenWidth, screenHeight)
      if isKeyPressed(Escape):
        state.confirmDeleteSlot = 0
      elif isPointerPressed():
        if checkCollisionPointRec(mousePos, rects.noBtn):
          state.confirmDeleteSlot = 0
        elif checkCollisionPointRec(mousePos, rects.yesBtn) and
             state.confirmCooldown <= 0:
          discard deleteProfile(state.confirmDeleteSlot)
          state.confirmDeleteSlot = 0
          refreshSlots(state)
      return 0

    let cards = slotCardRects(screenWidth, screenHeight)
    # Keyboard: 1/2/3 behaves like clicking the slot card.
    var pickedSlot = 0
    if isKeyPressed(KeyboardKey.One): pickedSlot = 1
    elif isKeyPressed(KeyboardKey.Two): pickedSlot = 2
    elif isKeyPressed(KeyboardKey.Three): pickedSlot = 3
    elif isKeyPressed(KeyboardKey.Four): pickedSlot = 4

    if isPointerPressed():
      for slot in 1..MaxProfileSlots:
        if state.slots[slot].exists and
           checkCollisionPointRec(mousePos, deleteButtonRect(cards[slot])):
          state.confirmDeleteSlot = slot
          state.confirmCooldown = DeleteConfirmCooldown
          return 0
      for slot in 1..MaxProfileSlots:
        if checkCollisionPointRec(mousePos, cards[slot]):
          pickedSlot = slot
          break

    if pickedSlot > 0:
      if state.slots[pickedSlot].exists:
        return pickedSlot
      else:
        state.mode = psmDifficulty
        state.targetSlot = pickedSlot

  of psmDifficulty:
    if isKeyPressed(Escape):
      state.mode = psmSlots
      state.targetSlot = 0
      return 0

    var picked = -1
    if isKeyPressed(KeyboardKey.One): picked = ord(gdEasy)
    elif isKeyPressed(KeyboardKey.Two): picked = ord(gdMedium)
    elif isKeyPressed(KeyboardKey.Three): picked = ord(gdHard)
    elif isKeyPressed(KeyboardKey.Four): picked = ord(gdNightmare)
    if isPointerPressed():
      let cards = difficultyCardRects(screenWidth, screenHeight)
      for d in GameDifficulty:
        if checkCollisionPointRec(mousePos, cards[d]):
          picked = ord(d)
          break

    if picked >= 0:
      let slot = state.targetSlot
      if createProfile(slot, GameDifficulty(picked)):
        refreshSlots(state)
        state.mode = psmSlots
        state.targetSlot = 0
        return slot
      state.mode = psmSlots
      state.targetSlot = 0

# --- Drawing ---

proc drawCenteredText(text: string, cx, y, size: int32, color: Color) =
  let w = measureText(text, size)
  drawText(text, cx - w div 2, y, size, color)

proc drawScreenFrame(screenWidth, screenHeight: int32, title, subtitle: string) =
  clearBackground(Color(r: 12, g: 15, b: 22, a: 255))
  # Faint scanlines to match the OS-desktop aesthetic.
  var ly = 0'i32
  while ly < screenHeight:
    drawRectangle(0, ly, screenWidth, 1, Color(r: 255, g: 255, b: 255, a: 6))
    ly += 3
  let cx = screenWidth div 2
  let titleY = (screenHeight.float32 * 0.5'f32 - 230.0'f32).int32
  drawCenteredText(title, cx, titleY, 38, Color(r: 0, g: 225, b: 255, a: 255))
  drawCenteredText(subtitle, cx, titleY + 44, 24, Color(r: 180, g: 200, b: 220, a: 230))

proc drawCardBase(rect: Rectangle, hovered: bool, time: float32, accent: Color) =
  let pulse = (sin(time * 3.0'f32) * 0.5'f32 + 0.5'f32)
  let bg = if hovered: Color(r: 30, g: 42, b: 60, a: 255)
           else: Color(r: 22, g: 28, b: 40, a: 255)
  let border = if hovered: Color(r: accent.r, b: accent.b, a: 255,
                                 g: uint8(min(255.0'f32, accent.g.float32 * (0.8'f32 + pulse * 0.35'f32))))
               else: Color(r: 70, g: 86, b: 110, a: 255)
  drawRectangle((rect.x + 4).int32, (rect.y + 5).int32, rect.width.int32, rect.height.int32,
                Color(r: 0, g: 0, b: 0, a: 120))  # drop shadow
  drawRectangle(rect.x.int32, rect.y.int32, rect.width.int32, rect.height.int32, bg)
  drawRectangleLines(rect, if hovered: 3.0'f32 else: 1.5'f32, border)

proc drawTophatBadge(cx, cy: float32, scale: float32, tint: Color) =
  ## Minimal tophat glyph so occupied slots read as "a player lives here".
  let brimW = 46.0'f32 * scale
  let crownW = 30.0'f32 * scale
  let crownH = 26.0'f32 * scale
  drawRectangle((cx - brimW / 2).int32, (cy + crownH / 2 - 3.0'f32 * scale).int32,
                brimW.int32, (6.0'f32 * scale).int32, tint)
  drawRectangle((cx - crownW / 2).int32, (cy - crownH / 2).int32,
                crownW.int32, crownH.int32, tint)
  drawRectangle((cx - crownW / 2).int32, (cy + crownH / 2 - 10.0'f32 * scale).int32,
                crownW.int32, (4.0'f32 * scale).int32,
                Color(r: 200, g: 60, b: 60, a: 255))  # hat band

proc drawDeleteConfirmDialog(state: ProfileSelectState, screenWidth, screenHeight: int32,
                             mousePos: Vector2) =
  ## Bilingual clone of main.nim's global quit-confirm dialog: DELETE is greyed
  ## out and shows a countdown until the anti-accident cooldown expires.
  let rects = confirmDialogRects(screenWidth, screenHeight)
  let d = rects.dialog
  drawRectangle(0, 0, screenWidth, screenHeight, Color(r: 0, g: 0, b: 0, a: 160))
  drawRectangle((d.x + 7).int32, (d.y + 7).int32, d.width.int32, d.height.int32,
                Color(r: 0, g: 0, b: 0, a: 140))
  drawRectangle(d.x.int32, d.y.int32, d.width.int32, d.height.int32,
                Color(r: 18, g: 22, b: 32, a: 255))
  drawRectangleLines(d, 3.0'f32, Color(r: 255, g: 80, b: 80, a: 255))

  let cx = (d.x + d.width / 2.0'f32).int32
  const TitleBarH = 36.0'f32
  drawRectangle(d.x.int32, d.y.int32, d.width.int32, TitleBarH.int32,
                Color(r: 120, g: 28, b: 28, a: 255))
  drawCenteredText("Delete Profile / Borrar perfil", cx, (d.y + 9).int32, 16,
                   Color(r: 255, g: 200, b: 200, a: 255))
  drawCenteredText("Delete Profile " & $state.confirmDeleteSlot &
                   "? / Borrar perfil " & $state.confirmDeleteSlot & "?",
                   cx, (d.y + TitleBarH + 24).int32, 19, White)
  drawCenteredText("All progress will be lost / Se perdera todo el progreso",
                   cx, (d.y + TitleBarH + 54).int32, 13,
                   Color(r: 200, g: 150, b: 150, a: 255))

  let noHov = checkCollisionPointRec(mousePos, rects.noBtn)
  let yesHov = checkCollisionPointRec(mousePos, rects.yesBtn)
  let ready = state.confirmCooldown <= 0

  drawRectangle(rects.noBtn.x.int32, rects.noBtn.y.int32,
                rects.noBtn.width.int32, rects.noBtn.height.int32,
                if noHov: Color(r: 0, g: 145, b: 0, a: 255)
                else: Color(r: 0, g: 105, b: 0, a: 255))
  drawRectangleLines(rects.noBtn, if noHov: 3.0'f32 else: 2.0'f32,
                     if noHov: Color(r: 0, g: 255, b: 100, a: 255)
                     else: Color(r: 0, g: 195, b: 55, a: 255))
  drawCenteredText("Cancel / Cancelar",
                   (rects.noBtn.x + rects.noBtn.width / 2.0'f32).int32,
                   (rects.noBtn.y + 13).int32, 14, White)

  # DELETE button greyed out (showing the countdown) until the cooldown ends
  let yesBg = if not ready: Color(r: 90, g: 90, b: 90, a: 255)
              elif yesHov:  Color(r: 158, g: 38, b: 38, a: 255)
              else:         Color(r: 118, g: 28, b: 28, a: 255)
  drawRectangle(rects.yesBtn.x.int32, rects.yesBtn.y.int32,
                rects.yesBtn.width.int32, rects.yesBtn.height.int32, yesBg)
  drawRectangleLines(rects.yesBtn, if yesHov and ready: 3.0'f32 else: 2.0'f32,
                     if not ready: Color(r: 140, g: 140, b: 140, a: 255)
                     elif yesHov:  Color(r: 255, g: 100, b: 100, a: 255)
                     else:         Color(r: 195, g: 55, b: 55, a: 255))
  let yesTxt = if not ready: $(int(ceil(state.confirmCooldown)))
               else: "Delete / Borrar"
  drawCenteredText(yesTxt, (rects.yesBtn.x + rects.yesBtn.width / 2.0'f32).int32,
                   (rects.yesBtn.y + 13).int32, 14, White)

proc drawProfileSelect*(state: ProfileSelectState, screenWidth, screenHeight: int32,
                        time: float32, mousePos: Vector2, activeSlot: int) =
  case state.mode
  of psmSlots:
    drawScreenFrame(screenWidth, screenHeight,
                    "Select Profile", "Selecciona perfil")
    let cards = slotCardRects(screenWidth, screenHeight)
    for slot in 1..MaxProfileSlots:
      let rect = cards[slot]
      let info = state.slots[slot]
      let hovered = checkCollisionPointRec(mousePos, rect)
      let accent = if info.exists: difficultyColor(info.difficulty)
                   else: Color(r: 0, g: 210, b: 255, a: 255)
      drawCardBase(rect, hovered, time, accent)

      let cx = (rect.x + rect.width / 2.0'f32).int32
      if info.exists:
        drawCenteredText("PROFILE " & $slot, cx, (rect.y + 24).int32, 24, White)
        drawCenteredText("PERFIL " & $slot, cx, (rect.y + 52).int32, 14,
                         Color(r: 150, g: 168, b: 190, a: 220))
        drawTophatBadge(rect.x + rect.width / 2.0'f32, rect.y + 108.0'f32, 1.0,
                        Color(r: 225, g: 232, b: 245, a: 255))
        drawCenteredText(difficultyLabel(info.difficulty), cx,
                         (rect.y + 152).int32, 18, difficultyColor(info.difficulty))
        if slot == activeSlot:
          drawCenteredText("LAST USED / ULTIMO", cx, (rect.y + 182).int32, 12,
                           Color(r: 0, g: 210, b: 255, a: 220))
        # Advancement completion: percent line + a slim bar, gold like the
        # master completion bar in the advancements window.
        let pct = int(round(info.completion * 100.0'f32))
        drawCenteredText("Progress / Progreso: " & $pct & "%", cx,
                         (rect.y + 206).int32, 13,
                         Color(r: 200, g: 212, b: 228, a: 240))
        let barW = rect.width * 0.64'f32
        let barX = rect.x + (rect.width - barW) / 2.0'f32
        let barY = rect.y + 228.0'f32
        drawRectangle(barX.int32, barY.int32, barW.int32, 7,
                      Color(r: 40, g: 48, b: 62, a: 255))
        if info.completion > 0:
          drawRectangle(barX.int32, barY.int32,
                        max(1'i32, (barW * info.completion).int32), 7,
                        Color(r: 255, g: 210, b: 70, a: 255))
        drawRectangleLines(Rectangle(x: barX, y: barY, width: barW, height: 7.0'f32),
                           1.0'f32, Color(r: 90, g: 105, b: 130, a: 255))
        # Delete button (opens the confirmation dialog)
        let delRect = deleteButtonRect(rect)
        let delHov = checkCollisionPointRec(mousePos, delRect)
        let delBg = if delHov: Color(r: 90, g: 34, b: 34, a: 255)
                    else: Color(r: 52, g: 30, b: 34, a: 255)
        drawRectangle(delRect.x.int32, delRect.y.int32,
                      delRect.width.int32, delRect.height.int32, delBg)
        drawRectangleLines(delRect, if delHov: 2.0'f32 else: 1.0'f32,
                           Color(r: 210, g: 80, b: 80, a: 255))
        drawCenteredText("Delete / Borrar", (delRect.x + delRect.width / 2.0'f32).int32,
                         (delRect.y + 8).int32, 13, Color(r: 235, g: 160, b: 160, a: 255))
      else:
        drawCenteredText("+", cx, (rect.y + rect.height / 2.0'f32 - 60.0'f32).int32, 60,
                         if hovered: Color(r: 0, g: 225, b: 255, a: 255)
                         else: Color(r: 90, g: 110, b: 135, a: 255))
        drawCenteredText("New Profile", cx, (rect.y + rect.height / 2.0'f32 + 14.0'f32).int32,
                         20, if hovered: White else: Color(r: 190, g: 205, b: 225, a: 255))
        drawCenteredText("Nuevo perfil", cx, (rect.y + rect.height / 2.0'f32 + 40.0'f32).int32,
                         14, Color(r: 150, g: 168, b: 190, a: 220))
      drawCenteredText("[" & $slot & "]", cx, (rect.y + rect.height + 12.0'f32).int32, 16,
                       Color(r: 130, g: 150, b: 170, a: 220))

    if state.confirmDeleteSlot > 0:
      drawDeleteConfirmDialog(state, screenWidth, screenHeight, mousePos)

  of psmDifficulty:
    drawScreenFrame(screenWidth, screenHeight,
                    "Select Difficulty", "Selecciona dificultad")
    drawCenteredText("Profile " & $state.targetSlot & " / Perfil " & $state.targetSlot,
                     screenWidth div 2,
                     (screenHeight.float32 * 0.5'f32 - 150.0'f32).int32, 18,
                     Color(r: 0, g: 210, b: 255, a: 220))
    let cards = difficultyCardRects(screenWidth, screenHeight)
    for d in GameDifficulty:
      let rect = cards[d]
      let hovered = checkCollisionPointRec(mousePos, rect)
      drawCardBase(rect, hovered, time, difficultyColor(d))
      let cx = (rect.x + rect.width / 2.0'f32).int32
      let name = case d
        of gdEasy: "EASY"
        of gdMedium: "MEDIUM"
        of gdHard: "HARD"
        of gdNightmare: "NIGHTMARE"
      let nameEs = case d
        of gdEasy: "Facil"
        of gdMedium: "Normal"
        of gdHard: "Dificil"
        of gdNightmare: "Pesadilla"
      # "NIGHTMARE" is the longest title by far; shrink it so it stays inside the
      # card instead of bleeding into its neighbours.
      let nameSize = if d == gdNightmare: 24'i32 else: 32'i32
      drawCenteredText(name, cx, (rect.y + 38).int32, nameSize, difficultyColor(d))
      drawCenteredText(nameEs, cx, (rect.y + 74).int32, 18,
                       Color(r: 170, g: 185, b: 205, a: 230))
      let lines = case d
        of gdEasy: @["-25% enemy HP / vida", "-30% enemy damage / daño"]
        of gdMedium: @["The classic balance", "El equilibrio clasico"]
        of gdHard: @["+35% enemy HP / vida", "+30% enemy damage / daño"]
        of gdNightmare: @["+50% enemy HP / vida", "+50% enemy damage / daño",
                          "NO CONTINUE / SIN CONTINUAR", "Death = restart at wave 1",
                          "Muerte = reinicio en oleada 1"]
      for i, line in lines:
        # The nightmare card carries more lines, in a smaller type size.
        let lineSize = if d == gdNightmare: 12'i32 else: 15'i32
        let lineStep = if d == gdNightmare: 21.0'f32 else: 26.0'f32
        let lineTop = if d == gdNightmare: 112.0'f32 else: 130.0'f32
        drawCenteredText(line, cx, (rect.y + lineTop + i.float32 * lineStep).int32, lineSize,
                         if d == gdNightmare and i == 2: difficultyColor(d)
                         else: Color(r: 200, g: 212, b: 228, a: 240))
      drawCenteredText("[" & $(ord(d) + 1) & "]  Click / Clic", cx,
                       (rect.y + rect.height - 32.0'f32).int32, 14,
                       Color(r: 130, g: 150, b: 170, a: 220))
    drawCenteredText("[ESC] Back / Volver", screenWidth div 2,
                     (screenHeight.float32 * 0.5'f32 + 200.0'f32).int32, 16,
                     Color(r: 130, g: 150, b: 170, a: 220))
