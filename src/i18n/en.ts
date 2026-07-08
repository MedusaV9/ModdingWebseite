import type { PresetId } from '../data/presets'

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
  mods: {
    eyebrow: 'BAPHUB CATALOG',
    title: 'ALL MODS & TOOLS',
    subtitle:
      'The full BAPHub catalog — every mod and tool installs in one click through the BAPBAP Nexus launcher.',
    searchLabel: 'SEARCH',
    searchPlaceholder: 'Search mods, tags, authors…',
    sortLabel: 'SORT BY',
    // Keyed by the Sort ids in ModsPage — the URL param VALUES never change.
    sortOptions: {
      name: 'NAME A–Z',
      newest: 'NEWEST',
      updated: 'RECENTLY UPDATED',
    },
    // Keyed by the TypeFilter ids in ModsPage — only the labels are localized.
    typeTabs: {
      all: 'ALL',
      mods: 'MODS',
      tools: 'TOOLS',
      'boss-rush': 'BOSS RUSH',
    },
    filterByType: 'Filter by type',
    filterByTag: 'Filter by tag',
    filterByCreator: 'Filter by creator',
    showing: (x: number, y: number) => `Showing ${x} of ${y}`,
    clearFilters: 'CLEAR FILTERS',
    surpriseMe: 'SURPRISE ME',
    surpriseMeLabel: 'Open a random mod',
    copyFilterLink: 'COPY FILTER LINK',
    copied: 'COPIED!',
    copiedAnnouncement: 'Filter link copied to clipboard',
    emptyTitle: 'NO MODS MATCH',
    emptyText: 'Try different keywords or drop a filter.',
  },
  modDetail: {
    allMods: '← ALL MODS',
    version: 'VERSION',
    author: 'AUTHOR',
    added: 'ADDED',
    updated: 'UPDATED',
    requires: 'REQUIRES',
    track: 'TRACK',
    type: 'TYPE',
    allTracks: 'All tracks',
    modId: 'MOD ID',
    copy: 'COPY',
    copied: 'COPIED!',
    // Mod descriptions are data and stay English; DE shows a small badge
    // noting that. Empty here = badge not rendered in EN.
    englishNote: '',
    versionHistory: 'VERSION HISTORY',
    installViaLauncher: 'INSTALL VIA LAUNCHER',
    getHelpOnDiscord: 'GET HELP ON DISCORD',
    moreMods: 'MORE MODS',
    moreBy: (author: string) => `MORE BY ${author} →`,
  },
  modes: {
    eyebrow: 'MORE WAYS TO PLAY',
    title: 'GAME MODES & TRACKS',
    subtitle:
      'Beyond the standard game, the launcher keeps whole game modes and archived builds alive — all installable in one click.',
    // Keyed by the MODES ids in src/data/modes.ts (mode NAMES stay data).
    // Also rendered by the Home modes teaser.
    cards: {
      'boss-rush': {
        tagline: 'THE COMMUNITY FAVOURITE',
        description:
          'A dedicated Boss Rush branch of BAPBAP, kept alive by the launcher. Fight boss gauntlets solo, then push it further with community mods: unlimited rerolls, 0-aug challenge runs, 5-aug chaos and a millisecond speedrun timer.',
        highlights: [
          'Dedicated game track',
          '4 dedicated mods',
          'Speedrun-ready',
        ],
      },
      'battle-royale': {
        tagline: 'AFTER YEARS. IT IS BACK.',
        description:
          'The legendary BAPBAP Battle Royale, revived as a community playtest bundle (v0.1.0, ~565 MB). One click in the launcher restores the classic mode — pair it with the Old But Gold UI mod for the full nostalgia hit.',
        highlights: [
          'Bundle v0.1.0',
          'Released 2026-05-27',
          'Classic BR UI mod available',
        ],
      },
      'time-machine': {
        tagline: 'PLAY ANY BUILD',
        description:
          'The launcher archives official BAPBAP builds so you can hop back in time — from the latest build-2025-08-19 all the way back to build-2025-04-22. Perfect for legacy strats, comparisons and preservation.',
        highlights: [
          '9 archived builds',
          'Latest: build-2025-08-19',
          'SHA-256 verified downloads',
        ],
      },
    },
    bossRush: {
      eyebrow: 'DEDICATED GAME TRACK',
      title: 'BOSS RUSH',
      subtitle:
        "Boss Rush isn't a mod — it's a dedicated branch of the game, preserved as its own track in the launcher.",
      branchSnapshot: 'BRANCH SNAPSHOT',
      steamManifest: 'STEAM MANIFEST',
      download: 'DOWNLOAD',
      directZipAvailable: 'DIRECT ZIP AVAILABLE',
      dedicatedMods: '4 DEDICATED MODS',
    },
    bundle: {
      eyebrow: 'GAME MODE BUNDLE',
      published: (date: string) => `PUBLISHED ${date}`,
      requiresLauncher: (version: string) =>
        `REQUIRES LAUNCHER ≥ ${version}`,
      text: 'One click in the launcher restores the whole Battle Royale mode. Pair it with the classic BR UI mod for the full nostalgia hit.',
      pairWith: 'PAIR WITH: BR UI (OLD BUT GOLD)',
    },
    timeMachine: {
      eyebrow: 'PLAY ANY BUILD',
      title: 'VERSION TIME MACHINE',
      subtitle:
        'Every archived official build the launcher can install — hop back in time for legacy strats, comparisons and preservation.',
      tableCaption:
        'Archived BAPBAP builds available in the launcher Version Time Machine',
      buildHeader: 'BUILD',
      trackHeader: 'TRACK',
      releasedHeader: 'RELEASED',
      steamManifestHeader: 'STEAM MANIFEST',
      badgesHeader: 'Badges',
      recommended: 'RECOMMENDED',
      directZip: 'DIRECT ZIP',
      footer: (appId: string, depotId: string) =>
        `Steam App ID ${appId} · Depot ${depotId} · downloads are SHA-256 verified.`,
      cta: 'GET THE LAUNCHER TO SWITCH BUILDS',
    },
  },
  launcher: {
    eyebrow: 'BAPBAP NEXUS',
    title: 'ONE LAUNCHER. EVERYTHING.',
    subtitle:
      'Mods, game modes, archived builds and the radio — the whole BAPBAP modding scene runs through one free launcher.',
    versionLine: (version: string, platform: string) =>
      `v${version} · ${platform} · FREE · AUTO-UPDATES`,
    downloadCta: (version: string) => `DOWNLOAD FOR WINDOWS (v${version})`,
    githubCta: 'VIEW ON GITHUB',
    // Same order as LAUNCHER.features in src/data/launcher.ts (6 entries);
    // also rendered (first three) by the Home launcher teaser.
    features: [
      {
        title: 'One-Click Mod Installs',
        text: 'Browse the BAPHub catalog and install any mod or tool instantly — files are SHA-256 verified.',
      },
      {
        title: 'MelonLoader Built In',
        text: 'The required mod loader (MelonLoader 0.7.2) is installed and managed automatically.',
      },
      {
        title: 'Version Time Machine',
        text: 'Switch between the latest build and archived official snapshots back to April 2025.',
      },
      {
        title: 'Game Mode Bundles',
        text: 'Restore whole game modes like the Battle Royale Playtest with a single download.',
      },
      {
        title: 'BAPBAP Radio',
        text: 'An offline soundtrack station with 15 official tracks — from Rigtown to Dimension Atlantis.',
      },
      {
        title: 'Custom Instances & Settings',
        text: 'Extra match and bot settings, custom instances, and per-track mod compatibility.',
      },
    ],
    detailsLabel: 'Requirements and MelonLoader',
    requirementsTitle: 'REQUIREMENTS',
    // Same order as LAUNCHER.requirements in src/data/launcher.ts.
    requirements: [
      'Windows 10/11 x64',
      'BAPBAP on Steam (App ID 2226280)',
      'Internet connection for downloads (SHA-256 verified)',
    ],
    installer: 'INSTALLER',
    copyShaLabel: 'Copy installer SHA-256',
    copied: 'COPIED!',
    melonLoader: {
      title: 'WHAT IS MELONLOADER?',
      // Split around the pinned-version <span> rendered in the component.
      p1Before:
        'MelonLoader is the Unity mod loader that BAPBAP mods run on. The launcher auto-installs the pinned version ',
      p1After:
        " — both x64 and x86 builds are hash-verified from the BAPHub repo. Mods themselves are .dll files placed in the game's Mods/ folder; the launcher handles all of that for you.",
      p2: 'Installed and managed automatically by the launcher.',
    },
    readGuideCta: 'READ THE INSTALL GUIDE',
    changelog: {
      eyebrow: 'EVERY RELEASE',
      title: 'FULL CHANGELOG',
      subtitle:
        "All 10 stable releases — from the very first Launcher V2 build to today's BAPBAP Nexus.",
      // Changelog NOTES are data and stay English; DE shows a small note.
      // Empty here = note not rendered in EN.
      englishNote: '',
      patchNotes: 'PATCH NOTES',
    },
    timeMachineCta: 'VERSION TIME MACHINE',
    radioCta: 'BAPBAP RADIO SHIPS IN THE LAUNCHER',
  },
  radio: {
    eyebrow: 'OFFLINE SOUNDTRACK STATION',
    title: 'BAPBAP RADIO',
    subtitle:
      'The 15 official BAPBAP soundtrack pieces bundled with the BAPBAP Nexus launcher radio — from the chill lobby loops to the Dimension combat themes.',
    // Same order as the module-scope stat values in RadioPage.tsx.
    stats: ['TRACKS', 'SCENES', 'RUNTIME'],
    trackCount: (n: number) => `${n} TRACK${n === 1 ? '' : 'S'}`,
    playTrack: (title: string, duration: string) =>
      `Play ${title}, ${duration}`,
    trackListLabel: 'Radio track list',
    listen: {
      title: 'LISTEN IN THE LAUNCHER',
      text: "This site doesn't ship the audio files — the full station plays offline inside the BAPBAP Nexus launcher. The track list lives in the open launcher manifest on GitHub.",
      getLauncher: 'GET THE LAUNCHER',
      openManifest: 'OPEN MANIFEST ON GITHUB',
    },
  },
  radioPlayer: {
    visualizerBadge: 'VISUALIZER — FULL AUDIO SHIPS IN THE LAUNCHER',
    prevTrack: 'Previous track',
    nextTrack: 'Next track',
    pause: 'Pause',
    play: 'Play',
    seek: 'Seek position',
    position: (shown: string, total: string) => `${shown} of ${total}`,
  },
  guide: {
    eyebrow: 'ZERO FRICTION',
    title: 'GETTING STARTED',
    subtitle: 'From vanilla BAPBAP to fully modded in about five minutes.',
    // Each step text is split around one inline link/highlight; the link
    // targets stay in GuidePage.tsx (linkLabel '' = no link in that step).
    steps: [
      {
        title: 'Own BAPBAP on Steam',
        before: 'The base game comes first — grab ',
        linkLabel: 'BAPBAP on Steam',
        after:
          ' (App ID 2226280). The launcher works with your existing Steam install.',
      },
      {
        title: 'Download BAPBAP Nexus v4.0.4',
        before: '',
        linkLabel: 'Download the installer',
        after:
          ' (BAPBAP.Nexus.Setup.4.0.4.exe, Windows x64) and run it. Free, with auto-updates.',
      },
      {
        title: 'MelonLoader installs itself',
        before: 'The launcher auto-installs MelonLoader ',
        linkLabel: '0.7.2-ci.2388',
        after:
          ', the Unity mod loader BAPBAP mods run on. No manual setup, ever.',
      },
      {
        title: 'Pick your track',
        before: 'Latest official build-2025-08-19, an ',
        linkLabel: 'archived snapshot',
        after:
          ' back to 2025-04-22, the Boss Rush branch, or the ≈565 MB Battle Royale Playtest bundle.',
      },
      {
        title: 'One-click install mods',
        before: '',
        linkLabel: 'Browse BAPHub',
        after:
          " and hit install — SHA-256-verified .dll files land in the game's Mods/ folder automatically.",
      },
      {
        title: 'BAP away',
        before:
          'Launch the game straight from the launcher. Your modded setup stays clean and switchable per track.',
        linkLabel: '',
        after: '',
      },
    ],
    faqEyebrow: 'GOOD TO KNOW',
    faqTitle: 'FAQ',
    faqs: [
      {
        question: 'What is MelonLoader?',
        answer:
          'MelonLoader is the Unity mod loader that BAPBAP mods run on. The launcher pins a known-good version (0.7.2-ci.2388) and manages it automatically — you never install or update it by hand.',
      },
      {
        question: 'Is this safe?',
        answer:
          'The whole mod manifest is open on GitHub, every download is verified against a SHA-256 hash before it touches your install, and downloads are HTTPS-only. Nothing is installed that you can’t inspect.',
      },
      {
        question: 'What does HOST-ONLY mean?',
        answer:
          'Host-only mods only need to be installed by the player hosting the match — everyone else in the lobby gets the effect without installing anything.',
      },
      {
        question: 'Where do mods live?',
        answer:
          'Mods are .dll files in the Mods/ folder inside the game install. The launcher manages them for you per track and per instance, so you never dig through folders yourself.',
      },
      {
        question: 'How do I uninstall?',
        answer:
          'Toggle or remove any mod from the launcher, or switch back to the vanilla track at any time. No manual cleanup needed.',
      },
      {
        question: 'Does this affect the normal game?',
        answer:
          'No — tracks and instances keep your vanilla install clean. Switch back to the unmodded game whenever you want.',
      },
    ],
    nextStepsLabel: 'Next steps',
    ctaTitle: 'SET UP? TIME TO PICK YOUR MODS.',
    browseMods: 'BROWSE MODS',
    askOnDiscord: 'ASK ON DISCORD',
  },
  modders: {
    eyebrow: 'BAPHUB',
    title: 'PUBLISH YOUR MOD',
    subtitle:
      'BAPHub is a git-backed mod registry — publishing is a pull request.',
    steps: [
      {
        title: 'Add your files',
        text: 'Put your mod files under manifest/channels/release/<package-id>/versions/<version>/files/.',
      },
      {
        title: 'Hash every file',
        text: 'Compute a SHA-256 hash per file (lowercase hex) — the launcher refuses anything unverified.',
      },
      {
        title: 'Create version.json',
        text: 'Describe the release: every file gets sourcePath, targetPath and its sha256.',
      },
      {
        title: 'Update package.json',
        text: 'Update <package-id>/package.json with the new version, metadata, links and visuals.',
      },
      {
        title: 'Register in packages.json',
        text: 'Add or update your package entry in the channel-wide packages.json registry.',
      },
      {
        title: 'Add your images',
        text: 'Drop thumbnails, hero shots and gallery images under manifest/assets/packages/.',
      },
      {
        title: 'Push to main',
        text: 'Push (or open a PR) to main and reload the launcher — your mod is live on BAPHub.',
      },
    ],
    filesLabel: 'Repository structure and version.json example',
    repoStructure: 'REPO STRUCTURE',
    versionJson: 'VERSION.JSON',
    hashIt: 'HASH IT (POWERSHELL)',
    detailsLabel: 'Publishing details',
    targeting: {
      title: 'TARGETING TRACKS',
      // Prose split around the inline <code> tokens kept in ModdersPage.tsx.
      p1Before: 'Set ',
      p1After:
        ' to control where your mod shows up. Omit it and the mod is visible for all tracks.',
      p2Before: 'Optional ',
      p2Middle:
        ' narrows things further: tracks[], environments[] and platforms[] (e.g. windows-x64). Add ',
      p2After: ' entries ({label, url, kind}) for source, docs or donations.',
    },
    secret: {
      title: 'SECRET & TIMED DROPS',
      p1a: 'Set ',
      p1b: ' (plus an optional ',
      p1c: ') to password-gate a mod. Passwords are stored as SHA-256 hashes in ',
      p1d: ' — the launcher never sees plaintext.',
      p2a: ' seals a package until trusted network time: the launcher reads the HTTP Date header from timeSourceUrl, not the local clock. Real example: the three April boss-rush mods unlocked at ',
      p2b: '.',
    },
    visuals: {
      title: 'CARD VISUALS',
      presetsLabel: 'VISUAL.PRESET — 28 PRESETS',
      presetsText:
        'Plus badges[], ribbon, frame (border/glow/pulse) and overlay. hidden_<token> variants apply the effect without showing the tag chip.',
      ribbonLabel: 'RIBBON TAGS',
      ribbonText:
        'Only one primary ribbon shows, and UPDATE outranks HOST ONLY. "update-available" is dynamic — never set it manually.',
      imageRolesLabel: 'IMAGE ROLES',
      // Same order as the module-scope image role names in ModdersPage.tsx.
      imageRoles: [
        'Grid tile — square, ~512×512 recommended.',
        'Card image and general fallback.',
        'Wide hero on the detail page.',
        'Extra shots only — not used as the card image.',
      ],
    },
    gallery: {
      eyebrow: 'VISUAL.PRESET — LIVE',
      title: 'CARD VISUALS GALLERY',
      subtitle:
        'The launcher supports 28 card presets via visual.preset — this is all of them, rendered live in pure CSS. Pick a swatch to preview it on the test card.',
      tryAll: 'TRY ALL 28 LIVE IN THE GALLERY ↓',
      chooseLabel: 'Choose a preset',
      testCardTitle: 'EFFECT TEST CARD',
      testCardSummary:
        'A fake mod card — this is how your BAPHub card ships with the selected preset.',
      // Neutral chips on the effect test card (fake metadata).
      testCardBadges: ['PREVIEW', 'QOL', 'V1.0.0'],
      copy: 'COPY',
      copied: 'COPIED!',
      hiddenNote:
        'Every effect token also has a hidden_<token> variant that applies the effect without the visible tag chip.',
      // One-liners per preset, keyed by PresetId (see src/data/presets.ts).
      descriptions: {
        default: 'Plain standard card, no extras.',
        featured: 'Amber highlight with a slow glow pulse.',
        shiny: 'Clean diagonal shimmer — subtle specular gloss.',
        holo: 'Holographic rainbow shimmer, subtle.',
        neon: 'Pink neon glow, bold and loud.',
        frost: 'Pale ice gradient with a frosted top edge.',
        ember: 'Rising embers — warm flicker from below.',
        prism: 'Rainbow facets, slowly drifting.',
        glitch: 'RGB split and jitter, digital error style.',
        aurora: 'Soft green/teal/purple northern lights.',
        frozen: 'Strong ice look, cold and crystalline.',
        plasma: 'Violet and electric, high energy.',
        toxic: 'Green/acid, radioactive style.',
        cosmic: 'Deep space look with wide color nebulas.',
        vapor: 'Pink/cyan retro wave.',
        storm: 'Dark electro-storm look.',
        inferno: 'Hot red/orange flare.',
        velvet: 'Dark violet soft glow.',
        matrix: 'Digital green with scanline character.',
        ghost: 'Pale, translucent and quiet.',
        crystal: 'Cyan-blue, clean crystal shine.',
        chrome: 'Metallic/silver.',
        noir: 'Dark low-gloss look.',
        sunset: 'Orange/pink evening gradient.',
        void: 'Dark deep-space style.',
        candy: 'Colorful sweet-pop look.',
        dev: 'Dashed terminal look for dev builds.',
        event: 'Party stripes and confetti for events.',
      } satisfies Record<PresetId, string>,
    },
    validation: {
      title: 'VALIDATION CHECKLIST',
      items: [
        'HTTPS-only download URLs — plain http is rejected.',
        'Every file entry needs a sha256 (lowercase hex).',
        'No unsafe target paths: no ".." and no absolute paths.',
        'Use "Test Connection" (and the effect test card) in the launcher Settings to verify.',
      ],
    },
    resourcesLabel: 'Modder resources',
    ctaTitle: 'EVERYTHING YOU NEED TO SHIP',
    starterTemplates: 'STARTER TEMPLATES',
    authoringDoc: 'FULL AUTHORING DOC (DE)',
    openManifest: 'OPEN THE MANIFEST',
    getHelpPublishing: 'GET HELP PUBLISHING',
  },
  community: {
    title: 'JOIN THE BAPBAP MODDING COMMUNITY',
    sub: 'MOD DROPS ✕ PLAYTESTS ✕ SPEEDRUNS ✕ DEV TALK',
    discordCta: 'DISCORD.GG/BAPBAPMODS',
    modCount: (n: number) => `${n} mods on BAPHub`,
    allTheirMods: 'ALL THEIR MODS →',
    trailer: {
      eyebrow: 'SEE IT IN MOTION',
      title: 'THE GAME',
      subtitle:
        'BAPBAP is a free-to-play roguelike party brawler on Steam — watch the trailer, then mod it.',
      watch: 'WATCH THE TRAILER ▶',
      thumbAlt: 'BAPBAP trailer',
      links: {
        official: 'OFFICIAL SITE',
        steam: 'STEAM PAGE',
        github: 'GITHUB / BAPHUB SOURCE',
      },
    },
    credits: {
      eyebrow: 'THE PEOPLE',
      title: 'CREDITS',
      // Keyed by the module-scope credit entries in CommunityPage.tsx.
      roles: {
        launcher: 'Launcher & core mods',
        bossRush: 'Boss Rush mods',
      },
      welcomeBefore:
        'Building something of your own? New modders are always welcome — ',
      welcomeLink: 'publish your first mod on BAPHub',
      welcomeAfter: '.',
      disclaimer:
        'BAPBAP Modding is a community project and is not affiliated with or endorsed by BAPBAP HQ. BAPBAP and all related assets are property of their respective owners.',
    },
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
    mods: {
      title: 'Mods',
      description:
        'Browse all 12 community mods & tools for BAPBAP — searchable, filterable and one-click installable via the BAPBAP Nexus launcher.',
    },
    modes: {
      title: 'Game Modes',
      description:
        'Boss Rush, the Battle Royale Playtest and the Version Time Machine — every extra way to play BAPBAP, kept alive by the launcher.',
    },
    launcher: {
      title: 'Launcher',
      description:
        'Download BAPBAP Nexus v4.0.4 for Windows — one-click mod installs, MelonLoader built in, archived builds and BAPBAP Radio.',
    },
    radio: {
      title: 'Radio',
      description:
        'The 15-track official BAPBAP soundtrack station — preview the tracklist here, listen offline in the BAPBAP Nexus launcher.',
    },
    guide: {
      title: 'Getting Started',
      description:
        'From vanilla BAPBAP to fully modded in about five minutes — step-by-step install guide and FAQ.',
    },
    modders: {
      title: 'For Modders',
      description:
        'Publish your own BAPBAP mod on BAPHub — manifest format, SHA-256 hashing, card visuals and secret drops explained.',
    },
    community: {
      title: 'Community',
      description:
        'Join the BAPBAP modding community on Discord — mod drops, playtests, speedruns and dev talk.',
    },
    notFound: {
      title: '404',
      description: 'This page got BAPPED — back to the mods.',
    },
  },
}
