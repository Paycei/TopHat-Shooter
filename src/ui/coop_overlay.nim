## Co-op overlays, over a co-op run on every machine: the teammates strip in
## play (each player's HP, who is down and when they are back, the team's
## lives) and the team-modal status over a draft, the shop, a Data Cache or
## floor select (who is still choosing, and the auto-pick countdown).

import raylib, math, strutils
import ../modding/mod_patch_core
import ../types, ../localization, ../render_context
import ../modding/mod_hooks
import ../coop/coop_context
import hud_dock

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
