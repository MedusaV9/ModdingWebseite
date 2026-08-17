# Generic instance templates (drop-in files)

Between can run **any** game server from a declarative template file — the same idea as AMP's Generic module templates ([CubeCoders/AMPTemplates](https://github.com/CubeCoders/AMPTemplates)), but in plain JSON or YAML.

A template describes *how to install, start, stop, configure and monitor* a game server. Between's built-in games, custom blueprints created in the UI, imported Pterodactyl eggs and drop-in template files all share **one format** (the blueprint schema) — so everything below also documents what the blueprint editor validates.

## Drop-in directory

Put `*.json`, `*.yaml` or `*.yml` files into:

```
<data dir>/templates/          # default: Between/data/templates/
```

- Templates load at panel boot and via **Blueprints → Rescan templates** (or `POST /api/templates/rescan`, admin).
- A broken file never blocks the others — errors are reported per file (`GET /api/templates`, boot log, Blueprints page).
- File templates are **read-only in the API/UI**: edit the file and rescan. Deleting the file (plus rescan) removes the template.
- Ids must not collide with builtin or custom blueprints.
- Ready-made examples live in [`Between/templates/`](../templates/) — ten popular games (Minecraft Java/Bedrock, Valheim, Palworld, Rust, ARK, Terraria, Satisfactory, Factorio, 7 Days to Die) exported from the curated builtins. Copy any of them into the drop-in directory and adapt.
- Export any existing blueprint as a starting point:

```bash
cd Between/server
npx tsx scripts/export-template.ts valheim --id my-valheim -o /path/to/data/templates/my-valheim.yaml
npx tsx scripts/export-template.ts factorio --json          # JSON to stdout
```

## Format reference

Minimal working example (YAML — JSON works identically):

```yaml
id: my-game                       # ^[a-z0-9][a-z0-9-]{1,63}$ — unique
name: My Game
category: steam                   # minecraft|steam|sandbox|survival|shooter|simulation|voice|custom|other
description: What this server is.
platforms: [linux]                # linux | win32 | darwin

install:                          # steps run in order (see below)
  - type: steamcmd
    appId: 123456

startCommand: ./run_server -port {{GAME_PORT}} -name "{{SERVER_NAME}}"

stop:                             # how to stop gracefully
  type: command                   # command | signal | rcon
  command: quit
  timeoutS: 30

variables:
  - key: SERVER_NAME              # ^[A-Z][A-Z0-9_]{0,63}$
    label: Server name
    type: string                  # string|number|boolean|enum|password
    default: My Server
  - key: GAME_PORT
    label: Game port
    type: number
    default: 7777
    isPort: true                  # participates in port-conflict checks

ports:
  - { name: game, variable: GAME_PORT, protocol: udp }   # tcp|udp|both
```

### Install steps (`install`)

| Step | Fields | Meaning |
|---|---|---|
| `steamcmd` | `appId`, `betaBranch?`, `validate?`, `platformOverride?`, `requiresLogin?` | Install/update a Steam app (anonymous by default; `requiresLogin` uses the panel Steam account) |
| `download` | `url`, `target`, `extract?`, `sha256?` | Direct download with progress; zip/tar.gz auto-extract |
| `paper` / `vanilla-minecraft` / `fabric` | `versionVar?`, `target?` | Version resolvers (PaperMC Fill v3, Mojang piston-meta, Fabric) |
| `writeFile` | `path`, `content` | Write a file (eula.txt, start scripts, configs) |
| `mkdir` | `path` | Create a directory |
| `command` | `command` | Run a shell command inside the server dir |
| `docker-script` | `image`, `script`, `entrypoint?` | Run an install script in a throwaway container (Pterodactyl-egg convention; needs Docker) |

**Updates:** SteamCMD games update via the *Run Steam update* action or the per-server *auto-update before start* toggle; resolver/download-based games update by reinstalling (files are kept unless wiped). All install steps re-run on reinstall.

### Start, stop, variables

- `startCommand` is tokenized shell-words style; `{{VAR}}` placeholders are replaced with variable values (quote them when values may contain spaces). Built-ins always available: `{{SERVER_DIR}}`, `{{SERVER_NAME}}`, `{{SERVER_ID}}`, `{{STEAMCMD_DIR}}`, `{{PLATFORM}}`.
- Every variable is exported to the process **environment** as well, so `LD_LIBRARY_PATH: ./linux64` style variables work without shell wrappers.
- `stop`: `command` writes to stdin, `signal` sends SIGINT/SIGTERM to the process tree, `rcon` sends an RCON command (falls back to SIGTERM). `timeoutS` before escalation.
- Variable types drive the create-wizard UI (`enum` needs `options`, `number` supports `min`/`max`, `password` renders masked, `advanced: true` folds into the advanced section, `pattern` adds regex validation).

### Optional blocks

```yaml
docker:                           # docker-runtime defaults (optional feature)
  image: eclipse-temurin:21-jre
  images:                         # alternatives offered in the UI
    - { label: Java 25, image: eclipse-temurin:25-jre }

query:                            # live player counts / version
  type: source                    # minecraft | source | none
  portVariable: QUERY_PORT

rcon:                             # console transport for stdin-deaf games
  portVariable: RCON_PORT
  passwordVariable: RCON_PASSWORD

configFiles:                      # live config editor + variable sync
  - path: server.properties
    format: properties            # properties|ini|json|keyvalue|yaml|toml|raw
    mappings:                     # blueprint variable -> config key (dot paths for json)
      SERVER_NAME: server-name

mods:                             # Modrinth one-click installs
  platform: modrinth
  loader: paper                   # paper | fabric | velocity
  dir: plugins

playerActions:                    # per-player buttons in the Players card
  - { key: kick, label: Kick, command: "kick {{PLAYER}}" }

readyRegex: "Done \\([0-9.]+s\\)!"   # console line that flips starting -> running
backupExcludes: ["steamapps/**"]     # default backup exclusions
notes: Free-form operator notes shown in the UI.
```

## YAML subset

Template YAML is parsed by a deliberately small, dependency-free parser (`server/src/lib/yamldoc.ts`). Supported: nested block mappings/sequences, inline `- key: value` items, quoted scalars, block scalars (`|`, `|-`, `|+`, `>`, `>-` — comment/blank lines inside them stay literal), one-line flow collections (`[a, b]`, `{k: v}`), comments, a single leading `---`. Not supported (clear error): anchors/aliases/tags, multi-document files, tab indentation. Leading-zero numerals (`007`) stay strings on purpose. When in doubt, use JSON — the formats are 1:1 interchangeable.

## Mapping from AMP Generic templates

| AMP `.kvp` concept | Template equivalent |
|---|---|
| `App.UpdateSources` (SteamCMD/GithubRelease/FetchURL) | `install` steps (`steamcmd`, `download`) |
| `App.CommandLineArgs` + `{{Setting}}` | `startCommand` + `{{VAR}}` |
| `App.Ports` / port settings | `variables` with `isPort` + `ports` |
| `App.EnvironmentVariables` | variables (all exported to the environment) |
| Config manifests (`*config.json`) | `configFiles` with `mappings` |
| `App.ApplicationReadyMode` / console regex | `readyRegex` |
| RCON / telnet console | `rcon` block (Source RCON) |
| `Meta.OS` | `platforms` |
| `Meta.SpecificDockerImage` | `docker.image` |
