## OS-Themed Changelog Viewer
## Scrollable "patch notes" window listing what changed since the last
## released version. Modeled on help_window.nim but read-only (no command
## input) and driven by a curated, bilingual data table rather than git log.
##
## Maintenance: when a new version ships, prepend a ChangelogVersion to
## `changelog` below. The chrome (title/header/category labels) is localized
## through t(); the entry bodies are curated strings kept here as data so the
## fast-churning patch-note text never pollutes the TranslationKey enum.

import raylib, strutils
import os_window, ../localization, ../render_context

type
  ChangelogCategory* = enum
    clcNew       # brand new features / content
    clcImproved  # reworks and quality-of-life changes
    clcBalance   # tuning / numbers
    clcFixed     # bug fixes

  ChangelogEntry* = object
    category*: ChangelogCategory
    en*, es*: string

  ChangelogVersion* = object
    titleEn*, titleEs*: string
    subtitleEn*, subtitleEs*: string
    latest*: bool            # show the "LATEST" badge on this version
    entries*: seq[ChangelogEntry]

  ChangelogWindow* = ref object
    window*: OSWindow
    scrollOffset*: int       # in pixels

const
  CHANGELOG_LINE_HEIGHT = 20
  CHANGELOG_SCROLL_STEP = 40

# Curated changelog data
# Newest version first. Entry text is player-facing prose distilled from the
# commit history since the last release tag (Release552), not raw git subjects.
let changelog: seq[ChangelogVersion] = @[
  ChangelogVersion(
    titleEn: "Upcoming Update",
    titleEs: "Proxima Actualizacion",
    subtitleEn: "",  # empty -> resolved live via t(tkChangelogSince)
    subtitleEs: "",
    latest: true,
    entries: @[
      ChangelogEntry(category: clcNew,
        en: "Bosses now fight in distinct phases, shifting their attack patterns as their health drops.",
        es: "Los jefes ahora luchan en fases, cambiando sus patrones de ataque a medida que pierden vida."),
      ChangelogEntry(category: clcNew,
        en: "New Summoner mechanic: some enemies call in reinforcements mid-fight.",
        es: "Nueva mecanica de Invocador: algunos enemigos llaman refuerzos en plena pelea."),
      ChangelogEntry(category: clcNew,
        en: "Added dedicated victory and death screens to cap off every run.",
        es: "Se anadieron pantallas dedicadas de victoria y derrota para cerrar cada partida."),
      ChangelogEntry(category: clcNew,
        en: "Overhauled sound effect system (v2) with richer, cleaner audio.",
        es: "Sistema de efectos de sonido renovado (v2) con audio mas rico y limpio."),
      ChangelogEntry(category: clcImproved,
        en: "Roguelite mode reworked, including a new destructible-wall system and smoother progression.",
        es: "Modo Roguelite renovado, con un nuevo sistema de muros destructibles y progresion mas fluida."),
      ChangelogEntry(category: clcImproved,
        en: "Boss phase transitions and weak-point hitboxes reworked for clearer, fairer fights.",
        es: "Transiciones de fase y puntos debiles de los jefes rehechos para peleas mas claras y justas."),
      ChangelogEntry(category: clcImproved,
        en: "Refreshed the PvP lobby window with a more compact layout, punchier buttons, glossy highlights, brighter focus states and clearer player lists.",
        es: "Ventana de la sala PvP renovada con un diseno mas compacto, botones mas vistosos, brillos, estados de foco mas claros y listas de jugadores mas legibles."),
      ChangelogEntry(category: clcBalance,
        en: "Bosses buffed across the board, including a retuned final boss encounter.",
        es: "Jefes reforzados en general, incluyendo un reajuste del jefe final."),
      ChangelogEntry(category: clcBalance,
        en: "The Summoner King is tougher: more health and a sturdier defensive stance, so clearing its legion now matters more.",
        es: "El Rey Invocador es mas resistente: mas vida y una postura defensiva mas solida, asi que limpiar su legion ahora importa mas."),
      ChangelogEntry(category: clcBalance,
        en: "The Meteor Striker hits a little harder and takes a little more punishment across all phases.",
        es: "El Golpeador de Meteoros pega un poco mas fuerte y aguanta un poco mas de castigo en todas las fases."),
      ChangelogEntry(category: clcBalance,
        en: "The Laser Architect's later phases are more readable: fewer simultaneous beams and shorter laser sweeps make its grid and cage attacks fairer to dodge.",
        es: "Las fases avanzadas del Arquitecto Laser son mas legibles: menos rayos simultaneos y barridos mas cortos hacen que sus ataques de rejilla y jaula sean mas justos de esquivar."),
      ChangelogEntry(category: clcBalance,
        en: "Reworked the Giant Slayer power-up.",
        es: "Rework del potenciador Cazagigantes."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Echo bullet hit detection and Curse/Echo interactions.",
        es: "Corregida la deteccion de impactos de las balas Eco y las interacciones Maldicion/Eco."),

      # --- Late-game scaling, balance & power-ups ---
      ChangelogEntry(category: clcNew,
        en: "Added a large batch of new mode-exclusive power-ups for Survival and Roguelite runs, including several Legendaries.",
        es: "Se anadio un gran lote de nuevos potenciadores exclusivos de modo para partidas de Supervivencia y Roguelite, incluyendo varios Legendarios."),
      ChangelogEntry(category: clcNew,
        en: "Each game mode now opens with its own intro cinematic.",
        es: "Cada modo de juego ahora comienza con su propia cinematica de introduccion."),
      ChangelogEntry(category: clcNew,
        en: "New comeback bonus: falling behind grants a temporary damage boost to help you recover.",
        es: "Nuevo bono de remontada: quedar atras otorga un aumento temporal de daño para ayudarte a recuperar."),
      ChangelogEntry(category: clcNew,
        en: "Controls can now be fully rebound from the Settings window.",
        es: "Los controles ahora se pueden reasignar por completo desde la ventana de Ajustes."),
      ChangelogEntry(category: clcNew,
        en: "Fights against multiple bosses now show a separate health bar for each one.",
        es: "Las peleas contra varios jefes ahora muestran una barra de vida separada para cada uno."),
      ChangelogEntry(category: clcNew,
        en: "Added new desktop themes (Kernel Panic, CyberGround, Casino) and hidden easter eggs to discover.",
        es: "Se anadieron nuevos temas de escritorio (Kernel Panic, CyberGround, Casino) y huevos de pascua ocultos por descubrir."),
      ChangelogEntry(category: clcNew,
        en: "New cosmetics, including D&D-themed skins and secret unlockable hats.",
        es: "Nuevos cosmeticos, incluyendo aspectos tematicos de D&D y sombreros secretos desbloqueables."),
      ChangelogEntry(category: clcImproved,
        en: "HUD notifications and power-up discoveries now appear as cleaner, stacking toasts.",
        es: "Las notificaciones del HUD y los descubrimientos de potenciadores ahora aparecen como avisos apilables mas limpios."),
      ChangelogEntry(category: clcImproved,
        en: "Reworked the splash/boot screen and refined enemy visual effects.",
        es: "Se rehizo la pantalla de inicio/arranque y se refinaron los efectos visuales de los enemigos."),
      ChangelogEntry(category: clcImproved,
        en: "Further refined the destructible-wall system for better placement and feel.",
        es: "Se refino aun mas el sistema de muros destructibles para mejor colocacion y sensacion."),
      ChangelogEntry(category: clcBalance,
        en: "Arcane Orbs buffed: +50% base damage. They deal pure damage with no elemental effect, so they now hit noticeably harder to compensate.",
        es: "Orbes Arcanos reforzados: +50% de daño base. Hacen daño puro sin efecto elemental, asi que ahora pegan notablemente mas fuerte para compensar."),
      ChangelogEntry(category: clcBalance,
        en: "Poison and Fire orb masteries strengthened: stronger damage-over-time and a heavier slow on affected enemies.",
        es: "Maestrias de orbe de Veneno y Fuego reforzadas: mas daño por tiempo y una ralentizacion mas fuerte sobre los enemigos afectados."),
      ChangelogEntry(category: clcBalance,
        en: "Reworked late-game scaling: enemy counts now grow on a smoother, uncapped curve while enemies (and endless bosses past wave 60) gain compounding health and damage, so runs stay challenging deep into the endless waves.",
        es: "Se rehizo el escalado de fin de partida: la cantidad de enemigos ahora crece en una curva mas suave y sin tope, mientras que los enemigos (y los jefes infinitos pasada la oleada 60) ganan vida y daño acumulativos, manteniendo el desafio en las oleadas infinitas."),
      ChangelogEntry(category: clcBalance,
        en: "Agility nerfed: its speed boost now grants +33% movement speed, down from +40%.",
        es: "Agilidad ajustada: su aumento de velocidad ahora otorga +33% de velocidad de movimiento, en lugar de +40%."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed player movement speed skyrocketing when certain power-ups were removed.",
        es: "Se corrigio que la velocidad del jugador se disparara al quitar ciertos potenciadores."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed several boss special-attack and behavior bugs.",
        es: "Se corrigieron varios errores en ataques especiales y comportamientos de jefes."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed unlock-system bugs.",
        es: "Se corrigieron errores del sistema de desbloqueos.")
    ]
  )
]

