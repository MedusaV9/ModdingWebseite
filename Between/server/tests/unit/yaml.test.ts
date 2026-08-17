import { test } from 'node:test'
import assert from 'node:assert/strict'
import { getYamlValue, applyYaml, parseYaml } from '../../src/lib/yaml.ts'

const BUKKIT_STYLE = `# This is the main configuration file for Bukkit.
settings:
  allow-end: true
  warn-on-overload: true   # spams the console when lagging
  connection-throttle: 4000
  query-plugins: true
spawn-limits:
  monsters: 70
  animals: 10
aliases: now-in-commands.yml
worlds:
  - world
  - world_nether
`

test('getYamlValue reads nested scalars', () => {
  assert.equal(getYamlValue(BUKKIT_STYLE, 'settings.allow-end'), 'true')
  assert.equal(getYamlValue(BUKKIT_STYLE, 'settings.connection-throttle'), '4000')
  assert.equal(getYamlValue(BUKKIT_STYLE, 'spawn-limits.monsters'), '70')
  assert.equal(getYamlValue(BUKKIT_STYLE, 'aliases'), 'now-in-commands.yml')
})

test('getYamlValue strips trailing comments and quotes', () => {
  assert.equal(getYamlValue(BUKKIT_STYLE, 'settings.warn-on-overload'), 'true')
  const doc = 'a:\n  b: "quoted: value"  # comment\n  c: \'single\'\n'
  assert.equal(getYamlValue(doc, 'a.b'), 'quoted: value')
  assert.equal(getYamlValue(doc, 'a.c'), 'single')
})

test('getYamlValue returns undefined for missing paths', () => {
  assert.equal(getYamlValue(BUKKIT_STYLE, 'settings.nope'), undefined)
  assert.equal(getYamlValue(BUKKIT_STYLE, 'nope.deep.deeper'), undefined)
  // a parent mapping is not a scalar — but must not crash either
  assert.equal(getYamlValue(BUKKIT_STYLE, 'settings'), '')
})

