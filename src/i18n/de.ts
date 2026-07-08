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
    notFound: {
      title: '404',
      description: 'Diese Seite wurde GEBAPPT — zurück zu den Mods.',
    },
  },
} satisfies Dict
