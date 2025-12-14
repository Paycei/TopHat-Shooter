# Sistema de Guardado y Estadísticas - Top Hat Shooter

## 📂 Ubicación de Archivos

Todos los archivos de guardado se almacenan en la carpeta de AppData del sistema:

### Windows
```
%APPDATA%\TopHat\Shooter\
├── settings.json     # Configuraciones del juego
└── stats.json        # Estadísticas de juego
```

### macOS
```
~/Library/Application Support/TopHat/Shooter/
├── settings.json
└── stats.json
```

### Linux
```
~/.local/share/TopHat/Shooter/
├── settings.json
└── stats.json
```

## ⚙️ Sistema de Configuración (settings.json)

### Configuraciones Guardadas

El sistema guarda automáticamente las siguientes configuraciones:

```json
{
  "fpsLimit": 60,
  "volume": 0.5,
  "musicVolume": 0.5,
  "fullscreen": false,
  "showFPS": false,
  "mouseSupport": true,
  "showCursorInMenus": true
}
```

### Guardado Automático

Las configuraciones se guardan instantáneamente al:
- Cambiar el límite de FPS (al presionar Enter)
- Ajustar el volumen de sonido o música (al soltar el slider)
- Activar/desactivar checkboxes (Fullscreen, Show FPS, Mouse Support, etc.)

## 📊 Sistema de Estadísticas (stats.json)

### Estadísticas por Modo de Juego

El juego trackea estadísticas separadas para cada modo:

#### Wave Mode (Modo por Oleadas)
- Partidas jugadas
- Oleada más alta alcanzada
- Promedio de oleadas alcanzadas
- Mejores kills en una partida
- Mejores monedas recolectadas
- Total de kills acumulados
- Jefes derrotados
- Tiempo total de juego

#### Time Survival Mode (Modo Supervivencia)
- Partidas jugadas
- Tiempo de supervivencia más largo
- Tiempo promedio de supervivencia
- Mejores kills en una partida
- Mejores monedas recolectadas
- Total de kills acumulados
- Jefes derrotados
- Tiempo total de juego

#### Estadísticas Globales
- Total de partidas jugadas (todos los modos)
- Tiempo total de juego
- Primera fecha de juego
- Última fecha de juego

### Ejemplo de stats.json

```json
{
  "waveMode": {
    "gamesPlayed": 15,
    "totalKills": 1250,
    "totalCoins": 3500,
    "totalTimePlayed": 4500.0,
    "bestScore": 12,
    "bestKills": 150,
    "bestCoins": 450,
    "averageWaveReached": 8.5,
    "averageSurvivalTime": 300.0,
    "totalDeaths": 15,
    "bossesDefeated": 4,
    "highestWaveReached": 12,
    "longestSurvivalTime": 0.0
  },
  "timeMode": {
    "gamesPlayed": 8,
    "totalKills": 800,
    "totalCoins": 2200,
    "totalTimePlayed": 2400.0,
    "bestScore": 420,
    "bestKills": 120,
    "bestCoins": 350,
    "averageWaveReached": 0.0,
    "averageSurvivalTime": 300.0,
    "totalDeaths": 8,
    "bossesDefeated": 3,
    "highestWaveReached": 0,
    "longestSurvivalTime": 420.0
  },
  "totalGamesPlayed": 23,
  "totalPlayTime": 6900.0,
  "firstPlayDate": "2025-01-15 10:30:00",
  "lastPlayDate": "2025-01-20 18:45:00"
}
```

### Cuándo se Guardan las Estadísticas

Las estadísticas se guardan automáticamente:
- Al momento de Game Over
- Solo si NO se usaron cheats durante la partida
- Una sola vez por sesión de juego

### Acceder a las Estadísticas

Desde el menú principal, selecciona **"Statistics"** para ver:
- Estadísticas detalladas de ambos modos de juego
- Récords personales
- Tiempos de juego formateados
- Promedios y totales acumulados


## 🔧 Implementación Técnica

### Módulos Creados

