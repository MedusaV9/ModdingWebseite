import { test } from 'node:test'
import assert from 'node:assert/strict'
import { convertEgg } from '../../src/lib/eggs.ts'
import { validateBlueprint } from '../../src/blueprints/schema.ts'
import type { Blueprint, BlueprintVariable, InstallStep } from '../../src/types.ts'

function variable(bp: Blueprint, key: string): BlueprintVariable {
  const v = bp.variables.find((entry) => entry.key === key)
  assert.ok(v, `variable ${key} missing (got ${bp.variables.map((entry) => entry.key).join(', ')})`)
  return v!
}

function dockerScript(bp: Blueprint): Extract<InstallStep, { type: 'docker-script' }> {
  const step = bp.install.find((s) => s.type === 'docker-script')
  assert.ok(step, 'docker-script install step missing')
  return step as Extract<InstallStep, { type: 'docker-script' }>
}

// ---------------------------------------------------------------------------
// Realistic PTDL_v2 Paper-like egg (double-encoded config strings, builtin
// placeholders, numeric/boolean/in: rules, install script, docker image map)
// ---------------------------------------------------------------------------
const PAPER_EGG = {
  _comment: 'DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO',
  meta: { version: 'PTDL_v2', update_url: null },
  exported_at: '2024-05-01T12:00:00+00:00',
  name: 'Paper',
  author: 'parker@pterodactyl.io',
  description: 'High performance Spigot fork that aims to fix gameplay and mechanics inconsistencies.',
  features: ['eula', 'java_version', 'pid_limit'],
  docker_images: {
    'Java 21': 'ghcr.io/pterodactyl/yolks:java_21',
    'Java 17': 'ghcr.io/pterodactyl/yolks:java_17',
  },
  file_denylist: [],
  startup:
    'java -Xms128M -Xmx{{SERVER_MEMORY}}M -Dterminal.jline=false -jar {{SERVER_JARFILE}} --port {{SERVER_PORT}}',
  config: {
    files:
      '{\r\n    "server.properties": {\r\n        "parser": "properties",\r\n        "find": {\r\n            "server-ip": "0.0.0.0",\r\n            "server-port": "{{server.build.default.port}}",\r\n            "query.port": "{{server.build.default.port}}",\r\n            "motd": "{{env.MOTD}}"\r\n        }\r\n    },\r\n    "config/settings.yml": {\r\n        "parser": "yaml",\r\n        "find": {\r\n            "web.port": "{{server.build.default.port}}"\r\n        }\r\n    }\r\n}',
    startup: '{\r\n    "done": ")! For help, type "\r\n}',
    logs: '{}',
    stop: 'stop',
  },
  scripts: {
    installation: {
      script:
        '#!/bin/bash\r\n# Paper Installation Script\r\napt update\r\napt install -y curl jq\r\ncd /mnt/server\r\ncurl -o server.jar "$DOWNLOAD_URL"\r\necho "install complete"\r\n',
      container: 'ghcr.io/pterodactyl/installers:debian',
      entrypoint: 'bash',
    },
  },
  variables: [
    {
      name: 'Minecraft Version',
      description: 'The version of Minecraft to download.',
      env_variable: 'MINECRAFT_VERSION',
      default_value: 'latest',
      user_viewable: true,
      user_editable: true,
      rules: 'nullable|string|max:20',
      field_type: 'text',
    },
    {
      name: 'Server Jar File',
      description: 'The name of the server jarfile.',
      env_variable: 'SERVER_JARFILE',
      default_value: 'server.jar',
      user_viewable: true,
      user_editable: true,
      rules: 'required|regex:/^([\\w\\d._-]+)(\\.jar)$/',
      field_type: 'text',
    },
    {
      name: 'Build Type',
      description: 'Which project to download.',
      env_variable: 'BUILD_TYPE',
      default_value: 'paper',
      user_viewable: true,
      user_editable: true,
      rules: 'required|string|in:paper,folia',
      field_type: 'text',
    },
    {
      name: 'Use Aikar Flags',
      description: 'Optimized JVM flags.',
      env_variable: 'USE_AIKAR',
      default_value: '1',
      user_viewable: true,
      user_editable: false,
      rules: 'required|boolean',
      field_type: 'text',
    },
    {
      name: 'Max Players',
      description: 'Maximum player slots.',
      env_variable: 'MAX_PLAYERS',
      default_value: '20',
      user_viewable: true,
      user_editable: true,
      rules: 'required|numeric|between:1,100',
      field_type: 'text',
    },
    {
      name: 'MOTD',
      description: 'Server list message.',
      env_variable: 'MOTD',
      default_value: 'A Paper server',
      user_viewable: true,
      user_editable: true,
      rules: 'required|string|max:60',
      field_type: 'text',
    },
  ],
}

