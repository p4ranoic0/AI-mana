# AI·mana

**Tus cuotas y tu gasto en herramientas de IA para programar, nativo en iPhone, iPad, Apple Watch y Mac.**

[English](README.md)

AI·mana muestra:
- cuánto llevas usado de tus límites de Claude Code y Codex;
- cuándo se reinicia cada ventana;
- si a tu ritmo se te acabará antes del reinicio;
- cuánto costaría ese uso a precios públicos de la API.

También sigue el saldo prepago de proveedores de API directamente desde el iPhone, sin Mac.

Es gratis y de código abierto (MIT). No tiene cuenta ni servidor, y usa **solo fuentes de datos oficiales**.

> AI·mana es un proyecto independiente. No está afiliado a Anthropic, OpenAI, GitHub, OpenRouter, DeepSeek, Moonshot
> AI ni xAI, ni cuenta con su respaldo o patrocinio. Sus nombres se usan solo para indicar compatibilidad.

<p align="center">
  <img src="docs/screenshots/dashboard-light.png" width="200" alt="Panel, tema claro">
  <img src="docs/screenshots/dashboard-dark.png" width="200" alt="Panel, tema oscuro">
  <img src="docs/screenshots/detail.png" width="200" alt="Detalle de Claude Code con presupuesto diario">
  <img src="docs/screenshots/balances.png" width="200" alt="Saldos de proveedores de API">
</p>

<p align="center">
  <img src="docs/screenshots/ipad-dashboard.png" height="300" alt="Panel en iPad">
  <img src="docs/screenshots/mac-menu.png" height="300" alt="App de la barra de menús del Mac">
  <img src="docs/screenshots/watch.png" height="200" alt="App del Apple Watch">
</p>

## Funciones

**iPhone y iPad**
- Panel con cada ventana de 5 horas y semanal, mostrada como usado o restante, en barras o anillos.
- Proyección de ritmo: ¿llegarás al límite antes del reinicio?
- Costos estimados equivalentes a la API, con historial. Se calculan en tu Mac a partir de los contadores locales
  de tokens.
- Widgets de pantalla de inicio y de bloqueo, botón interactivo de actualizar y control en el Centro de Control.
- Live Activity y Dynamic Island para el proveedor que estás siguiendo.
- Siri y Atajos (por ejemplo "How much Claude is left in AI·mana?"; las frases de Siri están en inglés).
- Notificaciones de ritmo rápido, de cuota disponible otra vez y un resumen diario.
- Seis idiomas: español, inglés, portugués (Brasil), francés, alemán e italiano.

**Apple Watch**
- App y complicaciones para la esfera, sincronizadas desde el iPhone.

**Mac (barra de menú)**
- Lee los datos oficiales del statusline de Claude Code (`rate_limits`), sin credenciales.
- Lee los logs locales de sesión de Codex (`~/.codex/sessions`).
- Estima costos a partir de los contadores locales de tokens y de los precios públicos de los modelos.
- Publica un archivo de resumen en tu iCloud Drive para el iPhone. No contiene credenciales ni prompts.

**Proveedores de API, en el iPhone y sin Mac** (con tu propia clave)
- OpenRouter, GitHub Copilot, DeepSeek, Moonshot (Kimi) y xAI. Las claves quedan en el Llavero de iOS.

## Cómo funciona

```
Statusline de Claude Code ─┐
Logs de sesión de Codex ───┼─▶ AI·mana para Mac ─▶ iCloud Drive/AImana/usage-relay.json ─▶ iPhone · iPad · Watch · widgets
                           │
Tus claves de API ─────────┴─────────────────────────────── (se leen directo en el iPhone) ─┘
```

El iPhone lee el resumen que publica tu Mac. Las consultas a los proveedores de API van directo desde tu dispositivo
a ese proveedor. AI·mana no tiene servidor ni analítica. Ver [PRIVACY.md](PRIVACY.md).

## Requisitos

- iOS / iPadOS 17 o posterior, watchOS 10 o posterior, macOS 14 o posterior.
- Xcode 26 o posterior y [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Para los datos de Claude Code y Codex: la app AI·mana para Mac, en un Mac con la misma cuenta de iCloud que el
  iPhone.
- Un Apple ID. Sirve una cuenta gratuita, pero Apple hace que las apps compiladas con ella venzan a los 7 días, así
  que tendrás que recompilar cada semana.

## Compilar e instalar

Para instalar las apps, compílalas desde el código:

```bash
git clone https://github.com/p4ranoic0/AI-mana.git AImana
cd AImana
cp AImana/Config/Local.xcconfig.example AImana/Config/Local.xcconfig
# Edita Local.xcconfig con tu Team ID y un prefijo de bundle propio (por ejemplo com.tunombre).
cd AImana && xcodegen generate && open AImana.xcodeproj
```

1. **Mac:** ejecuta el esquema `AImanaMac`. En sus ajustes, instala la integración del statusline de Claude Code
   y comprueba que iCloud Drive esté disponible. La app publica sola.
2. **iPhone:** ejecuta el esquema `AImana` en tu dispositivo. En Ajustes › AI·mana para Mac, toca
   **Elegir archivo del relay…** y elige `iCloud Drive/AImana/usage-relay.json`.
3. Añade los widgets, la app del Watch o la Live Activity, como prefieras.

Para correr los tests: `swift test` en `AImana/AImanaCore` y en `AImana/Relay`.

### Relay para macOS y Linux

Descarga un binario precompilado de `usage-relay` para macOS o Linux en la
[página de Releases](https://github.com/p4ranoic0/AI-mana/releases), o compílalo desde el código.
En Linux, el binario también necesita la biblioteca `libcurl` del sistema (en Ubuntu: `apt install libcurl4`).
Para compilarlo desde el código, ejecuta `swift build -c release --package-path AImana/Relay` y luego
`AImana/Relay/.build/release/usage-relay run --output /ruta/sincronizada/usage-relay.json`.
En el iPhone, abre ese archivo con **Elegir archivo del relay…**. Sin `--output`, Linux escribe en
`~/AImana/usage-relay.json`. Los datos y el estado usan `${XDG_DATA_HOME:-~/.local/share}/aimana`;
las cachés usan `${XDG_CACHE_HOME:-~/.cache}/aimana`.

La CLI de Linux no ofrece el instalador `statusline`: su script depende de `plutil` de macOS si no
hay `jq`. El relay sí puede leer una captura de statusline existente en su directorio de datos
y lee directamente los registros de sesiones de Codex.

## Roadmap

- **Windows** (planeado, sin fecha): publicar el archivo del relay en una carpeta sincronizada
  (iCloud para Windows, Dropbox, OneDrive o Syncthing) que el iPhone abra con **Elegir archivo del relay…**.

## Cuando un proveedor cambia algo

AI·mana depende de formatos que controlan otras empresas, y pueden cambiar sin aviso. El parser de cada proveedor
está aislado y cubierto por tests con datos de ejemplo. Si ves números raros, abre un issue con la plantilla
**Provider changed**.

## Apoya el proyecto

AI·mana es gratis. Si te ahorra quedarte sin cuota a mitad de una tarea, puedes apoyar su desarrollo:

- [Ko-fi](https://ko-fi.com/post/AImana-your-AI-coding-quotas-on-iPhone-Watch-an-S1D028MW28): única o mensual, con tarjeta o PayPal. Escribe "AI·mana" en tu mensaje.

También ayudan las estrellas, los reportes de errores y las traducciones.

## Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md). Problemas de seguridad: [SECURITY.md](SECURITY.md).

## Licencia

[MIT](LICENSE)
