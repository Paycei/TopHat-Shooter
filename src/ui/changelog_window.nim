## OS-Themed Changelog Viewer
## Scrollable "patch notes" window listing what changed in each released
## version. Modeled on help_window.nim but read-only (no command input) and
## driven by a curated, bilingual data table rather than git log.
##
## Two views, picked with the footer checkbox and saved per profile
## (Settings.changelogLegacyView): one page per version, flipped with the
## prev/next buttons, the page dots or Left/Right (dpad), or the legacy view
## with every version in a single scroll.
##
## Maintenance: when a new version ships, prepend a ChangelogVersion to
## `changelog` below. The chrome (title/header/category labels) is localized
## through t(); the entry bodies are curated strings kept here as data so the
## fast-churning patch-note text never pollutes the TranslationKey enum.
##
## Write entries to be scanned, not read start to finish: a short headline
## (headEn/headEs) plus a few one-to-two-line points built with `points(...)`,
## each point one fact. Numbers and controls belong in the points; design
## rationale and backstory do not.

import raylib, strutils
import os_window, ui_helpers, ../localization, ../render_context, ../settings, ../save_system
from settings_window import drawCheckbox

type
  ChangelogCategory* = enum
    clcNew       # brand new features / content
    clcImproved  # reworks and quality-of-life changes
    clcBalance   # tuning / numbers
    clcFixed     # bug fixes

  ChangelogEntry* = object
    category*: ChangelogCategory
    headEn*, headEs*: string  # optional headline, drawn bold above the body
    en*, es*: string          # body; each '\n'-separated line is its own bullet

  ChangelogVersion* = object
    titleEn*, titleEs*: string
    subtitleEn*, subtitleEs*: string
    latest*: bool            # show the "LATEST" badge on this version
    entries*: seq[ChangelogEntry]

  LineKind = enum
    lkHeader      # big section header ("What's New")
    lkVersion     # version title with optional LATEST badge
    lkSubtitle    # version subtitle ("Changes since vX")
    lkCategory    # category label
    lkHead        # an entry's headline (bold)
    lkBody        # an entry's body text

  MarkerKind = enum
    mkNone
    mkSquare      # top-level bullet, in the category colour
    mkPoint       # a point under a headline

  ChangelogLine = object
    kind: LineKind
    text: string
    color: Color
    x, y: int     # relative to the text margin / the top of the content
    marker: MarkerKind
    markerColor: Color
    badge: bool   # draw the LATEST badge after the text (lkVersion only)

  ChangelogLayout = object
    lines: seq[ChangelogLine]
    height: int   # total content height in pixels
    versionTops: seq[int]  # legacy view: y of each version's title

  ChangelogWindow* = ref object
    window*: OSWindow
    scrollOffset*: int       # in pixels, within the page (or the legacy scroll)
    page*: int               # paged view: index into `changelog`, 0 = newest
    layout: ChangelogLayout  # cached wrap of the current page / legacy scroll
    layoutWidth: int32
    layoutLanguage: Language
    layoutPage: int          # page the cache was built for, -1 = legacy view
    layoutValid: bool

const
  # Sized so 20px text wraps at ~60 characters, a comfortable reading measure,
  # while the window still fits the 768px-tall virtual screen.
  CHANGELOG_WINDOW_WIDTH = 780
  CHANGELOG_WINDOW_HEIGHT = 660
  CHANGELOG_SCROLL_STEP = 60

  # The default font is a 10px bitmap drawn with point filtering, so sizes on
  # its 10px grid scale every stroke by a whole number and stay even. The old
  # 16px body text scaled by 1.6, giving uneven 1px/2px strokes.
  CL_TITLE_SIZE = 30'i32
  CL_TEXT_SIZE = 20'i32
  CL_SMALL_SIZE = 10'i32

  CL_LINE_H = 25            # line advance at CL_TEXT_SIZE
  CL_HEADER_ADVANCE = 48    # "What's New" line plus its rule
  CL_VERSION_GAP = 30       # extra space above each version after the first
  CL_CATEGORY_GAP = 14      # extra space above each category label
  CL_ENTRY_GAP = 12         # space after each entry
  CL_HEAD_INDENT = 18       # text right of a square marker
  CL_POINT_INDENT = 38      # text right of a point marker
  CL_MARGIN_LEFT = 16
  CL_MARGIN_RIGHT = 22      # leaves room for the scrollbar
  CL_PAD_Y = 12

  CL_NAV_H = 82             # paged view: prev / title + subtitle + page dots / next
  CL_NAV_BTN = 40           # square prev/next buttons
  CL_DOT_PITCH = 18         # page dot cell (click target)
  CL_FOOTER_H = 38          # legacy-view checkbox row
  CL_CHECKBOX = 20

proc points(items: varargs[string]): string =
  ## Joins an entry's bullet points into one body string (see ChangelogEntry).
  items.join("\n")

