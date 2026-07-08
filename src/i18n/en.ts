// English dictionary — the source of truth for the Dict shape (see context.ts).
// Site data (mods, modes, launcher, radio…) stays English and is NOT in here.
export const en = {
  common: {
    skipToContent: 'SKIP TO CONTENT',
  },
  nav: {
    mods: 'Mods',
    modes: 'Modes',
    launcher: 'Launcher',
    radio: 'Radio',
    guide: 'Guide',
    modders: 'Modders',
    community: 'Community',
    joinDiscord: 'Join Discord',
    // Desktop navbar CTA — kept short so the DE row fits at 1024px without wrapping.
    joinDiscordShort: 'Join Discord',
    languageLabel: 'Language',
    searchLabel: 'Search (press /)',
    openMenu: 'Open navigation menu',
    closeMenu: 'Close navigation menu',
    mainNavLabel: 'Main navigation',
    mobileNavLabel: 'Mobile navigation',
  },
  footer: {
    tagline:
      'A fan-made modding community for BAPBAP, the roguelike party game.',
    quickKeys: 'QUICK KEYS:',
    quickKeysSearch: 'search',
    siteHeading: 'Site',
    linksHeading: 'Links',
    links: {
      discord: 'Discord',
      github: 'GitHub',
      official: 'Official site',
      steam: 'BAPBAP on Steam',
    },
    disclaimer:
      'BAPBAP Modding is a community project and is not affiliated with or endorsed by BAPBAP HQ. BAPBAP and all related assets are property of their respective owners.',
    builtBy: 'Built by the BAPBAP modding community',
  },
  palette: {
    dialogLabel: 'Site search',
    resultsLabel: 'Search results',
    placeholder: 'Search mods, pages, actions…',
    noResults: 'NO RESULTS — try different keywords.',
    footerHint: '↑↓ NAVIGATE · ↵ OPEN · ESC CLOSE',
    copied: 'COPIED!',
    groups: {
      mods: 'MODS',
      pages: 'PAGES',
      actions: 'ACTIONS',
    },
    pages: {
      home: 'Home',
      mods: 'Mods',
      modes: 'Game Modes',
      launcher: 'Launcher',
      radio: 'Radio',
      guide: 'Guide',
      modders: 'For Modders',
      community: 'Community',
    },
    actions: {
      surprise: 'Surprise me — random mod',
      surpriseSub: 'Open a random mod from the catalog',
      copyDiscord: 'Copy Discord invite',
      download: 'Download launcher',
      downloadSub: 'BAPBAP Nexus for Windows',
    },
  },
  loader: {
    loading: 'LOADING',
    loadingLabel: 'Loading page',
  },
  hero: {
    badge: 'COMMUNITY PROJECT — NOT AFFILIATED WITH BAPBAP HQ',
    // Rendered as tagline[0] ✕ tagline[1] ✕ tagline[2] (pink ✕ separators).
    tagline: ['COMMUNITY MODS', 'CUSTOM MODES', 'ONE LAUNCHER'],
    joinDiscord: 'JOIN THE DISCORD',
    getLauncher: 'GET THE LAUNCHER',
    subline: 'FOR BAPBAP — THE ROGUELIKE PARTY GAME ON STEAM',
    // Same order as the module-scope stat values in sections/Hero.tsx.
    stats: ['MODS & TOOLS', 'GAME TRACKS', 'RADIO TRACKS', 'MELONLOADER', 'NEXUS'],
  },
  home: {
    featured: {
      eyebrow: 'BAPHUB CATALOG',
      title: 'FEATURED MODS',
      subtitle:
        'Real community mods, installable in one click through the BAPBAP Nexus launcher.',
    },
    browseAllMods: (n: number) => `BROWSE ALL ${n} MODS`,
    modes: {
      eyebrow: 'MORE WAYS TO PLAY',
      title: 'GAME MODES & TRACKS',
      cta: 'EXPLORE GAME MODES',
    },
    launcher: {
      eyebrow: 'BAPBAP NEXUS',
      title: 'ONE LAUNCHER. EVERYTHING.',
      changelogCta: 'LAUNCHER & CHANGELOG',
      downloadCta: (version: string) => `DOWNLOAD FOR WINDOWS (v${version})`,
      subline: 'Windows x64 · Free · Auto-updates · Installs MelonLoader for you',
    },
    community: {
      marquee: 'JOIN THE DISCORD',
      title: 'JOIN THE BAPBAP MODDING COMMUNITY',
      sub: 'MOD DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV TALK',
      meetCta: 'MEET THE COMMUNITY',
      discordCta: 'DISCORD.GG/BAPBAPMODS',
    },
  },
  howItWorks: {
    eyebrow: 'ZERO FRICTION',
    title: 'HOW MODDING WORKS',
    steps: [
      {
        title: 'Install BAPBAP Nexus',
        text: 'Grab the launcher. It handles MelonLoader and updates for you.',
      },
      {
        title: 'Pick your track',
        text: 'Latest build, Boss Rush, Battle Royale — or any archived version.',
      },
      {
        title: 'One-click install mods',
        text: 'Browse BAPHub and install verified mods instantly.',
      },
      {
        title: 'BAP away',
        text: 'Jump into the party. Your setup stays clean and switchable.',
      },
    ],
  },
  notFound: {
    gotBappedPrefix: 'THIS PAGE GOT',
    gotBappedHighlight: 'BAPPED',
    tipBefore: 'TIP: PRESS',
    tipAfter: 'TO SEARCH THE SITE',
    backHome: 'BACK TO HOME',
    browseMods: 'BROWSE THE MODS',
    surpriseMe: 'SURPRISE ME',
  },
  meta: {
    home: {
      // Empty title = full site title (usePageMeta convention for Home).
      title: '',
      description:
        'Community mods, custom game modes and the BAPBAP Nexus launcher for BAPBAP — the roguelike party game. Join the modding community on Discord.',
    },
    notFound: {
      title: '404',
      description: 'This page got BAPPED — back to the mods.',
    },
  },
}
