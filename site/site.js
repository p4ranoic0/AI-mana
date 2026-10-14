const links = {
  windows: "https://github.com/p4ranoic0/AI-mana/releases/latest/download/AImana-Setup.exe",
  mac: "https://github.com/p4ranoic0/AI-mana/releases/latest/download/AImana.dmg",
  android: "https://github.com/p4ranoic0/AI-mana/releases/latest/download/AImana.apk",
  releases: "https://github.com/p4ranoic0/AI-mana/releases",
  github: "https://github.com/p4ranoic0/AI-mana",
  readme: "https://github.com/p4ranoic0/AI-mana" + '#step-1-install-the-app-on-your-iphone',
  readmeEs: "https://github.com/p4ranoic0/AI-mana" + '/blob/main/README.es.md#paso-1-instala-la-app-en-tu-iphone',
  kofi: 'https://ko-fi.com/post/AImana-your-AI-coding-quotas-on-iPhone-Watch-an-S1D028MW28'
};
const copy = {
  en: {
    skip: 'Skip to content', install: 'Install AI·mana', back: 'All devices', language: 'Language',
    heroTag: 'A simple path from download to your first numbers', hero: 'Your AI coding quotas, on your phone.',
    intro: 'AI·mana shows your Claude Code and Codex usage, reset times and estimated costs in one calm place.',
    choose: 'Choose where to start', selected: 'Suggested for your device', phone: '1. Your phone', computer: '2. Your computer',
    phoneDescription: 'Install the app, then choose the relay file your computer shares.',
    computerDescription: 'Publish your usage to a folder your phone can open.',
    screenshots: 'A look at AI·mana', light: 'Dashboard in light mode', dark: 'Dashboard in dark mode', detail: 'Usage detail', macShot: 'Mac menu bar app',
    platform: { android: 'Android', ios: 'iPhone / iPad', windows: 'Windows', mac: 'macOS', linux: 'Linux' },
    open: 'Open guide', download: 'Download', releases: 'See Linux releases',
    iosNote: 'Not in the App Store yet — build it with Xcode on a Mac.', iosGuide: 'Read the Xcode guide',
    linuxCommand: 'Install the relay with Homebrew', linuxHint: 'You also need system libcurl (Ubuntu: sudo apt install libcurl4).',
    stepsTitle: 'Three steps to your numbers', step: 'Step',
    steps: {
      android: [
        ['Download AI·mana', 'Download the APK on your Android phone and open it.', 'AImana.apk', 'download'],
        ['Allow the install', 'If Android asks, tap “Settings” and turn on “Allow from this source”, then tap “Install”.', 'Allow from this source', 'security'],
        ['Choose your relay file', 'On your phone: AI·mana › Settings › Your computer › Choose relay file…; pick usage-relay.json.', 'Your computer', 'phone']
      ],
      ios: [
        ['Get the iPhone app', 'On a Mac, follow the README guide to build AI·mana with Xcode.', 'Xcode on Mac', 'download'],
        ['Run it on your device', 'Connect your iPhone, select the AImana scheme and your device, then click Run.', 'Select device → Run', 'security'],
        ['Choose your relay file', 'On your phone: AI·mana › Settings › Your computer › Choose relay file…', 'Your computer', 'phone']
      ],
      windows: [
        ['Download the installer', 'Open AImana-Setup.exe on the computer where you use Claude Code or Codex.', 'AImana-Setup.exe', 'download'],
        ['Finish setup', 'If SmartScreen appears, click “More info → Run anyway”; choose your synced folder in the installer.', 'More info → Run anyway', 'security'],
        ['Choose the file on your phone', 'On your phone: AI·mana › Settings › Your computer › Choose relay file…; pick usage-relay.json.', 'Your computer', 'phone']
      ],
      mac: [
        ['Install the Mac app', 'Open AImana.dmg, drag AI·mana to Applications and launch it from there.', 'Applications', 'download'],
        ['Allow and set up', 'On macOS 15+, click “Open Anyway” in System Settings › Privacy & Security; on older macOS, right-click › Open. Enable the Claude statusline in app settings.', 'Open Anyway', 'security'],
        ['Choose the file on your phone', 'On your phone: AI·mana › Settings › Your computer › Choose relay file…; pick iCloud Drive/AImana/usage-relay.json.', 'Your computer', 'phone']
      ],
      linux: [
        ['Install the relay', 'Run the Homebrew command below, or get the Linux archive from Releases.', "brew install p4ranoic0/tap/usage-relay", 'command'],
        ['Publish to a synced folder', 'Run usage-relay setup --output /path/to/synced/folder/usage-relay.json.', 'usage-relay.json → synced folder', 'security'],
        ['Choose the file on your phone', 'On your phone: AI·mana › Settings › Your computer › Choose relay file…; pick usage-relay.json.', 'Your computer', 'phone']
      ]
    },
    trouble: 'Need a hand?', noNumbers: 'No numbers yet', noNumbersText: 'Claude usage appears after your next Claude Code message; its statusline runs then.',
    missing: 'File not found', missingText: 'Give iCloud Drive or OneDrive time to sync, then choose usage-relay.json again.',
    setup: 'Check or repeat setup', setupText: {windows: 'Open “AI·mana — check setup” in Start, or rerun AImana-Setup.exe.', mac: 'Open AI·mana in the menu bar and check its settings and iCloud Drive.', linux: 'Run usage-relay doctor; rerun usage-relay setup --output with your synced folder.', android: 'Reopen the APK to install again; choose the relay file in Settings.', ios: 'Run the app again from Xcode; choose the relay file in Settings.'},
    privacy: 'No AI·mana server, analytics or cookies. Your relay file stays in your chosen cloud folder.', mit: 'MIT license', support: 'Support on Ko-fi',
    needed: 'For coding quotas, your computer must also publish a relay file.', computerGuide: 'Set up your computer', phoneGuide: 'Set up your phone',
    deviceLabel: 'Device guides', copy: 'Copy command', copied: 'Copied',
    mockTitle: {windows:'SmartScreen prompt illustration', mac:'Privacy & Security prompt illustration', android:'Android install permission illustration', linux:'Terminal illustration', ios:'Xcode illustration'}
  },
  es: {
    skip: 'Saltar al contenido', install: 'Instalar AI·mana', back: 'Todos los dispositivos', language: 'Idioma',
    heroTag: 'Del primer paso a tus números, sin complicaciones', hero: 'Tus cuotas de programación con IA, en tu teléfono.',
    intro: 'AI·mana muestra el uso de Claude Code y Codex, los reinicios y los costos estimados en un solo lugar.',
    choose: 'Elige por dónde empezar', selected: 'Sugerido para tu dispositivo', phone: '1. Tu teléfono', computer: '2. Tu computadora',
    phoneDescription: 'Instala la app y elige el archivo relay que comparte tu computadora.',
    computerDescription: 'Publica tu uso en una carpeta que tu teléfono pueda abrir.',
    screenshots: 'Así se ve AI·mana', light: 'Panel en modo claro', dark: 'Panel en modo oscuro', detail: 'Detalle del uso', macShot: 'App de la barra de menús de Mac',
    platform: { android: 'Android', ios: 'iPhone / iPad', windows: 'Windows', mac: 'macOS', linux: 'Linux' },
    open: 'Abrir guía', download: 'Descargar', releases: 'Ver versiones para Linux',
    iosNote: 'Todavía no está en App Store: compílala con Xcode en una Mac.', iosGuide: 'Leer la guía de Xcode',
    linuxCommand: 'Instala el relay con Homebrew', linuxHint: 'También necesitas libcurl del sistema (Ubuntu: sudo apt install libcurl4).',
    stepsTitle: 'Tres pasos para ver tus números', step: 'Paso',
    steps: {
      android: [
        ['Descarga AI·mana', 'Descarga el APK en tu Android y ábrelo.', 'AImana.apk', 'download'],
        ['Permite la instalación', 'Si Android lo pide, toca «Ajustes», activa «Permitir desde esta fuente» y toca «Instalar».', 'Permitir desde esta fuente', 'security'],
        ['Elige el archivo relay', 'En tu teléfono: AI·mana › Ajustes › Tu computadora › Elegir archivo del relay…; selecciona usage-relay.json.', 'Tu computadora', 'phone']
      ],
      ios: [
        ['Obtén la app para iPhone', 'En una Mac, sigue la guía del README para compilar AI·mana con Xcode.', 'Xcode en Mac', 'download'],
        ['Ejecútala en tu dispositivo', 'Conecta tu iPhone, selecciona el esquema AImana y tu dispositivo; luego pulsa Run.', 'Seleccionar dispositivo → Run', 'security'],
        ['Elige el archivo relay', 'En tu teléfono: AI·mana › Ajustes › Tu computadora › Elegir archivo del relay…', 'Tu computadora', 'phone']
      ],
      windows: [
        ['Descarga el instalador', 'Abre AImana-Setup.exe en la computadora donde usas Claude Code o Codex.', 'AImana-Setup.exe', 'download'],
        ['Termina la configuración', 'Si aparece SmartScreen, haz clic en «Más información → Ejecutar de todas formas»; elige la carpeta sincronizada.', 'Más información → Ejecutar de todas formas', 'security'],
        ['Elige el archivo en tu teléfono', 'En tu teléfono: AI·mana › Ajustes › Tu computadora › Elegir archivo del relay…; selecciona usage-relay.json.', 'Tu computadora', 'phone']
      ],
      mac: [
        ['Instala la app para Mac', 'Abre AImana.dmg, arrastra AI·mana a Aplicaciones y ábrela desde allí.', 'Aplicaciones', 'download'],
        ['Permite y configura', 'En macOS 15+, pulsa «Abrir de todas formas» en Ajustes del Sistema › Privacidad y seguridad; en versiones anteriores, clic derecho › Abrir. Activa el statusline de Claude en la app.', 'Abrir de todas formas', 'security'],
        ['Elige el archivo en tu teléfono', 'En tu teléfono: AI·mana › Ajustes › Tu computadora › Elegir archivo del relay…; selecciona iCloud Drive/AImana/usage-relay.json.', 'Tu computadora', 'phone']
      ],
      linux: [
        ['Instala el relay', 'Ejecuta el comando de Homebrew de abajo o descarga el archivo para Linux desde Releases.', "brew install p4ranoic0/tap/usage-relay", 'command'],
        ['Publica en una carpeta sincronizada', 'Ejecuta usage-relay setup --output /ruta/a/carpeta/sincronizada/usage-relay.json.', 'usage-relay.json → carpeta sincronizada', 'security'],
        ['Elige el archivo en tu teléfono', 'En tu teléfono: AI·mana › Ajustes › Tu computadora › Elegir archivo del relay…; selecciona usage-relay.json.', 'Tu computadora', 'phone']
      ]
    },
    trouble: '¿Necesitas ayuda?', noNumbers: 'Todavía no hay números', noNumbersText: 'El uso de Claude aparece después de tu siguiente mensaje en Claude Code, cuando se ejecuta su statusline.',
    missing: 'No se encuentra el archivo', missingText: 'Espera a que iCloud Drive o OneDrive termine de sincronizar y vuelve a elegir usage-relay.json.',
    setup: 'Revisa o repite la configuración', setupText: {windows: 'Abre «AI·mana — check setup» en Inicio, o vuelve a ejecutar AImana-Setup.exe.', mac: 'Abre AI·mana en la barra de menús y revisa sus ajustes e iCloud Drive.', linux: 'Ejecuta usage-relay doctor; repite usage-relay setup --output con tu carpeta sincronizada.', android: 'Abre de nuevo el APK; elige el archivo relay en Ajustes.', ios: 'Vuelve a ejecutar la app desde Xcode; elige el archivo relay en Ajustes.'},
    privacy: 'Sin servidor de AI·mana, analítica ni cookies. El archivo relay queda en la carpeta en la nube que elegiste.', mit: 'Licencia MIT', support: 'Apoyar en Ko-fi',
    needed: 'Para ver cuotas de programación, tu computadora también debe publicar un archivo relay.', computerGuide: 'Configurar mi computadora', phoneGuide: 'Configurar mi teléfono',
    deviceLabel: 'Guías por dispositivo', copy: 'Copiar comando', copied: 'Copiado',
    mockTitle: {windows:'Ilustración del aviso SmartScreen', mac:'Ilustración de Privacidad y seguridad', android:'Ilustración del permiso de instalación', linux:'Ilustración de Terminal', ios:'Ilustración de Xcode'}
  }
};
const params = new URLSearchParams(location.search);
let language = params.get('lang') || (navigator.language.toLowerCase().startsWith('es') ? 'es' : 'en');
if (!copy[language]) language = 'en';
let platform = params.get('platform');
if (!['android', 'ios', 'windows', 'mac', 'linux'].includes(platform)) platform = null;
const system = /android/i.test(navigator.userAgent) ? 'android' : /iphone|ipad|ipod/i.test(navigator.userAgent) ? 'ios' : /windows/i.test(navigator.userAgent) ? 'windows' : /mac/i.test(navigator.userAgent) ? 'mac' : 'linux';
const t = copy[language];
const esc = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const page = (name = null, lang = language) => `?${new URLSearchParams({...name ? {platform: name} : {}, lang})}`;
function card(name, index) {
  return `<a class="device ${name === system ? 'suggested' : ''}" href="${page(name)}"><span class="device-index">${index}</span><span><strong>${esc(t.platform[name])}</strong>${name === system ? `<small>${esc(t.selected)}</small>` : ''}</span><span aria-hidden="true">↗</span></a>`;
}
function illustration(kind, label, name) {
  if (kind === 'phone') {
    const device = name === 'ios' || name === 'mac' ? 'ios' : 'android';
    const shot = `assets/relay-${device}-${language}`;
    return `<figure class="visual visual-phone ${device === 'ios' ? 'visual-ios' : ''}"><picture><source media="(prefers-color-scheme: dark)" srcset="${shot}-dark.png"><img src="${shot}-light.png" alt="${esc(label)}" loading="lazy"></picture><figcaption>${esc(label)}</figcaption></figure>`;
  }
  if (kind === 'security') return `<figure class="visual visual-prompt" role="img" aria-label="${esc(t.mockTitle[name])}"><div class="mock-title">${esc(t.mockTitle[name])}</div><div class="mock-rule"></div><div class="mock-message">${esc(label)}</div><div class="mock-button">${esc(label)}</div><figcaption>${esc(label)}</figcaption></figure>`;
  return `<figure class="visual visual-file" role="img" aria-label="${esc(label)}"><div class="file-symbol" aria-hidden="true">${kind === 'command' ? '›_' : '↓'}</div><strong>${esc(label)}</strong><figcaption>${esc(label)}</figcaption></figure>`;
}
function stepMarkup(name, step, i) {
  return `<li class="step"><div class="step-copy"><span class="step-number">${esc(t.step)} ${i + 1}</span><h3>${esc(step[0])}</h3><p>${esc(step[1])}</p></div>${illustration(step[3], step[2], name)}</li>`;
}
function home() {
  return `<section class="hero"><div class="hero-copy"><span class="eyebrow">${esc(t.heroTag)}</span><h1>${esc(t.hero)}</h1><p>${esc(t.intro)}</p><a class="primary" href="#choose">${esc(t.choose)} <span aria-hidden="true">↓</span></a></div><div class="hero-images"><img src="assets/dashboard-light.png" alt="${esc(t.light)}"><img src="assets/dashboard-dark.png" alt="${esc(t.dark)}"></div></section>
    <section id="choose" class="choices"><h2>${esc(t.choose)}</h2><div class="choice-grid"><div class="choice"><h3>${esc(t.phone)}</h3><p>${esc(t.phoneDescription)}</p>${card('android', '01')}${card('ios', '02')}</div><div class="choice"><h3>${esc(t.computer)}</h3><p>${esc(t.computerDescription)}</p>${card('windows', '01')}${card('mac', '02')}${card('linux', '03')}</div></div></section>
    <section class="gallery"><h2>${esc(t.screenshots)}</h2><div class="gallery-grid"><figure><img src="assets/detail.png" alt="${esc(t.detail)}" loading="lazy"><figcaption>${esc(t.detail)}</figcaption></figure><figure><img src="assets/mac-menu.png" alt="${esc(t.macShot)}" loading="lazy"><figcaption>${esc(t.macShot)}</figcaption></figure></div></section>`;
}
function guide(name) {
  const download = name === 'windows' || name === 'mac' || name === 'android';
  const extra = name === 'ios' ? `<p class="note">${esc(t.iosNote)} <a href="${language === 'es' ? links.readmeEs : links.readme}">${esc(t.iosGuide)} ↗</a></p>` : name === 'linux' ? `<div class="command"><span>${esc(t.linuxCommand)}</span><code>brew install p4ranoic0/tap/usage-relay</code><button type="button" id="copy-command">${esc(t.copy)}</button></div><p class="note">${esc(t.linuxHint)} <a href="${links.releases}">${esc(t.releases)} ↗</a></p>` : '';
  return `<div class="guide-head"><a href="${page()}" class="back">← ${esc(t.back)}</a><span class="eyebrow">${esc(t.deviceLabel)}</span><h1>${esc(t.platform[name])}</h1><p>${esc(t.stepsTitle)}</p>${download ? `<a class="primary" href="${links[name]}">${esc(t.download)} ${esc(t.platform[name])} ↗</a>` : ''}${extra}</div><ol class="steps">${t.steps[name].map((step, i) => stepMarkup(name, step, i)).join('')}</ol><aside class="next"><p>${esc(t.needed)}</p><a href="${page(name === 'android' || name === 'ios' ? 'mac' : 'android')}">${esc(name === 'android' || name === 'ios' ? t.computerGuide : t.phoneGuide)} →</a></aside><section class="trouble"><h2>${esc(t.trouble)}</h2><div class="trouble-grid"><article><h3>${esc(t.noNumbers)}</h3><p>${esc(t.noNumbersText)}</p></article><article><h3>${esc(t.missing)}</h3><p>${esc(t.missingText)}</p></article><article><h3>${esc(t.setup)}</h3><p>${esc(t.setupText[name])}</p></article></div></section>`;
}
function render() {
  document.documentElement.lang = language;
  document.title = `${t.install}${platform ? ' · ' + t.platform[platform] : ''}`;
  document.querySelector('.skip').textContent = t.skip;
  document.querySelector('meta[name="description"]').content = t.intro;
  document.querySelector('#app').innerHTML = `<header class="site-header"><a class="brand" href="${page()}"><span>AI</span>·mana</a><nav aria-label="${esc(t.language)}"><a href="${page(platform, 'en')}" lang="en" ${language === 'en' ? 'aria-current="true"' : ''}>EN</a><span aria-hidden="true">/</span><a href="${page(platform, 'es')}" lang="es" ${language === 'es' ? 'aria-current="true"' : ''}>ES</a></nav></header><main id="main">${platform ? guide(platform) : home()}</main><footer><p>${esc(t.privacy)}</p><div><a href="${links.github}">GitHub</a><a href="${links.github}/blob/main/LICENSE">${esc(t.mit)}</a><a href="${links.kofi}">${esc(t.support)}</a></div></footer>`;
  document.querySelector('#copy-command')?.addEventListener('click', async event => {
    await navigator.clipboard.writeText("brew install p4ranoic0/tap/usage-relay");
    event.currentTarget.textContent = t.copied;
  });
}
render();