proc categoryLabel(cat: ChangelogCategory): string =
  case cat
  of clcNew: t(tkChangelogCatNew)
  of clcImproved: t(tkChangelogCatImproved)
  of clcBalance: t(tkChangelogCatBalance)
  of clcFixed: t(tkChangelogCatFixed)

proc categoryColor(cat: ChangelogCategory): Color =
  case cat
  of clcNew: Color(r: 90, g: 255, b: 150, a: 255)      # green
  of clcImproved: Color(r: 90, g: 200, b: 255, a: 255) # cyan
  of clcBalance: Color(r: 255, g: 200, b: 50, a: 255)  # gold
  of clcFixed: Color(r: 255, g: 130, b: 110, a: 255)   # warm red

proc entryText(e: ChangelogEntry): string =
  if getLanguage() == Spanish: e.es else: e.en

proc versionTitle(v: ChangelogVersion): string =
  if getLanguage() == Spanish: v.titleEs else: v.titleEn

proc versionSubtitle(v: ChangelogVersion): string =
  let s = if getLanguage() == Spanish: v.subtitleEs else: v.subtitleEn
  if s.len == 0: t(tkChangelogSince) else: s

proc newChangelogWindow*(screenWidth, screenHeight: int): ChangelogWindow =
  let windowWidth = 640
  let windowHeight = 520
  let windowX = (screenWidth - windowWidth) div 2
  let windowY = (screenHeight - windowHeight) div 2

  let osWin = newOSWindow(
    t(tkChangelogWindowTitle),
    windowX, windowY,
    windowWidth, windowHeight,
    Color(r: 255, g: 180, b: 80, a: 255),  # amber
    owtHelp,
    resizable = false
  )

  result = ChangelogWindow(
    window: osWin,
    scrollOffset: 0
  )

