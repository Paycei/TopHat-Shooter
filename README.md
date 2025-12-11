# 🎩 TopHat Shooter

![Nim](https://img.shields.io/badge/Nim-FFE953?style=for-the-badge&logo=nim&logoColor=black)
![Raylib](https://img.shields.io/badge/Raylib-000000?style=for-the-badge&logo=c&logoColor=white)

![License](https://img.shields.io/github/license/Paycei/TopHat-Shooter?style=for-the-badge)

**TopHat Shooter** es un *bullet hell* rápido, caótico y con buena música, hecho en **Nim + Raylib**.  
Lucha contra oleadas, mejora tu *build* y destruye jefes cada **5 rondas**.

---

## Contenido

### Modos de juego
- **Waves**: avanza por oleadas, consigue mejoras y enfréntate a jefes.
- **Survival**: resiste todo lo que puedas mientras el caos escala.

### Enemigos y jefes
- **11 tipos de enemigos**, cada uno con un comportamiento distinto.
- **Jefes cada 5 oleadas**, con fases cambiantes y recompensas legendarias.

### Progresión y combate
- **30+ power-ups**, desde *multishot* hasta control del tiempo.
- **Tienda permanente**: mejora daño, velocidad, vida y más.
- **6 consumibles** y **muros defensivos** para crear espacio.

### Rendimiento y calidad
- Optimizado para **60+ FPS**, incluso con cientos de balas en pantalla.
- **92 tests** asegurando que nada explote (a menos que deba explotar).

---

## Controles

| Tecla           | Acción                          |
|-----------------|--------------------------------|
| WASD            | Moverse                        |
| Mouse / Space   | Disparar                       |
| F               | Auto-Shoot                     |
| E               | Colocar muro                   |
| Q               | Usar power-up activo(s)        |
| ESC             | Pausa                          |

---

## Instalación y ejecución

```bash
git clone https://github.com/yourusername/TopHat-Shooter.git
cd TopHat-Shooter
nimble install
nim c -d:release --opt:speed --app:gui --passL:icono.res -o:TopHatShooter.exe src/main.nim
