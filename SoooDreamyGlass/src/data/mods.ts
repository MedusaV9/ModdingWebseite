export type Mod = {
  id: string;
  name: string;
  type: "mod" | "tool";
  summary: string;
  description: string;
  version: string;
  author: string;
  tags: string[];
  ribbon?: "host-only" | "new";
  track?: "boss-rush";
  thumb: string;
  added: string;
  updated: string;
  requires: string;
  authorUrl?: string;
  versions: { version: string; changelog: string }[];
  longDescription?: string;
};

const REQUIRES = "MelonLoader 0.7.2-ci.2388";
const SONIC_URL = "https://github.com/Sonic0810";

const T =
  "https://raw.githubusercontent.com/Sonic0810/BAPBAPLauncher/main/manifest/assets/packages/";

export const MODS: Mod[] = [
  {
    id: "sonic.bapbap.hidden-dev-arguments",
    name: "BAPBAP Hidden Dev Arguments",
    type: "mod",
    summary: "Full native argument catalog and arena category integration.",
    description:
      "Standalone mod that extends hidden/dev argument access and category integration for BAPBAP.",
    version: "1.0.0",
    author: "Sonic0810",
    tags: ["dev", "arguments", "arena"],
    ribbon: "host-only",
    thumb: T + "devarg.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
    longDescription:
      "This Mod gives you way more Arguments (and sometimes broken stuff).",
  },
  {
    id: "sonic.bapbap.pool-randomizer",
    name: "BAPBAP Pool Randomizer",
    type: "mod",
    summary: "Rarity-aware randomizer across vanilla, legacy and hidden pools.",
    description:
      "Standalone pool randomizer for BAPBAP with tier-aware replacement and broad candidate coverage.",
    version: "1.0.0",
    author: "Sonic0810",
    tags: ["randomizer", "pool", "qol"],
    ribbon: "host-only",
    thumb: T + "refresh.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
  },
  {
    id: "jackmygoodman.bapbap.boss-rush-qol",
    name: "BossRushQoL",
    type: "mod",
    summary: "Unlimited Rerolls + 5 Card Choices",
    description:
      "A QoL mod for the boss rush gamemode which gives you unlimited rerolls and allows you to choose between 5 cards instead of 3 at once.",
    version: "1.0.1",
    author: "jackmygoodman",
    tags: ["boss-rush", "qol", "rerolls"],
    track: "boss-rush",
    thumb: T + "bossrush.jpg",
    added: "2026-03-18",
    updated: "2026-03-22",
    requires: REQUIRES,
    versions: [
      { version: "1.0.1", changelog: "Updated Boss Rush QoL build" },
      { version: "1.0.0", changelog: "Initial launcher release" },
    ],
    longDescription:
      "A QoL mod for the boss rush gamemode which gives you unlimited rerolls and allows you to choose between 5 cards instead of 3 at once. Note: it might look buggy sometimes but works as intended",
  },
  {
    id: "jackmygoodman.bapbap.boss-rush-speedrun-timer",
    name: "SpeedrunTimer",
    type: "mod",
    summary: "Shows milliseconds on the Boss Rush timer.",
    description:
      "Boss Rush timer mod that adds millisecond precision to the in-game timer display.",
    version: "1.0.0",
    author: "jackmygoodman",
    tags: ["boss-rush", "timer", "speedrun"],
    ribbon: "new",
    track: "boss-rush",
    thumb: T + "boss-rush-speedrun-timer.png",
    added: "2026-04-10",
    updated: "2026-04-10",
    requires: REQUIRES,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
  },
  {
    id: "jackmygoodman.bapbap.boss-rush-0-augs",
    name: "0 Augs Boss Rush",
    type: "mod",
    summary: "Lets you choose zero augments in Boss Rush.",
    description:
      "Boss Rush gameplay mod that changes augment selection so you can choose 0 augments.",
    version: "1.0.0",
    author: "jackmygoodman",
    tags: ["boss-rush", "augs", "challenge"],
    ribbon: "new",
    track: "boss-rush",
    thumb: T + "boss-rush-0-augs.png",
    added: "2026-04-10",
    updated: "2026-04-10",
    requires: REQUIRES,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
  },
  {
    id: "jackmygoodman.bapbap.boss-rush-5-augs",
    name: "5 Augs Boss Rush",
    type: "mod",
    summary: "Lets you choose five augments in Boss Rush.",
    description:
      "Boss Rush gameplay mod that changes augment selection so you can choose 5 augments.",
    version: "1.0.0",
    author: "jackmygoodman",
    tags: ["boss-rush", "augs", "qol"],
    ribbon: "new",
    track: "boss-rush",
    thumb: T + "boss-rush-5-augs.png",
    added: "2026-04-10",
    updated: "2026-04-10",
    requires: REQUIRES,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
  },
  {
    id: "sonic.bapbap.hp-numbers",
    name: "BAPBAP HP Numbers",
    type: "mod",
    summary: "Displays live HP values on health bars.",
    description:
      "Standalone HP numbers overlay mod for BAPBAP with in-match value updates.",
    version: "1.0.1",
    author: "Sonic0810",
    tags: ["ui", "hp", "qol"],
    thumb: T + "hpnumber.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [
      {
        version: "1.0.1",
        changelog: "Fix HP text visibility and safe prop handling",
      },
      { version: "1.0.0", changelog: "Initial launcher release" },
    ],
  },
  {
    id: "sonic.bapbap.arena-random-chars",
    name: "BAPBAP Arena Random Chars",
    type: "mod",
    summary: "Random character assignment for arena rounds.",
    description:
      "Standalone arena random character mod that rotates characters during active arena matches.",
    version: "1.0.0",
    author: "Sonic0810",
    tags: ["arena", "characters", "random"],
    ribbon: "host-only",
    thumb: T + "randomchar.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
    longDescription:
      "Everybody gets a new character after each round. Host only.",
  },
  {
    id: "sonic.bapbap.br-ui-old-but-gold",
    name: "BR UI (Old But Gold)",
    type: "mod",
    summary: "Restores the classic Battle Royale style UI.",
    description: "Adds the old Battle Royale HUD/UI style back into BAPBAP.",
    version: "1.0.0",
    author: "Sonic0810",
    tags: ["ui", "battle-royale", "legacy"],
    thumb: T + "oldgold.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
  },
  {
    id: "sonic.bapbap.fps-camera",
    name: "BAPFPS (First/Third Person)",
    type: "mod",
    summary: "Enables first-person and third-person camera gameplay.",
    description:
      "Camera mod that enables switching into first-person and third-person perspectives.",
    version: "0.2.0",
    author: "Sonic0810",
    tags: ["camera", "first-person", "third-person"],
    thumb: T + "fps.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "0.2.0", changelog: "Initial launcher release" }],
  },
  {
    id: "sonic.bapbap.asset-dumper",
    name: "BAPBAP Asset Dumper",
    type: "tool",
    summary: "Dump assets, icons and sounds from BAPBAP into a local folder.",
    description:
      "Dump all assets, icons and sounds inside the game into a folder so you can reuse them. In game press F8 to open the UI.",
    version: "1.0.0",
    author: "Sonic0810",
    tags: ["tool", "asset-dump", "modding", "audio"],
    thumb: T + "assetdumper.png",
    added: "2026-03-02",
    updated: "2026-03-02",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "1.0.0", changelog: "Initial launcher release" }],
    longDescription:
      "If you want all assets, icons and sounds inside of the game, use this tool/mod to dump them into a folder so you can reuse them. Ingame press F8 to open the UI. The mod creates a dump folder inside your BAPBAP game folder. Audio files are exported as .banks and can be converted with FMOD Bank Tools: https://github.com/Wouldubeinta/Fmod-Bank-Tools/releases",
  },
  {
    id: "sonic.bapbap.more-custom-settings",
    name: "BAPBAP More Custom Settings",
    type: "mod",
    summary: "Allows more settings for matches and bots.",
    description: "Adds more settings for custom matches and bots in BAPBAP.",
    version: "0.1.0",
    author: "Sonic0810",
    tags: ["arena", "bots", "settings"],
    thumb: T + "more-custom-settings.png",
    added: "2026-04-16",
    updated: "2026-04-16",
    requires: REQUIRES,
    authorUrl: SONIC_URL,
    versions: [{ version: "0.1.0", changelog: "Initial launcher release" }],
  },
];