# Render-line model
# The changelog is flattened to a flat list of drawable lines each frame so
# wrapping and the current language are always up to date.
type
  LineKind = enum
    lkHeader      # big section header ("What's New")
    lkSubtitle    # version subtitle ("Changes since vX")
    lkVersion     # version title with optional LATEST badge
    lkCategory    # category label
    lkEntry       # a bullet entry (wrapped)
    lkSpacer      # blank line

  RenderLine = object
    kind: LineKind
    text: string
    color: Color
    badge: bool   # draw the LATEST badge after the text (lkVersion only)

proc wrapText(text: string, maxWidth, fontSize: int32): seq[string] =
  result = @[]
  if text.len == 0:
    result.add("")
    return
  var cur = ""
  for word in text.split(' '):
    let candidate = if cur.len == 0: word else: cur & " " & word
    if measureText(candidate, fontSize) <= maxWidth:
      cur = candidate
    else:
      if cur.len > 0: result.add(cur)
      cur = word
  if cur.len > 0: result.add(cur)

proc buildRenderLines(cl: ChangelogWindow, textWidth: int32): seq[RenderLine] =
  result = @[]
  result.add(RenderLine(kind: lkHeader, text: t(tkChangelogHeader),
                        color: Color(r: 230, g: 245, b: 255, a: 255)))

  for v in changelog:
    result.add(RenderLine(kind: lkSpacer))
    result.add(RenderLine(kind: lkVersion, text: versionTitle(v),
                          color: Color(r: 255, g: 200, b: 120, a: 255),
                          badge: v.latest))
    result.add(RenderLine(kind: lkSubtitle, text: versionSubtitle(v),
                          color: Color(r: 150, g: 160, b: 175, a: 255)))

    # Group entries by category, preserving category order.
    for cat in ChangelogCategory:
      var any = false
      for e in v.entries:
        if e.category != cat: continue
        if not any:
          result.add(RenderLine(kind: lkSpacer))
          result.add(RenderLine(kind: lkCategory, text: categoryLabel(cat),
                                color: categoryColor(cat)))
          any = true
        # Wrap the bullet body to the content width (minus bullet indent).
        let wrapped = wrapText("- " & entryText(e), textWidth - 16, 16)
        var first = true
        for wline in wrapped:
          result.add(RenderLine(kind: lkEntry,
                                text: (if first: wline else: "  " & wline),
                                color: Color(r: 205, g: 212, b: 222, a: 255)))
          first = false

proc contentMetrics(cl: ChangelogWindow): tuple[x, y, w, h: int] =
  let x = cl.window.x + WINDOW_PADDING
  let y = cl.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let w = cl.window.width - WINDOW_PADDING * 2
  let h = cl.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  (x, y, w, h)

proc totalContentHeight(cl: ChangelogWindow, textWidth: int32): int =
  buildRenderLines(cl, textWidth).len * CHANGELOG_LINE_HEIGHT

