## Co-op overlays, over a co-op run on every machine: the teammates strip in
## play (each player's HP, who is down and when they are back, the team's
## lives) and the team-modal status over a draft, the shop, a Data Cache or
## floor select (who is still choosing, and the auto-pick countdown).

import raylib, math, strutils
import ../modding/mod_patch_core
import ../types, ../localization, ../render_context
import ../modding/mod_hooks
import ../coop/coop_context
import hud_dock, ui_theme
import ../draw_prims, ../utils, ../gamepad_input

const
  TeamGreen = Color(r: 110, g: 240, b: 170, a: 255)
  TeamAmber = Color(r: 255, g: 200, b: 90, a: 255)
  TeamRed = Color(r: 255, g: 95, b: 95, a: 255)
  RowH = 18'i32

proc coopName*(game: Game, slot: int): string {.moddable.} =
  ## A player's nickname, or "PLAYER n" when they have none.
  if not game.coop.isNil and slot in 0 ..< MaxCoopPlayers and
     game.coop.nicknames[slot].len > 0:
    game.coop.nicknames[slot]
  else:
    t(tkCoopPlayerN).replace("$1", $(slot + 1))

proc drawCoopModalStatus*(game: Game) {.moddable.} =
  ## Over a team modal: every player's state in it, and once this machine's
  ## player is done, that the screen is waiting for the rest.
  let coop = game.coop
  if coop.isNil or coop.modal == cmkNone or hudHidden(hpTeam): return
  let w = 300'i32
  let x = (getVirtualScreenWidth() - w) div 2
  let y = 10'i32
  let h = DockHeaderH + 6 + RowH * game.players.len.int32
  drawDockCard(x, y, w, h, TeamGreen)
  let title = if game.waitingOnTeam: t(tkCoopWaitingForTeam) else: t(tkCoopTeamChoosing)
  let right = if coop.modalTimer < 15.0'f32:
                t(tkCoopAutoIn).replace("$1", $max(0, int(ceil(coop.modalTimer))))
              else: ""
  var cy = drawDockHeader(x, y, w, title, TeamGreen, right, TeamAmber) + 3
  for p in game.players:
    let seat = coop.seats[p.slot]
    let (status, col) =
      if p.eliminated: (t(tkCoopOut), DockDim)
      elif seat.ready: (t(tkCoopReady), TeamGreen)
      else: (t(tkCoopChoosing), TeamAmber)
    let you = p.isLocalPlayer
    drawShadowText(coopName(game, p.slot.int), x + DockPad, cy, 12,
                   if you: DockInk else: DockDim)
    let sw = measureText(status, 12)
    drawShadowText(status, x + w - DockPad - sw, cy, 12, col)
    cy += RowH

