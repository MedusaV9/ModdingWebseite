# Gooby Mod release archive

Built release jars are kept here for reproducible roadmap testing. Numbered
files are canonical; unnumbered copies support existing server tooling.

| Ordinal | Version | Jar | Minecraft / NeoForge | GeckoLib | Create matrix | Status |
|---:|---:|---|---|---|---|---|
| 00 | 2.0.0 base | `v00_goobymod-2.0.0-base.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | imported baseline |
| 01 | 3.0.0 | `01-goobymod-3.0.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 26 GameTests |
| 02 | 3.1.0 | `02-goobymod-3.1.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 31 GameTests |
| 03 | 3.2.0 | `03-goobymod-3.2.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 35 GameTests |
| 04 | 3.3.0 | `04-goobymod-3.3.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 41 GameTests |
| 05 | 3.4.0 | `05-goobymod-3.4.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 49 GameTests |
| 06 | 3.5.0 | `06-goobymod-3.5.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 57 GameTests |
| 07 | 3.6.0 | `07-goobymod-3.6.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 63 GameTests |
| 08 | 3.7.0 | `08-goobymod-3.7.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 70 GameTests |
| 09 | 3.8.0 | `09-goobymod-3.8.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 77 GameTests |
| 10 | 3.9.0 | `10-goobymod-3.9.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | — | build + 83 GameTests |
| 11 | 4.0.0 | `11-goobymod-4.0.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 85 default + 3 Create GameTests |
| 12 | 4.1.0 | `12-goobymod-4.1.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 89 default + 3 Create GameTests |
| 13 | 4.2.0 | `13-goobymod-4.2.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 94 default + 3 Create GameTests |
| 14 | 4.3.0 | `14-goobymod-4.3.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 100 default + 3 Create GameTests |
| 15 | 5.0.0 | `15-goobymod-5.0.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 105 default + 3 Create GameTests |
| 16 | 5.0.1 | `goobymod-5.0.1.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 108 default + 3 Create GameTests |
| 17 | 5.0.2 | `17-goobymod-5.0.2.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 112 default + 3 Create GameTests + loaded soak |
| 18 | 5.1.0 | `18-goobymod-5.1.0.jar` | 1.21.1 / 21.1.248 | 4.9.2 | 6.0.10-280 | build + 118 default + 3 Create + 1 soak GameTest (12k ticks) + 9.5 min RCON wall-clock soak |

Every jar is binary-tracked. `scripts/release.py` validates language parity,
patch notes, and both manuals before building and copying an archive.

Made by Sonic0810.
