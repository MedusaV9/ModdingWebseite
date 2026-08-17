# AMP-Parity-Plan — Between vs. CubeCoders AMP

Ziel: **Between** (das Panel in `Between/`) soll alles können, was AMP von CubeCoders kann — und es besser machen. Dieses Dokument ist (1) das Architektur-Audit des Ist-Zustands, (2) die Feature-Matrix Ist vs. AMP, (3) die vollständige AMPTemplates-Spieleliste als Kompatibilitäts-Checkliste und (4) der Wellen-Plan.

- Referenz für die Spieleliste: [CubeCoders/AMPTemplates](https://github.com/CubeCoders/AMPTemplates) @ Commit `7f027ec` (2026-08, per `gh api repos/CubeCoders/AMPTemplates/git/trees/main` gezogen — **237 `.kvp`-Generic-Templates**).
- AMP-Feature-Referenz: AMP 2.6 (ADS/Instance Manager, Generic Module, dedizierte Module für Minecraft/srcds/Rust, SFTP, Scheduler, Backups (S3), Benutzer/Rollen (LDAP), Metrics, RCON, Developer-API).

---

## 1. Architektur-Audit (Ist-Zustand, Runde 29)

**Ein Node-Prozess, null externe Services** — Express + ws + JSON-Dokumentstore, React-19-Frontend (Vite, Tailwind v4) wird im Prod-Modus direkt mitserviert.

| Schicht | Umsetzung |
|---|---|
| **Prozess-/Instanz-Verwaltung** | `server/src/servers/` — `ServerManager` (CRUD, Ports, Klonen, Boot/Shutdown), `ServerInstance` (Lifecycle: start/stop/restart/kill, Stop-Ketten Konsole→Signal→Kill-Tree, Crash-Detection + Auto-Restart mit Backoff/Circuit-Breaker, Ressourcen-Sampling pro Prozessbaum), Runtime-Abstraktion `runtime.ts` (Host-Prozess **oder** Docker-Container über denselben Lifecycle) |
| **Docker-Integration** | `lib/docker.ts` — handgerollter Engine-API-Client über den Daemon-Socket (kein Dependency): Pull mit Progress, create/start/kill/wait, hijacked Attach-Stream für Konsole, Stats-Stream, `docker exec`-Web-Terminal (`ws/shell.ts`). Container überleben Panel-Restarts (Label + Re-Adoption). Optional: ohne Daemon degradiert alles sauber auf Prozess-Runtime |
| **Templates/Blueprints** | `blueprints/` — deklaratives JSON-Format (Schema-validiert): Install-Steps (steamcmd/download/paper/fabric/vanilla/writeFile/command/mkdir/docker-script), startCommand mit `{{VAR}}`-Templating, Variablen (typisiert, Ports, advanced), Stop-Strategie, Query/RCON/Mods/ConfigFiles/Docker-Defaults. **73 Builtins**, Custom-Blueprints im UI, Pterodactyl-Egg-Importer (v1+v2, per URL/Datei), Game-Library-Katalog (60 Einträge) |
| **Installer** | `install/pipeline.ts` + `steam/` — SteamCMD (auto-bootstrap, anonyme + authentifizierte Installs, Steam-Guard-Flow), Direkt-Downloads (SHA256, Progress, abbrechbar), Versions-Resolver (Paper Fill v3, Piston, Fabric), traversal-sichere zip/tar.gz-Extraktion mit Bomben-Budgets |
| **Dateimanager** | `services/files.ts` + `api/files.ts` — list/read/write/mkdir/rename/copy/move/delete/upload (4 GiB, Streaming)/download (Datei + Ordner-als-Zip)/zip/extract/stat, alles durch `safeJoin` gesandboxt (Traversal strukturell unmöglich), Editor-Cap 5 MiB, Kollisions-Konvention " (2)" |
| **Backups** | `services/backups.ts` — Zip-Snapshots, Excludes pro Blueprint, Notizen, Locking, Retention („letzte N ungesperrte"), Restore mit Wipe + Safety-Backup |
| **Scheduler** | `services/schedules.ts` — eigener 5-Feld-Cron (Vixie-OR), **Event-Trigger** (server.running/offline/crashed, player.joined/left), Task-Ketten (power/command/backup/wait), Template-Variablen, Run-Historie |
| **Benutzer/Rechte** | `auth/service.ts` — Admin/User global, **12 granulare Subuser-Rechte pro Server**, TOTP-2FA + Recovery-Codes, Sessions, API-Keys mit Scopes, Audit-Log (live über WS), Login-Rate-Limit |
| **Multi-Node** | `nodes/` — AMP-„Spires"-Äquivalent: headless Agent (`BETWEEN_MODE=node`), Registry + Health-Poll, `ServerGateway`-Dispatch, eine gemultiplexte WS-Bridge pro Node |
| **Monitoring** | `services/metrics.ts` — Host-CPU/RAM/Disk/Load mit Ring-Historie, per-Instanz-Ringe, Minecraft-Ping + Source-A2S (Spielerlisten), RCON (handgerollt), Discord + generische JSON-Webhooks |
| **Frontend** | `web/` — Liquid-Glass-Designsystem (`web/DESIGN.md` ist bindend), 8 Themes, EN/DE (compiler-erzwungene Key-Parität), Mobile (Bottom-Dock, Sheets), Live-Updates über eine gemultiplexte WS, PWA, Code-Splitting |
| **Qualität** | 439 Tests (419 + 20 Docker-Skips), oxlint 0 Warnungen, strict tsc, 0 npm-audit-Findings, 73/73 Blueprints valide |

---

## 2. Feature-Matrix: Between (Ist) vs. AMP

Legende: ✅ vorhanden (Parität oder besser) · 🟡 teilweise · ❌ fehlt

| Bereich | AMP | Between (Ist) | Status | Lücke / Plan |
|---|---|---|---|---|
| **Instances** (create/start/stop/kill/clone/suspend/reinstall) | Instance Manager (ADS), ein AMP-Prozess pro Instanz | ServerManager + ServerInstance, Klonen mit Port-Overrides, Suspend, Reinstall, Auto-Start, Auto-Update-vor-Start | ✅ | — |
| **Multi-Maschine** | ADS „Controller/Target" (Spires) | Multi-Node: headless Agent + Panel-Gateway + WS-Bridge; v1: einige Remote-Ops bewusst 400 | 🟡→✅ | Welle 2: Remote-Parität (Config-Editor, Schedules, Zip, Clone auf Node) |
| **Isolation** | Docker-Unterstützung pro Instanz | Runtime-Wahl Prozess **oder** Docker (Limits, bridge/host, Re-Adoption, Image-Pull im UI) | ✅ | — |
| **Konsole** | Live-Konsole, Befehle, Filter | Ringpuffer + ANSI, stdin **und** RCON-Transport, Suche, Log-Download, Backlog nach Reconnect, Web-Terminal (`docker exec`) — AMP hat kein Container-Web-Terminal | ✅ | — |
| **Scheduler** | Zeit- + Event-Trigger, Task-Ketten | Cron + Event-Trigger (Status + Player-Join/Leave), Task-Ketten, Template-Variablen, Run-Historie, Debounce | ✅ | Welle 2: Intervall-Trigger („alle N Minuten" ohne Cron-Syntax), mehr Events |
| **Backups** | Lokal + S3-Upload, Retention | Zip, Locking, Notizen, Retention, Restore mit Safety-Backup | 🟡 | Welle 2: S3/objektbasierte Remote-Ziele, Backup-Zeitpläne-Presets |
| **User/Rollen** | Rollen, Feingranular, LDAP | Admin/User + 12 Subuser-Rechte/Server, 2FA + Recovery, API-Keys mit Scopes, Audit | 🟡 | Welle 3: Rollen-Templates, LDAP/OIDC optional |
| **SFTP** | Eingebauter SFTP-Server pro Instanz | **Welle 1: saubere Schnittstelle** — Konfigurationsmodell (`settings.sftp`: enabled/port/bind), Provider-Seam + ehrlicher Platzhalter-Service (`services/fileaccess.ts`), Admin-API `GET`/`PATCH /api/fileaccess` (Aktivieren wird in v1 mit klarer Meldung abgelehnt) | ❌→🟡 | **Welle 2: konkrete Implementierung** (eingebetteter SSH/SFTP-Listener, s. §4.4); Welle 3: Public-Key-Auth, SFTP auf Remote-Nodes |
| **FileManager** | Browser, Editor, Upload | Browser + Editor + Streaming-Upload/-Download, Drag&Drop (auch Ordner), rename/copy/move, Archiv/Extract (zip-slip-sicher), Bildvorschau, Rechte-Gating | ✅ | — (besser als AMP) |
| **Metrics** | CPU/RAM pro Instanz, Spieler | Host- + Instanz-Metriken mit Historie (Reload-fest), Spielerlisten (A2S/MC) mit Quick-Actions | ✅ | Welle 2: längere Historie/Persistenz, Alarme |
| **Templates (Generic)** | Generic Module + 237 `.kvp`-Community-Templates | Blueprint-JSON (73 builtin) + Egg-Import + Katalog; **Welle 1: Datei-Template-Loader (`data/templates/`, JSON + YAML) + dokumentiertes Format (`docs/TEMPLATES.md`)** | 🟡→✅ | Welle 2+: AMPTemplates-Lücken schließen (siehe Checkliste), `.kvp`-Import-Konverter |
| **API** | REST + Developer-API, API-Keys | Vollständige REST + WS (alles, was das UI kann), API-Keys mit Scopes, node:test-Integrationssuite | ✅ | Welle 3: OpenAPI-Spez generieren |
| **RCON** | RCON-Unterstützung | Source-RCON handgerollt (Konsole + Stop-Strategie), A2S/MC-Query | ✅ | Welle 2: WebRCON (Rust) |
| **Mods/Workshop** | Steam Workshop, teils CurseForge | Modrinth-Browser (1-Klick-Install), SteamCMD-Workshop über Install-Steps | 🟡 | Welle 2: Steam-Workshop-Browser, CurseForge |
| **Steam-Login** | Authentifizierte Installs | Interaktiver SteamCMD-Login (stdin-only Secrets, Guard-Code-Flow) | ✅ | — |
| **Benachrichtigungen** | E-Mail/Push (begrenzt) | Discord + generischer JSON-Webhook mit Event-Toggles | ✅ | Welle 3: E-Mail (SMTP) |
| **UI/UX** | WinForms-artige Web-UI | Liquid-Glass-Designsystem, Mobile-First, 2 Sprachen, 8 Themes, PWA, A11y | ✅ | — (deutlich besser) |
| **Lizenz/Betrieb** | Kommerziell, Lizenzserver | Self-hosted, keine Lizenz, eine Node-Binary | ✅ | — |

**Zusammenfassung:** Welle 1 schließt die Template-Lücke (**dokumentiertes, dateibasiertes Generic-Template-System**) vollständig und legt für die zweite strukturelle Lücke (**SFTP**) die stabile Schnittstelle an (Konfigurationsmodell + Provider-Seam + Platzhalter-Service, API-Fläche final) — der konkrete Protokoll-Listener folgt in Welle 2 und tauscht nur noch die Provider-Instanz aus. Verbleibende Teil-Lücken (S3-Backups, Workshop-Browser, Remote-Node-Parität, LDAP) sind in Welle 2/3 eingeplant.

---

## 3. AMPTemplates-Kompatibilitätsziel (237 Templates)

Quelle: `CubeCoders/AMPTemplates` @ `7f027ec`. Abgehakt = es existiert ein funktionsäquivalentes Between-Builtin-Blueprint. **Stand: 66/237 Varianten abgedeckt** (plus die komplette Minecraft-Java-Familie, Rust, CS2 usw., die AMP über dedizierte Module statt über AMPTemplates abdeckt — siehe Hinweis unter der Liste).

Jedes nicht abgehakte Spiel ist über `custom-steamcmd` / `custom-command` / Egg-Import / das neue Datei-Template-Format sofort betreibbar; „abgedeckt" heißt hier: kuratiertes Builtin mit verifizierten Ports/Start-Args.

- [x] **Abiotic Factor** (`abiotic-factor.kvp`, Windows, Linux) — Between-Blueprint `abiotic-factor`
- [ ] **Alien Swarm: Reactive Drop** (`alien-swarm-reactive-drop.kvp`)
- [ ] **American Truck Simulator** (`american-truck-simulator.kvp`, Windows, Linux)
- [ ] **ANEURISM IV** (`aneurismiv.kvp`, Windows, Linux)
- [ ] **Archean** (`archean.kvp`, Windows, Linux)
- [x] **ARK: Survival Ascended** (`ark-sa.kvp`, Windows, Linux) — Between-Blueprint `ark-survival-ascended`
- [x] **ARK: Survival Ascended (Minimal)** (`ark-sa-min.kvp`, Windows, Linux) — Between-Blueprint `ark-survival-ascended`
- [x] **ARK: Survival Evolved** (`ark-se.kvp`, Windows, Linux) — Between-Blueprint `ark-survival-evolved`
- [x] **ARK: Survival Evolved (Minimal with Server API)** (`ark-seminapi.kvp`, Windows, Linux) — Between-Blueprint `ark-survival-evolved`
- [x] **ARK: Survival Evolved (Minimal)** (`ark-se-min.kvp`, Windows, Linux) — Between-Blueprint `ark-survival-evolved`
- [x] **Arma 3** (`arma3.kvp`, Windows, Linux) — Between-Blueprint `arma-3`
- [x] **Arma Reforger** (`arma-reforger.kvp`, Windows, Linux) — Between-Blueprint `arma-reforger`
- [ ] **ASKA** (`aska.kvp`, Windows, Linux)
- [ ] **Assetto Corsa** (`assetto-corsa.kvp`, Windows, Linux)
- [ ] **Assetto Corsa Competizione** (`assetto-corsa-comp.kvp`, Windows, Linux)
- [ ] **Astro Colony** (`astro-colony.kvp`, Windows, Linux)
- [x] **Astroneer** (`astroneer.kvp`, Windows, Linux) — Between-Blueprint `astroneer`
- [x] **Avorion** (`avorion.kvp`, Linux) — Between-Blueprint `avorion`
- [x] **Barotrauma** (`barotrauma.kvp`, Windows, Linux) — Between-Blueprint `barotrauma`
- [ ] **BeamMP** (`beammp.kvp`, Windows, Linux)
- [ ] **Beasts of Bermuda** (`beasts-of-bermuda.kvp`, Windows, Linux)
- [ ] **Black Mesa** (`black-mesa.kvp`, Windows, Linux)
- [ ] **Blackwake** (`blackwake.kvp`, Windows)
- [ ] **Broke Protocol** (`broke-protocol.kvp`, Windows, Linux)
- [ ] **Bun App Runner** (`bun-app-runner.kvp`, Windows, Linux)
- [ ] **Call of Duty 4: Modern Warfare** (`call-of-duty4mw.kvp`, Windows, Linux)
- [ ] **Call of Duty: Black Ops (Plutonium Mod)** (`call-of-dutybo1.kvp`, Windows, Linux)
- [ ] **Call of Duty: Black Ops II (Plutonium Mod)** (`call-of-dutybo2.kvp`, Windows, Linux)
- [ ] **Call of Duty: Modern Warfare 2 (2009)** (`call-of-dutymw2.kvp`, Windows, Linux)
- [ ] **Call of Duty: Modern Warfare 3 (2011 - Plutonium Mod)** (`call-of-dutymw3-plutonium.kvp`, Windows, Linux)
- [ ] **Call of Duty: Modern Warfare 3 (2011)** (`call-of-dutymw3.kvp`, Windows, Linux)
- [ ] **Call of Duty: World at War (Plutonium Mod)** (`call-of-dutywaw.kvp`, Windows, Linux)
- [ ] **Carrier Command 2** (`carrier-command2.kvp`, Windows, Linux)
- [ ] **Chivalry: Medieval Warfare** (`chivalry-medieval-warfare.kvp`, Windows, Linux)
- [ ] **Clone Hero** (`clone-hero.kvp`, Windows, Linux)
- [ ] **code-server** (`code-server.kvp`, Linux)
- [ ] **Colony Survival** (`colony-survival.kvp`, Windows, Linux)
- [x] **Conan Exiles (Legacy)** (`conan-exiles.kvp`, Windows) — Between-Blueprint `conan-exiles`
- [x] **Conan Exiles Enhanced** (`conan-exiles-enhanced.kvp`, Windows, Linux) — Between-Blueprint `conan-exiles`
- [x] **Core Keeper** (`core-keeper.kvp`, Windows, Linux) — Between-Blueprint `core-keeper`
- [ ] **Counter-Strike 1.6** (`counter-strike16.kvp`, Windows, Linux)
- [x] **Counter-Strike 2** (`counter-strike2.kvp`, Windows, Linux) — Between-Blueprint `counter-strike-2`
- [ ] **Counter-Strike: Condition Zero** (`counter-strike-czero.kvp`, Windows, Linux)
- [ ] **Counter-Strike: Global Offensive** (`counter-strike-go.kvp`, Windows, Linux)
- [x] **Counter-Strike: Source** (`counter-strike-source.kvp`, Windows, Linux) — Between-Blueprint `counter-strike-source`
- [ ] **Craftopia** (`craftopia.kvp`, Windows)
- [ ] **Creativerse** (`creativerse.kvp`, Windows)
- [ ] **CryoFall** (`cryofall.kvp`, Windows, Linux)
- [ ] **Cube 2: Sauerbraten** (`cube2-sauerbraten.kvp`, Linux)
- [ ] **Cubic Odyssey** (`cubic-odyssey.kvp`, Windows, Linux)
- [ ] **Day of Defeat** (`day-of-defeat.kvp`, Windows, Linux)
- [x] **Day of Defeat: Source** (`day-of-defeat-source.kvp`, Windows, Linux) — Between-Blueprint `day-of-defeat-source`
- [ ] **Day of Dragons** (`day-of-dragons.kvp`, Windows, Linux)
- [ ] **DayZ (Experimental)** (`dayz-experimental.kvp`, Windows)
- [ ] **DayZ (Stable)** (`dayz-original.kvp`, Windows, Linux)
- [ ] **Dead Matter** (`deadmatter.kvp`, Windows, Linux)
- [ ] **DeadPoly** (`deadpoly.kvp`, Windows)
- [ ] **Deno App Runner** (`deno-app-runner.kvp`, Windows, Linux)
- [x] **Don't Starve Together** (`dont-starve-together.kvp`, Windows, Linux) — Between-Blueprint `dont-starve-together`
- [ ] **DOOM II (Zandronum Mod)** (`doom2.kvp`, Windows, Linux)
- [ ] **Dota 2** (`dota2.kvp`, Windows, Linux)
- [ ] **Dotnet App Runner** (`dotnet-app-runner.kvp`, Windows, Linux)
- [ ] **Dune Awakening** (`duneawakening.kvp`, Windows)
- [x] **Eco** (`eco.kvp`, Windows, Linux) — Between-Blueprint `eco`
- [x] **Empyrion Galactic Survival** (`empyrion-galactic-survival.kvp`, Windows) — Between-Blueprint `empyrion`
- [x] **Enshrouded** (`enshrouded.kvp`, Windows) — Between-Blueprint `enshrouded`
- [ ] **ET: Legacy** (`et-legacy.kvp`, Windows, Linux)
- [x] **Euro Truck Simulator 2** (`euro-truck-simulator-2.kvp`, Windows, Linux) — Between-Blueprint `euro-truck-simulator-2`
- [ ] **EXFIL** (`exfil.kvp`, Windows)
- [ ] **E.Y.E: Divine Cybermancy** (`eye-dc.kvp`, Windows)
- [x] **Factorio** (`factorio.kvp`, Windows, Linux) — Between-Blueprint `factorio`
- [x] **Fistful of Frags** (`fistful-of-frags.kvp`, Windows, Linux) — Between-Blueprint `fistful-of-frags`
- [x] **FiveM - Grand Theft Auto V Server** (`fivem.kvp`, Windows, Linux) — Between-Blueprint `fivem`
- [ ] **FOUNDRY** (`foundry.kvp`, Windows, Linux)
- [ ] **Foundry Virtual Tabletop** (`foundry-vtt.kvp`, Windows, Linux)
- [ ] **Frozen Flame** (`frozen-flame.kvp`, Windows)
- [x] **Garry's Mod** (`garrys-mod.kvp`, Windows, Linux) — Between-Blueprint `garrys-mod`
- [x] **Garry's Mod (64 Bit)** (`garrys-mod64.kvp`, Windows, Linux) — Between-Blueprint `garrys-mod`
- [ ] **GatekeeperV2 Bot (Deprecated)** (`gatekeeperv2.kvp`, Windows, Linux)
- [ ] **Geyser** (`geyser.kvp`, Windows, Linux)
- [ ] **Ground Branch** (`ground-branch.kvp`, Windows)
- [ ] **Half-Life** (`half-life.kvp`, Windows, Linux)
- [x] **Half-Life 2: Deathmatch** (`half-life2dm.kvp`, Windows, Linux) — Between-Blueprint `half-life-2-deathmatch`
- [ ] **Half-Life Deathmatch: Source** (`half-life-deathmatch-source.kvp`, Windows, Linux)
- [ ] **Half-Life: Opposing Force** (`half-life-opposing-force.kvp`, Windows, Linux)
- [ ] **HumanitZ** (`humanitz.kvp`, Windows, Linux)
- [x] **Hurtworld** (`hurtworld.kvp`, Windows, Linux) — Between-Blueprint `hurtworld`
- [ ] **Hytale** (`hytale.kvp`, Windows, Linux)
- [x] **Icarus** (`icarus.kvp`, Windows) — Between-Blueprint `icarus`
- [ ] **Impostor - Among Us Server** (`impostor.kvp`, Windows, Linux)
- [x] **Insurgency Sandstorm** (`insurgencysandstorm.kvp`, Windows, Linux) — Between-Blueprint `insurgency-sandstorm`
- [ ] **Java App Runner** (`java-app-runner.kvp`, Windows, Linux)
- [ ] **Just Cause 3 Multiplayer Mod** (`jc3mp.kvp`, Windows, Linux)
- [ ] **Kaboom!** (`kaboom.kvp`, Windows, Linux)
- [ ] **Killing Floor** (`killing-floor.kvp`, Windows, Linux)
- [x] **Killing Floor 2** (`killing-floor-2.kvp`, Windows, Linux) — Between-Blueprint `killing-floor-2`
- [ ] **Last Oasis** (`last-oasis.kvp`, Windows)
- [ ] **Left 4 Dead** (`left-4-dead.kvp`, Windows, Linux)
- [x] **Left 4 Dead 2** (`left-4-dead2.kvp`, Windows, Linux) — Between-Blueprint `left-4-dead-2`
- [ ] **Longvinter** (`longvinter.kvp`, Windows)
- [ ] **Longvinter (Linux Wine)** (`longvinter-wine.kvp`, Linux)
- [ ] **Luanti** (`luanti.kvp`, Windows, Linux)
- [ ] **MariaDB** (`mariadb.kvp`, Windows, Linux)
- [ ] **Mindustry** (`mindustry.kvp`, Windows, Linux)
- [x] **Minecraft Bedrock** (`minecraft-bedrock.kvp`, Windows, Linux) — Between-Blueprint `minecraft-bedrock`
- [ ] **Minetest (Legacy)** (`minetest.kvp`, Windows, Linux)
- [ ] **Miscreated** (`miscreated.kvp`, Windows)
- [ ] **MongoDB** (`mongodb.kvp`, Windows, Linux)
- [x] **Mordhau** (`mordhau.kvp`, Windows, Linux) — Between-Blueprint `mordhau`
- [ ] **Mount & Blade II: Bannerlord** (`mount-and-blade2.kvp`, Windows, Linux)
- [x] **Multi Theft Auto: San Andreas** (`mta-sa.kvp`, Windows, Linux) — Between-Blueprint `multi-theft-auto`
- [ ] **MX Bikes** (`mxbikes.kvp`, Windows)
- [ ] **MySQL** (`mysql.kvp`, Windows, Linux)
- [ ] **Myth of Empires** (`myth-of-empires.kvp`, Windows)
- [ ] **NEBULOUS: Fleet Command** (`nebulous-fleet-command.kvp`, Windows)
- [x] **Necesse** (`necesse.kvp`, Windows, Linux) — Between-Blueprint `necesse`
- [ ] **Night of the Dead** (`night-of-the-dead.kvp`, Windows)
- [ ] **Nightingale** (`nightingale.kvp`, Windows)
- [ ] **No One Survived** (`no-one-survived.kvp`, Windows)
- [x] **No More Room in Hell** (`no-more-room-in-hell.kvp`, Windows, Linux) — Between-Blueprint `no-more-room-in-hell`
- [ ] **Node.js App Runner** (`node.kvp`, Windows, Linux)
- [ ] **Nuclear Option** (`nuclear-option.kvp`, Windows)
- [ ] **Nukkit** (`nukkit.kvp`, Windows, Linux)
- [x] **open.mp - Grand Theft Auto: San Andreas Server** (`open-mp.kvp`, Windows, Linux) — Between-Blueprint `open-mp`
- [ ] **Open World - RimWorld Server** (`open-world.kvp`, Windows, Linux)
- [ ] **OpenRA - Dune 2000** (`openra-dune-2000.kvp`, Linux)
- [ ] **OpenRA - Red Alert** (`openra-red-alert.kvp`, Linux)
- [ ] **OpenRA - Tiberian Dawn** (`openra-tiberian-dawn.kvp`, Linux)
- [ ] **OpenRCT2** (`openrct2.kvp`, Windows, Linux)
- [ ] **OpenStarbound** (`openstarbound.kvp`, Windows, Linux)
- [x] **OpenTTD** (`openttd.kvp`, Windows, Linux) — Between-Blueprint `openttd`
- [ ] **Operation: Harsh Doorstop** (`operation-harsh-doorstop.kvp`, Windows, Linux)
- [x] **Palworld** (`palworld.kvp`, Windows, Linux) — Between-Blueprint `palworld`
- [ ] **Palworld (Modded)** (`palworld-modded.kvp`, Windows, Linux)
- [ ] **Path of Titans** (`path-of-titans.kvp`, Windows, Linux)
- [x] **Pavlov VR** (`pavlov-vr.kvp`, Linux) — Between-Blueprint `pavlov-vr`
- [ ] **Pirates, Vikings, & Knights II** (`pirates-vikings-knights2.kvp`, Windows, Linux)
- [ ] **PixARK** (`pixark.kvp`, Windows, Linux)
- [ ] **Plains of Pain** (`plains-of-pain.kvp`, Windows)
- [ ] **PocketMine-MP** (`pocketmine-mp.kvp`, Windows, Linux)
- [ ] **Portal Knights** (`portal-knights.kvp`, Windows, Linux)
- [ ] **PostgreSQL** (`postgresql.kvp`, Windows, Linux)
- [ ] **Pre-Fortress 2** (`pre-fortress2.kvp`, Windows, Linux)
- [ ] **Project 5: Sightseer** (`project5-sightseer.kvp`, Windows, Linux)
- [x] **Project Zomboid** (`project-zomboid.kvp`, Windows, Linux) — Between-Blueprint `project-zomboid`
- [ ] **Puck** (`puck.kvp`, Windows, Linux)
- [ ] **Pumpkin** (`pumpkin.kvp`, Windows, Linux)
- [ ] **Python App Runner** (`python-app-runner.kvp`, Windows, Linux)
- [ ] **Quake III Arena** (`quake3-arena.kvp`, Windows, Linux)
- [ ] **Quake Live** (`quake-live.kvp`, Windows, Linux)
- [ ] **RAGE:MP - Grand Theft Auto V Server** (`ragemp.kvp`, Windows, Linux)
- [ ] **RedM - Red Dead Redemption 2 Server** (`redm.kvp`, Windows, Linux)
- [ ] **Reign Of Kings** (`reign-of-kings.kvp`, Windows)
- [ ] **Renown** (`renown.kvp`, Windows)
- [ ] **Rimworld Together - RimWorld Server** (`rimworld-together.kvp`, Windows, Linux)
- [ ] **Rising Storm 2: Vietnam** (`rising-storm2-vietnam.kvp`, Windows, Linux)
- [ ] **Rising World (Unity Version)** (`rising-world.kvp`, Windows, Linux)
- [x] **Risk of Rain 2** (`risk-of-rain-2.kvp`, Windows) — Between-Blueprint `risk-of-rain-2`
- [ ] **Romestead** (`romestead.kvp`, Windows, Linux)
- [ ] **RuneScape: Dragonwilds** (`runescape-dragonwilds.kvp`, Windows)
- [ ] **San Andreas Multiplayer** (`sa-mp.kvp`, Windows, Linux)
- [ ] **Sapiens** (`sapiens.kvp`, Linux)
- [x] **Satisfactory** (`satisfactory.kvp`, Windows, Linux) — Between-Blueprint `satisfactory`
- [x] **SCP: Secret Laboratory** (`scp-secret-laboratory.kvp`, Windows, Linux) — Between-Blueprint `scp-secret-laboratory`
- [ ] **SCUM** (`scum.kvp`, Windows)
- [x] **Seven Days To Die** (`seven-days-to-die.kvp`, Windows, Linux) — Between-Blueprint `7-days-to-die`
- [ ] **SinusBot** (`sinusbot.kvp`, Linux)
- [ ] **Skyrim Together Reborn** (`skyrim-together-reborn.kvp`, Windows)
- [ ] **Smalland: Survive the Wilds** (`smalland.kvp`, Windows)
- [ ] **Soldat** (`soldat.kvp`, Windows, Linux)
- [x] **Sons Of The Forest** (`sons-of-the-forest.kvp`, Windows, Linux) — Between-Blueprint `sons-of-the-forest`
- [ ] **Soulmask** (`soulmask.kvp`, Windows, Linux)
- [x] **Space Engineers** (`space-engineers-generic.kvp`, Windows, Linux) — Between-Blueprint `space-engineers`
- [ ] **Space Engineers (Torch)** (`space-engineers-torch.kvp`, Windows)
- [ ] **Spellmasons** (`spellmasons.kvp`, Windows, Linux)
- [x] **Squad** (`squad-dedicated-server.kvp`, Windows, Linux) — Between-Blueprint `squad`
- [ ] **Squad 44** (`post-scriptum.kvp`, Windows)
- [ ] **STAR WARS Jedi Knight - Jedi Academy** (`jedi-academy.kvp`, Windows, Linux)
- [ ] **Starbound** (`starbound.kvp`, Windows, Linux)
- [ ] **Stardew Valley** (`stardew-valley.kvp`, Windows, Linux)
- [ ] **Starmade** (`starmade.kvp`, Windows, Linux)
- [ ] **StarRupture** (`star-rupture.kvp`, Windows)
- [x] **Stationeers** (`stationeers.kvp`, Windows, Linux) — Between-Blueprint `stationeers`
- [ ] **Staxel** (`staxel.kvp`, Windows)
- [ ] **Stay In Tarkov** (`stay-in-tarkov.kvp`, Windows, Linux)
- [ ] **Stormworks** (`stormworks.kvp`, Windows)
- [ ] **Subnautica (Legacy Nitrox Mod)** (`subnautica-legacy.kvp`, Windows)
- [ ] **Subnautica (Nitrox Mod)** (`subnautica2.kvp`, Windows)
- [ ] **Subsistence** (`subsistence.kvp`, Windows)
- [ ] **Sunkenland** (`sunkenland.kvp`, Windows)
- [x] **Sven Co-op** (`sven-co-op.kvp`, Windows, Linux) — Between-Blueprint `sven-coop`
- [ ] **Swords 'n Magic and Stuff** (`swords-n-magic-and-stuff.kvp`, Windows)
- [ ] **Synergy** (`synergy.kvp`, Windows, Linux)
- [ ] **Tarkov (Fika Mod) (Legacy)** (`tarkov-fika.kvp`, Windows, Linux)
- [ ] **Tarkov (Fika Mod) 4.0.0+** (`tarkov-fika-new.kvp`, Windows, Linux)
- [x] **Team Fortress 2** (`team-fortress2.kvp`, Windows, Linux) — Between-Blueprint `team-fortress-2`
- [ ] **Team Fortress 2 (64 Bit)** (`team-fortress2-64.kvp`, Windows, Linux)
- [ ] **Team Fortress 2 Classified** (`team-fortress2-classified.kvp`, Windows, Linux)
- [ ] **Team Fortress Classic** (`team-fortress-classic.kvp`, Windows, Linux)
- [x] **TeamSpeak 3** (`teamspeak3.kvp`, Windows, Linux) — Between-Blueprint `teamspeak3`
- [ ] **TeamSpeak 6** (`teamspeak6.kvp`, Windows, Linux)
- [ ] **TeaSpeak** (`teaspeak.kvp`, Linux)
- [ ] **Teeworlds** (`teeworlds.kvp`, Windows, Linux)
- [x] **Terraria** (`terraria.kvp`, Windows, Linux) — Between-Blueprint `terraria`
- [ ] **TerraTech Worlds** (`terratech-worlds.kvp`, Windows)
- [ ] **TES3MP - The Elder Scrolls III: Morrowind Server** (`tes3mp.kvp`, Windows, Linux)
- [x] **The Forest** (`the-forest.kvp`, Windows) — Between-Blueprint `the-forest`
- [ ] **The Front** (`the-front.kvp`, Windows)
- [x] **The Isle (EVRIMA)** (`theisle-evrima.kvp`, Windows, Linux) — Between-Blueprint `the-isle-evrima`
- [ ] **The Isle (Legacy)** (`theisle-legacy.kvp`, Windows, Linux)
- [ ] **The Lord of the Rings: Return to Moria** (`lotr-moria.kvp`, Windows, Linux)
- [ ] **Titanfall 2** (`titanfall2.kvp`, Windows, Linux)
- [x] **tModLoader (Legacy)** (`tmodloader.kvp`, Windows, Linux) — Between-Blueprint `tmodloader`
- [x] **tModLoader 1.4+** (`tmodloader14.kvp`, Windows, Linux) — Between-Blueprint `tmodloader`
- [ ] **Tower Unite** (`tower-unite.kvp`, Windows, Linux)
- [ ] **TShock - Terraria Server** (`tshock.kvp`, Windows, Linux)
- [ ] **Turbo Sliders Unlimited** (`turbo-sliders-unlimited.kvp`, Windows)
- [ ] **txAdmin** (`txadmin.kvp`, Windows, Linux)
- [ ] **Unreal Tournament 2004** (`ut2004.kvp`, Windows, Linux)
- [ ] **Unreal Tournament 99** (`ut99.kvp`, Windows, Linux)
- [x] **Unturned** (`unturned.kvp`, Windows, Linux) — Between-Blueprint `unturned`
- [x] **Valheim** (`valheim.kvp`, Windows, Linux) — Between-Blueprint `valheim`
- [ ] **VEIN** (`vein.kvp`, Windows, Linux)
- [ ] **Veloren** (`veloren.kvp`, Windows, Linux) — als Community-Egg im Game-Library-Katalog
- [x] **Vintage Story (Legacy)** (`vintage-story.kvp`, Windows, Linux) — Between-Blueprint `vintage-story`
- [x] **Vintage Story 1.18.8+** (`vintage-story-new.kvp`, Windows, Linux) — Between-Blueprint `vintage-story`
- [ ] **Voyagers of Nera** (`voyagers-of-nera.kvp`, Windows)
- [x] **V Rising** (`v-rising.kvp`, Windows) — Between-Blueprint `v-rising`
- [ ] **Windrose** (`windrose.kvp`, Windows, Linux)
- [ ] **Windward** (`windward.kvp`, Windows, Linux)
- [ ] **Windward Horizon** (`windward-horizon.kvp`, Windows, Linux)
- [ ] **Wolfenstein: Enemy Territory** (`wolfenstein-et.kvp`, Windows, Linux)
- [ ] **Wreckfest** (`wreckfest.kvp`, Windows)
- [ ] **Wreckfest 2** (`wreckfest2.kvp`, Windows)
- [ ] **Wurm Unlimited** (`wurm-unlimited.kvp`, Windows, Linux)
- [x] **Xonotic** (`xonotic.kvp`, Windows, Linux) — Between-Blueprint `xonotic`
- [x] **Zombie Panic! Source** (`zombie-panic-source.kvp`, Windows, Linux) — Between-Blueprint `zombie-panic-source`

**Hinweis zu AMPs dedizierten Modulen:** AMPTemplates deckt nur AMPs *Generic Module* ab. Spiele, die AMP über first-party Module bedient, sind in Between bereits Builtins: die komplette **Minecraft-Java-Familie** (Paper, Purpur, Vanilla, Fabric, Forge, NeoForge, Quilt, Folia, Velocity — AMP: MinecraftModule), **Rust** (AMP: eigenes Modul; WebRCON in Welle 2) und diverse srcds-Spiele. Zusätzlich hat Between `mumble-server`, `openttd` u. a., und `demo-echo` / `custom-steamcmd` / `custom-command` als Meta-Blueprints.

**Weg zur 100-%-Abdeckung:** (1) Das Welle-1-Datei-Template-Format macht jedes fehlende Spiel per Drop-in-Datei betreibbar (ohne Panel-Update); (2) Welle 2+ arbeitet die Liste in kuratierten Builtin-Chargen ab (Priorität: Steam-Anonymous-Installs mit Linux-Support, dann Wine/Proton-Fälle wie Windows-only-Server); (3) ein `.kvp`-Import-Konverter (analog zum Egg-Importer) ist als Welle-2-Kandidat eingeplant, damit AMPTemplates direkt eingelesen werden können.

---

## 4. Welle 1 — Scope (dieses Arbeitspaket)

1. **Dieses Dokument** (Audit + Matrix + Checkliste).
2. **Generic-Instance-Template-System**: dokumentiertes deklaratives Template-Format (JSON **und** YAML) = Blueprint-Schema (steamcmd-app/docker-image, start-command, ports, env/variables, config-files, update über `steamAutoUpdate`/Reinstall); neuer **Datei-Template-Loader** (`data/templates/*.json|*.yaml|*.yml` — Drop-in wie bei AMPs Generic-Templates, Rescan zur Laufzeit per API/UI); Format-Doku `Between/docs/TEMPLATES.md`; Beispiel-Templates in `Between/templates/`. Die geforderten 10 Spiele (Minecraft Java/Bedrock, Valheim, Palworld, Rust, ARK, Terraria, Satisfactory, Factorio, 7DTD) existieren als kuratierte Builtins und zusätzlich als Datei-Template-Beispiele.
3. **File-Manager-Backend**: existierte bereits vollständig (siehe Matrix) — Audit + Testabdeckung verifiziert, keine Lücken gefunden.
4. **Dateizugriff per Standard-Protokoll — Schnittstelle** (Implementierung folgt in Welle 2):
   - **Wie die etablierten Panels es machen:** *Pterodactyl* bettet in den Wings-Daemon einen eigenen SFTP-Server ein (Standard-Port **2022**, kein OpenSSH beteiligt); Login ist `panelBenutzername.serverKurzId` mit dem Panel-Passwort (alternativ hinterlegte SSH-Keys), jede Session ist auf das Verzeichnis genau dieses Servers gejailt und die Panel-Rechte werden pro Operation durchgesetzt. *AMP* bettet den SFTP-über-SSH-Listener direkt in den jeweiligen Instanz-Prozess ein (ein Port pro Instanz); AMP-Panel-Zugangsdaten loggen sich direkt ein und sehen nur das Wurzelverzeichnis dieser Instanz. Gemeinsamer Nenner: **kein System-SSH, kein OS-Benutzer pro Spieler** — der Panel-Prozess spricht das Protokoll selbst und erzwingt sein eigenes Rechte-/Sandbox-Modell.
   - **Between-Zielbild (Welle 2):** EIN eingebetteter, dependency-freier SFTP-Listener pro Panel/Agent (Pterodactyl-Muster, nicht ein Port pro Instanz), Zugangsdaten **pro Benutzer×Server**, jede Session durch dieselbe `safeJoin`-Sandbox wie der Web-Dateimanager, `server.files.read`/`write` bei **jeder** Operation re-validiert (entzogene Rechte beenden offene Sessions — dieselbe Invariante wie bei den WebSocket-Hubs).
   - **In dieser Welle gebaut:** Konfigurationsmodell (`PanelSettings.sftp`: `enabled`/`port` (Default 2022)/`bind`), Provider-Interface `FileAccessProvider` (start/stop/running — genau das, was der echte Listener implementieren wird), ehrlicher `SftpPlaceholderProvider` (meldet `implemented: false` und verweigert das Aktivieren mit klarer Meldung, statt still nichts zu tun), `FileAccessService` mit Validierung/Persistenz/Reconcile + Shutdown-Pfad in `app.stop()`, Admin-API `GET`/`PATCH /api/fileaccess`. Die API-Fläche und Verdrahtung bleiben beim Tausch auf den echten Provider byte-identisch.
5. **Tests**: bestehende Suite grün halten; neue Unit-/Integrationstests für Template-Loader, YAML-Dokument-Parser und die File-Access-Schnittstelle (inkl. Fake-Provider, der den Start/Stop/Reconcile-Lebenszyklus des künftigen echten Listeners beweist); Docker-Instanz-Smoke-Test, wenn ein Daemon verfügbar ist.

## 5. Welle 2+ — Plan

**Welle 2 (Kern-Parität ausbauen):**
- **Scheduler**: Intervall-Trigger, mehr Events (Backup fertig, Update verfügbar), Zeitzonen-Anzeige.
- **Backups**: S3-kompatible Remote-Ziele (zero-dep SigV4-Client), Backup-Verifikation, Download-Streaming von Remote-Nodes.
- **Metrics**: persistente Langzeit-Historie (Downsampling), Schwellwert-Alarme → Webhooks.
- **Remote-Node-Parität**: Config-Editor/Schedules/Clone/Zip auf Nodes, Steam-Login pro Node (SFTP auf Nodes folgt in Welle 3, nach der Basis-Implementierung).
- **Templates**: `.kvp`-Import-Konverter (AMPTemplates direkt einlesen), nächste Builtin-Charge aus der Checkliste (~30 Spiele: Luanti, BeamMP, DayZ, Starbound, TShock, CS 1.6/CZ, Quake III, UT99/2004, OpenRA-Familie, App-Runner-Familie, …), Wine/Proton-Unterstützung für Windows-only-Server unter Linux (Docker-Image-Preset).
- **Rust WebRCON** + weitere Query-Protokolle (FiveM, TeamSpeak ServerQuery).
- **SFTP-Implementierung**: der echte eingebettete SSH-/SFTP-Listener hinter dem Welle-1-Provider-Seam (handgerollt auf node:crypto, zero-dep wie der Rest des Panels: curve25519-sha256-KEX, ssh-ed25519-Hostkey, AES-CTR + HMAC-SHA2), Passwort-Auth gegen pro Benutzer×Server generierte Zugangsdaten, `safeJoin`-Sandbox, Rechte-Re-Check pro Operation, UI-Karte im Files-Tab; getestet gegen einen echten OpenSSH-/`sftp`-Client. Danach (Welle 3): Public-Key-Auth, Read-only-Accounts, SFTP auf Remote-Nodes.

**Welle 3 (Komfort/Enterprise):**
- Steam-Workshop- und CurseForge-Browser (analog Modrinth).
- OpenAPI-Spez + generierte API-Doku; CLI-Client.
- E-Mail-Benachrichtigungen (SMTP), Wartungsfenster.
- LDAP/OIDC-Login (optional), Rollen-Templates.
- Import-Assistenten: aus AMP-, Pterodactyl- und LinuxGSM-Installationen migrieren.