proc drawCoopTeamStrip*(game: Game, x, y, w: int32): int32 {.discardable, moddable.} =
  ## The teammates card in play: each other player's HP (or how long until
  ## they are back), and the team's lives. Returns the y below it.
  let coop = game.coop
  if coop.isNil or hudHidden(hpTeam): return y
  let others = max(0, game.players.len - 1)
  let h = DockHeaderH + 6 + RowH * others.int32
  drawDockCard(x, y, w, h, TeamGreen)
  let lives = if coop.teamLives == UnlimitedLives: "--" else: $coop.teamLives
  var cy = drawDockHeader(x, y, w, t(tkCoopTeamLives) & " " & lives, TeamGreen) + 3
  for p in game.players:
    if p.isLocalPlayer: continue
    let name = coopName(game, p.slot.int)
    drawShadowText(name, x + DockPad, cy, 11, DockInk)
    let barX = x + DockPad + 92
    let barW = w - DockPad * 2 - 92
    if p.eliminated:
      drawShadowText(t(tkCoopOut), barX, cy, 11, DockDim)
    elif p.downTimer > 0:
      drawShadowText(t(tkCoopRespawnIn).replace("$1", $int(ceil(p.downTimer))), barX, cy, 11, TeamAmber)
    else:
      let frac = if p.maxHp > 0: p.hp / p.maxHp else: 0.0'f32
      drawDockBar(barX, cy + 2, barW, 8, frac,
                  if frac < 0.3'f32: TeamRed else: TeamGreen)
    cy += RowH
  y + h

proc drawCoopLocalDown*(game: Game) {.moddable.} =
  ## This machine's player is down or out: say so over the arena.
  let p = game.player
  if game.coop.isNil or p.isUp or hudHidden(hpTeam): return
  let text = if p.eliminated: t(tkCoopEliminated)
             else: t(tkCoopDown) & "  -  " & t(tkCoopRespawnIn).replace("$1", $int(ceil(p.downTimer)))
  let size = 22'i32
  let tw = measureText(text, size)
  let sx = (getVirtualScreenWidth() - tw) div 2
  let sy = getVirtualScreenHeight() div 2 - 90
  drawOverlayText(text, sx, sy, size, if p.eliminated: TeamRed else: TeamAmber)

proc drawCoopBanner*(text: string) {.moddable.} =
  ## A line across the top of the arena: the client is syncing, the host is
  ## somewhere this screen can't follow yet, the team is choosing...
  let size = 20'i32
  let tw = measureText(text, size)
  let w = tw + 40
  let x = (getVirtualScreenWidth() - w) div 2
  let y = 70'i32
  drawRectangle(x, y, w, size + 16, hudSurface(Color(r: 10, g: 14, b: 22, a: 215)))
  drawRectOutline(x, y, w, size + 16, uiLine(withAlpha(TeamGreen, 160)))
  drawText(text, x + 20, y + 8, size, uiInk(TeamGreen))

# The pause menu of a co-op run. The run goes on behind it (the team can't be
# paused by one player), so it is a menu over live play, not a state.

var pauseSelected = 0

proc menuRect(i: int): Rectangle =
  let w = 320'f32
  let x = (getVirtualScreenWidth().float32 - w) / 2
  let y = getVirtualScreenHeight().float32 / 2 - 10 + i.float32 * 52
  Rectangle(x: x, y: y, width: w, height: 42)

proc coopPauseMenu*(host: bool): int {.moddable.} =
  ## Draws the menu and reads it: 0 resume, 1 leave the run (the host: end it
  ## for everyone), -1 nothing this frame.
  result = -1
  let vw = getVirtualScreenWidth()
  let vh = getVirtualScreenHeight()
  drawRectangle(0, 0, vw, vh, Color(r: 0, g: 0, b: 0, a: 120))
  let title = t(tkCoopPausedNote)
  let tw = measureText(title, 22)
  drawOverlayText(title, (vw - tw) div 2, vh div 2 - 70, 22, uiOverlay(TeamAmber))
  let labels = [t(tkCoopResume), (if host: t(tkCoopEndRun) else: t(tkCoopLeaveRun))]
  let mp = getVirtualMousePosition()
  for i, label in labels:
    let r = menuRect(i)
    if checkCollisionPointRec(mp, r): pauseSelected = i
    let sel = pauseSelected == i
    drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32,
                  uiSurface(if sel: Color(r: 30, g: 60, b: 44, a: 240) else: Color(r: 14, g: 18, b: 28, a: 235)))
    drawRectOutline(r.x.int32, r.y.int32, r.width.int32, r.height.int32,
                       uiLine(if sel: TeamGreen else: Color(r: 70, g: 80, b: 100, a: 255)))
    let lw = measureText(label, 18)
    drawText(label, r.x.int32 + (r.width.int32 - lw) div 2, r.y.int32 + 12, 18,
             uiInk(if sel: White else: Color(r: 190, g: 198, b: 210, a: 255)))
  if isKeyPressed(Up) or isKeyPressed(W): pauseSelected = (pauseSelected + 1) mod 2
  if isKeyPressed(Down) or isKeyPressed(S): pauseSelected = (pauseSelected + 1) mod 2
  if isPointerPressed():
    for i in 0 .. 1:
      if checkCollisionPointRec(mp, menuRect(i)): return i
  if isKeyPressed(Enter) or isKeyPressed(E) or isGamepadConfirmPressed():
    return pauseSelected
  if isBackPressed() or isGamepadStartPressed():
    return 0

proc resetCoopPauseMenu*() =
  pauseSelected = 0

proc coopResultsPanel*(game: Game, reason: string, kills: int): bool {.moddable.} =
  ## A client's end of a co-op run, over its last frame: why it ended and what
  ## this player did. True when they go back to the lobby.
  let vw = getVirtualScreenWidth()
  let vh = getVirtualScreenHeight()
  drawRectangle(0, 0, vw, vh, Color(r: 0, g: 0, b: 0, a: 150))
  let w = 420'i32
  let h = 230'i32
  let x = (vw - w) div 2
  let y = (vh - h) div 2
  drawRectangle(x, y, w, h, uiSurface(Color(r: 12, g: 16, b: 26, a: 245)))
  drawRectOutline(x, y, w, h, uiLine(TeamGreen))
  let title = t(tkCoopRunOver)
  drawText(title, x + (w - measureText(title, 28)) div 2, y + 22, 28, uiInk(TeamGreen))
  drawText(reason, x + (w - measureText(reason, 16)) div 2, y + 66, 16,
           uiInk(Color(r: 205, g: 212, b: 222, a: 255)))
  let line = t(tkCoopResultsKills).replace("$1", $kills)
  drawText(line, x + (w - measureText(line, 18)) div 2, y + 104, 18,
           uiInk(Color(r: 235, g: 245, b: 255, a: 255)))
  let r = Rectangle(x: (x + 60).float32, y: (y + h - 62).float32, width: (w - 120).float32, height: 40)
  let hover = checkCollisionPointRec(getVirtualMousePosition(), r)
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32,
                uiSurface(if hover: Color(r: 56, g: 140, b: 84, a: 255) else: Color(r: 46, g: 120, b: 70, a: 255)))
  drawRectOutline(r.x.int32, r.y.int32, r.width.int32, r.height.int32, uiLine(White))
  let label = t(tkCoopBackToLobby)
  drawText(label, r.x.int32 + (r.width.int32 - measureText(label, 18)) div 2, r.y.int32 + 11, 18,
           uiInk(White))
  (isPointerPressed() and hover) or isKeyPressed(Enter) or isGamepadConfirmPressed()
