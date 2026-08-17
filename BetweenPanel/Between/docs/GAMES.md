# Supported games

Every builtin blueprint that ships with Between, in `server/src/blueprints/builtin/`.

- **Install** — `steamcmd <appid>` (anonymous SteamCMD install), `direct` (HTTP download), or `builtin` (resolved by a dedicated installer/API built into Between).
- **Main port** — the default value of the primary port variable; secondary defaults in parentheses.
- **Stop** — either a console command written to stdin or a POSIX signal (with graceful timeout).
- **Query** — `source` (Valve A2S), `minecraft` (Java edition ping), or `none`.

| Id | Game | Install | Main port | Platforms | Stop | Query | Special notes |
|---|---|---|---|---|---|---|---|
| `7-days-to-die` | 7 Days to Die | steamcmd 294420 | 26900 | linux, win32 | SIGTERM (90s) | source | Minimal `serverconfig.xml` written at install; enable telnet there for a remote console |
| `abiotic-factor` | Abiotic Factor | steamcmd 2857200 (Windows depot forced) | 7777/udp (query 27015) | linux, win32 | SIGTERM | source | Windows-only binary (Wine/Proton works); saves in `AbioticFactor/Saved/SaveGames/Server` |
| `ark-survival-ascended` | ARK: Survival Ascended | steamcmd 2430930 (Windows depot forced) | 7777/udp (rcon 27020/tcp) | linux, win32 | rcon `DoExit` | none | Windows-only binary (Wine/Proton works); 30+ GB; EOS server list, no A2S query |
| `ark-survival-evolved` | ARK: Survival Evolved | steamcmd 376030 | 7777/udp (query 27015) | linux, win32 | SIGINT (120s) | source | Also uses game port +1; raise `ulimit -n` on Linux |
| `arma-3` | Arma 3 | steamcmd 233780 | 2302/udp (query 2303) | linux, win32 | SIGTERM | source | `server.cfg` generated at install; open UDP 2302-2306 |
| `arma-reforger` | Arma Reforger | steamcmd 1874900 | 2001/udp | linux, win32 | SIGTERM | none | Case-sensitive `config.json` generated at install; A2S/RCON opt-in via config |
| `astroneer` | Astroneer | steamcmd 728470 | 8777/udp | win32 | SIGTERM | none | Windows-only binary; `OwnerName` + `PublicIP` must be set in `AstroServerSettings.ini` |
| `avorion` | Avorion | steamcmd 565060 | 27000 (query 27003/udp, steam 27021/udp) | linux, win32 | command `/stop` | source | Launched via the `server.sh` wrapper; galaxy data + `server.ini` under `galaxies/<name>/` |
| `barotrauma` | Barotrauma | steamcmd 1026340 | 27015/udp (query 27016) | linux, win32 | SIGTERM | none | All settings in `serversettings.xml` (generated on first run) |
| `conan-exiles` | Conan Exiles | steamcmd 443030 (Windows depot forced) | 7777/udp (query 27015) | linux, win32 | SIGTERM | source | Windows-only binary (Wine/Proton works); also open game port +1; settings in `ServerSettings.ini` |
| `core-keeper` | Core Keeper | steamcmd 1963720 | none (Steam relay) | linux | SIGTERM | none | Players join via the Game ID printed to the console; no port forwarding needed |
| `counter-strike-2` | Counter-Strike 2 | steamcmd 730 | 27015 | linux, win32 | command `quit` | source | GSLT (`+sv_setsteamaccount`) required for public servers; ~35 GB install |
| `counter-strike-source` | Counter-Strike: Source | steamcmd 232330 | 27015 | linux, win32 | command `quit` | source | GSLT (app 240) recommended for public servers; config in `cstrike/cfg/server.cfg` |
| `custom-command` | Custom Server (own command) | direct (optional URL) | 27015 | linux, win32, darwin | SIGINT | none | Bring-your-own binary/script |
| `custom-steamcmd` | Custom Server (SteamCMD) | steamcmd (user app id) | 27015 | linux, win32 | SIGINT | source | Install any Steam dedicated server by app ID |
| `day-of-defeat-source` | Day of Defeat: Source | steamcmd 232290 | 27015 | linux, win32 | command `quit` | source | GSLT (app 300) recommended for public servers; config in `dod/cfg/server.cfg` |
| `demo-echo` | Demo Server (built-in) | builtin | 27777/tcp | linux, win32, darwin | command `stop` | none | Instant fake server for testing the panel |
| `dont-starve-together` | Don't Starve Together | steamcmd 343050 | 10999/udp | linux | command `c_shutdown()` | none | Requires a free Klei `cluster_token.txt`; launched via a wrapper script (binary must run from its `bin` dir) |
| `eco` | Eco | steamcmd 739590 | 3000/udp (web 3001/tcp) | linux, win32 | SIGINT | none | Web UI + admin tools on the web port; config in `Configs/*.eco` |
| `empyrion` | Empyrion - Galactic Survival | steamcmd 530870 (Windows depot forced) | 30000/udp (uses 30000-30004) | linux, win32 | SIGTERM | none | Windows-only binary (Wine/Proton works); settings in `dedicated.yaml`; no stdin console |
| `enshrouded` | Enshrouded | steamcmd 2278520 | 15636/udp (query 15637) | win32 | SIGTERM | none | Windows-only binary (Wine/Proton works); `enshrouded_server.json` generated on first start |
| `euro-truck-simulator-2` | Euro Truck Simulator 2 (Convoy) | steamcmd 1948160 | 27015/udp (query 27016) | linux, win32 | SIGINT | none | Requires `server_packages.sii`/`.dat` exported from the game client (console: `export_server_packages`) |
| `factorio` | Factorio | direct (factorio.com stable headless) | 34197/udp | linux | SIGINT | none | `.tar.xz` unpacked via a shell `tar` step; initial map created at install; factorio.com credentials only for public listing |
| `fistful-of-frags` | Fistful of Frags | steamcmd 295230 | 27015 | linux, win32 | command `quit` | source | Free game; config in `fof/cfg/server.cfg` |
| `fivem` | FiveM (FXServer) | direct (build-pinned `fx.tar.xz` URL variable) | 30120 | linux | command `quit` | none | Free Cfx.re license key required; set the artifact URL before install; RedM uses the same artifacts |
| `garrys-mod` | Garry's Mod | steamcmd 4020 | 27015 | linux, win32 | command `quit` | source | GSLT recommended; workshop addons need `-authkey`; mount CSS via `mount.cfg` |
| `half-life-2-deathmatch` | Half-Life 2: Deathmatch | steamcmd 232370 | 27015 | linux, win32 | command `quit` | source | GSLT (app 320) recommended for public servers; config in `hl2mp/cfg/server.cfg` |
| `hurtworld` | Hurtworld | steamcmd 405100 | 12871/udp (query 12881) | linux, win32 | SIGTERM | source | Server settings passed via the `-exec "host ...;queryport ..."` string |
| `icarus` | Icarus | steamcmd 2089300 (Windows depot forced) | 17777/udp (query 27015) | linux, win32 | SIGTERM | source | Windows-only binary (Wine/Proton works); settings in `ServerSettings.ini` |
| `insurgency-sandstorm` | Insurgency: Sandstorm | steamcmd 581330 | 27102/udp (query 27131) | linux, win32 | SIGTERM | source | Startup scenario travel string; config in `Game.ini` |
| `killing-floor-2` | Killing Floor 2 | steamcmd 232130 | 7777/udp (query 27015) | linux, win32 | SIGTERM | source | Linux binary lives under `Binaries/Win64/`; web admin on TCP 8080 (opt-in) |
| `left-4-dead-2` | Left 4 Dead 2 | steamcmd 222860 | 27015 | linux, win32 | command `quit` | source | Basic `server.cfg` written at install |
| `minecraft-bedrock` | Minecraft: Bedrock Edition | direct (version-pinned Mojang zip) | 19132/udp | linux, win32 | command `stop` | none | Download URL is version-pinned (variable); Mojang CDN may require a browser-like User-Agent |
| `minecraft-fabric` | Minecraft: Java Edition (Fabric) | builtin (Fabric meta API) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Minecraft EULA must be accepted; Java required |
| `minecraft-folia` | Minecraft: Java Edition (Folia) | builtin (PaperMC API) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Regionised multithreading for very large servers; most plugins incompatible; Minecraft EULA must be accepted |
| `minecraft-forge` | Minecraft: Java Edition (Forge) | direct (Forge Maven installer) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Installer runs at install time (`run.sh` generated, MC 1.17+); memory via `user_jvm_args.txt`; EULA must be accepted |
| `minecraft-neoforge` | Minecraft: Java Edition (NeoForge) | direct (NeoForged Maven installer) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | NeoForge version implies the MC version (21.1.x → 1.21.1); EULA must be accepted |
| `minecraft-paper` | Minecraft: Java Edition (Paper) | builtin (PaperMC API) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Minecraft EULA must be accepted; Java 21+ |
| `minecraft-purpur` | Minecraft: Java Edition (Purpur) | direct (PurpurMC API) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Minecraft EULA must be accepted; version must be pinned (API has no `latest` alias) |
| `minecraft-quilt` | Minecraft: Java Edition (Quilt) | direct (Quilt installer) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Runs most Fabric mods; EULA must be accepted |
| `minecraft-vanilla` | Minecraft: Java Edition (Vanilla) | builtin (Mojang manifest) | 25565/tcp | linux, win32, darwin | command `stop` | minecraft | Minecraft EULA must be accepted; Java required |
| `mordhau` | Mordhau | steamcmd 629800 | 7777/udp (query 27015, beacon 15000) | linux, win32 | SIGTERM | source | Config in `Game.ini` |
| `multi-theft-auto` | Multi Theft Auto: San Andreas | direct (multitheftauto.com latest) | 22003/udp (http 22005/tcp, query 22126/udp) | linux | command `shutdown` | none | Tarball ships no config — working `mtaserver.conf`/`acl.xml` written at install; resources zip needs the host's `unzip` |
| `mumble-server` | Mumble Server (Murmur) | direct (GitHub static binary, v1.3.4) | 64738 (tcp+udp) | linux | SIGTERM | none | 32-bit static binary; set the SuperUser password with `-supw` while stopped |
| `necesse` | Necesse | steamcmd 1169370 | 14159/udp | linux, win32 | command `stop` | none | Java server; `-localdir` keeps saves/config inside the server dir |
| `no-more-room-in-hell` | No More Room in Hell | steamcmd 317670 | 27015 | linux, win32 | command `quit` | source | Free game; config in `nmrih/cfg/server.cfg` |
| `open-mp` | open.mp (GTA: San Andreas) | direct (GitHub release, version-pinned) | 7777/udp | linux | SIGTERM | none | 32-bit binary (needs 32-bit runtime libs); SA-MP compatible; all settings in `config.json` |
| `openttd` | OpenTTD | direct (cdn.openttd.org, version-pinned) | 3979 | linux | command `quit` | none | `.tar.xz` unpacked via a shell tar step; config in `openttd.cfg` |
| `palworld` | Palworld | steamcmd 2394010 | 8211/udp | linux, win32 | SIGTERM | none | Settings + RCON in `Pal/Saved/Config/.../PalWorldSettings.ini` |
| `pavlov-vr` | Pavlov VR | steamcmd 622970 | 7777/udp (ping 8177) | linux | SIGTERM | none | Needs `steamclient.so` reachable + GLIBC 2.27+; map rotation in `Game.ini`; custom rcon (not Source RCON) |
| `project-zomboid` | Project Zomboid | steamcmd 380870 | 16261/udp (direct 16262) | linux, win32 | command `quit` | source | `-adminpassword` avoids the first-boot console prompt; data defaults to `~/Zomboid` |
| `risk-of-rain-2` | Risk of Rain 2 | steamcmd 1180760 | 27015/udp | win32 | SIGTERM | source | Windows-only binary; may need Steam client libraries on the host |
| `rust` | Rust | steamcmd 258550 | 28015/udp (rcon 28016/tcp) | linux, win32 | SIGINT (60s) | source | Forced map wipes on the first Thursday of each month; 10+ GB install |
| `satisfactory` | Satisfactory | steamcmd 1690800 | 7777 (udp game + tcp API) | linux, win32 | SIGINT | none | Claim the server via the game client or HTTPS API after first start |
| `scp-secret-laboratory` | SCP: Secret Laboratory | steamcmd 996560 | 7777 | linux, win32 | command `stop` | none | `--acceptEULA` accepts the EULA; Northwood verification key needed for public listing |
| `sons-of-the-forest` | Sons of the Forest | steamcmd 2465200 (Windows depot forced) | 8766/udp (27016, 9700) | linux, win32 | SIGTERM | none | Server binary is a Windows exe — needs Wine/Proton on Linux; config in `userdata/dedicatedserver.cfg` |
| `space-engineers` | Space Engineers | steamcmd 298740 | 27016/udp | win32 | SIGTERM | source | Windows-only; instance config `SpaceEngineers-Dedicated.cfg`; .NET Framework 4.8 |
| `squad` | Squad | steamcmd 403240 | 7787/udp (query 27165) | linux, win32 | SIGTERM | source | Config in `SquadGame/ServerConfig/`; RCON on TCP 21114 |
| `stationeers` | Stationeers | steamcmd 600760 | 27016/udp | linux, win32 | SIGTERM | none | Configure via settings file or launch options (`-loadlatest`) |
| `sven-coop` | Sven Co-op | steamcmd 276060 | 27015 | linux, win32 | command `quit` | source | Free game; GoldSrc (HLDS) — legacy UDP rcon, panel RCON does not apply |
| `team-fortress-2` | Team Fortress 2 | steamcmd 232250 | 27015 | linux, win32 | command `quit` | source | GSLT recommended for public servers; config in `tf/cfg/server.cfg` |
| `teamspeak3` | TeamSpeak 3 Server | direct (files.teamspeak-services.com, version-pinned) | 9987/udp (query 10011/tcp, files 30033/tcp) | linux | SIGTERM | none | License accepted via variable; serveradmin token printed to the console on FIRST start |
| `terraria` | Terraria | direct (terraria.org zip, v1.4.4.9) | 7777/tcp | linux | command `exit` | none | Zip nests `1449/Linux/` — binaries copied to server root at install; `exit` saves the world |
| `the-forest` | The Forest | steamcmd 556450 | 27015/udp (27016, 8766) | win32 | SIGTERM | source | Windows-only binary (Wine works); config via `-configfilepath` |
| `the-isle-evrima` | The Isle (Evrima) | steamcmd 412680 (beta `evrima`) | 7777/udp (query 27015) | linux, win32 | SIGTERM | source | EVRIMA beta branch pinned at install; config in `TheIsle/Saved/Config/LinuxServer/Game.ini` |
| `tmodloader` | Terraria (tModLoader) | direct (GitHub latest zip) | 7777/tcp | linux | command `exit` | none | Launch script downloads a private .NET runtime on first start (needs curl/wget); clients need the same tML version |
| `unturned` | Unturned | steamcmd 1110390 | 27015/udp (query 27016) | linux, win32 | command `shutdown` | source | Settings in `Servers/<name>/Server/Commands.dat`; query is always game port +1 |
| `v-rising` | V Rising | steamcmd 1829350 | 9876/udp (query 9877) | win32 | SIGTERM | source | Windows-only binary (Wine/Proton works); settings in `save-data\Settings\ServerHostSettings.json` |
| `valheim` | Valheim | steamcmd 896660 | 2456/udp (query 2457) | linux, win32 | SIGINT | source | Password must be ≥5 chars; query port is always game port +1; worlds default to `~/.config` unless `-savedir` is added |
| `velocity` | Velocity (Minecraft proxy) | builtin (PaperMC API) | 25577/tcp | linux, win32, darwin | command `shutdown` | none | `velocity.toml` generated on first start; Java required |
| `vintage-story` | Vintage Story | direct (cdn.vintagestory.at, version-pinned) | 42420/tcp | linux | command `/stop` | none | Bundled .NET runtime; all data under `./data` via `--dataPath` |
| `xonotic` | Xonotic | direct (dl.xonotic.org zip, version-pinned) | 26000/udp | linux | command `quit` | none | ~1 GB zip nests everything under `Xonotic/` (copied to the root at install); config in `data/server.cfg` |
| `zombie-panic-source` | Zombie Panic! Source | steamcmd 17505 | 27015 | linux, win32 | command `quit` | source | Free game; config in `zps/cfg/server.cfg` |

Notes that apply to several blueprints:

- All SteamCMD installs use anonymous login; Between downloads and manages SteamCMD automatically.
- For games listed as linux+win32 whose start command is the Linux binary/script, Windows hosts should set the per-server start command override to the `.exe` equivalent named in the blueprint's notes.
- Blueprints exclude `steamapps/**` (SteamCMD manifests) from backups; game content is re-downloadable via re-install.
