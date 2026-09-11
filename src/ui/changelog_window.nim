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
    titleEn: "Version 6.2.2",
    titleEs: "Versión 6.2.2",
    subtitleEn: "Changes since v6.2.1",
    subtitleEs: "Cambios desde v6.2.1",
    latest: true,
    entries: @[
      # --- Game feel ---
      ChangelogEntry(category: clcNew,
        en: "You can dash. Tap Shift (or LT on a controller) for a short burst of speed in the direction you are moving, on a 2.5 second cooldown. It grants no invulnerability: the dash moves you out of the way, it does not let you pass through a hit, so it has to be aimed at open space and spent deliberately rather than mashed. It is available from the very first wave rather than waiting on a lucky legendary, so a real dodge is now something you can always do instead of something you might unlock. Rebindable in Settings > Controls.",
        es: "Ya puedes impulsarte. Pulsa Shift (o LT en el mando) para un empujón corto de velocidad en la dirección en la que te mueves, con 2.5 segundos de espera. No otorga invulnerabilidad: el impulso te aparta del peligro, no te deja atravesar un golpe, así que hay que apuntarlo a un hueco libre y gastarlo con criterio en vez de aporrearlo. Está disponible desde la primera oleada en vez de depender de una legendaria afortunada, así que esquivar de verdad ya es algo que siempre puedes hacer y no algo que quizás desbloquees. Reasignable en Ajustes > Controles."),
      ChangelogEntry(category: clcImproved,
        en: "Hits have weight now. Killing something freezes the game for a few frames, elites bite harder, and a boss going down gets a heavy freeze followed by a long slow-motion dwell. Taking a hit yourself freezes too. Screen shake was also raised roughly three and a half times across the board: a kill used to move the camera less than a pixel and a boss kill about four, which was at or below the point where the eye can register it at all.",
        es: "Los golpes ahora pesan. Matar algo congela el juego unos fotogramas, las élites muerden más fuerte, y la caída de un jefe recibe un congelado duro seguido de una cámara lenta larga. Recibir un golpe también congela. La sacudida de pantalla también subió unas tres veces y media: matar movía la cámara menos de un píxel y matar a un jefe unos cuatro, justo en el límite donde el ojo ya no lo percibe."),
      ChangelogEntry(category: clcImproved,
        en: "Damage numbers spray instead of stacking. Every floating number -- damage, healing, coins, experience, buff pickups -- used to launch straight up at the same speed with only a little sideways jitter, so a burst of hits on one enemy piled into a single unreadable column. Each one now gets its own launch angle and speed, its own weight, drift, tilt and size, and consecutive hits are thrown to alternating sides, so a stream of damage fans out like a fountain. Criticals are thrown harder but in a narrower arc, so they stay near the hit where you are already looking. The numbers also punch in oversized on the frame they appear and hold full brightness for the first half of their life instead of fading from the moment they spawn, which makes them far easier to read in a crowd.",
        es: "Los números de daño se dispersan en vez de amontonarse. Cada número flotante -- daño, curación, monedas, experiencia, objetos recogidos -- salía disparado hacia arriba a la misma velocidad con solo un poco de variación lateral, así que una ráfaga de golpes sobre un enemigo se apilaba en una columna ilegible. Ahora cada uno recibe su propio ángulo y velocidad de salida, su propio peso, deriva, inclinación y tamaño, y los golpes consecutivos se lanzan a lados alternos, de modo que un chorro de daño se abre como una fuente. Los críticos salen con más fuerza pero en un arco más estrecho, así que se quedan cerca del impacto, donde ya estás mirando. Los números además aparecen de golpe con un tamaño mayor y mantienen el brillo completo durante la primera mitad de su vida en vez de desvanecerse desde que salen, lo que los hace mucho más fáciles de leer entre la multitud."),
      ChangelogEntry(category: clcImproved,
        en: "The power-up reel stopped being a toll booth. A normal draft now settles in about a second instead of three and a half, and any key or click while it is spinning snaps it straight to the result. Legendary drafts keep a longer roll, since they are rare enough for the flourish to still be worth watching.",
        es: "La ruleta de mejoras dejó de ser un peaje. Una tirada normal se detiene en un segundo aproximadamente en vez de tres y medio, y cualquier tecla o clic mientras gira la lleva directa al resultado. Las tiradas legendarias mantienen un giro largo, porque son lo bastante raras como para que el gesto siga mereciendo la pena."),
      ChangelogEntry(category: clcImproved,
        en: "Loot comes to you. The pickup aura is much wider, and coins and orbs accelerate as they close in instead of drifting at a fixed speed that a boosted player could outrun. Collecting drops is a reward again rather than a chore of driving over each one. The Magnet consumable is still better -- it pulls from anywhere on the field.",
        es: "El botín viene a ti. El aura de recogida es mucho más amplia, y monedas y orbes aceleran al acercarse en vez de flotar a una velocidad fija que un jugador acelerado podía dejar atrás. Recoger objetos vuelve a ser una recompensa y no la tarea de pasar por encima de cada uno. El consumible Imán sigue siendo mejor: atrae desde cualquier punto del campo."),

      ChangelogEntry(category: clcImproved,
        en: "Level-ups no longer yank you out of the fight. Filling the bar now shows LEVEL UP and lets you play for a beat before the draft screen opens, so it never lands while your hands are still driving. Closing it eases you back in instead of dropping you cold: time ramps up from a crawl to full speed, you get a moment of invulnerability, and a ring pulses on your character so you can find yourself before the wave resumes.",
        es: "Subir de nivel ya no te arranca del combate. Al llenar la barra aparece SUBIÓ DE NIVEL y te deja jugar un instante antes de que se abra la pantalla de mejoras, así que nunca cae con las manos aún en los mandos. Al cerrarla vuelves poco a poco en vez de caer de golpe: el tiempo acelera desde muy lento hasta la velocidad normal, tienes un momento de invulnerabilidad, y un anillo late sobre tu personaje para que te encuentres antes de que la oleada siga."),
      ChangelogEntry(category: clcFixed,
        en: "The power-up reel stopped skipping itself. Every key the draft screen reads is also a gameplay key -- Space shoots, E places walls, A and D move, and the mouse button fires -- so a shot already in flight when the screen appeared would cancel the animation instantly, and sometimes pick a card straight after. The screen now ignores input for a moment and waits for you to actually let go of the controls before it listens.",
        es: "La ruleta de mejoras dejó de saltarse sola. Todas las teclas que lee la pantalla de mejoras son también teclas de juego -- Espacio dispara, E coloca muros, A y D mueven, y el botón del ratón dispara -- así que un disparo ya en marcha al aparecer la pantalla cancelaba la animación al instante, y a veces elegía una carta justo después. Ahora la pantalla ignora la entrada un momento y espera a que sueltes de verdad los controles antes de escuchar."),

      # --- Wave mode ---
      ChangelogEntry(category: clcNew,
        en: "Wave mode runs carry restore points now. Continuing from the boss-block checkpoint after a death used to be unlimited on every difficulty except Nightmare, which made a checkpoint a formality rather than something you spend. Each run now gets a fixed number of them -- unlimited on Easy, three on Normal, one on Hard, none on Nightmare -- shown as save-state platters in a meter on the pause menu, the death screen and the victory screen, so you always know how much rope you have left. The meter turns red and starts pulsing on your last one. Spending a restore point is not a number quietly moving either: the run holds on a full-screen sequence where the platter you just burned spins down, its write light gutters out, the surface fractures and the save scatters as data shards before the resumed wave counts you back in. On Easy it rebuilds itself, because there the budget never actually runs down. Spending one sticks: the count is written to the checkpoint the moment you continue, so dying again cannot refund it, and resuming a dead run from the desktop costs one on the same terms as the Continue button. When the last is gone the Continue option disappears and the dead platters stay on screen.",
        es: "Las partidas del modo oleadas ahora llevan puntos de restauración. Continuar desde el punto de control de bloque de jefe tras una muerte era ilimitado en todas las dificultades salvo Pesadilla, lo que convertía el punto de control en un trámite y no en algo que se gasta. Cada partida recibe ahora un número fijo -- ilimitados en Fácil, tres en Normal, uno en Difícil, ninguno en Pesadilla -- mostrados como discos de estado guardado en un medidor del menú de pausa, la pantalla de muerte y la de victoria, para que siempre sepas cuánto margen te queda. El medidor se pone rojo y late cuando te queda el último. Gastar un punto tampoco es un número que cambia en silencio: la partida se detiene en una secuencia a pantalla completa donde el disco que acabas de quemar frena, su luz de escritura se apaga, la superficie se agrieta y la copia se dispersa en fragmentos de datos antes de que la cuenta atrás te devuelva a la oleada. En Fácil se reconstruye, porque ahí el margen nunca se agota de verdad. Gastar uno es definitivo: la cuenta se escribe en el punto de control en cuanto continúas, así que volver a morir no lo devuelve, y retomar una partida muerta desde el escritorio cuesta uno igual que el botón de Continuar. Cuando se acaba el último, la opción de Continuar desaparece y los discos muertos se quedan en pantalla."),
      ChangelogEntry(category: clcNew,
        en: "Wave mode levels up. Enemies now drop experience orbs that stream toward you, fill a bar on the HUD, and hand you a power-up draft the moment it fills -- roughly once a wave. Until now every reward in wave mode waited for the end of a wave, so the minute-to-minute game gave you nothing back for a kill. Because levels carry the progression, the old between-wave draft has pulled back to the run-up before each boss.",
        es: "El modo oleadas sube de nivel. Los enemigos sueltan orbes de experiencia que vuelan hacia ti, llenan una barra en la interfaz y te dan una mejora en cuanto se llena, más o menos una vez por oleada. Hasta ahora toda recompensa del modo oleadas esperaba al final de la oleada, así que el juego minuto a minuto no te devolvía nada por matar. Como los niveles llevan la progresión, la antigua tirada entre oleadas se reserva ahora para la antesala de cada jefe."),
      ChangelogEntry(category: clcBalance,
        en: "Waves are crowds now, not a handful of sponges. A wave carries roughly four times as many enemies, each with a fraction of the health, so a wave costs about the same total effort but arrives as a swarm you cut through instead of three tough shapes you chip at. Wave 40 went from about 35 enemies to around 120.",
        es: "Las oleadas ahora son multitudes, no un puñado de esponjas. Una oleada trae unas cuatro veces más enemigos, cada uno con una fracción de la vida, así que cuesta más o menos el mismo esfuerzo total pero llega como un enjambre que atraviesas en vez de tres figuras duras que picas. La oleada 40 pasó de unos 35 enemigos a unos 120."),
      ChangelogEntry(category: clcBalance,
        en: "Getting stronger feels like getting stronger. Your per-wave growth and the enemies' were previously tuned to cancel each other out, which meant wave 40 played exactly like wave 10 with bigger numbers on both sides. Enemy health now grows far more slowly than your power does, so a build that took a clip to kill something early will delete it later. The difficulty comes from how many arrive, and from elites and bosses, which keep their own scaling.",
        es: "Hacerse fuerte por fin se nota. Tu crecimiento por oleada y el de los enemigos estaban ajustados para anularse, lo que hacía que la oleada 40 se jugara igual que la 10 con números más grandes en ambos lados. La vida enemiga ahora crece mucho más despacio que tu poder, así que lo que antes te costaba un cargador acabará cayendo de un golpe. La dificultad viene de cuántos llegan, y de élites y jefes, que mantienen su propia escala."),

      ChangelogEntry(category: clcBalance,
        en: "Rewards are paid per wave again, not per enemy. Waves now hold about four times as many enemies, and because coins, consumables and elite chances are all granted per kill, the whole economy had quietly quadrupled with them -- a full run was ending with tens of thousands of coins, hundreds of health pickups, 99 power-ups and a player who could not be killed. Every one of those channels is now scaled to the size of the wave, so a wave pays out roughly what it always did and only the number of bodies it is split across has changed. The swarm itself is untouched.",
        es: "Las recompensas vuelven a pagarse por oleada, no por enemigo. Las oleadas ahora tienen unas cuatro veces más enemigos, y como las monedas, los consumibles y la probabilidad de élites se conceden por muerte, toda la economía se había multiplicado con ellos: una partida terminaba con decenas de miles de monedas, cientos de curaciones, 99 mejoras y un jugador imposible de matar. Todos esos canales se ajustan ahora al tamaño de la oleada, así que una oleada paga más o menos lo de siempre y solo cambia entre cuántos cuerpos se reparte. El enjambre no se toca."),
      ChangelogEntry(category: clcBalance,
        en: "Healing that triggers per hit or per kill no longer scales with the crowd. Blood Bullets, Blood Aura and Life Steal all fire more often the more enemies are on screen, so the denser waves had handed those builds a large buff nobody chose -- one run healed more than the entire game had managed to deal to it. Life Steal stretches its kill requirement rather than shrinking the heal, so the number you were promised is still the number you get.",
        es: "La curación que se activa por golpe o por muerte ya no escala con la multitud. Balas de Sangre, Aura de Sangre y Robo de Vida se activan más cuanto más enemigos hay en pantalla, así que las oleadas más densas habían dado a esas construcciones una mejora enorme que nadie eligió: una partida se curó más de lo que el juego entero logró hacerle de daño. Robo de Vida alarga sus muertes necesarias en vez de reducir la curación, así que el número prometido sigue siendo el que recibes."),
      ChangelogEntry(category: clcNew,
        en: "Every enemy drops experience, always. Even the weakest one pays out, so a kill is never silent and orbs keep streaming in the whole wave -- that constant feedback is the point of them. Experience is the one reward with two sides, what an enemy gives and what a level costs, and only the second is a balance dial: levels now get more expensive over a long run instead of kills being made worthless. Wave mode reaches about twenty levels across sixty waves rather than sixty-plus, without ever quieting a kill. Roguelite and Time Survival keep their original pacing.",
        es: "Todos los enemigos sueltan experiencia, siempre. Hasta el más débil paga algo, así que una muerte nunca es muda y los orbes siguen llegando durante toda la oleada: esa respuesta constante es justo para lo que existen. La experiencia es la única recompensa con dos caras, lo que da un enemigo y lo que cuesta un nivel, y solo la segunda es una palanca de equilibrio: ahora los niveles se encarecen en partidas largas en vez de volver inútiles las muertes. El modo oleadas llega a unos veinte niveles en sesenta oleadas en lugar de sesenta y pico, sin silenciar ni una muerte. Roguelite y Supervivencia mantienen su ritmo original."),
      ChangelogEntry(category: clcBalance,
        en: "Elites are rare again. Their chance is rolled per enemy, so four times the bodies meant four times the elites -- more than a fifth of everything killed in a measured run, each paying double experience. An elite that common is just the baseline wearing a different colour.",
        es: "Las élites vuelven a ser raras. Su probabilidad se tira por enemigo, así que cuatro veces más cuerpos significaba cuatro veces más élites: más de una quinta parte de todo lo matado en una partida medida, y cada una pagando el doble de experiencia. Una élite tan común no es más que el enemigo normal con otro color."),

      ChangelogEntry(category: clcFixed,
        en: "Cornucopia was flooding the field. Its jackpot fires on a kill count, so the denser waves set it off about four times as often as intended -- in a measured wave-40 run it produced 486 of the 503 consumables collected, and the earlier drop-rate rebalance had barely dented the total because this one guaranteed path dwarfed every random roll. Its kill requirement now scales with the size of the wave. The jackpot itself is untouched: still three pickups and the full golden burst, just at the rate it was designed for.",
        es: "Cornucopia estaba inundando el campo. Su premio salta con una cuenta de muertes, así que las oleadas más densas lo activaban unas cuatro veces más de lo previsto: en una partida medida de oleada 40 produjo 486 de los 503 consumibles recogidos, y el reajuste anterior de probabilidad apenas había cambiado el total porque esta vía garantizada aplastaba a todas las tiradas aleatorias. Sus muertes necesarias ahora escalan con el tamaño de la oleada. El premio en sí no cambia: siguen siendo tres objetos y el estallido dorado completo, solo que al ritmo para el que se diseñó."),
      ChangelogEntry(category: clcBalance,
        en: "Enemies hit like they mean it again. Their damage barely grew across a run while your health pool multiplied many times over, so by the late waves a hit cost about three percent of your bar and nothing an enemy did could threaten you. Damage now scales properly with the waves, and a crowd keeps more of its individual bite, since the crowd is where the difficulty is supposed to live. Their health is deliberately still not scaling -- deleting them in one shot stays the reward for building up.",
        es: "Los enemigos vuelven a pegar en serio. Su daño apenas crecía a lo largo de una partida mientras tu vida se multiplicaba muchas veces, así que en las oleadas tardías un golpe costaba alrededor del tres por ciento de tu barra y nada de lo que hicieran podía amenazarte. El daño ahora escala como debe, y una multitud conserva más mordisco individual, porque la multitud es donde debe estar la dificultad. Su vida sigue sin escalar a propósito: borrarlos de un disparo sigue siendo la recompensa por crecer."),
      ChangelogEntry(category: clcBalance,
        en: "The shop's Max Health upgrade was the odd one out. Its bonus grew with every purchase on top of an already small starting pool, making it roughly three times more value per coin than any other slot at every depth -- seven purchases alone were about two thirds of a built player's entire health. It now flattens out as you stack it, while the first purchase is almost unchanged.",
        es: "La mejora de Vida Máxima de la tienda desentonaba. Su bonificación crecía con cada compra sobre una reserva inicial ya pequeña, lo que la hacía unas tres veces más rentable por moneda que cualquier otra ranura a cualquier profundidad: solo siete compras eran unos dos tercios de toda la vida de un jugador desarrollado. Ahora se aplana al acumularla, mientras que la primera compra apenas cambia."),

      # --- Tuning ---
      ChangelogEntry(category: clcBalance,
        en: "The shop's Damage and Fire Rate upgrades were pulled back slightly. Both compounded faster than intended over a long run -- damage especially, since each purchase paid more than the last, so a deep stack outran anything the waves could put in front of it. A first purchase is worth about what it always was; ten purchases in your damage output is down roughly 9%, and twenty in roughly 15%. Movement speed, bullet speed and walls are untouched.",
        es: "Las mejoras de Daño y Cadencia de la tienda bajan un poco. Las dos se acumulaban más rápido de lo previsto en partidas largas -- el daño sobre todo, porque cada compra pagaba más que la anterior, así que una inversión grande se escapaba de todo lo que las oleadas podían ponerle delante. Una primera compra vale casi lo mismo que siempre; con diez compras tu daño baja alrededor de un 9%, y con veinte alrededor de un 15%. Velocidad de movimiento, velocidad de bala y muros no se tocan."),
      ChangelogEntry(category: clcBalance,
        en: "Giant Slayer hits harder across all three levels: it now shaves 3%, 5.5% and 8% of an enemy's current health per hit, up from 2.5%, 4% and 6%. Its much smaller bite against bosses is unchanged, so it stays a crowd-clearing pick rather than a boss melter.",
        es: "Matagigantes pega más fuerte en sus tres niveles: ahora arranca el 3%, 5.5% y 8% de la vida actual del enemigo por golpe, frente al 2.5%, 4% y 6% anteriores. Su mordisco mucho menor contra jefes no cambia, así que sigue siendo una elección para limpiar hordas y no para fundir jefes."),

      # --- Interface ---
      ChangelogEntry(category: clcNew,
        en: "Healing has its own column in the stats window. The Power-Ups tab is now three panels -- what you picked, what it damaged, and what it healed -- instead of two, with healing ranked the same way damage is: every source in order, what it restored, and its share of the total, plus a running total at the foot of the column. Health consumables are counted alongside the power-ups, so the column adds up to every point of health you got back over the run. Healing was previously tacked on below the damage ranking, where a run with more than a couple of sources simply ran off the bottom of the panel with no way to see the rest.",
        es: "La curación tiene su propia columna en la ventana de estadísticas. La pestaña de Mejoras ahora son tres paneles -- lo que elegiste, lo que hizo daño y lo que curó -- en vez de dos, con la curación ordenada igual que el daño: cada fuente en orden, cuánto restauró y su porcentaje del total, más un total al pie de la columna. Los consumibles de salud se cuentan junto a las mejoras, así que la columna suma cada punto de vida que recuperaste en la partida. Antes la curación iba pegada debajo de la clasificación de daño, donde una partida con más de un par de fuentes se salía del panel sin manera de ver el resto."),
      ChangelogEntry(category: clcNew,
        en: "The stats lists scroll. All three columns of the Power-Ups tab take the mouse wheel, each one on its own, with a scrollbar that shows how much is still below the fold. A long run picks up dozens of power-ups and the timeline only ever showed the first twenty-odd of them; the rest are now reachable rather than quietly cut off.",
        es: "Las listas de estadísticas se desplazan. Las tres columnas de la pestaña de Mejoras responden a la rueda del ratón, cada una por separado, con una barra que muestra cuánto queda por debajo. Una partida larga recoge decenas de mejoras y la línea de tiempo solo mostraba las primeras veinte y pico; el resto ya se puede alcanzar en vez de quedar cortado en silencio."),
      ChangelogEntry(category: clcImproved,
        en: "Confirmation dialogs stop making you wait. The YES button now unlocks after one second instead of two -- still long enough to catch an accidental key, short enough that quitting or resetting on purpose no longer feels like a punishment.",
        es: "Los diálogos de confirmación ya no te hacen esperar tanto. El botón SÍ se desbloquea tras un segundo en vez de dos: sigue siendo suficiente para frenar una tecla accidental, pero salir o reiniciar a propósito ya no se siente como un castigo."),

      ChangelogEntry(category: clcFixed,
        en: "The Controls settings stopped running off the bottom of the panel. The tab had grown a controller selector and a second column of gamepad binds since its spacing was last set, and the two lines listing the fixed keys and the reserved controller buttons ended up printed past the edge of the panel, cut in half or missing entirely. The whole tab was retightened to fit, and its rows and buttons now come from a single shared layout, so the clickable area of every keybind button lines up with where the button is drawn. The two captions under the input selectors also sit with the row they describe instead of floating between two of them.",
        es: "Los ajustes de Controles dejaron de salirse por debajo del panel. La pestaña había ganado un selector de mando y una segunda columna de asignaciones desde la última vez que se fijó su espaciado, y las dos líneas que enumeran las teclas fijas y los botones reservados del mando acababan dibujadas más allá del borde del panel, cortadas por la mitad o directamente ausentes. Se ha reajustado toda la pestaña para que quepa, y sus filas y botones salen ahora de una única distribución compartida, así que la zona pulsable de cada botón de asignación coincide con donde se dibuja. Los dos pies de texto bajo los selectores de entrada también quedan junto a la fila que describen en vez de flotar entre dos de ellas."),

      # --- Startup ---
      ChangelogEntry(category: clcImproved,
        en: "The first launch got about eight times faster. The four music tracks are composed from scratch the first time you play, and that is by far the slowest thing the game ever does -- it was around thirteen seconds of staring at a loading screen, and most of a minute in a development build. All of it ran on a single core while the rest of the machine sat idle. The synthesiser now spreads each track across every core you have, and a cold first launch finishes in under two seconds. Everything is still fully built and cached before the game starts, exactly as before, and the tracks themselves come out identical to the last byte -- the music you already have cached is still the right music, so nothing is rebuilt.",
        es: "El primer arranque es unas ocho veces más rápido. Las cuatro pistas de música se componen desde cero la primera vez que juegas, y es de lejos lo más lento que hace el juego: eran unos trece segundos mirando una pantalla de carga, y casi un minuto en una versión de desarrollo. Todo ello corría en un solo núcleo mientras el resto de la máquina estaba parada. El sintetizador ahora reparte cada pista entre todos los núcleos disponibles, y un primer arranque en frío termina en menos de dos segundos. Todo se sigue creando y guardando por completo antes de que empiece el juego, igual que antes, y las pistas salen idénticas hasta el último byte: la música que ya tengas en caché sigue siendo la correcta, así que no se vuelve a crear nada."),

      # --- Fixes ---
      ChangelogEntry(category: clcFixed,
        en: "Fixed the background audio setup crashing the Windows release build on first launch. The progress counter used a threading instruction the Windows compiler builds incorrectly; it now uses a plain counter, so the first run generates its sounds and music without falling over.",
        es: "Corregido un fallo por el que la preparación de audio en segundo plano rompia la versión de Windows en el primer arranque. El contador de progreso usaba una instrucción de hilos que el compilador de Windows genera mal; ahora usa un contador normal, así que el primer arranque crea sus sonidos y su música sin caerse."),
      ChangelogEntry(category: clcFixed,
        en: "Slow motion never actually ran. Every kill was meant to trigger a moment of dilated time, but the effect was switched on and then never ticked, so it did nothing at all and quietly stayed on forever after your first kill. Time effects now run properly, and regular kills use a short freeze instead, which holds up when a whole crowd dies at once.",
        es: "La cámara lenta nunca llegó a funcionar. Cada muerte debía provocar un instante de tiempo dilatado, pero el efecto se activaba y luego nunca avanzaba, así que no hacía nada y se quedaba encendido para siempre tras tu primera baja. Los efectos de tiempo ya funcionan bien, y las muertes normales usan un congelado corto, que aguanta cuando muere una multitud entera a la vez."),
      ChangelogEntry(category: clcFixed,
        en: "Experience orbs were invisible in Time Survival. They dropped, homed in and were collected correctly, but were never drawn, so levelling up there looked like it happened out of nowhere. They are now drawn in every mode that spawns them.",
        es: "Los orbes de experiencia eran invisibles en Supervivencia. Caían, te seguían y se recogían bien, pero nunca se dibujaban, así que subir de nivel allí parecía salir de la nada. Ahora se dibujan en todos los modos que los generan."),
      ChangelogEntry(category: clcFixed,
        en: "The Reset To Defaults button in the controls settings can be clicked again. Its clickable area was pinned to a fixed number of key bindings, so adding the new dash binding left the button drawn in one place and clickable in another.",
        es: "El botón Restablecer Valores de los ajustes de control vuelve a poder pulsarse. Su zona pulsable estaba fijada a un número concreto de asignaciones, así que añadir la nueva tecla de impulso dejaba el botón dibujado en un sitio y pulsable en otro."),
      ChangelogEntry(category: clcFixed,
        en: "The level and experience bar no longer hangs outside the status panel in Wave mode. The panel sizes itself to its contents, and the level row was never counted, so with no processes installed to pad the panel out the bar spilled past the bottom border.",
        es: "La barra de nivel y experiencia ya no se sale del panel de estado en modo Oleadas. El panel se ajusta a su contenido y la fila de nivel nunca se contaba, así que sin procesos instalados que alargaran el panel la barra se salía por debajo del borde.")
    ]
  ),
  ChangelogVersion(
    titleEn: "Version 6.2.1",
    titleEs: "Versión 6.2.1",
    subtitleEn: "Changes since v6.2",
    subtitleEs: "Cambios desde v6.2",
    latest: false,
    entries: @[
      # --- Effects ---
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

      # --- Tuning ---
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

      # --- Interface ---
      ChangelogEntry(category: clcImproved,
        en: "The difficulty picker now carries a pulsing banner across the Easy and Normal cards marking them as the recommended starting point, so creating a profile is not a blind guess between four cards.",
        es: "El selector de dificultad ahora lleva un cartel palpitante sobre las tarjetas Facil y Normal que las marca como el punto de partida recomendado, para que crear un perfil no sea adivinar a ciegas entre cuatro tarjetas."),
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
      # --- Startup ---
      ChangelogEntry(category: clcFixed,
        en: "The first-launch audio setup no longer freezes the game. Building the four music tracks used to lock the window for several seconds at a time -- nothing animated and Windows could mark the game as not responding. The audio is now built in the background while the loading screen keeps running at full frame rate.",
        es: "La preparación de audio del primer arranque ya no congela el juego. Crear las cuatro pistas de música bloqueaba la ventana durante varios segundos seguidos -- nada se animaba y Windows podía marcar el juego como que no responde. Ahora el audio se crea en segundo plano mientras la pantalla de carga sigue funcionando a pleno rendimiento."),
      ChangelogEntry(category: clcImproved,
        en: "Redesigned loading screen: an audio_setup.exe window with SFX / MUSIC / MEMORY stage badges, an asset counter, the file being built right now, a smoothly filling progress bar and a live audio meter. It also notes that this only happens on the first run, since the generated audio is cached afterwards.",
        es: "Pantalla de carga rediseñada: una ventana audio_setup.exe con distintivos de fase SFX / MÚSICA / MEMORIA, un contador de recursos, el archivo que se está creando, una barra de progreso que se llena con suavidad y un medidor de audio en vivo. Además avisa de que esto solo ocurre en el primer arranque, porque el audio generado queda en caché."),

      # --- Tuning ---
      ChangelogEntry(category: clcBalance,
        en: "The Orbital Commander's final phase now belongs to its Orbital Scan: three walls per volley instead of two, arriving from three different edges (rake, crosswise, then a reverse rake), and the next scan starts telegraphing while the last wall is still crossing. The safe lane is a touch wider to compensate.",
        es: "La fase final del Comandante Orbital ahora gira en torno a su Escaneo Orbital: tres muros por descarga en vez de dos, llegando desde tres bordes distintos (barrido, transversal y barrido inverso), y el siguiente escaneo empieza a avisarse mientras el último muro aún cruza. El carril seguro es algo más ancho para compensar."),

      # --- Fixes ---
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
      # --- Headline features ---
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

      # --- Reworks and quality of life ---
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

      # --- Tuning ---
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

      # --- Fixes ---
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
      # --- Headline features ---
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

      # --- Reworks and quality of life ---
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

      # --- Tuning ---
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

      # --- Fixes ---
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
        es: "Se corrigieron errores del sistema de desbloqueos, ademas de varios arreglos en ajustes, panel de depuración y HUD.")
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
