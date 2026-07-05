export const LAUNCHER = {
  name: "BAPBAP Nexus",
  version: "4.0.4",
  platform: "Windows x64",
  features: [
    {
      title: "One-Click Mod Installs",
      text: "Browse the BAPHub catalog and install any mod or tool instantly — files are SHA-256 verified.",
    },
    {
      title: "MelonLoader Built In",
      text: "The required mod loader (MelonLoader 0.7.2) is installed and managed automatically.",
    },
    {
      title: "Version Time Machine",
      text: "Switch between the latest build and archived official snapshots back to April 2025.",
    },
    {
      title: "Game Mode Bundles",
      text: "Restore whole game modes like the Battle Royale Playtest with a single download.",
    },
    {
      title: "BAPBAP Radio",
      text: "An offline soundtrack station with 15 official tracks — from Rigtown to Dimension Atlantis.",
    },
    {
      title: "Custom Instances & Settings",
      text: "Extra match and bot settings, custom instances, and per-track mod compatibility.",
    },
  ],
  changelog: [
    { version: "4.0.4", date: "2026-07-02", notes: "Custom Instances bug fix" },
    { version: "4.0.3", date: "2026-06-30", notes: "Improved Translations" },
    { version: "4.0.2", date: "2026-06-30", notes: "Added new Translations" },
    {
      version: "4.0.1",
      date: "2026-06-25",
      notes: "New UI Scale Settings and Bug fixes",
    },
    {
      version: "4.0.0",
      date: "2026-06-24",
      notes: "The BAPBAP Nexus release. New UI, better Performance.",
    },
    { version: "0.3.3", date: "2026-05-27", notes: "Final Fix for Instances" },
    { version: "0.3.0", date: "2026-05-26", notes: "Newly made RebalanceUY" },
    {
      version: "0.2.2",
      date: "2026-04-16",
      notes:
        "Fixes selected instance path handling, bundles the refreshed Default Rebalance workspace data, keeps Tools hidden behind the password gate, and improves workspace repair for missing support catalogs.",
    },
    {
      version: "0.2.1",
      date: "2026-03-24",
      notes:
        "Launcher UI polish, mod workflow fixes, radio import support, and updater improvements.",
    },
    {
      version: "0.1.0",
      date: "2026-03-16",
      notes: "Initial BAPBAP Launcher V2 release.",
    },
  ],
  melonLoader: {
    version: "0.7.2-ci.2388",
    note: "Installed and managed automatically by the launcher.",
  },
  installer: {
    fileName: "BAPBAP.Nexus.Setup.4.0.4.exe",
    sha256: "33fe2d9bb97b23d380004a5e34e5301587694c0be9809194834add8b1518b883",
  },
  requirements: [
    "Windows 10/11 x64",
    "BAPBAP on Steam (App ID 2226280)",
    "Internet connection for downloads (SHA-256 verified)",
  ],
};
