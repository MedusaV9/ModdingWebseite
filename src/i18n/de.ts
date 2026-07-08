import type { Dict } from './context'

// German dictionary — informal "du", gaming-community tone. Proper nouns
// (BAPBAP, BAPHub, BAPBAP Nexus, MelonLoader, Boss Rush, Battle Royale,
// Discord, Version Time Machine) stay untranslated. Strings rendered with
// text-transform: uppercase avoid "ß" (no capital sharp s in these fonts).
export const de = {
  common: {
    skipToContent: 'ZUM INHALT SPRINGEN',
  },
  nav: {
    mods: 'Mods',
    modes: 'Modi',
    launcher: 'Launcher',
    radio: 'Radio',
    guide: 'Guide',
    modders: 'Modder',
    community: 'Community',
    joinDiscord: 'Discord beitreten',
    // "Discord beitreten" wraps to two lines in the 1024px navbar — keep it short.
    joinDiscordShort: 'Discord',
    languageLabel: 'Sprache',
    searchLabel: 'Suche (drück /)',
    openMenu: 'Navigationsmenü öffnen',
    closeMenu: 'Navigationsmenü schließen',
    mainNavLabel: 'Hauptnavigation',
    mobileNavLabel: 'Mobile Navigation',
  },
  footer: {
    tagline:
      'Eine von Fans gemachte Modding-Community für BAPBAP, das Roguelike-Partyspiel.',
    quickKeys: 'SCHNELLTASTEN:',
    quickKeysSearch: 'Suche',
    siteHeading: 'Seite',
    linksHeading: 'Links',
    links: {
      discord: 'Discord',
      github: 'GitHub',
      official: 'Offizielle Seite',
      steam: 'BAPBAP auf Steam',
    },
    disclaimer:
      'BAPBAP Modding ist ein Community-Projekt und steht in keiner Verbindung zu BAPBAP HQ, noch wird es von BAPBAP HQ unterstützt. BAPBAP und alle zugehörigen Inhalte sind Eigentum ihrer jeweiligen Rechteinhaber.',
    builtBy: 'Gebaut von der BAPBAP-Modding-Community',
  },
  palette: {
    dialogLabel: 'Website-Suche',
    resultsLabel: 'Suchergebnisse',
    placeholder: 'Mods, Seiten, Aktionen suchen…',
    noResults: 'KEINE TREFFER — versuch andere Suchbegriffe.',
    footerHint: '↑↓ NAVIGIEREN · ↵ ÖFFNEN · ESC SCHLIESSEN',
    copied: 'KOPIERT!',
    groups: {
      mods: 'MODS',
      pages: 'SEITEN',
      actions: 'AKTIONEN',
    },
    pages: {
      home: 'Startseite',
      mods: 'Mods',
      modes: 'Spielmodi',
      launcher: 'Launcher',
      radio: 'Radio',
      guide: 'Guide',
      modders: 'Für Modder',
      community: 'Community',
    },
    actions: {
      surprise: 'Überrasch mich — zufälliger Mod',
      surpriseSub: 'Öffnet einen zufälligen Mod aus dem Katalog',
      copyDiscord: 'Discord-Einladung kopieren',
      download: 'Launcher herunterladen',
      downloadSub: 'BAPBAP Nexus für Windows',
    },
  },
  loader: {
    loading: 'LÄDT',
    loadingLabel: 'Seite lädt',
  },
  hero: {
    badge: 'COMMUNITY-PROJEKT — NICHT MIT BAPBAP HQ VERBUNDEN',
    tagline: ['COMMUNITY-MODS', 'EIGENE MODI', 'EIN LAUNCHER'],
    joinDiscord: 'DISCORD BEITRETEN',
    getLauncher: 'LAUNCHER HOLEN',
    subline: 'FÜR BAPBAP — DAS ROGUELIKE-PARTYSPIEL AUF STEAM',
    stats: ['MODS & TOOLS', 'SPIEL-TRACKS', 'RADIO-TRACKS', 'MELONLOADER', 'NEXUS'],
  },
  home: {
    featured: {
      eyebrow: 'BAPHUB-KATALOG',
      title: 'AUSGEWÄHLTE MODS',
      subtitle:
        'Echte Community-Mods, mit einem Klick über den BAPBAP Nexus Launcher installierbar.',
    },
    browseAllMods: (n: number) => `ALLE ${n} MODS ANSEHEN`,
    modes: {
      eyebrow: 'MEHR ARTEN ZU SPIELEN',
      title: 'SPIELMODI & TRACKS',
      cta: 'SPIELMODI ENTDECKEN',
    },
    launcher: {
      eyebrow: 'BAPBAP NEXUS',
      title: 'EIN LAUNCHER. ALLES.',
      changelogCta: 'LAUNCHER & CHANGELOG',
      downloadCta: (version: string) => `FÜR WINDOWS LADEN (v${version})`,
      subline:
        'Windows x64 · Kostenlos · Auto-Updates · Installiert MelonLoader für dich',
    },
    community: {
      marquee: 'AB IN DEN DISCORD',
      title: 'WERDE TEIL DER BAPBAP MODDING-COMMUNITY',
      sub: 'MOD-DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV-TALK',
      meetCta: 'LERN DIE COMMUNITY KENNEN',
      discordCta: 'DISCORD.GG/BAPBAPMODS',
    },
  },
  howItWorks: {
    eyebrow: 'NULL AUFWAND',
    title: 'SO FUNKTIONIERT MODDING',
    steps: [
      {
        title: 'BAPBAP Nexus installieren',
        text: 'Schnapp dir den Launcher. Er kümmert sich um MelonLoader und Updates.',
      },
      {
        title: 'Wähl deinen Track',
        text: 'Neueste Version, Boss Rush, Battle Royale — oder jeder archivierte Stand.',
      },
      {
        title: 'Mods mit einem Klick',
        text: 'Stöber durch BAPHub und installier verifizierte Mods sofort.',
      },
      {
        title: 'BAP drauflos',
        text: 'Spring rein in die Party. Dein Setup bleibt sauber und flexibel.',
      },
    ],
  },
  mods: {
    eyebrow: 'BAPHUB-KATALOG',
    title: 'ALLE MODS & TOOLS',
    subtitle:
      'Der komplette BAPHub-Katalog — jeder Mod und jedes Tool installiert sich mit einem Klick über den BAPBAP Nexus Launcher.',
    searchLabel: 'SUCHE',
    searchPlaceholder: 'Mods, Tags, Autoren suchen…',
    sortLabel: 'SORTIEREN NACH',
    sortOptions: {
      name: 'NAME A–Z',
      newest: 'NEUESTE',
      updated: 'ZULETZT AKTUALISIERT',
    },
    typeTabs: {
      all: 'ALLE',
      mods: 'MODS',
      tools: 'TOOLS',
      'boss-rush': 'BOSS RUSH',
    },
    filterByType: 'Nach Typ filtern',
    filterByTag: 'Nach Tag filtern',
    showing: (x: number, y: number) => `Zeige ${x} von ${y}`,
    clearFilters: 'FILTER ZURÜCKSETZEN',
    surpriseMe: 'ÜBERRASCH MICH',
    surpriseMeLabel: 'Zufälligen Mod öffnen',
    copyFilterLink: 'FILTER-LINK KOPIEREN',
    copied: 'KOPIERT!',
    copiedAnnouncement: 'Filter-Link in die Zwischenablage kopiert',
    emptyTitle: 'KEINE MODS GEFUNDEN',
    emptyText: 'Versuch andere Suchbegriffe oder entfern einen Filter.',
  },
  modDetail: {
    allMods: '← ALLE MODS',
    version: 'VERSION',
    author: 'AUTOR',
    added: 'HINZUGEFÜGT',
    updated: 'AKTUALISIERT',
    requires: 'BENÖTIGT',
    track: 'TRACK',
    type: 'TYP',
    allTracks: 'Alle Tracks',
    modId: 'MOD ID',
    copy: 'KOPIEREN',
    copied: 'KOPIERT!',
    englishNote: 'BESCHREIBUNG AUF ENGLISCH',
    versionHistory: 'VERSIONSVERLAUF',
    installViaLauncher: 'ÜBER DEN LAUNCHER INSTALLIEREN',
    getHelpOnDiscord: 'HILFE AUF DISCORD',
    moreMods: 'MEHR MODS',
  },
  modes: {
    eyebrow: 'MEHR ARTEN ZU SPIELEN',
    title: 'SPIELMODI & TRACKS',
    subtitle:
      'Über das Standardspiel hinaus hält der Launcher ganze Spielmodi und archivierte Builds am Leben — alles mit einem Klick installierbar.',
    cards: {
      'boss-rush': {
        tagline: 'DER COMMUNITY-LIEBLING',
        description:
          'Ein eigener Boss-Rush-Zweig von BAPBAP, den der Launcher am Leben hält. Kämpf dich solo durch Boss-Gauntlets und treib es mit Community-Mods weiter: unbegrenzte Rerolls, 0-Aug-Challenge-Runs, 5-Aug-Chaos und ein Speedrun-Timer auf die Millisekunde.',
        highlights: [
          'Eigener Spiel-Track',
          '4 eigene Mods',
          'Bereit für Speedruns',
        ],
      },
      'battle-royale': {
        tagline: 'NACH JAHREN. ES IST ZURÜCK.',
        description:
          'Das legendäre BAPBAP Battle Royale, wiederbelebt als Community-Playtest-Bundle (v0.1.0, ~565 MB). Ein Klick im Launcher stellt den Klassiker wieder her — kombinier ihn mit dem Old But Gold UI-Mod für den vollen Nostalgie-Kick.',
        highlights: [
          'Bundle v0.1.0',
          'Veröffentlicht am 2026-05-27',
          'Klassischer BR-UI-Mod verfügbar',
        ],
      },
      'time-machine': {
        tagline: 'SPIEL JEDEN BUILD',
        description:
          'Der Launcher archiviert offizielle BAPBAP-Builds, damit du in der Zeit zurückspringen kannst — vom neuesten build-2025-08-19 bis zurück zu build-2025-04-22. Perfekt für Legacy-Strats, Vergleiche und Preservation.',
        highlights: [
          '9 archivierte Builds',
          'Neuester: build-2025-08-19',
          'SHA-256-verifizierte Downloads',
        ],
      },
    },
    bossRush: {
      eyebrow: 'EIGENER SPIEL-TRACK',
      title: 'BOSS RUSH',
      subtitle:
        'Boss Rush ist kein Mod — es ist ein eigener Zweig des Spiels, im Launcher als eigener Track erhalten.',
      branchSnapshot: 'BRANCH-SNAPSHOT',
      steamManifest: 'STEAM MANIFEST',
      download: 'DOWNLOAD',
      directZipAvailable: 'DIRECT ZIP VERFÜGBAR',
      dedicatedMods: '4 EIGENE MODS',
    },
    bundle: {
      eyebrow: 'SPIELMODUS-BUNDLE',
      published: (date: string) => `VERÖFFENTLICHT ${date}`,
      requiresLauncher: (version: string) =>
        `BENÖTIGT LAUNCHER ≥ ${version}`,
      text: 'Ein Klick im Launcher stellt den kompletten Battle-Royale-Modus wieder her. Kombinier ihn mit dem klassischen BR-UI-Mod für den vollen Nostalgie-Kick.',
      pairWith: 'KOMBINIER MIT: BR UI (OLD BUT GOLD)',
    },
    timeMachine: {
      eyebrow: 'SPIEL JEDEN BUILD',
      title: 'VERSION TIME MACHINE',
      subtitle:
        'Jeder archivierte offizielle Build, den der Launcher installieren kann — spring zurück in der Zeit für Legacy-Strats, Vergleiche und Preservation.',
      tableCaption:
        'Archivierte BAPBAP-Builds, die in der Version Time Machine des Launchers verfügbar sind',
      buildHeader: 'BUILD',
      trackHeader: 'TRACK',
      releasedHeader: 'VERÖFFENTLICHT',
      steamManifestHeader: 'STEAM MANIFEST',
      badgesHeader: 'Badges',
      recommended: 'EMPFOHLEN',
      directZip: 'DIRECT ZIP',
      footer: (appId: string, depotId: string) =>
        `Steam App ID ${appId} · Depot ${depotId} · Downloads sind SHA-256-verifiziert.`,
      cta: 'HOL DIR DEN LAUNCHER ZUM BUILD-WECHSELN',
    },
  },
  launcher: {
    eyebrow: 'BAPBAP NEXUS',
    title: 'EIN LAUNCHER. ALLES.',
    subtitle:
      'Mods, Spielmodi, archivierte Builds und das Radio — die ganze BAPBAP-Modding-Szene läuft über einen kostenlosen Launcher.',
    versionLine: (version: string, platform: string) =>
      `v${version} · ${platform} · KOSTENLOS · AUTO-UPDATES`,
    downloadCta: (version: string) => `FÜR WINDOWS LADEN (v${version})`,
    githubCta: 'AUF GITHUB ANSEHEN',
    features: [
      {
        title: 'Mod-Installs mit einem Klick',
        text: 'Stöber durch den BAPHub-Katalog und installier jeden Mod oder jedes Tool sofort — Dateien sind SHA-256-verifiziert.',
      },
      {
        title: 'MelonLoader integriert',
        text: 'Der benötigte Mod-Loader (MelonLoader 0.7.2) wird automatisch installiert und verwaltet.',
      },
      {
        title: 'Version Time Machine',
        text: 'Wechsle zwischen dem neuesten Build und archivierten offiziellen Snapshots bis zurück zum April 2025.',
      },
      {
        title: 'Spielmodus-Bundles',
        text: 'Stell ganze Spielmodi wie den Battle Royale Playtest mit einem einzigen Download wieder her.',
      },
      {
        title: 'BAPBAP Radio',
        text: 'Eine Offline-Soundtrack-Station mit 15 offiziellen Tracks — von Rigtown bis Dimension Atlantis.',
      },
      {
        title: 'Eigene Instanzen & Einstellungen',
        text: 'Extra Match- und Bot-Einstellungen, eigene Instanzen und Mod-Kompatibilität pro Track.',
      },
    ],
    detailsLabel: 'Voraussetzungen und MelonLoader',
    requirementsTitle: 'VORAUSSETZUNGEN',
    requirements: [
      'Windows 10/11 x64',
      'BAPBAP auf Steam (App ID 2226280)',
      'Internetverbindung für Downloads (SHA-256-verifiziert)',
    ],
    installer: 'INSTALLER',
    copyShaLabel: 'Installer-SHA-256 kopieren',
    copied: 'KOPIERT!',
    melonLoader: {
      title: 'WAS IST MELONLOADER?',
      p1Before:
        'MelonLoader ist der Unity-Mod-Loader, auf dem BAPBAP-Mods laufen. Der Launcher installiert automatisch die gepinnte Version ',
      p1After:
        ' — sowohl x64- als auch x86-Builds werden per Hash aus dem BAPHub-Repo verifiziert. Mods selbst sind .dll-Dateien im Mods/-Ordner des Spiels; der Launcher übernimmt das alles für dich.',
      p2: 'Wird vom Launcher automatisch installiert und verwaltet.',
    },
    readGuideCta: 'ZUR INSTALLATIONSANLEITUNG',
    changelog: {
      eyebrow: 'JEDES RELEASE',
      title: 'KOMPLETTER CHANGELOG',
      subtitle:
        'Alle 10 stabilen Releases — vom allerersten Launcher-V2-Build bis zum heutigen BAPBAP Nexus.',
      englishNote: 'Patch Notes auf Englisch.',
      patchNotes: 'PATCH NOTES',
    },
    timeMachineCta: 'VERSION TIME MACHINE',
    radioCta: 'BAPBAP RADIO STECKT IM LAUNCHER',
  },
  radio: {
    eyebrow: 'OFFLINE-SOUNDTRACK-STATION',
    title: 'BAPBAP RADIO',
    subtitle:
      'Die 15 offiziellen BAPBAP-Soundtrack-Stücke aus dem Radio des BAPBAP Nexus Launchers — von den entspannten Lobby-Loops bis zu den Dimension-Kampfthemes.',
    stats: ['TRACKS', 'SZENEN', 'LAUFZEIT'],
    trackCount: (n: number) => `${n} TRACK${n === 1 ? '' : 'S'}`,
    playTrack: (title: string, duration: string) =>
      `${title} abspielen, ${duration}`,
    trackListLabel: 'Radio-Trackliste',
    listen: {
      title: 'HÖR ES IM LAUNCHER',
      text: 'Diese Seite liefert keine Audiodateien aus — die volle Station spielt offline im BAPBAP Nexus Launcher. Die Trackliste liegt im offenen Launcher-Manifest auf GitHub.',
      getLauncher: 'HOL DIR DEN LAUNCHER',
      openManifest: 'MANIFEST AUF GITHUB ÖFFNEN',
    },
  },
  radioPlayer: {
    visualizerBadge: 'VISUALIZER — DER VOLLE SOUND STECKT IM LAUNCHER',
    prevTrack: 'Vorheriger Track',
    nextTrack: 'Nächster Track',
    pause: 'Pause',
    play: 'Abspielen',
    seek: 'Abspielposition',
    position: (shown: string, total: string) => `${shown} von ${total}`,
  },
  guide: {
    eyebrow: 'NULL AUFWAND',
    title: 'ERSTE SCHRITTE',
    subtitle: 'Von Vanilla-BAPBAP zu voll gemoddet in etwa fünf Minuten.',
    steps: [
      {
        title: 'Hol dir BAPBAP auf Steam',
        before: 'Das Grundspiel kommt zuerst — schnapp dir ',
        linkLabel: 'BAPBAP auf Steam',
        after:
          ' (App ID 2226280). Der Launcher arbeitet mit deiner bestehenden Steam-Installation.',
      },
      {
        title: 'BAPBAP Nexus v4.0.4 herunterladen',
        before: '',
        linkLabel: 'Lade den Installer herunter',
        after:
          ' (BAPBAP.Nexus.Setup.4.0.4.exe, Windows x64) und führ ihn aus. Kostenlos, mit Auto-Updates.',
      },
      {
        title: 'MelonLoader installiert sich selbst',
        before: 'Der Launcher installiert automatisch MelonLoader ',
        linkLabel: '0.7.2-ci.2388',
        after:
          ', den Unity-Mod-Loader, auf dem BAPBAP-Mods laufen. Nie wieder manuelles Setup.',
      },
      {
        title: 'Wähl deinen Track',
        before: 'Der neueste offizielle build-2025-08-19, ein ',
        linkLabel: 'archivierter Snapshot',
        after:
          ' bis zurück zu 2025-04-22, der Boss-Rush-Zweig oder das ≈565 MB große Battle Royale Playtest-Bundle.',
      },
      {
        title: 'Mods mit einem Klick installieren',
        before: '',
        linkLabel: 'Stöber durch BAPHub',
        after:
          ' und drück auf Install — SHA-256-verifizierte .dll-Dateien landen automatisch im Mods/-Ordner des Spiels.',
      },
      {
        title: 'BAP drauflos',
        before:
          'Starte das Spiel direkt aus dem Launcher. Dein gemoddetes Setup bleibt sauber und pro Track umschaltbar.',
        linkLabel: '',
        after: '',
      },
    ],
    faqEyebrow: 'GUT ZU WISSEN',
    faqTitle: 'FAQ',
    faqs: [
      {
        question: 'Was ist MelonLoader?',
        answer:
          'MelonLoader ist der Unity-Mod-Loader, auf dem BAPBAP-Mods laufen. Der Launcher pinnt eine bewährte Version (0.7.2-ci.2388) und verwaltet sie automatisch — du installierst oder aktualisierst nie von Hand.',
      },
      {
        question: 'Ist das sicher?',
        answer:
          'Das komplette Mod-Manifest ist offen auf GitHub, jeder Download wird vor der Installation gegen einen SHA-256-Hash geprüft, und Downloads laufen nur über HTTPS. Es wird nichts installiert, das du nicht selbst nachprüfen kannst.',
      },
      {
        question: 'Was bedeutet HOST-ONLY?',
        answer:
          'Host-only-Mods muss nur die Person installieren, die das Match hostet — alle anderen in der Lobby bekommen den Effekt, ohne irgendetwas zu installieren.',
      },
      {
        question: 'Wo liegen die Mods?',
        answer:
          'Mods sind .dll-Dateien im Mods/-Ordner in der Spielinstallation. Der Launcher verwaltet sie für dich pro Track und pro Instanz — du wühlst dich nie selbst durch Ordner.',
      },
      {
        question: 'Wie deinstalliere ich?',
        answer:
          'Schalte Mods im Launcher ab oder entferne sie, oder wechsel jederzeit zurück auf den Vanilla-Track. Kein manuelles Aufräumen nötig.',
      },
      {
        question: 'Beeinflusst das das normale Spiel?',
        answer:
          'Nein — Tracks und Instanzen halten deine Vanilla-Installation sauber. Wechsel zurück zum ungemoddeten Spiel, wann immer du willst.',
      },
    ],
    nextStepsLabel: 'Nächste Schritte',
    ctaTitle: 'FERTIG EINGERICHTET? ZEIT, DEINE MODS ZU WÄHLEN.',
    browseMods: 'MODS DURCHSTÖBERN',
    askOnDiscord: 'FRAG AUF DISCORD',
  },
  modders: {
    eyebrow: 'BAPHUB',
    // Short words on purpose: "VERÖFFENTLICHE DEINEN MOD" overflows the
    // display font at 375px viewports.
    title: 'BRING DEINEN MOD RAUS',
    subtitle:
      'BAPHub ist eine git-basierte Mod-Registry — Veröffentlichen ist ein Pull Request.',
    steps: [
      {
        title: 'Füge deine Dateien hinzu',
        text: 'Leg deine Mod-Dateien unter manifest/channels/release/<package-id>/versions/<version>/files/ ab.',
      },
      {
        title: 'Hashe jede Datei',
        text: 'Berechne pro Datei einen SHA-256-Hash (Hex in Kleinbuchstaben) — der Launcher lehnt alles Unverifizierte ab.',
      },
      {
        title: 'Erstelle die version.json',
        text: 'Beschreibe das Release: Jede Datei bekommt sourcePath, targetPath und ihren sha256.',
      },
      {
        title: 'Aktualisiere die package.json',
        text: 'Aktualisiere <package-id>/package.json mit der neuen Version, Metadaten, Links und Visuals.',
      },
      {
        title: 'Registriere in packages.json',
        text: 'Füge deinen Package-Eintrag in der channel-weiten packages.json-Registry hinzu oder aktualisiere ihn.',
      },
      {
        title: 'Füge deine Bilder hinzu',
        text: 'Leg Thumbnails, Hero-Shots und Galerie-Bilder unter manifest/assets/packages/ ab.',
      },
      {
        title: 'Push auf main',
        text: 'Push (oder öffne einen PR) auf main und lade den Launcher neu — dein Mod ist live auf BAPHub.',
      },
    ],
    filesLabel: 'Repo-Struktur und version.json-Beispiel',
    repoStructure: 'REPO-STRUKTUR',
    versionJson: 'VERSION.JSON',
    hashIt: 'HASHEN (POWERSHELL)',
    detailsLabel: 'Details zum Veröffentlichen',
    targeting: {
      title: 'TRACKS FESTLEGEN',
      p1Before: 'Setz ',
      p1After:
        ', um zu steuern, wo dein Mod auftaucht. Lässt du es weg, ist der Mod für alle Tracks sichtbar.',
      p2Before: 'Ein optionales ',
      p2Middle:
        ' grenzt weiter ein: tracks[], environments[] und platforms[] (z. B. windows-x64). Füge ',
      p2After:
        '-Einträge ({label, url, kind}) für Source, Doku oder Spenden hinzu.',
    },
    secret: {
      title: 'SECRET- & ZEIT-DROPS',
      p1a: 'Setz ',
      p1b: ' (plus optional ',
      p1c: '), um einen Mod hinter einem Passwort zu verstecken. Passwörter liegen als SHA-256-Hashes in ',
      p1d: ' — der Launcher sieht nie Klartext.',
      p2a: ' versiegelt ein Paket bis zu einer vertrauenswürdigen Netzwerkzeit: Der Launcher liest den HTTP-Date-Header von timeSourceUrl, nicht die lokale Uhr. Echtes Beispiel: Die drei April-Boss-Rush-Mods wurden um ',
      p2b: ' freigeschaltet.',
    },
    visuals: {
      title: 'CARD VISUALS',
      presetsLabel: 'VISUAL.PRESET — 28 PRESETS',
      presetsText:
        'Dazu badges[], ribbon, frame (border/glow/pulse) und overlay. hidden_<token>-Varianten wenden den Effekt an, ohne den Tag-Chip zu zeigen.',
      ribbonLabel: 'RIBBON TAGS',
      ribbonText:
        'Nur ein primäres Ribbon wird angezeigt, und UPDATE sticht HOST ONLY. "update-available" ist dynamisch — setz es nie manuell.',
      imageRolesLabel: 'BILD-ROLLEN',
      imageRoles: [
        'Kachel im Grid — quadratisch, ~512×512 empfohlen.',
        'Kartenbild und genereller Fallback.',
        'Breiter Hero auf der Detailseite.',
        'Nur zusätzliche Shots — wird nicht als Kartenbild verwendet.',
      ],
    },
    validation: {
      title: 'VALIDIERUNGS-CHECKLISTE',
      items: [
        'Download-URLs nur über HTTPS — plain http wird abgelehnt.',
        'Jeder Datei-Eintrag braucht einen sha256 (Hex in Kleinbuchstaben).',
        'Keine unsicheren Zielpfade: kein ".." und keine absoluten Pfade.',
        'Nutz "Test Connection" (und die Effekt-Testkarte) in den Launcher-Einstellungen zum Prüfen.',
      ],
    },
    resourcesLabel: 'Ressourcen für Modder',
    ctaTitle: 'ALLES, WAS DU ZUM VERÖFFENTLICHEN BRAUCHST',
    starterTemplates: 'STARTER-TEMPLATES',
    authoringDoc: 'KOMPLETTE AUTHORING-DOKU (DE)',
    openManifest: 'MANIFEST ÖFFNEN',
    getHelpPublishing: 'HILFE BEIM VERÖFFENTLICHEN',
  },
  community: {
    title: 'WERDE TEIL DER BAPBAP MODDING-COMMUNITY',
    sub: 'MOD-DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV-TALK',
    discordCta: 'DISCORD.GG/BAPBAPMODS',
    trailer: {
      eyebrow: 'SIEH ES IN BEWEGUNG',
      title: 'DAS SPIEL',
      subtitle:
        'BAPBAP ist ein Free-to-play-Roguelike-Party-Brawler auf Steam — schau den Trailer, dann modde es.',
      watch: 'TRAILER ANSEHEN ▶',
      thumbAlt: 'BAPBAP-Trailer',
      links: {
        official: 'OFFIZIELLE SEITE',
        steam: 'STEAM-SEITE',
        github: 'GITHUB / BAPHUB-SOURCE',
      },
    },
    credits: {
      eyebrow: 'DIE LEUTE',
      title: 'CREDITS',
      roles: {
        launcher: 'Launcher & Kern-Mods',
        bossRush: 'Boss-Rush-Mods',
      },
      welcomeBefore:
        'Baust du selbst an etwas? Neue Modder sind immer willkommen — ',
      welcomeLink: 'veröffentliche deinen ersten Mod auf BAPHub',
      welcomeAfter: '.',
      disclaimer:
        'BAPBAP Modding ist ein Community-Projekt und steht in keiner Verbindung zu BAPBAP HQ, noch wird es von BAPBAP HQ unterstützt. BAPBAP und alle zugehörigen Inhalte sind Eigentum ihrer jeweiligen Rechteinhaber.',
    },
  },
  notFound: {
    gotBappedPrefix: 'DIESE SEITE WURDE',
    gotBappedHighlight: 'GEBAPPT',
    tipBefore: 'TIPP: DRÜCK',
    tipAfter: 'UM DIE SEITE ZU DURCHSUCHEN',
    backHome: 'ZURÜCK ZUR STARTSEITE',
    browseMods: 'MODS DURCHSTÖBERN',
    surpriseMe: 'ÜBERRASCH MICH',
  },
  meta: {
    home: {
      title: '',
      description:
        'Community-Mods, eigene Spielmodi und der BAPBAP Nexus Launcher für BAPBAP — das Roguelike-Partyspiel. Tritt der Modding-Community auf Discord bei.',
    },
    mods: {
      title: 'Mods',
      description:
        'Alle 12 Community-Mods & Tools für BAPBAP durchstöbern — durchsuchbar, filterbar und mit einem Klick über den BAPBAP Nexus Launcher installierbar.',
    },
    modes: {
      title: 'Spielmodi',
      description:
        'Boss Rush, der Battle Royale Playtest und die Version Time Machine — jede zusätzliche Art, BAPBAP zu spielen, vom Launcher am Leben gehalten.',
    },
    launcher: {
      title: 'Launcher',
      description:
        'BAPBAP Nexus v4.0.4 für Windows herunterladen — Mod-Installs mit einem Klick, MelonLoader integriert, archivierte Builds und BAPBAP Radio.',
    },
    radio: {
      title: 'Radio',
      description:
        'Die offizielle BAPBAP-Soundtrack-Station mit 15 Tracks — Trackliste hier ansehen, offline hören im BAPBAP Nexus Launcher.',
    },
    guide: {
      title: 'Erste Schritte',
      description:
        'Von Vanilla-BAPBAP zu voll gemoddet in etwa fünf Minuten — Schritt-für-Schritt-Anleitung und FAQ.',
    },
    modders: {
      title: 'Für Modder',
      description:
        'Veröffentliche deinen eigenen BAPBAP-Mod auf BAPHub — Manifest-Format, SHA-256-Hashing, Karten-Visuals und Secret-Drops erklärt.',
    },
    community: {
      title: 'Community',
      description:
        'Tritt der BAPBAP-Modding-Community auf Discord bei — Mod-Drops, Playtests, Speedruns und Dev-Talk.',
    },
    notFound: {
      title: '404',
      description: 'Diese Seite wurde GEBAPPT — zurück zu den Mods.',
    },
  },
} satisfies Dict
