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
};

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
  },
];