test('applyYaml updates an existing nested scalar in place', () => {
  const next = applyYaml(BUKKIT_STYLE, { 'settings.connection-throttle': '8000' })
  assert.match(next, /  connection-throttle: 8000\n/)
  // everything else is untouched, comments included
  assert.match(next, /# This is the main configuration file for Bukkit\./)
  assert.match(next, /  allow-end: true\n/)
  assert.match(next, /  - world_nether\n/)
})

test('applyYaml preserves trailing comments on the edited line', () => {
  const next = applyYaml(BUKKIT_STYLE, { 'settings.warn-on-overload': 'false' })
  assert.match(next, /  warn-on-overload: false   # spams the console when lagging\n/)
})

test('applyYaml inserts a missing leaf after the last sibling of its parent', () => {
  const next = applyYaml(BUKKIT_STYLE, { 'settings.shutdown-message': 'Server closed' })
  const lines = next.split('\n')
  const at = lines.indexOf('  shutdown-message: Server closed')
  assert.ok(at > 0, 'new key inserted')
  assert.equal(lines[at - 1], '  query-plugins: true', 'inserted after the last settings child')
  assert.equal(lines[at + 1], 'spawn-limits:', 'before the next top-level key')
})

test('applyYaml creates missing nested paths with correct indentation', () => {
  const next = applyYaml(BUKKIT_STYLE, { 'chunk-gc.period-in-ticks': '600' })
  assert.match(next, /\nchunk-gc:\n  period-in-ticks: 600/)
})

test('applyYaml derives the indentation step from existing siblings', () => {
  const doc = 'root:\n    child: 1\n'
  const next = applyYaml(doc, { 'root.other.deep': 'x' })
  assert.equal(next, 'root:\n    child: 1\n    other:\n        deep: x\n')
})

test('applyYaml quotes only when needed', () => {
  const doc = 'a: 1\n'
  const next = applyYaml(doc, {
    plain: 'hello world',
    colon: 'a: b',
    hash: 'five # six',
    bool: 'true',
    num: '123',
    numString: '1.2.3',
    yes: 'yes',
    empty: '',
    spaces: '  padded  ',
    special: '*star',
  })
  assert.match(next, /\nplain: hello world\n/)
  assert.match(next, /\ncolon: "a: b"\n/)
  assert.match(next, /\nhash: "five # six"\n/)
  assert.match(next, /\nbool: true\n/)
  assert.match(next, /\nnum: 123\n/)
  assert.match(next, /\nnumString: "1\.2\.3"\n/)
  // YAML 1.1 readers treat bare yes/no as booleans — keep it a string
  assert.match(next, /\nyes: "yes"\n/)
  assert.match(next, /\nempty: ""\n/)
  assert.match(next, /\nspaces: "  padded  "\n/)
  assert.match(next, /\nspecial: "\*star"\n/)
})

test('applyYaml turns a scalar parent into a mapping when nesting below it', () => {
  const doc = 'a: 5\nb: 6\n'
  const next = applyYaml(doc, { 'a.child': 'x' })
  assert.equal(next, 'a:\n  child: x\nb: 6\n')
})

test('applyYaml leaves lists and block scalars alone', () => {
  const doc = 'motd: |\n  line: one\n  line: two\nworlds:\n  - alpha\n  - beta\nport: 1\n'
  const next = applyYaml(doc, { port: '2' })
  assert.equal(next, 'motd: |\n  line: one\n  line: two\nworlds:\n  - alpha\n  - beta\nport: 2\n')
})

test('applyYaml appends top-level keys to an empty or key-less document', () => {
  assert.equal(applyYaml('', { key: 'v' }), 'key: v\n')
  assert.equal(applyYaml('# only a comment\n', { key: 'v' }), '# only a comment\nkey: v\n')
})

test('applyYaml never throws on malformed input', () => {
  assert.doesNotThrow(() => applyYaml(':::\n\t{{{{\n- - -\n', { 'a.b': 'x' }))
  assert.doesNotThrow(() => applyYaml('"unclosed: quote\n', { a: 'x' }))
})

test('parseYaml parses a realistic document into a nested object', () => {
  const parsed = parseYaml(BUKKIT_STYLE)
  assert.deepEqual(parsed['spawn-limits'], { monsters: 70, animals: 10 })
  assert.equal((parsed.settings as Record<string, unknown>)['allow-end'], true)
  assert.equal((parsed.settings as Record<string, unknown>)['connection-throttle'], 4000)
  assert.equal(parsed.aliases, 'now-in-commands.yml')
  assert.deepEqual(parsed.worlds, ['world', 'world_nether'])
})

test('parseYaml coerces scalar types and handles quoted values', () => {
  const parsed = parseYaml('s: "123"\nn: 1.5\nb: false\nnothing: ~\nempty:\n')
  assert.equal(parsed.s, '123')
  assert.equal(parsed.n, 1.5)
  assert.equal(parsed.b, false)
  assert.equal(parsed.nothing, null)
  assert.deepEqual(parsed.empty, {})
})

test('parseYaml handles lists at the parent indent level', () => {
  const parsed = parseYaml('worlds:\n- one\n- two\nafter: 3\n')
  assert.deepEqual(parsed.worlds, ['one', 'two'])
  assert.equal(parsed.after, 3)
})

test('parseYaml never throws on garbage', () => {
  assert.doesNotThrow(() => parseYaml(']]]]\n\x00\x01\n:::'))
  assert.deepEqual(parseYaml(''), {})
})

test('parseYaml never pollutes Object.prototype via dangerous keys', () => {
  for (const doc of [
    '__proto__:\n  polluted: bad\n',
    'a:\n  __proto__:\n    polluted: bad\n',
    'constructor:\n  prototype:\n    polluted: bad\n',
    '__proto__: bad\n',
  ]) {
    parseYaml(doc)
    assert.equal(({} as Record<string, unknown>).polluted, undefined, `polluted via ${JSON.stringify(doc)}`)
    assert.equal(Object.prototype.hasOwnProperty('polluted'), false)
  }
  // a normal key sitting after a discarded __proto__ subtree still parses
  const parsed = parseYaml('__proto__:\n  x: 1\nreal: 2\n')
  assert.equal(parsed.real, 2)
})

test('applyYaml quotes leading-zero and lossy numbers so they survive a round-trip', () => {
  // Bare "007" would be read as octal by YAML 1.1 parsers (SnakeYAML) and
  // "3.0" would lose its trailing zero — keep such values quoted as strings.
  const next = applyYaml('head: 0\na: x\nb: x\nc: x\nd: x\n', { a: '08', b: '007', c: '3.0', d: '1.10' })
  assert.match(next, /\na: "08"\n/)
  assert.match(next, /\nb: "007"\n/)
  assert.match(next, /\nc: "3.0"\n/)
  assert.match(next, /\nd: "1.10"\n/)
  assert.equal(getYamlValue(next, 'a'), '08')
  assert.equal(getYamlValue(next, 'c'), '3.0')
  // canonical integers/decimals still land bare
  const bare = applyYaml('head: 0\nn: x\nf: x\nz: x\n', { n: '42', f: '3.14', z: '0' })
  assert.match(bare, /\nn: 42\n/)
  assert.match(bare, /\nf: 3\.14\n/)
  assert.match(bare, /\nz: 0\n/)
})