test('PTDL_v2 egg: full conversion passes validation', () => {
  const { blueprint, warnings } = convertEgg(PAPER_EGG)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.ok(Array.isArray(warnings))
  assert.equal(blueprint.name, 'Paper')
  assert.equal(blueprint.category, 'custom')
  assert.deepEqual(blueprint.platforms, ['linux'])
  assert.match(blueprint.id, /^paper-egg-[0-9a-f]{4}$/)
  assert.match(blueprint.notes ?? '', /Pterodactyl egg/)
  assert.match(blueprint.notes ?? '', /parker@pterodactyl\.io/)
  assert.equal(blueprint.custom, undefined, 'custom flag is set by the registry, not the importer')
})

test('PTDL_v2 egg: variables map with rules, defaults and advanced', () => {
  const { blueprint } = convertEgg(PAPER_EGG)

  const version = variable(blueprint, 'MINECRAFT_VERSION')
  assert.equal(version.type, 'string')
  assert.equal(version.default, 'latest')
  assert.equal(version.required, undefined)

  const jarfile = variable(blueprint, 'SERVER_JARFILE')
  assert.equal(jarfile.type, 'string')
  assert.equal(jarfile.required, true)
  assert.equal(jarfile.default, 'server.jar')

  const buildType = variable(blueprint, 'BUILD_TYPE')
  assert.equal(buildType.type, 'enum')
  assert.deepEqual(buildType.options?.map((o) => o.value), ['paper', 'folia'])
  assert.equal(buildType.default, 'paper')

  const aikar = variable(blueprint, 'USE_AIKAR')
  assert.equal(aikar.type, 'boolean')
  assert.equal(aikar.default, true, '"1" parses as true')
  assert.equal(aikar.advanced, true, 'user_editable: false maps to advanced')

  const maxPlayers = variable(blueprint, 'MAX_PLAYERS')
  assert.equal(maxPlayers.type, 'number')
  assert.equal(maxPlayers.default, 20)
  assert.equal(maxPlayers.min, 1)
  assert.equal(maxPlayers.max, 100)
})

test('PTDL_v2 egg: builtin placeholders become variables + ports', () => {
  const { blueprint } = convertEgg(PAPER_EGG)

  const port = variable(blueprint, 'SERVER_PORT')
  assert.equal(port.type, 'number')
  assert.equal(port.default, 25565)
  assert.equal(port.isPort, true)

  const memory = variable(blueprint, 'SERVER_MEMORY')
  assert.equal(memory.type, 'number')
  assert.equal(memory.default, 2048)
  assert.equal(memory.min, 128)

  assert.deepEqual(blueprint.ports, [{ name: 'game', variable: 'SERVER_PORT', protocol: 'both' }])
})

test('PTDL_v2 egg: docker image map is preserved', () => {
  const { blueprint } = convertEgg(PAPER_EGG)
  assert.equal(blueprint.docker?.image, 'ghcr.io/pterodactyl/yolks:java_21')
  assert.deepEqual(blueprint.docker?.images, [
    { label: 'Java 21', image: 'ghcr.io/pterodactyl/yolks:java_21' },
    { label: 'Java 17', image: 'ghcr.io/pterodactyl/yolks:java_17' },
  ])
})

test('PTDL_v2 egg: install script becomes a docker-script step with CRLF normalized', () => {
  const { blueprint } = convertEgg(PAPER_EGG)
  const step = dockerScript(blueprint)
  assert.equal(step.image, 'ghcr.io/pterodactyl/installers:debian')
  assert.equal(step.entrypoint, 'bash')
  assert.ok(step.script.includes('cd /mnt/server'))
  assert.ok(!step.script.includes('\r'), 'CRLF must be normalized to LF')
})

test('PTDL_v2 egg: double-encoded config.startup becomes an escaped readyRegex', () => {
  const { blueprint } = convertEgg(PAPER_EGG)
  assert.equal(blueprint.readyRegex, '\\)! For help, type ')
  const re = new RegExp(blueprint.readyRegex!)
  assert.ok(re.test('[12:00:00 INFO]: Done (2.512s)! For help, type "help"'))
  assert.ok(!re.test('Starting minecraft server'))
})

