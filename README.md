🎩 TopHat Shooter

TopHat Shooter es un bullet hell rápido, caótico y lleno de cinemática gloriosa, hecho en Nim + Raylib. Lucha contra oleadas, mejora tu build y destruye jefes cada 5 rondas.

Contenido:

Dos modos de juego

Waves: avanza por oleadas, consigue mejoras y enfréntate a jefes.

Survival: resiste todo lo que puedas mientras el caos escala.

11 tipos de enemigos, cada uno con un comportamiento distinto.

Jefes cada 5 oleadas, con fases cambiantes y recompensas legendarias.

30+ power-ups, desde multishot hasta control del tiempo.

Tienda permanente: mejora daño, velocidad, vida y más.

6 consumibles y muros defensivos para crear espacio.

Optimizado para 60+ FPS incluso con cientos de balas en pantalla.

92 tests asegurando que nada explote (a menos que deba explotar).

🎮 Controles
Tecla	Acción
WASD	Moverse
Mouse / Space	Disparar
F	Auto-Shoot
E	Colocar muro
Q  Usar power up activo/s
ESC	Pausa
🚀 Instalar y jugar
git clone https://github.com/yourusername/TopHat-Shooter.git
cd TopHat-Shooter
nimble install
nimble run


Build de lanzamiento:

nimble build

Performance

El juego está preparado para manejar:

+50 enemigos simultáneos

+200 balas activas

+500 partículas

Jefes con múltiples fases

Todo fluido a 60 FPS

Tests

Ejecuta todos los tests:

nim c -r tests/test_game.nim


Cobertura aproximada: 87%

🛠️ Estructura del proyecto (resumen)
src/
  main.nim       # Loop principal
  game.nim       # Lógica del juego
  player.nim     # Jugador
  enemy.nim      # IA enemiga
  bullet.nim     # Balas
  powerup.nim    # Mejores permanentes
  wall.nim       # Muros defensivos
  shop.nim       # Tienda
tests/
  test_game.nim  # Suite de tests

Paycei
