# 🎩 TopHat-ShooterOS

![Nim](https://img.shields.io/badge/Nim-FFE953?style=for-the-badge&logo=nim&logoColor=black)
![Raylib](https://img.shields.io/badge/Raylib-000000?style=for-the-badge&logo=c&logoColor=white)

![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge&logo=apache&logoColor=white)

**TopHat-ShooterOS** es un *bullet hell* rápido, caótico y hecho en **Nim + Raylib** btw.

---

## Contenido

### Modos de juego
- **Waves**: avanza por oleadas, consigue mejoras y enfréntate a jefes.
- **Survival**: resiste todo lo que puedas mientras el caos escala (TODO).

### Enemigos y jefes
- **13 tipos de enemigos**, cada uno con un comportamiento distinto.
- **12 Jefes que aparecen cada 5 oleadas**, con fases cambiantes y recompensas legendarias.

### Progresión y combate
- **60+ power-ups**, desde *multishot* hasta control del tiempo.
- **Tienda**: mejora daño, velocidad, vida y más permanentemente.
- **6 consumibles** y **muros defensivos** (aunque nadie los use están ahí).

---

## Controles

| Tecla           | Acción                         |
|-----------------|--------------------------------|
| WASD            | Moverse                        |
| Mouse / Space   | Disparar                       |
| E               | Colocar muro                   |
| Q               | Usar power-up activo(s)        |
| ESC             | Pausa                          |

---

## Instalación y ejecución

```bash
git clone https://github.com/Paycei/TopHat-Shooter.git
cd TopHat-Shooter
nimble install
nimble release
