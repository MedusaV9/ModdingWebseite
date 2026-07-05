// Real data from the BAPBAP Nexus launcher manifest (manifest/radio/radio.json).
export type RadioTrack = {
  id: string;
  title: string;
  group: string;
  durationMs: number;
};

export const RADIO = {
  stationName: "BAPBAP Radio",
  stationSubtitle: "Offline soundtrack station",
  tracks: [
    {
      id: "bapbap-lobby-music-chill",
      title: "BAPBAP Lobby Music Chill",
      group: "Lobby",
      durationMs: 112117,
    },
    {
      id: "barrio-cantina-rigtown-stages",
      title: "Barrio Cantina Rigtown Stages",
      group: "Rigtown",
      durationMs: 202057,
    },
    { id: "cave", title: "Cave", group: "Stage", durationMs: 228415 },
    {
      id: "dimension-atlantis",
      title: "Dimension Atlantis",
      group: "Dimension",
      durationMs: 53424,
    },
    {
      id: "dimension-atlantis-combat",
      title: "Dimension Atlantis Combat",
      group: "Dimension",
      durationMs: 53496,
    },
    {
      id: "dimension-sin-city",
      title: "Dimension Sin City",
      group: "Dimension",
      durationMs: 43517,
    },
    {
      id: "dimension-sin-city-drums",
      title: "Dimension Sin City Drums",
      group: "Dimension",
      durationMs: 43519,
    },
    { id: "dojo-stage", title: "Dojo Stage", group: "Stage", durationMs: 215092 },
    {
      id: "floating-island-1",
      title: "Floating Island 1",
      group: "Stage",
      durationMs: 129925,
    },
    {
      id: "floating-island-2",
      title: "Floating Island 2",
      group: "Stage",
      durationMs: 316500,
    },
    { id: "worksite", title: "Worksite", group: "Stage", durationMs: 288000 },
    {
      id: "night-lobby-v2",
      title: "Night Lobby V2",
      group: "Lobby",
      durationMs: 167865,
    },
    {
      id: "slime-main-loop",
      title: "Slime Main Loop",
      group: "Loop",
      durationMs: 30677,
    },
    { id: "testtest", title: "Testtest", group: "Misc", durationMs: 98400 },
    { id: "tutorial", title: "Tutorial", group: "Tutorial", durationMs: 155664 },
  ] satisfies RadioTrack[],
};