proc updateChangelogWindow*(cl: ChangelogWindow, dt: float32,
                            screenWidth, screenHeight: int,
                            allWindows: openArray[OSWindow]) =
  ## Update window chrome and handle scrolling. Closing is signalled by setting
  ## cl.window.visible = false (handled here), matching the help window.
  updateOSWindow(cl.window, dt)
  if not cl.window.visible:
    return

  let shouldClose = handleOSWindowInput(cl.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    cl.window.visible = false
    return

  if cl.window.minimized:
    return

  let (_, _, w, h) = contentMetrics(cl)
  let textWidth = (w - 24).int32
  let viewH = h - 16
  let maxScroll = max(0, totalContentHeight(cl, textWidth) - viewH)

  let wheel = getPointerWheelMove()
  if wheel != 0:
    cl.scrollOffset = clamp(cl.scrollOffset - int(wheel * CHANGELOG_SCROLL_STEP),
                            0, maxScroll)
  else:
    # Keep the offset valid if the window was just opened / language changed.
    cl.scrollOffset = clamp(cl.scrollOffset, 0, maxScroll)

proc drawChangelogWindow*(cl: ChangelogWindow) =
  if not cl.window.visible:
    return

  drawWindowChrome(cl.window)
  if cl.window.minimized:
    return

  let (contentX, contentY, contentW, contentH) = contentMetrics(cl)

  # Panel background
  drawRectangle(contentX.int32, contentY.int32, contentW.int32, contentH.int32,
               Color(r: 10, g: 12, b: 18, a: 255))
  drawRectangleLines(Rectangle(x: contentX.float32, y: contentY.float32,
                                width: contentW.float32, height: contentH.float32),
                    1, Color(r: 255, g: 180, b: 80, a: 200))

  let textWidth = (contentW - 24).int32
  let lines = buildRenderLines(cl, textWidth)

  # Clip region so scrolled content does not bleed over the chrome.
  let clipY = contentY + 8
  let clipH = contentH - 16
  beginVirtualScissorMode(contentX.int32, clipY.int32, contentW.int32, clipH.int32)

  let baseX = contentX + 14
  var yPos = clipY - cl.scrollOffset
  for line in lines:
    # Skip lines fully outside the visible band (cheap culling).
    if yPos + CHANGELOG_LINE_HEIGHT >= clipY and yPos <= clipY + clipH:
      case line.kind
      of lkSpacer:
        discard
      of lkHeader:
        drawText(line.text, baseX.int32, yPos.int32, 22, line.color)
        drawLine(Vector2(x: baseX.float32, y: (yPos + 24).float32),
                 Vector2(x: (contentX + contentW - 14).float32, y: (yPos + 24).float32),
                 1, Color(r: 255, g: 180, b: 80, a: 120))
      of lkVersion:
        drawText(line.text, baseX.int32, yPos.int32, 18, line.color)
        if line.badge:
          let badgeX = baseX + measureText(line.text, 18) + 10
          let label = t(tkChangelogLatest)
          let bw = measureText(label, 12) + 12
          drawRectangle(badgeX.int32, (yPos + 1).int32, bw.int32, 16,
                       Color(r: 90, g: 255, b: 150, a: 255))
          drawText(label, (badgeX + 6).int32, (yPos + 3).int32, 12,
                  Color(r: 8, g: 16, b: 12, a: 255))
      of lkSubtitle:
        drawText(line.text, baseX.int32, yPos.int32, 13, line.color)
      of lkCategory:
        drawText(line.text, baseX.int32, yPos.int32, 16, line.color)
      of lkEntry:
        drawText(line.text, (baseX + 8).int32, yPos.int32, 16, line.color)
    yPos += CHANGELOG_LINE_HEIGHT

  endScissorMode()

  # Scrollbar
  let viewH = contentH - 16
  let total = lines.len * CHANGELOG_LINE_HEIGHT
  if total > viewH:
    let trackX = contentX + contentW - 8
    let trackY = clipY
    let trackH = clipH
    let thumbH = max(24, int(float32(trackH) * float32(viewH) / float32(total)))
    let maxScroll = max(1, total - viewH)
    let thumbY = trackY + int(float32(trackH - thumbH) *
                              float32(cl.scrollOffset) / float32(maxScroll))
    drawRectangle(trackX.int32, trackY.int32, 5, trackH.int32,
                 Color(r: 25, g: 28, b: 36, a: 255))
    drawRectangle(trackX.int32, thumbY.int32, 5, thumbH.int32,
                 Color(r: 255, g: 180, b: 80, a: 230))

  drawResizeIndicator(cl.window)
