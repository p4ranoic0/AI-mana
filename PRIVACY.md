# Privacy

**Short version:** AI·mana has no account, no server and no analytics. Your data stays on your devices and in your
own iCloud Drive. Requests go directly from your device to the providers you choose.

[Español abajo](#privacidad)

## What AI·mana processes

- **Usage and limits:**
  - percentages, window lengths and reset times;
  - provider names, when each reading was taken, and connection errors.
- **Cost estimates:**
  - The Mac app reads Claude Code and Codex session files on your Mac. It extracts only token counts, timestamps and
    model names. It does not read message or prompt text.
  - It multiplies those counts by public model prices to estimate an API-equivalent amount. That is not your real
    bill.
- **API keys you enter** on the iPhone. They are stored in the iOS Keychain and never written to the relay file.
- **The relay file** (`iCloud Drive/AImana/usage-relay.json`):
  - It holds the usage summary, estimated costs and a short history, so your iPhone can read what your Mac
    measured.
  - It has no credentials and no prompts.
- **Apple Watch** receives percentages, reset times and status from the iPhone. It does not receive keys or costs.

## Direct access (optional, off by default)

- **On the iPhone**, signing in with Claude or ChatGPT creates a session of your own on that phone. It is stored in the
  iOS Keychain, shared with nobody, and deleted when you sign out.
- **On Android**, the same applies: the session is encrypted with the Android Keystore, kept out of backups, and
  deleted when you sign out. API keys you paste there are stored the same way.
- **On Windows and Linux**, the tray app reads the session Claude Code (`~/.claude/.credentials.json`) or Codex
  (`~/.codex/auth.json`) keeps. It never writes it; when the Claude session is about to expire it runs
  `claude auth status` so the CLI renews it itself.
- **On the Mac**, AI·mana reads the session Claude Code (Keychain or `~/.claude`) or Codex (`~/.codex/auth.json`)
  already keeps. It only reads it: it never copies, changes or renews it.
- Sessions and tokens are never written to the relay file and never sent to any AI·mana server (there is none).
- To revoke: turn direct access off or sign out in the app. On the Mac you can also sign out of the CLI itself.

## Where requests go

| From | To | Why |
|---|---|---|
| iPhone / Android | `openrouter.ai` | OpenRouter credits, with your key |
| iPhone / Android | `api.github.com` | Copilot usage and billing, with your token |
| iPhone / Android | `api.deepseek.com` | DeepSeek balance, with your key |
| iPhone / Android | `api.moonshot.ai` / `api.moonshot.cn` | Moonshot (Kimi) balance, with your key |
| iPhone / Android | `management-api.x.ai` | xAI balance, with your key |
| iPhone / Android / Mac / Windows / Linux | `api.anthropic.com` | Claude usage, with your session, only if you turn direct access on |
| iPhone / Android / Mac / Windows / Linux | `chatgpt.com` | Codex usage, with your session, only if you turn direct access on |
| iPhone / Android | `claude.ai`, `platform.claude.com`, `auth.openai.com` | Signing in on the phone, only if you choose to |
| Mac / Linux relay CLI | `models.dev` | Public model prices, used for cost estimates |
| Android / Windows / Linux | `api.github.com` | Once a day, whether a newer AI·mana release is out. Anonymous; can be turned off in Settings |
| Mac ↔ iPhone | Apple iCloud Drive | The relay file |

Each provider sees the request, your IP address and the key you gave it, under its own privacy policy. To remove
your data:
- remove a key in the app's Settings, and revoke it at the provider;
- uninstall the statusline integration from the Mac app;
- delete the relay file in Files or Finder.

---

## Privacidad

**En corto:** AI·mana no tiene cuenta, servidor ni analítica. Tus datos se quedan en tus dispositivos y en tu propio
iCloud Drive. Las consultas van directo de tu dispositivo a los proveedores que elijas.

- **Uso y límites:**
  - porcentajes, duración de las ventanas y horas de reinicio;
  - nombres de proveedores, momento de cada lectura y errores de conexión.
- **Costos estimados:**
  - La app del Mac lee los archivos de sesión de Claude Code y Codex en tu Mac. Solo extrae contadores de tokens,
    fechas y nombres de modelos. No lee el texto de los mensajes ni de los prompts.
  - Multiplica esos contadores por los precios públicos de los modelos para estimar un importe equivalente a la API.
    No es tu factura real.
- **Las claves de API que ingreses** en el iPhone se guardan en el Llavero de iOS (en Android, cifradas con el Keystore) y nunca se escriben en el archivo
  de relay.
- **El archivo de relay** (`iCloud Drive/AImana/usage-relay.json`):
  - Guarda el resumen de uso, los costos estimados y un historial corto, para que tu iPhone lea lo que midió tu
    Mac.
  - No contiene credenciales ni prompts.
- **El Apple Watch** recibe del iPhone porcentajes, horas de reinicio y estado. No recibe claves ni costos.
- **Acceso directo (opcional, desactivado por defecto):**
  - En el iPhone, iniciar sesión con Claude o ChatGPT crea una sesión propia en ese teléfono. Se guarda en el Llavero
    de iOS, no se comparte con nadie y se borra al cerrar sesión.
  - En Android ocurre lo mismo: la sesión se cifra con el Keystore de Android, queda fuera de las copias de seguridad
    y se borra al cerrar sesión.
  - En Windows y Linux, la app de bandeja lee la sesión que guardan Claude Code (`~/.claude/.credentials.json`) o
    Codex (`~/.codex/auth.json`). Nunca la escribe; cuando la sesión de Claude está por vencer ejecuta
    `claude auth status` para que el CLI la renueve por sí mismo.
  - En el Mac, AI·mana lee la sesión que Claude Code (Llavero o `~/.claude`) o Codex (`~/.codex/auth.json`) ya
    guardan. Solo la lee: nunca la copia, la cambia ni la renueva.
  - Las sesiones y los tokens nunca se escriben en el archivo de relay ni se envían a ningún servidor de AI·mana (no
    hay ninguno).
  - Para revocarlo: desactiva el acceso directo o cierra sesión en la app. En el Mac también puedes cerrar sesión en
    el propio CLI.

Los destinos de las consultas son los mismos de la tabla de arriba. Android, Windows y Linux además preguntan a
`api.github.com` una vez al día si hay una versión nueva de AI·mana: es anónimo y se puede desactivar en Ajustes.

Cada proveedor ve la consulta, tu dirección IP y la clave que le diste, según su propia política de privacidad. Para
borrar tus datos:
- quita la clave en los Ajustes de la app y revócala en el proveedor;
- desinstala la integración del statusline desde la app del Mac;
- borra el archivo de relay en Archivos o en Finder.
