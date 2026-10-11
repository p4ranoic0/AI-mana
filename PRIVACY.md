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

## Where requests go

| From | To | Why |
|---|---|---|
| iPhone | `openrouter.ai` | OpenRouter credits, with your key |
| iPhone | `api.github.com` | Copilot usage and billing, with your token |
| iPhone | `api.deepseek.com` | DeepSeek balance, with your key |
| iPhone | `api.moonshot.ai` / `api.moonshot.cn` | Moonshot (Kimi) balance, with your key |
| iPhone | `management-api.x.ai` | xAI balance, with your key |
| Mac / Linux relay CLI | `models.dev` | Public model prices, used for cost estimates |
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
- **Las claves de API que ingreses** en el iPhone se guardan en el Llavero de iOS y nunca se escriben en el archivo
  de relay.
- **El archivo de relay** (`iCloud Drive/AImana/usage-relay.json`):
  - Guarda el resumen de uso, los costos estimados y un historial corto, para que tu iPhone lea lo que midió tu
    Mac.
  - No contiene credenciales ni prompts.
- **El Apple Watch** recibe del iPhone porcentajes, horas de reinicio y estado. No recibe claves ni costos.

Los destinos de las consultas son los mismos de la tabla de arriba.

Cada proveedor ve la consulta, tu dirección IP y la clave que le diste, según su propia política de privacidad. Para
borrar tus datos:
- quita la clave en los Ajustes de la app y revócala en el proveedor;
- desinstala la integración del statusline desde la app del Mac;
- borra el archivo de relay en Archivos o en Finder.