test('PTDL_v2 egg: config.files map to inverse mappings; yaml and duplicates are skipped', () => {
  const { blueprint, warnings } = convertEgg(PAPER_EGG)
  assert.equal(blueprint.configFiles?.length, 1)
  const spec = blueprint.configFiles![0]
  assert.equal(spec.path, 'server.properties')
  assert.equal(spec.format, 'properties')
  assert.deepEqual(spec.mappings, { SERVER_PORT: 'server-port', MOTD: 'motd' })
  assert.ok(warnings.some((w) => w.includes('yaml')), 'yaml parser skipped with warning')
  assert.ok(warnings.some((w) => w.includes('query.port')), 'duplicate port mapping skipped with warning')
  assert.ok(warnings.some((w) => w.includes('server-ip')), 'literal find value skipped with warning')
})

test('PTDL_v2 egg: stop string becomes a stop command', () => {
  const { blueprint } = convertEgg(PAPER_EGG)
  assert.deepEqual(blueprint.stop, { type: 'command', command: 'stop' })
})

// ---------------------------------------------------------------------------
// PTDL_v1 egg: single image, ^C stop, config objects instead of strings
// ---------------------------------------------------------------------------
const V1_EGG = {
  meta: { version: 'PTDL_v1' },
  name: 'Mumble Server',
  author: 'support@pterodactyl.io',
  description: 'Low-latency voice chat server.',
  image: 'quay.io/pterodactyl/core:glibc',
  startup: './murmur.x86 -fg -ini murmur.ini',
  config: {
    files: {
      'murmur.ini': {
        parser: 'ini',
        find: { port: '{{server.build.default.port}}', users: '{{server.build.env.MAX_USERS}}' },
      },
    },
    startup: { done: 'Server listening on 0.0.0.0:' },
    logs: {},
    stop: '^C',
  },
  scripts: {
    installation: {
      script: '#!/bin/ash\napk add curl\ncd /mnt/server\ncurl -L -o murmur.tar.bz2 "$URL"\n',
      container: 'alpine:3.4',
      entrypoint: 'ash',
    },
  },
  variables: [
    {
      name: 'Maximum Users',
      description: 'Slots.',
      env_variable: 'MAX_USERS',
      default_value: '100',
      user_viewable: true,
      user_editable: true,
      rules: 'required|numeric|max:1024',
    },
  ],
}

test('PTDL_v1 egg: single image, ^C stop → SIGINT, dotted done marker escaped', () => {
  const { blueprint, warnings } = convertEgg(V1_EGG)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.deepEqual(blueprint.stop, { type: 'signal', signal: 'SIGINT' })
  assert.equal(blueprint.docker?.image, 'quay.io/pterodactyl/core:glibc')
  assert.equal(blueprint.docker?.images, undefined, 'single image needs no alternatives list')
  assert.equal(blueprint.readyRegex, 'Server listening on 0\\.0\\.0\\.0:')
  const step = dockerScript(blueprint)
  assert.equal(step.image, 'alpine:3.4')
  assert.equal(step.entrypoint, 'ash')
  // v1-style object config (not double-encoded) works too. This egg has no
  // port variable, so the port placeholder is skipped with a warning while
  // the {{server.build.env.MAX_USERS}} mapping survives.
  assert.deepEqual(blueprint.configFiles, [{ path: 'murmur.ini', format: 'ini', mappings: { MAX_USERS: 'users' } }])
  assert.ok(warnings.some((w) => w.includes('server.build.default.port')))
  const maxUsers = variable(blueprint, 'MAX_USERS')
  assert.equal(maxUsers.type, 'number')
  assert.equal(maxUsers.default, 100)
  assert.equal(maxUsers.max, 1024)
})

test('PTDL_v1 egg with ^^C also maps to SIGINT', () => {
  const { blueprint } = convertEgg({ ...V1_EGG, config: { ...V1_EGG.config, stop: '^^C' } })
  assert.deepEqual(blueprint.stop, { type: 'signal', signal: 'SIGINT' })
})