1. **`save_system.nim`** - Sistema de guardado/carga
   - Manejo de rutas multiplataforma (Windows/macOS/Linux)
   - Funciones de serialización JSON
   - Guardado y carga de settings y estadísticas
   - Manejo robusto de errores

2. **`statistics.nim`** - Sistema de estadísticas
   - Definición de tipos `Statistics` y `GameModeStats`
   - Funciones de conversión JSON
   - Cálculo de promedios y actualización de récords
   - Formateo de tiempo legible

### Integración en el Juego

#### En `main.nim`:
- Inicialización y carga de estadísticas al inicio
- Guardado automático en Game Over
- Protección contra guardado múltiple
- Exclusión de partidas con cheats

#### En `settings.nim`:
- Import del módulo `save_system`
- Carga automática en `initSettings()`
- Guardado tras cada cambio de configuración

#### En `types.nim`:
- Nuevo estado `gsStatistics` para pantalla de estadísticas

## 🎮 Características

✅ **Guardado multiplataforma**: Funciona en Windows, macOS y Linux
✅ **Persistencia automática**: Settings se guardan al cambiar, stats al terminar partida
✅ **Separación por modos**: Estadísticas independientes para cada modo de juego
✅ **Protección anti-cheats**: Las partidas con cheats no se registran
✅ **Formato legible**: JSON con pretty-print para fácil edición manual
✅ **Retrocompatibilidad**: Si falta alguna key, usa valores por defecto
✅ **Manejo de errores**: Logging detallado de problemas I/O o parsing
✅ **Directorio automático**: Crea la carpeta de guardado si no existe

## 📝 Notas Importantes

### Privacidad de Datos
- Todos los datos se guardan **localmente** en tu computadora
- No se envía información a servidores externos
- Los archivos JSON son fácilmente editables/borrables

### Resetear Estadísticas
Para resetear tus estadísticas, simplemente elimina el archivo:
```
%APPDATA%\TopHat\Shooter\stats.json (Windows)
~/Library/Application Support/TopHat/Shooter/stats.json (macOS)
~/.local/share/TopHat/Shooter/stats.json (Linux)
```

### Resetear Configuraciones
Para volver a valores por defecto, elimina:
```
%APPDATA%\TopHat\Shooter\settings.json
```

## 🐛 Solución de Problemas

### Las estadísticas no se guardan
- Verifica que no usaste cheats (las partidas con cheats no se guardan)
- Revisa los permisos de escritura en la carpeta AppData
- Mira la consola del juego para mensajes de error

### Los settings no se guardan
- Verifica permisos de escritura
- Asegúrate de que la carpeta `TopHat\Shooter` existe en AppData
- Revisa la consola para errores de I/O

### Archivo JSON corrupto
Si el juego no puede leer el archivo:
1. Cierra el juego
2. Elimina el archivo corrupto
3. Reinicia el juego (creará uno nuevo con valores por defecto)

## 🔮 Futuras Expansiones

El sistema está diseñado para ser fácilmente expandible. Posibles adiciones:

- **Achievements/Logros**: Sistema de logros desbloqueables
- **Leaderboards locales**: Ranking de mejores partidas
- **Replays**: Guardado de partidas para reproducción
- **Perfiles múltiples**: Soporte para varios jugadores
- **Cloud sync**: Sincronización en la nube (opcional)
- **Estadísticas detalladas**: Power-ups más usados, enemigos más matados, etc.

## 📚 Para Desarrolladores

### Agregar nuevas estadísticas

1. Agrega el campo en `statistics.nim`:
```nim
type
  GameModeStats* = object
    # ... campos existentes ...
    newStat*: int  # Tu nueva estadística
```

2. Actualiza `gameModeStatsToJson`:
```nim
result = %* {
  # ... campos existentes ...
  "newStat": stats.newStat
}
```

3. Actualiza `jsonToGameModeStats`:
```nim
if jsonNode.hasKey("newStat"):
  stats.newStat = jsonNode["newStat"].getInt()
```

4. Actualiza `updateStats` para calcular la nueva stat

5. Agrega visualización en `drawStatistics`

¡Listo! El sistema manejará automáticamente la serialización y retrocompatibilidad.