# Curated changelog data
# Newest version first. Entry text is player-facing prose distilled from the
# commit history since the previous release tag, not raw git subjects.
let changelog: seq[ChangelogVersion] = @[
  ChangelogVersion(
    titleEn: "Version 6.3.0",
    titleEs: "Versión 6.3.0",
    subtitleEn: "Changes since v6.2.2",
    subtitleEs: "Cambios desde v6.2.2",
    latest: true,
    entries: @[
      # --- New ---
      ChangelogEntry(category: clcNew,
        headEn: "Time Survival: its own horde and bosses",
        headEs: "Supervivencia: horda y jefes propios",
        en: points(
          "Time Survival no longer borrows the wave-mode enemies. The flood has its own horde of 7 processes that join the fight as the clock runs: Threads, Fork Bombs, Watchdogs, Zombie Processes, Deadlocks, Priority Daemons and Interrupts.",
          "They are made for a crowd. Fork Bombs split in two when killed, a Zombie Process stands back up unless you walk over its husk, Deadlocks come in pairs joined by a burning tether, a Priority Daemon speeds up everything around it and an Interrupt blows up the horde along with you.",
          "Three new phase bosses close Boot, Runtime and Overload, and each one fights with the horde. The Forkmother hides her children in the crowd and fires seeds that double on every beat, the Dispatcher marches walls of bodies across the arena for you to shoot through, and Thermal Runaway sets your own footsteps on fire.",
          "The Omega Entity still closes Kernel Panic, with a new survival kit that ends in Safe Mode: the flood takes everything but one drifting bubble.",
          "Overtime now rotates through all four bosses."),
        es: points(
          "Supervivencia ya no toma prestados los enemigos del modo oleadas. La inundación tiene su propia horda de 7 procesos que se suman al combate según avanza el reloj: Hilos, Bombas Fork, Perros Guardianes, Procesos Zombi, Interbloqueos, Demonios de Prioridad e Interrupciones.",
          "Están hechos para una multitud. Las Bombas Fork se parten en dos al morir, un Proceso Zombi se vuelve a levantar salvo que pases por encima de su cáscara, los Interbloqueos llegan en parejas unidas por un enlace ardiente, un Demonio de Prioridad acelera todo lo que tiene cerca y una Interrupción hace estallar a la horda contigo.",
          "Tres jefes de fase nuevos cierran Arranque, Ejecución y Sobrecarga, y cada uno lucha junto a la horda. La Madre Fork esconde a sus hijos entre la multitud y lanza semillas que se duplican a cada compás, el Despachador hace marchar muros de cuerpos por la arena para que te abras paso a tiros, y Fuga Térmica prende fuego a tus propias pisadas.",
          "La Entidad Omega sigue cerrando Pánico del Kernel, con un repertorio nuevo de supervivencia que termina en Modo Seguro: la inundación lo cubre todo salvo una burbuja a la deriva.",
          "El tiempo extra ahora rota entre los cuatro jefes.")),
      ChangelogEntry(category: clcNew,
        headEn: "Roguelite: its own processes and a guardian per folder",
        headEs: "Roguelite: procesos propios y un guardián por carpeta",
        en: points(
          "The folders are held by 8 legacy processes built for rooms: Fragments, Port Guards you have to flank, Sentries that dig in, Mimics posing as files, Restorers that raise the fallen, Packets that ricochet off the walls, armoured Drivers that stun themselves on obstacles and Corruptors that rot the floor.",
          "Every folder theme has its own guardian, so the theme card tells you who waits at the SERVICE: the Gatekeeper, the Compactor, the Hive, the Router, the Supervisor and the Mirror Cache.",
          "Each guardian plays with the room. Take cover from the Gatekeeper's searchlights, shred the Compactor's file bombs before the purge, freeze when the Hive audits, cross the Router's packet lanes, watch where the Supervisor pages its obstacles back in and outrun the Mirror Cache's echo of yourself.",
          "A guardian grows with the sector it appears in. The Corrupted Sector is now reserved for the final sector.",
          "The final sector's Omega Entity has a new roguelite kit that echoes the guardians and ends in Last Known Good: four doors light up, and only the one labelled with a folder you really walked is safe."),
        es: points(
          "Las carpetas están custodiadas por 8 procesos heredados hechos para las salas: Fragmentos, Guardias de Puerto a los que hay que flanquear, Centinelas que se atrincheran, Mímicos disfrazados de archivos, Restauradores que levantan a los caídos, Paquetes que rebotan en los muros, Controladores blindados que se aturden contra los obstáculos y Corruptores que pudren el suelo.",
          "Cada tema de carpeta tiene su propio guardián, así que la tarjeta del tema te dice quién espera en el SERVICIO: el Guardián, la Compactadora, la Colmena, el Enrutador, el Supervisor y la Caché Espejo.",
          "Cada guardián juega con la sala. Cúbrete de los haces del Guardián, destruye las bombas de archivos de la Compactadora antes de la purga, quédate quieto cuando la Colmena audita, cruza los carriles de paquetes del Enrutador, vigila dónde vuelve a colocar el Supervisor sus obstáculos y déjate atrás al eco de ti mismo de la Caché Espejo.",
          "Un guardián crece con el sector en el que aparece. El Sector Corrupto queda reservado para el sector final.",
          "La Entidad Omega del sector final tiene un repertorio nuevo de roguelite que repite a los guardianes y termina en Última Configuración Válida: se iluminan cuatro puertas y solo es segura la que lleva el nombre de una carpeta por la que pasaste de verdad.")),
      ChangelogEntry(category: clcNew,
        headEn: "Roguelite reworked: Deep Recovery",
        headEs: "Roguelite renovado: Recuperación Profunda",
        en: points(
          "Each sector is now a forward path of folders ending in the sector's SERVICE. No more keys, compass, map, treasure room or walking back through empty rooms.",
          "Clear a folder and its reward appears in the middle of the room. Collect it and 2 or 3 exits open, each showing the folder it leads to and what it pays: /bin power-up, /updates patch, /cache credits, /restore repair, /shards Data Shards, /pkg stalls, /quarantine elite fight.",
          "Picking a door is picking your build. The status panel shows your path as a breadcrumb (C:\\FIREWALL\\bin\\cache\\) and how many folders are left before the SERVICE.",
          "Folders are real fights now: crowds arrive in waves inside the room instead of one burst."),
        es: points(
          "Cada sector es ahora un camino de carpetas hacia delante que termina en el SERVICIO del sector. Se acabaron las llaves, la brújula, el mapa, la sala del tesoro y volver por salas vacías.",
          "Limpia una carpeta y su recompensa aparece en el centro de la sala. Recógela y se abren 2 o 3 salidas, cada una con la carpeta a la que lleva y lo que paga: /bin mejora, /updates parche, /cache créditos, /restore reparación, /shards Fragmentos, /pkg puestos, /quarantine combate élite.",
          "Elegir puerta es elegir tu build. El panel de estado muestra tu camino como una ruta (C:\\FIREWALL\\bin\\cache\\) y cuántas carpetas quedan hasta el SERVICIO.",
          "Las carpetas ahora son combates de verdad: las multitudes llegan en oleadas dentro de la sala en vez de en una sola ráfaga.")),
      ChangelogEntry(category: clcNew,
        headEn: "Patches replace relics",
        headEs: "Los parches sustituyen a las reliquias",
        en: points(
          "Relics are now Patches: numbered system updates like KB-3101 Overclock. /updates and /quarantine folders offer 3 and you apply 1. Walk up to one to read what it does.",
          "11 new patches that change how a run plays, including Overclock, Firewall Rule, Rollback, Cron Job, Zip Bomb, RAID 1 Mirroring and Packet Loss.",
          "Your applied patches show as icons on the status panel, dimmed while one is spent (a used Rollback, a stalled Overclock).",
          "Type recovery in the Help terminal for the full list."),
        es: points(
          "Las reliquias ahora son Parches: actualizaciones del sistema numeradas como KB-3101 Overclock. Las carpetas /updates y /quarantine ofrecen 3 y aplicas 1. Acércate a uno para leer lo que hace.",
          "11 parches nuevos que cambian cómo se juega una partida, entre ellos Overclock, Regla de Firewall, Reversión, Tarea Cron, Bomba Zip, Espejo RAID 1 y Pérdida de Paquetes.",
          "Tus parches aplicados aparecen como iconos en el panel de estado, atenuados mientras uno está gastado (una Reversión usada, un Overclock detenido).",
          "Escribe recovery en la terminal de Ayuda para ver la lista completa.")),
      ChangelogEntry(category: clcNew,
        headEn: "Package stalls",
        headEs: "Puestos de paquetes",
        en: points(
          "The roguelite shop is now the /pkg folder: priced stalls in the room selling specific power-ups, a patch, a repair and a restock.",
          "Walk up to a stall to see what it is and what it costs, then press E to buy. The wave-mode upgrade shop no longer appears in the roguelite."),
        es: points(
          "La tienda del roguelite ahora es la carpeta /pkg: puestos con precio en la propia sala que venden mejoras concretas, un parche, una reparación y una reposición.",
          "Acércate a un puesto para ver qué es y cuánto cuesta, y pulsa E para comprar. La tienda de mejoras del modo oleadas ya no aparece en el roguelite.")),
      ChangelogEntry(category: clcNew,
        headEn: "Dash",
        headEs: "Impulso",
        en: points(
          "Tap Shift (LT on a controller) for a short burst of speed in the direction you are moving. 2.5 second cooldown, available from wave 1.",
          "It gives no invulnerability: it gets you out of the way, it does not let you pass through a hit.",
          "A ring around your character refills as the dash recharges, and the status panel shows a DASH timer.",
          "Rebind it in Settings > Controls."),
        es: points(
          "Pulsa Shift (LT en el mando) para un empujón corto de velocidad en la dirección en la que te mueves. 2.5 segundos de recarga, disponible desde la oleada 1.",
          "No da invulnerabilidad: te aparta del peligro, pero no te deja atravesar un golpe.",
          "Un anillo alrededor de tu personaje se rellena mientras se recarga, y el panel de estado muestra un temporizador de IMPULSO.",
          "Reasígnalo en Ajustes > Controles.")),
      ChangelogEntry(category: clcNew,
        headEn: "Wave mode: experience and level-ups",
        headEs: "Modo oleadas: experiencia y niveles",
        en: points(
          "Every enemy drops experience orbs. Filling the bar on the HUD gives you a power-up draft, roughly once per wave.",
          "Levels get more expensive as the run goes on: about 20 levels over 60 waves.",
          "The old between-wave power-up draft now only appears in the run-up to each boss.",
          "Time Survival keeps its levelling pace. The roguelite has its own curve."),
        es: points(
          "Todos los enemigos sueltan orbes de experiencia. Al llenar la barra del HUD eliges una mejora, más o menos una vez por oleada.",
          "Los niveles se encarecen a medida que avanza la partida: unos 20 niveles en 60 oleadas.",
          "La antigua elección de mejora entre oleadas ahora solo aparece antes de cada jefe.",
          "Supervivencia mantiene su ritmo de niveles. El roguelite tiene su propia curva.")),
      ChangelogEntry(category: clcNew,
        headEn: "Wave mode: restore points",
        headEs: "Modo oleadas: puntos de restauración",
        en: points(
          "Continuing after a death now spends a restore point: unlimited on Easy, 3 on Normal, 1 on Hard, none on Nightmare.",
          "The pause menu, death screen and victory screen show how many you have left. The meter turns red on your last one.",
          "A spent point stays spent, even if you die again or resume the run from the desktop. With none left, Continue disappears.",
          "Endless play after wave 60 has no restore points: one death ends the run, and the screens now say so."),
        es: points(
          "Continuar tras una muerte ahora gasta un punto de restauración: ilimitados en Fácil, 3 en Normal, 1 en Difícil y ninguno en Pesadilla.",
          "El menú de pausa, la pantalla de muerte y la de victoria muestran cuántos te quedan. El medidor se pone rojo cuando te queda el último.",
          "Un punto gastado no se recupera, aunque vuelvas a morir o retomes la partida desde el escritorio. Sin puntos, la opción Continuar desaparece.",
          "El modo infinito tras la oleada 60 no tiene puntos de restauración: una muerte termina la partida, y ahora las pantallas lo indican.")),
      ChangelogEntry(category: clcNew,
        headEn: "Data Shards and Cores in every mode",
        headEs: "Fragmentos y Núcleos en todos los modos",
        en: points(
          "Wave mode and Time Survival now earn Data Shards and Cores for the cosmetic shop, not just Roguelite.",
          "Wave mode pays shards for every wave cleared and a bigger bounty for every boss. Cores start with the wave 15 boss. A full 60-wave run pays about 600 shards and 22 Cores.",
          "Time Survival pays shards for every minute survived, plus the same boss bounties: about 365 shards and 15 Cores in 15 minutes.",
          "Rewards are banked the moment you earn them, so quitting or a crash never loses them. The end screens show what you banked.",
          "Runs that used the cheat menu no longer earn permanent rewards in any mode: no shards, Cores, records or advancement progress."),
        es: points(
          "El modo oleadas y Supervivencia ahora dan Fragmentos y Núcleos para la tienda de cosméticos, no solo el Roguelite.",
          "El modo oleadas paga fragmentos por cada oleada superada y una recompensa mayor por cada jefe. Los Núcleos empiezan con el jefe de la oleada 15. Una partida completa de 60 oleadas da unos 600 fragmentos y 22 Núcleos.",
          "Supervivencia paga fragmentos por cada minuto sobrevivido, más las mismas recompensas por jefe: unos 365 fragmentos y 15 Núcleos en 15 minutos.",
          "Las recompensas se guardan en cuanto las ganas, así que salir o un cierre inesperado nunca te las quita. Las pantallas finales muestran lo ganado.",
          "Las partidas en las que se usó el menú de trucos ya no dan recompensas permanentes en ningún modo: ni fragmentos, ni Núcleos, ni récords, ni progreso de logros.")),
      ChangelogEntry(category: clcNew,
        headEn: "Interface scale",
        headEs: "Escala de interfaz",
        en: points(
          "A new Interface tab in Settings has three UI sizes: Small (70%), Default (100%) and Big (130%).",
          "It resizes the desktop, every window, the in-game HUD and all in-game menus together. A window never grows past the edge of the screen.",
          "In widescreen the side HUD bands widen with it and the arena shrinks slightly, so a bigger HUD never covers the fight."),
        es: points(
          "Una nueva pestaña Interfaz en Ajustes tiene tres tamaños: Pequeña (70%), Normal (100%) y Grande (130%).",
          "Ajusta a la vez el escritorio, todas las ventanas, el HUD y todos los menús de la partida. Ninguna ventana crece más allá del borde de la pantalla.",
          "En panorámico las bandas laterales del HUD se ensanchan con ella y la arena se reduce un poco, así que un HUD más grande nunca tapa el combate.")),
      ChangelogEntry(category: clcNew,
        headEn: "Damage number and screen shake settings",
        headEs: "Ajustes de números de daño y vibración",
        en: points(
          "Damage numbers can be turned off or sized from 60% to 160%. Screen shake goes from 0% (off) to 150%.",
          "The switches for enemy labels, vignettes, the FPS counter and the debug panel moved to the same tab."),
        es: points(
          "Los números de daño se pueden desactivar o ajustar del 60% al 160%. La vibración de pantalla va del 0% (apagada) al 150%.",
          "Los interruptores de etiquetas de enemigos, viñetas, contador de FPS y panel de depuración se han movido a la misma pestaña.")),
      ChangelogEntry(category: clcNew,
        headEn: "Healing breakdown in the stats window",
        headEs: "Desglose de curación en las estadísticas",
        en: points(
          "The Power-Ups tab now has three columns: what you picked, what dealt damage, and what healed you.",
          "Every healing source is ranked with its share of the total, including health pickups and level-ups.",
          "The grey part of each row is overheal: healing that landed on a full bar. Hover a row for the exact numbers.",
          "All three columns scroll with the mouse wheel, so long runs are no longer cut off."),
        es: points(
          "La pestaña Mejoras tiene ahora tres columnas: lo que elegiste, lo que hizo daño y lo que te curó.",
          "Cada fuente de curación aparece ordenada con su parte del total, incluidos los objetos de vida y las subidas de nivel.",
          "La parte gris de cada fila es la sobrecuración: lo que se curó con la barra ya llena. Pasa el ratón por una fila para ver las cifras exactas.",
          "Las tres columnas se desplazan con la rueda del ratón, así que las partidas largas ya no quedan cortadas.")),
      ChangelogEntry(category: clcNew,
        headEn: "Tutorial: ORIENTATION.EXE",
        headEs: "Tutorial: ORIENTACIÓN.EXE",
        en: points(
          "Your first wave run now opens with a short hands-on tutorial: moving, aiming and firing, the dash, a few practice enemies, loot, the status panel and walls. Wave 1 waits until it is done.",
          "Every prompt shows your own key bindings, or controller buttons when you play with a pad.",
          "Hold Tab (Select on a controller) at any time to skip it.",
          "Nothing from it carries into the run: credits, XP, kills, walls and HP all reset when wave 1 starts, whether you finish it or skip it.",
          "Replay it whenever you like from Settings > Gameplay. The replay is a practice session: it never touches your saved run, stats or rewards, and it returns you to the desktop when it ends.",
          "Profiles that have already played wave mode are not made to sit through it."),
        es: points(
          "Tu primera partida de oleadas empieza ahora con un tutorial corto y práctico: moverte, apuntar y disparar, el impulso, unos enemigos de práctica, el botín, el panel de estado y los muros. La oleada 1 espera a que termine.",
          "Cada indicación muestra tus propias teclas, o los botones del mando si juegas con uno.",
          "Mantén Tab (Select en el mando) en cualquier momento para saltarlo.",
          "Nada de él pasa a la partida: los créditos, la XP, las eliminaciones, los muros y el HP se reinician al empezar la oleada 1, tanto si lo terminas como si lo saltas.",
          "Repítelo cuando quieras desde Ajustes > Juego. La repetición es una sesión de práctica: nunca toca tu partida guardada, tus estadísticas ni tus recompensas, y te devuelve al escritorio al terminar.",
          "Los perfiles que ya han jugado al modo oleadas no tienen que pasar por él.")),
      ChangelogEntry(category: clcNew,
        headEn: "Boss lore: the hijacked services",
        headEs: "Historia de los jefes: los servicios secuestrados",
        en: points(
          "Every boss is now part of the story. The first eleven are TOPHAT's own system services that the Root took over: the Summoner King was the process scheduler, the Timekeeper was the system clock, the Chaos Weaver was the entropy pool.",
          "The Omega Entity is the Root itself, wearing every service it stole.",
          "The boss intro card names the service each boss was made from, and each boss has a new description that still hints at how it fights."),
        es: points(
          "Cada jefe forma parte ahora de la historia. Los once primeros son servicios del propio sistema de TOPHAT que la Raíz tomó: el Rey Invocador era el planificador de procesos, el Cronómetra era el reloj del sistema, el Tejedor del Caos era la reserva de entropía.",
          "La Entidad Omega es la propia Raíz, vistiendo cada servicio que robó.",
          "La tarjeta de presentación de cada jefe nombra el servicio del que salió, y cada jefe tiene una descripción nueva que sigue dando pistas de cómo lucha.")),
      ChangelogEntry(category: clcNew,
        headEn: "Incident archive",
        headEs: "Archivo del incidente",
        en: points(
          "Type 'lore' in the Help terminal to read the story so far, one case file per act.",
          "Act I is always open. The other three decrypt as you unlock their ending cinematics, and a sealed file tells you how to recover it.",
          "The 'bosses' command now lists the hijacked service behind every boss."),
        es: points(
          "Escribe 'lore' en la terminal de Ayuda para leer la historia hasta ahora, un expediente por acto.",
          "El Acto I siempre está abierto. Los otros tres se descifran al desbloquear sus cinemáticas finales, y un expediente sellado te dice cómo recuperarlo.",
          "El comando 'bosses' ahora muestra el servicio secuestrado detrás de cada jefe.")),
      ChangelogEntry(category: clcNew,
        headEn: "PvP: dash, kill feed and callouts",
        headEs: "PvP: impulso, registro de bajas y anuncios",
        en: points(
          "The dash from the other modes now works in PvP, with the same key and the same cooldown ring on your body. It is predicted on your screen and confirmed by the host, so it never snaps you back mid-dodge.",
          "Landing a hit gives you a hit marker and a confirm sound, and a kill gives a bigger red one. Getting hit shakes the screen and flashes the edges red, and they pulse while you are on your last third of health.",
          "A kill feed in the top right shows who took down whom, plus centre package grabs and players who leave.",
          "Callouts named after the system: FIRST CRASH for the first kill, DOUBLE FAULT and TRIPLE FAULT for quick multi kills, PRIVILEGE ESCALATION, ROOT ACCESS and KERNEL MODE for kill streaks, and SHUTDOWN for ending one. Anyone on a streak of 3 or more wears a gold # before their name.",
          "Your walls refill every time you respawn, and the respawn screen tells you who terminated you. The Shoot key now fires in PvP too, and the countdown shows the dash, wall and scoreboard keys."),
        es: points(
          "El impulso de los otros modos ahora funciona en PvP, con la misma tecla y el mismo anillo de recarga en tu cuerpo. Se predice en tu pantalla y lo confirma el anfitrión, así que nunca te devuelve atrás a mitad de esquiva.",
          "Acertar un disparo muestra una marca de impacto con sonido de confirmación, y una baja muestra una roja más grande. Recibir daño sacude la pantalla y tiñe los bordes de rojo, que laten mientras te queda el último tercio de vida.",
          "Un registro de bajas arriba a la derecha muestra quién eliminó a quién, además de los paquetes centrales recogidos y los jugadores que se van.",
          "Anuncios con nombres del sistema: PRIMER CRASH para la primera baja, DOBLE FALLO y TRIPLE FALLO para bajas seguidas, ESCALADA DE PRIVILEGIOS, ACCESO ROOT y MODO KERNEL para las rachas, y APAGADO por cortar una. Quien lleve una racha de 3 o más lleva un # dorado antes de su nombre.",
          "Tus muros se recargan cada vez que reapareces, y la pantalla de reaparición te dice quién te terminó. La tecla de Disparar ahora también dispara en PvP, y la cuenta atrás muestra las teclas de impulso, muro y marcador.")),
      ChangelogEntry(category: clcNew,
        headEn: "PvP: arena packages",
        headEs: "PvP: paquetes en la arena",
        en: points(
          "Five ports on the arena floor drop packages. The four outer ports roll CHKDSK.EXE (heals a third of your health), FIREWALL.SYS (blocks the next hit) or TURBO.DLL (40% faster for 5 seconds).",
          "The centre port is the one worth fighting over: its first drop lands 20 seconds in, then every 25 seconds, with OVERCLOCK.SYS (double fire rate for 6 seconds) or FORK.EXE (triple shot for 8 seconds, side bullets deal half damage).",
          "Each port shows a flickering INCOMING preview of its next package 3 seconds before it lands, so you can be there first. Your active effects show as timed pills above the wall counter.",
          "The host can turn packages off in the match settings."),
        es: points(
          "Cinco puertos en el suelo de la arena sueltan paquetes. Los cuatro exteriores sortean CHKDSK.EXE (cura un tercio de tu vida), FIREWALL.SYS (bloquea el próximo impacto) o TURBO.DLL (40% más rápido durante 5 segundos).",
          "El puerto central es el que vale la pena disputar: su primer paquete cae a los 20 segundos y luego cada 25, con OVERCLOCK.SYS (cadencia doble durante 6 segundos) o FORK.EXE (disparo triple durante 8 segundos, las balas laterales hacen la mitad de daño).",
          "Cada puerto muestra una vista previa parpadeante ENTRANTE de su próximo paquete 3 segundos antes de que caiga, para que llegues primero. Tus efectos activos aparecen como píldoras con tiempo encima del contador de muros.",
          "El anfitrión puede desactivar los paquetes en la configuración de la partida.")),
      ChangelogEntry(category: clcNew,
        headEn: "PvP: process table and rematch",
        headEs: "PvP: tabla de procesos y revancha",
        en: points(
          "Hold Tab (Select on a controller) during a match to see everyone's kills, deaths and current streak.",
          "The end screen shows the full process table: kills, deaths, best streak, accuracy and damage, grouped by team in team matches, plus awards for the best accuracy, the fewest deaths, the most packages and the longest uptime.",
          "The host can press Enter (A on a controller) to start a rematch with the same lobby. Nobody has to host or join again."),
        es: points(
          "Mantén Tab (Select en mando) durante la partida para ver las bajas, muertes y racha actual de todos.",
          "La pantalla final muestra la tabla de procesos completa: bajas, muertes, mejor racha, precisión y daño, agrupada por equipo en las partidas por equipos, más premios a la mejor precisión, a menos muertes, a más paquetes y al mayor uptime.",
          "El anfitrión puede pulsar Enter (A en mando) para empezar una revancha con la misma sala. Nadie tiene que volver a crear ni unirse a la partida.")),

      # --- Improvements ---
      ChangelogEntry(category: clcImproved,
        headEn: "Help and Sandbox cover every roster",
        headEs: "Ayuda y Sandbox cubren todos los repertorios",
        en: points(
          "The enemies and bosses pages in the Help terminal now list the wave, survival and roguelite rosters separately, with the tag each boss answers to.",
          "The Sandbox spawn lists include every new enemy and boss, and Deadlocks spawn there as pairs."),
        es: points(
          "Las páginas de enemigos y jefes de la terminal de Ayuda ahora separan los repertorios de oleadas, supervivencia y roguelite, con la etiqueta de cada jefe.",
          "Las listas del Sandbox incluyen todos los enemigos y jefes nuevos, y los Interbloqueos aparecen allí en parejas.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Roguelite: everything playable from the first run",
        headEs: "Roguelite: todo disponible desde la primera partida",
        en: points(
          "All power-up families and all three boot profiles (Operator, Bulwark, Arcanist) are available from your first run. The roguelite unlock shop is gone.",
          "Heat is earned: win a run at your highest Heat to unlock the next one.",
          "Everything you had bought in the old unlock shop is refunded as Data Shards and Cores the first time you load your profile. Heat you already had stays unlocked.",
          "Data Shards and Cores keep buying cosmetics in the desktop shop."),
        es: points(
          "Todas las familias de mejoras y los tres perfiles de arranque (Operador, Baluarte, Arcanista) están disponibles desde tu primera partida. La tienda de desbloqueos del roguelite ha desaparecido.",
          "El Calor se gana: gana una partida con tu Calor más alto para desbloquear el siguiente.",
          "Todo lo que compraste en la antigua tienda de desbloqueos se te devuelve en Fragmentos y Núcleos la primera vez que cargas tu perfil. El Calor que ya tenías sigue desbloqueado.",
          "Los Fragmentos y Núcleos siguen comprando cosméticos en la tienda del escritorio.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Roguelite speaks the OS",
        headEs: "El roguelite habla el idioma del SO",
        en: points(
          "Floors are sectors, rooms are folders, bosses are the sector's SERVICE, and the setup screen is Deep Recovery.",
          "The BETA banner is gone.",
          "The crash screen now shows the sector you reached, folders cleared, patches applied and the Data Shards and Cores the run banked.",
          "The victory screen lists your patches with their icons and what this run paid out."),
        es: points(
          "Los pisos ahora son sectores, las salas son carpetas, los jefes son el SERVICIO del sector y la pantalla de ajuste es Recuperación Profunda.",
          "El cartel de BETA ha desaparecido.",
          "La pantalla de fallo ahora muestra el sector alcanzado, las carpetas limpiadas, los parches aplicados y los Fragmentos y Núcleos que guardó la partida.",
          "La pantalla de victoria muestra tus parches con sus iconos y lo que pagó esta partida.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Berserker Juggernaut rework",
        headEs: "Rediseño del Berserker Imparable",
        en: points(
          "Its charges are real charges now: fast, aimed a little ahead of where you are moving, and they hit for full damage on contact.",
          "Watch the three chevrons in front of it. They follow you, then freeze and flash white: that is your cue to turn out of the lane or dash. With hints on, the lane is outlined too.",
          "Double and triple charges re-aim between each run, and your dash will not be back for all of them, so at least one has to be dodged on foot.",
          "Charges no longer leave bullets in their lane. After the last one it stands winded for a moment with its armor cracked open."),
        es: points(
          "Sus embestidas ahora son de verdad: rápidas, apuntadas un poco por delante de hacia donde te mueves, y golpean con todo su daño al contacto.",
          "Fíjate en las tres flechas delante de él. Te siguen, y luego se congelan y destellan en blanco: esa es tu señal para salir del carril o impulsarte. Con las pistas activadas, el carril también se marca.",
          "Las embestidas dobles y triples reapuntan entre cada carrera, y tu impulso no estará listo para todas, así que al menos una hay que esquivarla a pie.",
          "Las embestidas ya no dejan balas en su carril. Tras la última se queda sin aliento un momento con la armadura agrietada.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Summoner King rework",
        headEs: "Rediseño del Rey Invocador",
        en: points(
          "Each summon raises a crowd of a dozen or more one-hit legionnaires, with big, gold, crowned Royal Guards among them.",
          "Only the Royal Guards keep the King sealed (gold chains link them to it), and only they fire the Legion Volley. Kill the guards to open the King up.",
          "The opening after the last guard falls lasts longer and you deal more damage during it. An ignored crowd is topped up instead of piling up forever.",
          "Phase 2: the legion rises in a ring around you while the guards gather by the King, so you have to cut your way out first. The ring never spawns on top of you."),
        es: points(
          "Cada invocación alza una multitud de una docena o más de legionarios que caen de un golpe, con grandes Guardias Reales dorados y coronados entre ellos.",
          "Solo la Guardia Real mantiene sellado al Rey (unas cadenas doradas los unen a él) y solo ella lanza la Descarga de la Legión. Abate a los guardias para dejar expuesto al Rey.",
          "La ventana tras caer el último guardia dura más y en ella haces más daño. Una multitud ignorada se repone en vez de acumularse sin fin.",
          "Fase 2: la legión se alza en un anillo a tu alrededor mientras la guardia se reúne junto al Rey, así que primero hay que abrirse paso. El anillo nunca aparece encima de ti.")),
      ChangelogEntry(category: clcImproved,
        headEn: "A defeated boss takes its attacks with it",
        headEs: "Un jefe derrotado se lleva sus ataques",
        en: points(
          "When a boss dies, a wave spreads out from it and erases its bullets, beams, meteors and pending attacks.",
          "Everything it fired is harmless from the moment it dies, so a bullet from a boss you already beat can no longer end your run."),
        es: points(
          "Cuando muere un jefe, una onda sale de él y borra sus balas, rayos, meteoritos y ataques pendientes.",
          "Todo lo que disparó es inofensivo desde el momento en que muere, así que una bala de un jefe ya vencido ya no puede acabar con tu partida.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Hits have weight",
        headEs: "Los golpes pesan",
        en: points(
          "Kills freeze the game for a few frames, elites a little longer, and a boss kill gets a heavy freeze followed by slow motion. Taking a hit freezes briefly too.",
          "Screen shake is about 3.5x stronger across the board. You can turn it down in Settings > Interface."),
        es: points(
          "Matar congela el juego unos fotogramas, las élites algo más, y matar a un jefe da un congelado fuerte seguido de cámara lenta. Recibir un golpe también congela un instante.",
          "La vibración de pantalla es unas 3.5 veces más fuerte en general. Puedes bajarla en Ajustes > Interfaz.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Damage numbers fan out",
        headEs: "Los números de daño se abren en abanico",
        en: points(
          "Floating numbers (damage, healing, coins, experience, pickups) now spray in different directions instead of stacking into one unreadable column.",
          "Critical hits stay close to the target. Numbers pop in large and stay fully bright for the first half of their life."),
        es: points(
          "Los números flotantes (daño, curación, monedas, experiencia, objetos) ahora salen en distintas direcciones en vez de apilarse en una columna ilegible.",
          "Los críticos se quedan cerca del objetivo. Los números aparecen grandes y mantienen todo su brillo durante la primera mitad de su vida.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Faster power-up draft",
        headEs: "Selección de mejoras más rápida",
        en: points(
          "A normal draft settles in about 1 second instead of 3.5, and a legendary one in about 2.5 seconds instead of 4.5.",
          "Press any key or click while the reel spins to skip straight to the result."),
        es: points(
          "Una tirada normal se detiene en 1 segundo aprox. en vez de 3.5, y una legendaria en unos 2.5 segundos en vez de 4.5.",
          "Pulsa cualquier tecla o haz clic mientras gira para ir directo al resultado.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Smoother level-ups",
        headEs: "Subidas de nivel más suaves",
        en: points(
          "LEVEL UP shows first and you keep playing for a moment before the draft opens, so it never lands mid-dodge.",
          "After you pick, time ramps back up from slow motion, you get a moment of invulnerability, and a ring pulses on your character so you can find yourself."),
        es: points(
          "Primero aparece SUBIÓ DE NIVEL y sigues jugando un instante antes de que se abra la selección, así que nunca te pilla a mitad de un esquive.",
          "Al elegir, el tiempo vuelve poco a poco desde cámara lenta, tienes un momento de invulnerabilidad y un anillo late sobre tu personaje para que te encuentres.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Loot comes to you",
        headEs: "El botín viene a ti",
        en: points(
          "The pickup range is much wider, and coins and orbs speed up as they fly in, so they no longer trail behind a fast player.",
          "The Magnet consumable still pulls from anywhere on the field."),
        es: points(
          "El alcance de recogida es mucho mayor, y monedas y orbes aceleran al acercarse, así que ya no se quedan atrás si vas rápido.",
          "El consumible Imán sigue atrayendo desde cualquier punto del campo.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Volatile shows its work",
        headEs: "Volátil enseña lo que hace",
        en: points(
          "Enemies carrying 2+ elements (the ones Volatile boosts) wear a ring of arcs in their elements' colors.",
          "The death pulse now shows its radius and what it spreads, with arcs to each enemy it infects."),
        es: points(
          "Los enemigos con 2 o más elementos (los que Volátil potencia) llevan un anillo de arcos con los colores de sus elementos.",
          "El pulso al morir ahora muestra su radio y lo que propaga, con arcos hacia cada enemigo que contagia.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Redrawn icons",
        headEs: "Iconos redibujados",
        en: points(
          "Every power-up icon and shop icon has been redrawn with a dark outline, so it stays readable on any background.",
          "This also removes the stray magenta and lime streaks on the old icons, and the pieces that never drew, like half of the heart and the rocket's fins.",
          "Shop upgrades now sit on app-style tiles in their slot's color."),
        es: points(
          "Todos los iconos de mejoras y de la tienda se han redibujado con un contorno oscuro, para que se lean bien sobre cualquier fondo.",
          "También desaparecen las rayas magenta y verde lima de los iconos antiguos, y las partes que nunca se dibujaban, como la mitad del corazón o las aletas del cohete.",
          "Las mejoras de la tienda aparecen ahora sobre casillas tipo app del color de su ranura.")),
      ChangelogEntry(category: clcImproved,
        headEn: "First launch about 8x faster",
        headEs: "Primer arranque unas 8 veces más rápido",
        en: points(
          "The music built on first launch is now generated on every CPU core: under 2 seconds instead of about 13.",
          "The result is identical, so music you already have cached is kept."),
        es: points(
          "La música que se crea en el primer arranque ahora se genera en todos los núcleos de la CPU: menos de 2 segundos en vez de unos 13.",
          "El resultado es idéntico, así que la música que ya tengas en caché se conserva.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Opening cinematic and mode intros rebuilt",
        headEs: "Cinemática inicial e introducciones de modo rehechas",
        en: points(
          "The opening cinematic now shows what it says: an unknown host tears through a TopHat-ShooterOS window, the flood pours out and corrupts your actual desktop icons, the caged kernel beams you into existence, and the Root seizes TOPHAT's eleven services one by one.",
          "Wave mode opens on a radar sweep that finds the eleven hijacked services you will face as bosses.",
          "Roguelite opens with a real fall through the sector stack, past every floor theme, toward the rot at the bottom.",
          "PvP gets a third shot, a duel over one contested link, and Sandbox gets a second shot showing how it really works: click a process in the spawn list and it walks in from the edge of the screen."),
        es: points(
          "La cinemática inicial ahora muestra lo que cuenta: un host desconocido rasga una ventana de TopHat-ShooterOS, la marea se derrama y corrompe los iconos reales de tu escritorio, el kernel enjaulado te trae a la existencia con un haz y la Raíz se apodera uno a uno de los once servicios de TOPHAT.",
          "El modo oleadas abre con un barrido de radar que encuentra los once servicios secuestrados que enfrentarás como jefes.",
          "El roguelite abre con una caída real a través de la pila de sectores, pasando por cada tema de piso, hacia la podredumbre del fondo.",
          "El PvP suma una tercera toma, un duelo por un único enlace disputado, y el Sandbox suma una segunda toma que muestra cómo funciona de verdad: haz clic en un proceso de la lista y entra caminando desde el borde de la pantalla.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Cinematics polish",
        headEs: "Cinemáticas pulidas",
        en: points(
          "Every cinematic plays about 20% faster. Fast forward still doubles that.",
          "Captions in every cinematic now type out like a terminal log, with a blinking cursor.",
          "Controllers can drive every cinematic: hold A to play at 2x, hold B to skip. The on-screen hint switches to your pad's buttons.",
          "The Time Survival intro has been restaged. Its countdown made no sense for a mode that never ends, so it now opens on an uptime clock counting up while the swarm gathers, then a watch log that just keeps going.",
          "Story lines were tightened so the acts connect: the intro now warns that every service the Root touches turns on you, and the ending shows those services coming back online."),
        es: points(
          "Todas las cinemáticas se reproducen un 20% más rápido. El avance rápido sigue duplicando esa velocidad.",
          "Los subtítulos de todas las cinemáticas ahora se escriben como un registro de terminal, con un cursor parpadeante.",
          "El mando controla todas las cinemáticas: mantén A para verlas a x2 y mantén B para saltarlas. La indicación en pantalla muestra los botones de tu mando.",
          "La introducción de Supervivencia por Tiempo se ha rehecho. Su cuenta regresiva no tenía sentido en un modo que nunca termina, así que ahora abre con un reloj de actividad que sube mientras se reúne el enjambre, y después un registro de vigilia que no se detiene.",
          "Se ajustaron las frases de la historia para que los actos conecten: la introducción ahora avisa de que cada servicio que toca la Raíz se vuelve contra ti, y el final muestra esos servicios volviendo a estar en línea.")),
      ChangelogEntry(category: clcImproved,
        headEn: "Clearer boss intro card",
        headEs: "Tarjeta de jefe más legible",
        en: "The card now reaches full brightness right away instead of only as it vanished, stays up a little longer, and wraps long descriptions evenly.",
        es: "La tarjeta ahora alcanza su brillo máximo al instante en vez de justo al desaparecer, dura un poco más y reparte las descripciones largas en líneas equilibradas."),

      # --- Balance ---
      ChangelogEntry(category: clcBalance,
        headEn: "Roguelite pacing",
        headEs: "Ritmo del roguelite",
        en: points(
          "Folders field crowds on the same curve as wave mode, lighter in the first sector. Each enemy is tuned so a folder's total toughness stays close to before.",
          "The roguelite has its own level curve: about 3 to 4 levels per sector.",
          "Credits from kills and kill streaks are lower in the roguelite, so a /pkg visit is a choice rather than buying everything.",
          "SERVICE fights have 25% less HP to make up for the old stat shop.",
          "Draft Cache now makes the first reroll of every draft free. Emergency Patch now blocks the first hit in every SERVICE room and restores 25% integrity when you shut one down."),
        es: points(
          "Las carpetas traen multitudes con la misma curva que el modo oleadas, más ligeras en el primer sector. Cada enemigo se ajusta para que la dureza total de una carpeta se parezca a la de antes.",
          "El roguelite tiene su propia curva de niveles: unos 3 o 4 niveles por sector.",
          "Los créditos por bajas y rachas son menores en el roguelite, así que visitar /pkg es elegir en vez de comprarlo todo.",
          "Los combates de SERVICIO tienen un 25% menos de vida para compensar la antigua tienda de estadísticas.",
          "Caché de Instalación ahora hace gratis el primer reroll de cada elección. Parche de Emergencia ahora bloquea el primer golpe en cada sala de SERVICIO y restaura un 25% de integridad al apagar uno.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Waves are crowds",
        headEs: "Las oleadas son multitudes",
        en: points(
          "Waves bring about 4x as many enemies, each with a fraction of the health. Wave 40 went from about 35 enemies to around 120.",
          "Enemy health now grows much more slowly than your power, so a strong build really does tear through late waves.",
          "The challenge comes from numbers, elites and bosses instead. Cube Shooters are a bit rarer in waves 16-20."),
        es: points(
          "Las oleadas traen unas 4 veces más enemigos, cada uno con una fracción de la vida. La oleada 40 pasó de unos 35 enemigos a unos 120.",
          "La vida enemiga crece ahora mucho más despacio que tu poder, así que una build fuerte de verdad arrasa en las oleadas tardías.",
          "El reto viene ahora de la cantidad, las élites y los jefes. Los Tiradores son algo menos frecuentes en las oleadas 16-20.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Rewards are still paid per wave",
        headEs: "Las recompensas siguen siendo por oleada",
        en: points(
          "Coins, consumable drops and the elite chance are scaled to the size of the wave, so a wave pays about what it did before the crowds.",
          "Elites are rare again. They had grown to more than a fifth of all enemies.",
          "Healing per hit or per kill (Blood Bullets, Blood Aura, Life Steal) no longer grows with the crowd. Life Steal needs more kills rather than healing less.",
          "Cornucopia's jackpot needs more kills in bigger waves, so it fires at its intended rate. The jackpot itself is unchanged."),
        es: points(
          "Monedas, consumibles y probabilidad de élite se ajustan al tamaño de la oleada, así que una oleada paga más o menos lo mismo que antes de las multitudes.",
          "Las élites vuelven a ser raras. Habían llegado a ser más de una quinta parte de los enemigos.",
          "La curación por golpe o por muerte (Balas de Sangre, Aura de Sangre, Robo de Vida) ya no crece con la multitud. Robo de Vida pide más muertes en vez de curar menos.",
          "El premio de Cornucopia pide más muertes en oleadas grandes, así que salta al ritmo previsto. El premio en sí no cambia.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Enemies hit harder",
        headEs: "Los enemigos pegan más fuerte",
        en: points(
          "Enemy damage now scales properly with the waves. Late in a run, a hit used to cost only about 3% of your health bar.",
          "Enemy health still does not scale the same way: one-shotting enemies stays the reward for building up."),
        es: points(
          "El daño enemigo ahora escala como debe con las oleadas. Al final de una partida, un golpe apenas quitaba un 3% de tu barra de vida.",
          "La vida enemiga sigue sin escalar igual: borrarlos de un disparo sigue siendo la recompensa por hacerte fuerte.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Bosses are sturdier",
        headEs: "Los jefes son más duros",
        en: points(
          "Every boss except the Void Dancer has more health: +20% for the first four, +13% to +25% for the rest.",
          "The last five bosses (Berserker Juggernaut to Omega Entity) take about 10% to 25% less damage, depending on boss and phase. The Omega Phase is unchanged.",
          "Completing a boss mechanic still pays its full damage burst, so playing the mechanics is the fastest way through.",
          "The Prism Architect's final phase hits slightly softer, and the Chaos Weaver's final phase moves slightly faster."),
        es: points(
          "Todos los jefes salvo el Danzante del Vacío tienen más vida: +20% los cuatro primeros y entre +13% y +25% el resto.",
          "Los cinco últimos jefes (del Berserker Imparable a la Entidad Omega) reciben entre un 10% y un 25% menos de daño, según el jefe y la fase. La Fase Omega no cambia.",
          "Completar una mecánica de jefe sigue dando su ráfaga de daño completa, así que jugar las mecánicas es la forma más rápida de ganar.",
          "La fase final del Arquitecto Prisma pega un poco menos, y la fase final del Tejedor del Caos se mueve un poco más rápido.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Lasers and beams",
        headEs: "Láseres y rayos",
        en: points(
          "Standing in any laser or beam now hits you once every half second, for as long as you stay in it.",
          "The Orbital Commander's satellite lasers and the Cross Striker's spinning laser used to hit almost every frame. Boss beams that hit only once now hit again if you linger.",
          "The Orbital Commander deploys 4 laser satellites instead of 6 in its final phase, and its aimed volleys hold fire while an Orbital Scan wall is crossing."),
        es: points(
          "Estar dentro de cualquier láser o rayo ahora te golpea una vez cada medio segundo mientras sigas dentro.",
          "Los láseres de los satélites del Comandante Orbital y el láser giratorio del Embistidor golpeaban casi en cada fotograma. Los rayos de jefe que solo golpeaban una vez ahora vuelven a golpear si te quedas dentro.",
          "El Comandante Orbital despliega 4 satélites láser en vez de 6 en su fase final, y sus descargas apuntadas esperan mientras cruza un muro del Escaneo Orbital.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Momentum (legendary) rework",
        headEs: "Rediseño de Impulso (mejora legendaria)",
        en: points(
          "Momentum now builds stacks: one for every 0.5 seconds you keep moving at 60% or more of your base speed, up to 5.",
          "Each stack is +4% damage, so +20% at full stacks. It used to be up to +25%, and was almost always full.",
          "Slow down and, after a short grace period, you lose a stack every 0.5 seconds.",
          "At 5 stacks you also get +20% critical chance."),
        es: points(
          "La mejora legendaria Impulso ahora acumula cargas: una por cada 0.5 segundos que sigas moviéndote al 60% o más de tu velocidad base, hasta 5.",
          "Cada carga da +4% de daño, así que +20% con todas. Antes era hasta +25%, y casi siempre estaba al máximo.",
          "Si frenas, tras un breve margen pierdes una carga cada 0.5 segundos.",
          "Con 5 cargas también ganas +20% de probabilidad de crítico.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Power-up tuning",
        headEs: "Ajustes de mejoras",
        en: points(
          "Volatile: +30% bullet damage against enemies with 2+ elements (was +50%). Its death pulse is smaller and spreads elements at 40% strength and duration (was 60% and 50%).",
          "Blood Pact: costs 25% of your current HP (was 20%) and deals 1.25 bonus damage per HP sacrificed (was 2.5). The hit for 25% of each enemy's max HP is unchanged.",
          "Fortified: 5% / 10% / 15% damage reduction (was 10% / 20% / 30%). Its +250 / +500 / +750 max HP is unchanged."),
        es: points(
          "Volátil: +30% de daño de bala contra enemigos con 2 o más elementos (antes +50%). Su pulso al morir es más pequeño y propaga los elementos al 40% de fuerza y duración (antes 60% y 50%).",
          "Pacto de Sangre: cuesta el 25% de tu vida actual (antes 20%) e inflige 1.25 de daño extra por punto sacrificado (antes 2.5). El golpe del 25% de la vida máxima de cada enemigo no cambia.",
          "Fortificado: 5% / 10% / 15% de reducción de daño (antes 10% / 20% / 30%). Sus +250 / +500 / +750 de vida máxima no cambian.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Shop upgrades",
        headEs: "Mejoras de la tienda",
        en: points(
          "Max Health gives less and flattens out as you stack it: the first purchase gives about 30% less than before, seven purchases about a third less.",
          "Damage and Fire Rate were trimmed for deep stacks: with 10 purchases in each, your damage output is about 9% lower; with 20 in each, about 15% lower. A first purchase is worth about the same.",
          "Move speed, bullet speed and walls are unchanged."),
        es: points(
          "Vida Máxima da menos y se aplana al acumularla: la primera compra da un 30% menos que antes, y siete compras alrededor de un tercio menos.",
          "Daño y Cadencia bajan en inversiones grandes: con 10 compras de cada una tu daño es un 9% menor; con 20 de cada una, un 15% menor. Una primera compra vale casi lo mismo.",
          "Velocidad de movimiento, velocidad de bala y muros no cambian.")),
      ChangelogEntry(category: clcBalance,
        headEn: "Comeback bonus removed",
        headEs: "Se elimina la bonificación de regreso",
        en: "Starting a new Wave mode run after a death no longer grants +10% health, damage, speed, fire rate and bullet speed until you pass the wave you died on.",
        es: "Empezar una nueva partida del modo oleadas tras morir ya no da +10% de vida, daño, velocidad, cadencia y velocidad de bala hasta superar la oleada en la que moriste."),
      ChangelogEntry(category: clcBalance,
        headEn: "Octagon Sprayers no longer flood the screen",
        headEs: "Los Dispersadores ya no inundan la pantalla",
        en: points(
          "Octagon Sprayers fire every 0.5 seconds (was 0.4).",
          "Their slow shots now fade out after 3 seconds instead of 4. They still reach you from their usual distance, but misses no longer drift across the whole arena.",
          "Together this leaves about 40% fewer of their bullets on screen."),
        es: points(
          "Los Dispersadores disparan cada 0.5 segundos (antes 0.4).",
          "Sus balas lentas ahora se desvanecen tras 3 segundos en lugar de 4. Siguen alcanzándote desde su distancia habitual, pero las que fallan ya no cruzan toda la arena.",
          "En conjunto quedan alrededor de un 40% menos de sus balas en pantalla.")),

      # --- Fixes ---
      ChangelogEntry(category: clcFixed,
        headEn: "Regeneration no longer offered where it does nothing",
        headEs: "Regeneración ya no aparece donde no hace nada",
        en: "Regeneration heals when a wave or folder is cleared, so it had no effect in Time Survival and Sandbox, which have no waves. It is no longer offered in those modes.",
        es: "Regeneración cura al despejar una oleada o carpeta, así que no tenía efecto en Supervivencia ni en Sandbox, que no tienen oleadas. Ya no se ofrece en esos modos."),
      ChangelogEntry(category: clcFixed,
        headEn: "PvP: connection and result fixes",
        headEs: "PvP: correcciones de conexión y resultados",
        en: points(
          "A finished match no longer disconnects everyone after a couple of seconds on the result screen.",
          "A lost start or end signal no longer leaves a player stuck in the countdown, or still playing after the match ended.",
          "When the host played in Spanish, team matches ended as a draw on every other screen.",
          "A time limit that ends with a shared first place is now a draw instead of a win for one of the tied players.",
          "With respawn turned off, the match now ends when one side is left instead of waiting for the clock.",
          "Respawning no longer shows a 0 damage number, and half damage hits show 0.5 instead of 0. The host now sees damage numbers too.",
          "After you stop moving, your position smoothly settles onto the one the host checks hits against, so shots no longer land or miss by a gap you cannot see.",
          "In big free-for-all lobbies the score line no longer runs off the screen: it shows the top 3 and you.",
          "When the host leaves a match with 3 or more players, everyone else gets the result screen instead of a frozen arena."),
        es: points(
          "Una partida terminada ya no desconecta a todos tras un par de segundos en la pantalla de resultados.",
          "Perder la señal de inicio o de fin ya no deja a un jugador atascado en la cuenta atrás, o jugando después de que la partida terminó.",
          "Cuando el anfitrión jugaba en español, las partidas por equipos acababan en empate en todas las demás pantallas.",
          "Un límite de tiempo que acaba con el primer puesto compartido ahora es un empate, en lugar de una victoria para uno de los empatados.",
          "Con la reaparición desactivada, la partida ahora termina cuando queda un solo bando en vez de esperar al reloj.",
          "Reaparecer ya no muestra un número de daño 0, y los impactos de medio daño muestran 0.5 en vez de 0. El anfitrión ahora también ve los números de daño.",
          "Al dejar de moverte, tu posición se ajusta suavemente a la que el anfitrión usa para los impactos, así que los disparos ya no aciertan o fallan por una distancia invisible.",
          "En salas grandes de todos contra todos, la línea de puntuación ya no se sale de la pantalla: muestra a los 3 primeros y a ti.",
          "Cuando el anfitrión abandona una partida de 3 o más jugadores, los demás ven la pantalla de resultados en lugar de una arena congelada.")),
      ChangelogEntry(category: clcFixed,
        headEn: "Roguelite: experience from the last kills was banked late",
        headEs: "Roguelite: la experiencia de las últimas bajas llegaba tarde",
        en: "Clearing a folder now collects every orb before your level-ups are counted, so the final kills (and a SERVICE's big shower of orbs) count right away instead of a folder or a sector later.",
        es: "Limpiar una carpeta ahora recoge todos los orbes antes de contar tus subidas de nivel, así que las últimas bajas (y la gran lluvia de orbes de un SERVICIO) cuentan en el acto y no una carpeta o un sector después."),
      ChangelogEntry(category: clcFixed,
        headEn: "Roguelite: relic effects that did not work",
        headEs: "Roguelite: efectos de reliquias que no funcionaban",
        en: "Emergency Patch's shield charge disappeared a moment after it was granted, and the two reroll discounts did not match their descriptions. Both are fixed as part of the move to patches.",
        es: "La carga de escudo de Parche de Emergencia desaparecía justo después de darse, y los dos descuentos de reroll no coincidían con su descripción. Ambos se corrigen con el paso a parches."),
      ChangelogEntry(category: clcFixed,
        headEn: "Boss armor worked backwards for most damage types",
        headEs: "La armadura de los jefes funcionaba al revés",
        en: points(
          "Auras, damage over time, orbitals, chain lightning, explosions and thorns were multiplied by a boss's armor instead of reduced by it. The Omega Phase took 3x their damage.",
          "Conduit, Aftershock, Resonance and Giant Slayer skipped some or all boss resistances, including the seal from adds or shields.",
          "All damage now goes through the same boss resistances as bullets, which makes every boss noticeably sturdier against those builds."),
        es: points(
          "Auras, daño en el tiempo, orbitales, rayos en cadena, explosiones y espinas se multiplicaban por la armadura del jefe en vez de reducirse. La Fase Omega recibía el triple de su daño.",
          "Conducto, Réplica, Resonancia y Matador de Gigantes se saltaban parte o todas las resistencias de los jefes, incluido el sello de sus esbirros o su escudo.",
          "Ahora todo el daño pasa por las mismas resistencias que las balas, lo que hace a todos los jefes bastante más duros frente a esas builds.")),
      ChangelogEntry(category: clcFixed,
        headEn: "Damage and accuracy statistics",
        headEs: "Estadísticas de daño y precisión",
        en: points(
          "Damage Dealt and DPS now count every source (auras, damage over time, orbitals, explosions, thorns, abilities), not just bullets. So does the HUD's DPS readout.",
          "Accuracy no longer goes above 100% with piercing or ricochet builds, and the wave-clear screen no longer always shows 0% accuracy and FLAWLESS.",
          "An elemental mastery and the power-up it boosts no longer both take full credit for the same hit.",
          "Slow Field, ROOM_ECHO.dll and Blood Lord now get credit for their own damage and healing, and burn and poison ticks are credited to the right source."),
        es: points(
          "Daño Infligido y DPS cuentan ahora todas las fuentes (auras, daño en el tiempo, orbitales, explosiones, espinas, habilidades), no solo las balas. También el DPS del HUD.",
          "La precisión ya no pasa del 100% con builds perforantes o de rebote, y la pantalla de oleada superada ya no muestra siempre 0% de precisión e IMPECABLE.",
          "Una maestría elemental y la mejora que potencia ya no se llevan las dos todo el mérito del mismo golpe.",
          "Campo Lento, ECO_SALA.dll y Señor de Sangre reciben ahora el mérito de su propio daño y curación, y los tics de fuego y veneno se atribuyen a la fuente correcta.")),
      ChangelogEntry(category: clcFixed,
        headEn: "Run records",
        headEs: "Registros de partida",
        en: points(
          "Winning a run (the wave 60 victory, or cashing out a Roguelite run) is no longer recorded as a death.",
          "Dodged, blocked and absorbed hits no longer also count as damage taken, which broke hit counts and no-damage streaks. Near-death moments are no longer logged on every hit.",
          "Sandbox, PvP and the 3D boss no longer add to your Time Survival lifetime totals.",
          "Resumed runs no longer show inflated DPS and kills per minute.",
          "After a Continue, the power-up timeline drops the picks the rollback undid instead of listing them twice. Damage and healing done before the death still count."),
        es: points(
          "Ganar una partida (la victoria de la oleada 60, o cobrar una partida Roguelite) ya no se registra como una muerte.",
          "Los golpes esquivados, bloqueados o absorbidos ya no cuentan también como daño recibido, lo que rompía el conteo de golpes y las rachas sin daño. Los momentos al borde de la muerte ya no se registran en cada golpe.",
          "Sandbox, PvP y el jefe 3D ya no suman a tus totales permanentes de Supervivencia.",
          "Las partidas retomadas ya no muestran DPS ni muertes por minuto inflados.",
          "Tras Continuar, la línea de tiempo de mejoras descarta las elecciones que deshizo el retroceso en vez de listarlas dos veces. El daño y la curación anteriores a la muerte siguen contando.")),
      ChangelogEntry(category: clcFixed,
        headEn: "The power-up draft skipped itself",
        headEs: "La selección de mejoras se saltaba sola",
        en: "A shot or key still held when the draft opened could skip the reel and even pick a card. The draft now waits until you let go of the controls.",
        es: "Un disparo o una tecla aún pulsados al abrirse la selección podían saltarse la ruleta e incluso elegir una carta. Ahora espera a que sueltes los controles."),
      ChangelogEntry(category: clcFixed,
        headEn: "Kill slow motion never played",
        headEs: "La cámara lenta al matar nunca funcionaba",
        en: "It was switched on and never updated, so it did nothing. Time effects now work, and regular kills use a short freeze instead.",
        es: "Se activaba y nunca avanzaba, así que no hacía nada. Los efectos de tiempo ya funcionan, y las muertes normales usan un congelado corto."),
      ChangelogEntry(category: clcFixed,
        headEn: "Invisible experience orbs in Time Survival",
        headEs: "Orbes de experiencia invisibles en Supervivencia",
        en: "They dropped and were collected but never drawn, so level-ups seemed to come from nowhere. They are now visible in every mode.",
        es: "Caían y se recogían pero nunca se dibujaban, así que las subidas de nivel parecían salir de la nada. Ahora se ven en todos los modos."),
      ChangelogEntry(category: clcFixed,
        headEn: "Explosive Rounds hit the same enemy twice",
        headEs: "Balas Explosivas golpeaban dos veces al mismo enemigo",
        en: "The blast also damaged the enemy the bullet had just hit, adding another half hit on top. It now only damages the enemies around it.",
        es: "La explosión también dañaba al enemigo que la bala acababa de golpear, sumando otra media encima. Ahora solo daña a los enemigos de alrededor."),
      ChangelogEntry(category: clcFixed,
        headEn: "Level bar outside the status panel",
        headEs: "Barra de nivel fuera del panel de estado",
        en: "In Wave mode the level and experience bar could hang below the status panel. It now fits inside.",
        es: "En el modo oleadas la barra de nivel y experiencia podía salirse por debajo del panel de estado. Ahora cabe dentro."),
      ChangelogEntry(category: clcFixed,
        headEn: "Controls settings layout",
        headEs: "Diseño de los ajustes de Controles",
        en: points(
          "The fixed-key and reserved controller-button lists no longer run off the bottom of the panel.",
          "Keybind buttons, including Reset to Defaults, are clickable exactly where they are drawn."),
        es: points(
          "Las listas de teclas fijas y botones reservados del mando ya no se salen por debajo del panel.",
          "Los botones de asignación, incluido Restaurar Valores, se pulsan justo donde se dibujan.")),
      ChangelogEntry(category: clcFixed,
        headEn: "Overcharge had the wrong name in English",
        headEs: "Sobrecarga tenía el nombre equivocado en inglés",
        en: "It was listed as Momentum, the same name as the legendary. It is now called Overcharge.",
        es: "Aparecía como Momentum, el mismo nombre que la legendaria. Ahora se llama Overcharge."),
      ChangelogEntry(category: clcFixed,
        headEn: "Misleading quit warning",
        headEs: "Aviso de salida engañoso",
        en: "Quitting mid-run warned that unsaved progress would be lost, but your run is saved. The dialog now says so.",
        es: "Al salir a mitad de partida se avisaba de que el progreso no guardado se perdería, pero la partida se guarda. Ahora el diálogo lo dice."),
      ChangelogEntry(category: clcFixed,
        headEn: "Mode intros now open their mode",
        headEs: "Las introducciones de modo ya abren su modo",
        en: points(
          "The first time you opened Sandbox or PvP, its intro played and then dropped you back on the desktop, so you had to click the icon again. Every mode intro now carries on into its mode when it ends, or when you skip it.",
          "If you already had a saved run, Wave and Time Survival now offer to resume it after their intro instead of starting a new one."),
        es: points(
          "La primera vez que abrías Sandbox o PvP, su introducción se reproducía y te devolvía al escritorio, así que tenías que volver a hacer clic en el icono. Ahora cada introducción de modo continúa hacia su modo al terminar, o al saltarla.",
          "Si ya tenías una partida guardada, Oleadas y Supervivencia por Tiempo ahora ofrecen continuarla tras su introducción en vez de empezar una nueva.")),
      ChangelogEntry(category: clcFixed,
        headEn: "Intro cinematic in the wrong language",
        headEs: "Cinemática inicial en el idioma equivocado",
        en: "On a new profile, picking Spanish left the intro's tape labels and title card in English. They now follow the language you choose.",
        es: "En un perfil nuevo, elegir español dejaba en inglés las etiquetas de cinta y el título de la introducción. Ahora siguen el idioma que eliges."),
      ChangelogEntry(category: clcFixed,
        headEn: "Untranslated mode intro text",
        headEs: "Texto sin traducir en las introducciones",
        en: "The Sandbox intro's boot lines and the Roguelite intro's sector label are now translated.",
        es: "Las líneas de arranque de la introducción del Sandbox y la etiqueta de sector de la del Roguelite ahora están traducidas."),
      ChangelogEntry(category: clcFixed,
        headEn: "Help terminal cut off long output",
        headEs: "La terminal de Ayuda cortaba las salidas largas",
        en: "Scrolling to the bottom now always reaches the last line, even when long entries wrap, and text no longer runs under the scrollbar.",
        es: "Desplazarse hasta el final ahora siempre llega a la última línea, aunque las entradas largas ocupen varias líneas, y el texto ya no pasa por debajo de la barra de desplazamiento."),
      ChangelogEntry(category: clcFixed,
        headEn: "Exit prompt vanished on the game over screen",
        headEs: "El aviso de salida desaparecía en la pantalla de fin de partida",
        en: "Pressing Escape on the game over, victory or run stats screen flashed the exit confirmation for a single frame and closed it. It now stays open until you answer.",
        es: "Pulsar Escape en la pantalla de fin de partida, de victoria o de estadísticas de la partida mostraba la confirmación de salida un solo fotograma y la cerraba. Ahora permanece abierta hasta que respondas.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.2.2",
    titleEs: "Versión 6.2.2",
    subtitleEn: "Changes since v6.2.1",
    subtitleEs: "Cambios desde v6.2.1",
    latest: false,
    entries: @[
      # Tuning
      ChangelogEntry(category: clcBalance,
        en: "Giant Slayer hits harder across all three levels: it now shaves 3%, 5.5% and 8% of an enemy's current health per hit, up from 2.5%, 4% and 6%. Its much smaller bite against bosses is unchanged, so it stays a crowd-clearing pick rather than a boss melter.",
        es: "Matagigantes pega más fuerte en sus tres niveles: ahora arranca el 3%, 5.5% y 8% de la vida actual del enemigo por golpe, frente al 2.5%, 4% y 6% anteriores. Su mordisco mucho menor contra jefes no cambia, así que sigue siendo una elección para limpiar hordas y no para fundir jefes."),

      # Interface
      ChangelogEntry(category: clcImproved,
        en: "Confirmation dialogs stop making you wait. The YES button now unlocks after one second instead of two -- still long enough to catch an accidental key, short enough that quitting or resetting on purpose no longer feels like a punishment.",
        es: "Los diálogos de confirmación ya no te hacen esperar tanto. El botón SÍ se desbloquea tras un segundo en vez de dos: sigue siendo suficiente para frenar una tecla accidental, pero salir o reiniciar a propósito ya no se siente como un castigo."),

      # Fixes
      ChangelogEntry(category: clcFixed,
        en: "Fixed the background audio setup crashing the Windows release build on first launch. The progress counter used a threading instruction the Windows compiler builds incorrectly; it now uses a plain counter, so the first run generates its sounds and music without falling over.",
        es: "Corregido un fallo por el que la preparación de audio en segundo plano rompía la versión de Windows en el primer arranque. El contador de progreso usaba una instrucción de hilos que el compilador de Windows genera mal; ahora usa un contador normal, así que el primer arranque crea sus sonidos y su música sin caerse.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.2.1",
    titleEs: "Versión 6.2.1",
    subtitleEn: "Changes since v6.2",
    subtitleEs: "Cambios desde v6.2",
    latest: false,
    entries: @[
      # Effects
      ChangelogEntry(category: clcImproved,
        en: "Aftershock is finally something you can see. The shockwave now draws the actual corridor you ran through: a bright crest rolls backwards along your path exactly the way the damage resolves, leaving a glowing swath and a trail of sparks behind it, and every enemy it catches bursts at the point on the path that hit them. Before this, a wide loop just made enemies fly away from nothing.",
        es: "Réplica por fin se ve. La onda ahora dibuja el pasillo por el que corriste de verdad: una cresta brillante recorre tu recorrido hacia atrás igual que se resuelve el daño, dejando una estela luminosa y un rastro de chispas, y cada enemigo alcanzado revienta en el punto exacto del recorrido que lo tocó. Antes, dar una vuelta amplia solo hacía que los enemigos salieran volando sin motivo visible."),
      ChangelogEntry(category: clcImproved,
        en: "Conduit now detonates where the damage actually lands. Each burning, poisoned or frozen enemy pops with a burst in that element's own colour, a ring sized to how much damage it had banked, and an arc of energy running back to you. The damage numbers are colour-coded per element too, so a target carrying several damage-over-time effects reads as several payloads going off at once instead of one anonymous flash at your feet.",
        es: "Conducto ahora detona donde el daño cae de verdad. Cada enemigo ardiendo, envenenado o congelado estalla con una explosión del color de su propio elemento, un anillo del tamaño del daño acumulado y un arco de energía que vuelve hasta ti. Los números de daño también van coloreados por elemento, así que un objetivo con varios efectos por tiempo se lee como varias cargas estallando a la vez en lugar de un fogonazo anónimo a tus pies."),
      ChangelogEntry(category: clcImproved,
        en: "Blood Pact and Nova got their impact back. The pact opens two blood-red rings around you and snaps a tether to every victim, each of which bursts where it stands. Nova marks each bullet as it is caught, keeps the held rounds shimmering in mid-air so they no longer look stuck, and flashes every one of them as the volley launches.",
        es: "Pacto de Sangre y Nova recuperan su impacto. El pacto abre dos anillos rojo sangre a tu alrededor y lanza un lazo a cada víctima, y cada una revienta donde está. Nova marca cada bala al atraparla, mantiene los proyectiles retenidos brillando en el aire para que ya no parezcan atascados, y hace destellar a todos al salir la descarga."),
      ChangelogEntry(category: clcImproved,
        en: "Several quiet power-ups now show their work. Giant Slayer scatters arcane shards on the target, Curse cracks its purple ring open on every hit that cashes it in, Overcharge lands a golden impact once a shot is near its full charge, and Thorns throws a green spike ring outward from whatever hit you instead of a plain red puff.",
        es: "Varias mejoras silenciosas ahora enseñan lo que hacen. Matagigantes esparce fragmentos arcanos sobre el objetivo, Maldición rompe su anillo morado en cada golpe que la cobra, Sobrecarga deja un impacto dorado cuando el disparo llega casi a plena carga, y Espinas lanza un anillo verde de púas desde lo que te golpeó en vez de una simple nube roja."),

      # Tuning
      ChangelogEntry(category: clcBalance,
        en: "Juggernaut reworked: it no longer hands out its damage for free. Your starting health pool and every automatic gain -- the health you pick up just by clearing waves or levelling up -- no longer count, so only max HP you actually bought (shop upgrades, Fortified, Corrupted Core) is converted, at +3% damage per 100 up to +45%. Picking it up bolts 300 max HP of plating onto you to start that off, and the plating has weight: it slows you by up to 18%, scaling with however much damage it is currently granting. Wearing it also caps how much Momentum can pay you, since you can no longer reach full speed.",
        es: "Coloso rediseñado: ya no regala su daño. Tu vida inicial y todo lo que ganas de forma automática -- la vida que sale sola al superar oleadas o subir de nivel -- dejan de contar, así que solo se convierte el HP máximo que compraste de verdad (mejoras de tienda, Fortificado, Núcleo Corrupto), a +3% de daño por cada 100 y hasta +45%. Al cogerlo te instala 300 HP máx de blindaje para arrancar, y ese blindaje pesa: te ralentiza hasta un 18%, en proporción al daño que te esté dando en ese momento. Llevarlo también limita lo que puede pagarte Momento, porque ya no alcanzas la velocidad máxima."),
      ChangelogEntry(category: clcNew,
        en: "New power-up -- Bulwark: your damage rises with how much of your health bar is still intact, up to +25% at full HP and falling away as you take hits. Healing welds the plating back on. It is the exact opposite of Rage and Crisis Mode, so taking those alongside it mostly cancels out.",
        es: "Nueva mejora -- Baluarte: tu daño sube según lo intacta que esté tu barra de vida, hasta +25% con la vida llena y bajando a medida que recibes golpes. Curarte vuelve a soldar el blindaje. Es justo lo contrario de Furia y Modo Crisis, así que llevarlas junto a él se cancela casi del todo."),
      ChangelogEntry(category: clcBalance,
        en: "Boss overload shields now throw your actual bullet back at you. Instead of spitting out a generic pellet, the shell catches the shot you fired -- same skin, same shape, same element and explosive or piercing behaviour -- flips it around and sends it home along the line it came in on. It travels far slower than it arrived, so you can step out of the way, and it hits for half of that bullet's own damage, capped so no single round can take you out. Your own walls will stop it, and a Parry sends it straight back at the boss.",
        es: "Los escudos de sobrecarga de los jefes ahora te devuelven tu propia bala. En vez de soltar un proyectil genérico, el caparazón atrapa el disparo que hiciste -- mismo aspecto, misma forma, mismo elemento y comportamiento explosivo o perforante --, lo gira y lo manda de vuelta por la línea por la que llegó. Viaja mucho más despacio de lo que llegó, así que puedes apartarte, y golpea con la mitad del daño de esa misma bala, con un tope para que ningún disparo pueda acabar contigo. Tus propios muros lo detienen, y una Parada lo reenvía directo al jefe."),
      ChangelogEntry(category: clcImproved,
        en: "Boss overload shields now telegraph themselves. Six shards fall inward onto the shell's future corners while a ring closes around the boss, landing exactly as the shield snaps up, so you get a moment to hold fire instead of finding out by eating your own shot. A returned bullet is also ringed with a pulsing cyan cage and spinning spokes, so you can pick it out of the crossfire. Both cues are purely visual and always shown, even with hints turned off.",
        es: "Los escudos de sobrecarga de los jefes ahora se avisan. Seis fragmentos caen hacia dentro sobre las futuras esquinas del caparazón mientras un anillo se cierra alrededor del jefe, y ambos llegan justo cuando el escudo se levanta, así que tienes un momento para dejar de disparar en vez de enterarte comiéndote tu propio disparo. La bala devuelta también lleva una jaula cian que late y radios que giran, para que puedas distinguirla en medio del fuego cruzado. Ambas señales son puramente visuales y se muestran siempre, incluso con las pistas desactivadas."),

      # Interface
      ChangelogEntry(category: clcImproved,
        en: "The difficulty picker now carries a pulsing banner across the Easy and Normal cards marking them as the recommended starting point, so creating a profile is not a blind guess between four cards.",
        es: "El selector de dificultad ahora lleva un cartel palpitante sobre las tarjetas Fácil y Normal que las marca como el punto de partida recomendado, para que crear un perfil no sea adivinar a ciegas entre cuatro tarjetas."),
      ChangelogEntry(category: clcFixed,
        en: "The [OK] badge in the top-right corner of the victory screen no longer spills outside its box; it is sized to fit and centred.",
        es: "El distintivo [OK] de la esquina superior derecha de la pantalla de victoria ya no se sale de su recuadro; ahora se ajusta al tamaño y queda centrado."),
      ChangelogEntry(category: clcFixed,
        en: "The mission duration on the ending screens no longer keeps counting while you sit there reading your own results. The run clock now stops the moment the run does, and that frozen time is what gets written to your lifetime statistics. Continuing into endless play from the victory screen picks the clock back up where it stopped, so the pause is not billed to the run either.",
        es: "La duración de la misión en las pantallas de final ya no sigue subiendo mientras te quedas leyendo tus propios resultados. El reloj de la partida ahora se detiene justo cuando termina la partida, y ese tiempo congelado es el que se guarda en tus estadísticas totales. Si continúas al modo infinito desde la pantalla de victoria, el reloj sigue desde donde se paró, así que la pausa tampoco se le cobra a la partida.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.2",
    titleEs: "Versión 6.2",
    subtitleEn: "Changes since v6.1.1",
    subtitleEs: "Cambios desde v6.1.1",
    latest: false,
    entries: @[
      # Startup
      ChangelogEntry(category: clcFixed,
        en: "The first-launch audio setup no longer freezes the game. Building the four music tracks used to lock the window for several seconds at a time -- nothing animated and Windows could mark the game as not responding. The audio is now built in the background while the loading screen keeps running at full frame rate.",
        es: "La preparación de audio del primer arranque ya no congela el juego. Crear las cuatro pistas de música bloqueaba la ventana durante varios segundos seguidos -- nada se animaba y Windows podía marcar el juego como que no responde. Ahora el audio se crea en segundo plano mientras la pantalla de carga sigue funcionando a pleno rendimiento."),
      ChangelogEntry(category: clcImproved,
        en: "Redesigned loading screen: an audio_setup.exe window with SFX / MUSIC / MEMORY stage badges, an asset counter, the file being built right now, a smoothly filling progress bar and a live audio meter. It also notes that this only happens on the first run, since the generated audio is cached afterwards.",
        es: "Pantalla de carga rediseñada: una ventana audio_setup.exe con distintivos de fase SFX / MÚSICA / MEMORIA, un contador de recursos, el archivo que se está creando, una barra de progreso que se llena con suavidad y un medidor de audio en vivo. Además avisa de que esto solo ocurre en el primer arranque, porque el audio generado queda en caché."),

      # Tuning
      ChangelogEntry(category: clcBalance,
        en: "The Orbital Commander's final phase now belongs to its Orbital Scan: three walls per volley instead of two, arriving from three different edges (rake, crosswise, then a reverse rake), and the next scan starts telegraphing while the last wall is still crossing. The safe lane is a touch wider to compensate.",
        es: "La fase final del Comandante Orbital ahora gira en torno a su Escaneo Orbital: tres muros por descarga en vez de dos, llegando desde tres bordes distintos (barrido, transversal y barrido inverso), y el siguiente escaneo empieza a avisarse mientras el último muro aún cruza. El carril seguro es algo más ancho para compensar."),

      # Fixes
      ChangelogEntry(category: clcFixed,
        en: "Fixed a crash when starting Wave mode with a checkpoint saved by an older build. Checkpoints written before the run save started tracking shop purchases were missing that field, and reading it crashed the game instead of skipping it. Older checkpoints now load again, and the same fault was fixed in the roguelite floor and profile loaders.",
        es: "Corregido un cierre inesperado al entrar en el modo Oleadas con un punto de control guardado por una versión anterior. A los puntos de control escritos antes de que la partida guardara las compras de tienda les faltaba ese campo, y leerlo cerraba el juego en vez de omitirlo. Los puntos de control antiguos vuelven a cargarse, y se corrigió el mismo fallo en los cargadores de planta y de perfil del Roguelite."),
      ChangelogEntry(category: clcFixed,
        en: "Heavy Rounds' knockback now actually pushes. It was nudging enemies by under three pixels -- invisible on anything -- and now lands a real shove that sends them coasting backwards, like the Wind Aura gust. Bosses still shrug off most of it, and rapid fire cannot stack the shoves into a stun-lock.",
        es: "El retroceso de Balas Pesadas ahora empuja de verdad. Movía a los enemigos menos de tres píxeles -- invisible en cualquier caso -- y ahora aplica un empujón real que los hace retroceder deslizándose, como la ráfaga del Aura de Viento. Los jefes siguen resistiendo casi todo, y disparar rápido no puede acumular los empujones hasta inmovilizar."),
      ChangelogEntry(category: clcFixed,
        en: "Spanish text fixes: the 35 boss phase names in the boss health panel (Awakening, Spiral Rage, Omega Phase and the rest) were still English, as were the general boss mechanics list in the Help window and the DONE badge on completed advancements. All translated now.",
        es: "Correcciones de texto en español: los 35 nombres de fase de los jefes del panel de vida (Despertar, Furia Espiral, Fase Omega y los demás) seguían en inglés, igual que la lista general de mecánicas de jefes en la ventana de Ayuda y la etiqueta LISTO de los logros completados. Ya están todos traducidos.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.1",
    titleEs: "Versión 6.1",
    subtitleEn: "Changes since v6.0",
    subtitleEs: "Cambios desde v6.0",
    entries: @[
      # Headline features
      ChangelogEntry(category: clcNew,
        en: "Checkpoints: clearing a boss block now writes a checkpoint that survives death. The game-over screen offers CONTINUE (WAVE N) to drop straight back into the run instead of starting over.",
        es: "Puntos de control: superar un bloque de jefe ahora guarda un punto de control que sobrevive a la muerte. La pantalla de derrota ofrece CONTINUAR (OLEADA N) para volver directamente a la partida en vez de empezar de cero."),
      ChangelogEntry(category: clcNew,
        en: "Continuing from a checkpoint keeps the same run going: kills, power-ups collected, damage dealt and time played all carry over instead of resetting.",
        es: "Continuar desde un punto de control mantiene la misma partida: bajas, potenciadores recogidos, daño infligido y tiempo jugado se conservan en vez de reiniciarse."),
      ChangelogEntry(category: clcNew,
        en: "Nightmare difficulty: enemies get +50% health and damage (speed untouched) and checkpoints are disabled -- every death sends you back to wave 1.",
        es: "Dificultad Pesadilla: los enemigos ganan +50% de vida y daño (la velocidad no cambia) y los puntos de control quedan desactivados: cada muerte te devuelve a la oleada 1."),
      ChangelogEntry(category: clcNew,
        en: "A fourth save profile slot, so there is exactly one slot per difficulty.",
        es: "Una cuarta ranura de perfil, de modo que hay exactamente una ranura por dificultad."),
      ChangelogEntry(category: clcNew,
        en: "New Credits.nfo desktop icon: a scrolling credits window with a SUPPORT panel linking to GitHub Sponsors, Ko-fi and Buy Me a Coffee. You can also open it by typing 'credits' in the terminal.",
        es: "Nuevo icono de escritorio Credits.nfo: una ventana de créditos con desplazamiento y un panel de APOYO con enlaces a GitHub Sponsors, Ko-fi y Buy Me a Coffee. También puedes abrirla escribiendo 'credits' en la terminal."),
      ChangelogEntry(category: clcNew,
        en: "New Mythic rarity, one step above Legendary: reserved for one-shot feats that a whole run can void, and it pays out 400 Data Shards and 3 Cores.",
        es: "Nueva rareza Mítica, un escalón por encima de Legendaria: reservada para hazañas de una sola vez que toda una partida puede anular, y paga 400 Fragmentos de Datos y 3 Núcleos."),
      ChangelogEntry(category: clcNew,
        en: "New Mythic advancement, Flawless Kernel: clear wave mode from wave 1 to the twelfth boss without dying once. Pressing CONTINUE at any point voids it for that run, and so does using cheats.",
        es: "Nuevo logro Mítico, Núcleo Impecable: completa el modo oleadas desde la oleada 1 hasta el duodécimo jefe sin morir ni una vez. Pulsar CONTINUAR en cualquier momento lo anula en esa partida, igual que usar trucos."),

      # Reworks and quality of life
      ChangelogEntry(category: clcImproved,
        en: "Auras reworked into pulses: instead of a constant field, each aura fires a shockwave that sweeps outward from you on its own beat, hitting every enemy the wavefront reaches.",
        es: "Auras rehechas como pulsos: en vez de un campo constante, cada aura lanza una onda de choque que barre hacia afuera desde ti con su propio ritmo, golpeando a cada enemigo que alcanza el frente de onda."),
      ChangelogEntry(category: clcImproved,
        en: "Every aura gained range: base radii went from 188/250/313 to 250/325/400, and each aura takes a different share of that band so stacked auras read as distinct concentric rings.",
        es: "Todas las auras ganaron alcance: los radios base pasaron de 188/250/313 a 250/325/400, y cada aura toma una porción distinta de esa banda para que las auras apiladas se lean como anillos concéntricos diferenciados."),
      ChangelogEntry(category: clcImproved,
        en: "Stacked auras no longer fire on the same frame: each one keeps its own timer and starts on a staggered beat, so pulses arrive spread out instead of all at once.",
        es: "Las auras apiladas ya no disparan en el mismo fotograma: cada una tiene su propio temporizador y arranca desfasada, así que los pulsos llegan repartidos en vez de todos a la vez."),
      ChangelogEntry(category: clcImproved,
        en: "Each aura's wave has its own look -- flame crests, jagged lightning fronts, poison and blood washes, arcane rings -- so you can tell which one just fired at a glance.",
        es: "La onda de cada aura tiene su propio aspecto -- crestas de fuego, frentes dentados de rayo, oleadas de veneno y sangre, anillos arcanos -- para que sepas de un vistazo cual acaba de dispararse."),
      ChangelogEntry(category: clcImproved,
        en: "Wind Aura is now a periodic gust that blasts enemies away, and Slow Field became a slowing pulse.",
        es: "El Aura de Viento ahora es una ráfaga periódica que empuja a los enemigos, y el Campo de Ralentización pasa a ser un pulso ralentizador."),
      ChangelogEntry(category: clcImproved,
        en: "Element masteries now also make their aura pulse faster, not just hit harder.",
        es: "Las maestrías elementales ahora también hacen que su aura pulse más rápido, no solo que pegue más fuerte."),
      ChangelogEntry(category: clcImproved,
        en: "Restarting from wave 1 while a checkpoint exists now asks for confirmation first, so a reflex keypress cannot throw the run away.",
        es: "Reiniciar desde la oleada 1 teniendo un punto de control ahora pide confirmación, para que una tecla por reflejo no tire la partida a la basura."),
      ChangelogEntry(category: clcImproved,
        en: "Game-over buttons are colour-coded: green for continuing, red for leaving.",
        es: "Los botones de la pantalla de derrota están codificados por color: verde para continuar, rojo para salir."),
      ChangelogEntry(category: clcImproved,
        en: "Resumed runs now restore more of your build: shop purchase counts (so prices and gains keep their curve), Heavy Rounds' extra size, and the comeback bonus bookkeeping.",
        es: "Las partidas retomadas ahora restauran más de tu build: las compras de tienda (para que precios y mejoras mantengan su curva), el tamaño extra de Balas Pesadas y el registro del bono de remontada."),
      ChangelogEntry(category: clcImproved,
        en: "Boss laser beams now use one shared duration formula with a hard cap, so no beam can lock a lane down longer than intended.",
        es: "Los rayos de los jefes ahora usan una única fórmula de duración con tope máximo, así que ningun rayo puede bloquear un carril más tiempo del previsto."),
      ChangelogEntry(category: clcImproved,
        en: "New default settings: the widescreen 16:9 HUD and render resolution scaling are now on out of the box. Both can still be switched back in Settings.",
        es: "Nuevos ajustes por defecto: el HUD panorámico 16:9 y el escalado de resolución de render vienen activados de serie. Ambos se pueden volver a cambiar en Ajustes."),
      ChangelogEntry(category: clcImproved,
        en: "The power-up slot machine reel now only spins through power-ups this run can actually offer, instead of teasing mode-exclusive or locked entries.",
        es: "El carrete de la maquina tragaperras de potenciadores ahora solo pasa por potenciadores que esta partida puede ofrecer, en vez de mostrar entradas exclusivas de otro modo o bloqueadas."),
      ChangelogEntry(category: clcImproved,
        en: "The desktop icons were redrawn so each one reads at a glance: Survival is a sweeping stopwatch, Settings a turning cog, Shop a shopping bag, Advancements a trophy, PvP crossed swords, Roguelite a branching route map ending on a boss node, Quit a proper power symbol and Help a manual instead of a second document.",
        es: "Se redibujaron los iconos del escritorio para que cada uno se entienda de un vistazo: Supervivencia es un cronometro en marcha, Ajustes un engranaje giratorio, Tienda una bolsa de compra, Logros un trofeo, PvP espadas cruzadas, Roguelite un mapa de rutas que termina en un nodo de jefe, Salir un simbolo de encendido de verdad y Ayuda un manual en vez de un segundo documento."),
      ChangelogEntry(category: clcImproved,
        en: "Icons also picked up small animations and darker backing outlines, so they stay legible over a busy wallpaper: thruster streaks on Play, bubbles rising in the Sandbox flask, and bullet points on the changelog page.",
        es: "Los iconos también ganaron pequeñas animaciones y contornos oscuros de fondo, para que sigan siendo legibles sobre un fondo de pantalla cargado: estelas de propulsor en Jugar, burbujas subiendo en el matraz del Sandbox y viñetas en la página del registro de cambios."),
      ChangelogEntry(category: clcImproved,
        en: "Credits.nfo now sits in the bottom-right corner of the desktop instead of starting a third column, and it stays anchored there when you switch between the 4:3 and 16:9 HUD layouts.",
        es: "Credits.nfo ahora se situa en la esquina inferior derecha del escritorio en vez de empezar una tercera columna, y se mantiene anclado ahi al cambiar entre los diseños de HUD 4:3 y 16:9."),
      ChangelogEntry(category: clcImproved,
        en: "Advancements are now sorted by rarity. Each category lists Bronze first up to Mythic, with a header per rarity showing how many of that group you have unlocked.",
        es: "Los logros ahora se ordenan por rareza. Cada categoria lista de Bronce hasta Mítico, con una cabecera por rareza que muestra cuantos de ese grupo llevas desbloqueados."),
      ChangelogEntry(category: clcImproved,
        en: "The advancements window gained a rarity legend in the sidebar with your overall progress per rarity, and each entry now shows its Data Shard payout right on the card.",
        es: "La ventana de logros gano una leyenda de rareza en la barra lateral con tu progreso global por rareza, y cada entrada muestra ahora su pago en Fragmentos de Datos en la propia tarjeta."),
      ChangelogEntry(category: clcImproved,
        en: "The advancement detail panel now shows its category and how far along that rarity you are, and the list scrolls smoothly with a scrollbar that reflects how much is left below.",
        es: "El panel de detalle de logros ahora muestra su categoria y cuanto llevas de esa rareza, y la lista se desplaza con suavidad con una barra que refleja cuanto queda por debajo."),

      # Tuning
      ChangelogEntry(category: clcBalance,
        en: "Fire Mastery pulled back from +350% to +150% damage, now in line with the other element masteries.",
        es: "Maestría de Fuego reducida de +350% a +150% de daño, ahora en línea con las demás maestrías elementales."),
      ChangelogEntry(category: clcBalance,
        en: "Frost Mastery reworked into a pure control pick: +25% slow (up to 85%) and orbs that chill for 55%, instead of extra damage and duration.",
        es: "Maestría de Escarcha rehecha como opción de control puro: +25% de ralentización (hasta 85%) y orbes que enfrían un 55%, en vez de daño y duración extra."),
      ChangelogEntry(category: clcBalance,
        en: "Arcane Mastery simplified: +75% damage to everything arcane, and arcane bullets still pierce.",
        es: "Maestría Arcana simplificada: +75% de daño a todo lo arcano, y las balas arcanas siguen perforando."),
      ChangelogEntry(category: clcBalance,
        en: "Wind Mastery now grants +45% slow and a 3.5x stronger push.",
        es: "Maestría de Viento ahora otorga +45% de ralentización y un empuje 3.5 veces más fuerte."),
      ChangelogEntry(category: clcBalance,
        en: "Boss weak points reward a little less: their damage multipliers were trimmed across every boss tier, so bursting a weak spot no longer skips whole phases.",
        es: "Los puntos débiles de los jefes recompensan un poco menos: sus multiplicadores de daño se recortaron en todos los niveles de jefe, así que reventar un punto débil ya no se salta fases enteras."),
      ChangelogEntry(category: clcBalance,
        en: "Bosses take less damage while channelling a mega special (30% of normal, down from 40%), so their big casts cannot simply be raced.",
        es: "Los jefes reciben menos daño mientras canalizan un mega especial (30% del normal, antes 40%), así que ya no basta con correr contra sus grandes conjuros."),
      ChangelogEntry(category: clcBalance,
        en: "The Laser Architect reads better again: a tighter ricochet-beam wind-up, a faster sweep, one less beam in the prismatic cage, weaker sniping lasers and one fewer projectile attack in its last phase.",
        es: "El Arquitecto Láser vuelve a leerse mejor: preparación más ajustada del rayo de rebote, barrido más rápido, un rayo menos en la jaula prismática, láseres de francotirador más débiles y un ataque de proyectiles menos en su última fase."),
      ChangelogEntry(category: clcBalance,
        en: "The Void Walker's final phase trades damage for defence: it hits softer and throws fewer projectiles, but is much tougher to burn down.",
        es: "La fase final del Caminante del Vacío cambia daño por defensa: pega más flojo y lanza menos proyectiles, pero es mucho más difícil de fundir."),
      ChangelogEntry(category: clcBalance,
        en: "Regeneration reworked to scale with your health pool: it now heals a flat amount plus a share of your max HP each wave (150 HP +3%, 250 HP +5%, 350 HP +7%), like health pickups do, instead of a fixed roll that fell behind late.",
        es: "Regeneración rehecha para escalar con tu vida: ahora cura una cantidad fija más una parte de tu vida máxima en cada oleada (150 HP +3%, 250 HP +5%, 350 HP +7%), como los botiquines, en vez de una tirada fija que se quedaba corta al final."),
      ChangelogEntry(category: clcBalance,
        en: "Power-up offers retimed around the boss cycle: you now get a selection on every wave of a block except the first, plus the guaranteed boss reward.",
        es: "Las ofertas de potenciadores se reajustaron al ciclo de jefes: ahora recibes una selección en cada oleada del bloque salvo la primera, más la recompensa garantizada del jefe."),

      # Fixes
      ChangelogEntry(category: clcFixed,
        en: "Fixed bosses sometimes dying outright when a phase health bar ran out instead of changing to their next phase.",
        es: "Se corrigió que los jefes murieran a veces de golpe al agotarse la barra de vida de una fase en vez de pasar a su siguiente fase."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed the Last Run stats screen changing under you: it now stores its own snapshot instead of tracking a run that kept updating.",
        es: "Se corrigió que la pantalla de estadísticas de la última partida cambiara sola: ahora guarda su propia instantanea en vez de seguir una partida que se seguia actualizando."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed the Sandbox boss buttons spawning the wrong boss (or none at all).",
        es: "Se corrigió que los botones de jefes del Sandbox invocaran al jefe equivocado (o a ninguno)."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed resumed runs silently dropping Heavy Rounds' size penalty and leaving the comeback bonus permanently active.",
        es: "Se corrigió que las partidas retomadas perdieran en silencio la penalización de tamaño de Balas Pesadas y dejaran el bono de remontada activo para siempre."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed aura tints still being drawn at the old, smaller radius: the coloured area now fills the whole aura out to its border, and wind, arcane and blood auras got the same tinted body the others already had.",
        es: "Se corrigió que los tintes de las auras se dibujaran aún con el radio antiguo, más pequeño: el área coloreada ahora llena toda el aura hasta su borde, y las auras de viento, arcana y sangre recibieron el mismo cuerpo tenido que ya tenían las demás."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed a single wind gust hitting the same enemy repeatedly as its own knockback pushed it back through the wavefront.",
        es: "Se corrigió que una sola ráfaga de viento golpeara al mismo enemigo varias veces porque su propio empuje lo devolvia a traves del frente de onda."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed wall placement in the widescreen layout: walls landed offset from the cursor and could be dropped outside the arena. Placement now follows the ghost preview exactly and refuses spots outside the play area.",
        es: "Se corrigió la colocación de muros en el diseño panorámico: los muros aparecían desplazados respecto al cursor y podían colocarse fuera del escenario. La colocación ahora sigue exactamente la vista previa y rechaza posiciones fuera del área de juego."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Fortified granting double the max HP it advertises: upgrading it re-applied the whole bonus, reaching +1500 HP at level 3 instead of +750.",
        es: "Se corrigió que Fortificado otorgara el doble de la vida máxima que anuncia: al mejorarlo se volvia a aplicar el bono completo, llegando a +1500 HP en el nivel 3 en vez de +750."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Recursion compounding when levelled up in the same run: a level 1 to 3 climb gave about +48% damage instead of the +20% the level is worth.",
        es: "Se corrigió que Recursion se acumulara al subir de nivel en la misma partida: pasar de nivel 1 a 3 daba cerca de +48% de daño en vez del +20% que vale el nivel."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Diamond enemies losing their one-hit shield to a passive aura or damage-over-time tick the moment they drifted into range, which erased the mechanic for aura builds. Only a real hit spends it now.",
        es: "Se corrigió que los enemigos Diamante perdieran su escudo de un golpe por un aura pasiva o un tic de daño con el tiempo nada más entrar en rango, lo que anulaba la mecánica en builds de aura. Ahora solo lo gasta un impacto real."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed enemies ground down against a wall handing out a full kill: wall damage can no longer finish an enemy off, so it cannot be farmed for coins, XP and combo.",
        es: "Se corrigió que los enemigos desgastados contra un muro contaran como muerte completa: el daño del muro ya no puede rematar a un enemigo, así que no se puede farmear por monedas, XP y combo."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed advancement descriptions running underneath the progress bar on their cards; the cards are taller now and the text has room.",
        es: "Se corrigió que las descripciones de los logros quedaran por debajo de la barra de progreso en sus tarjetas; ahora las tarjetas son más altas y el texto tiene espacio.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.0",
    titleEs: "Versión 6.0",
    subtitleEn: "Changes since v5.5.2",
    subtitleEs: "Cambios desde v5.5.2",
    entries: @[
      # Headline features
      ChangelogEntry(category: clcNew,
        en: "Save profiles: three independent slots, each with its own progress and its own difficulty, chosen when the profile is created.",
        es: "Perfiles de guardado: tres ranuras independientes, cada una con su propio progreso y su propia dificultad, elegida al crear el perfil."),
      ChangelogEntry(category: clcNew,
        en: "Full controller support: play with a gamepad, rebind pad buttons in Settings, and enable optional aim assist that snaps to nearby enemies.",
        es: "Soporte completo de mando: juega con gamepad, reasigna los botones en Ajustes y activa la asistencia de apuntado opcional que se ajusta a enemigos cercanos."),
      ChangelogEntry(category: clcNew,
        en: "Runs are now saved: quit in the middle of a run and pick it back up exactly where you left off.",
        es: "Las partidas ahora se guardan: sal en mitad de una partida y retomala justo donde la dejaste."),
      ChangelogEntry(category: clcNew,
        en: "New widescreen 16:9 HUD layout that moves the interface into side bands, switchable in Settings alongside the classic 4:3 layout.",
        es: "Nuevo diseño de HUD panorámico 16:9 que mueve la interfaz a paneles laterales, intercambiable en Ajustes junto al diseño clásico 4:3."),
      ChangelogEntry(category: clcNew,
        en: "XP orbs and levelling in Roguelite and Survival: enemies drop experience that you collect to level up mid-run.",
        es: "Orbes de XP y niveles en Roguelite y Supervivencia: los enemigos sueltan experiencia que recoges para subir de nivel en plena partida."),
      ChangelogEntry(category: clcNew,
        en: "Sandbox setup window: build a custom loadout, pick a preset from Fresh Start to End Game (wave 60), or pull the average build for any wave.",
        es: "Ventana de configuración del Sandbox: arma un equipamiento a medida, elige un preajuste desde Inicio hasta Fin de Partida (oleada 60), o carga la build media de cualquier oleada."),
      ChangelogEntry(category: clcNew,
        en: "Roguelite victory screen and endless loop: clear every floor boss, then cash out or descend again for richer rewards and fiercer processes.",
        es: "Pantalla de victoria del Roguelite y bucle infinito: derrota a todos los jefes de piso y luego cobra tu botín o desciende de nuevo por mejores recompensas y procesos más feroces."),
      ChangelogEntry(category: clcNew,
        en: "Roguelite and Survival now have their own ending cinematics, closing out the story each mode tells.",
        es: "Roguelite y Supervivencia ahora tienen sus propias cinemáticas finales, cerrando la historia que cuenta cada modo."),
      ChangelogEntry(category: clcNew,
        en: "New Cinematics tab in Settings: replay any story cinematic or mode intro whenever you want.",
        es: "Nueva pestaña de Cinemáticas en Ajustes: vuelve a ver cualquier cinemática de historia o intro de modo cuando quieras."),
      ChangelogEntry(category: clcNew,
        en: "Cosmetic theme bundles: a new PACKS tab in the shop sells matching player, bullet and particle trios at 40% off, and only charges you for the pieces you do not already own.",
        es: "Paquetes temáticos de cosméticos: la nueva pestaña PACKS de la tienda vende trios de jugador, bala y particulas a juego con 40% de descuento, y solo te cobra las piezas que aún no tienes."),
      ChangelogEntry(category: clcNew,
        en: "New cosmetics: Starfall and Storm Surge player and bullet skins, plus Crystal Bloom and Code Rain particle effects.",
        es: "Nuevos cosméticos: aspectos de jugador y bala Starfall y Storm Surge, más los efectos de particulas Crystal Bloom y Code Rain."),
      ChangelogEntry(category: clcNew,
        en: "Undiscovered power-ups now stay hidden until you find them, with a NEW badge on first sight and a discovery codex tracking what you have seen.",
        es: "Los potenciadores sin descubrir ahora permanecen ocultos hasta que los encuentras, con una insignia NEW al verlos por primera vez y un codice de descubrimientos que registra lo que ya conoces."),
      ChangelogEntry(category: clcNew,
        en: "New enemy and boss mechanics: phase firewalls, sealed enemies you must clear before the fight continues, and overload states that punish holding fire.",
        es: "Nuevas mecánicas de enemigos y jefes: cortafuegos de fase, enemigos sellados que debes limpiar antes de que la pelea continue, y estados de sobrecarga que castigan disparar sin parar."),
      ChangelogEntry(category: clcNew,
        en: "New ricochet laser boss ultimate that bounces around the arena.",
        es: "Nueva ultimate de jefe con láser de rebote que va rebotando por el escenario."),
      ChangelogEntry(category: clcNew,
        en: "Roguelite starter kits now show a small class emblem on your character (Operator, Bulwark or Arcanist).",
        es: "Los kits iniciales del Roguelite ahora muestran un pequeño emblema de clase en tu personaje (Operador, Baluarte o Arcanista)."),
      ChangelogEntry(category: clcNew,
        en: "Time Survival is now unlocked by beating Roguelite mode.",
        es: "Supervivencia en Tiempo ahora se desbloquea derrotando el modo Roguelite."),
      ChangelogEntry(category: clcNew,
        en: "Bosses now fight in distinct phases, shifting their attack patterns as their health drops.",
        es: "Los jefes ahora luchan en fases, cambiando sus patrones de ataque a medida que pierden vida."),
      ChangelogEntry(category: clcNew,
        en: "New Summoner mechanic: some enemies call in reinforcements mid-fight.",
        es: "Nueva mecánica de Invocador: algunos enemigos llaman refuerzos en plena pelea."),
      ChangelogEntry(category: clcNew,
        en: "Added a large batch of new mode-exclusive power-ups for Survival and Roguelite runs, including several Legendaries.",
        es: "Se añadió un gran lote de nuevos potenciadores exclusivos de modo para partidas de Supervivencia y Roguelite, incluyendo varios Legendarios."),
      ChangelogEntry(category: clcNew,
        en: "Each game mode now opens with its own intro cinematic.",
        es: "Cada modo de juego ahora comienza con su propia cinemática de introducción."),
      ChangelogEntry(category: clcNew,
        en: "Added dedicated victory and death screens to cap off every run.",
        es: "Se añadieron pantallas dedicadas de victoria y derrota para cerrar cada partida."),
      ChangelogEntry(category: clcNew,
        en: "Overhauled sound effect system (v2) with richer, cleaner audio.",
        es: "Sistema de efectos de sonido renovado (v2) con audio más rico y limpio."),
      ChangelogEntry(category: clcNew,
        en: "New comeback bonus: falling behind grants a temporary damage boost to help you recover.",
        es: "Nuevo bono de remontada: quedar atras otorga un aumento temporal de daño para ayudarte a recuperar."),
      ChangelogEntry(category: clcNew,
        en: "Keyboard controls can now be fully rebound from the Settings window.",
        es: "Los controles de teclado ahora se pueden reasignar por completo desde la ventana de Ajustes."),
      ChangelogEntry(category: clcNew,
        en: "Fights against multiple bosses now show a separate health bar for each one.",
        es: "Las peleas contra varios jefes ahora muestran una barra de vida separada para cada uno."),
      ChangelogEntry(category: clcNew,
        en: "Added new desktop themes (Kernel Panic, CyberGround, Casino) and hidden easter eggs to discover.",
        es: "Se añadieron nuevos temas de escritorio (Kernel Panic, CyberGround, Casino) y huevos de pascua ocultos por descubrir."),
      ChangelogEntry(category: clcNew,
        en: "More cosmetics, including D&D-themed skins and secret unlockable hats.",
        es: "Más cosméticos, incluyendo aspectos temáticos de D&D y sombreros secretos desbloqueables."),

      # Reworks and quality of life
      ChangelogEntry(category: clcImproved,
        en: "Four power-ups reworked into distinct identities and renamed: Overclock (hold fire to ramp your fire rate up to +30%), Juggernaut (+2% damage per 100 max HP, up to +40%), Momentum (up to +25% damage while moving) and Lightspeed (every shot fires an instant tracer beam for 50% damage).",
        es: "Cuatro potenciadores rehechos con identidades propias y renombrados: Sobrecarga (manten el disparo para acelerar la cadencia hasta +30%), Coloso (+2% de daño por cada 100 HP máximos, hasta +40%), Impulso (hasta +25% de daño en movimiento) y Lightspeed (cada disparo lanza un rayo trazador instantaneo por 50% de daño)."),
      ChangelogEntry(category: clcImproved,
        en: "Fire and poison now play differently: fire lands as a burst, poison drips and stacks over time, and each shows its own damage numbers.",
        es: "Fuego y veneno ahora se juegan distinto: el fuego golpea de golpe, el veneno gotea y se acumula con el tiempo, y cada uno muestra sus propios números de daño."),
      ChangelogEntry(category: clcImproved,
        en: "Bosses 1, 2, 3, 5 and 7 through 12 all received reworks or retunes, giving each one a clearer signature attack.",
        es: "Los jefes 1, 2, 3, 5 y del 7 al 12 recibieron reworks o reajustes, dando a cada uno un ataque característico más claro."),
      ChangelogEntry(category: clcImproved,
        en: "Boss phase transitions and weak-point hitboxes reworked for clearer, fairer fights.",
        es: "Transiciones de fase y puntos débiles de los jefes rehechos para peleas más claras y justas."),
      ChangelogEntry(category: clcImproved,
        en: "Boss telegraphs unified so every delayed attack warns you the same way before it lands.",
        es: "Avisos de jefes unificados para que todo ataque diferido te advierta de la misma manera antes de impactar."),
      ChangelogEntry(category: clcImproved,
        en: "Advancements window overhauled with clearer progress and better organisation.",
        es: "Ventana de logros renovada con progreso más claro y mejor organización."),
      ChangelogEntry(category: clcImproved,
        en: "Roguelite quality of life: a clearer sector map, a warning before the point of no return on the final floor, and a relic summary when you leave a run.",
        es: "Mejoras de calidad de vida en Roguelite: mapa de sectores más claro, un aviso antes del punto sin retorno en el piso final, y un resumen de reliquias al abandonar la partida."),
      ChangelogEntry(category: clcImproved,
        en: "Survival quality of life, including a reworked boss roster so the pacing of each stretch reads better.",
        es: "Mejoras de calidad de vida en Supervivencia, incluyendo una lista de jefes rehecha para que el ritmo de cada tramo se lea mejor."),
      ChangelogEntry(category: clcImproved,
        en: "Roguelite mode reworked, including a new destructible-wall system and smoother progression.",
        es: "Modo Roguelite renovado, con un nuevo sistema de muros destructibles y progresión más fluida."),
      ChangelogEntry(category: clcImproved,
        en: "Shop and power-up installer relaid out so they sit correctly in the widescreen layout.",
        es: "Tienda e instalador de potenciadores redistribuidos para encajar correctamente en el diseño panorámico."),
      ChangelogEntry(category: clcImproved,
        en: "Dragon wallpaper silhouettes redrawn with articulated legs and wings.",
        es: "Siluetas de dragon del fondo de escritorio redibujadas con patas y alas articuladas."),
      ChangelogEntry(category: clcImproved,
        en: "Star explosion visuals improved.",
        es: "Visuales de las explosiones estelares mejoradas."),
      ChangelogEntry(category: clcImproved,
        en: "Refreshed the PvP lobby window with a more compact layout, punchier buttons, glossy highlights, brighter focus states and clearer player lists.",
        es: "Ventana de la sala PvP renovada con un diseño más compacto, botones más vistosos, brillos, estados de foco más claros y listas de jugadores más legibles."),
      ChangelogEntry(category: clcImproved,
        en: "HUD notifications and power-up discoveries now appear as cleaner, stacking toasts.",
        es: "Las notificaciones del HUD y los descubrimientos de potenciadores ahora aparecen como avisos apilables más limpios."),
      ChangelogEntry(category: clcImproved,
        en: "Reworked the splash/boot screen and refined enemy visual effects.",
        es: "Se rehizo la pantalla de inicio/arranque y se refinaron los efectos visuales de los enemigos."),
      ChangelogEntry(category: clcImproved,
        en: "Further refined the destructible-wall system for better placement and feel.",
        es: "Se refinó aún más el sistema de muros destructibles para mejor colocación y sensación."),

      # Tuning
      ChangelogEntry(category: clcBalance,
        en: "Late-game scaling retuned: enemy counts grow on a smoother, uncapped curve and enemies (plus endless bosses past wave 60) gain compounding health and damage, while regular enemies were pulled back so deep waves lean on bosses and elites instead of sheer chip damage.",
        es: "Escalado de fin de partida reajustado: la cantidad de enemigos crece en una curva más suave y sin tope y los enemigos (y los jefes infinitos pasada la oleada 60) ganan vida y daño acumulativos, mientras que los enemigos normales se moderaron para que las oleadas profundas dependan de jefes y elites en vez del desgaste constante."),
      ChangelogEntry(category: clcBalance,
        en: "Element masteries retuned around the new fire and poison split: Fire Mastery grants +350% damage, +50% duration and +45% slow, while Poison Mastery grants +150% damage, +200% duration and +40% slow.",
        es: "Maestrías elementales reajustadas con la nueva división de fuego y veneno: Maestría de Fuego otorga +350% de daño, +50% de duración y +45% de ralentización, y Maestría de Veneno otorga +150% de daño, +200% de duración y +40% de ralentización."),
      ChangelogEntry(category: clcBalance,
        en: "Celestial Veil buffed: it now nullifies two hits per wave and refreshes at the start of each wave. Rotating shields were nerfed in exchange.",
        es: "Velo Celestial reforzado: ahora anula dos impactos por oleada y se restablece al comienzo de cada una. Los escudos giratorios se ajustaron a la baja a cambio."),
      ChangelogEntry(category: clcBalance,
        en: "Bosses buffed across the board, including a retuned final boss encounter.",
        es: "Jefes reforzados en general, incluyendo un reajuste del jefe final."),
      ChangelogEntry(category: clcBalance,
        en: "The Summoner King is tougher: more health and a sturdier defensive stance, so clearing its legion now matters more.",
        es: "El Rey Invocador es más resistente: más vida y una postura defensiva más solida, así que limpiar su legion ahora importa más."),
      ChangelogEntry(category: clcBalance,
        en: "The Meteor Striker hits a little harder and takes a little more punishment across all phases.",
        es: "El Golpeador de Meteoros pega un poco más fuerte y aguanta un poco más de castigo en todas las fases."),
      ChangelogEntry(category: clcBalance,
        en: "The Laser Architect's later phases are more readable: fewer simultaneous beams and shorter laser sweeps make its grid and cage attacks fairer to dodge.",
        es: "Las fases avanzadas del Arquitecto Láser son más legibles: menos rayos simultaneos y barridos más cortos hacen que sus ataques de rejilla y jaula sean más justos de esquivar."),
      ChangelogEntry(category: clcBalance,
        en: "Roguelite boss rolls adjusted for a better spread of encounters, and Recursion retuned to +8%, +14% and +20% permanent damage.",
        es: "Las tiradas de jefes del Roguelite se ajustaron para un mejor reparto de encuentros, y Recursion se reajusto a +8%, +14% y +20% de daño permanente."),
      ChangelogEntry(category: clcBalance,
        en: "Arcane Orbs buffed: +50% base damage. They deal pure damage with no elemental effect, so they now hit noticeably harder to compensate.",
        es: "Orbes Arcanos reforzados: +50% de daño base. Hacen daño puro sin efecto elemental, así que ahora pegan notablemente más fuerte para compensar."),
      ChangelogEntry(category: clcBalance,
        en: "Reworked the Giant Slayer power-up.",
        es: "Rework del potenciador Cazagigantes."),
      ChangelogEntry(category: clcBalance,
        en: "Agility nerfed: its speed boost now grants +33% movement speed, down from +40%.",
        es: "Agilidad ajustada: su aumento de velocidad ahora otorga +33% de velocidad de movimiento, en lugar de +40%."),
      ChangelogEntry(category: clcBalance,
        en: "Healing is now credited to your healing multiplier, so healing stats add up correctly.",
        es: "La curación ahora se atribuye a tu multiplicador de curación, así que las estadísticas de curación cuadran correctamente."),

      # Fixes
      ChangelogEntry(category: clcFixed,
        en: "Fixed bosses occasionally dying at random.",
        es: "Se corrigió que los jefes murieran al azar en ocasiones."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed thunderstrike and void rift warnings spawning incorrectly.",
        es: "Se corrigió que los avisos de rayo y de grietas del vacío aparecieran de forma incorrecta."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Pulse Armor and orbital cube behaviour.",
        es: "Se corrigió el comportamiento de la Armadura de Pulso y del cubo orbital."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed the Survival timer being drawn in the wrong position.",
        es: "Se corrigió que el temporizador de Supervivencia se dibujara en la posición equivocada."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed Echo bullet hit detection and Curse/Echo interactions.",
        es: "Corregida la detección de impactos de las balas Eco y las interacciones Maldición/Eco."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed player movement speed skyrocketing when certain power-ups were removed.",
        es: "Se corrigió que la velocidad del jugador se disparara al quitar ciertos potenciadores."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed several boss special-attack and behavior bugs.",
        es: "Se corrigieron varios errores en ataques especiales y comportamientos de jefes."),
      ChangelogEntry(category: clcFixed,
        en: "Fixed unlock-system bugs, plus assorted settings, debug panel and HUD fixes.",
        es: "Se corrigieron errores del sistema de desbloqueos, además de varios arreglos en ajustes, panel de depuración y HUD.")
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

proc entryHead(e: ChangelogEntry): string =
  if getLanguage() == Spanish: e.headEs else: e.headEn

proc entryText(e: ChangelogEntry): string =
  if getLanguage() == Spanish: e.es else: e.en

proc versionTitle(v: ChangelogVersion): string =
  if getLanguage() == Spanish: v.titleEs else: v.titleEn

proc versionSubtitle(v: ChangelogVersion): string =
  let s = if getLanguage() == Spanish: v.subtitleEs else: v.subtitleEn
  if s.len == 0: t(tkChangelogSince) else: s

proc newChangelogWindow*(screenWidth, screenHeight: int): ChangelogWindow =
  let windowWidth = CHANGELOG_WINDOW_WIDTH
  let windowHeight = CHANGELOG_WINDOW_HEIGHT
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
    scrollOffset: 0,
    page: 0
  )

proc resetChangelogView*(cl: ChangelogWindow) =
  ## Called when the window is opened: newest version, scrolled to the top.
  cl.page = 0
  cl.scrollOffset = 0

proc legacyView(): bool =
  ## The profile's choice between a page per version (default) and the legacy
  ## single scroll through every version.
  not globalSettings.isNil and globalSettings.changelogLegacyView

# Layout
# The changelog is flattened into positioned lines. Wrapping all of it is not
# free, so the result is cached and only rebuilt when the text width, the
# language or the page (or view) changes.

const
  HeaderColor = Color(r: 230, g: 245, b: 255, a: 255)
  VersionColor = Color(r: 255, g: 200, b: 120, a: 255)
  SubtitleColor = Color(r: 135, g: 145, b: 160, a: 255)
  HeadColor = Color(r: 240, g: 244, b: 250, a: 255)
  BodyColor = Color(r: 192, g: 200, b: 212, a: 255)
  PointMarkerColor = Color(r: 115, g: 128, b: 148, a: 255)
  AccentColor = Color(r: 255, g: 180, b: 80, a: 255)
  RuleColor = Color(r: 255, g: 180, b: 80, a: 90)

proc addWrapped(layout: var ChangelogLayout, y: var int, kind: LineKind,
                text: string, x: int, maxWidth: int32, color: Color,
                marker: MarkerKind = mkNone, markerColor = PointMarkerColor) =
  ## Wraps `text` into lines starting at `x`. Continuation lines keep the same
  ## x, so a bullet's text forms a clean block beside its marker.
  var wrapped = wrapTextLines(text, maxWidth - x.int32, CL_TEXT_SIZE)
  # Don't leave a short word ("1.", "120.") alone on the last line: pull the
  # previous line's last word down to join it.
  if wrapped.len >= 2 and wrapped[^1].len <= 4:
    let prev = wrapped[^2]
    let cut = prev.rfind(' ')
    if cut > 0:
      wrapped[^1] = prev[cut + 1 .. ^1] & " " & wrapped[^1]
      wrapped[^2] = prev[0 ..< cut]
  var first = true
  for wline in wrapped:
    layout.lines.add(ChangelogLine(kind: kind, text: wline, color: color,
                                   x: x, y: y,
                                   marker: (if first: marker else: mkNone),
                                   markerColor: markerColor))
    y += CL_LINE_H
    first = false

proc addVersionEntries(layout: var ChangelogLayout, y: var int,
                       v: ChangelogVersion, textWidth: int32) =
  ## One version's entries, grouped by category in category order.
  # Bold text is drawn twice, 1px apart, so it is 1px wider than measured.
  let boldWidth = textWidth - 2
  for cat in ChangelogCategory:
    var any = false
    for e in v.entries:
      if e.category != cat: continue
      if not any:
        y += CL_CATEGORY_GAP
        layout.lines.add(ChangelogLine(kind: lkCategory, text: categoryLabel(cat),
                                       color: categoryColor(cat), y: y))
        y += CL_LINE_H + CL_ENTRY_GAP
        any = true
      let head = entryHead(e)
      let body = entryText(e).split('\n')
      if head.len > 0:
        layout.addWrapped(y, lkHead, head, CL_HEAD_INDENT, boldWidth, HeadColor,
                          mkSquare, categoryColor(cat))
        for point in body:
          layout.addWrapped(y, lkBody, point, CL_POINT_INDENT, textWidth, BodyColor,
                            mkPoint)
      else:
        # Older, headline-less entries: each paragraph is a top-level bullet.
        for para in body:
          layout.addWrapped(y, lkBody, para, CL_HEAD_INDENT, textWidth, BodyColor,
                            mkSquare, categoryColor(cat))
      y += CL_ENTRY_GAP

proc buildPageLayout(textWidth: int32, page: int): ChangelogLayout =
  ## Paged view: just one version's entries. Its title and subtitle live in
  ## the fixed navigation bar above the scrolling text.
  var y = 0
  result.addVersionEntries(y, changelog[page], textWidth)
  result.height = y

proc buildLegacyLayout(textWidth: int32): ChangelogLayout =
  ## Legacy view: every version in one scroll, newest first.
  var y = 0
  result.lines.add(ChangelogLine(kind: lkHeader, text: t(tkChangelogHeader),
                                 color: HeaderColor, y: y))
  y += CL_HEADER_ADVANCE

  for vi, v in changelog:
    if vi > 0: y += CL_VERSION_GAP
    result.versionTops.add(y)
    result.lines.add(ChangelogLine(kind: lkVersion, text: versionTitle(v),
                                   color: VersionColor, y: y, badge: v.latest))
    y += CL_LINE_H
    result.lines.add(ChangelogLine(kind: lkSubtitle, text: versionSubtitle(v),
                                   color: SubtitleColor, y: y))
    y += CL_LINE_H
    result.addVersionEntries(y, v, textWidth)

  result.height = y

proc contentMetrics(cl: ChangelogWindow): tuple[x, y, w, h: int] =
  let x = cl.window.x + WINDOW_PADDING
  let y = cl.window.y + TITLE_BAR_HEIGHT + WINDOW_PADDING
  let w = cl.window.width - WINDOW_PADDING * 2
  let h = cl.window.height - TITLE_BAR_HEIGHT - WINDOW_PADDING * 2
  (x, y, w, h)

type
  ChangelogGeometry = object
    ## Every hit-testable and drawn region, computed in one place so what is
    ## drawn and what is clickable can never drift apart.
    contentX, contentY, contentW, contentH: int
    navH: int                 # 0 in the legacy view (no navigation bar)
    viewX, viewY, viewW, viewH: int   # scrolling text viewport
    prevBtn, nextBtn: Rectangle
    dotsX, dotsY: int         # left edge / top of the page-dot row
    footerY: int
    checkbox: Rectangle       # box plus label: the whole row toggles it
    boxX, boxY: int

proc pageDotRect(g: ChangelogGeometry, i: int): Rectangle =
  ## The clickable cell of page dot `i` (the dot is drawn centred inside it).
  Rectangle(x: (g.dotsX + i * CL_DOT_PITCH).float32, y: g.dotsY.float32,
            width: CL_DOT_PITCH.float32, height: CL_DOT_PITCH.float32)

proc geometry(cl: ChangelogWindow, legacy: bool): ChangelogGeometry =
  let (cx, cy, cw, ch) = contentMetrics(cl)
  result.contentX = cx
  result.contentY = cy
  result.contentW = cw
  result.contentH = ch
  result.navH = if legacy: 0 else: CL_NAV_H

  let btnY = cy + (CL_NAV_H - CL_NAV_BTN) div 2
  result.prevBtn = Rectangle(x: (cx + 12).float32, y: btnY.float32,
                             width: CL_NAV_BTN.float32, height: CL_NAV_BTN.float32)
  result.nextBtn = Rectangle(x: (cx + cw - 12 - CL_NAV_BTN).float32, y: btnY.float32,
                             width: CL_NAV_BTN.float32, height: CL_NAV_BTN.float32)
  result.dotsX = cx + (cw - changelog.len * CL_DOT_PITCH) div 2
  result.dotsY = cy + CL_NAV_H - CL_DOT_PITCH - 6

  result.footerY = cy + ch - CL_FOOTER_H
  result.viewX = cx
  result.viewY = cy + result.navH + CL_PAD_Y
  result.viewW = cw
  result.viewH = result.footerY - CL_PAD_Y - result.viewY

  result.boxX = cx + 14
  result.boxY = result.footerY + (CL_FOOTER_H - CL_CHECKBOX) div 2
  let labelW = measureText(t(tkChangelogLegacyView), CL_TEXT_SIZE)
  result.checkbox = Rectangle(x: result.boxX.float32, y: result.boxY.float32 - 4,
                              width: (CL_CHECKBOX + 10 + labelW).float32,
                              height: (CL_CHECKBOX + 8).float32)

proc ensureLayout(cl: ChangelogWindow, g: ChangelogGeometry, legacy: bool) =
  ## Rebuilds cl.layout if the text width, the language, the page or the view
  ## changed.
  let textWidth = (g.viewW - CL_MARGIN_LEFT - CL_MARGIN_RIGHT).int32
  let page = if legacy: -1 else: cl.page
  if not cl.layoutValid or cl.layoutWidth != textWidth or
     cl.layoutLanguage != getLanguage() or cl.layoutPage != page:
    cl.layout = if legacy: buildLegacyLayout(textWidth)
                else: buildPageLayout(textWidth, page)
    cl.layoutWidth = textWidth
    cl.layoutLanguage = getLanguage()
    cl.layoutPage = page
    cl.layoutValid = true

proc goToPage(cl: ChangelogWindow, page: int) =
  let target = clamp(page, 0, changelog.high)
  if target != cl.page:
    cl.page = target
    cl.scrollOffset = 0

proc toggleLegacyView(cl: ChangelogWindow) =
  ## Flip the view and save the choice. The reader keeps their place: the
  ## legacy scroll opens at the version that was on screen, and the paged view
  ## opens on the version the legacy scroll was showing.
  if globalSettings.isNil:
    return
  let wasLegacy = globalSettings.changelogLegacyView
  if wasLegacy:
    var page = 0
    for i, top in cl.layout.versionTops:
      if top <= cl.scrollOffset + CL_LINE_H: page = i
    cl.page = page
    cl.scrollOffset = 0
  globalSettings.changelogLegacyView = not wasLegacy
  discard saveSettings(globalSettings)
  if not wasLegacy:
    let g = cl.geometry(legacy = true)
    cl.ensureLayout(g, legacy = true)
    if cl.page < cl.layout.versionTops.len:
      cl.scrollOffset = cl.layout.versionTops[cl.page]

proc updateChangelogWindow*(cl: ChangelogWindow, dt: float32,
                            screenWidth, screenHeight: int,
                            allWindows: openArray[OSWindow]) =
  ## Update window chrome, paging and scrolling. Closing is signalled by
  ## setting cl.window.visible = false (handled here), matching the help window.
  updateOSWindow(cl.window, dt)
  if not cl.window.visible:
    return

  let shouldClose = handleOSWindowInput(cl.window, screenWidth, screenHeight, allWindows)
  if shouldClose:
    cl.window.visible = false
    return

  if cl.window.minimized:
    return

  # Clicks: only if this window took the click and is on top where it landed.
  if cl.window.handledClickThisFrame:
    let mousePos = getVirtualMousePosition()
    if isWindowTopmostAtPoint(cl.window, mousePos.x, mousePos.y, allWindows):
      let g = cl.geometry(legacyView())
      if checkCollisionPointRec(mousePos, g.checkbox):
        cl.toggleLegacyView()
      elif not legacyView():
        if checkCollisionPointRec(mousePos, g.prevBtn):
          cl.goToPage(cl.page - 1)
        elif checkCollisionPointRec(mousePos, g.nextBtn):
          cl.goToPage(cl.page + 1)
        else:
          for i in 0 ..< changelog.len:
            if checkCollisionPointRec(mousePos, pageDotRect(g, i)):
              cl.goToPage(i)
              break

  # Keyboard / dpad paging. Left = newer, Right = older, like the buttons.
  let legacy = legacyView()
  if not legacy and cl.window.focused:
    if isKeyPressed(KeyboardKey.Left) or gamepadNavPressed(gnLeft):
      cl.goToPage(cl.page - 1)
    elif isKeyPressed(KeyboardKey.Right) or gamepadNavPressed(gnRight):
      cl.goToPage(cl.page + 1)

  let g = cl.geometry(legacy)
  cl.ensureLayout(g, legacy)
  let maxScroll = max(0, cl.layout.height - g.viewH)

  let wheel = getPointerWheelMove()
  if wheel != 0:
    cl.scrollOffset = clamp(cl.scrollOffset - int(wheel * CHANGELOG_SCROLL_STEP),
                            0, maxScroll)
  else:
    # Keep the offset valid if the window was just opened / language changed.
    cl.scrollOffset = clamp(cl.scrollOffset, 0, maxScroll)

proc drawTextBold(text: string, x, y, size: int32, color: Color) =
  ## Faux bold for the default bitmap font: the same glyphs 1px apart.
  drawText(text, x, y, size, color)
  drawText(text, x + 1, y, size, color)

proc drawLatestBadge(x, y: int32) =
  let label = t(tkChangelogLatest)
  let bw = measureText(label, CL_SMALL_SIZE) + 12
  drawRectangle(x, y + 1, bw, 18, Color(r: 90, g: 255, b: 150, a: 255))
  drawText(label, x + 6, y + 5, CL_SMALL_SIZE, Color(r: 8, g: 16, b: 12, a: 255))

proc latestBadgeWidth(): int32 =
  measureText(t(tkChangelogLatest), CL_SMALL_SIZE) + 12

proc drawNavButton(r: Rectangle, pointsLeft, enabled, hovered: bool) =
  let bg = if not enabled: Color(r: 18, g: 20, b: 26, a: 255)
           elif hovered: Color(r: 60, g: 52, b: 34, a: 255)
           else: Color(r: 30, g: 32, b: 40, a: 255)
  let fg = if not enabled: Color(r: 60, g: 64, b: 74, a: 255)
           elif hovered: Color(r: 255, g: 220, b: 150, a: 255)
           else: AccentColor
  drawRectangle(r.x.int32, r.y.int32, r.width.int32, r.height.int32, bg)
  drawRectangleLines(r, (if enabled and hovered: 2.0'f32 else: 1.0'f32), fg)
  # Chevron as a filled triangle. raylib culls clockwise triangles, so both
  # arrows are listed counter-clockwise as seen on screen.
  let cx = r.x + r.width / 2
  let cy = r.y + r.height / 2
  if pointsLeft:
    drawTriangle(Vector2(x: cx - 7, y: cy), Vector2(x: cx + 5, y: cy + 9),
                 Vector2(x: cx + 5, y: cy - 9), fg)
  else:
    drawTriangle(Vector2(x: cx + 7, y: cy), Vector2(x: cx - 5, y: cy - 9),
                 Vector2(x: cx - 5, y: cy + 9), fg)

proc drawNavBar(cl: ChangelogWindow, g: ChangelogGeometry, mouse: Vector2) =
  ## Paged view header: prev / version title and subtitle / next, with a row
  ## of page dots (the current page highlighted) under the title.
  let v = changelog[cl.page]
  let midX = g.contentX + g.contentW div 2

  drawNavButton(g.prevBtn, pointsLeft = true, enabled = cl.page > 0,
                hovered = checkCollisionPointRec(mouse, g.prevBtn))
  drawNavButton(g.nextBtn, pointsLeft = false, enabled = cl.page < changelog.high,
                hovered = checkCollisionPointRec(mouse, g.nextBtn))

  let title = versionTitle(v)
  let titleW = measureText(title, CL_TEXT_SIZE) + 1
  let badgeW = if v.latest: latestBadgeWidth() + 12 else: 0'i32
  let titleX = (midX - (titleW + badgeW) div 2).int32
  let titleY = (g.contentY + 8).int32
  drawTextBold(title, titleX, titleY, CL_TEXT_SIZE, VersionColor)
  if v.latest:
    drawLatestBadge(titleX + titleW + 12, titleY)

  let subtitle = versionSubtitle(v)
  drawText(subtitle, (midX - measureText(subtitle, CL_TEXT_SIZE) div 2).int32,
           titleY + CL_LINE_H, CL_TEXT_SIZE, SubtitleColor)

  for i in 0 ..< changelog.len:
    let cell = pageDotRect(g, i)
    let hovered = checkCollisionPointRec(mouse, cell)
    let size: int32 = if i == cl.page: 10 else: 8
    let dx = (cell.x + (cell.width - size.float32) / 2).int32
    let dy = (cell.y + (cell.height - size.float32) / 2).int32
    if i == cl.page:
      drawRectangle(dx, dy, size, size, AccentColor)
    else:
      drawRectangle(dx, dy, size, size,
                    if hovered: Color(r: 150, g: 130, b: 95, a: 255)
                    else: Color(r: 70, g: 76, b: 90, a: 255))

  drawRectangle(g.contentX.int32 + 1, (g.contentY + g.navH).int32, g.contentW.int32 - 2, 1,
                RuleColor)

proc drawFooter(g: ChangelogGeometry, mouse: Vector2) =
  drawRectangle(g.contentX.int32 + 1, g.footerY.int32, g.contentW.int32 - 2, 1, RuleColor)
  let hovered = checkCollisionPointRec(mouse, g.checkbox)
  drawCheckbox(g.boxX, g.boxY, CL_CHECKBOX, legacyView(), hovered)
  drawText(t(tkChangelogLegacyView), (g.boxX + CL_CHECKBOX + 10).int32,
           (g.boxY + (CL_CHECKBOX - CL_TEXT_SIZE) div 2 + 1).int32, CL_TEXT_SIZE,
           if hovered: HeadColor else: SubtitleColor)

proc drawChangelogWindow*(cl: ChangelogWindow) =
  if not cl.window.visible:
    return

  drawWindowChrome(cl.window)
  if cl.window.minimized:
    return

  let legacy = legacyView()
  let g = cl.geometry(legacy)
  let mouse = getVirtualMousePosition()

  # Panel background
  drawRectangle(g.contentX.int32, g.contentY.int32, g.contentW.int32, g.contentH.int32,
               Color(r: 10, g: 12, b: 18, a: 255))
  drawRectangleLines(Rectangle(x: g.contentX.float32, y: g.contentY.float32,
                                width: g.contentW.float32, height: g.contentH.float32),
                    1, Color(r: 255, g: 180, b: 80, a: 200))

  cl.ensureLayout(g, legacy)
  if not legacy:
    cl.drawNavBar(g, mouse)

  # Clip region so scrolled content does not bleed over the bars.
  beginVirtualScissorMode(g.viewX.int32, g.viewY.int32, g.viewW.int32, g.viewH.int32)

  let baseX = g.viewX + CL_MARGIN_LEFT
  let rightX = g.viewX + g.viewW - CL_MARGIN_RIGHT
  let top = g.viewY - cl.scrollOffset
  for line in cl.layout.lines:
    let yPos = top + line.y
    # Skip lines fully outside the visible band (cheap culling; the header is
    # the tallest line at CL_HEADER_ADVANCE).
    if yPos + CL_HEADER_ADVANCE < g.viewY or yPos > g.viewY + g.viewH:
      continue
    let x = (baseX + line.x).int32
    let y = yPos.int32
    case line.kind
    of lkHeader:
      drawTextBold(line.text, x, y, CL_TITLE_SIZE, line.color)
      drawRectangle(baseX.int32, y + 36, (rightX - baseX).int32, 1,
                    Color(r: 255, g: 180, b: 80, a: 120))
    of lkVersion:
      drawTextBold(line.text, x, y, CL_TEXT_SIZE, line.color)
      if line.badge:
        drawLatestBadge(x + measureText(line.text, CL_TEXT_SIZE) + 12, y)
    of lkSubtitle:
      drawText(line.text, x, y, CL_TEXT_SIZE, line.color)
    of lkCategory:
      drawTextBold(line.text, x, y, CL_TEXT_SIZE, line.color)
      # A rule runs from the label to the right edge, marking the section.
      let ruleX = x + measureText(line.text, CL_TEXT_SIZE) + 12
      if ruleX < rightX:
        drawRectangle(ruleX, y + 9, rightX.int32 - ruleX, 2,
                      Color(r: line.color.r, g: line.color.g, b: line.color.b, a: 80))
    of lkHead:
      drawTextBold(line.text, x, y, CL_TEXT_SIZE, line.color)
    of lkBody:
      drawText(line.text, x, y, CL_TEXT_SIZE, line.color)

    case line.marker
    of mkNone: discard
    of mkSquare:
      drawRectangle((baseX + 2).int32, y + 6, 7, 7, line.markerColor)
    of mkPoint:
      drawRectangle((baseX + CL_HEAD_INDENT + 4).int32, y + 8, 5, 5, line.markerColor)

  endScissorMode()

  # Scrollbar
  let total = cl.layout.height
  if total > g.viewH:
    let trackX = g.viewX + g.viewW - 8
    let thumbH = max(24, int(float32(g.viewH) * float32(g.viewH) / float32(total)))
    let maxScroll = max(1, total - g.viewH)
    let thumbY = g.viewY + int(float32(g.viewH - thumbH) *
                               float32(cl.scrollOffset) / float32(maxScroll))
    drawRectangle(trackX.int32, g.viewY.int32, 5, g.viewH.int32,
                 Color(r: 25, g: 28, b: 36, a: 255))
    drawRectangle(trackX.int32, thumbY.int32, 5, thumbH.int32,
                 Color(r: 255, g: 180, b: 80, a: 230))

  drawFooter(g, mouse)
  drawResizeIndicator(cl.window)
