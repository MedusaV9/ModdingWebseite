// Real data from the BAPBAP Nexus launcher manifest (manifest/game-versions.json).
export type GameBuild = {
  id: string;
  track: "bapbap" | "boss-rush";
  gameVersion: string;
  releaseDateUtc: string;
  steamManifestId: string;
  recommended: boolean;
  description: string;
  /** Has a direct ZIP download (latest.zip / bossrush.zip) in addition to Steam depot. */
  directDownload?: boolean;
};

export const VERSIONS = {
  steamAppId: "2226280",
  steamDepotId: "2226283",
  builds: [
    {
      id: "latest",
      track: "bapbap",
      gameVersion: "build-2025-08-19",
      releaseDateUtc: "2025-08-19T18:14:42Z",
      steamManifestId: "3691247073315750068",
      recommended: true,
      description: "Latest official BAPBAP release.",
      directDownload: true,
    },
    {
      id: "build-2025-08-14",
      track: "bapbap",
      gameVersion: "build-2025-08-14",
      releaseDateUtc: "2025-08-14T19:21:19Z",
      steamManifestId: "1667107872466291867",
      recommended: false,
      description: "Official snapshot from 2025-08-14.",
    },
    {
      id: "build-2025-08-13",
      track: "bapbap",
      gameVersion: "build-2025-08-13",
      releaseDateUtc: "2025-08-13T19:06:42Z",
      steamManifestId: "5084162501424859386",
      recommended: false,
      description: "Official snapshot from 2025-08-13.",
    },
    {
      id: "build-2025-06-02",
      track: "bapbap",
      gameVersion: "build-2025-06-02",
      releaseDateUtc: "2025-06-02T17:20:23Z",
      steamManifestId: "2817238071018487176",
      recommended: false,
      description: "Official snapshot from 2025-06-02.",
    },
    {
      id: "build-2025-05-26",
      track: "bapbap",
      gameVersion: "build-2025-05-26",
      releaseDateUtc: "2025-05-26T21:23:38Z",
      steamManifestId: "8755208936006757139",
      recommended: false,
      description: "Official snapshot from 2025-05-26.",
    },
    {
      id: "build-2025-05-26-2",
      track: "bapbap",
      gameVersion: "build-2025-05-26",
      releaseDateUtc: "2025-05-26T19:34:23Z",
      steamManifestId: "7313060452487972838",
      recommended: false,
      description: "Official snapshot from 2025-05-26.",
    },
    {
      id: "build-2025-05-13",
      track: "bapbap",
      gameVersion: "build-2025-05-13",
      releaseDateUtc: "2025-05-13T17:16:55Z",
      steamManifestId: "616116375838942956",
      recommended: false,
      description: "Official snapshot from 2025-05-13.",
    },
    {
      id: "build-2025-05-01",
      track: "bapbap",
      gameVersion: "build-2025-05-01",
      releaseDateUtc: "2025-05-01T16:21:05Z",
      steamManifestId: "3820145233746744008",
      recommended: false,
      description: "Official snapshot from 2025-05-01.",
    },
    {
      id: "build-2025-04-22",
      track: "bapbap",
      gameVersion: "build-2025-04-22",
      releaseDateUtc: "2025-04-22T19:32:13Z",
      steamManifestId: "2118764693225205523",
      recommended: false,
      description: "Official snapshot from 2025-04-22.",
    },
    {
      id: "boss-rush",
      track: "boss-rush",
      gameVersion: "boss-rush",
      releaseDateUtc: "2025-06-10T17:58:43Z",
      steamManifestId: "9199065605303375081",
      recommended: false,
      description: "Boss Rush branch snapshot.",
      directDownload: true,
    },
  ] satisfies GameBuild[],
};