test('config port placeholder is skipped when no port variable exists', () => {
  const egg = {
    name: 'No Port',
    startup: './run.sh',
    config: {
      files: { 'a.properties': { parser: 'properties', find: { port: '{{server.build.default.port}}' } } },
      stop: 'quit',
    },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.equal(blueprint.configFiles, undefined)
  assert.ok(warnings.some((w) => w.includes('server.build.default.port')))
})

// ---------------------------------------------------------------------------
// Hostile / broken input
// ---------------------------------------------------------------------------
test('non-egg input throws with a clear message', () => {
  assert.throws(() => convertEgg(42), /not a Pterodactyl egg/)
  assert.throws(() => convertEgg(null), /not a Pterodactyl egg/)
  assert.throws(() => convertEgg([1, 2]), /not a Pterodactyl egg/)
  assert.throws(() => convertEgg({}), /missing "name"/)
  assert.throws(() => convertEgg({ name: 'X' }), /missing "startup"/)
  assert.throws(() => convertEgg({ name: 'X', startup: '   ' }), /missing "startup"/)
})

test('invalid env variable names are sanitized, warned about and references rewritten', () => {
  const egg = {
    name: 'Weird Vars',
    startup: './run --key {{my-weird.var}} --token {{2FA_TOKEN}}',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [
      { name: 'Weird', env_variable: 'my-weird.var', default_value: 'x', rules: 'required|string' },
      { name: 'Token', env_variable: '2FA_TOKEN', default_value: '', rules: 'nullable|string' },
    ],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const weird = variable(blueprint, 'MY_WEIRD_VAR')
  assert.equal(weird.default, 'x')
  variable(blueprint, 'V_2FA_TOKEN')
  assert.ok(blueprint.startCommand.includes('{{MY_WEIRD_VAR}}'))
  assert.ok(blueprint.startCommand.includes('{{V_2FA_TOKEN}}'))
  assert.ok(warnings.some((w) => w.includes('my-weird.var')))
  assert.ok(warnings.some((w) => w.includes('2FA_TOKEN')))
})

test('duplicate env variables after sanitization stay unique', () => {
  const egg = {
    name: 'Dupes',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [
      { name: 'A', env_variable: 'MY VAR', default_value: 'a', rules: 'string' },
      { name: 'B', env_variable: 'MY_VAR', default_value: 'b', rules: 'string' },
    ],
  }
  const { blueprint } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const keys = blueprint.variables.map((v) => v.key)
  assert.equal(new Set(keys).size, keys.length, 'no duplicate keys')
  assert.ok(keys.includes('MY_VAR'))
  assert.ok(keys.includes('MY_VAR_2'))
})

test('undeclared startup variables are auto-added with a warning', () => {
  const egg = {
    name: 'Missing Var',
    startup: './run --secret {{SOME_UNDECLARED}}',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const added = variable(blueprint, 'SOME_UNDECLARED')
  assert.equal(added.type, 'string')
  assert.equal(added.default, '')
  assert.ok(warnings.some((w) => w.includes('SOME_UNDECLARED')))
})

test('P_SERVER_UUID/P_SERVER_LOCATION and TZ/SERVER_IP builtins are handled', () => {
  const egg = {
    name: 'Builtins',
    startup: './run --uuid {{P_SERVER_UUID}} --loc {{P_SERVER_LOCATION}} --ip {{SERVER_IP}} --tz {{TZ}}',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.ok(blueprint.startCommand.includes('{{SERVER_ID}}'), 'P_SERVER_UUID becomes the SERVER_ID builtin')
  assert.ok(!blueprint.startCommand.includes('P_SERVER_LOCATION'))
  assert.ok(warnings.some((w) => w.includes('P_SERVER_LOCATION')))
  const ip = variable(blueprint, 'SERVER_IP')
  assert.equal(ip.default, '0.0.0.0')
  assert.equal(ip.advanced, true)
  const tz = variable(blueprint, 'TZ')
  assert.equal(tz.default, 'UTC')
  assert.equal(tz.advanced, true)
  assert.equal(blueprint.variables.some((v) => v.key === 'SERVER_ID'), false, 'builtins are not declared as variables')
})

test('numeric default that does not parse falls back to 0 with a warning', () => {
  const egg = {
    name: 'Bad Number',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [{ name: 'Count', env_variable: 'COUNT', default_value: 'many', rules: 'required|numeric' }],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.equal(variable(blueprint, 'COUNT').default, 0)
  assert.ok(warnings.some((w) => w.includes('COUNT')))
})

test('enum default outside its options is added as an option with a warning', () => {
  const egg = {
    name: 'Enum Default',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [{ name: 'Mode', env_variable: 'MODE', default_value: 'custom', rules: 'required|string|in:easy,hard' }],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const mode = variable(blueprint, 'MODE')
  assert.deepEqual(mode.options?.map((o) => o.value), ['easy', 'hard', 'custom'])
  assert.equal(mode.default, 'custom')
  assert.ok(warnings.some((w) => w.includes('MODE')))
})

test('array-style rules are accepted', () => {
  const egg = {
    name: 'Array Rules',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [{ name: 'Port', env_variable: 'GAME_PORT', default_value: '7777', rules: ['required', 'integer', 'between:1024,65535'] }],
  }
  const { blueprint } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const port = variable(blueprint, 'GAME_PORT')
  assert.equal(port.type, 'number')
  assert.equal(port.default, 7777)
  assert.equal(port.min, 1024)
  assert.equal(port.max, 65535)
})

test('missing install container falls back with a warning; empty script means no install steps', () => {
  const withScript = {
    name: 'No Container',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '#!/bin/bash\necho hi', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(withScript)
  assert.deepEqual(validateBlueprint(blueprint), [])
  const step = dockerScript(blueprint)
  assert.equal(step.image, 'debian:bookworm-slim')
  assert.equal(step.entrypoint, 'bash')
  assert.ok(warnings.some((w) => w.includes('debian:bookworm-slim')))

  const noScript = { ...withScript, scripts: { installation: { script: '   \n ', container: 'alpine:3', entrypoint: 'ash' } } }
  assert.deepEqual(convertEgg(noScript).blueprint.install, [])
})

test('invalid docker images are skipped with warnings', () => {
  const egg = {
    name: 'Bad Images',
    startup: './run',
    docker_images: { OK: 'alpine:3', Bad: 'not valid!!', Worse: 42 },
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.equal(blueprint.docker?.image, 'alpine:3')
  assert.equal(blueprint.docker?.images, undefined)
  assert.equal(warnings.filter((w) => w.includes('not a valid image reference')).length, 2)
})

test('unparseable double-encoded config strings warn instead of failing', () => {
  const egg = {
    name: 'Broken Config',
    startup: './run',
    config: { files: '{not json', startup: 'also not json', stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.equal(blueprint.configFiles, undefined)
  assert.equal(blueprint.readyRegex, undefined)
  assert.ok(warnings.some((w) => w.includes('config.files')))
  assert.ok(warnings.some((w) => w.includes('config.startup')))
})

test('missing stop falls back to SIGTERM with a warning', () => {
  const egg = {
    name: 'No Stop',
    startup: './run',
    config: {},
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.deepEqual(blueprint.stop, { type: 'signal', signal: 'SIGTERM' })
  assert.ok(warnings.some((w) => w.includes('SIGTERM')))
})

test('multiple done markers join into one alternation regex', () => {
  const egg = {
    name: 'Multi Done',
    startup: './run',
    config: { startup: { done: ['Listening on (port)', 'Ready.'] }, stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.equal(blueprint.readyRegex, 'Listening on \\(port\\)|Ready\\.')
  const re = new RegExp(blueprint.readyRegex!)
  assert.ok(re.test('Listening on (port)'))
  assert.ok(re.test('Ready.'))
  assert.ok(!re.test('ReadyX'))
})

test('ready markers are bounded: oversized and surplus markers are dropped with a warning', () => {
  const egg = {
    name: 'Marker Flood',
    startup: './run',
    config: {
      startup: { done: ['Ready.', 'x'.repeat(10_000), ...Array.from({ length: 30 }, (_, i) => `marker-${i}`)] },
      stop: 'quit',
    },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const { blueprint, warnings } = convertEgg(egg)
  assert.deepEqual(validateBlueprint(blueprint), [])
  assert.ok(blueprint.readyRegex!.length < 1000, 'readyRegex stays small (matched against every console line)')
  assert.ok(!blueprint.readyRegex!.includes('xxxxx'), 'the 10k marker is dropped')
  assert.ok(new RegExp(blueprint.readyRegex!).test('Ready.'), 'surviving markers still work')
  assert.ok(warnings.some((w) => w.includes('ready markers')), 'dropping markers is reported')
})

test('generated ids are unique, slug-capped and always valid', () => {
  const egg = {
    name: 'An Extremely Long Egg Name That Goes On And On And Certainly Exceeds Forty Characters!!!',
    startup: './run',
    config: { stop: 'quit' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const a = convertEgg(egg).blueprint
  const b = convertEgg(egg).blueprint
  assert.deepEqual(validateBlueprint(a), [])
  assert.notEqual(a.id, b.id)
  assert.ok(a.id.length <= 64)
  assert.match(a.id, /^[a-z0-9][a-z0-9-]{1,63}$/)
})
