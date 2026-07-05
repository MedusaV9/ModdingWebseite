// Real data from the BAPBAP Nexus launcher manifest (manifest/bundles.json).
// There is exactly one bundle — Boss Rush is a game-versions track, not a bundle.
export type Bundle = {
  bundleId: string;
  name: string;
  version: string;
  published: string;
  sizeBytes: number;
  sizeDisplay: string;
  notes: string;
  minLauncherVersion: string;
  channel: string;
};

export const BUNDLES: Bundle[] = [
  {
    bundleId: "battle-royale-playtest",
    name: "Battle Royale Playtest",
    version: "0.1.0",
    published: "2026-05-27",
    sizeBytes: 564701369,
    sizeDisplay: "≈ 565 MB",
    notes: "After years. It is BACK.",
    minLauncherVersion: "0.3.1",
    channel: "stable",
  },
];
